extends Node2D
## PLACEHOLDER island drawn with flat-colour tiles until real art exists.
## The buildable plot (the save's grid_size) sits in the middle; a ring of grass and beach
## surrounds it, and the coastline shape comes from the "island" settings in game_config.json.
## Drawn once, not every frame.

const WATER := Color("1f4e79")
const SHALLOW := Color("2f7fb3")
const CLIFF := Color("6b5a43")
const SAND := Color("e2cf96")
const GRASS := Color("5d9b45")
const PLOT_A := Color("7cbf5a")
const PLOT_B := Color("74b553")
const PLOT_EDGE := Color(1, 1, 1, 0.55)
const CLIFF_DEPTH := 12.0

var plot_size := Vector2i.ZERO
var _land := {}  # Vector2i -> true for every land cell
var _shallow := {}  # Vector2i -> true for water cells near the coast


func _ready() -> void:
	var grid: Array = Economy.state.plot.grid_size
	plot_size = Vector2i(int(grid[0]), int(grid[1]))
	_generate(GameData.config.island)


func is_buildable(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, plot_size).has_point(cell)


func is_land(cell: Vector2i) -> bool:
	return _land.has(cell)


## Rectangle (in world pixels) around the whole island, used to stop the camera wandering off.
func world_bounds() -> Rect2:
	var rect := Rect2(Iso.to_world(Vector2(_land.keys()[0])), Vector2.ZERO)
	for cell: Vector2i in _land:
		rect = rect.expand(Iso.to_world(Vector2(cell)))
	return rect


func _generate(settings: Dictionary) -> void:
	var margin := int(settings.margin)
	var noise := FastNoiseLite.new()
	noise.seed = int(settings.seed)
	noise.frequency = float(settings.coast_frequency)
	var roughness := float(settings.coast_roughness)

	var center := (Vector2(plot_size) - Vector2.ONE) / 2.0
	var radius := Vector2(plot_size) / 2.0 + Vector2(margin, margin)
	var reach := margin + 6  # how far past the plot the coast may wobble out
	for x in range(-reach, plot_size.x + reach):
		for y in range(-reach, plot_size.y + reach):
			var cell := Vector2i(x, y)
			# Distance from the middle, halfway between a circle and a square (0 = centre, 1 = coast).
			var d := (Vector2(cell) - center) / radius
			var dist := lerpf(d.length(), maxf(absf(d.x), absf(d.y)), 0.5)
			var coast := 1.0 + noise.get_noise_2d(x, y) * roughness
			# The plot plus one tile around it is always land, so the coast never cuts into it.
			if dist < coast or Rect2i(Vector2i(-1, -1), plot_size + Vector2i(2, 2)).has_point(cell):
				_land[cell] = true

	for cell: Vector2i in _land:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				var near := cell + Vector2i(dx, dy)
				if not _land.has(near):
					_shallow[near] = true


func _is_coast(cell: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if not _land.has(cell + Vector2i(dx, dy)):
				return true
	return false


func _draw() -> void:
	var bounds := world_bounds().grow(3000)
	draw_rect(bounds, WATER)
	for cell in _shallow:
		draw_colored_polygon(Iso.diamond(cell), SHALLOW)

	# Cliff edges first: a dark strip under land tiles whose front neighbour is water (fake 3D depth).
	var down := Vector2(0, CLIFF_DEPTH)
	for cell: Vector2i in _land:
		var d := Iso.diamond(cell)
		if not _land.has(cell + Vector2i(1, 0)):
			draw_colored_polygon(PackedVector2Array([d[1], d[2], d[2] + down, d[1] + down]), CLIFF.darkened(0.15))
		if not _land.has(cell + Vector2i(0, 1)):
			draw_colored_polygon(PackedVector2Array([d[2], d[3], d[3] + down, d[2] + down]), CLIFF)

	for cell: Vector2i in _land:
		var color := GRASS
		if is_buildable(cell):
			color = PLOT_A if (cell.x + cell.y) % 2 == 0 else PLOT_B
		elif _is_coast(cell):
			color = SAND
		draw_colored_polygon(Iso.diamond(cell), color)

	# Outline of the buildable plot.
	var corners := PackedVector2Array([
		Iso.to_world(Vector2(-0.5, -0.5)),
		Iso.to_world(Vector2(plot_size.x - 0.5, -0.5)),
		Iso.to_world(Vector2(plot_size.x - 0.5, plot_size.y - 0.5)),
		Iso.to_world(Vector2(-0.5, plot_size.y - 0.5)),
		Iso.to_world(Vector2(-0.5, -0.5)),
	])
	draw_polyline(corners, PLOT_EDGE, 2.0)
