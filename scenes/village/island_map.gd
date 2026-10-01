extends Node2D
## PLACEHOLDER island until the baked island art exists (plan.md §4, visual step 3).
## This script decides WHERE things are: the coastline (from the "island" settings in
## game_config.json), which stretches of coast are sandy beaches, and where trees grow.
## island.gdshader decides how it LOOKS. Everything is worked out once at start-up and handed to
## the shader as a small data texture; after that only the water animates (on the GPU).

const IslandShader = preload("res://scenes/village/island.gdshader")

## How far past the land the shader's data reaches (cells). Must be further than the shallow-water
## colour reaches (about 15 cells on beaches), so the sea is plain deep blue where the data ends.
const SEA_PAD := 18
## Distance written on the data's outer edge, which the shader repeats across the open sea.
const OPEN_SEA := 99.0
## How high the land stands above the sea, in pixels: rocky cliffs and sandy beaches.
const CLIFF_PX := 40.0
const BEACH_PX := 7.0

var plot_size := Vector2i.ZERO
var _settings: Dictionary
var _land := {}  # Vector2i -> true for every land cell
var _beach_noise := FastNoiseLite.new()
var _data_rect := Rect2i()  # cells covered by the shader's data texture
var _coast_distance := PackedFloat32Array()  # per cell of _data_rect: cells to the coast, negative on land


func _ready() -> void:
	var grid: Array = Economy.state.plot.grid_size
	plot_size = Vector2i(int(grid[0]), int(grid[1]))
	_settings = GameData.config.island
	_generate()
	_beach_noise.seed = int(_settings.seed) + 1
	_beach_noise.frequency = 0.07
	_measure_coast()
	_setup_shader()


func is_buildable(cell: Vector2i) -> bool:
	return Rect2i(Vector2i.ZERO, plot_size).has_point(cell)


func is_land(cell: Vector2i) -> bool:
	return _land.has(cell)


## Rectangle (in world pixels) around everything you can see of the island: the outer tiles' edges
## and the cliffs hanging below the front coast. The camera frames and stays within this.
func world_bounds() -> Rect2:
	var rect := Rect2(Iso.to_world(Vector2(_land.keys()[0])), Vector2.ZERO)
	for cell: Vector2i in _land:
		rect = rect.expand(Iso.to_world(Vector2(cell)))
	return rect.grow_individual(Iso.TILE_W / 2.0, Iso.TILE_H / 2.0, Iso.TILE_W / 2.0, Iso.TILE_H / 2.0 + CLIFF_PX)


## Where PLACEHOLDER trees stand: patches of forest on the land around the plot, never on the plot,
## right next to it, at the water's edge or on a beach. Same seed, same trees, every time.
## Each spot is {"position": world point of the trunk's foot, "pine": bool, "size": float}.
func tree_spots() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_settings.seed)
	var forest := FastNoiseLite.new()
	forest.seed = int(_settings.seed) + 2
	forest.frequency = 0.12
	var keep_clear := Rect2i(Vector2i(-1, -1), plot_size + Vector2i(2, 2))
	var spots := []
	for cell: Vector2i in _land:
		var inland := -_distance_at(cell)
		if keep_clear.has_point(cell) or inland < 1.4 or (_beach_at(cell) > 0.3 and inland < 3.0):
			continue
		var thickness := clampf(0.45 + forest.get_noise_2d(cell.x, cell.y) * 1.6, 0.0, 1.0)
		for i in 2:  # up to two trees per cell in thick forest
			if rng.randf() < thickness * float(_settings.tree_density):
				var nudge := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35))
				spots.append({
					"position": Iso.to_world(Vector2(cell) + nudge),
					"pine": rng.randf() < 0.25 + thickness * 0.4,
					"size": rng.randf_range(0.8, 1.25),
				})
	return spots


func _generate() -> void:
	var margin := int(_settings.margin)
	var noise := FastNoiseLite.new()
	noise.seed = int(_settings.seed)
	noise.frequency = float(_settings.coast_frequency)
	var roughness := float(_settings.coast_roughness)

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


## 0 = rocky cliff, 1 = sandy beach. Changes slowly along the coast, so beaches come in stretches.
## The "beaches" setting is roughly the share of coast that is sandy.
func _beach_at(cell: Vector2i) -> float:
	var threshold := lerpf(0.35, -0.35, float(_settings.beaches))
	return smoothstep(threshold - 0.08, threshold + 0.08, _beach_noise.get_noise_2d(cell.x, cell.y))


## Works out how far every cell is from the coast. The shader blends these numbers between cells,
## which is what turns the blocky grid coastline into a smooth one.
func _measure_coast() -> void:
	var lo: Vector2i = _land.keys()[0]
	var hi := lo
	for cell: Vector2i in _land:
		lo = lo.min(cell)
		hi = hi.max(cell)
	_data_rect = Rect2i(lo, hi - lo + Vector2i.ONE).grow(SEA_PAD)
	var to_land := _spread_distance(true)
	var to_sea := _spread_distance(false)
	_coast_distance.resize(to_land.size())
	for i in to_land.size():
		# Halfway between a land cell and a sea cell is the coast (distance 0).
		_coast_distance[i] = 0.5 - to_sea[i] if to_land[i] == 0.0 else to_land[i] - 0.5
	# Soften one-tile notches and bumps, but keep every land cell's centre on land (taps must
	# match what you see).
	for pass_number in 2:
		_coast_distance = _blurred(_coast_distance)
	for y in _data_rect.size.y:
		for x in _data_rect.size.x:
			var i := y * _data_rect.size.x + x
			if _land.has(_data_rect.position + Vector2i(x, y)):
				_coast_distance[i] = minf(_coast_distance[i], -0.25)
			else:
				_coast_distance[i] = maxf(_coast_distance[i], 0.25)
			if x == 0 or y == 0 or x == _data_rect.size.x - 1 or y == _data_rect.size.y - 1:
				_coast_distance[i] = OPEN_SEA


## Each cell becomes a weighted average of itself and its 8 neighbours (edges are left as they are).
func _blurred(d: PackedFloat32Array) -> PackedFloat32Array:
	var w := _data_rect.size.x
	var out := d.duplicate()
	for y in range(1, _data_rect.size.y - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var sides := d[i - 1] + d[i + 1] + d[i - w] + d[i + w]
			var corners := d[i - w - 1] + d[i - w + 1] + d[i + w - 1] + d[i + w + 1]
			out[i] = (d[i] * 4.0 + sides * 2.0 + corners) / 16.0
	return out


func _distance_at(cell: Vector2i) -> float:
	var p := cell - _data_rect.position
	return _coast_distance[p.y * _data_rect.size.x + p.x]


## For every cell of _data_rect, the distance to the nearest land cell (or, with from_land
## false, the nearest sea cell). Two sweeps across the grid, each passing distances to neighbours.
func _spread_distance(from_land: bool) -> PackedFloat32Array:
	const DIAGONAL := 1.4142
	var w := _data_rect.size.x
	var h := _data_rect.size.y
	var d := PackedFloat32Array()
	d.resize(w * h)
	for y in h:
		for x in w:
			var land := _land.has(_data_rect.position + Vector2i(x, y))
			d[y * w + x] = 0.0 if land == from_land else 1.0e6
	for y in h:  # top-left to bottom-right
		for x in w:
			var i := y * w + x
			if x > 0:
				d[i] = minf(d[i], d[i - 1] + 1.0)
			if y > 0:
				d[i] = minf(d[i], d[i - w] + 1.0)
				if x > 0:
					d[i] = minf(d[i], d[i - w - 1] + DIAGONAL)
				if x < w - 1:
					d[i] = minf(d[i], d[i - w + 1] + DIAGONAL)
	for y in range(h - 1, -1, -1):  # bottom-right back to top-left
		for x in range(w - 1, -1, -1):
			var i := y * w + x
			if x < w - 1:
				d[i] = minf(d[i], d[i + 1] + 1.0)
			if y < h - 1:
				d[i] = minf(d[i], d[i + w] + 1.0)
				if x < w - 1:
					d[i] = minf(d[i], d[i + w + 1] + DIAGONAL)
				if x > 0:
					d[i] = minf(d[i], d[i + w - 1] + DIAGONAL)
	return d


func _setup_shader() -> void:
	# Data texture: red = distance to the coast, green = how sandy the coast is here.
	var data := Image.create_empty(_data_rect.size.x, _data_rect.size.y, false, Image.FORMAT_RGH)
	for y in _data_rect.size.y:
		for x in _data_rect.size.x:
			var cell := _data_rect.position + Vector2i(x, y)
			data.set_pixel(x, y, Color(_distance_at(cell), _beach_at(cell), 0.0))
	# A tileable cloudy pattern the shader reuses at different scales for grass, rock and ripples.
	var pattern := FastNoiseLite.new()
	pattern.seed = int(_settings.seed)
	pattern.frequency = 0.03
	var noise_image := pattern.get_seamless_image(256, 256)
	noise_image.generate_mipmaps()

	var mat := ShaderMaterial.new()
	mat.shader = IslandShader
	mat.set_shader_parameter("terrain", ImageTexture.create_from_image(data))
	mat.set_shader_parameter("terrain_origin", Vector2(_data_rect.position))
	mat.set_shader_parameter("terrain_size", Vector2(_data_rect.size))
	mat.set_shader_parameter("noise", ImageTexture.create_from_image(noise_image))
	mat.set_shader_parameter("plot_rect", Vector4(0, 0, plot_size.x, plot_size.y))
	mat.set_shader_parameter("tile_px", Vector2(Iso.TILE_W, Iso.TILE_H))
	mat.set_shader_parameter("shadow_px", Iso.SHADOW)
	mat.set_shader_parameter("sun_dir", -Iso.to_cell_f(Iso.SHADOW).normalized())
	mat.set_shader_parameter("cliff_px", CLIFF_PX)
	mat.set_shader_parameter("beach_px", BEACH_PX)
	material = mat


func _draw() -> void:
	# One big rectangle; the shader paints the whole island and sea inside it.
	draw_rect(world_bounds().grow(3000), Color.WHITE)
