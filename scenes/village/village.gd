extends Node2D
## Village View: the island, the camera, and everything standing on the island.
## Layers, back to front: IslandMap (sea and land) -> Roads -> Grid (only in Placement Mode) ->
## Shadows -> Marker (ring under the selected building) -> Objects (buildings, trees, and the
## people and cars of Traffic, sorted so lower-on-screen covers higher) -> Cursor (placement
## preview, the "ghost", or the road being drawn in Road Mode).
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
const NEW_ROAD := Color(0.45, 1.0, 0.5, 0.45)  # Road Mode: a tile that becomes road
const OLD_ROAD := Color(1, 1, 1, 0.15)  # Road Mode: a tile that's road already
const POWER_AREA := Color(1.0, 0.85, 0.25, 0.22)  # tiles the power network reaches (plan.md §5.5)
const POWER_JOINS := Color(0.45, 1.0, 0.5, 0.3)  # a power building's own circle: it joins the network
const POWER_ALONE := Color(1.0, 0.5, 0.2, 0.3)  # ... it doesn't reach the network

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
## Road Mode (plan.md §5.20): one finger draws a line of road (straight, or with one corner) from
## where it was pressed; ✓ builds it, or removes the road on it when `road_removing`.
var road_mode := false
var road_removing := false
var _road_line: Array[Vector2i] = []
var _road_start := Vector2i.ZERO
var _road_before: Array[Vector2i] = []  # put back if that finger turns out to start a pinch


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
	if _selected != "" and _shows_power(Economy.building(_selected).get("type", "")):
		marker.queue_redraw()  # the power network it shows may have grown
	if placing_type != "":
		_ghost_changed()  # cash may have changed, so the ghost may turn red or green
	elif road_mode:
		_road_changed()


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


## Ends Placement Mode and Road Mode.
func stop_placement() -> void:
	if _views.has(moving_id):
		_views[moving_id].modulate.a = 1.0
	moving_id = ""
	placing_type = ""
	road_mode = false
	_road_line.clear()
	camera.placing = false
	grid.hide()
	cursor.queue_redraw()


## Can the building go where the ghost is? {"ok", "error"}, plus a "hint" when it can but would
## have no road there (so no workers), or no power.
func ghost_check() -> Dictionary:
	var check := Economy.can_move(moving_id, ghost_cell) if moving_id != "" else Economy.can_build(placing_type, ghost_cell)
	if check.ok and Economy.needs_road({"type": placing_type}):
		var linked := Economy.linked_roads()
		var near_road := false
		for side in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			near_road = near_road or linked.has(ghost_cell + side)
		if not near_road:
			check["hint"] = "No road here: it gets no workers until a road reaches it. Tap the tick to place it anyway"
	if check.ok and not check.has("hint") and _shows_power(placing_type):
		var ghost := {"type": placing_type}
		if Economy.power_radius(ghost) > 0.0 and moving_id == "" and not Economy.would_join_network(ghost_cell, Economy.power_radius(ghost)):
			check["hint"] = "Its circle doesn't touch your power network here (the yellow tiles), so it won't be connected. Tap the tick to place it anyway"
		elif Economy.power_need(ghost) > 0.0 and not Economy.powered_cells().has(ghost_cell):
			check["hint"] = "No power here: it won't work until your power network (the yellow tiles) reaches it. Tap the tick to place it anyway"
	return check


## Whether placing this building should show where power reaches: it uses or carries power.
func _shows_power(type_id: String) -> bool:
	if type_id == "" or not Economy.power_on():
		return false
	var ghost := {"type": type_id}
	return Economy.power_need(ghost) > 0.0 or Economy.power_radius(ghost) > 0.0


## Tints the tiles the power network reaches, plus `circle_radius` tiles around `circle_at` (a
## power building's own reach: green when it joins the network, orange when it doesn't).
func _draw_power(canvas: CanvasItem, circle_at: Vector2i, circle_radius: float, joins: bool) -> void:
	for cell in Economy.powered_cells():
		canvas.draw_colored_polygon(Iso.diamond(cell), POWER_AREA)
	if circle_radius <= 0.0:
		return
	var r := ceili(circle_radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := circle_at + Vector2i(dx, dy)
			if dx * dx + dy * dy <= circle_radius * circle_radius + 0.000001 and cell.x >= 0 and cell.y >= 0 and cell.x < island.plot_size.x and cell.y < island.plot_size.y:
				canvas.draw_colored_polygon(Iso.diamond(cell), POWER_JOINS if joins else POWER_ALONE)


## Road Mode: drag across the map to lay road (or remove it, see set_road_removing).
func start_road_mode() -> void:
	stop_placement()
	road_mode = true
	road_removing = false
	camera.placing = true
	grid.show()
	_road_changed()


func set_road_removing(on: bool) -> void:
	road_removing = on
	_road_line.clear()
	_road_changed()


## Can the road being drawn be built (or removed)? {"ok", "error", "hint"}
func road_check() -> Dictionary:
	if _road_line.is_empty():
		return {"ok": false, "error": "Drag across the road you want to remove" if road_removing else "Drag from a road to lay road. Corners and crossroads appear by themselves"}
	if road_removing:
		var removal := Economy.can_remove_roads(_road_line)
		if removal.ok:
			removal["hint"] = "Remove %d road tiles (nothing is paid back)? Tap the tick" % removal.cells.size()
		return removal
	var quote := Economy.road_quote(_road_line)
	if quote.ok:
		quote["hint"] = "%d new road tiles for %s: tap the green tick" % [quote.new_cells.size(), UITheme.money(int(quote.cost))]
	return quote


## ✓ in Road Mode: build (or remove) the road drawn. Road Mode stays on for the next stretch.
func confirm_road() -> Dictionary:
	var result := Economy.remove_roads(_road_line) if road_removing else Economy.build_roads(_road_line)
	if result.ok:
		_road_line.clear()
		_road_changed()
	return result


func _road_changed() -> void:
	cursor.queue_redraw()
	ghost_moved.emit(road_check())


## The tiles from a to b: along the longer side first, then round one corner.
func _road_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [a]
	var corner := Vector2i(b.x, a.y) if absi(b.x - a.x) >= absi(b.y - a.y) else Vector2i(a.x, b.y)
	for target in [corner, b]:
		while cells[-1] != target:
			cells.append(cells[-1] + (target - cells[-1]).sign())
	return cells


func _plot_cell(world_pos: Vector2) -> Vector2i:
	return Iso.to_cell(world_pos).clamp(Vector2i.ZERO, island.plot_size - Vector2i.ONE)


func _begin_placement(type_id: String, cell: Vector2i) -> void:
	placing_type = type_id
	ghost_cell = cell
	camera.placing = true
	grid.show()
	_ghost_changed()


func _ghost_changed() -> void:
	cursor.queue_redraw()
	if _shows_power(placing_type):
		grid.queue_redraw()  # its power circle moves with it
	ghost_moved.emit(ghost_check())


## The free building-area tile closest to `near` (or `near` itself if there is none).
func _free_cell_near(near: Vector2i) -> Vector2i:
	var best := near
	var best_dist := INF
	for x in island.plot_size.x:
		for y in island.plot_size.y:
			var cell := Vector2i(x, y)
			var dist := Vector2(cell - near).length()
			if dist < best_dist and Economy.building_at(cell).is_empty() and not Economy.is_road(cell):
				best = cell
				best_dist = dist
	return best


## Placement Mode, finger down: on the ghost, grab it where it was touched; anywhere else, the
## ghost jumps under the finger.
func _on_finger_down(world_pos: Vector2) -> void:
	if road_mode:
		_road_before = _road_line.duplicate()
		_road_start = _plot_cell(world_pos)
		_road_line = _road_between(_road_start, _road_start)
		_road_changed()
		return
	_ghost_before_press = ghost_cell
	var at := Iso.to_world(Vector2(ghost_cell))
	if BuildingView.preview_rect(placing_type, at).grow(8.0).has_point(world_pos):
		_grip = at - world_pos
	else:
		_grip = Vector2.ZERO
		_move_ghost(Iso.to_cell(world_pos))


func _on_finger_moved(world_pos: Vector2) -> void:
	if road_mode:
		var line := _road_between(_road_start, _plot_cell(world_pos))
		if line != _road_line:
			_road_line = line
			_road_changed()
		return
	_move_ghost(Iso.to_cell(world_pos + _grip))


## That finger was the start of a two-finger pan/zoom: undo the ghost's jump (or the new road).
func _on_finger_cancelled() -> void:
	if road_mode:
		_road_line = _road_before
		_road_changed()
		return
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
	TreeView.bake_picture(self)  # all trees then share one picture: far less work to draw


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
	# A power building (or one that uses power) shows where the power network reaches.
	var b := Economy.building(_selected)
	if not b.is_empty() and _shows_power(b.type):
		var cell := Vector2i(int(b.position[0]), int(b.position[1]))
		_draw_power(marker, cell, Economy.power_radius(b), Economy.power_network().ids.has(b.id))


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
	if _shows_power(placing_type):
		var ghost := {"type": placing_type}
		var radius := Economy.power_radius(ghost)
		_draw_power(grid, ghost_cell, radius, radius > 0.0 and Economy.would_join_network(ghost_cell, radius))


## The ghost: a green (free) or red (blocked) tile with a see-through picture of the building.
func _draw_cursor() -> void:
	if road_mode:
		_draw_road_line()
		return
	if placing_type == "":
		return
	var free: bool = ghost_check().ok
	var diamond := Iso.diamond(ghost_cell)
	cursor.draw_colored_polygon(diamond, OK_COLOR if free else BLOCKED_COLOR)
	cursor.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color.WHITE, 2.0, true)
	var tint := Color(1, 1, 1, 0.6) if free else Color(1, 0.4, 0.4, 0.6)
	BuildingView.draw_preview(cursor, Iso.to_world(Vector2(ghost_cell)), placing_type, tint)


## Road Mode: the road being drawn. Green = new road, faint = already road, red = blocked (or, when
## removing, the road that goes).
func _draw_road_line() -> void:
	var roads := Economy.road_cells()
	for cell in _road_line:
		var color := NEW_ROAD
		if road_removing:
			color = BLOCKED_COLOR if roads.has(cell) else OLD_ROAD
		elif not Economy.building_at(cell).is_empty():
			color = BLOCKED_COLOR
		elif roads.has(cell):
			color = OLD_ROAD
		var diamond := Iso.diamond(cell)
		cursor.draw_colored_polygon(diamond, color)
		cursor.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(1, 1, 1, 0.8), 1.5, true)
