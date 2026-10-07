extends Control
## Build Menu (plan.md §6): the Build card in the bottom menu bar opens a window of buildings,
## sorted into tabs down the window's right edge (Farming, Industry, …; the tabs are listed in
## data/build_menu.json and each building names its tab with "menu_tab"). Each card shows a
## building's picture and name. Tapping a card shows its details and cost along the bottom;
## Build (or tapping the same card again) starts Placement Mode. On a computer, pointing at a
## card previews its details too. Wide screens get a window in the middle; tall (phone) screens
## a sheet along the bottom.
## The Roads tab holds one "Road" card: it starts Road Mode (plan.md §5.20), where the placing bar
## gets a switch between laying and removing road.
## Costs come from GameData; affordability from Economy. This panel decides nothing itself.

signal placement_requested(type_id: String)
signal placement_cancelled
## Placement Mode: ✓ was tapped (put the building where the ghost is, or build the drawn road).
signal placement_confirmed
## The Road card was chosen: start Road Mode.
signal road_requested
## Road Mode: the switch between laying road (false) and removing it (true) was flipped.
signal road_remove_toggled(removing: bool)

const BuildingView = preload("res://scenes/village/building_view.gd")
const MAX_SIZE := Vector2(900, 640)  # the window on wide screens (smaller if the screen is)
const SHEET_TOP := 0.3  # on tall screens the sheet covers the bottom 70%
const HUD_WIDTH := 250.0  # the money / population / warehouse bars down the top-right corner
const TAB_SIZE := Vector2(72, 66)
const CARD_SIZE := Vector2(128, 144)
const ROAD := "road"  # the Road card's id in the Roads tab (roads aren't buildings)
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
var _title: Label
var _grid: HFlowContainer
var _tab_buttons := {}  # tab id -> its Button
var _cards := {}  # type id -> {"badge": TextureRect, "outline": Panel}
var _tab := ""  # the open tab
var _selected := ""  # the chosen building: Build places this one
var _shown := ""  # the building in the details strip (the selected one, or the one pointed at)
var _grey: ShaderMaterial
var _confirm: RoundButton  # the ✓ in the placing bar
var _road_switch: RoundButton  # Road Mode: lay road (blue) or remove it (red)
var _removing := false
var _placing_text := ""  # the placing bar's hint while the ghost is on a free tile

# The details strip along the bottom.
var _name: Label
var _cost: Label
var _cost_note: Label
var _about: Label
var _makes: HFlowContainer  # wraps onto more lines when it lists many items
var _needs: Label  # what building it needs (materials, crew, time) and when prices change
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
	if not _window.visible:
		Sfx.play("panel_open")
	_window.show()
	_show_tab(_tab if _tab_buttons.has(_tab) else _tab_buttons.keys()[0])
	_apply_layout()
	UITheme.pop_in(_frame, 0.9)


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


## Shows the ✗ / hint / ✓ bar. Moving a building uses it too; Road Mode adds its lay / remove switch.
func show_placing(text: String, roads := false) -> void:
	_window.hide()
	_placing_text = text
	_road_switch.visible = roads
	_set_removing(false)
	placing_bar.show()
	show_hint(text)


## The ghost (or the drawn road) moved: when it can go there ✓ works and the hint says what to do
## (or the check's own "hint"); otherwise ✓ greys out and the hint says why
## (check = {"ok", "error", "hint"}).
func show_ghost_state(check: Dictionary) -> void:
	_confirm.set_disabled(not check.ok)
	show_hint(str(check.get("hint", _placing_text)) if check.ok else check.error)


func _set_removing(on: bool) -> void:
	_removing = on
	_road_switch.set_color("red" if on else "honey")
	_road_switch.set_icon("demolish" if on else "road")
	_road_switch.button.tooltip_text = "Removing road: tap to lay road instead" if on else "Laying road: tap to remove road instead"


## ✗ (cancel) on the left of the placing bar's hint, ✓ (place) on the right.
func _make_placing_buttons() -> void:
	var row: HBoxContainer = $PlacingBar/Row
	var cancel := RoundButton.make("red", "close", "", UITheme.ROUND_ICON_SIZE)
	cancel.pressed.connect(cancel_placement)
	row.add_child(cancel)
	row.move_child(cancel, 0)
	_road_switch = RoundButton.make("honey", "road", "", UITheme.ROUND_ICON_SIZE)
	_road_switch.pressed.connect(func():
		_set_removing(not _removing)
		road_remove_toggled.emit(_removing))
	_road_switch.hide()
	row.add_child(_road_switch)
	row.move_child(_road_switch, 1)
	_confirm = RoundButton.make("green", "check", "", UITheme.ROUND_ICON_SIZE)
	_confirm.pressed.connect(placement_confirmed.emit)
	row.add_child(_confirm)


func _close() -> void:
	if _window.visible:
		Sfx.play("panel_close")
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
	dim.color = UITheme.DIM
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
	# The same title ribbon and close button as every other window.
	var header := UITheme.title_bar()
	column.add_child(header.bar)
	_title = header.label
	header.close.pressed.connect(_close)
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

	# The tabs, added after the page so the open tab is drawn over the page's border. They scroll
	# when there are more than fit down the window's edge.
	var tab_scroll := ScrollContainer.new()
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # drag or wheel to scroll
	tab_scroll.anchor_left = 1.0
	tab_scroll.anchor_right = 1.0
	tab_scroll.anchor_bottom = 1.0
	tab_scroll.offset_left = -TAB_SIZE.x - 1  # over the page's 1px see-through edge, touching its outline
	tab_scroll.offset_top = 96  # below the title ribbon
	tab_scroll.offset_bottom = -12
	_frame.add_child(tab_scroll)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(tabs)
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


## The strip along the bottom: name and cost, then description and what it makes, and Build.
func _make_details() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	_name = UITheme.label("", "BigLabel")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name)
	_cost_note = _body("")
	_cost_note.add_theme_color_override("font_color", UITheme.BAD_TEXT)
	top.add_child(_cost_note)
	top.add_child(_icon("cash", 32))
	_cost = UITheme.label("", "BigLabel")
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
	_makes = HFlowContainer.new()
	_makes.add_theme_constant_override("h_separation", 6)
	_makes.add_theme_constant_override("v_separation", 2)
	text.add_child(_makes)
	_needs = _body("")
	_needs.theme_type_variation = "SmallLabel"
	_needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_needs)
	_build = UITheme.button("Build", "GoButton", "big", "build")
	_build.custom_minimum_size.x = 180
	_build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_build.pressed.connect(func(): _choose(_selected))
	row.add_child(_build)
	return box


## One card: the building's picture with its name underneath. A badge in the corner shows a lock
## (not available) or a coin (can't afford it yet); a gold outline marks the chosen card.
func _add_card(type_id: String) -> void:
	var def := _def(type_id)
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
	var art := BuildingView.picture(type_id) if type_id != ROAD else {}
	var picture := _icon("build" if type_id != ROAD else "road", 0)
	if not art.is_empty():
		picture.texture = art.texture
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	var title := _body(def.name)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.theme_type_variation = "SmallLabel"
	title.add_theme_color_override("font_color", UITheme.TEXT_DARK)
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
	outline.theme_type_variation = "CardRing"
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.hide()
	card.add_child(outline)
	_cards[type_id] = {"badge": badge, "outline": outline}


# --- Behaviour -------------------------------------------------------------------

## Buildable-or-not buildings listed under this tab, in buildings.json order. The Roads tab lists
## the Road card (when the game has roads).
func _types_in(tab_id: String) -> Array[String]:
	var types: Array[String] = []
	if tab_id == "roads" and GameData.config.has("roads"):
		types.append(ROAD)
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
			if _def(type_id).get("buildable", false):
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
	var def := _def(type_id)
	_name.text = def.name
	_about.text = def.get("description", "")
	for child in _makes.get_children():
		_makes.remove_child(child)
		child.queue_free()
	var r := BuildingInfo.recipe(type_id) if type_id != ROAD else {}
	var recipes: Array = def.get("recipes", [])
	if recipes.size() > 1:
		# Several products (plan.md §5.21): each building makes one; a Plantation can switch.
		_makes.add_child(_body("Grows one of" if def.category == "extractor" else "Makes one of"))
		for each in recipes:
			_makes.add_child(_icon(BuildingInfo.output_of(each), 26))
		_makes.add_child(_body("(switch for a fee)" if Economy.is_switchable(type_id) else "(picked once)"))
		if Economy.power_on() and float(def.get("power_mw", 0.0)) > 0.0:
			_makes.add_child(_icon("power", 24))
			_makes.add_child(_body(BuildingInfo.mw(float(def.power_mw))))
	match "" if recipes.size() > 1 else def.category:
		"extractor":
			_makes.add_child(_body("Grows"))
			_add_amounts(r.outputs)
			_makes.add_child(_body("an hour"))
		"processor":
			_add_amounts(r.inputs)
			_makes.add_child(_icon("arrow", 26))
			_add_amounts(r.outputs)
			_makes.add_child(_body("an hour"))
			if Economy.power_on() and float(def.get("power_mw", 0.0)) > 0.0:
				_makes.add_child(_icon("power", 24))
				_makes.add_child(_body("needs %s" % BuildingInfo.mw(float(def.power_mw))))
		"residential":
			# "6 households · for Broke, Poor · free · 0.3 MW when lived in" (plan.md §5.18)
			_makes.add_child(_icon("population", 26))
			var names := {}
			for wealth in Economy.wealth_classes():
				names[str(wealth.id)] = str(wealth.name)
			var who: Array[String] = []
			for id in def.get("wealth", []):
				who.append(str(names.get(id, id)))
			var rent := Economy.rent_per_household(type_id)
			var parts: Array[String] = ["%d households" % int(def.get("households", 0))]
			parts.append("for " + (", ".join(who) if not who.is_empty() else "anyone"))
			parts.append("free" if rent <= 0.0 else "rent %s/h each" % UITheme.price(roundi(rent * 100.0)))
			if float(def.get("power_mw", 0.0)) > 0.0:
				parts.append("%s MW when lived in" % str(def.power_mw))
			_makes.add_child(_body(" · ".join(parts)))
		"storage":
			_makes.add_child(_icon("warehouse", 26))
			_makes.add_child(_body("Room for %s goods (%d workers)" % [UITheme.number(int(def.get("capacity", 0))), int(def.get("max_workers", 0))]))
		"construction":
			_makes.add_child(_icon("build", 26))
			_makes.add_child(_body("%d construction workers: building anything needs 1, an upgrade 1 per level. They're busy until the work is done" % int(def.get("max_workers", 0))))
		"utility":
			_makes.add_child(_icon("water", 26))
			_makes.add_child(_body("Cleans %s m³ of water an hour for your buildings (%d workers)" % [UITheme.number(int(def.get("water_supply", 0))), int(def.get("max_workers", 0))]))
		"power":
			# "5 MW · no workers · reaches 3 tiles" (plan.md §5.5)
			_makes.add_child(_icon("power", 26))
			var parts: Array[String] = []
			if float(def.get("power_supply", 0.0)) > 0.0:
				parts.append("Makes %s" % BuildingInfo.mw(float(def.power_supply)))
				var workers := int(def.get("max_workers", 0))
				parts.append("no workers" if workers <= 0 else "%d %s workers" % [workers, str(GameData.config.get("worker_types", {}).get(def.get("worker_type", ""), {}).get("name", ""))])
			else:
				parts.append("Makes no power: carries it")
			parts.append("reaches %s tiles" % str(def.get("power_radius", 0)))
			_makes.add_child(_body(" · ".join(parts)))
		"road":
			_makes.add_child(_icon("road", 26))
			_makes.add_child(_body("%s a tile · ready at once · removing is free" % UITheme.money(Economy.road_price())))
		"trade":
			# "Buys anything at 60%, sells anything at 150% of its price" (plan.md §5.22)
			var shares: Dictionary = GameData.config.get("trade", {})
			_makes.add_child(_icon("market", 26))
			_makes.add_child(_body("Buys anything at %d%%, sells anything at %d%% of its price · no workers" % [roundi(float(shares.get("sell_share", 1.0)) * 100.0), roundi(float(shares.get("buy_share", 1.0)) * 100.0)]))
		"retail":
			# "Sells Food on 4 shelves" (its "sells" categories), or the goods' icons if it has no list.
			var kinds: Array[String] = []
			for kind in def.get("sells", []):
				kinds.append(Economy.category_name(str(kind)))
			_makes.add_child(_body("Sells " + ", ".join(kinds) if not kinds.is_empty() else "Sells"))
			if kinds.is_empty():
				for res in Economy.store_products(type_id):
					_makes.add_child(_icon(res, 26))
			_makes.add_child(_body("on %d shelves (%d workers)" % [int(def.get("shelves", 0)), int(def.get("max_workers", 0))]))
	if def.get("category", "") in ["extractor", "processor"]:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_makes.add_child(spacer)
		_makes.add_child(_icon("clock", 24))
		_makes.add_child(_body("Batches of 1-%d h" % Economy.batch_hours_limit()))
	_refresh()


## Badges on the cards, and the cost / Build button for the building in the details strip.
func _refresh() -> void:
	if not _window.visible:
		return
	for type_id in _cards:
		var badge: TextureRect = _cards[type_id].badge
		badge.visible = true
		if not _def(type_id).get("buildable", false):
			badge.texture = UITheme.icon("lock")
		elif _shortfall(type_id) > 0:
			badge.texture = UITheme.icon("cash")
		else:
			badge.visible = false
	if _shown == "":
		return
	var locked: bool = not _def(_shown).get("buildable", false)
	if _shown == ROAD:
		_cost.text = UITheme.money(Economy.road_price())
		_needs.visible = false
	else:
		# The warehouse's own materials are used first; the rest is bought at today's market price,
		# so the cost is "about" and moves every hour.
		var quote := Economy.build_quote(_shown)
		_cost.text = "≈ " + UITheme.money(int(quote.cost))
		_needs.visible = not locked and not quote.lines.is_empty()
		_needs.text = "Needs %s. Material prices change in %s." % [BuildingInfo.construction_needs(quote), UITheme.duration(Economy.price_change_in())]
	var short := _shortfall(_shown)
	UITheme.set_font_color(_cost, UITheme.BAD_TEXT if short > 0 and not locked else UITheme.TEXT_DARK)
	_cost_note.text = str(_def(_shown).get("coming_soon", "Not available yet")) if locked else ("Need %s more" % UITheme.money(short) if short > 0 else "")
	if not locked and _shown != ROAD and Economy.at_build_limit(_shown):
		_cost_note.text = "Already built: one is all you need"  # max_count (the Trading Post: 1)
	_build.disabled = not _can_place(_shown)


func _can_place(type_id: String) -> bool:
	if type_id != ROAD and Economy.at_build_limit(type_id):
		return false
	return _def(type_id).get("buildable", false) and _shortfall(type_id) <= 0


## How much more money the player needs to build this (0 = can afford it; for road: one tile).
func _shortfall(type_id: String) -> int:
	var cost := Economy.road_price() if type_id == ROAD else Economy.build_cost(type_id)
	return maxi(cost - Economy.currency(), 0)


## A building's entry in buildings.json, or the Road card's made-up one.
func _def(type_id: String) -> Dictionary:
	if type_id == ROAD:
		return {"name": "Road", "category": "road", "buildable": true,
			"description": "Workers need a way in: a building with workers only works with a road beside it that leads to City Hall. Drag across the map to lay road; corners and crossroads appear by themselves."}
	return GameData.buildings[type_id]


func _choose(type_id: String) -> void:
	if not _can_place(type_id):
		return
	if type_id == ROAD:
		show_placing("Drag from a road to lay road, then tap the green tick", true)
		road_requested.emit()
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


# --- Small helpers -------------------------------------------------------------

## [icon] 40 for each item, e.g. [wheat] 40 [milk] 4.
func _add_amounts(items: Dictionary) -> void:
	for res in items:
		_makes.add_child(_icon(res, 28))
		_makes.add_child(_body(str(int(items[res]))))


func _icon(icon_name: String, side: float) -> TextureRect:
	return UITheme.icon_rect(icon_name, side)


func _body(text: String) -> Label:
	var label := UITheme.label(text)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
