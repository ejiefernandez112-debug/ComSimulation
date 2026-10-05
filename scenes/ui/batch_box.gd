class_name BatchBox
extends VBoxContainer
## A Farm, Mill or Bakery's batch (plan.md §5.1), inside its building window.
## Idle: choose the bonus (more units for higher wages) and how long it works: step the finish
## time an hour at a time, or All (as long as the ingredients and cash allow). The lines under it
## show what the batch makes and costs before the player starts it.
## With a batch: how far along it is, what's ready to collect, what's locked in, and Cancel.
## Shows numbers from Economy only; its buttons ask (signals) and main.gd acts.

signal start_requested(building_id: String, hours: int, bonus: String)
signal collect_requested(building_id: String)
signal cancel_requested(building_id: String)

const TITLES := {"units": "Makes:", "ingredients": "Ingredients:", "labor": "Labor (paid now):",
	"water": "Water (estimate):", "power": "Power (estimate):", "total": "Total cost:", "per_unit": "Cost per unit:", "price": "Sells for:"}

var building_id := ""
var _hours := 0  # the length chosen for the next batch (0 = not chosen yet: offer the default)
var _bonus := "none"  # the bonus chosen for the next batch
var _width := 400.0

# Idle: setting up the next batch.
var _setup: VBoxContainer
var _bonus_buttons := {}  # bonus level -> its Button
var _finish_text: Label
var _lines := {}  # TITLES key -> its value Label
var _start: Button
var _note: Label
# With a batch.
var _running: VBoxContainer
var _status: Label
var _progress: ProgressBar
var _ready_text: Label
var _collect: Button
var _locked: Label
var _cancel: Button


## Builds the box for this building. `width` = the window's text width (wrapped lines need it).
func setup(id: String, width: float) -> void:
	building_id = id
	_width = width
	add_theme_constant_override("separation", 6)
	_bonus = str(Economy.workers(Economy.building(id)).bonus)  # the last choice
	_hours = 0
	_build_setup()
	_build_running()


func _build_setup() -> void:
	_setup = VBoxContainer.new()
	_setup.add_theme_constant_override("separation", 6)
	add_child(_setup)
	# Bonus: paid on top of the minimum wage for the whole batch, for more units. Locked in once
	# the batch starts.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_setup.add_child(row)
	var title := _label("Bonus:", 18)
	title.custom_minimum_size.x = 70
	row.add_child(title)
	var wages: Dictionary = GameData.config.get("wage_bonuses", {})
	for level in wages:
		var extra := Economy.bonus_output(level)
		var button := Button.new()
		button.text = "None" if extra <= 0.0 else "+%d%%" % roundi(extra * 100.0)
		button.tooltip_text = "%s bonus: wages +%d%%, the batch makes +%d%% units" % [level.capitalize(), roundi(float(wages[level]) * 100.0), roundi(extra * 100.0)]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(func():
			_bonus = level
			refresh())
		row.add_child(button)
		_bonus_buttons[level] = button
	# How long: step the finish time an hour at a time, or All.
	var length := HBoxContainer.new()
	length.add_theme_constant_override("separation", 6)
	_setup.add_child(length)
	length.add_child(_step_button("−", -1, "One hour less"))
	_finish_text = _label("", 18)
	_finish_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_finish_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	length.add_child(_finish_text)
	length.add_child(_step_button("+", 1, "One hour more"))
	var all := Button.new()
	all.theme_type_variation = "BlueButton"
	all.text = "All"
	all.tooltip_text = "As long as your ingredients and cash allow"
	all.custom_minimum_size = Vector2(70, 44)
	all.add_theme_font_size_override("font_size", 17)
	all.pressed.connect(func():
		_hours = maxi(_most_hours(), 1)
		refresh())
	length.add_child(all)
	# What it makes and costs, before starting.
	for key in TITLES:
		_lines[key] = _figure_row(_setup, TITLES[key])
	_note = _wrapped("", 15)
	_setup.add_child(_note)
	_start = Button.new()
	_start.custom_minimum_size = Vector2(300, 56)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Greyed when it can't start, but still tappable, so the player is told why.
	_start.pressed.connect(func(): start_requested.emit(building_id, _hours, _bonus))
	_setup.add_child(_start)


func _build_running() -> void:
	_running = VBoxContainer.new()
	_running.add_theme_constant_override("separation", 6)
	add_child(_running)
	_status = _wrapped("", 18)
	_running.add_child(_status)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 16
	_running.add_child(_progress)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_running.add_child(row)
	_ready_text = _wrapped("", 17)
	_ready_text.custom_minimum_size.x = _width - 260
	_ready_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ready_text)
	_collect = Button.new()
	_collect.expand_icon = true
	_collect.custom_minimum_size = Vector2(190, 56)
	_collect.pressed.connect(func(): collect_requested.emit(building_id))
	row.add_child(_collect)
	_locked = _wrapped("", 15)
	_running.add_child(_locked)
	_cancel = Button.new()
	_cancel.theme_type_variation = "RedButton"
	_cancel.text = "Cancel batch"
	_cancel.icon = UITheme.icon("close")
	_cancel.expand_icon = true
	_cancel.custom_minimum_size = Vector2(190, 44)
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_cancel.add_theme_font_size_override("font_size", 16)
	_cancel.tooltip_text = "Stop it: the hours made are kept, part of the rest is given back"
	_cancel.pressed.connect(func(): cancel_requested.emit(building_id))
	_running.add_child(_cancel)


## Brings the box up to date (the building window calls this on every Economy change).
func refresh() -> void:
	var b := Economy.building(building_id)
	if b.is_empty():
		return
	var has := Economy.has_batch(b)
	_setup.visible = not has
	_running.visible = has
	if has:
		_refresh_running(b)
	else:
		_refresh_setup(b)


## True while it shows a batch (being made or waiting to be collected), false while setting one up.
func showing_batch() -> bool:
	return _running.visible


func _recipe_id(b: Dictionary) -> String:
	return str(BuildingInfo.recipe(b.type).get("id", ""))


func _most_hours() -> int:
	var b := Economy.building(building_id)
	return Economy.batch_max_hours(building_id, _recipe_id(b), _bonus)


func _refresh_setup(b: Dictionary) -> void:
	var most := _most_hours()
	var limit := Economy.batch_hours_limit()
	if _hours <= 0:  # first look: the usual length, or less if the stock and cash run out sooner
		_hours = mini(Economy.batch_default_hours(), most)
	_hours = clampi(_hours, 1, limit)
	for level in _bonus_buttons:
		_bonus_buttons[level].theme_type_variation = "YellowButton" if level == _bonus else "BlueButton"
	var q := Economy.batch_quote(b, _recipe_id(b), _hours, _bonus)
	if q.is_empty():
		return
	var real_hours := float(q.seconds) / 3600.0
	_finish_text.text = "%s h · %s" % [_amount(real_hours), "waits for workers" if is_inf(float(q.finishes_at)) else "done %s" % UITheme.clock(float(q.finishes_at), TimeService.now())]
	_lines.units.text = _amounts(q.units)
	var parts: Array[String] = []
	var ingredients := 0.0
	for line in q.ingredients:
		parts.append("%s %s" % [UITheme.number(int(line.qty)), BuildingInfo.resource_name(line.res)])
		ingredients += float(line.cost)
	_lines.ingredients.text = "%s · %s" % [", ".join(parts), UITheme.money(roundi(ingredients))] if not parts.is_empty() else "none"
	_lines.labor.text = "%d × %s/h × %s h = %s" % [int(q.workers), UITheme.dollars(float(q.wage_each)), _amount(real_hours), UITheme.money(int(q.wages))]
	_lines.water.text = UITheme.money(roundi(float(q.water)))
	_lines.power.text = UITheme.money(roundi(float(q.get("power", 0.0))))
	_lines.power.get_parent().visible = Economy.power_need(Economy.building(building_id)) > 0.0  # only Mills and Bakeries use power
	_lines.total.text = UITheme.money(roundi(float(q.total)))
	_lines.per_unit.text = UITheme.price(roundi(float(q.per_unit)))
	var profit := int(q.price) - roundi(float(q.per_unit))
	_lines.price.text = "%s each (%s %s)" % [UITheme.price(int(q.price)), UITheme.price(absi(profit)), "profit" if profit >= 0 else "loss"]
	var notes: Array[String] = []
	notes.append("Longest batch your stock and cash allow now: %d h." % most if most > 0 else "Not enough ingredients or cash for a batch yet.")
	if q.estimated:
		notes.append("Ingredients not in stock are priced at an estimate.")
	notes.append("Every finished hour adds its share; collect any time.")
	_note.text = " ".join(notes)
	var check := Economy.can_start_batch(building_id, _recipe_id(b), _hours, _bonus)
	_start.text = "Start %s h batch" % _amount(real_hours)
	_start.theme_type_variation = "YellowButton" if check.ok else "GreyButton"
	_start.tooltip_text = "Pays the ingredients and wages now" if check.ok else str(check.error)


func _refresh_running(b: Dictionary) -> void:
	var batch: Dictionary = b.batch
	var status := BuildingInfo.status(b)
	_status.text = status.text
	_progress.value = Economy.job_progress(b) * 100.0
	var ready := Economy.ready_units(b)
	var count := BuildingInfo.stored(b)
	var per_hour := {}
	for res in batch.units:
		per_hour[res] = floori(float(batch.units[res]) / int(batch.hours))
	if count > 0:
		_ready_text.text = "Ready: %s" % _amounts(ready)
	elif Economy.batch_running(b):
		_ready_text.text = "Every finished hour adds about %s" % _amounts(per_hour)
	else:
		_ready_text.text = "All collected"
	var output: String = batch.units.keys()[0] if not batch.units.is_empty() else "item"
	_collect.icon = UITheme.icon(output)
	_collect.text = "Collect %s" % UITheme.number(count) if count > 0 else "Collect"
	_collect.disabled = count == 0
	var units := 0
	for res in batch.units:
		units += int(batch.units[res])
	var each := float(batch.cost) / maxf(units, 1.0)
	var extra := Economy.bonus_output(str(batch.bonus))
	var bonus_text := "no bonus" if extra <= 0.0 else "%s bonus (+%d%% units)" % [str(batch.bonus).capitalize(), roundi(extra * 100.0)]
	_locked.text = "Locked in: %s h, %s, %s for %s = %s each." % [_amount(float(batch.hours)), bonus_text, UITheme.money(roundi(float(batch.cost))), _amounts(batch.units), UITheme.price(roundi(each))]
	_cancel.visible = Economy.batch_running(b)


func _step_button(text: String, step: int, tip: String) -> Button:
	var button := Button.new()
	button.theme_type_variation = "BlueButton"
	button.text = text
	button.tooltip_text = tip
	button.custom_minimum_size = Vector2(52, 44)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(func():
		_hours = clampi(_hours + step, 1, Economy.batch_hours_limit())
		refresh())
	return button


## "Title ........ value". Returns the value label.
func _figure_row(parent: Control, title: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(title, 17)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := _label("", 18)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.theme_type_variation = "BodyLabel"
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _wrapped(text: String, font_size: int) -> Label:
	var label := _label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _width
	return label


## "1,584 Wheat" / "19 Flour + 3 Bran".
func _amounts(items: Dictionary) -> String:
	var parts: Array[String] = []
	for res in items:
		parts.append("%s %s" % [UITheme.number(int(items[res])), BuildingInfo.resource_name(res)])
	return " + ".join(parts)


## 14.0 -> "14", 1.5 -> "1.5".
func _amount(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
