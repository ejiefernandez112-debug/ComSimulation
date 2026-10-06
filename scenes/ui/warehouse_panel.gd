extends ModalWindow
## The Warehouse window (the Warehouse card in the bottom menu): everything the company has in
## stock, how much room all warehouses have together, and what the goods are worth. Selling
## happens at a Retail store (a later building), not here. Only shows Economy's numbers.

var _room_text: Label
var _room_bar: ProgressBar
var _list: VBoxContainer


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
	var hint := _label("More room: build another Warehouse, or give your warehouses more workers.", 15)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = WIDTH - 70
	content.add_child(hint)
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
	_room_text.text = "%s / %s goods · %d warehouse%s" % [UITheme.number(stored), UITheme.number(cap), warehouses, "" if warehouses == 1 else "s"]
	_room_bar.value = 100.0 * stored / maxf(cap, 1.0)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var inventory: Dictionary = Economy.state.inventory
	var any := false
	for res in GameData.resources:  # in the order of resources.json: raw goods first
		var qty := int(inventory.get(res, 0))
		if qty <= 0:
			continue
		any = true
		_list.add_child(_row(res, qty))
	if not any:
		var empty := _label("Nothing in stock yet. Collect goods from your buildings to fill it.", 17)
		_list.add_child(empty)


## [icon] Wheat (made for $0.30 each) ... 1,250   sells $0.64   worth $800
func _row(res: String, qty: int) -> PanelContainer:
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
	var tag := _label("made for %s each" % UITheme.price(roundi(Economy.average_cost(res))), 14)
	names.add_child(tag)
	row.add_child(_label(UITheme.number(qty), 20))
	var each := _label("sells %s" % UITheme.price(Economy.unit_price(res)), 16)
	each.custom_minimum_size.x = 100
	each.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(each)
	var worth := _label("worth %s" % UITheme.money(qty * Economy.unit_price(res)), 16)
	worth.custom_minimum_size.x = 130
	worth.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(worth)
	return box


func _label(text: String, font_size: int) -> Label:
	return UITheme.label(text, UITheme.style_for(font_size))
