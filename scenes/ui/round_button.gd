class_name RoundButton
extends VBoxContainer
## A square glass tile with an icon, and optionally a caption under the icon: the building card's
## action buttons and small icon buttons (close ✕, ✓). (The name is from the round cartoon buttons
## these replaced; the functions stayed the same, so the screens that use them didn't change.)
## style is one of the button looks in ui_theme.gd: "Button" (normal), "GoButton" (go, collect),
## "DangerButton" (can't be undone), "BackButton" (can't do it yet) or "IconButton" (no box).
## Sizes: UITheme.ROUND_ACTION_SIZE (with a caption) or UITheme.ROUND_ICON_SIZE (icon only).

signal pressed

var button := Button.new()
var _icon := TextureRect.new()
var _caption := Label.new()
var _side := 0.0  # the tile's height (and its width when it has no caption)


static func make(style: String, icon_name: String, caption := "", side := UITheme.ROUND_ACTION_SIZE) -> RoundButton:
	var b := RoundButton.new()
	b._side = side
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the tile itself catches clicks
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.button.custom_minimum_size = Vector2(side, side)
	b.button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_child(b.button)
	# The icon and the caption, stacked in the middle of the tile.
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 3)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.button.add_child(stack)
	var icon_side := roundf(side * (0.5 if caption == "" else 0.38))
	b._icon.custom_minimum_size = Vector2(icon_side, icon_side)
	b._icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	b._icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	b._icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b._icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(b._icon)
	b._caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b._caption.add_theme_font_override("font", UITheme.bold_font())
	b._caption.add_theme_font_size_override("font_size", UITheme.SIZE_SMALL)
	b._caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(b._caption)
	b.set_icon(icon_name)
	b.set_caption(caption)
	b.set_style(style)
	b.button.pressed.connect(b._on_pressed)
	return b


func set_icon(icon_name: String) -> void:
	_icon.texture = UITheme.icon(icon_name)


## The caption under the icon; the tile grows wider when the words need it.
func set_caption(text: String) -> void:
	if text == _caption.text and _caption.visible == (text != ""):
		return
	_caption.text = text
	_caption.visible = text != ""
	var words := UITheme.bold_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.SIZE_SMALL).x
	button.custom_minimum_size.x = maxf(_side * 1.25, ceilf(words) + 24.0) if text != "" else _side


## Changes the tile's look (one of the styles listed at the top).
func set_style(style: String) -> void:
	if button.theme_type_variation == style:
		return
	button.theme_type_variation = style
	# Captions are white on filled tiles and grey on plain ones, like the buttons' text.
	UITheme.set_font_color(_caption, UITheme.TEXT_DIM if style in ["BackButton", "IconButton"] else UITheme.TEXT)


func set_disabled(disabled: bool) -> void:
	button.disabled = disabled
	_icon.modulate.a = 0.4 if disabled else 1.0
	_caption.modulate.a = 0.4 if disabled else 1.0


func _on_pressed() -> void:
	pressed.emit()
