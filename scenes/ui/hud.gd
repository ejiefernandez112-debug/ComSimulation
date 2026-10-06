extends Control
## The always-on HUD: a dark glass strip in the top-right corner with the village's key numbers
## (cash, people, happiness, warehouse), a small glass chip under it for each item in the warehouse,
## and short messages ("toasts") at the top. Shows numbers from Economy; decides nothing itself.
## (The menu buttons live in the bottom toolbar, menu_bar.gd.)

signal happiness_pressed  # the happiness block was tapped: main.gd shows the breakdown

const MARGIN := 12  # space between the strip and the screen's edges
const BAR_WIDTH := 76.0  # the small fill bars under the numbers
const TOAST_TOP := 76  # messages appear below the strip

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
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, TOAST_TOP)
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)
	Economy.changed.connect(_refresh)
	_refresh()


## A short message at the top of the screen that fades away. Bad news gets a red warning sign.
func toast(text: String, bad := false) -> void:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "HudPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pill.add_child(row)
	var mark := UITheme.icon_rect("alert" if bad else "info", 22)
	mark.modulate = UITheme.BAD if bad else UITheme.ACCENT_HIGH
	row.add_child(mark)
	var label := UITheme.label(text)
	if bad:
		label.add_theme_color_override("font_color", UITheme.BAD)
	row.add_child(label)
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
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	# The strip: [cash] | [people] | [happiness] | [warehouse], with thin lines between them.
	var strip := PanelContainer.new()
	strip.theme_type_variation = "HudBar"
	column.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)
	var cash := _block(row, "cash", "", "Cash")
	_cash = cash.label
	_cash.add_theme_font_size_override("font_size", UITheme.SIZE_HEADING)
	var pop := _block(row, "population", "BlueBar", "People living here / room in homes")
	_population = pop.label
	_population_bar = pop.bar
	var mood := _block(row, "happiness", "GreenBar", "Village happiness: tap to see why")
	_happiness = mood.label
	_happiness_bar = mood.bar
	# The only block that reacts to a tap: it opens the breakdown (Food, Jobs, move-in speed).
	mood.block.mouse_filter = Control.MOUSE_FILTER_STOP
	mood.block.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mood.block.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			happiness_pressed.emit())
	var store := _block(row, "warehouse", "BrownBar", "Goods in the warehouse / room")
	_warehouse = store.label
	_warehouse_bar = store.bar
	# One chip per item (from data/resources.json), so new resources appear automatically. They
	# wrap onto more rows under the strip, lined up on the right.
	var chips := HFlowContainer.new()
	chips.alignment = FlowContainer.ALIGNMENT_END
	chips.add_theme_constant_override("h_separation", 4)
	chips.add_theme_constant_override("v_separation", 4)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(chips)
	for resource_id in GameData.resources:
		var chip := PanelContainer.new()
		chip.theme_type_variation = "HudPill"
		chip.tooltip_text = GameData.resources[resource_id].name
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(line)
		line.add_child(UITheme.icon_rect(resource_id, 22))
		var amount := UITheme.label("", "SmallLabel")
		amount.add_theme_color_override("font_color", UITheme.TEXT)
		line.add_child(amount)
		chips.add_child(chip)
		_items[resource_id] = amount
	column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN


## One block of the strip: an icon, the number and (when `bar_style` isn't "") a thin fill bar
## under it. A thin line separates it from the block before. Returns {"block", "label", "bar"}.
func _block(row: HBoxContainer, icon_name: String, bar_style: String, tip: String) -> Dictionary:
	if row.get_child_count() > 0:
		var line := ColorRect.new()
		line.color = UITheme.EDGE
		line.custom_minimum_size = Vector2(1, 26)
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(line)
	var block := HBoxContainer.new()
	block.add_theme_constant_override("separation", 8)
	block.mouse_filter = Control.MOUSE_FILTER_PASS  # shows the tooltip; the strip takes the click
	block.tooltip_text = tip
	row.add_child(block)
	var icon := UITheme.icon_rect(icon_name, 22)
	icon.modulate = UITheme.TEXT_DIM
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_child(icon)
	var numbers := VBoxContainer.new()
	numbers.add_theme_constant_override("separation", 3)
	numbers.alignment = BoxContainer.ALIGNMENT_CENTER
	numbers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(numbers)
	var label := UITheme.label("", "HeadingLabel")
	label.add_theme_font_size_override("font_size", UITheme.SIZE_BODY)
	numbers.add_child(label)
	var bar: ProgressBar = null
	if bar_style != "":
		bar = ProgressBar.new()
		bar.theme_type_variation = bar_style
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(BAR_WIDTH, 4)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		numbers.add_child(bar)
	return {"block": block, "label": label, "bar": bar}


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
	_population.text = "%s / %s" % [UITheme.number(pop), UITheme.number(pop_cap)]
	_population_bar.value = 100.0 * pop / maxf(pop_cap, 1)
	var happy := Economy.happiness()
	_happiness.text = "%d%%" % int(happy.percent)  # rounded down, like the bands
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
		var qty := int(Economy.state.inventory.get(resource_id, 0))
		_items[resource_id].text = UITheme.number(qty)
		# Many kinds of goods: only those in stock get a chip (chip > row > amount label).
		_items[resource_id].get_parent().get_parent().visible = qty > 0


## Cash counts smoothly towards the new amount, like coins pouring in.
func _show_cash(value: float) -> void:
	_shown_cash = value
	_cash.text = UITheme.money(roundi(value))
	# In debt (wages can take cash below 0): show it in red.
	UITheme.set_font_color(_cash, UITheme.BAD if value < 0.0 else UITheme.TEXT)
