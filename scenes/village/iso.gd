class_name Iso
## Isometric grid math: converts between grid cells (x, y) and on-screen world positions.
## Every visual that sits on the grid uses these, so tiles, buildings and taps always line up.

## Size of one tile diamond in pixels (2:1 is the classic isometric ratio). Art should match this.
const TILE_W := 64.0
const TILE_H := 32.0


## Centre of a cell on screen. Accepts fractions too (e.g. -0.5 gives a cell's corner).
static func to_world(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE_W / 2.0, (cell.x + cell.y) * TILE_H / 2.0)


## Which cell a screen point falls in.
static func to_cell(world: Vector2) -> Vector2i:
	var fx := (world.x / (TILE_W / 2.0) + world.y / (TILE_H / 2.0)) / 2.0
	var fy := (world.y / (TILE_H / 2.0) - world.x / (TILE_W / 2.0)) / 2.0
	return Vector2i(roundi(fx), roundi(fy))


## The 4 corners of a cell's diamond: top, right, bottom, left.
static func diamond(cell: Vector2i, lift := 0.0) -> PackedVector2Array:
	var c := to_world(Vector2(cell)) - Vector2(0, lift)
	return PackedVector2Array([
		c + Vector2(0, -TILE_H / 2.0),
		c + Vector2(TILE_W / 2.0, 0),
		c + Vector2(0, TILE_H / 2.0),
		c + Vector2(-TILE_W / 2.0, 0),
	])
