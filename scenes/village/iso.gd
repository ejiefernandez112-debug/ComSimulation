class_name Iso
## Isometric grid math: converts between grid cells (x, y) and on-screen world positions.
## Every visual that sits on the grid uses these, so tiles, buildings and taps always line up.

## Size of one tile diamond in pixels (2:1 is the classic isometric ratio). Art should match this.
const TILE_W := 64.0
const TILE_H := 32.0

## Where shadows fall on screen, per pixel of an object's height. The sun shines from the upper
## left (plan.md §4 look rules); the island shader and every object use this, so all shadows agree.
const SHADOW := Vector2(0.9, 0.11)


## Centre of a cell on screen. Accepts fractions too (e.g. -0.5 gives a cell's corner).
static func to_world(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * TILE_W / 2.0, (cell.x + cell.y) * TILE_H / 2.0)


## Which cell a screen point falls in.
static func to_cell(world: Vector2) -> Vector2i:
	return Vector2i(to_cell_f(world).round())


## Like to_cell, but keeps the fraction (where inside the cell the point is).
static func to_cell_f(world: Vector2) -> Vector2:
	return Vector2(world.x / TILE_W + world.y / TILE_H, world.y / TILE_H - world.x / TILE_W)


## The 4 corners of a cell's diamond: top, right, bottom, left.
static func diamond(cell: Vector2i, lift := 0.0) -> PackedVector2Array:
	return diamond_at(to_world(Vector2(cell)), lift)


## The outline of a size x size square of tiles whose top tile is `cell` (a 2x2 building's
## footprint): top, right, bottom, left corners.
static func square(cell: Vector2i, size: int) -> PackedVector2Array:
	var c := Vector2(cell)
	var far := size - 0.5
	return PackedVector2Array([to_world(c + Vector2(-0.5, -0.5)), to_world(c + Vector2(far, -0.5)),
		to_world(c + Vector2(far, far)), to_world(c + Vector2(-0.5, far))])


## The same diamond around any screen point (e.g. a building's position), raised by `lift` pixels.
static func diamond_at(center: Vector2, lift := 0.0) -> PackedVector2Array:
	var c := center - Vector2(0, lift)
	return PackedVector2Array([
		c + Vector2(0, -TILE_H / 2.0),
		c + Vector2(TILE_W / 2.0, 0),
		c + Vector2(0, TILE_H / 2.0),
		c + Vector2(-TILE_W / 2.0, 0),
	])
