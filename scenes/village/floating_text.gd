extends Node2D
## A "+32 [icon]" that rises from a building and fades away, e.g. when goods are collected
## (or "-40 [icon]" in red when a job uses them up). Removes itself when done.

var text := ""
var icon: Texture2D
var color := Color.WHITE

const SIZE := 24
const ICON := 28.0


func _ready() -> void:
	z_index = 6  # above buildings and bubbles
	var rise := create_tween().set_parallel()
	rise.tween_property(self, "position:y", position.y - 50, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_property(self, "modulate:a", 0.0, 0.45).set_delay(0.75)
	rise.chain().tween_callback(queue_free)


func _draw() -> void:
	var font := UITheme.font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	var x := -(width + 4 + ICON) / 2.0
	draw_string_outline(font, Vector2(x, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 8, UITheme.OUTLINE)
	draw_string(font, Vector2(x, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, color)
	if icon:
		draw_texture_rect(icon, Rect2(x + width + 4, -ICON / 2.0 - 1, ICON, ICON), false)
