extends Control
## TEMPORARY test buttons in the top-left corner, until the real Retailer (sell) screen exists:
## sell goods, and skip time ahead to test offline production. The HUD and the building buttons
## have replaced everything else that used to be here. Only calls Economy; results go to the HUD.

signal message(text: String, bad: bool)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE  # clicks on empty space fall through to the map
	var row := HBoxContainer.new()
	row.position = Vector2(14, 14)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(row)
	_add_button(row, "Sell all Bread", _sell_all.bind("bread"))
	_add_button(row, "Sell all Flour", _sell_all.bind("flour"))
	_add_button(row, "Sell 50 Wheat", _sell.bind("wheat", 50))
	_add_button(row, "Skip 10 min (test)", _warp.bind(600))


func _add_button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.theme_type_variation = "BlueButton"
	button.add_theme_font_size_override("font_size", 15)
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _sell(resource_id: String, qty: int) -> void:
	var result := Economy.sell(resource_id, qty)
	if result.ok:
		message.emit("Sold %d %s for %s (made for %s, %s tax): %s profit" % [qty, GameData.resources[resource_id].name, UITheme.money(result.gross), UITheme.money(result.cost), UITheme.money(result.tax), UITheme.money(result.profit)], false)
	else:
		message.emit(result.error, true)


func _sell_all(resource_id: String) -> void:
	_sell(resource_id, int(Economy.state.inventory.get(resource_id, 0)))


func _warp(seconds: float) -> void:
	TimeService.warp(seconds)
	var report := Economy.tick()
	message.emit("Skipped 10 minutes" if report.is_empty() else "Skipped 10 minutes: made %s" % str(report), false)
