extends Node2D
## Village View: the island, the camera, and everything standing on the island.
## Layers, back to front: IslandMap (sea and land) -> Grid (only in Placement Mode) -> Shadows ->
## Objects (buildings and trees, sorted so lower-on-screen covers higher) -> Cursor (placement preview).
## Reads building positions from Economy; never stores game numbers itself.

## A land tile was tapped/clicked. Build placement listens to this.
signal cell_tapped(cell: Vector2i)

const IslandMap = preload("res://scenes/village/island_map.gd")
const VillageCamera = preload("res://scenes/village/village_camera.gd")
const BuildingView = preload("res://scenes/village/building_view.gd")
const TreeView = preload("res://scenes/village/tree_view.gd")
const ShadowLayer = preload("res://scenes/village/shadow_layer.gd")

const OK_COLOR := Color(1, 1, 1, 0.35)
const BLOCKED_COLOR := Color(1, 0.25, 0.2, 0.45)
const GRID_LINE := Color(1, 1, 1, 0.22)
const GRID_EDGE := Color(1, 1, 1, 0.7)

@onready var island: IslandMap = $IslandMap
@onready var grid: Node2D = $Grid
@onready var shadows: ShadowLayer = $Shadows
@onready var objects: Node2D = $Objects
@onready var cursor: Node2D = $Cursor
@onready var camera: VillageCamera = $Camera

var _hover := Vector2i(-9999, -9999)
var _views := {}  # building id -> its BuildingView
## Building type being placed, or "" when not in Placement Mode.
var placing_type := ""


func _ready() -> void:
	grid.draw.connect(_draw_grid)
	grid.hide()
	cursor.draw.connect(_draw_cursor)
	shadows.objects = objects
	_plant_trees()
	_sync_buildings()
	camera.bounds = island.world_bounds()
	camera.position = Iso.to_world((Vector2(island.plot_size) - Vector2.ONE) / 2.0)
	# Start zoomed out far enough to see the whole island.
	var fit := get_viewport_rect().size / camera.bounds.size
	var start_zoom := clampf(minf(fit.x, fit.y) * 0.95, VillageCamera.ZOOM_MIN, 1.0)
	camera.zoom = Vector2(start_zoom, start_zoom)
	camera.hovered.connect(_on_hovered)
	camera.tapped.connect(_on_tapped)
	Economy.changed.connect(_on_economy_changed)


func _on_economy_changed() -> void:
	# Economy ticks every second; only touch the map when a building was actually added.
	if Economy.state.buildings.size() != _views.size():
		_sync_buildings()
	if placing_type != "":
		cursor.queue_redraw()  # cash may have changed, so the preview may turn red or green


## Placement Mode: show the grid and a see-through preview of type_id under the pointer.
func start_placement(type_id: String) -> void:
	placing_type = type_id
	grid.show()
	cursor.queue_redraw()


func stop_placement() -> void:
	placing_type = ""
	grid.hide()
	cursor.queue_redraw()


## Gives every building in the game state a view on the map (buildings are never removed in Phase 1a).
func _sync_buildings() -> void:
	for b in Economy.state.buildings:
		if _views.has(b.id):
			continue
		var view := BuildingView.new()
		view.type_id = b.type
		view.position = Iso.to_world(Vector2(b.position[0], b.position[1]))
		objects.add_child(view)
		_views[b.id] = view
	shadows.queue_redraw()


func _plant_trees() -> void:
	for spot in island.tree_spots():
		var tree := TreeView.new()
		tree.position = spot.position
		tree.pine = spot.pine
		tree.size = spot.size
		objects.add_child(tree)


func _on_hovered(world_pos: Vector2) -> void:
	var cell := Iso.to_cell(world_pos)
	if cell != _hover:
		_hover = cell
		if placing_type != "":
			cursor.queue_redraw()


func _on_tapped(world_pos: Vector2) -> void:
	var cell := Iso.to_cell(world_pos)
	# On touchscreens there is no hover, so a tap also moves the preview.
	_hover = cell
	cursor.queue_redraw()
	if island.is_land(cell):
		cell_tapped.emit(cell)


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


func _draw_cursor() -> void:
	if placing_type == "" or not island.is_land(_hover):
		return
	var free: bool = Economy.can_build(placing_type, _hover).ok
	var diamond := Iso.diamond(_hover)
	cursor.draw_colored_polygon(diamond, OK_COLOR if free else BLOCKED_COLOR)
	cursor.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color.WHITE, 2.0, true)
	var tint := Color(1, 1, 1, 0.6) if free else Color(1, 0.4, 0.4, 0.6)
	BuildingView.draw_preview(cursor, Iso.to_world(Vector2(_hover)), placing_type, tint)
