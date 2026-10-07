extends ModalWindow
## A small "Are you sure?" window for actions that can't be undone (demolish, cancelling a batch
## that's already being made). Shows a message, what the player gets back, and two buttons.
## Whoever asks passes a function to run if the player says yes.

var _on_yes := Callable()


func _init() -> void:
	docked = false  # a small question: in the middle of the screen, not docked at the side


## money: coins given back; goods: {resource: qty} given back. Either can be empty/0.
## no_text / yes_variation: the "no" button's words and the "yes" button's colour (red for
## things that can't be undone, blue for a go-ahead like starting a batch).
## yes_variation: "DangerButton" (red) or "GoButton" (blue).
func ask(title_text: String, message: String, money: int, goods: Dictionary, yes_text: String, on_yes: Callable,
		no_text := "Keep it", yes_variation := "DangerButton") -> void:
	_on_yes = on_yes
	clear_content()
	content.add_child(UITheme.wrapped(message, UITheme.WINDOW_WIDTH - 70))

	if money > 0 or not goods.is_empty():
		var box := PanelContainer.new()
		box.theme_type_variation = "Inset"
		content.add_child(box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		row.add_child(UITheme.label("You get back:", "HeadingLabel"))
		if money > 0:
			row.add_child(_amount("cash", money))
		for res in goods:
			row.add_child(_amount(res, int(goods[res])))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	content.add_child(buttons)
	var no := UITheme.button(no_text, "BackButton", "big")
	no.custom_minimum_size.x = 170
	no.pressed.connect(close)
	buttons.add_child(no)
	var yes := UITheme.button(yes_text, yes_variation, "big")
	yes.custom_minimum_size.x = 190
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
	row.add_child(UITheme.icon_rect(icon_name, 34))
	row.add_child(UITheme.label(UITheme.money(qty) if icon_name == "cash" else UITheme.number(qty), "HeadingLabel"))
	return row
