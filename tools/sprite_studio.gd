extends SceneTree
## SPRITE STUDIO (plan.md §4 pipeline): "photographs" 3D models into 2D building sprites, using the
## game's exact camera angle and sun, so every picture matches the map. A developer tool only: the
## game never loads this file.
##
## Make the building sprites listed in tools/sprite_studio.json (writes assets/buildings/):
##   "C:\Program Files\Godot\Godot.exe.exe" --path . --rendering-method forward_plus -s tools/sprite_studio.gd
## Remake only some of them (the others and their sprites.json entries stay as they are):
##   ... -s tools/sprite_studio.gd -- only wind_turbine flour_mill
## A building whose entry has a "spin" (a part that turns: a turbine's rotor, a mill's sails) also
## gets <id>_base.png and <id>_spin.png, see _spin_photos().
## Make a contact sheet of every model in the kit (or in another folder, e.g. art/models), to choose from:
##   ... -s tools/sprite_studio.gd -- sheet <output.png> [folder]
##
## It needs a real graphics card (not --headless). forward_plus is the high-quality renderer; the game
## itself keeps the lighter Compatibility renderer, since it only shows the finished pictures.

const CONFIG_PATH := "res://tools/sprite_studio.json"
## Sprite pixels across one tile. The game's tile is Iso.TILE_W (64) wide, so this is 2x: sharp when zoomed in.
const PX_PER_TILE := 128.0
const CANVAS := Vector2i(512, 640)  # size of each photo, in pixels
const ANCHOR := Vector2(256, 480)  # where the centre of the building's footprint lands in the photo
const FILL := 0.92  # how much of its tile(s) a building covers, so neighbours don't touch
const SHEET_COLUMNS := 7
## Baked shadow colour at its darkest; same blue-black as the map's shadows (scenes/village/shadow_layer.gd).
const SHADOW := Color(0.03, 0.08, 0.12, 0.45)
const AMBIENT := 0.45  # strength of the bluish sky light that fills in shaded walls
const SPIN_NOISE := 3  # a pixel counts as changed by a turning part when a colour differs by more than this (of 255)
const SPIN_PAD := 4  # see-through border around each picture in a spin sheet, so neighbours don't bleed in when shrunk

var _viewport: SubViewport
var _camera: Camera3D
var _environment: Environment
var _floor: MeshInstance3D  # only visible while photographing the shadow
var _stand: Node3D  # the model being photographed is placed on this
var _caption: Label3D
var _last_shadow: Image  # the shadow photo of the last _photograph()


func _initialize() -> void:
	_build_studio()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "sheet":
		_make_sheet.call_deferred(args[1], args[2] if args.size() >= 3 else "")
	else:
		_make_sprites.call_deferred(args.slice(1) if args.size() >= 2 and args[0] == "only" else [])


# --- The two jobs ---

## `only` = building ids to remake (empty = all of them).
func _make_sprites(only: Array) -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var out_folder: String = "res://" + config.output_folder
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_folder))
	var manifest := {"_note": "Written by tools/sprite_studio.gd - do not edit by hand.", "pixels_per_tile": PX_PER_TILE, "sprites": {}}
	var manifest_path := out_folder.path_join("sprites.json")
	if not only.is_empty() and FileAccess.file_exists(manifest_path):
		manifest.sprites = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)).sprites  # keep the others
	# How many tiles wide each building stands: its "size" in data/buildings.json (1 if none).
	var buildings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/buildings.json"))
	for building_id in config.buildings:
		if not only.is_empty() and building_id not in only:
			continue
		var entry: Dictionary = config.buildings[building_id]
		var tiles := int(entry.get("tiles", buildings.get(building_id, {}).get("size", 1)))
		var photo := await _photograph(_kit_path(config, entry), int(entry.get("turn", 0)), tiles, "")
		if photo.is_empty():
			continue
		var crop := photo.get_used_rect()
		var sprite := photo.get_region(crop)
		sprite.save_png(ProjectSettings.globalize_path(out_folder.path_join(building_id + ".png")))
		var anchor := ANCHOR - Vector2(crop.position)
		manifest.sprites[building_id] = {"anchor": [anchor.x, anchor.y], "model": entry.model}
		print("Sprite studio: %s <- %s (%dx%d px)" % [building_id, entry.model, crop.size.x, crop.size.y])
		if entry.has("spin"):
			var spin := await _spin_photos(building_id, entry.spin, crop, out_folder)
			if not spin.is_empty():
				manifest.sprites[building_id]["spin"] = spin
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	quit()


## `kit_folder` = the folder to show ("" = the kit_folder in sprite_studio.json).
func _make_sheet(out_path: String, kit_folder: String) -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	var folder := ProjectSettings.globalize_path("res://" + (kit_folder if kit_folder != "" else String(config.kit_folder)))
	var models := Array(DirAccess.get_files_at(folder)).filter(func(f: String): return f.ends_with(".glb"))
	var cell := CANVAS / 2
	var rows := ceili(models.size() / float(SHEET_COLUMNS))
	var sheet := Image.create_empty(cell.x * SHEET_COLUMNS, cell.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("6a9f45"))
	for i in models.size():
		var photo := await _photograph(folder.path_join(models[i]), 0, 1, models[i].get_basename())
		if photo.is_empty():
			continue
		photo.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(photo, Rect2i(Vector2i.ZERO, cell), Vector2i(i % SHEET_COLUMNS, i / SHEET_COLUMNS) * cell)
	sheet.save_png(out_path)
	print("Sprite studio: contact sheet of %d models -> %s" % [models.size(), out_path])
	quit()


# --- The studio itself ---

## A transparent picture of one model standing on `tiles` x `tiles` tiles, turned `turn` quarter turns.
## `caption` (contact sheet only) is written under it. Returns an empty Image if the model won't load.
func _photograph(model_path: String, turn: int, tiles: int, caption: String) -> Image:
	for old in _stand.get_children():
		old.free()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(model_path, state) != OK:
		push_error("Sprite studio: could not load " + model_path)
		return Image.new()
	var model: Node3D = doc.generate_scene(state)
	_stand.add_child(model)
	_stand.transform = Transform3D.IDENTITY
	_stand.rotation.y = turn * PI / 2.0

	# Scale the model to fit its tiles, centred on the footprint and standing on the ground.
	var box := _bounds(model)
	var s := tiles * FILL / maxf(box.size.x, box.size.z)
	_stand.scale = Vector3.ONE * s
	_stand.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s

	_caption.text = caption

	# Two photos: the building on its own, then only its shadow falling on a white floor.
	var building := await _snap()
	_shadow_pass(true)
	_last_shadow = await _snap()
	_shadow_pass(false)
	return _combine(building, _last_shadow)


## A building with a part that turns in the game ("spin" in sprite_studio.json: "part" = the
## model's part, e.g. "rotor"; it turns around that part's own X axis, see art/blender/kit.py).
## Besides the normal picture (the part at rest) it gets two more, for the game to put together:
## - <id>_base.png: the same picture without the part (same size and anchor),
## - <id>_spin.png: a sheet of the part at `frames` angles, each turned `repeat_degrees` / `frames`
##   further (a 3-bladed rotor looks the same again after 120°). Only the pixels the part changes
##   are kept (the part, and its shadow on the building), so the sheet stays small. Its shadow on
##   the ground stays as in the normal picture: with the sun beside it, it is only a thin line.
## Returns what the game needs (sprites.json "spin"): the number of frames, the sheet's grid, where
## the sheet's top-left corner sits in the normal picture, and seconds per frame.
## Call it right after _photograph() of that building (the model is still on the stand).
func _spin_photos(building_id: String, spin: Dictionary, crop: Rect2i, out_folder: String) -> Dictionary:
	var part := _stand.find_child(String(spin.part), true, false) as Node3D
	if part == null:
		push_error("Sprite studio: %s's model has no part called \"%s\"" % [building_id, spin.part])
		return {}
	var frames := int(spin.frames)
	var step := deg_to_rad(float(spin.repeat_degrees) / frames)
	if spin.get("clockwise", true):
		step = -step  # its axle points at the camera, and a positive turn looks anticlockwise from there
	var rest := part.transform
	part.visible = false
	var bare := await _snap()
	_combine(bare, _last_shadow).get_region(crop).save_png(ProjectSettings.globalize_path(out_folder.path_join(building_id + "_base.png")))
	part.visible = true
	var layers: Array[Image] = []
	var used := Rect2i()
	for k in frames:
		part.transform = rest.rotated_local(Vector3.RIGHT, step * k)
		var layer := _changed(await _snap(), bare)
		layers.append(layer)
		var area := layer.get_used_rect()
		if area.has_area():
			used = area if not used.has_area() else used.merge(area)
	part.transform = rest
	var columns := ceili(sqrt(frames))
	var rows := ceili(frames / float(columns))
	var pad := Vector2i(SPIN_PAD, SPIN_PAD)
	var cell := used.size + pad * 2
	var sheet := Image.create_empty(cell.x * columns, cell.y * rows, false, Image.FORMAT_RGBA8)
	for k in frames:
		sheet.blit_rect(layers[k], used, Vector2i(k % columns, k / columns) * cell + pad)
	sheet.save_png(ProjectSettings.globalize_path(out_folder.path_join(building_id + "_spin.png")))
	var at := used.position - crop.position - pad
	print("Sprite studio: %s turns: %d frames of %dx%d px" % [building_id, frames, cell.x, cell.y])
	return {
		"frames": frames, "columns": columns, "rows": rows, "at": [at.x, at.y],
		"seconds_per_frame": float(spin.seconds_per_turn) * float(spin.repeat_degrees) / frames / 360.0,
	}


## The pixels of `photo` that differ from `bare`; everything else see-through.
func _changed(photo: Image, bare: Image) -> Image:
	var a := photo.get_data()
	var b := bare.get_data()
	var out := PackedByteArray()
	out.resize(a.size())  # all zero: see-through
	for i in range(0, a.size(), 4):
		if absi(a[i] - b[i]) > SPIN_NOISE or absi(a[i + 1] - b[i + 1]) > SPIN_NOISE \
				or absi(a[i + 2] - b[i + 2]) > SPIN_NOISE or absi(a[i + 3] - b[i + 3]) > SPIN_NOISE:
			for c in 4:
				out[i + c] = a[i + c]
	return Image.create_from_data(photo.get_width(), photo.get_height(), false, Image.FORMAT_RGBA8, out)


## Gives the renderer a few frames (shadows and shading settle), then takes the picture.
func _snap() -> Image:
	for i in 3:
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


## Shadow photo: the floor appears, the building turns invisible but still casts its shadow, and
## the sky light is switched off so the floor is either sunlit or in shadow, nothing in between.
func _shadow_pass(on: bool) -> void:
	_floor.visible = on
	_caption.visible = not on
	_environment.ambient_light_energy = 0.0 if on else AMBIENT
	for mesh: MeshInstance3D in _stand.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Turns the shadow photo into a see-through shadow (how much darker than sunlit floor each pixel
## is), then lays the building on top.
func _combine(building: Image, shadow: Image) -> Image:
	var sunlit := 0.0
	for x in shadow.get_width():  # the top row is never in shadow (shadows fall right and down)
		sunlit = maxf(sunlit, shadow.get_pixel(x, 0).get_luminance())
	var out := Image.create_empty(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	for y in CANVAS.y:
		for x in CANVAS.x:
			var dark := 1.0 - shadow.get_pixel(x, y).get_luminance() / sunlit
			dark = clampf((dark - 0.12) / 0.8, 0.0, 1.0)  # ignore faint speckle the renderer leaves on sunlit floor
			if dark > 0.0:
				out.set_pixel(x, y, Color(SHADOW, SHADOW.a * dark))
	out.blend_rect(building, Rect2i(Vector2i.ZERO, CANVAS), Vector2i.ZERO)
	return out


## Box around every mesh in the model, in world space.
func _bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var part := mesh.global_transform * mesh.get_aabb()
		if not mesh.global_basis.orthonormalized().is_equal_approx(Basis.IDENTITY):
			part = _turned_bounds(mesh)  # a turned part (a rotor on its pivot): a box around a turned box is too big
		box = part if first else box.merge(part)
		first = false
	return box


## Box around a turned part's corners, in world space.
func _turned_bounds(mesh: MeshInstance3D) -> AABB:
	var corners := mesh.mesh.get_faces()
	var box := AABB(mesh.global_transform * corners[0], Vector3.ZERO)
	for corner in corners:
		box = box.expand(mesh.global_transform * corner)
	return box


## A building's model file: in its own "kit_folder" if it names one (e.g. our Blender models in
## art/models), otherwise in the shared kit_folder.
func _kit_path(config: Dictionary, entry: Dictionary) -> String:
	var folder: String = entry.get("kit_folder", config.kit_folder)
	return ProjectSettings.globalize_path("res://" + folder).path_join(entry.model)


func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.size = CANVAS
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_8X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)

	# Camera: the game's 2:1 isometric view. One tile (1 x 1 metre) becomes PX_PER_TILE pixels wide.
	var px_per_metre := PX_PER_TILE / sqrt(2.0)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CANVAS.y / px_per_metre
	_camera.rotation_degrees = Vector3(-30, 45, 0)
	# A short view range: with the default (4 km) Godot draws no sun shadows for this kind of camera.
	_camera.near = 1.0
	_camera.far = 30.0
	_viewport.add_child(_camera)
	var lift := (ANCHOR.y - CANVAS.y / 2.0) / px_per_metre  # aim above the footprint so it lands on ANCHOR
	_camera.position = _camera.basis.y * lift + _camera.basis.z * 10.0
	RenderingServer.directional_shadow_atlas_set_size(8192, true)  # sharp, smooth shadows
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)

	# Sun: the same direction as Iso.SHADOW (upper left of the screen), high enough that shadows
	# are as long as the game draws them.
	var toward_sun := -Iso.to_cell_f(Iso.SHADOW).normalized()  # grid x -> world X, grid y -> world Z
	var height := deg_to_rad(51.0)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.light_angular_distance = 1.5  # slightly soft shadow edges
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 25.0  # measured from the camera, which stands 10 m back
	_viewport.add_child(sun)
	var sun_from := Vector3(toward_sun.x * cos(height), sin(height), toward_sun.y * cos(height))
	sun.look_at_from_position(sun_from * 10.0, Vector3.ZERO)

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_CLEAR_COLOR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.75, 0.85, 1.0)  # bluish sky light fills the shadows
	_environment.ambient_light_energy = AMBIENT
	_environment.ssao_enabled = true  # soft darkening in corners and where things meet
	_environment.ssao_radius = 0.4
	_environment.ssao_intensity = 1.5
	var world := WorldEnvironment.new()
	world.environment = _environment
	_viewport.add_child(world)

	# Plain floor, used only for the shadow photo (see _shadow_pass).
	_floor = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	_floor.mesh = plane
	var matte := StandardMaterial3D.new()
	matte.albedo_color = Color(0.5, 0.5, 0.5)  # mid grey, so sunlit floor never clips to pure white
	matte.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_floor.material_override = matte
	_floor.visible = false
	_viewport.add_child(_floor)

	_stand = Node3D.new()
	_viewport.add_child(_stand)

	_caption = Label3D.new()  # model names on the contact sheet
	_caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_caption.no_depth_test = true
	_caption.font_size = 40
	_caption.outline_size = 12
	_caption.pixel_size = 0.006
	_caption.position = -_camera.basis.y * 0.65  # just below the footprint on screen
	_viewport.add_child(_caption)
