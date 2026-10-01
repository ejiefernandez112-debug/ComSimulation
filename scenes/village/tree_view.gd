extends Node2D
## PLACEHOLDER tree drawn with shaded shapes until real tree sprites exist (plan.md §4, visual
## step 2). Its position is the foot of the trunk, so the Objects layer sorts it by how low on
## screen it stands. Purely decoration: trees are not part of the game state (yet).

const TRUNK := Color("6b4a2f")
const LEAVES := Color("3f7f33")
const NEEDLES := Color("2e6b3c")

var pine := false
var size := 1.0


func _draw() -> void:
	draw_rect(Rect2(Vector2(-2, -12) * size, Vector2(4, 12) * size), TRUNK)
	if pine:
		_draw_pine()
	else:
		_draw_round()


## Shadow on the ground under the leaves, pushed away from the sun. Called by the Shadows layer.
func draw_shadow(layer: Node2D) -> void:
	var height := 30.0 * size
	layer.blob(position + Iso.SHADOW * height * 0.45, Vector2(34, 14) * size)


func _draw_round() -> void:
	var c := Vector2(0, -24) * size
	var r := 11.0 * size
	# Shadowed clumps behind, the main crown, then sunlit layers toward the upper left.
	draw_circle(c + Vector2(7, 5) * size, r * 0.75, LEAVES.darkened(0.35), true, -1.0, true)
	draw_circle(c + Vector2(-7, 5) * size, r * 0.7, LEAVES.darkened(0.2), true, -1.0, true)
	draw_circle(c, r, LEAVES, true, -1.0, true)
	draw_circle(c + Vector2(-3, -3) * size, r * 0.68, LEAVES.lightened(0.15), true, -1.0, true)
	draw_circle(c + Vector2(-5, -6) * size, r * 0.32, LEAVES.lightened(0.35), true, -1.0, true)


func _draw_pine() -> void:
	for i in 3:  # three layers of branches, widest at the bottom
		var base_y := (-8.0 - i * 9.0) * size
		var half := (11.0 - i * 2.5) * size
		var left := Vector2(-half, base_y)
		var right := Vector2(half, base_y)
		var front := Vector2(0, base_y + 3.0 * size)
		var tip := Vector2(0, base_y - 16.0 * size)
		draw_colored_polygon(PackedVector2Array([left, front, tip]), NEEDLES.lightened(0.12))  # sunny side
		draw_colored_polygon(PackedVector2Array([front, right, tip]), NEEDLES.darkened(0.3))
		draw_polyline(PackedVector2Array([left, tip, right, front, left]), NEEDLES.darkened(0.45), 1.0, true)
