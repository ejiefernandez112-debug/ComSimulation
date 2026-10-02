extends ModalWindow
## The building's info window (plan.md §6 Building Panel): what it makes and from what, what
## it's doing now with its job queue, and its storage, with Collect and Make buttons.
## Tapping a filled queue slot cancels that batch; Fill queues as many as fit. Move and Demolish
## sit at the bottom.
## Shows numbers from Economy only; the buttons ask main.gd to act (signals).

signal collect_requested(building_id: String)
signal produce_requested(building_id: String)
signal fill_requested(building_id: String)
signal cancel_requested(building_id: String, index: int)
signal move_requested(building_id: String)
signal demolish_requested(building_id: String)
signal staffing_requested(building_id: String, level: String)
signal suspend_requested(building_id: String)
signal resume_requested(building_id: String)

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
var _workers_text: Label
var _wages_text: Label
var _rate_text: Label
var _workers_note: Label
var _suspend: Button  # Suspend / Resume
var _stock_text: Label  # warehouses: goods stored in all warehouses / their room
var _stock_bar: ProgressBar
var _goods_grid: HFlowContainer  # warehouses: one [icon] amount tile per item in stock
var _shown_stock := {}  # what the grid shows now, so it's only rebuilt when the stock changes


func _ready() -> void:
	super()
	Economy.changed.connect(_refresh)


func show_building(id: String) -> void:
	building_id = id
	var b := Economy.building(id)
	if b.is_empty():
		return
	var def: Dictionary = GameData.buildings[b.type]
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
	_workers_text = null
	_suspend = null
	_stock_bar = null
	_goods_grid = null
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
		var fixed := _wrapped("Always %d workers, no Low or High choice. Upgrading to Level 2 (coming later) doubles them." % int(def.max_workers))
		fixed.add_theme_font_size_override("font_size", 16)
		box.add_child(fixed)
	else:
		_build_staffing_buttons(box, def)
	_workers_text = _figure_row(box, "Workers:")
	_rate_text = _figure_row(box, "Usable Room:" if def.category == "storage" else "Production Rate:")
	_wages_text = _figure_row(box, "Wage:")
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
	var working := _count(w.working)
	var producing: bool = Economy.is_built(b) and Economy.is_producing(b)
	# Short of people only counts while it has work: a halted or idle building sends everyone home.
	var short: bool = producing and w.working < w.wanted - 0.01
	# Workers employed / most it can employ, e.g. "6/8".
	_workers_text.text = "%s/%d" % [working, w.max]
	_workers_text.add_theme_color_override("font_color", UITheme.BAD.darkened(0.3) if short else UITheme.TEXT_DARK)
	_wages_text.text = "%s / hour" % UITheme.money(roundi(w.wages))
	var speed := Economy.building_speed(b)
	_rate_text.text = "%d%%" % floori(speed * 100.0 + 0.001)
	# The details: why it isn't full speed, what that rate makes, and the wage per worker.
	var note := "%s workers at %s / hour each" % [w.type, UITheme.money(roundi(w.wage_each))]
	if def.category == "storage":
		_rate_text.text = "%s of %s" % [UITheme.number(Economy.storage_capacity(b)), UITheme.number(int(def.get("capacity", 0)))]
		note += " · short of workers = less room"
	else:
		var r := BuildingInfo.recipe(b.type)
		var per_minute := 0.0
		for res in r.outputs:
			per_minute += int(r.outputs[res]) * 60.0 / float(r.duration) * speed
		note += " · %.1f %s / min" % [per_minute, BuildingInfo.resource_name(BuildingInfo.output_of(r))]
	if not Economy.is_built(b):
		note = "Workers start when it's built (%d asked for). " % w.wanted + note
	elif Economy.is_suspended(b):
		note = "Suspended: the workers went home and cost nothing. Resume to start again. " + note
	elif short:
		note = "Only %s of the %d asked for: not enough people, build houses. " % [working, w.wanted] + note
	elif Economy.is_halted(b):
		note = "Halted: storage full, so the workers went home and cost nothing. Collect to restart. " + note
	elif not producing:
		note = "Idle: no jobs queued, so the workers went home and cost nothing. Add a job to start. " + note
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


## "6" for whole workers, "4.3" when short of people (an average across the town's buildings).
func _count(workers: float) -> String:
	return str(roundi(workers)) if absf(workers - roundf(workers)) < 0.05 else "%.1f" % workers
