extends Node2D
## Soft shadows on the ground under buildings and trees. They are drawn in one layer underneath
## all objects, so a shadow never darkens a building or tree itself. Each object decides the shape
## of its own shadow (its draw_shadow function calls blob or cast below).

const COLOR := Color(0.03, 0.08, 0.12, 0.32)

## The node holding the buildings and trees (set by the village).
var objects: Node2D

var _soft_spot := GradientTexture2D.new()


func _ready() -> void:
	# A round spot that fades from shadow colour in the middle to clear at the edge.
	var fade := Gradient.new()
	fade.set_color(0, COLOR)
	fade.set_color(1, Color(COLOR, 0.0))
	_soft_spot.gradient = fade
	_soft_spot.fill = GradientTexture2D.FILL_RADIAL
	_soft_spot.fill_from = Vector2(0.5, 0.5)
	_soft_spot.fill_to = Vector2(1.0, 0.5)


func _draw() -> void:
	for object in objects.get_children():
		object.draw_shadow(self)


## A soft oval shadow, e.g. under a tree's leaves.
func blob(center: Vector2, size: Vector2) -> void:
	draw_texture_rect(_soft_spot, Rect2(center - size / 2.0, size), false)


## The shadow of something solid: `footprint` is its outline on the ground, `height` how tall it is.
func cast(footprint: PackedVector2Array, height: float) -> void:
	var points := footprint.duplicate()
	for p in footprint:
		points.append(p + Iso.SHADOW * height)
	var outline := Geometry2D.convex_hull(points)
	outline.remove_at(outline.size() - 1)  # the hull repeats its first point at the end
	# Soft edge: two slightly bigger, fainter copies underneath the main shape.
	for grow in [4.0, 2.0]:
		for ring in Geometry2D.offset_polygon(outline, grow, Geometry2D.JOIN_ROUND):
			draw_colored_polygon(ring, Color(COLOR, COLOR.a * 0.35))
	draw_colored_polygon(outline, Color(COLOR, COLOR.a * 0.6))
