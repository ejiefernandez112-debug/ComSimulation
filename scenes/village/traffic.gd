extends Node
## Life on the roads (plan.md §5.20): little people walking on the pavements and cars and vans
## driving on the right-hand lane. FOR SHOW ONLY: they never slow anything down, are never saved
## and hold no game numbers, so random choices are fine here (the rules in scripts/sim/ never use
## randomness). More people walk the busier the village is (workers at work), more cars drive the
## more buildings are working; about half the cars drive to or from the Warehouse, like
## deliveries. Each one walks or drives from road tile to road tile along the roads, then picks a
## new trip. Fewer of them on the "Low" detail setting. Nothing moves when there are no roads.

const WALKERS_MAX := 30
const CARS_MAX := 12
const WORKERS_PER_WALKER := 4
const ROAD_TILES_PER_CAR := 10
const WALK_SPEED := 0.55  # tiles a second
const DRIVE_SPEED := 1.6
const SHIRTS: Array[Color] = [Color("e05a47"), Color("3d8bd4"), Color("f2c14e"), Color("5cb85c"), Color("9b6dd6"), Color("f08a4b"), Color("ffffff")]
const SKIN: Array[Color] = [Color("f1c7a1"), Color("d9a074"), Color("a86b45"), Color("6e4429")]
const CAR_COLORS: Array[Color] = [Color("d64541"), Color("2f80c9"), Color("f4d03f"), Color("ecf0f1"), Color("27ae60"), Color("34495e")]

## The node the people and cars are added to: the village's y-sorted Objects layer.
@onready var objects: Node2D = $"../Objects"

var _agents: Array[Agent] = []
var _roads := {}  # Vector2i -> true: the road tiles they move on
var _next_to_warehouse: Array[Vector2i] = []  # road tiles beside a warehouse (delivery stops)
var _walkers_wanted := 0
var _cars_wanted := 0


func _ready() -> void:
	set_process(false)
	Economy.changed.connect(_on_economy_changed)
	Settings.changed.connect(_on_economy_changed)
	_on_economy_changed()


## Works out how many people and cars there should be, and adds or removes some.
func _on_economy_changed() -> void:
	_roads = Economy.road_cells()
	_next_to_warehouse.clear()
	var working := 0
	var busy := 0
	for b in Economy.state.buildings:
		var w := Economy.workers(b)
		working += roundi(float(w.working))
		if Economy.needs_road(b) and float(w.working) > 0.0:
			busy += 1
		if GameData.buildings[b.type].get("category", "") == "storage":
			for side in Agent.SIDES:
				var cell := Vector2i(int(b.position[0]), int(b.position[1])) + side
				if _roads.has(cell):
					_next_to_warehouse.append(cell)
	var share := 1.0 if Settings.get_value("water_detail") else 0.5
	_walkers_wanted = 0 if _roads.is_empty() else mini(WALKERS_MAX, ceili(working / float(WORKERS_PER_WALKER) * share))
	_cars_wanted = 0 if _roads.size() < 2 else mini(CARS_MAX, ceili((busy + _roads.size() / float(ROAD_TILES_PER_CAR)) * share))
	# Anyone standing on a road that's gone leaves at once; the rest finish their trip first.
	for agent in _agents.duplicate():
		if not _roads.has(agent.tile()):
			_remove(agent)
	while _count(false) < _walkers_wanted:
		_add(false)
	while _count(true) < _cars_wanted:
		_add(true)
	set_process(not _agents.is_empty())


func _process(delta: float) -> void:
	for agent in _agents.duplicate():
		if agent.advance(delta):
			continue  # still on its way
		# Arrived: too many of its kind leave; the others set off on a new trip.
		if _count(agent.car) > (_cars_wanted if agent.car else _walkers_wanted):
			_remove(agent)
		elif not _new_trip(agent, agent.tile()):
			_remove(agent)
	set_process(not _agents.is_empty())


func _count(car: bool) -> int:
	var n := 0
	for agent in _agents:
		if agent.car == car:
			n += 1
	return n


func _add(car: bool) -> void:
	var agent := Agent.new()
	agent.car = car
	agent.speed = (DRIVE_SPEED if car else WALK_SPEED) * randf_range(0.85, 1.15)
	agent.color = CAR_COLORS.pick_random() if car else SHIRTS.pick_random()
	agent.skin = SKIN.pick_random()
	agent.van = car and randf() < 0.35
	agent.side = 1.0 if randf() < 0.5 else -1.0  # which pavement a walker keeps to
	if not _new_trip(agent, _roads.keys().pick_random()):
		agent.free()
		return
	_agents.append(agent)
	objects.add_child(agent)


func _remove(agent: Agent) -> void:
	_agents.erase(agent)
	agent.queue_free()


## Sends the agent from `from` to somewhere else along the roads. False when there's nowhere to go.
func _new_trip(agent: Agent, from: Vector2i) -> bool:
	var to: Vector2i = _roads.keys().pick_random()
	if agent.car and not _next_to_warehouse.is_empty() and randf() < 0.5:
		to = _next_to_warehouse.pick_random()  # a delivery
	var tiles := _route(from, to)
	if tiles.size() < 2:
		tiles = _route(from, _roads.keys().pick_random())
	if tiles.size() < 2:
		return false
	agent.follow(tiles)
	return true


## The shortest way along the roads from one tile to another ([] when they aren't joined).
func _route(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var came_from := {from: from}
	var todo: Array[Vector2i] = [from]
	var i := 0
	while i < todo.size():
		var cell: Vector2i = todo[i]
		i += 1
		if cell == to:
			var path: Array[Vector2i] = []
			while cell != from:
				path.push_front(cell)
				cell = came_from[cell]
			path.push_front(from)
			return path
		var sides := Agent.SIDES.duplicate()
		sides.shuffle()  # equal-length ways: not always the same one
		for side in sides:
			var next: Vector2i = cell + side
			if _roads.has(next) and not came_from.has(next):
				came_from[next] = cell
				todo.append(next)
	return []


## One person or car. Moves in tile units (so lanes and pavements are easy) and is placed on the
## map with Iso, so the Objects layer sorts it in front of or behind buildings.
class Agent extends Node2D:
	const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	const LANE := 0.12  # cars keep this far right of the middle of the road (tiles)
	const PAVEMENT := 0.31  # walkers walk this far from the middle

	var car := false
	var van := false
	var speed := 1.0
	var color := Color.WHITE
	var skin := Color.WHITE
	var side := 1.0
	var _points: Array[Vector2] = []  # where to go next, in tile units
	var _at := Vector2.ZERO  # where it is, in tile units
	var _heading := Vector2(1, 0)
	var _step := 0.0  # walking bob

	## Takes this route of road tiles: works out the points along its lane or pavement.
	func follow(tiles: Array[Vector2i]) -> void:
		_points.clear()
		for i in tiles.size():
			var dir := Vector2(tiles[mini(i + 1, tiles.size() - 1)] - tiles[maxi(i - 1, 0)]).normalized()
			var right := Vector2(-dir.y, dir.x)
			var off := right * LANE if car else right * PAVEMENT * side
			_points.append(Vector2(tiles[i]) + off)
		_at = _points.pop_front()
		_place()

	## The road tile it's on.
	func tile() -> Vector2i:
		return Vector2i(_at.round())

	## Moves on. False once it has arrived.
	func advance(delta: float) -> bool:
		var left := speed * delta
		while left > 0.0 and not _points.is_empty():
			var to := _points[0]
			var gap := _at.distance_to(to)
			if gap > 0.0001:
				_heading = (to - _at) / gap
			if gap <= left:
				_at = to
				left -= gap
				_points.pop_front()
			else:
				_at += _heading * left
				left = 0.0
		_step += delta * speed * 14.0
		_place()
		return not _points.is_empty()

	func _place() -> void:
		position = Iso.to_world(_at)
		queue_redraw()

	## Its own soft shadow is drawn with it (the Shadows layer only redraws when buildings change).
	func draw_shadow(_layer: Node2D) -> void:
		pass

	func _draw() -> void:
		if car:
			_draw_car()
		else:
			_draw_walker()

	func _draw_walker() -> void:
		var bob := absf(sin(_step)) * 1.2
		draw_circle(Vector2(1.5, 0.5), 2.6, Color(0, 0, 0, 0.18))
		var swing := sin(_step) * 1.4
		draw_line(Vector2(-0.8, -3.5 - bob), Vector2(-0.8 + swing, 0), Color("2d3440"), 1.3, true)
		draw_line(Vector2(0.8, -3.5 - bob), Vector2(0.8 - swing, 0), Color("2d3440"), 1.3, true)
		draw_rect(Rect2(-1.8, -8.5 - bob, 3.6, 5.2), color)
		draw_circle(Vector2(0, -10.2 - bob), 1.9, skin, true, -1.0, true)

	## A little box on wheels, turned the way it's driving: body, then a lighter roof.
	func _draw_car() -> void:
		var length := 0.30 if van else 0.24
		var width := 0.13
		var height := 7.0 if van else 5.0
		var along := _heading * length / 2.0
		var across := Vector2(-_heading.y, _heading.x) * width / 2.0
		var base := PackedVector2Array()
		for c in [along + across, along - across, -along - across, -along + across]:
			base.append(Iso.to_world(_at + c) - position)
		var shadow := base.duplicate()
		for i in shadow.size():
			shadow[i] += Vector2(2.0, 1.0)
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.22))
		var lift := Vector2(0, -height)
		var top := PackedVector2Array()
		for p in base:
			top.append(p + lift)
		# Sides: each edge of the base raised into a wall; drawn back to front.
		for i in 4:
			var a := base[i]
			var b := base[(i + 1) % 4]
			if (a.y + b.y) / 2.0 >= 0.0:  # the walls facing the viewer
				draw_colored_polygon(PackedVector2Array([a, b, b + lift, a + lift]), color.darkened(0.3 if a.x < b.x else 0.45))
		draw_colored_polygon(top, color)
		# The cabin's windows / roof: a smaller, lighter box on top (not on a van's load area).
		var roof := PackedVector2Array()
		var shrink := 0.55
		for p in top:
			roof.append(p * shrink + lift * 0.45 + (Vector2(0, 0) if not van else Iso.to_world(_at + _heading * length * 0.18) - position))
		draw_colored_polygon(roof, Color("cfe8f5") if not van else color.lightened(0.25))
