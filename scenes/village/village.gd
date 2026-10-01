extends Node2D
## Village View: the island, the camera, a highlight on the tile under the pointer, and
## PLACEHOLDER blocks for buildings (grey boxes with a name) until real sprites exist.
## Reads building positions from Economy; never stores game numbers itself.

## A land tile was tapped/clicked. Build placement (next step) will listen to this.
signal cell_tapped(cell: Vector2i)

const IslandMap = preload("res://scenes/village/island_map.gd")
const VillageCamera = preload("res://scenes/village/village_camera.gd")

const OK_COLOR := Color(1, 1, 1, 0.35)
const BLOCKED_COLOR := Color(1, 0.25, 0.2, 0.45)
const BLOCK_HEIGHT := 22.0
const CATEGORY_COLORS := {
	"civic": Color("8a8fa8"),
	"residential": Color("c98b5e"),
	"extractor": Color("d6b84a"),
	"processor": Color("9c7bb5"),
}

@onready var island: IslandMap = $IslandMap
@onready var buildings_layer: Node2D = $Buildings
@onready var cursor: Node2D = $Cursor
@onready var camera: VillageCamera = $Camera

var _hover := Vector2i(-9999, -9999)
var _building_count := -1
## Building type being placed, or "" when not in Placement Mode.
var placing_type := ""


func _ready() -> void:
	buildings_layer.draw.connect(_draw_buildings)
	cursor.draw.connect(_draw_cursor)
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
	# Economy ticks every second; only redraw when a building was actually added.
	if Economy.state.buildings.size() != _building_count:
		_building_count = Economy.state.buildings.size()
		buildings_layer.queue_redraw()
	if placing_type != "":
		cursor.queue_redraw()  # cash may have changed, so the preview may turn red or green


## Placement Mode: show a see-through preview of type_id under the pointer.
func start_placement(type_id: String) -> void:
	placing_type = type_id
	cursor.queue_redraw()


func stop_placement() -> void:
	placing_type = ""
	cursor.queue_redraw()


func _on_hovered(world_pos: Vector2) -> void:
	var cell := Iso.to_cell(world_pos)
	if cell != _hover:
		_hover = cell
		cursor.queue_redraw()


func _on_tapped(world_pos: Vector2) -> void:
	var cell := Iso.to_cell(world_pos)
	# On touchscreens there is no hover, so a tap also moves the highlight/preview.
	_hover = cell
	cursor.queue_redraw()
	if island.is_land(cell):
		cell_tapped.emit(cell)


func _draw_cursor() -> void:
	if not island.is_land(_hover):
		return
	var free: bool
	if placing_type != "":
		free = Economy.can_build(placing_type, _hover).ok
	else:
		free = island.is_buildable(_hover) and Economy.building_at(_hover).is_empty()
	var color := OK_COLOR if free else BLOCKED_COLOR
	cursor.draw_colored_polygon(Iso.diamond(_hover), color)
	cursor.draw_polyline(Iso.diamond(_hover) + PackedVector2Array([Iso.diamond(_hover)[0]]), Color.WHITE, 2.0)
	if placing_type != "":
		var tint := Color(1, 1, 1, 0.6) if free else Color(1, 0.4, 0.4, 0.6)
		_draw_block(cursor, _hover, placing_type, tint)


func _draw_buildings() -> void:
	var list: Array = Economy.state.buildings.duplicate()
	# Draw back-to-front so nearer blocks cover farther ones.
	list.sort_custom(func(a, b): return a.position[0] + a.position[1] < b.position[0] + b.position[1])
	for b in list:
		_draw_block(buildings_layer, Vector2i(int(b.position[0]), int(b.position[1])), b.type, Color.WHITE)


## PLACEHOLDER building look: a coloured box with the building's name above it.
func _draw_block(canvas: CanvasItem, cell: Vector2i, type_id: String, tint: Color) -> void:
	var def: Dictionary = GameData.buildings[type_id]
	var color: Color = CATEGORY_COLORS.get(def.category, Color.GRAY) * tint
	var base := Iso.diamond(cell)
	var top := Iso.diamond(cell, BLOCK_HEIGHT)
	canvas.draw_colored_polygon(PackedVector2Array([top[3], top[2], base[2], base[3]]), color.darkened(0.25))
	canvas.draw_colored_polygon(PackedVector2Array([top[2], top[1], base[1], base[2]]), color.darkened(0.4))
	canvas.draw_colored_polygon(top, color)
	var label_pos := top[0] + Vector2(-60, -6)
	canvas.draw_string(ThemeDB.fallback_font, label_pos, def.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(1, 1, 1, tint.a))
