extends Node2D
## PLACEHOLDER tree drawn with shaded shapes until real tree sprites exist (plan.md §4, visual
## step 2). Its position is the foot of the trunk, so the Objects layer sorts it by how low on
## screen it stands. Purely decoration: trees are not part of the game state (yet).
##
## Speed (plan.md §9.1): drawing a tree out of circles and triangles costs the graphics chip about
## 14 separate jobs ("draw calls"), ~1,500 for the island, which made it the slowest part of the
## game. So at start-up each kind of tree is drawn ONCE into a shared picture (bake_picture), and
## from then on every tree just shows its part of that picture: the graphics chip can then draw
## all the trees together in a few jobs. Same look; until the picture is ready (a frame or two at
## start-up) trees draw their shapes as before.

const TRUNK := Color("6b4a2f")
const LEAVES := Color("3f7f33")
const NEEDLES := Color("2e6b3c")
## The picture is drawn this many times bigger than a size-1 tree, so trees stay sharp at the
## closest zoom on high-resolution phone screens.
const BAKE_SCALE := 3.0
## Each kind's box around the foot of its trunk, for a size-1 tree (with room for the soft edges).
const ROUND_BOX := Rect2(-17, -37, 34, 38)
const PINE_BOX := Rect2(-13, -44, 26, 45)

## Both kinds side by side (round on the left, pine on the right), or null until it's ready.
static var _picture: Texture2D
## The picture's soft edges are stored "premultiplied" (that's how Godot draws onto a see-through
## background), so trees show it with the matching blend mode, or their edges would look dark.
static var _blend: CanvasItemMaterial

var pine := false
var size := 1.0


func _ready() -> void:
	add_to_group("placeholder_trees")
	if _picture:
		use_picture()


func _draw() -> void:
	if _picture:
		var box := PINE_BOX if pine else ROUND_BOX
		draw_texture_rect_region(_picture, Rect2(box.position * size, box.size * size), _region(pine))
	else:
		paint(self, Vector2.ZERO, pine, size)


## Switch from drawing shapes to showing the shared picture.
func use_picture() -> void:
	material = _blend
	queue_redraw()


## Shadow on the ground under the leaves, pushed away from the sun. Called by the Shadows layer.
func draw_shadow(layer: Node2D) -> void:
	var height := 30.0 * size
	layer.blob(position + Iso.SHADOW * height * 0.45, Vector2(34, 14) * size)


## Draws the shared picture once (the village calls this after planting its trees). Takes a frame:
## the shapes are painted into a hidden see-through canvas, which is then copied into a picture.
static func bake_picture(host: Node) -> void:
	if _picture:
		return
	var canvas := SubViewport.new()
	canvas.transparent_bg = true
	canvas.disable_3d = true
	canvas.size = Vector2i(_region(true).end.ceil())
	canvas.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Node2D.new()
	painter.draw.connect(func():
		for kind_is_pine in [false, true]:
			var box := PINE_BOX if kind_is_pine else ROUND_BOX
			# Scale up, then move the box's top-left corner to its place in the picture.
			painter.draw_set_transform(_region(kind_is_pine).position - box.position * BAKE_SCALE, 0.0, Vector2.ONE * BAKE_SCALE)
			paint(painter, Vector2.ZERO, kind_is_pine, 1.0))
	canvas.add_child(painter)
	host.add_child(canvas)
	await RenderingServer.frame_post_draw
	if not is_instance_valid(canvas):
		return  # the village closed before the picture was made
	var image := canvas.get_texture().get_image()
	canvas.queue_free()
	if image == null or image.is_empty():
		return  # couldn't read it back: the trees just keep drawing their shapes
	image.generate_mipmaps()  # smaller copies, so far-away trees stay smooth instead of sparkling
	_blend = CanvasItemMaterial.new()
	_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_picture = ImageTexture.create_from_image(image)
	host.get_tree().call_group("placeholder_trees", "use_picture")


## Where each kind sits in the shared picture, in picture pixels.
static func _region(kind_is_pine: bool) -> Rect2:
	var round_size := ROUND_BOX.size * BAKE_SCALE
	if not kind_is_pine:
		return Rect2(Vector2.ZERO, round_size)
	return Rect2(Vector2(round_size.x + 2.0, 0.0), PINE_BOX.size * BAKE_SCALE)


## The tree's shapes, with the foot of the trunk at `at`.
static func paint(canvas: CanvasItem, at: Vector2, kind_is_pine: bool, s: float) -> void:
	canvas.draw_rect(Rect2(at + Vector2(-2, -12) * s, Vector2(4, 12) * s), TRUNK)
	if kind_is_pine:
		_paint_pine(canvas, at, s)
	else:
		_paint_round(canvas, at, s)


static func _paint_round(canvas: CanvasItem, at: Vector2, s: float) -> void:
	var c := at + Vector2(0, -24) * s
	var r := 11.0 * s
	# Shadowed clumps behind, the main crown, then sunlit layers toward the upper left.
	canvas.draw_circle(c + Vector2(7, 5) * s, r * 0.75, LEAVES.darkened(0.35), true, -1.0, true)
	canvas.draw_circle(c + Vector2(-7, 5) * s, r * 0.7, LEAVES.darkened(0.2), true, -1.0, true)
	canvas.draw_circle(c, r, LEAVES, true, -1.0, true)
	canvas.draw_circle(c + Vector2(-3, -3) * s, r * 0.68, LEAVES.lightened(0.15), true, -1.0, true)
	canvas.draw_circle(c + Vector2(-5, -6) * s, r * 0.32, LEAVES.lightened(0.35), true, -1.0, true)


static func _paint_pine(canvas: CanvasItem, at: Vector2, s: float) -> void:
	for i in 3:  # three layers of branches, widest at the bottom
		var base_y := (-8.0 - i * 9.0) * s
		var half := (11.0 - i * 2.5) * s
		var left := at + Vector2(-half, base_y)
		var right := at + Vector2(half, base_y)
		var front := at + Vector2(0, base_y + 3.0 * s)
		var tip := at + Vector2(0, base_y - 16.0 * s)
		canvas.draw_colored_polygon(PackedVector2Array([left, front, tip]), NEEDLES.lightened(0.12))  # sunny side
		canvas.draw_colored_polygon(PackedVector2Array([front, right, tip]), NEEDLES.darkened(0.3))
		canvas.draw_polyline(PackedVector2Array([left, tip, right, front, left]), NEEDLES.darkened(0.45), 1.0, true)
