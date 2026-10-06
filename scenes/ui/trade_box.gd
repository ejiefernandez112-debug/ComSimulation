class_name TradeBox
extends VBoxContainer
## The Trading Post's part of its building window (plan.md §5.22): sell anything you have to the
## trader, or buy anything from it. Pick Sell or Buy, a kind of item, the item and how many; the
## lines under it show the price and what it brings or costs before the player commits.
## Shows numbers from Economy only; its button asks (signal) and main.gd acts.

signal trade_requested(side: String, resource_id: String, qty: int)

const MOST_TO_BUY := 100000  # the slider's top when buying (cash and warehouse room limit it first)
const TITLES := {"price": "Price:", "total": "Total:", "tax": "Sales tax (today's rate):", "earned": "You get:",
	"cost": "They cost you to make:", "profit": "Profit:", "cash": "Cash after:"}

var _width := 400.0
var _side := "sell"  # "sell" (to the trader) or "buy" (from it)
var _kind := ""  # the item category shown ("" = every kind)
var _item := ""
var _amount := 0
var _side_buttons := {}  # side -> Button
var _kind_buttons := {}  # category id ("" = all) -> Button
var _items: HFlowContainer
var _item_buttons := {}  # item -> Button
var _shown_items: Array = []  # the items the grid shows, so it's only rebuilt when that changes
var _empty_note: Label
var _slider: HSlider
var _amount_label: Label
var _lines := {}  # "price", "total", "tax", "earned", "cost", "profit", "cash" -> value Label
var _go: Button


func setup(width: float) -> void:
	_width = width
	add_theme_constant_override("separation", 8)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 8)
	add_child(sides)
	for side in ["sell", "buy"]:
		var button := Button.new()
		button.text = "Sell to the trader" if side == "sell" else "Buy from the trader"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.size_button(button, "normal")
		button.pressed.connect(func():
			_side = side
			_item = ""
			refresh())
		sides.add_child(button)
		_side_buttons[side] = button
	# Kinds of item: All, Food, Crops, ... (game_config.json item_categories).
	var kinds := HFlowContainer.new()
	kinds.add_theme_constant_override("h_separation", 4)
	kinds.add_theme_constant_override("v_separation", 4)
	add_child(kinds)
	var categories: Dictionary = GameData.config.get("item_categories", {})
	for kind in [""] + categories.keys():
		var button := Button.new()
		button.text = "All" if kind == "" else Economy.category_name(kind)
		UITheme.size_button(button, "small")
		button.custom_minimum_size.x = 80
		button.pressed.connect(func():
			_kind = kind
			_item = ""
			refresh())
		kinds.add_child(button)
		_kind_buttons[kind] = button
	_items = HFlowContainer.new()
	_items.add_theme_constant_override("h_separation", 6)
	_items.add_theme_constant_override("v_separation", 6)
	add_child(_items)
	_empty_note = _label("", 16)
	_empty_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_note.custom_minimum_size.x = _width
	add_child(_empty_note)
	# How many: a slider, or All.
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 10)
	add_child(amount_row)
	amount_row.add_child(_label("Amount:", 17))
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.step = 1
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(func(value: float):
		_amount = int(value)
		refresh())
	amount_row.add_child(_slider)
	_amount_label = _label("", 17)
	_amount_label.custom_minimum_size.x = 70
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_row.add_child(_amount_label)
	var all := Button.new()
	all.theme_type_variation = ""
	all.text = "All"
	UITheme.size_button(all, "small")
	all.pressed.connect(func():
		_amount = _most()
		refresh())
	amount_row.add_child(all)
	# What it brings or costs.
	for key in ["price", "total", "tax", "earned", "cost", "profit", "cash"]:
		_lines[key] = _figure_row(key)
	_go = Button.new()
	UITheme.size_button(_go, "big")
	_go.custom_minimum_size.x = 300
	_go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Greyed when it can't trade, but still tappable, so the player is told why.
	_go.pressed.connect(func(): trade_requested.emit(_side, _item, _amount))
	add_child(_go)


## Brings the box up to date (the building window calls this on every Economy change).
func refresh() -> void:
	for side in _side_buttons:
		_side_buttons[side].theme_type_variation = "ChipOnButton" if side == _side else "ChipButton"
	for kind in _kind_buttons:
		_kind_buttons[kind].theme_type_variation = "ChipOnButton" if kind == _kind else "ChipButton"
	var list := _list()
	if list != _shown_items:
		_fill_items(list)
	if not list.has(_item):
		_item = list[0] if not list.is_empty() else ""
		_amount = mini(_most(), 100) if _side == "buy" else _most()
	var stock: Dictionary = Economy.state.inventory
	for res in _item_buttons:
		_item_buttons[res].theme_type_variation = "ChipOnButton" if res == _item else "ChipButton"
		_item_buttons[res].text = "%s  %s" % [BuildingInfo.resource_name(res), UITheme.number(int(stock.get(res, 0)))]
	_empty_note.visible = list.is_empty()
	_empty_note.text = "Nothing of this kind in your warehouse to sell." if _side == "sell" else "Nothing of this kind."
	var most := _most()
	_amount = clampi(_amount, mini(1, most), most)
	_slider.max_value = maxi(most, 1)
	_slider.editable = most > 1
	_slider.set_value_no_signal(maxi(_amount, 1))
	_amount_label.text = UITheme.number(_amount)
	_refresh_lines()


## The items the grid offers: to sell, what's in the warehouse; to buy, everything (of the kind).
func _list() -> Array:
	var out := []
	for res in GameData.resources:
		if _kind != "" and Economy.item_category(res) != _kind:
			continue
		if _side == "sell" and int(Economy.state.inventory.get(res, 0)) <= 0:
			continue
		out.append(res)
	return out


func _fill_items(list: Array) -> void:
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	_item_buttons.clear()
	_shown_items = list
	for res in list:
		var button := Button.new()
		button.icon = UITheme.icon(res)
		button.expand_icon = true
		UITheme.size_button(button, "small")
		button.custom_minimum_size.x = 150
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			_item = res
			_amount = mini(_most(), 100) if _side == "buy" else _most()
			refresh())
		_items.add_child(button)
		_item_buttons[res] = button


## The most that can be traded now: to sell, all you have; to buy, what the cash and the
## warehouse's room allow.
func _most() -> int:
	if _item == "":
		return 0
	if _side == "sell":
		return int(Economy.state.inventory.get(_item, 0))
	var price := Economy.trade_price(_item, "buy")
	var room := Economy.warehouse_cap() - Economy.warehouse_total()
	return clampi(mini(floori(float(Economy.currency()) / maxf(price, 1.0)), room), 0, MOST_TO_BUY)


func _refresh_lines() -> void:
	var selling := _side == "sell"
	for key in ["tax", "earned", "cost", "profit"]:
		_lines[key].get_parent().visible = selling
	_lines.cash.get_parent().visible = not selling
	if _item == "":
		for key in _lines:
			_lines[key].text = "-"
		_go.text = "Choose an item"
		_go.theme_type_variation = "BackButton"
		return
	var item_name := BuildingInfo.resource_name(_item)
	var normal := Economy.unit_price(_item)
	if selling:
		var check := Economy.can_trade_sell(_item, maxi(_amount, 1))
		var price := Economy.trade_price(_item, "sell")
		_lines.price.text = "%s each (the village pays %s)" % [UITheme.price(price), UITheme.price(normal)]
		_lines.total.text = UITheme.money(price * _amount)
		_lines.tax.text = "-" + UITheme.money(int(check.get("tax", 0)))
		_lines.earned.text = UITheme.money(int(check.get("earned", 0)))
		_lines.cost.text = UITheme.money(int(check.get("cost", 0)))
		var profit := int(check.get("profit", 0))
		_lines.profit.text = ("" if profit >= 0 else "-") + UITheme.money(absi(profit))
		UITheme.set_font_color(_lines.profit, UITheme.GOOD if profit >= 0 else UITheme.BAD)
		_go.text = "Sell %s %s" % [UITheme.number(_amount), item_name]
		_go.theme_type_variation = "GoButton" if check.ok and _amount > 0 else "BackButton"
		_go.tooltip_text = "Sold at once; the money reaches cash now" if check.ok else str(check.error)
	else:
		var check := Economy.can_trade_buy(_item, maxi(_amount, 1))
		var price := Economy.trade_price(_item, "buy")
		_lines.price.text = "%s each (the village pays %s)" % [UITheme.price(price), UITheme.price(normal)]
		_lines.total.text = UITheme.money(price * _amount)
		_lines.cash.text = UITheme.money(Economy.currency() - price * _amount)
		_go.text = "Buy %s %s" % [UITheme.number(_amount), item_name]
		_go.theme_type_variation = "GoButton" if check.ok and _amount > 0 else "BackButton"
		_go.tooltip_text = "Paid now; the goods go into your warehouse" if check.ok else str(check.error)


## "Title ........ value". Returns the value label.
func _figure_row(key: String) -> Label:
	var row := HBoxContainer.new()
	add_child(row)
	var title := _label(TITLES[key], 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var value := _label("", 18)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


func _label(text: String, font_size: int) -> Label:
	return UITheme.label(text, UITheme.style_for(font_size))
