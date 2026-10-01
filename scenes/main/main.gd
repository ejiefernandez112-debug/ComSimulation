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
	menu_bar.tile_pressed.connect(_on_menu_tile)
	menu_bar.coming_soon.connect(func(title): hud.toast("%s is coming soon" % title))
	# The bottom menu steps aside for anything else that uses the bottom of the screen.
	menu_bar.hide_while_visible([building_bar, build_menu.placing_bar, build_menu.window()])
	test_panel.message.connect(hud.toast)


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
## Industrial buildings (farms, mills, bakeries…) then open their info window in the middle;
## the others (Construction Office, houses) show the action bar at the bottom.
func _on_building_tapped(building_id: String) -> void:
	var b := Economy.building(building_id)
	if not b.storage.is_empty():
		_collect(building_id)
	village.select(building_id)
	if GameData.buildings[b.type].category in ["extractor", "processor"]:
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
		hud.toast("%s demolished. +%s cash" % [building_name, UITheme.number(result.money)])
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
		hud.toast("%s built!" % GameData.buildings[type_id].name)
	else:
		build_menu.show_hint(result.error)  # stay in Placement Mode so the player can try another tile
