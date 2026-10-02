extends Control
## TEMPORARY test button in the top-left corner: skip time ahead to test offline production.
## (The Sell buttons are gone: food is sold in a Supermarket now, plan.md §5.16.) Only calls
## Economy; results go to the HUD.

signal message(text: String, bad: bool)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE  # clicks on empty space fall through to the map
	var row := HBoxContainer.new()
	row.position = Vector2(14, 14)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(row)
	_add_button(row, "Skip 10 min (test)", _warp.bind(600))


func _add_button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.theme_type_variation = "BlueButton"
	button.add_theme_font_size_override("font_size", 15)
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _warp(seconds: float) -> void:
	TimeService.warp(seconds)
	var report := Economy.tick()
	message.emit("Skipped 10 minutes" if report.is_empty() else "Skipped 10 minutes: made %s" % str(report), false)
