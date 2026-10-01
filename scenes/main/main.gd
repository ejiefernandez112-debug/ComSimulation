extends Node
## Root of the game: the Village View (the island) with the UI drawn on top of it.
## Connects the pieces: Build Menu -> Placement Mode on the map -> Economy.build.

@onready var village: Node2D = $Village
@onready var build_menu: Control = $UI/BuildMenu
@onready var test_panel: Control = $UI/TestPanel


func _ready() -> void:
	village.cell_tapped.connect(_on_cell_tapped)
	build_menu.placement_requested.connect(village.start_placement)
	build_menu.placement_cancelled.connect(village.stop_placement)


func _unhandled_input(event: InputEvent) -> void:
	# Esc or right-click cancels Placement Mode.
	if not build_menu.is_placing():
		return
	var esc: bool = event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE
	var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if esc or right_click:
		build_menu.cancel_placement()
		get_viewport().set_input_as_handled()


func _on_cell_tapped(cell: Vector2i) -> void:
	if build_menu.is_placing():
		_place(cell)
		return
	var building := Economy.building_at(cell)
	if not building.is_empty():
		test_panel.show_status("Tile %s: %s" % [cell, GameData.buildings[building.type].name])
	elif village.island.is_buildable(cell):
		test_panel.show_status("Tile %s: empty, buildable" % cell)
	else:
		test_panel.show_status("Tile %s: outside the building area" % cell)


func _place(cell: Vector2i) -> void:
	var type_id: String = village.placing_type
	var result := Economy.build(type_id, cell)
	if result.ok:
		village.stop_placement()
		build_menu.end_placement()
		test_panel.show_status("Built %s." % GameData.buildings[type_id].name)
	else:
		build_menu.show_hint(result.error)  # stay in Placement Mode so the player can try another tile
