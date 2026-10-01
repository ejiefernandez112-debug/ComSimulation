class_name RoundButton
extends VBoxContainer
## A round, glossy Clash-of-Clans-style button with an icon and a caption underneath, used in the
## building action bar and as small icon buttons (close, menu). It squishes when pressed.

signal pressed

var button := TextureButton.new()
var _icon := TextureRect.new()
var _caption := Label.new()
var _color := "blue"


static func make(color: String, icon_name: String, caption := "", diameter := 84.0) -> RoundButton:
	var b := RoundButton.new()
	b._color = color
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the round button itself catches clicks
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_theme_constant_override("separation", 0)
	b.button.custom_minimum_size = Vector2(diameter, diameter)
	b.button.ignore_texture_size = true
	b.button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_child(b.button)
	# The icon sits on the button's face (a little above centre, clear of the darker lip).
	b._icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b._icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	b._icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b._icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	var inset := diameter * 0.22
	b._icon.offset_left = inset
	b._icon.offset_right = -inset
	b._icon.offset_top = inset * 0.8
	b._icon.offset_bottom = -inset * 1.2
	b.button.add_child(b._icon)
	b._caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b._caption.add_theme_font_size_override("font_size", 16)
	b._caption.visible = caption != ""
	b.add_child(b._caption)
	b.set_icon(icon_name)
	b.set_caption(caption)
	b._apply_color()
	b.button.pressed.connect(b._on_pressed)
	b.button.button_down.connect(func(): b._squish(0.9))
	b.button.button_up.connect(func(): b._squish(1.0))
	b.button.mouse_entered.connect(func(): b.button.self_modulate = Color(1.1, 1.1, 1.1))
	b.button.mouse_exited.connect(func(): b.button.self_modulate = Color.WHITE)
	return b


func set_icon(icon_name: String) -> void:
	_icon.texture = UITheme.icon(icon_name)


func set_caption(text: String) -> void:
	_caption.text = text
	_caption.visible = text != ""


func set_color(color: String) -> void:
	_color = color
	_apply_color()


func set_disabled(disabled: bool) -> void:
	button.disabled = disabled
	_icon.modulate = Color(1, 1, 1, 0.55) if disabled else Color.WHITE


func _apply_color() -> void:
	button.texture_normal = load(UITheme.SKINS + "round_%s.svg" % _color)
	button.texture_disabled = load(UITheme.SKINS + "round_grey.svg")


func _on_pressed() -> void:
	pressed.emit()


func _squish(amount: float) -> void:
	button.pivot_offset = button.size / 2.0
	create_tween().tween_property(button, "scale", Vector2.ONE * amount, 0.08)
