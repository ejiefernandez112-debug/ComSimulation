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
	hint.theme_type_variation = "BodyLabel"
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
		empty.theme_type_variation = "BodyLabel"
		_list.add_child(empty)


## [icon] Wheat ............ 1,250   worth $2,500
func _row(res: String, qty: int) -> PanelContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UITheme.icon(res)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(36, 36)
	row.add_child(icon)
	var name_label := _label(BuildingInfo.resource_name(res), 20)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	row.add_child(_label(UITheme.number(qty), 20))
	var worth := _label("worth %s" % UITheme.money(qty * Economy.unit_price(res)), 16)
	worth.theme_type_variation = "BodyLabel"
	worth.custom_minimum_size.x = 130
	worth.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(worth)
	return box


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
