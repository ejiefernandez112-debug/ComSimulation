extends ModalWindow
## The Warehouse window (the Warehouse card in the bottom menu): everything the company has in
## stock, how much room all warehouses have together, and what the goods are worth. Selling
## happens at a Retail store (a later building), not here. Only shows Economy's numbers.

var _room_text: Label
var _room_bar: ProgressBar
var _list: VBoxContainer
var _shown: Array[String] = []  # the goods the rows are for, in order
var _rows := {}  # resource id -> {"tag", "qty", "worth"}: the labels _refresh updates


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
		labels.tag.text = "made for %s each" % UITheme.price(roundi(Economy.average_cost(res)))
		labels.qty.text = UITheme.number(qty)
		labels.worth.text = "worth %s" % UITheme.money(qty * Economy.unit_price(res))


## [icon] Wheat (made for $0.30 each) ... 1,250   worth $800 (the numbers that
## change are filled in by _refresh).
func _row(res: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	row.add_child(UITheme.icon_rect(res, 36))
	# The name, with its cost tag underneath: what this stock cost you to make or buy (§5.14).
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(names)
	names.add_child(_label(BuildingInfo.resource_name(res), 20))
	var tag := _label("", 14)
	names.add_child(tag)
	var qty := _label("", 20)
	row.add_child(qty)
	var worth := _label("", 16)
	worth.custom_minimum_size.x = 130
	worth.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(worth)
	_rows[res] = {"tag": tag, "qty": qty, "worth": worth}
	return box


func _label(text: String, font_size: int) -> Label:
	return UITheme.label(text, UITheme.style_for(font_size))
