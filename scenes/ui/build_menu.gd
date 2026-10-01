extends Control
## Build Menu: a "Build" button that opens a list of buildable buildings with their cost.
## Picking one starts Placement Mode (the village shows a preview and the player taps a tile).
## The list is a side panel on wide screens and a bottom sheet on tall (phone) screens.
## Costs come from GameData; affordability from Economy. This panel decides nothing itself.

signal placement_requested(type_id: String)
signal placement_cancelled

const SIDE_PANEL_WIDTH := 320.0
const BOTTOM_SHEET_TOP := 0.55  # bottom sheet covers the lower 45% of a tall screen

@onready var build_button: Button = $BuildButton
@onready var sheet: PanelContainer = $Sheet
@onready var list: VBoxContainer = $Sheet/Margin/Content/Scroll/List
@onready var placing_bar: PanelContainer = $PlacingBar
@onready var hint: Label = $PlacingBar/Row/Hint

var _entries := {}  # type_id -> Button


func _ready() -> void:
	build_button.pressed.connect(_open)
	$Sheet/Margin/Content/Header/CloseButton.pressed.connect(_close)
	$PlacingBar/Row/CancelButton.pressed.connect(cancel_placement)
	for type_id in GameData.buildings:
		var def: Dictionary = GameData.buildings[type_id]
		if not def.get("buildable", false):
			continue
		var entry := Button.new()
		entry.text = "%s    Cost %d" % [def.name, int(def.build_cost)]
		entry.custom_minimum_size.y = 52
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.pressed.connect(_choose.bind(type_id))
		list.add_child(entry)
		_entries[type_id] = entry
	resized.connect(_apply_layout)
	_apply_layout()
	Economy.changed.connect(_refresh)
	_refresh()


## Called when the building was placed (or placement ended some other way).
func end_placement() -> void:
	placing_bar.hide()
	build_button.show()


func cancel_placement() -> void:
	end_placement()
	placement_cancelled.emit()


func is_placing() -> bool:
	return placing_bar.visible


func show_hint(text: String) -> void:
	hint.text = text


func _open() -> void:
	sheet.show()
	build_button.hide()


func _close() -> void:
	sheet.hide()
	build_button.show()


func _choose(type_id: String) -> void:
	sheet.hide()
	placing_bar.show()
	show_hint("Placing %s: tap a free tile" % GameData.buildings[type_id].name)
	placement_requested.emit(type_id)


## Grey out what the player can't afford right now.
func _refresh() -> void:
	for type_id in _entries:
		_entries[type_id].disabled = Economy.currency() < int(GameData.buildings[type_id].build_cost)


func _apply_layout() -> void:
	if size.x < size.y:
		# Tall screen (phone held upright): bottom sheet across the full width.
		sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
		sheet.anchor_top = BOTTOM_SHEET_TOP
		sheet.offset_left = 0
		sheet.offset_right = 0
		sheet.offset_top = 0
		sheet.offset_bottom = 0
	else:
		# Wide screen (PC / landscape): panel down the right edge.
		sheet.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		sheet.offset_left = -SIDE_PANEL_WIDTH
		sheet.offset_right = 0
		sheet.offset_top = 0
		sheet.offset_bottom = 0
