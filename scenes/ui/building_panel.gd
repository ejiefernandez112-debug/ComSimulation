extends ModalWindow
## The building's info window (plan.md §6 Building Panel): what it makes and from what, and for
## a Farm, Mill or Bakery its batch (BatchBox: set one up, or see it run and collect it). Move
## and Demolish sit at the bottom. A Supermarket shows its shelves and a form to put food on one
## (§5.16). Shows numbers from Economy only; the buttons ask main.gd to act (signals).

signal collect_requested(building_id: String)
signal start_batch_requested(building_id: String, hours: int, bonus: String)
signal cancel_batch_requested(building_id: String)
signal move_requested(building_id: String)
signal demolish_requested(building_id: String)
signal staffing_requested(building_id: String, level: String)
signal suspend_requested(building_id: String)
signal resume_requested(building_id: String)
signal stock_requested(building_id: String, resource_id: String, qty: int, tag: String)
signal clear_shelf_requested(building_id: String, index: int)
signal upgrade_requested(building_id: String)

var building_id := ""
var _shown_level := 0  # the level the rows were built for: an upgrade finishing rebuilds them

# Parts that change while the window is open (refreshed every Economy tick).
var _road_box: Control  # shown while it has no road: why it stops
var _road_text: Label
var _power_box: Control  # shown while it has no power (plan.md §5.5): why it stops
var _power_warning: Label
var _power_text: Label  # buildings that use power: how much and what it costs
var _status: Label  # "Now" (buildings without batches)
var _progress: ProgressBar
var _batch_box: BatchBox  # a Farm, Mill or Bakery's batch (plan.md §5.1)
var _staff_buttons := {}  # staffing level -> its button
var _wage_each_text: Label
var _water_text: Label  # buildings that draw water from the public supply (plan.md §5.13)
var _workers_text: Label
var _wages_text: Label
var _rate_text: Label
var _workers_note: Label
var _suspend: Button  # Suspend / Resume
var _upgrade_text: Label  # what the next level brings, or how long the upgrade has left
var _upgrade_button: Button
var _upgrade_needs: Label  # what the next level needs (materials, crew) at today's prices
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
	_shown_level = Economy.building_level(b)
	open("%s  ·  Level %d" % [def.name, _shown_level])
	_refresh()


func _build_rows(b: Dictionary, def: Dictionary) -> void:
	clear_content()
	_status = null
	_batch_box = null
	_staff_buttons.clear()
	_workers_text = null
	_water_text = null
	_power_text = null
	_suspend = null
	_upgrade_text = null
	_upgrade_button = null
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
	_road_box = null
	if Economy.needs_road(b):
		_road_box = _section("No road")
		_road_text = _wrapped("")
		_road_text.add_theme_color_override("font_color", UITheme.BAD)
		_road_box.add_child(_road_text)
	_power_box = null
	if Economy.power_need(b) > 0.0:
		_power_box = _section("No power")
		_power_warning = _wrapped("")
		_power_warning.add_theme_color_override("font_color", UITheme.BAD)
		_power_box.add_child(_power_warning)

	if def.category in ["extractor", "processor"]:
		# What one hour of work makes (plan.md §5.1), then the batch: set one up, or watch it run.
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
		row.add_child(_body("per %s of work" % ("hour" if is_equal_approx(float(r.duration), 3600.0) else UITheme.duration(float(r.duration)))))
		_batch_box = BatchBox.new()
		_batch_box.setup(building_id, WIDTH - 70)
		_batch_box.start_requested.connect(func(id, hours, bonus): start_batch_requested.emit(id, hours, bonus))
		_batch_box.collect_requested.connect(func(id): collect_requested.emit(id))
		_batch_box.cancel_requested.connect(func(id): cancel_batch_requested.emit(id))
		box.add_child(_batch_box)
	else:
		# "Now": what it's doing.
		var now_box := _section("Now")
		_status = _body("")
		now_box.add_child(_status)
		_progress = ProgressBar.new()
		_progress.show_percentage = false
		_progress.custom_minimum_size.y = 16
		now_box.add_child(_progress)

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
		_build_shelves(b)
		_build_stock_form()

	if int(def.get("max_workers", 0)) > 0:
		_build_workers(b, def)

	if Economy.max_level(b.type) > 1:
		_build_upgrade()

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


## Without a road (plan.md §5.20) nobody can get to work here: say so. Hidden once it has a road.
func _refresh_road(b: Dictionary) -> void:
	var cut_off := not Economy.on_road(b)
	var section: Control = _road_box.get_parent()  # the Inset panel around the box
	if section.visible != cut_off:
		section.visible = cut_off
		_layout.call_deferred()
	_road_text.text = "No workers can get here, so it stops. It needs a road beside it that leads to City Hall: lay one with Build → Roads."


## Without power (plan.md §5.5) it doesn't work at all: say why. Hidden while it has power.
func _refresh_power(b: Dictionary) -> void:
	var warning := BuildingInfo.power_warning(b)
	var section: Control = _power_box.get_parent()
	if section.visible != (warning != ""):
		section.visible = warning != ""
		_layout.call_deferred()
	_power_warning.text = warning.trim_prefix("No power: ") + "."


## Upgrade (plan.md §5.15): what the next level brings and the button that starts it (cost and
## time on it); while upgrading, how long is left; at the top, just the level.
func _build_upgrade() -> void:
	var box := _section("Upgrade")
	_upgrade_text = _wrapped("")
	_upgrade_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_upgrade_text)
	_upgrade_button = Button.new()
	_upgrade_button.custom_minimum_size = Vector2(0, 52)
	_upgrade_button.add_theme_font_size_override("font_size", 18)
	_upgrade_button.pressed.connect(func(): upgrade_requested.emit(building_id))
	box.add_child(_upgrade_button)
	_upgrade_needs = _wrapped("")
	_upgrade_needs.add_theme_font_size_override("font_size", 15)
	box.add_child(_upgrade_needs)
	# A later upgrade, shown so players know it's coming (plan.md §5.15); nothing behind it yet.
	var robots := Button.new()
	robots.text = "Robotic workers: coming soon"
	robots.theme_type_variation = "GreyButton"
	robots.disabled = true
	robots.custom_minimum_size = Vector2(0, 44)
	box.add_child(robots)


## "12 workers (1.5x as fast)", "room for 20,000 goods": what the next level changes.
func _upgrade_changes(b: Dictionary, next: Dictionary) -> String:
	var parts: Array[String] = []
	var full := int(GameData.buildings[b.type].get("max_workers", 0))
	var names := {"capacity": "room for %s goods", "shelves": "%s shelves", "households": "%s households", "water_supply": "cleans %s m³ of water an hour",
		"power_supply": "makes %s MW", "power_radius": "reaches %s tiles"}
	if next.has("max_workers"):
		var workers := int(next.max_workers)
		var text := "%d workers" % workers
		if GameData.buildings[b.type].category in ["extractor", "processor"] and full > 0:
			text += " (%sx as fast)" % str(snappedf(float(workers) / full, 0.01))
		parts.append(text)
	for key in names:
		if next.has(key):
			parts.append(names[key] % UITheme.number(int(next[key])))
	return ", ".join(parts)


func _refresh_upgrade(b: Dictionary) -> void:
	var level := Economy.building_level(b)
	var next := Economy.next_upgrade(b)
	if Economy.is_upgrading(b):
		var open := " It keeps working meanwhile." if Economy.stays_open_while_upgrading(b) else " Closed meanwhile: no workers, no wages; work in progress waits."
		_upgrade_text.text = "Upgrading to Level %d: %s left.%s" % [level + 1, UITheme.duration(Economy.upgrade_left(b)), open]
		_upgrade_button.visible = false
		_upgrade_needs.visible = false
		return
	_upgrade_button.visible = not next.is_empty()
	_upgrade_needs.visible = not next.is_empty()
	if next.is_empty():
		_upgrade_text.text = "Level %d: the highest level." % level
		return
	var how := "It keeps working while it's upgraded." if Economy.stays_open_while_upgrading(b) else "It closes while it's upgraded (its workers go to other buildings); finish or cancel its batch and collect it first."
	_upgrade_text.text = "Level %d brings %s. %s" % [level + 1, _upgrade_changes(b, next), how]
	var check := Economy.can_upgrade(building_id)
	var quote := Economy.upgrade_quote(b)
	_upgrade_button.text = "Upgrade to Level %d · ≈ %s · %s" % [level + 1, UITheme.money(int(quote.cost)), UITheme.duration(float(quote.seconds))]
	_upgrade_needs.text = "Needs %s. Materials are bought at today's prices (they change in %s)." % [BuildingInfo.construction_needs(quote), UITheme.duration(Economy.price_change_in())]
	# Greyed when it can't start, but still tappable, so the player is told why.
	_upgrade_button.theme_type_variation = "GreenButton" if check.ok else "GreyButton"
	_upgrade_button.tooltip_text = "Pay now; it reaches Level %d when the time is up" % (level + 1) if check.ok else str(check.error)


## Workers: the staffing choice (Low / Medium / High, with how many workers each means), who's
## working, what they cost, and how fast the building produces with them. Buildings with fixed
## workers (warehouses) get no choice, just a line saying how many they always employ.
func _build_workers(b: Dictionary, def: Dictionary) -> void:
	var box := _section("Workers")
	if def.get("fixed_workers", false):
		var text := "Always %d workers" % int(Economy.level_stat(b, "max_workers"))
		if def.get("fixed_wage", false):
			text += " at the minimum wage"
		if def.get("staffed_first", false):
			text += ", hired before any other building"
		var later := " Upgrading adds more." if int(Economy.next_upgrade(b).get("max_workers", 0)) > 0 else ""
		var fixed := _wrapped(text + "." + later)
		fixed.add_theme_font_size_override("font_size", 16)
		box.add_child(fixed)
	else:
		_build_staffing_buttons(box, int(Economy.level_stat(b, "max_workers")))
	_workers_text = _figure_row(box, "Workers:")
	var rate_title := "Production Rate:"
	if def.category == "storage":
		rate_title = "Usable Room:"
	elif def.category == "utility":
		rate_title = "Water Cleaned:"
	elif def.category == "retail":
		rate_title = "Serving Speed:"
	elif def.category == "construction":
		rate_title = "Free for new work:"
	_rate_text = _figure_row(box, rate_title)
	_wage_each_text = _figure_row(box, "Wage per worker:")
	_wages_text = _figure_row(box, "Wage bill:") if not def.category in ["extractor", "processor"] else null
	_water_text = _figure_row(box, "Water:") if float(def.get("water_per_hour", 0.0)) > 0.0 else null
	_power_text = _figure_row(box, "Power:") if Economy.power_need(b) > 0.0 else null
	_workers_note = _wrapped("")
	_workers_note.add_theme_font_size_override("font_size", 15)
	box.add_child(_workers_note)


## Low / Medium / High, each with how many workers it means ("Medium  6").
func _build_staffing_buttons(box: VBoxContainer, most: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var levels: Dictionary = GameData.config.get("staffing_levels", {})
	for level in levels:
		var button := Button.new()
		button.text = "%s  %d" % [level.capitalize(), roundi(most * float(levels[level]))]
		button.tooltip_text = "Employ %d of %d workers. Fewer workers = slower (a batch costs the same, it just takes longer)" % [roundi(most * float(levels[level])), most]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(func(): staffing_requested.emit(building_id, level))
		row.add_child(button)
		_staff_buttons[level] = button


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
	var batches := Economy.makes_batches(b)
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
	if _wages_text:
		_wages_text.text = "%s / hour" % UITheme.dollars(w.wages)
	if _water_text:
		# What its water costs: own plants' water at their price, the rest at the public price.
		var m3 := Economy.water_use(b)
		_water_text.text = "%s m³/h · %s / hour" % [UITheme.number(roundi(m3)), UITheme.dollars(Economy.water_cost_per_hour(b))]
	if _power_text:
		# Needs its MW while it runs; what that costs: own plants' power first, then the grid.
		var on := str(b.get("power", "")) == "on"
		_power_text.text = "%s · %s / hour" % [BuildingInfo.mw(Economy.power_need(b)), UITheme.dollars(Economy.power_cost_per_hour(b))] if on else "%s while it runs" % BuildingInfo.mw(Economy.power_need(b))
	var speed := Economy.building_speed(b)
	_rate_text.text = "%d%%" % floori(speed * 100.0 + 0.001)
	# The details: why it isn't full speed and what that rate makes.
	var note := "%s workers, paid %s" % [w.type, "for the whole batch when it starts" if batches else "per hour"]
	if def.category == "construction":
		var crew := Economy.crew()
		_rate_text.text = "%d of %d" % [int(crew.free), int(crew.total)]
		note = "%s workers, paid per project (the Labor cost when building or upgrading starts), nothing while they wait. Building anything needs 1, an upgrade 1 per level (Level 3 = 3). Free counts every Construction Office" % w.type
	elif def.category == "storage":
		_rate_text.text = "%s of %s" % [UITheme.number(Economy.storage_capacity(b)), UITheme.number(int(Economy.level_stat(b, "capacity")))]
		note += " · short of workers = less room"
	elif def.category == "utility":
		_rate_text.text = "%s of %s m³/h" % [UITheme.number(roundi(Economy.water_supply(b))), UITheme.number(int(Economy.level_stat(b, "water_supply")))]
		var price := float(Economy.water_summary().own_price)
		note += " · short of workers = less water"
		if price > 0.0:
			note += " · its water costs %s a m³ (public: %s)" % [UITheme.dollars(price), UITheme.dollars(float(GameData.config.get("water", {}).get("price_per_m3", 0.0)))]
	elif def.category == "retail":
		note += " while a shelf is selling · short of people = shelves sell slower"
	else:
		var r := BuildingInfo.recipe(b.type)
		var per_hour := 0.0
		for res in r.outputs:
			per_hour += int(r.outputs[res]) * 3600.0 / float(r.duration) * speed
		note += " · %s %s / hour (before any bonus)" % [UITheme.number(roundi(per_hour)), BuildingInfo.resource_name(BuildingInfo.output_of(r))]
	if Economy.is_upgrading(b) and not Economy.is_built(b):
		note = "Closed for its upgrade: its workers were freed for other buildings. It hires again when it's done. " + note
	elif not Economy.is_built(b):
		note = "It hires when it's built (%d asked for). " % w.wanted + note
	elif Economy.is_suspended(b):
		note = "Suspended: its workers were freed for other buildings. Resume to hire again. " + note
	elif not producing and def.category == "retail":
		note = "Idle: shelves empty. Its workers wait, unpaid, until you put food on a shelf. " + note
	elif not producing:
		note = "Idle: no batch being made. Its workers wait for the next batch. " + note
	elif short and def.get("staffed_first", false):
		note = "Only %d of the %d asked for: it gets free people before any other building, so the town just needs more people. Build houses. " % [int(w.hired), int(w.wanted)] + note
	elif short:
		note = "Only %d of the %d asked for: free people go to warehouses first, then take turns. Build houses. %s" % [int(w.hired), int(w.wanted), "Its batch costs the same, it just takes longer. " if batches else ""] + note
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
	if Economy.building_level(b) != _shown_level:
		show_building(building_id)  # an upgrade just finished: more slots, shelves or workers
		return
	var def: Dictionary = GameData.buildings[b.type]
	if _road_box:
		_refresh_road(b)
	if _power_box:
		_refresh_power(b)
	if _status:
		var status := BuildingInfo.status(b)
		_status.text = status.text
		_progress.visible = status.progress >= 0.0
		_progress.value = status.progress * 100.0
		# Homes show how full they are in blue (the population colour); everything else in green.
		_progress.theme_type_variation = "BlueBar" if def.category == "residential" else ""
	if _batch_box:
		var had_batch := _batch_box.showing_batch()
		_batch_box.refresh()
		if had_batch != _batch_box.showing_batch():
			_layout.call_deferred()  # set-up and running look differ in height
	if _workers_text:
		_refresh_workers(b, def)
	if _suspend:
		var off := Economy.is_suspended(b)
		_suspend.text = "Resume" if off else "Suspend"
		_suspend.theme_type_variation = "GreenButton" if off else "YellowButton"
		_suspend.tooltip_text = "Switch it back on (free)" if off else "Switch it off: workers go home, no wages. Goods inside go to the warehouse (a batch must be finished or cancelled first)"
	if _upgrade_text:
		_refresh_upgrade(b)
	if _stock_bar:
		var cap := Economy.warehouse_cap()
		_stock_bar.value = 100.0 * Economy.warehouse_total() / maxf(cap, 1.0)
		_stock_text.text = "%s / %s" % [UITheme.number(Economy.warehouse_total()), UITheme.number(cap)]
	if _goods_grid and Economy.state.inventory != _shown_stock:
		_fill_goods_grid()
	if not _shelf_rows.is_empty():
		_refresh_shelves(b)
	if _stock_button:
		_refresh_stock_form()


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
func _build_shelves(b: Dictionary) -> void:
	var box := _section("Shelves")
	_shoppers_text = _body("")
	_shoppers_text.add_theme_font_size_override("font_size", 16)
	box.get_child(0).add_child(_shoppers_text)
	for i in int(Economy.level_stat(b, "shelves")):
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


## The form's starting choice: the first food in stock that isn't on this store's shelves yet
## (else the first one), all of it, at the default price tag.
func choose_defaults() -> void:
	var products := Economy.shop_products()
	_chosen_item = products[0] if not products.is_empty() else ""
	for res in products:
		if int(Economy.state.inventory.get(res, 0)) > 0 and not Economy.store_has_product(building_id, res):
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
	var selling := Economy.selling_counts()
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
		var stores := int(selling.get(shelf.res, 0))
		if left < INF and stores > 1:
			row.detail.text += " · shared with %d other store%s" % [stores - 1, "" if stores == 2 else "s"]


func _refresh_stock_form() -> void:
	var stock: Dictionary = Economy.state.inventory
	for res in _item_buttons:
		var have := int(stock.get(res, 0))
		var on_shelf := Economy.store_has_product(building_id, res)
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
	var others := int(p.get("other_stores", 0))
	_preview.speed.text = "%s an hour" % UITheme.number(roundi(p.per_hour))
	if others > 0:  # the village's shoppers for it are shared with the other stores selling it
		_preview.speed.text += " (shared with %d other store%s)" % [others, "" if others == 1 else "s"]
	_preview.time.text = UITheme.duration(p.seconds) if p.seconds < INF else "nobody would buy"
	_preview.revenue.text = UITheme.money(int(p.gross))
	_preview.cost.text = "-" + UITheme.money(int(p.cost))
	_preview.tax.text = "-" + UITheme.money(int(p.tax))
	_preview.profit.text = UITheme.money(int(p.profit))
	_preview.profit.add_theme_color_override("font_color", UITheme.GOOD.darkened(0.35) if int(p.profit) >= 0 else UITheme.BAD.darkened(0.3))
	var item := BuildingInfo.resource_name(_chosen_item)
	if Economy.store_has_product(building_id, _chosen_item):
		_stock_button.text = "%s is already on a shelf here" % item
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

