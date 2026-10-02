extends Control
## Build Menu (plan.md §6): the Build card in the bottom menu bar opens a window of buildings,
## sorted into tabs down the window's right edge (Farming, Industry, …; the tabs are listed in
## data/build_menu.json and each building names its tab with "menu_tab"). Each card shows a
## building's picture and name. Tapping a card shows its details and cost along the bottom;
## Build (or tapping the same card again) starts Placement Mode. On a computer, pointing at a
## card previews its details too. Wide screens get a window in the middle; tall (phone) screens
## a sheet along the bottom.
## Costs come from GameData; affordability from Economy. This panel decides nothing itself.

signal placement_requested(type_id: String)
signal placement_cancelled
## Placement Mode: ✓ was tapped (put the building where the ghost is).
signal placement_confirmed

const BuildingView = preload("res://scenes/village/building_view.gd")
const MAX_SIZE := Vector2(900, 640)  # the window on wide screens (smaller if the screen is)
const SHEET_TOP := 0.3  # on tall screens the sheet covers the bottom 70%
const HUD_WIDTH := 250.0  # the money / population / warehouse bars down the top-right corner
const TAB_SIZE := Vector2(72, 66)
const CARD_SIZE := Vector2(128, 144)
const SELECTED := Color("ffc93c")
## Locked buildings' pictures are drawn in grey.
const GREY_SHADER := "shader_type canvas_item;
void fragment() {
	float g = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	COLOR = vec4(vec3(g * 0.85 + 0.12), COLOR.a);
}"

@onready var placing_bar: PanelContainer = $PlacingBar
@onready var hint: Label = $PlacingBar/Row/Hint

var _window: Control  # everything the Build button opens: a dimmer over the map + _frame
var _frame: Control  # the window and its tabs; _apply_layout places it
var _close_button: RoundButton
var _title: Label
var _grid: HFlowContainer
var _tab_buttons := {}  # tab id -> its Button
var _cards := {}  # type id -> {"badge": TextureRect, "outline": Panel}
var _tab := ""  # the open tab
var _selected := ""  # the chosen building: Build places this one
var _shown := ""  # the building in the details strip (the selected one, or the one pointed at)
var _grey: ShaderMaterial
var _confirm: RoundButton  # the ✓ in the placing bar
var _placing_text := ""  # the placing bar's hint while the ghost is on a free tile

# The details strip along the bottom.
var _name: Label
var _cost: Label
var _cost_note: Label
var _about: Label
var _makes: HBoxContainer
var _build: Button


func _ready() -> void:
	_make_placing_buttons()
	_grey = ShaderMaterial.new()
	_grey.shader = Shader.new()
	_grey.shader.code = GREY_SHADER
	_make_window()
	resized.connect(_apply_layout)
	Economy.changed.connect(_refresh)


func open() -> void:
	if _tab_buttons.is_empty():
		return
	_window.show()
	_show_tab(_tab if _tab_buttons.has(_tab) else _tab_buttons.keys()[0])
	_apply_layout()
	_frame.pivot_offset = _frame.size / 2.0
	_frame.scale = Vector2(0.9, 0.9)
	_frame.modulate.a = 0.0
	var pop := create_tween().set_parallel()
	pop.tween_property(_frame, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_frame, "modulate:a", 1.0, 0.12)


## Called when the building was placed (or placement ended some other way).
func end_placement() -> void:
	placing_bar.hide()


func cancel_placement() -> void:
	end_placement()
	placement_cancelled.emit()


func is_placing() -> bool:
	return placing_bar.visible


func show_hint(text: String) -> void:
	hint.text = text


## Shows the ✗ / hint / ✓ bar. Moving a building uses it too.
func show_placing(text: String) -> void:
	_window.hide()
	_placing_text = text
	placing_bar.show()
	show_hint(text)


## The ghost moved: on a free tile ✓ works and the hint says what to do; on a blocked one ✓ greys
## out and the hint says why (check = {"ok", "error"}).
func show_ghost_state(check: Dictionary) -> void:
	_confirm.set_disabled(not check.ok)
	show_hint(_placing_text if check.ok else check.error)


## ✗ (cancel) on the left of the placing bar's hint, ✓ (place) on the right.
func _make_placing_buttons() -> void:
	var row: HBoxContainer = $PlacingBar/Row
	var cancel := RoundButton.make("red", "close", "", 64)
	cancel.pressed.connect(cancel_placement)
	row.add_child(cancel)
	row.move_child(cancel, 0)
	_confirm = RoundButton.make("green", "check", "", 64)
	_confirm.pressed.connect(placement_confirmed.emit)
	row.add_child(_confirm)


func _close() -> void:
	_window.hide()


## The window itself (the bottom menu bar steps aside while it's open).
func window() -> Control:
	return _window


func _unhandled_input(event: InputEvent) -> void:
	if _window.visible and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# --- Building the window ---------------------------------------------------------

func _make_window() -> void:
	_window = Control.new()
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.hide()
	add_child(_window)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)  # tapping outside the window closes it
	_window.add_child(dim)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_frame)

	# The page, leaving room on the right for the tabs.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_right = -TAB_SIZE.x
	_frame.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var banner := PanelContainer.new()
	banner.theme_type_variation = "Inset"
	column.add_child(banner)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	banner.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	column.add_child(_make_details())

	# The tabs, added after the page so the open tab is drawn over the page's border.
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.anchor_left = 1.0
	tabs.anchor_right = 1.0
	tabs.offset_left = -TAB_SIZE.x - 1  # over the page's 1px see-through edge, touching its outline
	tabs.offset_top = 80
	_frame.add_child(tabs)
	for tab in GameData.build_menu.get("tabs", []):
		if _types_in(tab.id).is_empty():
			continue  # nothing to build here yet
		var button := Button.new()
		button.theme_type_variation = "SideTab"
		button.icon = UITheme.icon(tab.icon)
		button.expand_icon = true
		button.custom_minimum_size = TAB_SIZE
		button.tooltip_text = tab.name
		button.pressed.connect(_show_tab.bind(tab.id))
		tabs.add_child(button)
		_tab_buttons[tab.id] = button

	# Round close button sitting on the page's top-right corner.
	_close_button = RoundButton.make("red", "close", "", 50)
	_close_button.pressed.connect(_close)
	_frame.add_child(_close_button)


## The strip along the bottom: name and cost, then description and what it makes, and Build.
func _make_details() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 25)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name)
	_cost_note = _body("")
	_cost_note.add_theme_color_override("font_color", Color("b8321f"))
	top.add_child(_cost_note)
	top.add_child(_icon("cash", 32))
	_cost = Label.new()
	_cost.add_theme_font_size_override("font_size", 25)
	top.add_child(_cost)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var inset := PanelContainer.new()
	inset.theme_type_variation = "Inset"
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.custom_minimum_size.y = 92
	row.add_child(inset)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 8)
	inset.add_child(text)
	_about = _body("")
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_about)
	_makes = HBoxContainer.new()
	_makes.add_theme_constant_override("separation", 6)
	text.add_child(_makes)
	_build = Button.new()
	_build.theme_type_variation = "YellowButton"
	_build.text = "Build"
	_build.icon = UITheme.icon("build")
	_build.expand_icon = true
	_build.custom_minimum_size = Vector2(176, 72)
	_build.add_theme_font_size_override("font_size", 27)
	_build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_build.pressed.connect(func(): _choose(_selected))
	row.add_child(_build)
	return box


## One card: the building's picture with its name underneath. A badge in the corner shows a lock
## (not available) or a coin (can't afford it yet); a gold outline marks the chosen card.
func _add_card(type_id: String) -> void:
	var def: Dictionary = GameData.buildings[type_id]
	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.custom_minimum_size = CARD_SIZE
	card.tooltip_text = def.name
	card.pressed.connect(_on_card_pressed.bind(type_id))
	card.mouse_entered.connect(_show_details.bind(type_id))
	card.mouse_exited.connect(func(): _show_details(_selected))
	_grid.add_child(card)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 8)
	column.offset_bottom = -14  # clear of the card's darker bottom lip
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var art := BuildingView.picture(type_id)
	var picture := _icon("build", 0)
	if not art.is_empty():
		picture.texture = art.texture
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	var title := _body(def.name)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)
	if not def.get("buildable", false):
		picture.material = _grey
		card.self_modulate = Color(0.85, 0.85, 0.85)  # greys the card itself, not what's on it
	var badge := _icon("lock", 32)
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -38
	badge.offset_right = -6
	badge.offset_top = 6
	badge.offset_bottom = 38
	card.add_child(badge)
	var outline := Panel.new()
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = SELECTED
	ring.set_border_width_all(4)
	ring.set_corner_radius_all(14)
	ring.expand_margin_left = 3
	ring.expand_margin_right = 3
	ring.expand_margin_top = 3
	ring.expand_margin_bottom = 1
	outline.add_theme_stylebox_override("panel", ring)
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.hide()
	card.add_child(outline)
	_cards[type_id] = {"badge": badge, "outline": outline}


# --- Behaviour -------------------------------------------------------------------

## Buildable-or-not buildings listed under this tab, in buildings.json order.
func _types_in(tab_id: String) -> Array[String]:
	var types: Array[String] = []
	for type_id in GameData.buildings:
		if GameData.buildings[type_id].get("menu_tab", "") == tab_id:
			types.append(type_id)
	return types


func _show_tab(tab_id: String) -> void:
	_tab = tab_id
	for id in _tab_buttons:
		_tab_buttons[id].theme_type_variation = "SideTabOpen" if id == tab_id else "SideTab"
	for tab in GameData.build_menu.tabs:
		if tab.id == tab_id:
			_title.text = tab.name
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	var types := _types_in(tab_id)
	for type_id in types:
		_add_card(type_id)
	# Keep the chosen building if it's in this tab; otherwise choose the first one that can be built.
	if not types.has(_selected):
		_selected = types[0]
		for type_id in types:
			if GameData.buildings[type_id].get("buildable", false):
				_selected = type_id
				break
	_select(_selected)


func _on_card_pressed(type_id: String) -> void:
	if type_id == _selected and _can_place(type_id):
		_choose(type_id)  # tapping the chosen card again builds it
	else:
		_select(type_id)


func _select(type_id: String) -> void:
	_selected = type_id
	for id in _cards:
		_cards[id].outline.visible = id == type_id
	_show_details(type_id)


func _show_details(type_id: String) -> void:
	if type_id == "":
		return
	_shown = type_id
	var def: Dictionary = GameData.buildings[type_id]
	_name.text = def.name
	_cost.text = UITheme.money(Economy.build_cost(_shown))
	_about.text = def.get("description", "")
	for child in _makes.get_children():
		_makes.remove_child(child)
		child.queue_free()
	var r := BuildingInfo.recipe(type_id)
	match def.category:
		"extractor":
			_makes.add_child(_body("Grows"))
			_add_amounts(r.outputs)
			_makes.add_child(_body("every %s" % UITheme.duration(float(r.duration))))
		"processor":
			_add_amounts(r.inputs)
			_makes.add_child(_icon("arrow", 26))
			_add_amounts(r.outputs)
			_makes.add_child(_icon("clock", 24))
			_makes.add_child(_body(UITheme.duration(float(r.duration))))
		"residential":
			_makes.add_child(_icon("population", 26))
			_makes.add_child(_body("Home for %d people" % int(def.get("population_capacity", 0))))
		"storage":
			_makes.add_child(_icon("warehouse", 26))
			_makes.add_child(_body("Room for %s goods (%d workers)" % [UITheme.number(int(def.get("capacity", 0))), int(def.get("max_workers", 0))]))
		"retail":
			_makes.add_child(_body("Sells"))
			for res in Economy.shop_products():
				_makes.add_child(_icon(res, 26))
			_makes.add_child(_body("on %d shelves (%d workers)" % [int(def.get("shelves", 0)), int(def.get("max_workers", 0))]))
	if def.has("storage_cap"):
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_makes.add_child(spacer)
		_makes.add_child(_icon("warehouse", 24))
		_makes.add_child(_body("Holds %s" % UITheme.number(int(def.storage_cap))))
	_refresh()


## Badges on the cards, and the cost / Build button for the building in the details strip.
func _refresh() -> void:
	if not _window.visible:
		return
	for type_id in _cards:
		var badge: TextureRect = _cards[type_id].badge
		badge.visible = true
		if not GameData.buildings[type_id].get("buildable", false):
			badge.texture = UITheme.icon("lock")
		elif _shortfall(type_id) > 0:
			badge.texture = UITheme.icon("cash")
		else:
			badge.visible = false
	if _shown == "":
		return
	var locked: bool = not GameData.buildings[_shown].get("buildable", false)
	var short := _shortfall(_shown)
	_cost.add_theme_color_override("font_color", UITheme.BAD if short > 0 and not locked else UITheme.TEXT)
	_cost_note.text = "Not available yet" if locked else ("Need %s more" % UITheme.money(short) if short > 0 else "")
	_build.disabled = not _can_place(_shown)


func _can_place(type_id: String) -> bool:
	return GameData.buildings[type_id].get("buildable", false) and _shortfall(type_id) <= 0


## How much more money the player needs to build this (0 = can afford it).
func _shortfall(type_id: String) -> int:
	return maxi(Economy.build_cost(type_id) - Economy.currency(), 0)


func _choose(type_id: String) -> void:
	if not _can_place(type_id):
		return
	show_placing("Placing %s: drag it to a free spot, then tap the green tick" % GameData.buildings[type_id].name)
	placement_requested.emit(type_id)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _apply_layout() -> void:
	if not _window.visible:
		return
	if size.x < size.y:
		# Tall screen (phone held upright): a sheet across the bottom, tabs down its right edge.
		_frame.position = Vector2(0, roundf(size.y * SHEET_TOP))
		_frame.size = Vector2(size.x, size.y - _frame.position.y)
	else:
		# Wide screen (PC / landscape): a window in the middle, nudged left if it would cover the
		# money bar (handy to see while shopping).
		_frame.size = Vector2(minf(MAX_SIZE.x, size.x * 0.94), minf(MAX_SIZE.y, size.y * 0.92))
		_frame.position = ((size - _frame.size) / 2.0).round()
		_frame.position.x = maxf(minf(_frame.position.x, size.x - HUD_WIDTH - _frame.size.x), 16.0)
	_close_button.position = Vector2(_frame.size.x - TAB_SIZE.x - 40, -12)


# --- Small helpers -------------------------------------------------------------

## [icon] 40 for each item, e.g. [wheat] 40 [milk] 4.
func _add_amounts(items: Dictionary) -> void:
	for res in items:
		_makes.add_child(_icon(res, 28))
		_makes.add_child(_body(str(int(items[res]))))


func _icon(icon_name: String, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = UITheme.icon(icon_name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _body(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "BodyLabel"
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
