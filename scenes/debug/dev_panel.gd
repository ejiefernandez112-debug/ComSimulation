extends ModalWindow
## Developer tools (plan.md §10). Only loaded in test builds (main.gd checks OS.is_debug_build()),
## so real players never see it. Opens with F12 on a computer, or 5 quick taps on the cash bar
## (top-right corner) on a phone.
## Cash: set it to any amount (negative to test debt) or add to it. Changes go through Economy
## like everything else; they aren't counted as income in the statistics.
## Rent: raise or lower the rent per household of each housing type (plan.md §5.18), or reset it
## to the rent in buildings.json. Kept in the save until reset.

const QUICK_ADD := [1000, 10000, 100000]
const RENT_STEPS := [-1, 1, 10]  # dollars an hour per button
const TAPS_TO_OPEN := 5
const TAP_WINDOW_MS := 2000  # the taps must all land within this time
const CORNER := Vector2(280, 70)  # the top-right area holding the cash bar

var _cash: Label
var _amount: LineEdit
var _message: Label
var _rent_labels := {}  # home type id -> Label showing its rent
var _taps: Array = []  # times of recent taps on the cash bar (ms)


func _ready() -> void:
	super()
	var hint := _text("Only in test builds. Opens with F12, or 5 quick taps on the cash bar.")
	hint.add_theme_font_size_override("font_size", 15)
	hint.modulate.a = 0.75
	content.add_child(hint)

	var box := _section("Cash")
	_cash = _text("")
	_cash.add_theme_font_size_override("font_size", 26)
	box.add_child(_cash)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_amount = LineEdit.new()
	_amount.placeholder_text = "Amount in $, e.g. 5000"
	_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount.custom_minimum_size.y = 46
	_amount.text_submitted.connect(func(_text: String): _add())
	row.add_child(_amount)
	row.add_child(_button("Add", "GreenButton", _add))
	row.add_child(_button("Set to", "BlueButton", _set_cash))
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	box.add_child(quick)
	for amount in QUICK_ADD:
		var button := _button("+" + UITheme.dollars(amount), "YellowButton", _quick_add.bind(amount))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick.add_child(button)
	quick.add_child(_button("Set $0", "RedButton", func(): _apply(Economy.dev_set_cash(0), "Cash set to $0")))
	_message = _text("")
	box.add_child(_message)

	var rent_box := _section("Rent per household (per hour)")
	var rent_hint := _text("Households that can't afford the new rent move to cheaper homes, or become homeless.")
	rent_hint.add_theme_font_size_override("font_size", 15)
	rent_hint.modulate.a = 0.75
	rent_box.add_child(rent_hint)
	for type_id in GameData.buildings:
		var def: Dictionary = GameData.buildings[type_id]
		if int(def.get("households", 0)) <= 0 or def.get("hut", false):
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		rent_box.add_child(line)
		var name_label := _text(def.name)
		name_label.custom_minimum_size.x = 150
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value := _text("")
		value.custom_minimum_size.x = 110
		line.add_child(value)
		_rent_labels[type_id] = value
		for step in RENT_STEPS:
			line.add_child(_button("%+d" % step, "YellowButton" if step > 0 else "BlueButton", _change_rent.bind(type_id, step)))
		line.add_child(_button("Reset", "RedButton", _reset_rent.bind(type_id)))
	Economy.changed.connect(_refresh)


func show_dev() -> void:
	_message.text = ""
	open("Developer")
	_refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		if visible:
			close()
		else:
			show_dev()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not visible:
		if event.position.x >= size.x - CORNER.x and event.position.y <= CORNER.y:
			var now := Time.get_ticks_msec()
			_taps.append(now)
			_taps = _taps.filter(func(t: int): return now - t <= TAP_WINDOW_MS)
			if _taps.size() >= TAPS_TO_OPEN:
				_taps.clear()
				show_dev()


func _refresh() -> void:
	if visible:
		_cash.text = "Now: %s" % UITheme.money(Economy.currency())
		for type_id in _rent_labels:
			var rent := Economy.rent_per_household(type_id)
			_rent_labels[type_id].text = ("free" if rent <= 0.0 else UITheme.price(roundi(rent * 100.0))) + (" *" if Economy.rent_changed(type_id) else "")


## Rent up or down by `step` dollars an hour (never below free).
func _change_rent(type_id: String, step: int) -> void:
	var rent := maxf(Economy.rent_per_household(type_id) + step, 0.0)
	_apply(Economy.dev_set_rent(type_id, rent), "%s rent: %s per household an hour (* = changed by you)" % [GameData.buildings[type_id].name, UITheme.price(roundi(rent * 100.0))])


func _reset_rent(type_id: String) -> void:
	_apply(Economy.dev_set_rent(type_id, -1.0), "%s rent back to the data file's" % GameData.buildings[type_id].name)


func _add() -> void:
	var amount = _read_amount()  # a number of dollars, or null if the typing wasn't one
	if amount != null:
		_apply(Economy.dev_add_cash(amount), "Added %s" % UITheme.dollars(amount))


func _set_cash() -> void:
	var amount = _read_amount()  # a number of dollars, or null if the typing wasn't one
	if amount != null:
		_apply(Economy.dev_set_cash(amount), "Cash set to %s" % UITheme.dollars(amount))


func _quick_add(amount: int) -> void:
	_apply(Economy.dev_add_cash(amount), "Added %s" % UITheme.dollars(amount))


## The typed amount as a whole number of dollars ("$5,000" and "5000" both work), or null.
func _read_amount() -> Variant:
	var text := _amount.text.replace("$", "").replace(",", "").strip_edges()
	if not text.is_valid_int():
		_message.text = "Type a whole number of dollars, e.g. 5000 (or -500 to test debt)."
		return null
	return text.to_int()


func _apply(result: Dictionary, done: String) -> void:
	_message.text = done if result.ok else result.error
	_refresh()


func _section(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Inset"
	content.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 19)
	column.add_child(heading)
	return column


func _button(text: String, variation: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(action)
	return button


func _text(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "BodyLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 70
	return label
