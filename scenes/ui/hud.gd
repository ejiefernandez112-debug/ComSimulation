extends Control
## The always-on HUD, Clash-of-Clans style: resource bars in the top-right corner (cash,
## population, happiness, warehouse) with a chip for each item in the warehouse, and short
## messages ("toasts") at the top. Shows numbers from Economy; decides nothing itself.
## (The menu buttons live in the bottom menu bar, menu_bar.gd.)

signal happiness_pressed  # the happiness row was tapped: main.gd shows the breakdown

const ROW_WIDTH := 236.0

var _cash: Label
var _shown_cash := NAN  # what the cash label shows (NAN = nothing yet); it counts up/down to the real amount
var _cash_tween: Tween
var _population: Label
var _population_bar: ProgressBar
var _happiness: Label
var _happiness_bar: ProgressBar
var _warehouse: Label
var _warehouse_bar: ProgressBar
var _items := {}  # resource id -> its Label in the item chips
var _toast_box: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_resources()
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 18)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)
	Economy.changed.connect(_refresh)
	_refresh()


## A short message at the top of the screen that fades away. Bad news is tinted red.
func toast(text: String, bad := false) -> void:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "HudPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	if bad:
		label.add_theme_color_override("font_color", UITheme.BAD)
	pill.add_child(label)
	_toast_box.add_child(pill)
	if _toast_box.get_child_count() > 3:
		_toast_box.get_child(0).queue_free()
	var fade := create_tween()
	fade.tween_interval(1.8)
	fade.tween_property(pill, "modulate:a", 0.0, 0.5)
	fade.tween_callback(pill.queue_free)


func _build_resources() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var cash := _resource_row(column, "cash", "")
	_cash = cash.label
	var pop := _resource_row(column, "population", "BlueBar")
	_population = pop.label
	_population_bar = pop.bar
	var mood := _resource_row(column, "happiness", "GreenBar")
	_happiness = mood.label
	_happiness_bar = mood.bar
	# The only HUD row that reacts to a tap: it opens the breakdown (Food, Jobs, move-in speed).
	mood.row.mouse_filter = Control.MOUSE_FILTER_STOP
	mood.row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mood.row.tooltip_text = "Village happiness: tap to see why"
	mood.row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			happiness_pressed.emit())
	var store := _resource_row(column, "warehouse", "BrownBar")
	_warehouse = store.label
	_warehouse_bar = store.bar
	# One chip per item (from data/resources.json), so new resources appear automatically.
	var chips := HFlowContainer.new()
	chips.alignment = FlowContainer.ALIGNMENT_END
	chips.custom_minimum_size.x = ROW_WIDTH
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(chips)
	for resource_id in GameData.resources:
		var chip := PanelContainer.new()
		chip.theme_type_variation = "HudPill"
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.tooltip_text = GameData.resources[resource_id].name
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		chip.add_child(row)
		row.add_child(_icon_rect(UITheme.icon(resource_id), 26))
		var amount := Label.new()
		amount.add_theme_font_size_override("font_size", 17)
		row.add_child(amount)
		chips.add_child(chip)
		_items[resource_id] = amount


## One HUD row: a dark pill holding the number (and a fill bar), with the icon overlapping its
## right end. Returns {"row", "label", "bar"}; bar is null when `bar_style` is "".
func _resource_row(parent: Control, icon_name: String, bar_style: String) -> Dictionary:
	var row := Control.new()
	row.custom_minimum_size = Vector2(ROW_WIDTH, 46)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var pill := PanelContainer.new()
	pill.theme_type_variation = "HudPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.position = Vector2(0, 6)
	pill.size = Vector2(ROW_WIDTH - 24, 34)
	row.add_child(pill)
	var bar: ProgressBar = null
	if bar_style != "":
		bar = ProgressBar.new()
		bar.theme_type_variation = bar_style
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(6, 26)
		bar.size = Vector2(ROW_WIDTH - 52, 9)
		row.add_child(bar)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(8, 2)
	label.size = Vector2(ROW_WIDTH - 66, 30 if bar else 40)
	label.add_theme_font_size_override("font_size", 21 if bar else 24)
	row.add_child(label)
	var icon := _icon_rect(UITheme.icon(icon_name), 46)
	icon.position = Vector2(ROW_WIDTH - 46, 0)
	row.add_child(icon)
	return {"row": row, "label": label, "bar": bar}


func _icon_rect(texture: Texture2D, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _refresh() -> void:
	var cash := Economy.currency()
	if is_nan(_shown_cash):
		_shown_cash = cash
	if roundi(_shown_cash) != cash:
		if _cash_tween:
			_cash_tween.kill()
		_cash_tween = create_tween()
		_cash_tween.tween_method(_show_cash, _shown_cash, float(cash), 0.5)
	else:
		_show_cash(cash)
	var pop := Economy.population()
	var pop_cap := Economy.population_capacity()
	_population.text = "%d / %d" % [pop, pop_cap]
	_population_bar.value = 100.0 * pop / maxf(pop_cap, 1)
	var happy := Economy.happiness()
	_happiness.text = "%d%% happy" % roundi(100.0 * float(happy.score))
	_happiness_bar.value = 100.0 * float(happy.score)
	# Green: babies come at normal speed or faster; gold: slower; red: no babies, or people are
	# leaving the island.
	var speed := float(happy.growth_speed)
	var leaving := float(happy.get("leave_per_hour", 0.0)) > 0.0
	_happiness_bar.theme_type_variation = "RedBar" if leaving or speed <= 0.0 else ("GreenBar" if speed >= 1.0 else "GoldBar")
	var stored := Economy.warehouse_total()
	var cap := Economy.warehouse_cap()
	_warehouse.text = "%s / %s" % [UITheme.number(stored), UITheme.number(cap)]
	_warehouse_bar.value = 100.0 * stored / maxf(cap, 1)
	for resource_id in _items:
		_items[resource_id].text = UITheme.number(int(Economy.state.inventory.get(resource_id, 0)))


## Cash counts smoothly towards the new amount, like coins pouring in.
func _show_cash(value: float) -> void:
	_shown_cash = value
	_cash.text = UITheme.money(roundi(value))
	# In debt (wages can take cash below 0): show it in red.
	_cash.add_theme_color_override("font_color", UITheme.BAD if value < 0.0 else UITheme.TEXT)
