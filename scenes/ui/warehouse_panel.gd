extends ModalWindow
## The Warehouse window (the Warehouse button in the top-left corner): everything the company has
## in stock, how much room all warehouses have together, and for each item what it cost you and
## what it sells for. Selling happens at a Supermarket or the Trading Post, not here. Only shows
## Economy's numbers.

var _room_text: Label
var _room_bar: ProgressBar
var _list: VBoxContainer
var _shown: Array[String] = []  # the goods the rows are for, in order
var _rows := {}  # resource id -> {"cost", "sells", "qty"}: the labels _refresh updates


func _ready() -> void:
	super()
	Economy.changed.connect(_refresh)


func show_stock() -> void:
	clear_content()
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	content.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	box.add_child(column)
	_room_text = _label("", 19)
	column.add_child(_room_text)
	_room_bar = ProgressBar.new()
	_room_bar.theme_type_variation = "GoldBar"
	_room_bar.show_percentage = false
	_room_bar.custom_minimum_size.y = 18
	column.add_child(_room_bar)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	content.add_child(_list)
	open("Warehouse")
	_refresh()


func _refresh() -> void:
	if not visible or _list == null:
		return
	var stored := Economy.warehouse_total()
	var cap := Economy.warehouse_cap()
	var warehouses := 0
	for b in Economy.state.buildings:
		if GameData.buildings[b.type].category == "storage":
			warehouses += 1
	_room_text.text = "%s / %s goods ⋅ %d warehouse%s" % [UITheme.number(stored), UITheme.number(cap), warehouses, "" if warehouses == 1 else "s"]
	_room_bar.value = 100.0 * stored / maxf(cap, 1.0)
	var inventory: Dictionary = Economy.state.inventory
	var items: Array[String] = []
	for res in GameData.resources:  # in the order of resources.json: raw goods first
		if int(inventory.get(res, 0)) > 0:
			items.append(res)
	# New rows only when the list of goods changed; otherwise just new numbers in the same rows.
	if items != _shown or _list.get_child_count() == 0:
		_shown = items
		_rows.clear()
		for child in _list.get_children():
			_list.remove_child(child)
			child.queue_free()  # perf-ok: only when the list of goods changed
		for res in items:
			_list.add_child(_row(res))
		if items.is_empty():
			var empty := _label("Nothing in stock yet.", 17)
			_list.add_child(empty)
	for res in items:
		var qty := int(inventory[res])
		var labels: Dictionary = _rows[res]
		# What it cost you: the average of all its batches and purchases (its cost tag, §5.14).
		var cost := Economy.average_cost(res)
		labels.cost.text = "cost %s each (%s)" % [UITheme.price(roundi(cost)), UITheme.money(roundi(cost * qty))]
		# What it sells for: the village price in a store, or what the trader pays for the rest
		# (crops, ingredients and materials can't go on a shelf, §5.22).
		if Economy.sold_in_stores(res):
			var price := Economy.unit_price(res)
			labels.sells.text = "sells for %s each (%s)" % [UITheme.price(price), UITheme.money(price * qty)]
		else:
			var paid := Economy.trade_price(res, "sell")
			labels.sells.text = "trader pays %s each (%s)" % [UITheme.price(paid), UITheme.money(paid * qty)]
		labels.qty.text = UITheme.number(qty)


## [icon] Corn                                5,520
##        cost $2.10 each ($11,592)
##        trader pays $2.33 each ($12,862)
## (the numbers are filled in by _refresh).
func _row(res: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(UITheme.icon_rect(res, 36))
	# The name, then what this stock cost you to make or buy (§5.14) and what it sells for.
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	names.add_child(_label(BuildingInfo.resource_name(res), 20))
	var cost := _label("", 14)
	names.add_child(cost)
	var sells := _label("", 14)
	names.add_child(sells)
	var qty := _label("", 20)
	row.add_child(qty)
	_rows[res] = {"cost": cost, "sells": sells, "qty": qty}
	return box


func _label(text: String, font_size: int) -> Label:
	return UITheme.label(text, UITheme.style_for(font_size))
