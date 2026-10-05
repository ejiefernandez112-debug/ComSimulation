extends ModalWindow
## A small "Are you sure?" window for actions that can't be undone (demolish, cancelling a batch
## that's already being made). Shows a message, what the player gets back, and two buttons.
## Whoever asks passes a function to run if the player says yes.

var _on_yes := Callable()


## money: coins given back; goods: {resource: qty} given back. Either can be empty/0.
## no_text / yes_variation: the "no" button's words and the "yes" button's colour (red for
## things that can't be undone, green for a go-ahead like starting a batch).
func ask(title_text: String, message: String, money: int, goods: Dictionary, yes_text: String, on_yes: Callable,
		no_text := "Keep it", yes_variation := "RedButton") -> void:
	_on_yes = on_yes
	clear_content()
	var text := Label.new()
	text.theme_type_variation = "BodyLabel"
	text.text = message
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = WIDTH - 70  # wrapped text needs a width
	content.add_child(text)

	if money > 0 or not goods.is_empty():
		var box := PanelContainer.new()
		box.theme_type_variation = "Inset"
		content.add_child(box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		var heading := Label.new()
		heading.text = "You get back:"
		heading.add_theme_font_size_override("font_size", 19)
		row.add_child(heading)
		if money > 0:
			row.add_child(_amount("cash", money))
		for res in goods:
			row.add_child(_amount(res, int(goods[res])))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	content.add_child(buttons)
	var no := Button.new()
	no.theme_type_variation = "GreyButton"
	no.text = no_text
	no.custom_minimum_size = Vector2(170, 58)
	no.pressed.connect(close)
	buttons.add_child(no)
	var yes := Button.new()
	yes.theme_type_variation = yes_variation
	yes.text = yes_text
	yes.custom_minimum_size = Vector2(190, 58)
	yes.pressed.connect(_yes)
	buttons.add_child(yes)
	open(title_text)


func _yes() -> void:
	var action := _on_yes
	_on_yes = Callable()
	close()
	if action.is_valid():
		action.call()


## [icon] 125
func _amount(icon_name: String, qty: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var icon := TextureRect.new()
	icon.texture = UITheme.icon(icon_name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(34, 34)
	row.add_child(icon)
	var label := Label.new()
	label.text = UITheme.money(qty) if icon_name == "cash" else UITheme.number(qty)
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	return row
