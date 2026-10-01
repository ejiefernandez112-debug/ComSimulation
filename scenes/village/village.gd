extends Node2D
## Village View: the island, the camera, and everything standing on the island.
## Layers, back to front: IslandMap (sea and land) -> Grid (only in Placement Mode) -> Shadows ->
## Marker (ring under the selected building) -> Objects (buildings and trees, sorted so
## lower-on-screen covers higher) -> Cursor (placement preview, the "ghost").
## Works out WHAT was tapped and tells main.gd (signals); reads building positions from Economy and
## never stores game numbers itself.

## Placement Mode: the ghost moved (or the money changed). `check` = {"ok", "error"}: can the
## building go where the ghost is?
signal ghost_moved(check: Dictionary)
## Not placing: a building, a building's "ready to collect" bubble, or nothing was tapped.
signal building_tapped(building_id: String)
signal bubble_tapped(building_id: String)
signal empty_tapped

const IslandMap = preload("res://scenes/village/island_map.gd")
const VillageCamera = preload("res://scenes/village/village_camera.gd")
const BuildingView = preload("res://scenes/village/building_view.gd")
const TreeView = preload("res://scenes/village/tree_view.gd")
const ShadowLayer = preload("res://scenes/village/shadow_layer.gd")
const FloatingText = preload("res://scenes/village/floating_text.gd")

const OK_COLOR := Color(1, 1, 1, 0.35)
const BLOCKED_COLOR := Color(1, 0.25, 0.2, 0.45)
const GRID_LINE := Color(1, 1, 1, 0.22)
const GRID_EDGE := Color(1, 1, 1, 0.7)
const MARKER := Color(1.0, 0.95, 0.6)

@onready var island: IslandMap = $IslandMap
@onready var grid: Node2D = $Grid
@onready var shadows: ShadowLayer = $Shadows
@onready var marker: Node2D = $Marker
@onready var objects: Node2D = $Objects
@onready var cursor: Node2D = $Cursor
@onready var camera: VillageCamera = $Camera

var _views := {}  # building id -> its BuildingView
var _selected := ""  # id of the selected building, or ""
var _started := false  # buildings added after start-up drop in with an animation
## Building type being placed, or "" when not in Placement Mode.
var placing_type := ""
## When Placement Mode is moving an existing building (not building a new one): its id, else "".
var moving_id := ""
## Placement Mode: the tile the ghost stands on. ✓ puts the building here.
var ghost_cell := Vector2i.ZERO
var _grip := Vector2.ZERO  # finger -> ghost offset while dragging, so a grabbed ghost doesn't jump
var _ghost_before_press := Vector2i.ZERO  # put back if that finger turns out to start a pinch


func _ready() -> void:
	grid.draw.connect(_draw_grid)
	grid.hide()
	marker.draw.connect(_draw_marker)
	cursor.draw.connect(_draw_cursor)
	shadows.objects = objects
	_plant_trees()
	_sync_buildings()
	_started = true
	camera.bounds = island.world_bounds()
	camera.show_whole_island()
	camera.tapped.connect(_on_tapped)
	camera.finger_down.connect(_on_finger_down)
	camera.finger_moved.connect(_on_finger_moved)
	camera.finger_cancelled.connect(_on_finger_cancelled)
	Economy.changed.connect(_on_economy_changed)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_on_economy_changed()


func _on_economy_changed() -> void:
	_sync_buildings()
	for b in Economy.state.buildings:
		_views[b.id].refresh(b)  # "ready to collect" bubbles
	if placing_type != "":
		_ghost_changed()  # cash may have changed, so the ghost may turn red or green


## Placement Mode for a new building: show the grid and a see-through ghost of type_id on a free
## tile near the middle of the screen.
func start_placement(type_id: String) -> void:
	_begin_placement(type_id, _free_cell_near(Iso.to_cell(camera.position)))


## Placement Mode for an existing building: it fades where it stands and the ghost starts right on
## top of it, so the player sees both where it was and where it's going.
func start_moving(building_id: String) -> void:
	var b := Economy.building(building_id)
	if b.is_empty():
		return
	moving_id = building_id
	_views[building_id].modulate.a = 0.35
	_begin_placement(b.type, Vector2i(b.position[0], b.position[1]))


func stop_placement() -> void:
	if _views.has(moving_id):
		_views[moving_id].modulate.a = 1.0
	moving_id = ""
	placing_type = ""
	camera.placing = false
	grid.hide()
	cursor.queue_redraw()


## Can the building go where the ghost is? {"ok", "error"}
func ghost_check() -> Dictionary:
	return Economy.can_move(moving_id, ghost_cell) if moving_id != "" else Economy.can_build(placing_type, ghost_cell)


func _begin_placement(type_id: String, cell: Vector2i) -> void:
	placing_type = type_id
	ghost_cell = cell
	camera.placing = true
	grid.show()
	_ghost_changed()


func _ghost_changed() -> void:
	cursor.queue_redraw()
	ghost_moved.emit(ghost_check())


## The free building-area tile closest to `near` (or `near` itself if there is none).
func _free_cell_near(near: Vector2i) -> Vector2i:
	var best := near
	var best_dist := INF
	for x in island.plot_size.x:
		for y in island.plot_size.y:
			var cell := Vector2i(x, y)
			var dist := Vector2(cell - near).length()
			if dist < best_dist and Economy.building_at(cell).is_empty():
				best = cell
				best_dist = dist
	return best


## Placement Mode, finger down: on the ghost, grab it where it was touched; anywhere else, the
## ghost jumps under the finger.
func _on_finger_down(world_pos: Vector2) -> void:
	_ghost_before_press = ghost_cell
	var at := Iso.to_world(Vector2(ghost_cell))
	if BuildingView.preview_rect(placing_type, at).grow(8.0).has_point(world_pos):
		_grip = at - world_pos
	else:
		_grip = Vector2.ZERO
		_move_ghost(Iso.to_cell(world_pos))


func _on_finger_moved(world_pos: Vector2) -> void:
	_move_ghost(Iso.to_cell(world_pos + _grip))


## That finger was the start of a two-finger pan/zoom: undo the ghost's jump.
func _on_finger_cancelled() -> void:
	_move_ghost(_ghost_before_press)


## The ghost only stands on land, so it stops at the shore instead of sliding into the sea.
func _move_ghost(cell: Vector2i) -> void:
	if cell != ghost_cell and island.is_land(cell):
		ghost_cell = cell
		_ghost_changed()


func select(building_id: String) -> void:
	if _selected != "" and _views.has(_selected):
		_views[_selected].set_selected(false)
	_selected = building_id
	if _views.has(building_id):
		_views[building_id].set_selected(true)
	marker.queue_redraw()


func deselect() -> void:
	select("")


## Floating "+32 [flour]" numbers rising from a building (negative amounts show in red).
func show_gain(building_id: String, amounts: Dictionary) -> void:
	var view: Node2D = _views.get(building_id)
	if view == null:
		return
	var i := 0
	for res in amounts:
		var qty := int(amounts[res])
		var label := FloatingText.new()
		label.text = ("+%s" if qty >= 0 else "%s") % UITheme.number(qty)
		label.icon = UITheme.icon(res)
		label.color = UITheme.GOOD if qty >= 0 else UITheme.BAD
		label.position = view.position + Vector2(0, -view.top_height() - 10 - 30 * i)
		add_child(label)
		i += 1


## Gives every building in the game state a view on the map, removes views of demolished ones,
## and follows buildings that moved.
func _sync_buildings() -> void:
	var alive := {}
	for b in Economy.state.buildings:
		alive[b.id] = true
	for id in _views.keys():
		if not alive.has(id):
			_remove_view(id)
	for b in Economy.state.buildings:
		if _views.has(b.id):
			var at := Iso.to_world(Vector2(b.position[0], b.position[1]))
			if _views[b.id].position != at:
				_views[b.id].position = at
				_views[b.id].pop_in()
				shadows.queue_redraw()
				marker.queue_redraw()
			continue
		var view := BuildingView.new()
		view.type_id = b.type
		view.building_id = b.id
		view.position = Iso.to_world(Vector2(b.position[0], b.position[1]))
		objects.add_child(view)
		_views[b.id] = view
		if _started:
			view.pop_in()
		shadows.queue_redraw()


## A demolished building squashes down into the ground, then disappears.
func _remove_view(id: String) -> void:
	var view: Node2D = _views[id]
	_views.erase(id)
	if _selected == id:
		deselect()
	var squash := view.create_tween().set_parallel()
	squash.tween_property(view, "scale", Vector2(1.3, 0.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	squash.tween_property(view, "modulate:a", 0.0, 0.3)
	squash.chain().tween_callback(func():
		objects.remove_child(view)
		view.queue_free()
		shadows.queue_redraw())


func _plant_trees() -> void:
	for spot in island.tree_spots():
		var tree := TreeView.new()
		tree.position = spot.position
		tree.pine = spot.pine
		tree.size = spot.size
		objects.add_child(tree)


func _apply_settings() -> void:
	BuildingView.show_names = Settings.get_value("building_names")
	for view in _views.values():
		view.queue_redraw()
	island.material.set_shader_parameter("detail", Settings.get_value("water_detail"))


## A tap outside Placement Mode (in Placement Mode the camera sends finger_* signals instead).
func _on_tapped(world_pos: Vector2) -> void:
	var cell := Iso.to_cell(world_pos)
	# Bubbles float on top of everything, so they win; then the front-most building picture.
	for id in _views:
		if _views[id].hits_bubble(world_pos):
			bubble_tapped.emit(id)
			return
	var front_first := _views.values()
	front_first.sort_custom(func(a, b): return a.position.y > b.position.y)
	for view in front_first:
		if view.hits(world_pos):
			building_tapped.emit(view.building_id)
			return
	var on_tile := Economy.building_at(cell)  # e.g. tapped the ground right at its foot
	if not on_tile.is_empty():
		building_tapped.emit(on_tile.id)
	else:
		empty_tapped.emit()


## A glowing ring on the ground around the selected building's tile.
func _draw_marker() -> void:
	if _selected == "" or not _views.has(_selected):
		return
	var at: Vector2 = _views[_selected].position
	var half := Vector2(Iso.TILE_W, Iso.TILE_H) * 0.62  # a little bigger than the tile
	var ring := PackedVector2Array([at + Vector2(0, -half.y), at + Vector2(half.x, 0),
		at + Vector2(0, half.y), at + Vector2(-half.x, 0), at + Vector2(0, -half.y)])
	marker.draw_polyline(ring, Color(MARKER, 0.35), 9.0, true)
	marker.draw_polyline(ring, MARKER, 3.0, true)


## The plot's tile lines, like Clash of Clans shows while you move a building.
func _draw_grid() -> void:
	var size := island.plot_size
	for x in range(1, size.x):
		grid.draw_line(Iso.to_world(Vector2(x - 0.5, -0.5)), Iso.to_world(Vector2(x - 0.5, size.y - 0.5)), GRID_LINE, 1.0, true)
	for y in range(1, size.y):
		grid.draw_line(Iso.to_world(Vector2(-0.5, y - 0.5)), Iso.to_world(Vector2(size.x - 0.5, y - 0.5)), GRID_LINE, 1.0, true)
	var corners := PackedVector2Array([
		Iso.to_world(Vector2(-0.5, -0.5)),
		Iso.to_world(Vector2(size.x - 0.5, -0.5)),
		Iso.to_world(Vector2(size.x - 0.5, size.y - 0.5)),
		Iso.to_world(Vector2(-0.5, size.y - 0.5)),
		Iso.to_world(Vector2(-0.5, -0.5)),
	])
	grid.draw_polyline(corners, GRID_EDGE, 2.0, true)


## The ghost: a green (free) or red (blocked) tile with a see-through picture of the building.
func _draw_cursor() -> void:
	if placing_type == "":
		return
	var free: bool = ghost_check().ok
	var diamond := Iso.diamond(ghost_cell)
	cursor.draw_colored_polygon(diamond, OK_COLOR if free else BLOCKED_COLOR)
	cursor.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color.WHITE, 2.0, true)
	var tint := Color(1, 1, 1, 0.6) if free else Color(1, 0.4, 0.4, 0.6)
	BuildingView.draw_preview(cursor, Iso.to_world(Vector2(ghost_cell)), placing_type, tint)
