extends ModalWindow
## The building's info window (plan.md §6 Building Panel): what it makes and from what, and for
## a Farm, Mill or Bakery its batch (BatchBox: set one up, or see it run and collect it). Move
## and Demolish sit at the bottom. A Supermarket shows its shelves and a form to put food on one
## (§5.16). Shows numbers from Economy only; the buttons ask main.gd to act (signals).

signal collect_requested(building_id: String)
signal start_batch_requested(building_id: String, recipe_id: String, hours: int, bonus: String)
signal switch_product_requested(building_id: String, recipe_id: String)
signal cancel_batch_requested(building_id: String)
signal move_requested(building_id: String)
signal demolish_requested(building_id: String)
signal staffing_requested(building_id: String, level: String)
signal suspend_requested(building_id: String)
signal resume_requested(building_id: String)
signal stock_requested(building_id: String, resource_id: String, qty: int, tag: String)
signal clear_shelf_requested(building_id: String, index: int)
signal upgrade_requested(building_id: String)
signal trade_requested(side: String, resource_id: String, qty: int)

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
var _recipe_row: HBoxContainer  # what one hour of work makes, for the product shown
var _shown_recipe := ""  # the recipe the row shows, so it's only refilled when that changes
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
var _built_with: Label  # the materials it was built with, which demolishing gives back
var _stock_text: Label  # warehouses: goods stored in all warehouses / their room
var _stock_bar: ProgressBar
var _goods_grid: HFlowContainer  # warehouses: one [icon] amount tile per item in stock
var _shown_stock := {}  # what the grid shows now, so it's only rebuilt when the stock changes
# Supermarket (plan.md §5.16): its shelves, and the form that puts food on one.
var _shelf_rows: Array[Dictionary] = []  # per shelf: {"icon", "title", "bar", "detail", "take_down"}
var _item_buttons := {}  # item -> its Button
var _tag_buttons := {}  # price tag -> its Button
var _amount_slider: HSlider
var _amount_label: Label
var _preview := {}  # "price", "time", "profit" -> value Label
var _stock_button: Button
var _chosen_item := ""
var _chosen_tag := ""
var _chosen_amount := 0
var _trade_box: TradeBox  # the Trading Post's Sell / Buy form (plan.md §5.22)


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
	_built_with = null
	_stock_bar = null
	_goods_grid = null
	_shelf_rows.clear()
	_item_buttons.clear()
	_tag_buttons.clear()
	_preview.clear()
	_stock_button = null
	_trade_box = null
	var about := _body(def.get("description", ""))
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = WIDTH - 70  # wrapped text needs a width, or it measures one word per line
	content.add_child(about)
	var r := BuildingInfo.recipe_of(b)
	_recipe_row = null
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
		# The row follows the product shown in the batch box (a Plantation's crop, plan.md §5.21).
		var box := _section("Production")
		_recipe_row = HBoxContainer.new()
		_recipe_row.add_theme_constant_override("separation", 10)
		box.add_child(_recipe_row)
		_fill_recipe_row(r)
		_batch_box = BatchBox.new()
		_batch_box.setup(building_id, WIDTH - 70)
		_batch_box.start_requested.connect(func(id, recipe_id, hours, bonus): start_batch_requested.emit(id, recipe_id, hours, bonus))
		_batch_box.switch_requested.connect(func(id, recipe_id): switch_product_requested.emit(id, recipe_id))
		_batch_box.collect_requested.connect(func(id): collect_requested.emit(id))
		_batch_box.cancel_requested.connect(func(id): cancel_batch_requested.emit(id))
		box.add_child(_batch_box)
	elif def.category != "storage":  # a warehouse shows its room as a bar below instead
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

	if def.category == "trade":
		# The Trading Post (plan.md §5.22): sell anything to the trader, or buy anything from it.
		var trade := _section("Trade")
		_trade_box = TradeBox.new()
		_trade_box.setup(WIDTH - 70)
		_trade_box.trade_requested.connect(func(side, res, qty): trade_requested.emit(side, res, qty))
		trade.add_child(_trade_box)

	if int(def.get("max_workers", 0)) > 0:
		_build_workers(b, def)

	if Economy.max_level(b.type) > 1:
		_build_upgrade()

	if def.get("buildable", false) and not b.get("materials", {}).is_empty():
		# What it was built with (plan.md §5.15): demolishing puts all of it back in the warehouse.
		_built_with = _wrapped("")
		_built_with.theme_type_variation = "SmallLabel"
		content.add_child(_built_with)

	# Move and Demolish: smaller, in their own row at the bottom, so they aren't tapped by accident.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 14)
	content.add_child(tools)
	tools.add_child(_small_button("", "Move", "move", func(): move_requested.emit(building_id)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(spacer)
	if Economy.can_be_suspended(b.type):  # only buildings with workers (not the Warehouse or Construction Office)
		_suspend = _small_button("", "Suspend", "clock", func():
			if Economy.is_suspended(Economy.building(building_id)):
				resume_requested.emit(building_id)
			else:
				suspend_requested.emit(building_id))
		tools.add_child(_suspend)
	if def.get("buildable", false):  # starter buildings can't be rebuilt, so they can't be demolished
		tools.add_child(_small_button("DangerButton", "Demolish", "demolish", func(): demolish_requested.emit(building_id)))


## Without a road (plan.md §5.20) nobody can get to work here: say so. Hidden once it has a road.
func _refresh_road(b: Dictionary) -> void:
	var cut_off := not Economy.on_road(b)
	var section: Control = _road_box.get_parent()  # the Inset panel around the box
	if section.visible != cut_off:
		section.visible = cut_off
		_layout.call_deferred()
	_road_text.text = "No road reaches it, so no workers can come. Lay one (Build → Roads)."


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
	_upgrade_text.theme_type_variation = "SmallLabel"
	box.add_child(_upgrade_text)
	_upgrade_button = Button.new()
	UITheme.size_button(_upgrade_button, "normal")
	_upgrade_button.pressed.connect(func(): upgrade_requested.emit(building_id))
	box.add_child(_upgrade_button)
	_upgrade_needs = _wrapped("")
	_upgrade_needs.theme_type_variation = "SmallLabel"
	box.add_child(_upgrade_needs)


## "12 workers", "room for 20,000 goods": what the next level changes.
func _upgrade_changes(b: Dictionary, next: Dictionary) -> String:
	var parts: Array[String] = []
	var names := {"capacity": "room for %s goods", "shelves": "%s shelves", "households": "%s households", "water_supply": "cleans %s m³ of water an hour",
		"power_supply": "makes %s MW", "power_radius": "reaches %s tiles"}
	if next.has("max_workers"):
		parts.append("%d workers" % int(next.max_workers))
	for key in names:
		if next.has(key):
			parts.append(names[key] % UITheme.number(int(next[key])))
	return ", ".join(parts)


func _refresh_upgrade(b: Dictionary) -> void:
	var level := Economy.building_level(b)
	var next := Economy.next_upgrade(b)
	if Economy.is_upgrading(b):
		_upgrade_text.text = "Upgrading to Level %d: %s left." % [level + 1, UITheme.duration(Economy.upgrade_left(b))]
		_upgrade_button.visible = false
		_upgrade_needs.visible = false
		return
	_upgrade_button.visible = not next.is_empty()
	_upgrade_needs.visible = not next.is_empty()
	if next.is_empty():
		_upgrade_text.text = "Level %d: the highest level." % level
		return
	_upgrade_text.text = "Level %d brings %s." % [level + 1, _upgrade_changes(b, next)]
	var check := Economy.can_upgrade(building_id)
	var quote := Economy.upgrade_quote(b)
	# Upgrades never buy materials (they come from the warehouse), so the money is the crew only.
	var money := int(quote.cost)
	for line in quote.lines:
		if line.id != "labor":
			money -= int(line.cost)
	_upgrade_button.text = "Upgrade to Level %d · ≈ %s · %s" % [level + 1, UITheme.money(money), UITheme.duration(float(quote.seconds))]
	_upgrade_needs.text = "Needs %s." % BuildingInfo.construction_needs(quote)
	if not check.ok:
		_upgrade_needs.text += "\n" + str(check.error)
	# Greyed when it can't start, but still tappable, so the player is told why.
	_upgrade_button.theme_type_variation = "GoButton" if check.ok else "BackButton"
	_upgrade_button.tooltip_text = "" if check.ok else str(check.error)  # only says why it can't start


## Workers: the staffing choice (Low / Medium / High, with how many workers each means), who's
## working, what they cost, and how fast the building produces with them. Buildings with fixed
## workers (warehouses) get no choice, just a line saying how many they always employ.
func _build_workers(b: Dictionary, def: Dictionary) -> void:
	var box := _section("Workers")
	if def.get("fixed_workers", false):
		var fixed := _wrapped("Always %d workers." % int(Economy.level_stat(b, "max_workers")))
		fixed.theme_type_variation = "SmallLabel"
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
	_workers_note.theme_type_variation = "SmallLabel"
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
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.size_button(button, "small")
		button.custom_minimum_size.x = 0
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
	value.theme_type_variation = "HeadingLabel"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


func _refresh_workers(b: Dictionary, def: Dictionary) -> void:
	var w := Economy.workers(b)
	for level in _staff_buttons:
		_staff_buttons[level].theme_type_variation = "ChipOnButton" if level == w.level else "ChipButton"
	# Short: posts it asked for that nobody has taken (open posts, waiting for free people).
	var short: bool = Economy.is_built(b) and not Economy.is_suspended(b) and int(w.hired) < int(w.wanted)
	# Workers tied to it / most it can employ, e.g. "6/8" (always whole people).
	_workers_text.text = "%d/%d" % [int(w.hired), int(w.max)]
	UITheme.set_font_color(_workers_text, UITheme.BAD if short else UITheme.TEXT)
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
	# Rate details for the buildings that show them as "x of y".
	if def.category == "construction":
		var crew := Economy.crew()
		_rate_text.text = "%d of %d" % [int(crew.free), int(crew.total)]
	elif def.category == "storage":
		_rate_text.text = "%s of %s" % [UITheme.number(Economy.storage_capacity(b)), UITheme.number(int(Economy.level_stat(b, "capacity")))]
	elif def.category == "utility":
		_rate_text.text = "%s of %s m³/h" % [UITheme.number(roundi(Economy.water_supply(b))), UITheme.number(int(Economy.level_stat(b, "water_supply")))]
	# A note only when workers are missing (otherwise nothing needs saying).
	var note := "Only %d of the %d workers it needs: build houses." % [int(w.hired), int(w.wanted)] if short else ""
	if _workers_note.visible != (note != ""):
		_workers_note.visible = note != ""
		_layout.call_deferred()
	_workers_note.text = note


func _small_button(variation: String, text: String, icon_name: String, action: Callable) -> Button:
	var button := UITheme.button(text, variation, "small", icon_name)
	button.custom_minimum_size.x = 160
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
		if _batch_box.current_recipe_id() != _shown_recipe:  # a crop was picked or switched
			for r in def.get("recipes", []):
				if r.id == _batch_box.current_recipe_id():
					_fill_recipe_row(r)
	if _workers_text:
		_refresh_workers(b, def)
	if _suspend:
		var off := Economy.is_suspended(b)
		_suspend.text = "Resume" if off else "Suspend"
		_suspend.theme_type_variation = "GoButton" if off else ""
	if _upgrade_text:
		_refresh_upgrade(b)
	if _built_with:
		_built_with.text = "Built with %s." % BuildingInfo.built_with(b)
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
	if _trade_box:
		_trade_box.refresh()


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
		var amount := UITheme.label(UITheme.number(qty), "HeadingLabel")
		row.add_child(amount)
		_goods_grid.add_child(tile)
	if _goods_grid.get_child_count() == 0:
		var empty := _body("Nothing stored yet.")
		empty.theme_type_variation = "SmallLabel"
		_goods_grid.add_child(empty)
	_layout.call_deferred()  # the window may need to grow or shrink for the new rows


## Supermarket: one row per shelf with its food, price tag and price, a bar of how much has sold,
## and an ✕ to take it down.
func _build_shelves(b: Dictionary) -> void:
	var box := _section("Shelves")
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
		column.add_child(title)
		var bar := ProgressBar.new()
		bar.theme_type_variation = "GoldBar"
		bar.show_percentage = false
		bar.custom_minimum_size.y = 12
		column.add_child(bar)
		var detail := _body("")
		detail.theme_type_variation = "SmallLabel"
		column.add_child(detail)
		var take_down := RoundButton.make("BackButton", "close", "", UITheme.ROUND_ICON_SIZE - 6)
		take_down.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		take_down.pressed.connect(func(): clear_shelf_requested.emit(building_id, i))
		row.add_child(take_down)
		_shelf_rows.append({"icon": icon, "title": title, "bar": bar, "detail": detail, "take_down": take_down})


## "Put on a shelf": choose the item, how much (a slider, or All) and its price tag. The lines
## under it show what that would bring before the player commits: the price, how fast the
## village would buy it, how long it takes, and the profit. Only what this store sells is listed
## (its "sells" categories), and only what's in stock or on its shelves is shown.
func _build_stock_form() -> void:
	var box := _section("Put on a shelf")
	var items := HFlowContainer.new()  # wraps onto more rows when the store sells many goods
	items.add_theme_constant_override("h_separation", 6)
	items.add_theme_constant_override("v_separation", 6)
	box.add_child(items)
	for res in Economy.store_products(Economy.building(building_id).type):
		var button := Button.new()
		button.icon = UITheme.icon(res)
		button.expand_icon = true
		UITheme.size_button(button, "small")
		button.custom_minimum_size.x = 150
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	all.theme_type_variation = ""
	all.text = "All"
	UITheme.size_button(all, "small")
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
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.size_button(button, "small")
		button.custom_minimum_size = Vector2(0, 62)  # two lines: the tag's name and its price change
		button.add_theme_font_size_override("font_size", UITheme.SIZE_SMALL)
		button.pressed.connect(func():
			_chosen_tag = tag
			_refresh())
		tags_row.add_child(button)
		_tag_buttons[tag] = button

	_preview["price"] = _figure_row(box, "Price each:")
	_preview["time"] = _figure_row(box, "Sells out in about:")
	_preview["profit"] = _figure_row(box, "Profit:")
	_stock_button = Button.new()
	_stock_button.theme_type_variation = ""
	UITheme.size_button(_stock_button, "big")
	_stock_button.custom_minimum_size.x = 300
	_stock_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Greyed when it can't go on a shelf, but still tappable, so the player is told why.
	_stock_button.pressed.connect(func(): stock_requested.emit(building_id, _chosen_item, _chosen_amount, _chosen_tag))
	box.add_child(_stock_button)


## The form's starting choice: the first item in stock that isn't on this store's shelves yet
## (else the first one), all of it, at the default price tag.
func choose_defaults() -> void:
	var products := Economy.store_products(Economy.building(building_id).type)
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
			row.detail.visible = false
			continue
		row.detail.visible = true
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
		var on_shelf := Economy.store_has_product(building_id, res)
		# Many goods: show only those you have, are selling here, or have picked.
		_item_buttons[res].visible = have > 0 or on_shelf or res == _chosen_item
		_item_buttons[res].text = "%s  %s" % [BuildingInfo.resource_name(res), "on a shelf" if on_shelf else UITheme.number(have)]
		if res == _chosen_item:
			_item_buttons[res].theme_type_variation = "ChipOnButton"
		else:
			_item_buttons[res].theme_type_variation = "ChipButton" if have > 0 and not on_shelf else "BackButton"
	for tag in _tag_buttons:
		_tag_buttons[tag].theme_type_variation = "ChipOnButton" if tag == _chosen_tag else "ChipButton"
	var have := int(stock.get(_chosen_item, 0))
	_chosen_amount = clampi(_chosen_amount, mini(1, have), have)
	_amount_slider.max_value = maxi(have, 1)
	_amount_slider.editable = have > 1
	_amount_slider.set_value_no_signal(maxi(_chosen_amount, 1))
	_amount_label.text = UITheme.number(_chosen_amount)
	var p := Economy.stock_preview(building_id, _chosen_item, _chosen_amount, _chosen_tag)
	_preview.price.text = UITheme.price(int(p.price))
	_preview.time.text = UITheme.duration(p.seconds) if p.seconds < INF else "nobody would buy"
	_preview.profit.text = UITheme.money(int(p.profit))
	UITheme.set_font_color(_preview.profit, UITheme.GOOD if int(p.profit) >= 0 else UITheme.BAD)
	var item := BuildingInfo.resource_name(_chosen_item)
	if Economy.store_has_product(building_id, _chosen_item):
		_stock_button.text = "%s is already on a shelf here" % item
	elif have <= 0:
		_stock_button.text = "No %s in the warehouse" % item
	else:
		_stock_button.text = "Put %s %s on a shelf" % [UITheme.number(_chosen_amount), item]
	var check := Economy.can_stock_shelf(building_id, _chosen_item, _chosen_amount, _chosen_tag)
	_stock_button.theme_type_variation = "GoButton" if check.ok else "BackButton"


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
	heading.theme_type_variation = "HeadingLabel"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	return column


## An item icon with its amount, e.g. [wheat] 40.
## "[wheat] 40 → [flour] 32 · per hour of work": what one hour of this recipe makes.
func _fill_recipe_row(r: Dictionary) -> void:
	for child in _recipe_row.get_children():
		_recipe_row.remove_child(child)
		child.queue_free()
	_shown_recipe = str(r.get("id", ""))
	for res in r.get("inputs", {}):
		_recipe_row.add_child(_item(res, int(r.inputs[res])))
	if not r.get("inputs", {}).is_empty():
		_recipe_row.add_child(_icon("arrow", 34))
	for res in r.get("outputs", {}):
		_recipe_row.add_child(_item(res, int(r.outputs[res])))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_row.add_child(spacer)
	_recipe_row.add_child(_icon("clock", 30))
	_recipe_row.add_child(_body("per %s of work" % ("hour" if is_equal_approx(float(r.get("duration", 3600.0)), 3600.0) else UITheme.duration(float(r.duration)))))


func _item(resource_id: String, amount: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.tooltip_text = BuildingInfo.resource_name(resource_id)
	row.add_child(_icon(resource_id, 38))
	var label := Label.new()
	label.text = "x%d" % amount
	label.theme_type_variation = "HeadingLabel"
	row.add_child(label)
	return row


func _icon(icon_name: String, side: float) -> TextureRect:
	return UITheme.icon_rect(icon_name, side)


func _body(text: String) -> Label:
	return UITheme.label(text)


## Body text that wraps onto more lines instead of making the window wider.
func _wrapped(text: String) -> Label:
	return UITheme.wrapped(text, WIDTH - 70)

