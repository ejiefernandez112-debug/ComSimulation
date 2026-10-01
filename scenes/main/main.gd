extends Node
## Root of the game: the Village View (the island) with the UI drawn on top of it.

@onready var village: Node2D = $Village
@onready var test_panel: Control = $UI/TestPanel


func _ready() -> void:
	village.cell_tapped.connect(_on_cell_tapped)


func _on_cell_tapped(cell: Vector2i) -> void:
	var building := Economy.building_at(cell)
	if not building.is_empty():
		test_panel.show_status("Tile %s: %s" % [cell, GameData.buildings[building.type].name])
	elif village.island.is_buildable(cell):
		test_panel.show_status("Tile %s: empty, buildable" % cell)
	else:
		test_panel.show_status("Tile %s: outside the building area" % cell)
