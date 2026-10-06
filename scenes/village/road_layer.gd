extends Node2D
## Draws the streets on the ground (plan.md §5.20), under shadows and buildings. PLACEHOLDER art
## drawn in code, like the island, in the clean isometric city-block style the user picked:
## - roads: grey asphalt with a pale pavement on both sides; each tile picks its shape from its
##   road neighbours (dead end, straight, corner, T-junction, crossroads), so corners and
##   junctions appear by themselves. Straight pieces get a dashed centre line.
## - pedestrian crossings (zebra stripes) only at corners, T-junctions and crossroads, on each arm.
## - building plots: every building (not the Makeshift Huts) stands on its own little island, a
##   lawn with a raised pavement edge and a few bushes. No road runs into a building.
## - street lights: a few lamp posts along the pavements (every 4th straight tile, junctions), added to the village's y-sorted Objects
##   layer so buildings, people and cars pass in front of and behind them.
## Redraws only when the roads or buildings change. (Later: pieces made in Blender and
## photographed by the sprite studio.)

const PAVEMENT := Color("d6d2c6")
const PAVEMENT_EDGE := Color("a9a497")  # the side of a raised pavement / plot edge
const ASPHALT := Color("5b6068")
const LINE := Color("f2d15c")  # centre line
const ZEBRA := Color(1, 1, 1, 0.9)
const LAWN := Color("86c25a")
const LAWN_DARK := Color("6aa647")
const BUSH := Color("3f8a3a")
const CURB_HALF := 0.36  # half the road's width with its pavement, in tiles
const ROAD_HALF := 0.27  # half the asphalt's width, in tiles
const PLOT_HALF := 0.47  # half a building plot, in tiles (a little gap between neighbours)
const LAWN_HALF := 0.40
const PLOT_LIFT := 2.5  # pixels a plot's edge stands above the ground
const LAMP_EVERY := 4  # a street light on every 4th straight road tile
const LAMP_SPOT := 0.32  # how far from the road's middle the lamp posts stand (on the pavement)
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

@onready var _objects: Node2D = $"../Objects"
var _lamps: Array[Node2D] = []
var _drawn_key := -1  # Economy.layout_key() at the last redraw


func _ready() -> void:
	Economy.changed.connect(_on_economy_changed)
	_on_economy_changed()


func _on_economy_changed() -> void:
	var key := Economy.layout_key()
	if key != _drawn_key:
		_drawn_key = key
		queue_redraw()
		_place_lamps.call_deferred()


func _draw() -> void:
	var roads := Economy.road_cells()
	for b in Economy.state.buildings:
		if not GameData.buildings[b.type].get("hut", false):
			_draw_plot(Economy.centre_at(b.type, Vector2i(int(b.position[0]), int(b.position[1]))), Economy.size_of(b.type))
	# Two passes, so every tile's pavement sits under every tile's asphalt and the joins are clean.
	for half in [CURB_HALF, ROAD_HALF]:
		for cell in roads:
			_draw_piece(cell, roads, half, PAVEMENT if half == CURB_HALF else ASPHALT)
	for cell in roads:
		_draw_markings(cell, roads)


## A building's little island: a raised pavement square, a lawn inside, bushes on its corners.
## `c` = the middle of the building in tiles, `size` = how many tiles wide it is.
func _draw_plot(c: Vector2, size: int) -> void:
	var grow := (size - 1) / 2.0  # a 2x2 plot reaches half a tile further each way
	var h := PLOT_HALF + grow
	var lawn := LAWN_HALF + grow
	var top := [Iso.to_world(c + Vector2(-h, -h)), Iso.to_world(c + Vector2(h, -h)),
		Iso.to_world(c + Vector2(h, h)), Iso.to_world(c + Vector2(-h, h))]
	var lift := Vector2(0, PLOT_LIFT)
	# The two edges facing the viewer, then the top.
	draw_colored_polygon(PackedVector2Array([top[1], top[2], top[2] + lift, top[1] + lift]), PAVEMENT_EDGE.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([top[2], top[3], top[3] + lift, top[2] + lift]), PAVEMENT_EDGE)
	_quad_at(c, Vector2(-h, -h), Vector2(h, h), PAVEMENT)
	_quad_at(c, Vector2(-lawn, -lawn), Vector2(lawn, lawn), LAWN)
	# A darker band along the lawn's back edges, so it reads as grass behind a kerb.
	_quad_at(c, Vector2(-lawn, -lawn), Vector2(lawn, -lawn + 0.05), LAWN_DARK)
	_quad_at(c, Vector2(-lawn, -lawn), Vector2(-lawn + 0.05, lawn), LAWN_DARK)
	# Bushes on the left, right and front corners (the back one hides behind the building).
	for corner in [Vector2(0.34, -0.34), Vector2(-0.34, 0.34), Vector2(0.35, 0.35)]:
		var at := Iso.to_world(c + corner + corner.sign() * grow)
		draw_circle(at + Vector2(1.5, 1.0), 3.6, Color(0, 0, 0, 0.18), true, -1.0, true)
		draw_circle(at, 3.6, BUSH, true, -1.0, true)
		draw_circle(at + Vector2(-1.0, -1.3), 1.6, BUSH.lightened(0.3), true, -1.0, true)


## One road tile: a square in the middle, plus an arm to each road beside it.
func _draw_piece(cell: Vector2i, roads: Dictionary, half: float, color: Color) -> void:
	_quad(cell, Vector2(-half, -half), Vector2(half, half), color)
	for side in SIDES:
		if roads.has(cell + side):
			if side.x != 0:
				_quad(cell, Vector2(minf(0.0, side.x * 0.5), -half), Vector2(maxf(0.0, side.x * 0.5), half), color)
			else:
				_quad(cell, Vector2(-half, minf(0.0, side.y * 0.5)), Vector2(half, maxf(0.0, side.y * 0.5)), color)


## The road's arms (sides with road beside it).
static func _arms(cell: Vector2i, roads: Dictionary) -> Array[Vector2i]:
	var arms: Array[Vector2i] = []
	for side in SIDES:
		if roads.has(cell + side):
			arms.append(side)
	return arms


## Dashed centre line on straight pieces; zebra crossings on the arms of corners and junctions.
func _draw_markings(cell: Vector2i, roads: Dictionary) -> void:
	var arms := _arms(cell, roads)
	if arms.size() == 2 and arms[0] == -arms[1]:
		var along := Vector2(absi(arms[0].x), absi(arms[0].y))  # same direction on every tile
		for t in [-0.4, 0.1]:  # two dashes per tile, lined up from tile to tile
			_line(cell, along * t, along * (t + 0.25), LINE, 1.6)
	elif arms.size() >= 2:  # corners, T-junctions and crossroads
		for arm in arms:
			_zebra(cell, Vector2(arm) * 0.4, Vector2(arm))


## A zebra crossing centred at `mid` (tile units from the tile's middle) across a road that runs
## along `along`: white bars, each parallel to the traffic, side by side across the road.
func _zebra(cell: Vector2i, mid: Vector2, along: Vector2) -> void:
	var across := Vector2(along.y, along.x)
	for k in range(-2, 3):
		var at := mid + across * (k * 0.1)
		var a := at - along * 0.07 - across * 0.03
		var b := at + along * 0.07 + across * 0.03
		_quad(cell, Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(maxf(a.x, b.x), maxf(a.y, b.y)), ZEBRA)


## Street lights, kept sparse: one on every 4th straight road tile (on alternate sides of the
## road) and one at each junction; none on bends. LAMP_EVERY sets the spacing.
func _place_lamps() -> void:
	for lamp in _lamps:
		lamp.queue_free()
	_lamps.clear()
	var roads := Economy.road_cells()
	for cell in roads:
		var arms := _arms(cell, roads)
		var spot := Vector2.INF
		var step := posmod(cell.x + cell.y, LAMP_EVERY * 2)
		if arms.size() == 2 and arms[0] == -arms[1]:
			if step % LAMP_EVERY == 0:
				var across := Vector2(absi(arms[0].y), absi(arms[0].x))
				spot = across * LAMP_SPOT * (1.0 if step == 0 else -1.0)
		elif arms.size() >= 3:
			spot = Vector2(LAMP_SPOT, -LAMP_SPOT)  # a pavement corner (never on an arm)
		if spot == Vector2.INF:
			continue
		var lamp := Lamp.new()
		lamp.position = Iso.to_world(Vector2(cell) + spot)
		lamp.reach = (Iso.to_world(Vector2(cell)) - lamp.position).normalized() * 7.0  # leans over the road
		_objects.add_child(lamp)
		_lamps.append(lamp)


## A rectangle given in tile units around the tile's centre (from `a` to `b`), drawn as a diamond.
func _quad(cell: Vector2i, a: Vector2, b: Vector2, color: Color) -> void:
	_quad_at(Vector2(cell), a, b, color)


## The same around any point in tiles (e.g. the middle of a 2x2 building).
func _quad_at(c: Vector2, a: Vector2, b: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Iso.to_world(c + Vector2(a.x, a.y)), Iso.to_world(c + Vector2(b.x, a.y)),
		Iso.to_world(c + Vector2(b.x, b.y)), Iso.to_world(c + Vector2(a.x, b.y)),
	]), color)


func _line(cell: Vector2i, a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var c := Vector2(cell)
	draw_line(Iso.to_world(c + a), Iso.to_world(c + b), color, width, true)


## A street light: a thin dark pole with an arm leaning over the road and a lamp at its end.
class Lamp extends Node2D:
	const HEIGHT := 24.0
	const POLE := Color("3b4048")
	var reach := Vector2.ZERO  # where the arm points (towards the road's middle)

	## Its own thin shadow is drawn with it (the Shadows layer only redraws when buildings change).
	func draw_shadow(_layer: Node2D) -> void:
		pass

	func _draw() -> void:
		draw_line(Vector2.ZERO, Iso.SHADOW * HEIGHT * 0.6, Color(0, 0, 0, 0.16), 2.0, true)
		draw_circle(Vector2.ZERO, 1.8, POLE, true, -1.0, true)
		var top := Vector2(0, -HEIGHT)
		draw_line(Vector2.ZERO, top, POLE, 1.6, true)
		var head := top + reach + Vector2(0, 2)
		draw_line(top, top + reach * 0.6 + Vector2(0, -1.5), POLE, 1.4, true)
		draw_line(top + reach * 0.6 + Vector2(0, -1.5), head, POLE, 1.4, true)
		draw_circle(head + Vector2(0, 1.2), 3.2, Color(1.0, 0.92, 0.6, 0.25), true, -1.0, true)
		draw_circle(head + Vector2(0, 0.8), 1.7, Color("fff3c4"), true, -1.0, true)
