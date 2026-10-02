extends ModalWindow
## The building's info window (plan.md §6 Building Panel): what it makes and from what, what
## it's doing now with its job queue, and its storage, with Collect and Make buttons.
## Tapping a filled queue slot cancels that batch; Fill queues as many as fit. Move and Demolish
## sit at the bottom. A Supermarket shows its shelves and a form to put food on one (§5.16).
## Shows numbers from Economy only; the buttons ask main.gd to act (signals).

signal collect_requested(building_id: String)
signal produce_requested(building_id: String)
signal fill_requested(building_id: String)
signal cancel_requested(building_id: String, index: int)
signal move_requested(building_id: String)
signal demolish_requested(building_id: String)
signal staffing_requested(building_id: String, level: String)
signal bonus_requested(building_id: String, level: String)
signal suspend_requested(building_id: String)
signal resume_requested(building_id: String)
signal stock_requested(building_id: String, resource_id: String, qty: int, tag: String)
signal clear_shelf_requested(building_id: String, index: int)

var building_id := ""

# Parts that change while the window is open (refreshed every Economy tick).
var _status: Label
var _progress: ProgressBar
var _slots: Array[PanelContainer] = []
var _storage_text: Label
var _storage_bar: ProgressBar
var _collect: Button
var _produce: Button
var _fill: Button
var _staff_buttons := {}  # staffing level -> its button
var _bonus_buttons := {}  # wage bonus level -> its button
var _wage_each_text: Label
var _water_text: Label  # buildings that draw water from the public supply (plan.md §5.13)
var _cost_button: Button  # production buildings: "Cost per unit: $1.83 ▸", tap to open
var _cost_details: VBoxContainer  # the breakdown lines under it
var _cost_open := false  # whether the breakdown is open (kept while the game runs)
var _workers_text: Label
var _wages_text: Label
var _rate_text: Label
var _workers_note: Label
var _suspend: Button  # Suspend / Resume
var _stock_text: Label  # warehouses: goods stored in all warehouses / their room
var _stock_bar: ProgressBar
var _goods_grid: HFlowContainer  # warehouses: one [icon] amount tile per item in stock
var _shown_stock := {}  # what the grid shows now, so it's only rebuilt when the stock changes
# Supermarket (plan.md §5.16): its shelves, and the form that puts food on one.
var _shelf_rows: Array[Dictionary] = []  # per shelf: {"icon", "title", "bar", "detail", "take_down"}
var _shoppers_text: Label
var _item_buttons := {}  # item -> its Button
var _tag_buttons := {}  # price tag -> its Button
var _amount_slider: HSlider
var _amount_label: Label
var _preview := {}  # "price", "speed", "time", "revenue", "cost", "tax", "profit" -> value Label
var _stock_button: Button
var _chosen_item := ""
var _chosen_tag := ""
var _chosen_amount := 0


func _ready() -> void:
	super()
	Economy.changed.connect(_refresh)


func show_building(id: String) -> void:
	building_id = id
	var b := Economy.building(id)
	if b.is_empty():
		return
	var def: Dictionary = GameData.buildings[b.type]
	if def.category == "retail":
		choose_defaults()
	_build_rows(b, def)
	open("%s  ·  Level %d" % [def.name, int(b.level)])
	_refresh()


func _build_rows(b: Dictionary, def: Dictionary) -> void:
	clear_content()
	_slots.clear()
	_storage_bar = null
	_collect = null
	_produce = null
	_fill = null
	_staff_buttons.clear()
	_bonus_buttons.clear()
	_workers_text = null
	_water_text = null
	_cost_button = null
	_cost_details = null
	_suspend = null
	_stock_bar = null
	_goods_grid = null
	_shelf_rows.clear()
	_item_buttons.clear()
	_tag_buttons.clear()
	_preview.clear()
	_stock_button = null
	var about := _body(def.get("description", ""))
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = WIDTH - 70  # wrapped text needs a width, or it measures one word per line
	content.add_child(about)
	var r := BuildingInfo.recipe(b.type)

	if def.category in ["extractor", "processor"]:
		var box := _section("Production")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		for res in r.inputs:
			row.add_child(_item(res, int(r.inputs[res])))
		if not r.inputs.is_empty():
			row.add_child(_icon("arrow", 34))
		for res in r.outputs:
			row.add_child(_item(res, int(r.outputs[res])))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(_icon("clock", 30))
		row.add_child(_body(UITheme.duration(float(r.duration))))
		# Cost per unit (plan.md §5.14): one line; tapping it opens the breakdown.
		_cost_button = Button.new()
		_cost_button.flat = true
		_cost_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_cost_button.add_theme_font_size_override("font_size", 18)
		_cost_button.add_theme_constant_override("outline_size", 0)  # plain text, like the lines under it
		_cost_button.add_theme_color_override("font_color", UITheme.TEXT_DARK)
		_cost_button.add_theme_color_override("font_hover_color", UITheme.TEXT_DARK)
		_cost_button.add_theme_color_override("font_pressed_color", UITheme.TEXT_DARK)
		_cost_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_cost_button.tooltip_text = "Tap to see what goes into the cost"
		_cost_button.pressed.connect(func():
			_cost_open = not _cost_open
			_refresh()
			_layout.call_deferred())
		box.add_child(_cost_button)
		_cost_details = VBoxContainer.new()
		_cost_details.add_theme_constant_override("separation", 2)
		box.add_child(_cost_details)

	# "Now": what it's doing, and for processors the queue too (its first slot is the batch
	# being made), with a Fill button beside the heading.
	var now_box := _section("Now")
	_status = _body("")
	now_box.add_child(_status)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 16
	now_box.add_child(_progress)

	if def.category == "processor":
		var header: HBoxContainer = now_box.get_child(0)
		var hint := _body("tap a batch to cancel")
		hint.add_theme_font_size_override("font_size", 15)
		hint.modulate.a = 0.75
		header.add_child(hint)
		_fill = Button.new()
		_fill.theme_type_variation = "YellowButton"
		_fill.custom_minimum_size = Vector2(110, 40)
		_fill.add_theme_font_size_override("font_size", 17)
		_fill.tooltip_text = "Queue as many batches as you have room and ingredients for"
		_fill.pressed.connect(func(): fill_requested.emit(building_id))
		header.add_child(_fill)
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 6)
		now_box.add_child(slots)
		for i in int(def.queue_size):
			slots.add_child(_queue_slot(i, BuildingInfo.output_of(r)))

	if def.category == "storage":
		# All warehouses share one stock, so show the whole stock (every item with its icon and
		# amount), not just this building's part.
		var stock := _section("Stored goods (all warehouses)")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		stock.add_child(row)
		row.add_child(_icon("warehouse", 34))
		_stock_bar = ProgressBar.new()
		_stock_bar.theme_type_variation = "GoldBar"
		_stock_bar.show_percentage = false
		_stock_bar.custom_minimum_size.y = 16
		_stock_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stock_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_stock_bar)
		_stock_text = _body("")
		row.add_child(_stock_text)
		_goods_grid = HFlowContainer.new()  # wraps onto more rows when there are many goods
		_goods_grid.add_theme_constant_override("h_separation", 8)
		_goods_grid.add_theme_constant_override("v_separation", 8)
		stock.add_child(_goods_grid)
		_shown_stock = {"never shown": 1}  # so the first refresh fills the grid

	if def.category == "retail":
		_build_shelves(def)
		_build_stock_form()

	if int(def.get("max_workers", 0)) > 0:
		_build_workers(def)

	if def.has("storage_cap"):
		var store := _section("Storage")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		store.add_child(row)
		row.add_child(_icon(BuildingInfo.output_of(r), 34))
		_storage_bar = ProgressBar.new()
		_storage_bar.theme_type_variation = "GoldBar"
		_storage_bar.show_percentage = false
		_storage_bar.custom_minimum_size.y = 16
		_storage_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_storage_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_storage_bar)
		_storage_text = _body("")
		row.add_child(_storage_text)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	content.add_child(buttons)
	if def.has("storage_cap"):
		_collect = Button.new()
		_collect.icon = UITheme.icon(BuildingInfo.output_of(r))
		_collect.expand_icon = true
		_collect.custom_minimum_size = Vector2(190, 60)
		_collect.pressed.connect(func(): collect_requested.emit(building_id))
		buttons.add_child(_collect)
	if def.category == "processor":
		_produce = Button.new()
		_produce.theme_type_variation = "YellowButton"
		_produce.text = "Make %s" % BuildingInfo.amounts(r.outputs)
		_produce.tooltip_text = "Uses %s from the warehouse" % BuildingInfo.amounts(r.inputs)
		_produce.custom_minimum_size = Vector2(230, 60)
		_produce.pressed.connect(func(): produce_requested.emit(building_id))
		buttons.add_child(_produce)

	# Move and Demolish: smaller, in their own row at the bottom, so they aren't tapped by accident.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 14)
	content.add_child(tools)
	tools.add_child(_small_button("BlueButton", "Move", "move", func(): move_requested.emit(building_id)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	if int(def.get("max_workers", 0)) > 0:  # only buildings with workers can be switched off
		_suspend = _small_button("YellowButton", "Suspend", "clock", func():
			if Economy.is_suspended(Economy.building(building_id)):
				resume_requested.emit(building_id)
			else:
				suspend_requested.emit(building_id))
		tools.add_child(_suspend)
	if def.get("buildable", false):  # starter buildings can't be rebuilt, so they can't be demolished
		tools.add_child(_small_button("RedButton", "Demolish", "demolish", func(): demolish_requested.emit(building_id)))


## Workers: the staffing choice (Low / Medium / High, with how many workers each means), who's
## working, what they cost, and how fast the building produces with them. Buildings with fixed
## workers (warehouses) get no choice, just a line saying how many they always employ.
func _build_workers(def: Dictionary) -> void:
	var box := _section("Workers")
	if def.get("fixed_workers", false):
		var text := "Always %d workers" % int(def.max_workers)
		if def.get("fixed_wage", false):
			text += " at the minimum wage"
		if def.get("staffed_first", false):
			text += ", hired before any other building"
		var fixed := _wrapped(text + ". Upgrading to Level 2 (coming later) doubles them.")
		fixed.add_theme_font_size_override("font_size", 16)
		box.add_child(fixed)
	else:
		_build_staffing_buttons(box, def)
	if not def.get("fixed_wage", false):  # warehouses always pay the minimum wage
		_build_bonus_buttons(box)
	_workers_text = _figure_row(box, "Workers:")
	var rate_title := "Production Rate:"
	if def.category == "storage":
		rate_title = "Usable Room:"
	elif def.category == "retail":
		rate_title = "Serving Speed:"
	_rate_text = _figure_row(box, rate_title)
	_wage_each_text = _figure_row(box, "Wage per worker:")
	_wages_text = _figure_row(box, "Wage bill:")
	_water_text = _figure_row(box, "Water:") if float(def.get("water_per_hour", 0.0)) > 0.0 else null
	_workers_note = _wrapped("")
	_workers_note.add_theme_font_size_override("font_size", 15)
	box.add_child(_workers_note)


## Low / Medium / High, each with how many workers it means ("Medium  6").
func _build_staffing_buttons(box: VBoxContainer, def: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var levels: Dictionary = GameData.config.get("staffing_levels", {})
	for level in levels:
		var button := Button.new()
		button.text = "%s  %d" % [level.capitalize(), roundi(int(def.max_workers) * float(levels[level]))]
		button.tooltip_text = "Employ %d of %d workers. Fewer workers = slower, but lower wages" % [roundi(int(def.max_workers) * float(levels[level])), int(def.max_workers)]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(func(): staffing_requested.emit(building_id, level))
		row.add_child(button)
		_staff_buttons[level] = button


## Wage bonus: None / +20% / +40% / +60% on top of the minimum wage. A bigger bonus costs more
## per worker and gets this building the next free workers first.
func _build_bonus_buttons(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var title := _body("Bonus:")
	title.custom_minimum_size.x = 70
	row.add_child(title)
	var bonuses: Dictionary = GameData.config.get("wage_bonuses", {})
	for level in bonuses:
		var share := float(bonuses[level])
		var button := Button.new()
		button.text = "None" if share <= 0.0 else "+%d%%" % roundi(share * 100.0)
		button.tooltip_text = "%s bonus: pay %d%% more than the minimum wage. Bigger bonuses get free workers first" % [level.capitalize(), roundi(share * 100.0)]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(func(): bonus_requested.emit(building_id, level))
		row.add_child(button)
		_bonus_buttons[level] = button


## "Title ........ value" with the value in bigger type. Returns the value label.
func _figure_row(parent: Control, title: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _body(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := _body("")
	value.add_theme_font_size_override("font_size", 20)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


func _refresh_workers(b: Dictionary, def: Dictionary) -> void:
	var w := Economy.workers(b)
	for level in _staff_buttons:
		_staff_buttons[level].theme_type_variation = "YellowButton" if level == w.level else "BlueButton"
	for level in _bonus_buttons:
		_bonus_buttons[level].theme_type_variation = "YellowButton" if level == w.bonus else "BlueButton"
	var producing: bool = Economy.is_built(b) and Economy.is_producing(b)
	# Short: posts it asked for that nobody has taken (open posts, waiting for free people).
	var short: bool = Economy.is_built(b) and not Economy.is_suspended(b) and int(w.hired) < int(w.wanted)
	# Workers tied to it / most it can employ, e.g. "6/8" (always whole people).
	_workers_text.text = "%d/%d" % [int(w.hired), int(w.max)]
	_workers_text.add_theme_color_override("font_color", UITheme.BAD.darkened(0.3) if short else UITheme.TEXT_DARK)
	var bonus_pay: float = w.wage_each - w.minimum
	if bonus_pay > 0.01:
		_wage_each_text.text = "%s + %s bonus = %s" % [UITheme.dollars(w.minimum), UITheme.dollars(bonus_pay), UITheme.dollars(w.wage_each)]
	else:
		_wage_each_text.text = "%s (minimum)" % UITheme.dollars(w.minimum)
	_wages_text.text = "%s / hour" % UITheme.dollars(w.wages)
	if _water_text:
		# Its share of the bill at the base price (the company pays +25% above 100 m³/h in all).
		var m3 := Economy.water_use(b)
		var price := float(GameData.config.get("water", {}).get("price_per_m3", 0.0))
		_water_text.text = "%s m³/h · %s / hour" % [UITheme.number(roundi(m3)), UITheme.dollars(m3 * price)]
	var speed := Economy.building_speed(b)
	_rate_text.text = "%d%%" % floori(speed * 100.0 + 0.001)
	# The details: why it isn't full speed and what that rate makes.
	var note := "%s workers, paid per hour" % w.type
	if def.category == "storage":
		_rate_text.text = "%s of %s" % [UITheme.number(Economy.storage_capacity(b)), UITheme.number(int(def.get("capacity", 0)))]
		note += " · short of workers = less room"
	elif def.category == "retail":
		note += " while a shelf is selling · fewer workers = shelves sell slower"
	else:
		var r := BuildingInfo.recipe(b.type)
		var per_minute := 0.0
		for res in r.outputs:
			per_minute += int(r.outputs[res]) * 60.0 / float(r.duration) * speed
		note += " · %.1f %s / min" % [per_minute, BuildingInfo.resource_name(BuildingInfo.output_of(r))]
	if not Economy.is_built(b):
		note = "It hires when it's built (%d asked for). " % w.wanted + note
	elif Economy.is_suspended(b):
		note = "Suspended: its workers were freed for other buildings. Resume to hire again. " + note
	elif Economy.is_halted(b):
		note = "Halted: storage full. Its workers wait, unpaid, until you collect. " + note
	elif not producing and def.category == "retail":
		note = "Idle: shelves empty. Its workers wait, unpaid, until you put food on a shelf. " + note
	elif not producing:
		note = "Idle: no jobs queued. Its workers wait, unpaid, for the next job. " + note
	elif short and def.get("staffed_first", false):
		note = "Only %d of the %d asked for: it gets free people before any other building, so the town just needs more people. Build houses. " % [int(w.hired), int(w.wanted)] + note
	elif short:
		note = "Only %d of the %d asked for: free people go to warehouses first, then to the biggest bonus. Build houses, or raise its bonus. " % [int(w.hired), int(w.wanted)] + note
	_workers_note.text = note


func _small_button(variation: String, text: String, icon_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = variation
	button.text = text
	button.icon = UITheme.icon(icon_name)
	button.expand_icon = true
	button.custom_minimum_size = Vector2(160, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(action)
	return button


func _refresh() -> void:
	if not visible or building_id == "":
		return
	var b := Economy.building(building_id)
	if b.is_empty():
		close()
		return
	var def: Dictionary = GameData.buildings[b.type]
	var status := BuildingInfo.status(b)
	_status.text = status.text
	_progress.visible = status.progress >= 0.0
	_progress.value = status.progress * 100.0
	if def.category == "residential":
		_status.text = "%s · %d living here now" % [status.text, Economy.population()]
		_progress.visible = true
		_progress.theme_type_variation = "BlueBar"
		_progress.value = 100.0 * Economy.population() / maxf(Economy.population_capacity(), 1)
	for i in _slots.size():
		var filled: bool = i < b.queue.size()
		var finished: bool = i == 0 and b.blocked
		_slots[i].get_child(0).modulate.a = 1.0 if filled else 0.0  # the item icon
		_slots[i].get_child(1).visible = filled and not finished  # the little red X
		_slots[i].mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if filled and not finished else Control.CURSOR_ARROW
		if not filled:
			_slots[i].tooltip_text = ""
		elif finished:
			_slots[i].tooltip_text = "Finished: collect to make room"
		elif i == 0:
			_slots[i].tooltip_text = "Being made now. Cancel to get %d%% of the ingredients back" % _percent("cancel_refund_in_progress")
		else:
			_slots[i].tooltip_text = "Waiting. Cancel to get %d%% of the ingredients back" % _percent("cancel_refund_waiting")
	if _workers_text:
		_refresh_workers(b, def)
	if _suspend:
		var off := Economy.is_suspended(b)
		_suspend.text = "Resume" if off else "Suspend"
		_suspend.theme_type_variation = "GreenButton" if off else "YellowButton"
		_suspend.tooltip_text = "Switch it back on (free); work starts from the beginning" if off else "Switch it off: workers go home, no wages. Work in progress is lost; goods go to the warehouse"
	if _stock_bar:
		var cap := Economy.warehouse_cap()
		_stock_bar.value = 100.0 * Economy.warehouse_total() / maxf(cap, 1.0)
		_stock_text.text = "%s / %s" % [UITheme.number(Economy.warehouse_total()), UITheme.number(cap)]
	if _goods_grid and Economy.state.inventory != _shown_stock:
		_fill_goods_grid()
	if _cost_button:
		_refresh_cost(b)
	if not _shelf_rows.is_empty():
		_refresh_shelves(b)
	if _stock_button:
		_refresh_stock_form()
	if _storage_bar:
		var stored := BuildingInfo.stored(b)
		_storage_bar.value = 100.0 * stored / float(def.storage_cap)
		_storage_text.text = "%s / %s" % [UITheme.number(stored), UITheme.number(int(def.storage_cap))]
	if _collect:
		var stored := BuildingInfo.stored(b)
		_collect.text = "Collect %s" % UITheme.number(stored) if stored > 0 else "Collect"
		_collect.disabled = b.storage.is_empty()
	if _produce:
		var check := Economy.can_enqueue(building_id, BuildingInfo.recipe(b.type).id)
		_produce.theme_type_variation = "YellowButton" if check.ok else "GreyButton"
	if _fill:
		var count := Economy.batches_possible(building_id, BuildingInfo.recipe(b.type).id)
		_fill.text = "Fill x%d" % count if count > 0 else "Fill"
		# Greyed when nothing fits, but still tappable, so the player is told why.
		_fill.theme_type_variation = "YellowButton" if count > 0 else "GreyButton"


## "Cost per unit: $1.83 ▸"; open, the lines of plan.md §5.14: each ingredient at its cost tag,
## wages, water, electricity (later), then what it sells for and the profit, and (for buildings
## with ingredients) what making it earns over selling the ingredients.
func _refresh_cost(b: Dictionary) -> void:
	var cost := Economy.cost_breakdown(b)
	if cost.is_empty():
		_cost_button.visible = false
		return
	var item := BuildingInfo.resource_name(cost.output)
	_cost_button.text = "Cost per unit (%s): %s  %s" % [item, UITheme.price(roundi(cost.total)), "▾" if _cost_open else "▸"]
	_cost_details.visible = _cost_open
	for child in _cost_details.get_children():
		_cost_details.remove_child(child)
		child.queue_free()
	if not _cost_open:
		return
	for line in cost.ingredients:
		_cost_line("%s   %s × %s" % [BuildingInfo.resource_name(line.res), _amount_text(float(line.qty)), UITheme.price(roundi(line.each))], float(line.per_unit))
	_cost_line("Wages   %d × %s/h, %s" % [int(cost.workers), UITheme.dollars(cost.wage_each), _minutes_text(float(cost.minutes))], float(cost.wages))
	_cost_line("Water", float(cost.water))
	_cost_line("Electricity", -1.0)
	var profit: int = int(cost.price) - roundi(cost.total)
	var sells := _small_note("Sells for %s · about %s %s each (before tax)" % [UITheme.price(int(cost.price)), UITheme.price(absi(profit)), "profit" if profit >= 0 else "loss"])
	_cost_details.add_child(sells)
	if not cost.ingredients.is_empty():
		var parts: Array[String] = []
		for line in cost.ingredients:
			parts.append("%d %s" % [roundi(float(line.qty) * int(cost.units)), BuildingInfo.resource_name(line.res).to_lower()])
		var earns := float(cost.making_earns)
		_cost_details.add_child(_small_note("If you sold the %s instead: %s → making it earns %s %s per batch" % [
			" and ".join(parts), UITheme.money(int(cost.inputs_value)), UITheme.money(absi(roundi(earns))), "more" if earns >= 0 else "less"]))
	if cost.estimated:
		_cost_details.add_child(_small_note("Not in stock yet: the ingredients' cost is an estimate."))


## One breakdown line: "Flour   1.33 × $0.75 ........ $1.00" (amount -1 = not in the game yet).
func _cost_line(title: String, cents: float) -> void:
	var row := HBoxContainer.new()
	_cost_details.add_child(row)
	var label := _body("   " + title)
	label.add_theme_font_size_override("font_size", 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := _body("coming later" if cents < 0.0 else UITheme.price(roundi(cents)))
	value.add_theme_font_size_override("font_size", 16)
	row.add_child(value)


func _small_note(text: String) -> Label:
	var note := _wrapped(text)
	note.add_theme_font_size_override("font_size", 15)
	return note


## 1.333 -> "1.33", 4.0 -> "4".
func _amount_text(amount: float) -> String:
	return str(roundi(amount)) if is_equal_approx(amount, roundf(amount)) else "%.2f" % amount


## 10.0 -> "10 min", 1.5 -> "1.5 min".
func _minutes_text(minutes: float) -> String:
	return "%s min" % _amount_text(minutes)


## Warehouses: one dark tile per item in stock, [icon] amount like the HUD's item counters, in
## the order of resources.json (raw goods first). Its name shows when pointing at it.
func _fill_goods_grid() -> void:
	_shown_stock = Economy.state.inventory.duplicate()
	for child in _goods_grid.get_children():
		_goods_grid.remove_child(child)
		child.queue_free()
	for res in GameData.resources:
		var qty := int(_shown_stock.get(res, 0))
		if qty <= 0:
			continue
		var tile := PanelContainer.new()
		tile.theme_type_variation = "HudPill"
		tile.tooltip_text = BuildingInfo.resource_name(res)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		tile.add_child(row)
		row.add_child(_icon(res, 34))
		var amount := Label.new()
		amount.text = UITheme.number(qty)
		amount.add_theme_font_size_override("font_size", 20)
		row.add_child(amount)
		_goods_grid.add_child(tile)
	if _goods_grid.get_child_count() == 0:
		var empty := _body("Nothing stored yet. Collect goods from your buildings.")
		empty.add_theme_font_size_override("font_size", 16)
		_goods_grid.add_child(empty)
	_layout.call_deferred()  # the window may need to grow or shrink for the new rows


## Supermarket: one row per shelf with its food, price tag and price, a bar of how much has sold,
## and a red X to take it down. The heading shows the shoppers bonus.
func _build_shelves(def: Dictionary) -> void:
	var box := _section("Shelves")
	_shoppers_text = _body("")
	_shoppers_text.add_theme_font_size_override("font_size", 16)
	box.get_child(0).add_child(_shoppers_text)
	for i in int(def.get("shelves", 0)):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var icon := _icon("item", 40)
		row.add_child(icon)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		row.add_child(column)
		var title := _body("")
		title.add_theme_font_size_override("font_size", 18)
		column.add_child(title)
		var bar := ProgressBar.new()
		bar.theme_type_variation = "GoldBar"
		bar.show_percentage = false
		bar.custom_minimum_size.y = 12
		column.add_child(bar)
		var detail := _body("")
		detail.add_theme_font_size_override("font_size", 15)
		column.add_child(detail)
		var take_down := RoundButton.make("red", "close", "", 44)
		take_down.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		take_down.tooltip_text = "Take it down: what's sold is paid for, the rest goes back to the warehouse"
		take_down.pressed.connect(func(): clear_shelf_requested.emit(building_id, i))
		row.add_child(take_down)
		_shelf_rows.append({"icon": icon, "title": title, "bar": bar, "detail": detail, "take_down": take_down})


## "Put on a shelf": choose the food, how much (a slider, or All) and its price tag. The lines
## under it show what that would bring before the player commits: the price, how fast the
## village would buy it, how long it takes, and the profit.
func _build_stock_form() -> void:
	var box := _section("Put on a shelf")
	var items := HBoxContainer.new()
	items.add_theme_constant_override("separation", 6)
	box.add_child(items)
	for res in Economy.shop_products():
		var button := Button.new()
		button.icon = UITheme.icon(res)
		button.expand_icon = true
		button.custom_minimum_size = Vector2(0, 48)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(func(): _choose_item(res))
		items.add_child(button)
		_item_buttons[res] = button

	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 10)
	box.add_child(amount_row)
	amount_row.add_child(_body("Amount:"))
	_amount_slider = HSlider.new()
	_amount_slider.min_value = 1
	_amount_slider.step = 1
	_amount_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_amount_slider.value_changed.connect(func(value: float):
		_chosen_amount = int(value)
		_refresh())
	amount_row.add_child(_amount_slider)
	_amount_label = _body("")
	_amount_label.custom_minimum_size.x = 64
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_row.add_child(_amount_label)
	var all := Button.new()
	all.theme_type_variation = "BlueButton"
	all.text = "All"
	all.custom_minimum_size = Vector2(70, 42)
	all.add_theme_font_size_override("font_size", 16)
	all.pressed.connect(func():
		_chosen_amount = int(Economy.state.inventory.get(_chosen_item, 0))
		_refresh())
	amount_row.add_child(all)

	# Price tags: cheaper sells faster, dearer sells slower (game_config.json retail.price_tags).
	var tags_row := HBoxContainer.new()
	tags_row.add_theme_constant_override("separation", 4)
	box.add_child(tags_row)
	var tags: Dictionary = GameData.config.get("retail", {}).get("price_tags", {})
	for tag in tags:
		var change := roundi((float(tags[tag].price) - 1.0) * 100.0)
		var button := Button.new()
		button.text = "%s\n%s" % [tags[tag].name, "price" if change == 0 else "%+d%%" % change]
		button.tooltip_text = "Price x%.2f: sells %.2fx as fast" % [float(tags[tag].price), float(tags[tag].speed)]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 58
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func():
			_chosen_tag = tag
			_refresh())
		tags_row.add_child(button)
		_tag_buttons[tag] = button

	_preview["price"] = _figure_row(box, "Price each:")
	_preview["speed"] = _figure_row(box, "The village buys:")
	_preview["time"] = _figure_row(box, "Sells out in about:")
	_preview["revenue"] = _figure_row(box, "Sales:")
	_preview["cost"] = _figure_row(box, "Cost to make them:")
	_preview["tax"] = _figure_row(box, "Sales tax (today's rate):")
	_preview["profit"] = _figure_row(box, "Profit:")
	_stock_button = Button.new()
	_stock_button.theme_type_variation = "YellowButton"
	_stock_button.custom_minimum_size = Vector2(300, 56)
	_stock_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Greyed when it can't go on a shelf, but still tappable, so the player is told why.
	_stock_button.pressed.connect(func(): stock_requested.emit(building_id, _chosen_item, _chosen_amount, _chosen_tag))
	box.add_child(_stock_button)


## The form's starting choice: the first food in stock that isn't on a shelf yet (else the first
## one), all of it, at the default price tag.
func choose_defaults() -> void:
	var products := Economy.shop_products()
	_chosen_item = products[0] if not products.is_empty() else ""
	for res in products:
		if int(Economy.state.inventory.get(res, 0)) > 0 and Economy.shelf_selling(res).is_empty():
			_chosen_item = res
			break
	_chosen_amount = int(Economy.state.inventory.get(_chosen_item, 0))
	_chosen_tag = str(GameData.config.get("retail", {}).get("default_tag", "normal"))


func _choose_item(res: String) -> void:
	_chosen_item = res
	_chosen_amount = int(Economy.state.inventory.get(res, 0))  # all of it, until the slider says less
	_refresh()


func _refresh_shelves(b: Dictionary) -> void:
	var list := Economy.shelves(b)
	var bonus := Economy.shoppers(b) - 1.0
	_shoppers_text.text = "Shoppers +%d%%" % roundi(bonus * 100.0) if bonus > 0.001 else "More products = more shoppers"
	var tags: Dictionary = GameData.config.get("retail", {}).get("price_tags", {})
	for i in _shelf_rows.size():
		var row: Dictionary = _shelf_rows[i]
		var shelf: Dictionary = list[i] if i < list.size() else {}
		row.take_down.visible = not shelf.is_empty()
		row.bar.visible = not shelf.is_empty()
		if shelf.is_empty():
			row.icon.texture = UITheme.icon("item")
			row.icon.modulate.a = 0.3
			row.title.text = "Empty shelf"
			row.detail.text = "Put food on it below."
			continue
		row.icon.texture = UITheme.icon(shelf.res)
		row.icon.modulate.a = 1.0
		row.title.text = "%s · %s · %s each" % [BuildingInfo.resource_name(shelf.res), tags.get(shelf.tag, {}).get("name", shelf.tag), UITheme.price(int(shelf.price))]
		var sold := Economy.shelf_sold_now(b, i)
		row.bar.value = 100.0 * sold / maxf(float(shelf.qty), 1.0)
		var left := Economy.shelf_time_left(b, i)
		row.detail.text = "%s of %s sold · %s" % [UITheme.number(floori(sold)), UITheme.number(int(shelf.qty)),
			"sells out in %s" % UITheme.duration(left) if left < INF else "not selling: no workers"]


func _refresh_stock_form() -> void:
	var stock: Dictionary = Economy.state.inventory
	for res in _item_buttons:
		var have := int(stock.get(res, 0))
		var on_shelf := not Economy.shelf_selling(res).is_empty()
		_item_buttons[res].text = "%s  %s" % [BuildingInfo.resource_name(res), "on a shelf" if on_shelf else UITheme.number(have)]
		if res == _chosen_item:
			_item_buttons[res].theme_type_variation = "YellowButton"
		else:
			_item_buttons[res].theme_type_variation = "BlueButton" if have > 0 and not on_shelf else "GreyButton"
	for tag in _tag_buttons:
		_tag_buttons[tag].theme_type_variation = "YellowButton" if tag == _chosen_tag else "BlueButton"
	var have := int(stock.get(_chosen_item, 0))
	_chosen_amount = clampi(_chosen_amount, mini(1, have), have)
	_amount_slider.max_value = maxi(have, 1)
	_amount_slider.editable = have > 1
	_amount_slider.set_value_no_signal(maxi(_chosen_amount, 1))
	_amount_label.text = UITheme.number(_chosen_amount)
	var p := Economy.stock_preview(building_id, _chosen_item, _chosen_amount, _chosen_tag)
	_preview.price.text = UITheme.price(int(p.price))
	_preview.speed.text = "%s an hour" % UITheme.number(roundi(p.per_hour))
	_preview.time.text = UITheme.duration(p.seconds) if p.seconds < INF else "nobody would buy"
	_preview.revenue.text = UITheme.money(int(p.gross))
	_preview.cost.text = "-" + UITheme.money(int(p.cost))
	_preview.tax.text = "-" + UITheme.money(int(p.tax))
	_preview.profit.text = UITheme.money(int(p.profit))
	_preview.profit.add_theme_color_override("font_color", UITheme.GOOD.darkened(0.35) if int(p.profit) >= 0 else UITheme.BAD.darkened(0.3))
	var item := BuildingInfo.resource_name(_chosen_item)
	if not Economy.shelf_selling(_chosen_item).is_empty():
		_stock_button.text = "%s is already on a shelf" % item
	elif have <= 0:
		_stock_button.text = "No %s in the warehouse" % item
	else:
		_stock_button.text = "Put %s %s on a shelf" % [UITheme.number(_chosen_amount), item]
	var check := Economy.can_stock_shelf(building_id, _chosen_item, _chosen_amount, _chosen_tag)
	_stock_button.theme_type_variation = "YellowButton" if check.ok else "GreyButton"


## A titled, sunken box in the window. Returns the column to add rows to; its first child is the
## header row (the title, which other controls can be added beside).
func _section(title: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	content.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	box.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 19)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	return column


func _percent(config_key: String) -> int:
	return roundi(100.0 * float(GameData.config.get(config_key, 0.0)))


## One queue slot: the item being made, with a small red X in the corner when it can be cancelled.
## Child 0 is the item icon, child 1 the X (_refresh shows and hides them).
func _queue_slot(index: int, item: String) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.theme_type_variation = "HudPill"
	slot.custom_minimum_size = Vector2(44, 44)
	slot.add_child(_icon(item, 32))
	var x := _icon("close", 18)
	x.size_flags_horizontal = Control.SIZE_SHRINK_END
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.modulate = UITheme.BAD
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(x)
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			cancel_requested.emit(building_id, index))
	_slots.append(slot)
	return slot


## An item icon with its amount, e.g. [wheat] 40.
func _item(resource_id: String, amount: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.tooltip_text = BuildingInfo.resource_name(resource_id)
	row.add_child(_icon(resource_id, 38))
	var label := Label.new()
	label.text = "x%d" % amount
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	return row


func _icon(icon_name: String, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = UITheme.icon(icon_name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	return rect


func _body(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "BodyLabel"
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## Body text that wraps onto more lines instead of making the window wider.
func _wrapped(text: String) -> Label:
	var label := _body(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 70
	return label

