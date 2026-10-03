extends Node
## Root of the game: the Village View (the island) with the UI drawn on top of it.
## Connects the pieces: taps on the map -> selecting buildings or Placement Mode, and requests
## from the UI (collect, produce, build) -> Economy, with feedback on the map and in the HUD.

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
@onready var test_panel: Control = $UI/Root/TestPanel
var _warehouse_panel: ModalWindow  # made in code (_ready)


func _ready() -> void:
	ui_root.theme = UITheme.build()
	village.ghost_moved.connect(build_menu.show_ghost_state)
	village.building_tapped.connect(_on_building_tapped)
	village.bubble_tapped.connect(_collect)
	village.empty_tapped.connect(_deselect)
	build_menu.placement_requested.connect(_start_placement)
	build_menu.placement_cancelled.connect(village.stop_placement)
	build_menu.placement_confirmed.connect(_place)
	building_bar.info_requested.connect(building_panel.show_building)
	building_bar.collect_requested.connect(_collect)
	building_bar.produce_requested.connect(_produce)
	building_bar.build_requested.connect(build_menu.open)
	building_bar.move_requested.connect(_start_move)
	building_panel.collect_requested.connect(_collect)
	building_panel.produce_requested.connect(_produce)
	building_panel.fill_requested.connect(_fill)
	building_panel.closed.connect(_on_panel_closed)
	building_panel.cancel_requested.connect(_ask_cancel)
	building_panel.move_requested.connect(_start_move)
	building_panel.demolish_requested.connect(_ask_demolish)
	building_panel.staffing_requested.connect(_set_staffing)
	building_panel.bonus_requested.connect(_set_bonus)
	building_panel.suspend_requested.connect(_ask_suspend)
	building_panel.resume_requested.connect(_resume)
	building_panel.stock_requested.connect(_stock)
	building_panel.clear_shelf_requested.connect(_ask_clear_shelf)
	Economy.shelves_sold.connect(_on_shelves_sold)
	menu_bar.tile_pressed.connect(_on_menu_tile)
	menu_bar.coming_soon.connect(func(title): hud.toast("%s is coming soon" % title))
	# The bottom menu steps aside for anything else that uses the bottom of the screen.
	menu_bar.hide_while_visible([building_bar, build_menu.placing_bar, build_menu.window()])
	test_panel.message.connect(hud.toast)
	hud.happiness_pressed.connect(func(): stats_panel.show_stats("people"))
	settings_panel.new_game_requested.connect(_ask_new_game)
	Economy.water_bill_paid.connect(func(cost: int, m3: float):
		hud.toast("Water bill paid: %s for %s m³" % [UITheme.money(cost), UITheme.number(roundi(m3))], Economy.currency() < 0))
	_warehouse_panel = load("res://scenes/ui/warehouse_panel.gd").new()
	_warehouse_panel.name = "WarehousePanel"
	ui_root.add_child(_warehouse_panel)
	ui_root.move_child(_warehouse_panel, confirm_dialog.get_index())  # under the "Are you sure?" window
	_warehouse_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Developer tools exist only in test builds (plan.md §10): never loaded for real players.
	if OS.is_debug_build():
		var dev_panel: Control = load("res://scenes/debug/dev_panel.gd").new()
		dev_panel.name = "DevPanel"
		ui_root.add_child(dev_panel)
		dev_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # made in code, so give it the whole screen
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
	Economy.start_new_game()
	hud.toast("New game started. Good luck!")


## A card in the bottom menu bar was tapped.
func _on_menu_tile(id: String) -> void:
	match id:
		"build":
			_deselect()
			build_menu.open()
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
## Buildings with workers (farms, mills, bakeries, warehouses…) then open their info window in
## the middle; the others (Construction Office, houses) show the action bar at the bottom.
func _on_building_tapped(building_id: String) -> void:
	var b := Economy.building(building_id)
	if not b.storage.is_empty():
		_collect(building_id)
	village.select(building_id)
	if GameData.buildings[b.type].category in ["extractor", "processor", "storage", "retail"]:
		building_bar.close()
		building_panel.show_building(building_id)
	else:
		building_bar.show_for(building_id)


## Closing the info window also un-highlights the building, unless its action bar is still up.
func _on_panel_closed() -> void:
	if building_bar.building_id == "":
		village.deselect()


func _deselect() -> void:
	village.deselect()
	building_bar.close()


func _collect(building_id: String) -> void:
	var result := Economy.collect(building_id)
	if result.ok:
		village.show_gain(building_id, result.moved)
	else:
		hud.toast(result.error, true)


func _produce(building_id: String) -> void:
	var b := Economy.building(building_id)
	var recipe := BuildingInfo.recipe(b.type)
	var result := Economy.enqueue(building_id, recipe.id)
	if result.ok:
		var used := {}
		for res in recipe.inputs:
			used[res] = -int(recipe.inputs[res])
		village.show_gain(building_id, used)  # "-40 [wheat]" rises from the building
	else:
		hud.toast(result.error, true)


## Queues as many batches as there's room and ingredients for.
func _fill(building_id: String) -> void:
	var result := Economy.fill_queue(building_id, BuildingInfo.recipe(Economy.building(building_id).type).id)
	if result.ok:
		var used := {}
		for res in result.used:
			used[res] = -int(result.used[res])
		village.show_gain(building_id, used)
	else:
		hud.toast(result.error, true)


## Cancelling a batch that's only waiting loses nothing, so it happens straight away.
## Cancelling the batch being made loses ingredients, so we ask first.
func _ask_cancel(building_id: String, index: int) -> void:
	var check := Economy.can_cancel_job(building_id, index)
	if not check.ok:
		hud.toast(check.error, true)
		return
	if not check.in_progress:
		_cancel(building_id, index)
		return
	confirm_dialog.ask("Stop this batch?",
		"It's already being made, so you only get part of the ingredients back.",
		0, check.refund, "Stop it", _cancel.bind(building_id, index))


func _cancel(building_id: String, index: int) -> void:
	var result := Economy.cancel_job(building_id, index)
	if result.ok:
		village.show_gain(building_id, result.refund)
	else:
		hud.toast(result.error, true)


func _ask_demolish(building_id: String) -> void:
	var check := Economy.can_demolish(building_id)
	if not check.ok:
		hud.toast(check.error, true)
		return
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	confirm_dialog.ask("Demolish %s?" % building_name,
		"The building is gone for good. Goods inside it and queued ingredients go to your warehouse.",
		check.money, check.goods, "Demolish", _demolish.bind(building_id))


func _demolish(building_id: String) -> void:
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	var result := Economy.demolish(building_id)
	if result.ok:
		building_panel.close()
		hud.toast("%s demolished. +%s" % [building_name, UITheme.money(result.money)])
	else:
		hud.toast(result.error, true)


func _start_placement(type_id: String) -> void:
	_deselect()
	village.start_placement(type_id)


## Move: the same Placement Mode as building, but for a building that already exists.
## Everything inside it keeps working while it moves.
func _start_move(building_id: String) -> void:
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	building_panel.close()
	_deselect()
	build_menu.show_placing("Moving %s: drag it to a free spot, then tap the green tick" % building_name)
	village.start_moving(building_id)  # after the bar is up, so the ghost's first check reaches it


## ✓ in Placement Mode: build (or move) the building where the ghost stands.
func _place() -> void:
	var cell: Vector2i = village.ghost_cell
	if village.moving_id != "":
		var result := Economy.move(village.moving_id, cell)
		if result.ok:
			village.stop_placement()
			build_menu.end_placement()
		else:
			build_menu.show_hint(result.error)  # stay in Move mode so the player can try another tile
		return
	var type_id: String = village.placing_type
	var result := Economy.build(type_id, cell)
	if result.ok:
		village.stop_placement()
		build_menu.end_placement()
		var room := int(GameData.buildings[type_id].get("population_capacity", 0))
		if room > 0:  # a home only adds room; babies fill it over time
			hud.toast("%s built! Room for %d more people: babies will fill it over time." % [GameData.buildings[type_id].name, room])
		else:
			hud.toast("%s built!" % GameData.buildings[type_id].name)
		# Heads-up: once finished, its jobs won't all be filled even when the houses are full.
		var levels: Dictionary = GameData.config.get("staffing_levels", {})
		var share := float(levels.get(GameData.config.get("default_staffing", "high"), 1.0))
		var workers := roundi(int(GameData.buildings[type_id].get("max_workers", 0)) * share)
		if workers > 0 and Economy.employment().jobs + workers > Economy.population_capacity():
			hud.toast("Not enough people for all the jobs: work will slow down. Build a house!", true)
	else:
		build_menu.show_hint(result.error)  # stay in Placement Mode so the player can try another tile


## Suspending loses the work in progress, so ask first and show what goes to the warehouse.
func _ask_suspend(building_id: String) -> void:
	var check := Economy.can_suspend(building_id)
	if not check.ok:
		hud.toast(check.error, true)
		return
	var building_name: String = GameData.buildings[Economy.building(building_id).type].name
	confirm_dialog.ask("Suspend %s?" % building_name,
		"It switches off: the workers go home and cost nothing. Work in progress is lost, but goods inside and queued ingredients go to your warehouse. Resume any time, for free.",
		0, check.goods, "Suspend", _suspend.bind(building_id))


func _suspend(building_id: String) -> void:
	var result := Economy.suspend(building_id)
	if not result.ok:
		hud.toast(result.error, true)
		return
	village.show_gain(building_id, result.moved)
	if not result.kept.is_empty():
		hud.toast("The warehouse is full: the rest waits inside the building. Collect it later.", true)


func _resume(building_id: String) -> void:
	var result := Economy.resume(building_id)
	if result.ok:
		hud.toast("%s is back to work." % GameData.buildings[Economy.building(building_id).type].name)
	else:
		hud.toast(result.error, true)


## Supermarket: put food on a shelf at a price tag. It leaves the warehouse now and is paid for
## when the shelf sells out.
func _stock(building_id: String, resource_id: String, qty: int, tag: String) -> void:
	var result := Economy.stock_shelf(building_id, resource_id, qty, tag)
	if result.ok:
		village.show_gain(building_id, {resource_id: -qty})
		hud.toast("%s %s on the shelf at %s each" % [UITheme.number(qty), GameData.resources[resource_id].name, UITheme.price(result.price)])
		building_panel.choose_defaults()  # the form moves on to the next food not on a shelf yet
	else:
		hud.toast(result.error, true)


## Taking a shelf down ends its sale early, so ask first and show what comes back.
func _ask_clear_shelf(building_id: String, index: int) -> void:
	var check := Economy.can_clear_shelf(building_id, index)
	if not check.ok:
		hud.toast(check.error, true)
		return
	confirm_dialog.ask("Take it off the shelf?",
		"The %s already sold are paid for now (minus sales tax). The rest goes back to your warehouse." % UITheme.number(check.sold),
		check.paid, check.back, "Take it down", _clear_shelf.bind(building_id, index))


func _clear_shelf(building_id: String, index: int) -> void:
	var result := Economy.clear_shelf(building_id, index)
	if result.ok:
		village.show_gain(building_id, result.back)
	else:
		hud.toast(result.error, true)


## A shelf sold out while playing: say what sold and what it earned.
func _on_shelves_sold(earned: int, sold: Dictionary) -> void:
	var parts: Array[String] = []
	for res in sold:
		parts.append("%s %s" % [UITheme.number(int(sold[res])), GameData.resources.get(res, {}).get("name", res)])
	hud.toast("Sold out: %s. +%s" % [", ".join(parts), UITheme.money(earned)])


## Wage bonus in the building window: costs more per worker, gets free workers first.
func _set_bonus(building_id: String, level: String) -> void:
	var result := Economy.set_bonus(building_id, level)
	if not result.ok:
		hud.toast(result.error, true)


## Low / Medium / High staffing in the building window: fewer workers = slower but cheaper.
func _set_staffing(building_id: String, level: String) -> void:
	var result := Economy.set_staffing(building_id, level)
	if not result.ok:
		hud.toast(result.error, true)
