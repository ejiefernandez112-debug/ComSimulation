class_name BatchBox
extends VBoxContainer
## A Farm, Mill or Bakery's batch (plan.md §5.1), inside its building window.
## Idle: choose the bonus (more units for higher wages), fertilizer (a Plantation's crops: more
## units for some fertilizer, plan.md §5.17) and how long it works: step the finish
## time an hour at a time, or All (as long as the ingredients and cash allow). The lines under it
## show what the batch makes and costs before the player starts it.
## With a batch: how far along it is, what's ready to collect, what's locked in, and Cancel.
## A building with several products (a Plantation's crops, a Dairy's cheese / butter / yogurt;
## plan.md §5.21) shows them first: pick one for the first batch; later a Plantation can switch
## (for a fee) and a factory keeps its product for good.
## Shows numbers from Economy only; its buttons ask (signals) and main.gd acts.

signal start_requested(building_id: String, recipe_id: String, hours: int, bonus: String, fertilize: bool)
signal switch_requested(building_id: String, recipe_id: String)
signal collect_requested(building_id: String)
signal cancel_requested(building_id: String)

const TITLES := {"units": "Makes:", "ingredients": "Ingredients:", "labor": "Labor:", "water": "Water:", "per_unit": "Per unit:", "total": "Total cost:"}

var building_id := ""
var _hours := 0  # the length chosen for the next batch (0 = not chosen yet: offer the default)
var _bonus := "none"  # the bonus chosen for the next batch
var _fertilize := false  # fertilizer chosen for the next batch (only used where the recipe takes it)
var _choice := ""  # the product picked for the first batch, before the building has one
var _width := 400.0

# Idle: setting up the next batch.
var _setup: VBoxContainer
var _product_buttons := {}  # recipe id -> its Button (only for buildings with several products)
var _bonus_buttons := {}  # bonus level -> its Button
var _fertilizer_row: HBoxContainer  # hidden when the recipe can't use fertilizer
var _fertilizer_buttons := {}  # false / true -> its Button
var _finish_text: Label
var _lines := {}  # TITLES key -> its value Label
var _start: Button
# With a batch.
var _running: VBoxContainer
var _status: Label
var _progress: ProgressBar
var _ready_text: Label
var _collect: Button
var _cancel: Button


## Builds the box for this building. `width` = the window's text width (wrapped lines need it).
func setup(id: String, width: float) -> void:
	building_id = id
	_width = width
	add_theme_constant_override("separation", 6)
	_bonus = str(Economy.workers(Economy.building(id)).bonus)  # the last choice
	_fertilize = bool(Economy.building(id).get("fertilize", false))  # the same
	_hours = 0
	_build_setup()
	_build_running()


func _build_setup() -> void:
	_setup = VBoxContainer.new()
	_setup.add_theme_constant_override("separation", 6)
	add_child(_setup)
	# What it makes, when it can make several things (plan.md §5.21).
	var recipes: Array = GameData.buildings[Economy.building(building_id).type].get("recipes", [])
	if recipes.size() > 1:
		var products := HFlowContainer.new()
		products.add_theme_constant_override("h_separation", 6)
		products.add_theme_constant_override("v_separation", 6)
		_setup.add_child(products)
		for r in recipes:
			var out := BuildingInfo.output_of(r)
			var button := Button.new()
			button.icon = UITheme.icon(out)
			button.expand_icon = true
			button.text = BuildingInfo.resource_name(out)
			UITheme.size_button(button, "small")
			button.custom_minimum_size.x = 130
			button.pressed.connect(_on_product_pressed.bind(str(r.id)))
			products.add_child(button)
			_product_buttons[str(r.id)] = button
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
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.size_button(button, "small")
		button.pressed.connect(func():
			_bonus = level
			refresh())
		row.add_child(button)
		_bonus_buttons[level] = button
	# Fertilizer: more units for some fertilizer from the Warehouse (taken with the ingredients).
	_fertilizer_row = HBoxContainer.new()
	_fertilizer_row.add_theme_constant_override("separation", 6)
	_setup.add_child(_fertilizer_row)
	var fertilizer_title := _label("Fertilizer:", 18)
	fertilizer_title.custom_minimum_size.x = 70
	_fertilizer_row.add_child(fertilizer_title)
	for choice in [false, true]:
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.size_button(button, "small")
		button.pressed.connect(func():
			_fertilize = choice
			refresh())
		_fertilizer_row.add_child(button)
		_fertilizer_buttons[choice] = button
	# How long: step the finish time an hour at a time, or All.
	var length := HBoxContainer.new()
	length.add_theme_constant_override("separation", 6)
	_setup.add_child(length)
	length.add_child(_step_button("−", -1))
	_finish_text = _label("", 18)
	_finish_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_finish_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	length.add_child(_finish_text)
	length.add_child(_step_button("+", 1))
	var all := Button.new()
	all.theme_type_variation = ""
	all.text = "All"
	UITheme.size_button(all, "small")
	all.pressed.connect(func():
		_hours = maxi(_most_hours(), 1)
		refresh())
	length.add_child(all)
	# What it makes and costs, before starting.
	for key in TITLES:
		_lines[key] = _figure_row(_setup, TITLES[key])
	_start = Button.new()
	UITheme.size_button(_start, "big")
	_start.custom_minimum_size.x = 300
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Greyed when it can't start, but still tappable, so the player is told why.
	_start.pressed.connect(func(): start_requested.emit(building_id, _recipe_id(Economy.building(building_id)), _hours, _bonus, _fertilize))
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
	UITheme.size_button(_collect, "normal")
	_collect.custom_minimum_size.x = 190
	_collect.pressed.connect(func(): collect_requested.emit(building_id))
	row.add_child(_collect)
	_cancel = Button.new()
	_cancel.theme_type_variation = "DangerButton"
	_cancel.text = "Cancel batch"
	_cancel.icon = UITheme.icon("close")
	_cancel.expand_icon = true
	UITheme.size_button(_cancel, "small")
	_cancel.custom_minimum_size.x = 190
	_cancel.size_flags_horizontal = Control.SIZE_SHRINK_END
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


## The recipe the next batch makes: the building's product, or (before it has one) the pick.
func _recipe_id(b: Dictionary) -> String:
	if Economy.product_of(b) == "" and _choice != "":
		return _choice
	return str(BuildingInfo.recipe_of(b).get("id", ""))


## The recipe shown: the batch's while it has one, else the next batch's.
func current_recipe_id() -> String:
	return _recipe_id(Economy.building(building_id))


## A product button: before the first batch it's just the pick; after, a Plantation asks to
## switch (main.gd shows the fee, or why not), and a factory explains it can't.
func _on_product_pressed(recipe_id: String) -> void:
	var b := Economy.building(building_id)
	var current := Economy.product_of(b)
	if current == "":
		_choice = recipe_id
		_hours = 0  # offer the usual length again for the new product
		refresh()
	elif recipe_id != current:
		switch_requested.emit(building_id, recipe_id)


func _most_hours() -> int:
	var b := Economy.building(building_id)
	return Economy.batch_max_hours(building_id, _recipe_id(b), _bonus, _fertilize)


func _refresh_setup(b: Dictionary) -> void:
	if not _product_buttons.is_empty():
		_refresh_products(b)
	var most := _most_hours()
	var limit := Economy.batch_hours_limit()
	if _hours <= 0:  # first look: the usual length, or less if the stock and cash run out sooner
		_hours = mini(Economy.batch_default_hours(), most)
	_hours = clampi(_hours, 1, limit)
	for level in _bonus_buttons:
		_bonus_buttons[level].theme_type_variation = "ChipOnButton" if level == _bonus else "ChipButton"
	_refresh_fertilizer(b)
	var q := Economy.batch_quote(b, _recipe_id(b), _hours, _bonus, _fertilize)
	if q.is_empty():
		return
	var real_hours := float(q.seconds) / 3600.0
	_finish_text.text = "%s h ⋅ %s" % [_amount(real_hours), "waits for workers" if is_inf(float(q.finishes_at)) else "done %s" % UITheme.clock(float(q.finishes_at), TimeService.now())]
	_lines.units.text = _amounts(q.units)
	var parts: Array[String] = []
	var ingredients := 0.0
	for line in q.ingredients:
		parts.append("%s %s" % [UITheme.number(int(line.qty)), BuildingInfo.resource_name(line.res)])
		ingredients += float(line.cost)
	_lines.ingredients.text = "%s ⋅ %s" % [", ".join(parts), UITheme.money(roundi(ingredients))] if not parts.is_empty() else "none"
	_lines.labor.text = "%d workers ⋅ %s" % [int(q.workers), UITheme.money(int(q.wages))]
	# Water: only for buildings that use it (a Plantation's crop decides how much).
	_lines.water.get_parent().visible = float(q.water_units) > 0.0
	_lines.water.text = "%s units ⋅ %s" % [UITheme.number(roundi(float(q.water_units))), UITheme.money(roundi(float(q.water)))]
	_refresh_per_unit(q)
	_lines.total.text = UITheme.money(roundi(float(q.total)))  # includes the power estimate too
	var check := Economy.can_start_batch(building_id, _recipe_id(b), _hours, _bonus, _fertilize)
	_start.text = "Start %s h batch" % _amount(real_hours)
	_start.theme_type_variation = "GoButton" if check.ok else "BackButton"
	_start.tooltip_text = "" if check.ok else str(check.error)  # only says why it can't start


## "Per Wheat: 0.5 water ⋅ 0.05 fertilizer": what each unit of this batch's main product takes
## (plan.md §5.17.1). Fertilizer shows the crop's rate, like its button (the batch rounds its bags
## up). Only for batches that use water or fertilizer.
func _refresh_per_unit(q: Dictionary) -> void:
	var made := float(q.units.get(q.output, 0))
	var fertilizer := 0.0
	for line in q.ingredients:
		if line.res == Economy.fertilizer_item():
			fertilizer = float(line.qty)
	var row: Control = _lines.per_unit.get_parent()
	row.visible = made > 0.0 and (float(q.water_units) > 0.0 or fertilizer > 0.0)
	if not row.visible:
		return
	(row.get_child(0) as Label).text = "Per %s:" % BuildingInfo.resource_name(q.output)
	var parts: Array[String] = []
	if float(q.water_units) > 0.0:
		parts.append("%s water" % _per_unit_amount(float(q.water_units) / made))
	if fertilizer > 0.0:
		parts.append("%s fertilizer" % _per_unit_amount(Economy.fertilizer_per_unit(Economy.building(building_id).type, str(q.recipe_id))))
	_lines.per_unit.text = " ⋅ ".join(parts)


## 0.5 -> "0.5", 0.0417 -> "0.042", 10.67 -> "10.7": small amounts keep 3 decimals.
func _per_unit_amount(value: float) -> String:
	return String.num(value, 1 if value >= 10.0 else (2 if value >= 1.0 else 3))


## The fertilizer row: only for recipes that can use it; its "+25% ⋅ 0.05 each" button says the
## boost and the fertilizer each unit made takes.
func _refresh_fertilizer(b: Dictionary) -> void:
	var per_unit := Economy.fertilizer_per_unit(b.type, _recipe_id(b))
	_fertilizer_row.visible = per_unit > 0.0
	if per_unit <= 0.0:
		return
	_fertilizer_buttons[false].text = "None"
	_fertilizer_buttons[true].text = "+%d%% ⋅ %s each" % [roundi(Economy.fertilizer_boost(b.type, _recipe_id(b)) * 100.0), _per_unit_amount(per_unit)]
	for choice in _fertilizer_buttons:
		_fertilizer_buttons[choice].theme_type_variation = "ChipOnButton" if choice == _fertilize else "ChipButton"


## The product buttons: the one it makes (or the pick) in yellow.
func _refresh_products(b: Dictionary) -> void:
	var current := Economy.product_of(b)
	var shown := _recipe_id(b)
	var switchable := Economy.is_switchable(b.type)
	for id in _product_buttons:
		var variation := "ChipButton"
		if id == shown:
			variation = "ChipOnButton"
		elif current != "" and not switchable:
			variation = "BackButton"  # a factory's product is for good
		_product_buttons[id].theme_type_variation = variation


func _refresh_running(b: Dictionary) -> void:
	var batch: Dictionary = b.batch
	var status := BuildingInfo.status(b)
	_status.text = status.text
	_progress.value = Economy.job_progress(b) * 100.0
	var ready := Economy.ready_units(b)
	var count := BuildingInfo.stored(b)
	if count > 0:
		_ready_text.text = "Ready: %s" % _amounts(ready)
	elif Economy.batch_running(b):
		_ready_text.text = "Nothing ready yet"
	else:
		_ready_text.text = "All collected"
	var output: String = batch.units.keys()[0] if not batch.units.is_empty() else "item"
	_collect.icon = UITheme.icon(output)
	_collect.text = "Collect %s" % UITheme.number(count) if count > 0 else "Collect"
	_collect.disabled = count == 0
	_cancel.visible = Economy.batch_running(b)


func _step_button(text: String, step: int) -> Button:
	var button := Button.new()
	button.theme_type_variation = ""
	button.text = text
	UITheme.size_button(button, "small")
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
	return UITheme.label(text, UITheme.style_for(font_size))


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
