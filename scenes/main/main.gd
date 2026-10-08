extends Node
## Root of the game: the Village View (the island) with the UI drawn on top of it.
## Connects the pieces: taps on the map -> selecting buildings or Placement Mode, and requests
## from the UI (collect, produce, build) -> Economy, with feedback on the map and in the HUD.

const SoundCues = preload("res://scenes/main/sound_cues.gd")
const FrameRate = preload("res://scenes/main/frame_rate.gd")

@onready var village: Node2D = $Village
@onready var ui_root: Control = $UI/Root
@onready var hud: Control = $UI/Root/HUD
@onready var menu_bar: Control = $UI/Root/MenuBar
@onready var building_bar: Control = $UI/Root/BuildingBar
@onready var build_menu: Control = $UI/Root/BuildMenu
@onready var building_panel: ModalWindow = $UI/Root/BuildingPanel
@onready var settings_panel: ModalWindow = $UI/Root/SettingsPanel
@onready var stats_panel: ModalWindow = $UI/Root/StatsPanel
@onready var confirm_dialog: ModalWindow = $UI/Root/ConfirmDialog
var _warehouse_panel: ModalWindow  # made in code (_ready)
var _sound_cues: SoundCues  # sounds for things that happen by themselves (made in _ready)
var _glass_blur = null  # the "glass_blur" setting the look was last built for (null = not yet)
## The Developer window's Look page made every window again (rebuild_windows): skip the start-up
## messages and open that page again.
static var _look_rebuild := false


func _ready() -> void:
	_apply_glass()
	Settings.changed.connect(_apply_glass)
	_sound_cues = SoundCues.new()
	_sound_cues.name = "SoundCues"
	add_child(_sound_cues)
	var frame_rate := FrameRate.new()  # about 60 pictures a second, 30 when untouched (keeps laptops and phones cool)
	frame_rate.name = "FrameRate"
	add_child(frame_rate)
	village.ghost_moved.connect(build_menu.show_ghost_state)
	village.building_tapped.connect(_on_building_tapped)
	village.bubble_tapped.connect(_collect)
	village.empty_tapped.connect(func():
		_deselect()
		build_menu.close())  # tapping the map outside the Build panel closes it
	build_menu.placement_requested.connect(_start_placement)
	build_menu.placement_cancelled.connect(village.stop_placement)
	build_menu.placement_confirmed.connect(_place)
	build_menu.road_requested.connect(_start_roads)
	build_menu.road_remove_toggled.connect(village.set_road_removing)
	build_menu.tab_changed.connect(menu_bar.set_open)
	building_bar.info_requested.connect(building_panel.show_building)
	building_bar.collect_requested.connect(_collect)
	building_bar.build_requested.connect(build_menu.open)
	building_bar.move_requested.connect(_start_move)
	building_panel.collect_requested.connect(_collect)
	building_panel.start_batch_requested.connect(_ask_start_batch)
	building_panel.switch_product_requested.connect(_ask_switch_product)
	building_panel.cancel_batch_requested.connect(_ask_cancel_batch)
	building_panel.closed.connect(_on_panel_closed)
	building_panel.move_requested.connect(_start_move)
	building_panel.demolish_requested.connect(_ask_demolish)
	building_panel.staffing_requested.connect(_set_staffing)
	building_panel.suspend_requested.connect(_ask_suspend)
	building_panel.resume_requested.connect(_resume)
	building_panel.upgrade_requested.connect(_ask_upgrade)
	building_panel.stock_requested.connect(_stock)
	building_panel.trade_requested.connect(_trade)
	building_panel.clear_shelf_requested.connect(_ask_clear_shelf)
	Economy.shelves_sold.connect(_on_shelves_sold)
	Economy.people_changed.connect(_on_people_changed)
	menu_bar.tile_pressed.connect(_on_menu_tile)
	menu_bar.category_pressed.connect(_on_category)
	menu_bar.coming_soon.connect(func(title): hud.toast("%s is coming soon" % title))
	hud.happiness_pressed.connect(func(): stats_panel.show_stats("happiness"))
	settings_panel.new_game_requested.connect(_ask_new_game)
	Economy.water_bill_paid.connect(func(cost: int, m3: float):
		hud.toast("Water bill paid: %s for %s m³" % [UITheme.money(cost), UITheme.number(roundi(m3))], Economy.currency() < 0))
	Economy.power_bill_paid.connect(func(cost: int, mwh: float):
		hud.toast("Power bill paid: %s for %s MWh" % [UITheme.money(cost), UITheme.number(roundi(mwh))], Economy.currency() < 0))
	_warehouse_panel = load("res://scenes/ui/warehouse_panel.gd").new()
	_warehouse_panel.name = "WarehousePanel"
	ui_root.add_child(_warehouse_panel)
	ui_root.move_child(_warehouse_panel, confirm_dialog.get_index())  # under the "Are you sure?" window
	_warehouse_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The build toolbar steps aside for anything else that uses the bottom of the screen, and for
	# windows (on a computer a docked window can reach down to the bottom edge). It stays under the
	# Build panel, which sits just above it.
	menu_bar.hide_while_visible([building_bar, build_menu.placing_bar,
		building_panel, settings_panel, stats_panel, _warehouse_panel])
	# Developer tools exist only in test builds (plan.md §10): never loaded for real players.
	if OS.is_debug_build():
		var dev_panel: Control = load("res://scenes/debug/dev_panel.gd").new()
		dev_panel.name = "DevPanel"
		ui_root.add_child(dev_panel)
		dev_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # made in code, so give it the whole screen
		var overlay: Control = load("res://scenes/debug/perf_overlay.gd").new()
		overlay.name = "PerfOverlay"  # the Developer window finds it by this name
		overlay.village = village
		ui_root.add_child(overlay)
		if _look_rebuild:
			dev_panel.show_dev.call_deferred("look")
	if _look_rebuild:
		_look_rebuild = false
	else:
		_welcome_back.call_deferred()  # once the screen has its real size


## Start-up: what happened while the game was closed, and any problem reading the save.
func _welcome_back() -> void:
	var welcome: ModalWindow = load("res://scenes/ui/welcome_back.gd").new()
	welcome.name = "WelcomeBack"
	ui_root.add_child(welcome)
	welcome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	welcome.show_if_away()
	for note in Economy.save_notes:
		hud.toast(note, true)


## Settings → Start over: everything is lost, so ask first.
func _ask_new_game() -> void:
	settings_panel.close()
	confirm_dialog.ask("Start over?",
		"Your buildings, goods and cash are gone for good, and you begin again with the starting kit.",
		0, {}, "Start over", _new_game)


func _new_game() -> void:
	_deselect()
	building_panel.close()
	_sound_cues.forget()
	Economy.start_new_game()
	hud.toast("New game started. Good luck!")


## The frosted glass setting (Settings → Frosted glass): rebuild the look when it changes.
func _apply_glass() -> void:
	var blur: bool = Settings.get_value("glass_blur")
	if blur == _glass_blur:
		return
	_glass_blur = blur
	ui_root.theme = UITheme.build(blur)
	UITheme.set_frosted(get_tree(), blur)


## The Developer window's Look page changed a colour or size: build the look again.
func restyle() -> void:
	_glass_blur = null
	_apply_glass()


## The Look page's "Rebuild windows": load the whole screen again, so every window is made with
## the new sizes and icons (the game itself lives in Economy and carries on).
func rebuild_windows() -> void:
	_look_rebuild = true
	get_tree().reload_current_scene()


## A category in the bottom build toolbar was tapped: open (or close) the Build panel on it.
func _on_category(tab_id: String) -> void:
	_deselect()
	building_panel.close()
	build_menu.toggle(tab_id)


## A screen button in the top-left corner was tapped.
func _on_menu_tile(id: String) -> void:
	build_menu.close()
	match id:
		"settings":
			settings_panel.show_settings()
		"stats":
			stats_panel.show_stats()
		"warehouse":
			_deselect()
			_warehouse_panel.show_stock()


func _unhandled_input(event: InputEvent) -> void:
	# Esc or right-click cancels Placement Mode, or else clears the selection.
	var esc: bool = event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE
	var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if not (esc or right_click):
		return
	if build_menu.is_placing():
		build_menu.cancel_placement()
	else:
		_deselect()
	get_viewport().set_input_as_handled()


## Tapping a building selects it; like Clash of Clans, a building with goods waiting also collects.
## Buildings with workers (farms, mills, bakeries, warehouses, water plants…) and power buildings then
## open their info window (docked on the left on a computer); the others (City Hall, houses) show the
## building card at the bottom.
func _on_building_tapped(building_id: String) -> void:
	build_menu.close()
	var b := Economy.building(building_id)
	if not Economy.waiting_goods(b).is_empty():
		_collect(building_id)
	village.select(building_id)
	if GameData.buildings[b.type].category in ["extractor", "processor", "storage", "utility", "construction", "power", "retail", "trade", "service"]:
		building_bar.close()
		building_panel.show_building(building_id)
	else:
		Sfx.play("select")  # the info window has its own opening sound
		building_bar.show_for(building_id)


## Closing the info window also un-highlights the building, unless its action bar is still up.
func _on_panel_closed() -> void:
	if building_bar.building_id == "":
		village.deselect()


func _deselect() -> void:
	village.deselect()
	building_bar.close()


## A red "can't do that" message, with the error sound.
func _refuse(text: String) -> void:
	Sfx.play("error")
	hud.toast(text, true)


## The same in Placement, Move or Road Mode, where the hint bar says why.
func _refuse_placement(text: String) -> void:
	Sfx.play("error")
	build_menu.show_hint(text)


## A red heads-up about something that is going wrong (not a refused action), with the warning sound.
func _warn(text: String) -> void:
	Sfx.play("warning")
	hud.toast(text, true)


## One tap collects every building of the same type (all Bakeries, all Mills…) at once.
func _collect(building_id: String) -> void:
	var result := Economy.collect_group(building_id)
	if result.ok:
		Sfx.play("collect")
		for id in result.by_building:
			village.show_gain(id, result.by_building[id])  # "+16 [bread]" over each one emptied
		if result.left_over:
			_warn("The warehouse is full: the rest waits inside the buildings.")
	else:
		_refuse(result.error)


## Starting a batch pays its ingredients and wages at once and locks in its bonus (plan.md §5.1),
## so show the whole cost first and ask.
func _ask_start_batch(building_id: String, recipe_id: String, hours: int, bonus: String) -> void:
	var b := Economy.building(building_id)
	var check := Economy.can_start_batch(building_id, recipe_id, hours, bonus)
	if not check.ok:
		_refuse(check.error)
		return
	var item := BuildingInfo.resource_name(check.output)
	var lines: Array[String] = []
	var finish := "when workers come" if is_inf(float(check.finishes_at)) else "about %s" % UITheme.clock(float(check.finishes_at), TimeService.now())
	var work := float(check.seconds) / 3600.0  # hours of work (whole in the real data)
	var hours_text := str(roundi(work)) if is_equal_approx(work, roundf(work)) else "%.1f" % work
	lines.append("Makes %s in %s h (done %s)." % [BuildingInfo.amounts(check.units), hours_text, finish])
	for line in check.ingredients:
		lines.append("Ingredients: %s %s ⋅ %s" % [UITheme.number(int(line.qty)), BuildingInfo.resource_name(line.res), UITheme.money(roundi(float(line.cost)))])
	lines.append("Labor: %d workers ⋅ %s" % [int(check.workers), UITheme.money(int(check.wages))])
	if Economy.power_problem(Economy.building(building_id)) == "no_grid":
		lines.append("No power: it won't work until a Substation reaches it.")
	lines.append("Total: %s" % UITheme.money(roundi(float(check.total))))  # includes water and power
	# Its first batch chooses what it makes (plan.md §5.21): say so when that's for good.
	if BuildingInfo.choosing(b):
		if Economy.is_switchable(b.type):
			lines.append("Switching later costs %s." % UITheme.money(Economy.switch_fee(b)))
		else:
			lines.append("It will make %s for good." % item)
	confirm_dialog.ask("Start this batch?", "\n".join(lines), 0, {}, "Start",
		_start_batch.bind(building_id, recipe_id, hours, bonus), "Back", "GoButton")


## Switching a Plantation (or Ranch) to another product costs a fee (plan.md §5.21), so ask.
func _ask_switch_product(building_id: String, recipe_id: String) -> void:
	var check := Economy.can_switch_product(building_id, recipe_id)
	if not check.ok:
		_refuse(check.error)
		return
	var b := Economy.building(building_id)
	var item := BuildingInfo.resource_name(BuildingInfo.output_of(BuildingInfo.recipe_of({"type": b.type, "product": recipe_id})))
	var now_item := BuildingInfo.resource_name(BuildingInfo.output_of(BuildingInfo.recipe_of(b)))
	confirm_dialog.ask("Switch to %s?" % item, "Stops making %s. Switching costs %s." % [now_item, UITheme.money(int(check.fee))],
		0, {}, "Switch", _switch_product.bind(building_id, recipe_id), "Back", "GoButton")


func _switch_product(building_id: String, recipe_id: String) -> void:
	var result := Economy.switch_product(building_id, recipe_id)
	if not result.ok:
		_refuse(result.error)
		return


func _start_batch(building_id: String, recipe_id: String, hours: int, bonus: String) -> void:
	var result := Economy.start_batch(building_id, recipe_id, hours, bonus)
	if not result.ok:
		_refuse(result.error)
		return
	Sfx.play("start_batch")
	var used := {}
	for line in result.ingredients:
		used[line.res] = -int(line.qty)
	if not used.is_empty():
		village.show_gain(building_id, used)  # "-960 [wheat]" rises from the building


## Cancelling keeps the hours already made; the rest gives back only part, so ask first.
func _ask_cancel_batch(building_id: String) -> void:
	var check := Economy.can_cancel_batch(building_id)
	if not check.ok:
		_refuse(check.error)
		return
	confirm_dialog.ask("Cancel this batch?",
		"What it made so far stays. You get back %d%% of the ingredients and wages of the %d hours not made yet." % [roundi(100.0 * float(GameData.config.get("cancel_refund_in_progress", 0.0))), int(check.hours_left)],
		int(check.money), check.refund, "Cancel batch", _cancel_batch.bind(building_id))


func _cancel_batch(building_id: String) -> void:
	var result := Economy.cancel_batch(building_id)
	if result.ok:
		village.show_gain(building_id, result.refund)
	else:
		_refuse(result.error)


func _ask_demolish(building_id: String) -> void:
	var check := Economy.can_demolish(building_id)
	if not check.ok:
		_refuse(check.error)
		return
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	# No money back: every unit of material it was built with, and the goods inside, go to the
	# warehouse (plan.md §5.15).
	var back: Dictionary = check.materials.duplicate()
	for res in check.goods:
		back[res] = int(back.get(res, 0)) + int(check.goods[res])
	confirm_dialog.ask("Demolish %s?" % building_name,
		"No money comes back, but its building materials and the goods inside go to your warehouse:",
		0, back, "Demolish", _demolish.bind(building_id))


func _demolish(building_id: String) -> void:
	var result := Economy.demolish(building_id)
	if result.ok:
		building_panel.close()
	else:
		_refuse(result.error)


func _start_placement(type_id: String) -> void:
	_deselect()
	village.start_placement(type_id, build_menu.free_map_centre())  # in view, above the Build panel


## Move: the same Placement Mode as building, but for a building that already exists.
## Everything inside it keeps working while it moves.
func _start_move(building_id: String) -> void:
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	building_panel.close()
	_deselect()
	build_menu.show_placing("Moving %s: drag it to a free spot, then tap the blue tick" % building_name)
	village.start_moving(building_id)  # after the bar is up, so the ghost's first check reaches it


## Road Mode (plan.md §5.20): drag across the map to lay or remove road.
func _start_roads() -> void:
	_deselect()
	village.start_road_mode()


## ✓ in Placement Mode: build (or move) the building where the ghost stands. In Road Mode: build
## (or remove) the road drawn, and stay in Road Mode for the next stretch.
func _place() -> void:
	if village.road_mode:
		var done: Dictionary = village.confirm_road()
		if not done.ok:
			_refuse_placement(done.error)
		else:
			Sfx.play("road")
		return
	var cell: Vector2i = village.ghost_cell
	if village.moving_id != "":
		var result := Economy.move(village.moving_id, cell)
		if result.ok:
			Sfx.play("place")
			village.stop_placement()
			build_menu.end_placement()
		else:
			_refuse_placement(result.error)  # stay in Move mode so the player can try another tile
		return
	var type_id: String = village.placing_type
	var result := Economy.build(type_id, cell)
	if result.ok:
		Sfx.play("place")
		village.stop_placement()
		build_menu.end_placement()
		var built := Economy.building(str(result.get("building_id", "")))
		if not built.is_empty() and not Economy.on_road(built):
			_warn("No road reaches it yet, so it gets no workers.")
		# Heads-up: once finished, its jobs won't all be filled: there aren't enough adults.
		var levels: Dictionary = GameData.config.get("staffing_levels", {})
		var share := float(levels.get(GameData.config.get("default_staffing", "high"), 1.0))
		var workers := roundi(int(GameData.buildings[type_id].get("max_workers", 0)) * share)
		if workers > 0 and Economy.employment().jobs + workers > Economy.adults():
			var seconds := float(GameData.config.get("population_growth_seconds", 0))
			var homes_full: bool = Economy.employment().jobs + workers > Economy.adult_room()
			var needs_home := bool(GameData.config.get("move_in_needs_home", true))
			if seconds > 0.0 and homes_full and needs_home:
				_warn("Not enough people for its jobs: build homes.")
			elif seconds > 0.0 and homes_full:
				_warn("No free homes for new workers: they'll live in huts. Build homes.")
			elif seconds <= 0.0:
				_warn("Not enough adults for all the jobs.")
	else:
		_refuse_placement(result.error)  # stay in Placement Mode so the player can try another tile


## Suspending loses the work in progress, so ask first and show what goes to the warehouse.
func _ask_suspend(building_id: String) -> void:
	var check := Economy.can_suspend(building_id)
	if not check.ok:
		_refuse(check.error)
		return
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	confirm_dialog.ask("Suspend %s?" % building_name,
		"The workers go home. Goods inside go to your warehouse.",
		0, check.goods, "Suspend", _suspend.bind(building_id))


func _suspend(building_id: String) -> void:
	var result := Economy.suspend(building_id)
	if not result.ok:
		_refuse(result.error)
		return
	village.show_gain(building_id, result.moved)
	if not result.kept.is_empty():
		_warn("The warehouse is full: the rest waits inside the building. Collect it later.")


## Upgrading costs materials and a crew and may close the building for a while, so ask first
## (plan.md §5.15).
func _ask_upgrade(building_id: String) -> void:
	var check := Economy.can_upgrade(building_id)
	if not check.ok:
		_refuse(check.error)
		return
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	confirm_dialog.ask("Upgrade %s to Level %d?" % [building_name, int(check.level)],
		"It needs %s. About %s, takes %s." % [BuildingInfo.construction_needs(check), UITheme.money(int(check.cost)), UITheme.duration(float(check.seconds))],
		0, {}, "Upgrade", _upgrade.bind(building_id))


func _upgrade(building_id: String) -> void:
	var result := Economy.upgrade(building_id)
	if result.ok:
		Sfx.play("place")  # construction work begins
	else:
		_refuse(result.error)


func _resume(building_id: String) -> void:
	var result := Economy.resume(building_id)
	if not result.ok:
		_refuse(result.error)


## Supermarket: put food on a shelf at a price tag. It leaves the warehouse now and is paid for
## when the shelf sells out.
func _stock(building_id: String, resource_id: String, qty: int, tag: String) -> void:
	var result := Economy.stock_shelf(building_id, resource_id, qty, tag)
	if result.ok:
		Sfx.play("collect")
		village.show_gain(building_id, {resource_id: -qty})
		building_panel.choose_defaults()  # the form moves on to the next food not on a shelf yet
	else:
		_refuse(result.error)


## Selling to or buying from the Trading Post's trader (plan.md §5.22): instant.
func _trade(side: String, resource_id: String, qty: int) -> void:
	var post: String = building_panel.building_id
	if side == "sell":
		var sold := Economy.trade_sell(resource_id, qty)
		if not sold.ok:
			_refuse(sold.error)
			return
		Sfx.play("sale")
		village.show_gain(post, {resource_id: -qty})
	else:
		var bought := Economy.trade_buy(resource_id, qty)
		if not bought.ok:
			_refuse(bought.error)
			return
		Sfx.play("purchase")
		village.show_gain(post, {resource_id: qty})


## Taking a shelf down ends its sale early, so ask first and show what comes back.
func _ask_clear_shelf(building_id: String, index: int) -> void:
	var check := Economy.can_clear_shelf(building_id, index)
	if not check.ok:
		_refuse(check.error)
		return
	confirm_dialog.ask("Take it off the shelf?",
		"The %s sold are paid now (minus sales tax). The rest goes back to your warehouse." % UITheme.number(check.sold),
		check.paid, check.back, "Take it down", _clear_shelf.bind(building_id, index))


func _clear_shelf(building_id: String, index: int) -> void:
	var result := Economy.clear_shelf(building_id, index)
	if result.ok:
		Sfx.play("collect")
		village.show_gain(building_id, result.back)
	else:
		_refuse(result.error)


## A shelf sold out while playing: say what sold and what it earned.
func _on_shelves_sold(earned: int, sold: Dictionary) -> void:
	Sfx.play("sale")
	var parts: Array[String] = []
	for res in sold:
		parts.append("%s %s" % [UITheme.number(int(sold[res])), GameData.resources.get(res, {}).get("name", res)])
	hud.toast("Sold out: %s. +%s" % [", ".join(parts), UITheme.money(earned)])


## People came or went: one message for the good news, a red one if people left the island.
func _on_people_changed(report: Dictionary) -> void:
	var parts: Array[String] = []
	var arrived := int(report.get("population", 0))
	if arrived > 0:
		parts.append("%d migrant worker%s arrived" % [arrived, "" if arrived == 1 else "s"])
	var born := int(report.get("born", 0))
	if born > 0:
		parts.append("%s born" % ("A baby was" if born == 1 else "%d babies were" % born))
	var for_work := int(report.get("left_for_work", 0))  # grew up with no job waiting
	var grew := int(report.get("grew_up", 0)) - for_work
	if grew > 0:
		parts.append("%d %s grew up and can work" % [grew, "child" if grew == 1 else "children"])
	if not parts.is_empty():
		hud.toast(" ⋅ ".join(parts))
	if for_work > 0:
		_warn("%d grown-up %s left the island to find work: build more jobs to keep them" % [for_work, "child" if for_work == 1 else "children"])
	var left := int(report.get("moved_away", 0)) - for_work
	if left > 0:
		_warn("%d %s left the island: the village is unhappy" % [left, "person" if left == 1 else "people"])


## Low / Medium / High staffing in the building window: fewer workers = slower but cheaper.
func _set_staffing(building_id: String, level: String) -> void:
	var result := Economy.set_staffing(building_id, level)
	if not result.ok:
		_refuse(result.error)
