class_name ModalWindow
extends Control
## A pop-up window over the game: dims the map, shows a cream panel with a title and a red close
## button, and pops in with a little bounce. Wide screens get a centred window; tall (phone)
## screens get a sheet along the bottom (plan.md §6). BuildingPanel and SettingsPanel build on
## this: they fill `content` with their own rows.

signal closed

const WIDTH := 540.0
const SHEET_TOP := 0.35  # on tall screens the sheet covers the bottom 65%
## For this long after opening, tapping outside doesn't close the window: a quick second tap (a
## double-tap on the building that opened it) would otherwise shut it straight away.
const IGNORE_OUTSIDE_TAPS_MS := 300

var content: VBoxContainer
var _opened_at_ms := 0  # when the window last opened (milliseconds since the game started)
var _title: Label
var _window: PanelContainer
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)  # tapping outside the window closes it
	add_child(dim)
	_window = PanelContainer.new()
	add_child(_window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_window.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 32)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title)
	var close_button := RoundButton.make("red", "close", "", 52)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	# The rows scroll if the screen is too short to show them all.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	hide()
	resized.connect(_layout)


func open(title_text: String) -> void:
	_title.text = title_text
	_opened_at_ms = Time.get_ticks_msec()
	show()
	_layout()
	_layout.call_deferred()  # again once new text has been measured
	_window.pivot_offset = _window.size / 2.0
	_window.scale = Vector2(0.8, 0.8)
	_window.modulate.a = 0.0
	var pop := create_tween().set_parallel()
	pop.tween_property(_window, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_window, "modulate:a", 1.0, 0.12)


func close() -> void:
	if visible:
		hide()
		closed.emit()


## Empties `content`, ready to be filled again.
func clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)  # out right away, so the window's size is measured without it
		child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _opened_at_ms >= IGNORE_OUTSIDE_TAPS_MS:
			close()


func _layout() -> void:
	if not visible:
		return
	var tall := size.x < size.y
	# As tall as the rows need, but no taller than the screen allows (then they scroll).
	var room := size.y * (1.0 - SHEET_TOP if tall else 0.94) - 110.0  # minus title and window edges
	_scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, room)
	_window.reset_size()
	if tall:
		# Tall screen (phone held upright): sheet across the bottom.
		_window.custom_minimum_size.x = 0
		_window.set_anchors_preset(Control.PRESET_FULL_RECT)
		_window.anchor_top = SHEET_TOP
		_window.offset_left = 0
		_window.offset_right = 0
		_window.offset_top = 0
		_window.offset_bottom = 0
	else:
		# Wide screen (PC / landscape): a window in the middle.
		_window.custom_minimum_size.x = WIDTH
		_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		_window.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_window.grow_vertical = Control.GROW_DIRECTION_BOTH
