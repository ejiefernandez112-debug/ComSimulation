extends Node2D
## How one building looks on the map: its picture from assets/buildings/ (made by the sprite studio,
## tools/sprite_studio.gd) when there is one, otherwise a PLACEHOLDER shaded box. Sits at the centre
## of the building's tile; the Objects layer sorts it by how low on screen it is, so nearer things
## cover farther ones. Also shows a bubble when goods are ready to collect, a bounce and glow when
## selected, and its name when the "Building names" setting is on. Holds no game numbers.

const SPRITES := "res://assets/buildings/"
const HEIGHT := 30.0  # placeholder box height
const FOOTPRINT := 0.74  # placeholder box size, in tiles: it stands on its plot, lawn showing around it
const BUBBLE_RADIUS := 17.0
const CONSTRUCTION_TINT := Color(1, 1, 1, 0.45)
const SUSPENDED_TINT := Color(0.55, 0.55, 0.62)  # greyed: switched off by the player
const BUILD_BAR_SIZE := Vector2(60, 10)
const CATEGORY_COLORS := {
	"civic": Color("8a8fa8"),
	"residential": Color("c98b5e"),
	"extractor": Color("d6b84a"),
	"processor": Color("9c7bb5"),
	"storage": Color("7aa0b8"),
	"utility": Color("5fb3c9"),
	"service": Color("7fae8f"),
	"construction": Color("e0a43a"),
	"power": Color("f2c94c"),
	"retail": Color("6fb07f"),
	"trade": Color("c46a5a"),
}

static var show_names := false
static var _manifest := {}  # what the sprite studio wrote: which pictures exist, and their anchors
static var _hit_images := {}  # building type -> Image, to check whether a tap landed on the picture
static var _pictures := {}  # building type -> picture(): worked out once, it's asked for often

var type_id := ""
var building_id := ""
var _sprite: Sprite2D
var _bubble := Node2D.new()
var _bubble_icon: Texture2D
var _bob: Tween
var _glow: Tween
# Construction: while it's being built the building is faded, with a progress bar and time left
# above it. Only buildings under construction do per-frame work (_process), to move that bar.
var _b := {}
var _constructing := false
var _suspended := false
var _build_bar := Node2D.new()
var _no_road := Node2D.new()  # a red sign: no road (plan.md §5.20) or no power (§5.5)
var _sign_icon := "road"  # what the red sign shows: "road" or "power"


func _ready() -> void:
	set_process(false)
	_build_bar.z_index = 5
	_build_bar.visible = false
	_build_bar.position = Vector2(0, -top_height() - 16)
	_build_bar.draw.connect(_draw_build_bar)
	add_child(_build_bar)
	var art := picture(type_id)
	if not art.is_empty():
		_sprite = Sprite2D.new()
		_sprite.texture = art.texture
		_sprite.centered = false
		_sprite.offset = -art.anchor  # puts the footprint's centre (the anchor) on this node
		_sprite.scale = Vector2.ONE * art.scale
		_sprite.show_behind_parent = true  # keeps the name label drawn on top
		add_child(_sprite)
	# The bubble floats above every building (z_index), bobbing gently.
	_bubble.z_index = 5
	_bubble.visible = false
	_bubble.position = Vector2(0, -top_height() - 24)
	_bubble.draw.connect(_draw_bubble)
	add_child(_bubble)
	_no_road.z_index = 5
	_no_road.visible = false
	_no_road.draw.connect(_draw_no_road)
	add_child(_no_road)


func _draw() -> void:
	if not _sprite:
		draw_block(self, Vector2.ZERO, type_id, _tint())
	if show_names:
		draw_name(self, Vector2.ZERO, type_id, 1.0)


func _process(_delta: float) -> void:
	if Economy.is_built(_b):
		refresh(_b)  # finished: switch to the normal look right away, not at the next tick
	else:
		_build_bar.queue_redraw()


## Keeps the bubble and the construction look up to date (the village calls this every tick).
func refresh(b: Dictionary) -> void:
	_b = b
	var constructing := not Economy.is_built(b)
	var suspended := Economy.is_suspended(b)
	if constructing != _constructing or suspended != _suspended:
		var finished := _constructing and not constructing
		_constructing = constructing
		_suspended = suspended
		set_process(constructing)
		_build_bar.visible = constructing
		if _sprite:
			_sprite.modulate = _tint()
		queue_redraw()
		if finished:
			pop_in()  # construction done
	# A batch's finished hours wait in the building (plan.md §5.1): the bubble appears once the
	# first hour is done and stays until they are collected.
	var waiting := Economy.waiting_goods(b)
	var has_goods: bool = not waiting.is_empty()
	# No road comes first (without workers nothing works anyway); a home without power gets no
	# sign, because nothing happens to it yet.
	var sign := ""
	if not constructing and not Economy.on_road(b):
		sign = "road"
	elif not constructing and Economy.power_problem(b) != "" and GameData.buildings[b.type].category != "residential":
		sign = "power"
	_no_road.visible = sign != ""
	if sign != "" and sign != _sign_icon:
		_sign_icon = sign
		_no_road.queue_redraw()
	_no_road.position = Vector2(26 if has_goods else 0, -top_height() - 20)  # beside a bubble
	if has_goods:
		var icon := UITheme.icon(waiting.keys()[0])
		if icon != _bubble_icon:
			_bubble_icon = icon
			_bubble.queue_redraw()
	if has_goods == _bubble.visible:
		return
	_bubble.visible = has_goods
	if _bob:
		_bob.kill()  # only bob while there is a bubble to see
		_bob = null
	if has_goods:
		var rest := -top_height() - 24
		_bubble.position.y = rest
		_bubble.scale = Vector2(0.3, 0.3)
		create_tween().tween_property(_bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_bob = create_tween().set_loops()
		_bob.tween_property(_bubble, "position:y", rest - 5, 0.6).set_trans(Tween.TRANS_SINE)
		_bob.tween_property(_bubble, "position:y", rest, 0.6).set_trans(Tween.TRANS_SINE)


## Faded while being built, greyed while suspended.
func _tint() -> Color:
	if _constructing:
		return CONSTRUCTION_TINT
	return SUSPENDED_TINT if _suspended else Color.WHITE


## Selected: a quick bounce, then a soft glow pulsing until deselected.
func set_selected(on: bool) -> void:
	var target: CanvasItem = _sprite if _sprite else self
	if _glow:
		_glow.kill()
		_glow = null
	target.self_modulate = Color.WHITE
	if not on:
		return
	var bounce := create_tween()
	bounce.tween_property(self, "scale", Vector2(1.08, 0.94), 0.08)
	bounce.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_glow = create_tween().set_loops()
	_glow.tween_property(target, "self_modulate", Color(1.25, 1.25, 1.2), 0.5).set_trans(Tween.TRANS_SINE)
	_glow.tween_property(target, "self_modulate", Color.WHITE, 0.5).set_trans(Tween.TRANS_SINE)


## A just-built building drops into place.
func pop_in() -> void:
	scale = Vector2(0.6, 1.3)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Did a tap at this world point land on the building's picture (not on its shadow)?
func hits(world: Vector2) -> bool:
	var local := world - position
	var art := picture(type_id)
	if art.is_empty():
		var base := _footprint(Vector2.ZERO, 0.0, Economy.size_of(type_id))
		var top := _footprint(Vector2.ZERO, HEIGHT, Economy.size_of(type_id))
		return Geometry2D.is_point_in_polygon(local, PackedVector2Array([top[0], top[1], base[1], base[2], base[3], top[3]]))
	if not _hit_images.has(type_id):
		var image: Image = art.texture.get_image()
		if image.is_compressed():
			image.decompress()
		_hit_images[type_id] = image
	var img: Image = _hit_images[type_id]
	var p: Vector2 = local / art.scale + art.anchor
	if not Rect2(Vector2.ZERO, img.get_size()).has_point(p):
		return false
	return img.get_pixelv(Vector2i(p)).a > 0.6  # baked shadows are fainter than this


func hits_bubble(world: Vector2) -> bool:
	return _bubble.visible and world.distance_to(position + _bubble.position) < BUBBLE_RADIUS + 8.0


## How far the building reaches above its position (to place bubbles, names and effects).
func top_height() -> float:
	var art := picture(type_id)
	return art.anchor.y * art.scale if not art.is_empty() else HEIGHT + Iso.TILE_H / 2.0


## Shadow on the ground, falling away from the sun. Called by the village's Shadows layer.
## Pictures from the sprite studio already include their shadow.
func draw_shadow(layer: Node2D) -> void:
	if picture(type_id).is_empty():
		layer.cast(_footprint(position, 0.0, Economy.size_of(type_id)), HEIGHT)


func _draw_bubble() -> void:
	var r := BUBBLE_RADIUS
	_bubble.draw_colored_polygon(PackedVector2Array([Vector2(-7, r - 4), Vector2(7, r - 4), Vector2(0, r + 9)]), UITheme.OUTLINE)
	_bubble.draw_circle(Vector2.ZERO, r + 3.0, UITheme.OUTLINE, true, -1.0, true)
	_bubble.draw_colored_polygon(PackedVector2Array([Vector2(-4.5, r - 3), Vector2(4.5, r - 3), Vector2(0, r + 4.5)]), Color("fffdf4"))
	_bubble.draw_circle(Vector2.ZERO, r, Color("fffdf4"), true, -1.0, true)
	if _bubble_icon:
		_bubble.draw_texture_rect(_bubble_icon, Rect2(-r * 0.78, -r * 0.8, r * 1.56, r * 1.56), false)


## A round red sign with a road (or a lightning bolt) on it, and a bar across: "no road here" /
## "no power here".
func _draw_no_road() -> void:
	var r := 12.0
	_no_road.draw_circle(Vector2.ZERO, r + 2.5, UITheme.OUTLINE, true, -1.0, true)
	_no_road.draw_circle(Vector2.ZERO, r, Color("d8452f"), true, -1.0, true)
	_no_road.draw_circle(Vector2.ZERO, r - 3.5, Color("1b2430"), true, -1.0, true)  # dark, for the white icon
	_no_road.draw_texture_rect(UITheme.icon(_sign_icon), Rect2(-6.5, -6.5, 13, 13), false)
	_no_road.draw_line(Vector2(-6.5, -6.5), Vector2(6.5, 6.5), Color("d8452f"), 2.6, true)


## Construction progress bar with the time left written above it.
func _draw_build_bar() -> void:
	if _b.is_empty():
		return
	var rect := Rect2(-BUILD_BAR_SIZE / 2.0, BUILD_BAR_SIZE)
	_build_bar.draw_rect(rect.grow(2.0), UITheme.OUTLINE)
	_build_bar.draw_rect(rect, Color("3a2c1c"))
	var fill := rect
	fill.size.x *= Economy.construction_progress(_b)
	_build_bar.draw_rect(fill, Color("ffd166"))
	var text := UITheme.duration(Economy.construction_left(_b))
	var pos := Vector2(-40, -8)
	_build_bar.draw_string_outline(UITheme.font(), pos, text, HORIZONTAL_ALIGNMENT_CENTER, 80, 15, 5, UITheme.OUTLINE)
	_build_bar.draw_string(UITheme.font(), pos, text, HORIZONTAL_ALIGNMENT_CENTER, 80, 15, UITheme.TEXT)


## The see-through preview in Placement Mode, centred on `at`.
static func draw_preview(canvas: CanvasItem, at: Vector2, type_id: String, tint: Color) -> void:
	var art := picture(type_id)
	if art.is_empty():
		draw_block(canvas, at, type_id, tint)
	else:
		var size: Vector2 = art.texture.get_size() * art.scale
		canvas.draw_texture_rect(art.texture, Rect2(at - art.anchor * art.scale, size), false, tint)
	draw_name(canvas, at, type_id, tint.a)


## The rectangle the Placement Mode preview covers when centred on `at` (world units). Used to tell
## whether a finger grabbed the ghost; a rectangle is generous on purpose, as fingers are big.
static func preview_rect(type_id: String, at: Vector2) -> Rect2:
	var art := picture(type_id)
	if art.is_empty():
		var tile := Vector2(Iso.TILE_W, Iso.TILE_H) * Economy.size_of(type_id)
		return Rect2(at - Vector2(tile.x / 2.0, tile.y / 2.0 + HEIGHT), tile + Vector2(0, HEIGHT))
	return Rect2(at - art.anchor * art.scale, art.texture.get_size() * art.scale)


## The building's picture as {"texture", "anchor" (footprint centre, in picture pixels), "scale"},
## or {} if the sprite studio hasn't made one for this building type. Read it; don't change it.
static func picture(type_id: String) -> Dictionary:
	if _pictures.has(type_id):
		return _pictures[type_id]
	if _manifest.is_empty() and FileAccess.file_exists(SPRITES + "sprites.json"):
		_manifest = GameData.load_json(SPRITES + "sprites.json")
	var entry: Dictionary = _manifest.get("sprites", {}).get(type_id, {})
	var art := {}
	if not entry.is_empty():
		art = {
			"texture": load(SPRITES + type_id + ".png"),
			"anchor": Vector2(entry.anchor[0], entry.anchor[1]),
			"scale": Iso.TILE_W / float(_manifest.pixels_per_tile),
		}
	_pictures[type_id] = art
	return art


## The building's name, just above its top, in the game's outlined font.
static func draw_name(canvas: CanvasItem, at: Vector2, type_id: String, alpha: float) -> void:
	var art := picture(type_id)
	var top: float = at.y - (art.anchor.y * art.scale if not art.is_empty() else HEIGHT + Iso.TILE_H / 2.0)
	var def: Dictionary = GameData.buildings[type_id]
	var pos := Vector2(at.x - 70, top - 6)
	canvas.draw_string_outline(UITheme.font(), pos, def.name, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, 5, Color(UITheme.OUTLINE, alpha))
	canvas.draw_string(UITheme.font(), pos, def.name, HORIZONTAL_ALIGNMENT_CENTER, 140, 14, Color(1, 1, 1, alpha))


## The placeholder box's outline on the ground (raised by `lift`): the diamond of its `size` x
## `size` tiles, a bit smaller.
static func _footprint(at: Vector2, lift := 0.0, size := 1) -> PackedVector2Array:
	var points := Iso.diamond_at(Vector2.ZERO)
	for i in points.size():
		points[i] = at + points[i] * (size - 1.0 + FOOTPRINT) - Vector2(0, lift)
	return points


## PLACEHOLDER box, centred on `at`, for buildings that have no picture yet.
static func draw_block(canvas: CanvasItem, at: Vector2, type_id: String, tint: Color) -> void:
	var def: Dictionary = GameData.buildings[type_id]
	var color: Color = CATEGORY_COLORS.get(def.category, Color.GRAY) * tint
	var base := _footprint(at, 0.0, Economy.size_of(type_id))
	var top := _footprint(at, HEIGHT, Economy.size_of(type_id))
	# Sun from the upper left: the left wall is half-lit, the right wall faces away.
	var left := PackedVector2Array([top[3], top[2], base[2], base[3]])
	var right := PackedVector2Array([top[2], top[1], base[1], base[2]])
	canvas.draw_colored_polygon(left, color.darkened(0.2))
	canvas.draw_colored_polygon(right, color.darkened(0.42))
	canvas.draw_colored_polygon(top, color.lightened(0.08))
	# Thin smooth outlines hide jagged edges and give a crisp cartoon look.
	var edge := color.darkened(0.6)
	canvas.draw_polyline(PackedVector2Array([top[0], top[1], base[1], base[2], base[3], top[3], top[0]]), edge, 1.0, true)
	canvas.draw_polyline(PackedVector2Array([top[3], top[2], top[1]]), color.lightened(0.35), 1.0, true)
	canvas.draw_line(top[2], base[2], edge.lightened(0.15), 1.0, true)
