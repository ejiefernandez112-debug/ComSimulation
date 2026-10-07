extends Control
## Build panel (plan.md §6, the Harbor Glass mockup): picking a category in the bottom build
## toolbar (menu_bar.gd; categories from data/build_menu.json, each building names its own with
## "menu_tab") opens this frosted glass panel just above the toolbar. Its header has the category's
## coloured square, name and a line about it. On the left: one card per building (picture, name,
## and a line about its cost: materials ready, how much must be bought, or locked). On the right:
## the chosen building's details, the materials it needs (from the warehouse first, the rest bought
## at today's prices) and a big Build button. On a computer, pointing at a card previews it.
## Wide screens get a wide panel above the toolbar; tall (phone) screens a sheet, cards on top.
## The panel keeps one size whatever building is shown (longer details scroll inside it), so
## pointing from card to card never makes it jump.
##
## Placing: tapping a card only chooses it. Build closes the panel and puts the building's
## see-through "ghost" on the map, with the bar along the bottom (✕, hint, ✓): ✓ builds it where
## the ghost stands, ✕ goes back to the panel. Road Mode (the Road card, plan.md §5.20) and moving
## a building use the same bar (Road Mode adds its lay / remove switch).
## Costs come from GameData; affordability from Economy. This panel decides nothing itself.

signal placement_requested(type_id: String)
signal placement_cancelled
## Placement Mode: ✓ was tapped (put the building where the ghost is, or build the road).
signal placement_confirmed
## The Road card was chosen: start Road Mode.
signal road_requested
## Road Mode: the switch between laying road (false) and removing it (true) was flipped.
signal road_remove_toggled(removing: bool)
## The panel opened a category, or closed (""): the toolbar shows that button blue.
signal tab_changed(tab_id: String)

const BuildingView = preload("res://scenes/village/building_view.gd")
const Toolbars = preload("res://scenes/ui/menu_bar.gd")
const HUD_SPACE := 84.0  # the HUD strip across the top: the panel stays below it
const SHEET_TOP := 0.4  # on tall screens the sheet starts 40% down
## Pointing away from a card waits this long before the details go back to the chosen card, so
## moving straight onto the next card changes them only once.
const HOVER_BACK_SECONDS := 0.15
const ROAD := BuildingInfo.ROAD
## Locked buildings' pictures are drawn in grey.
const GREY_SHADER := "shader_type canvas_item;
void fragment() {
	float g = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	COLOR = vec4(vec3(g * 0.85 + 0.12), COLOR.a);
}"

@onready var placing_bar: PanelContainer = $PlacingBar
@onready var hint: Label = $PlacingBar/Row/Hint

var _window: Control  # everything a category opens
var _frame: PanelContainer  # the panel; _apply_layout places it
var _square_holder: Control  # holds the category's coloured square (rebuilt per category)
var _title: Label
var _about_tab: Label
var _body: BoxContainer  # cards | details (side by side on wide screens, stacked on tall ones)
var _split: ColorRect  # the line between cards and details
var _grid: HFlowContainer
var _cards := {}  # type id -> {"outline": Panel, "badge": Control, "status": Label, "status_icon": TextureRect}
var _tab := ""  # the open category
var _selected := ""  # the chosen building: Build places this one
var _shown := ""  # the building in the details (the selected one, or the one pointed at)
var _placing := ""  # the building whose ghost is on the map after Build ("" = none)
var _grey: ShaderMaterial
var _confirm: RoundButton  # the ✓ in the bottom bar
var _road_switch: RoundButton  # Road Mode: lay road (glass) or remove it (red)
var _removing := false
var _placing_text := ""  # the bottom bar's hint while the ghost is on a free tile
var _hover_back: Timer  # see HOVER_BACK_SECONDS

# The details, on the right.
var _name: Label
var _tag: Dictionary  # UITheme.tag(): {"tag", "dot", "label"}
var _about: Label
var _makes: HFlowContainer  # what it makes or does (wraps onto more lines when it lists many items)
var _details: VBoxContainer  # the right side; as wide as the category's widest building (_fit_all)
var _materials: VBoxContainer  # one row per material (and the crew)
## The material rows, made once and reused (the extra ones hidden): {"row", "icon", "name",
## "amount", "status"}. Only the first _material_count are in use.
var _material_rows: Array[Dictionary] = []
var _material_count := 0
var _fit := 0.0  # the height the panel needs for its biggest building (see _fit_all; 0 = not yet)
var _note: Label  # why it can't be built: locked, already built, not enough cash
var _build: Button


func _ready() -> void:
	_make_placing_buttons()
	_hover_back = Timer.new()
	_hover_back.one_shot = true
	_hover_back.wait_time = HOVER_BACK_SECONDS
	_hover_back.timeout.connect(func(): _show_details(_selected))
	add_child(_hover_back)
	UITheme.frost(placing_bar)
	_grey = ShaderMaterial.new()
	_grey.shader = Shader.new()
	_grey.shader.code = GREY_SHADER
	_make_window()
	resized.connect(_apply_layout)
	Economy.changed.connect(_refresh)


## Opens the panel on this category (or the last one / the first one when "").
func open(tab_id := "") -> void:
	var tabs := BuildingInfo.menu_tabs()
	if tabs.is_empty():
		return
	if tab_id == "":
		tab_id = _tab if _tab != "" else str(tabs[0].id)
	var was_open := _window.visible
	_window.show()
	_about.custom_minimum_size.y = _about.get_line_height() * 2  # short and long texts take the same room
	_show_tab(tab_id)
	if _fit <= 0.0:
		_fit_all()  # the first time (and after the look changed): one size for every category
	_apply_layout()
	_apply_layout.call_deferred()  # again once new text has been measured
	if not was_open:
		UITheme.pop_in(_frame, 0.99)


## The toolbar button of the open category closes the panel; any other one opens its category.
func toggle(tab_id: String) -> void:
	if _window.visible and tab_id == _tab:
		close()
	else:
		open(tab_id)


func close() -> void:
	if _placing != "":
		end_placement()
		placement_cancelled.emit()
	if _window.visible:
		_window.hide()
		tab_changed.emit("")


func is_open() -> bool:
	return _window.visible


## The middle of the part of the map the panel leaves in view: a new ghost starts there.
func free_map_centre() -> Vector2:
	var bottom := _frame.position.y if _window.visible else size.y
	return Vector2(size.x / 2.0, (HUD_SPACE + bottom) / 2.0).round()


## Called when the building was placed, moved, or the road mode ended. The panel stays closed.
func end_placement() -> void:
	placing_bar.hide()
	_placing = ""


## ✕ (or Esc / right-click): stop placing. A building chosen in the panel goes back to the panel,
## on the same category with the same card chosen, so the player can pick again.
func cancel_placement() -> void:
	var back := _placing != ""
	end_placement()
	placement_cancelled.emit()
	if back:
		open(_tab)


func is_placing() -> bool:
	return placing_bar.visible or _placing != ""


func show_hint(text: String) -> void:
	hint.text = text


## Shows the bottom bar (✕ / hint / ✓) for placing a building, Road Mode and moving a building;
## the panel closes.
func show_placing(text: String, roads := false) -> void:
	if _window.visible:
		_window.hide()
		tab_changed.emit("")
	_placing_text = text
	_road_switch.visible = roads
	_set_removing(false)
	placing_bar.show()
	hint.text = text


## The ghost (or the drawn road) moved: when it can go there ✓ works and the hint says what to do
## (or the check's own "hint"); otherwise ✓ greys out and the hint says why
## (check = {"ok", "error", "hint"}).
func show_ghost_state(check: Dictionary) -> void:
	_confirm.set_disabled(not check.ok)
	hint.text = str(check.get("hint", _placing_text)) if check.ok else str(check.error)


func _set_removing(on: bool) -> void:
	_removing = on
	_road_switch.set_style("DangerButton" if on else "Button")
	_road_switch.set_icon("demolish" if on else "road")
	_road_switch.button.tooltip_text = "Removing road: tap to lay road instead" if on else "Laying road: tap to remove road instead"


## ✕ (cancel) on the left of the bottom bar's hint, ✓ (place) on the right.
func _make_placing_buttons() -> void:
	var row: HBoxContainer = $PlacingBar/Row
	var cancel := RoundButton.make("BackButton", "close", "", UITheme.ROUND_ICON_SIZE)
	cancel.pressed.connect(cancel_placement)
	row.add_child(cancel)
	row.move_child(cancel, 0)
	_road_switch = RoundButton.make("Button", "road", "", UITheme.ROUND_ICON_SIZE)
	_road_switch.pressed.connect(func():
		_set_removing(not _removing)
		road_remove_toggled.emit(_removing))
	_road_switch.hide()
	row.add_child(_road_switch)
	row.move_child(_road_switch, 1)
	_confirm = RoundButton.make("GoButton", "check", "", UITheme.ROUND_ICON_SIZE)
	_confirm.pressed.connect(placement_confirmed.emit)
	row.add_child(_confirm)


## A new look (Developer window → Look) can change text and button sizes: measure again next time.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_fit = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not _window.visible or not event.is_action_pressed("ui_cancel"):
		return
	close()  # Esc closes the panel (while placing it's hidden; main.gd's Esc cancels placing)
	get_viewport().set_input_as_handled()


# --- Building the panel ------------------------------------------------------------

func _make_window() -> void:
	_window = Control.new()
	_window.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE  # the map stays live around the panel
	_window.add_to_group(ModalWindow.GROUP)  # ...but the mouse wheel doesn't zoom it while it's open
	_window.hide()
	add_child(_window)
	_frame = PanelContainer.new()
	UITheme.frost(_frame)
	_window.add_child(_frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_frame.add_child(column)
	column.add_child(_make_header())
	_body = BoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	column.add_child(_body)

	# Left: the cards, and a note about where materials come from.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	_body.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	var note := HBoxContainer.new()
	note.add_theme_constant_override("separation", 8)
	left.add_child(note)
	var box_icon := UITheme.icon_rect("warehouse", 16)
	box_icon.modulate = UITheme.TEXT_FAINT
	note.add_child(box_icon)
	var words := UITheme.label("Materials come from your warehouse first; anything missing is bought at market price.", "SmallLabel")
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # one line; cut short on narrow screens
	note.add_child(words)

	_split = UITheme.divider(true)
	_body.add_child(_split)
	_body.add_child(_make_details())


## The header: the category's coloured square, its name, a line about it, and ✕.
func _make_header() -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = "TitleBar"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_square_holder = CenterContainer.new()
	row.add_child(_square_holder)
	_title = UITheme.label("", "TitleLabel")
	row.add_child(_title)
	_about_tab = UITheme.label("", "SmallLabel")
	_about_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_about_tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_about_tab.clip_text = true
	row.add_child(_about_tab)
	var close_button := RoundButton.make("IconButton", "close", "", 40)
	close_button.button.tooltip_text = "Close"
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return bar


## The right side: name and price tag, what it is, what it makes, the materials it needs, and Build.
func _make_details() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = UITheme.BUILD_DETAILS_WIDTH
	_details = box
	box.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	_name = UITheme.label("", "HeadingLabel")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	top.add_child(_name)
	_tag = UITheme.tag()
	top.add_child(_tag.tag)
	# The middle: no scroll bar. The panel is made tall enough for the biggest building of the
	# category when it opens (_fit_all), so it never changes size while pointing at cards.
	var middle := VBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 8)
	box.add_child(middle)
	_about = UITheme.wrapped("", UITheme.BUILD_DETAILS_WIDTH, "SmallLabel")
	middle.add_child(_about)
	_makes = HFlowContainer.new()
	_makes.add_theme_constant_override("h_separation", 6)
	_makes.add_theme_constant_override("v_separation", 2)
	middle.add_child(_makes)
	_materials = VBoxContainer.new()
	_materials.add_theme_constant_override("separation", 0)
	middle.add_child(_materials)
	_note = UITheme.wrapped("", UITheme.BUILD_DETAILS_WIDTH, "SmallLabel")
	middle.add_child(_note)
	_build = UITheme.button("Build", "GoButton", "normal", "build")
	_build.size_flags_horizontal = Control.SIZE_FILL
	_build.pressed.connect(_on_build_pressed)
	box.add_child(_build)
	return box


## One card: the building's picture, its name, and a line about its cost. A lock in the corner
## marks one that can't be built yet; a blue edge marks the chosen card.
func _add_card(type_id: String) -> void:
	var def := _def(type_id)
	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.custom_minimum_size = UITheme.BUILD_CARD_SIZE
	card.pressed.connect(_select.bind(type_id))
	# Pointing at a card previews it; pointing away goes back to the chosen card a moment later
	# (moving straight onto the next card cancels that, so the details change once).
	card.mouse_entered.connect(func():
		_hover_back.stop()
		_show_details(type_id))
	card.mouse_exited.connect(_hover_back.start)
	_grid.add_child(card)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 8)
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var art := BuildingView.picture(type_id) if type_id != ROAD else {}
	var picture := UITheme.icon_rect("build" if type_id != ROAD else "road", 0)
	if not art.is_empty():
		picture.texture = art.texture
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	var title := UITheme.label(def.name)
	title.add_theme_font_override("font", UITheme.bold_font())
	title.add_theme_font_size_override("font_size", 15)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 5)
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status_row)
	var status_icon := UITheme.icon_rect("check", 14)
	status_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(status_icon)
	var status := UITheme.label("", "SmallLabel")
	status.add_theme_font_size_override("font_size", 13)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true  # never wider than the card: cut short with "…"
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_row.add_child(status)
	if not def.get("buildable", false):
		picture.material = _grey
	# The lock badge: a small dark square in the top-right corner.
	var badge := PanelContainer.new()
	badge.theme_type_variation = "Tag"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(UITheme.icon_rect("lock", 14))
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -36
	badge.offset_right = -8
	badge.offset_top = 8
	badge.offset_bottom = 32
	badge.visible = not def.get("buildable", false)
	card.add_child(badge)
	var outline := Panel.new()
	outline.theme_type_variation = "CardRing"
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.hide()
	card.add_child(outline)
	_cards[type_id] = {"outline": outline, "status": status, "status_icon": status_icon}


# --- Behaviour -------------------------------------------------------------------

func _show_tab(tab_id: String) -> void:
	if tab_id == _tab and not _cards.is_empty():
		tab_changed.emit(tab_id)
		return
	_tab = tab_id
	var tab := {}
	for each: Dictionary in BuildingInfo.menu_tabs():
		if each.id == tab_id:
			tab = each
	_title.text = str(tab.get("name", ""))
	_about_tab.text = str(tab.get("about", ""))
	for child in _square_holder.get_children():
		child.queue_free()
	_square_holder.add_child(UITheme.category_square(str(tab.get("icon", "build")), Color(str(tab.get("color", "#7f86a0")))))
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	var types := BuildingInfo.menu_types(tab_id)
	for type_id in types:
		_add_card(type_id)
	# Keep the chosen building if it's in this category; otherwise choose the first one that can be built.
	if not types.has(_selected):
		_selected = types[0] if not types.is_empty() else ""
		for type_id in types:
			if _def(type_id).get("buildable", false):
				_selected = type_id
				break
	_select(_selected)
	tab_changed.emit(tab_id)


## Build: the panel closes and the building's ghost goes on the map, with the bottom bar (✕ / ✓).
func _on_build_pressed() -> void:
	_start(_selected)


func _start(type_id: String) -> void:
	if not _can_place(type_id):
		return
	if type_id == ROAD:
		show_placing("Drag from a road to lay road, then tap the blue tick", true)
		road_requested.emit()
		return
	show_placing("%s ⋅ %s: drag it to a free spot, then tap the blue tick" % [_def(type_id).name, UITheme.money(Economy.build_cost(type_id))])
	_placing = type_id
	placement_requested.emit(type_id)  # the village's first check of the ghost comes back here


## Shows every building of every category in the details in turn and keeps the most height the
## panel needs (with room for a one-line note) and the widest the details get. So the panel and the
## Build button keep one size, whichever card is pointed at and whichever category is open, and
## nothing needs a scroll bar. Done once, the first time the panel opens (again after the look
## changes, see _notification).
func _fit_all() -> void:
	var types: Array[String] = []
	for tab: Dictionary in BuildingInfo.menu_tabs():
		types.append_array(BuildingInfo.menu_types(str(tab.id)))
	_fit = 0.0
	_details.custom_minimum_size.x = UITheme.BUILD_DETAILS_WIDTH
	var widest := 0.0
	for type_id in types:
		_shown = ""
		_show_details(type_id)
		var note_room := 0.0 if _note.visible else _note.get_line_height() + 8.0
		_fit = maxf(_fit, _frame.get_combined_minimum_size().y + note_room)
		widest = maxf(widest, _details.get_combined_minimum_size().x)
	_details.custom_minimum_size.x = widest
	_shown = ""
	_show_details(_selected)  # back to the chosen building


## Tapping a card chooses it (Build then places it).
func _select(type_id: String) -> void:
	_hover_back.stop()
	_selected = type_id
	for id in _cards:
		_cards[id].outline.visible = id == type_id
	_show_details(type_id)


func _show_details(type_id: String) -> void:
	if type_id == "" or type_id == _shown:
		return
	_shown = type_id
	var def := _def(type_id)
	_name.text = def.name
	_about.text = def.get("description", "")
	_fill_makes(type_id)
	# One row per material (and the crew), reusing the rows already made; _refresh keeps their
	# numbers up to date.
	var lines: Array = Economy.build_quote(type_id).lines if type_id != ROAD and def.get("buildable", false) else []
	while _material_rows.size() < lines.size():
		_add_material_row()
	for i in _material_rows.size():
		var row: Dictionary = _material_rows[i]
		row.row.visible = i < lines.size()
		if i < lines.size():
			_fill_material_row(row, lines[i])
	_material_count = lines.size()
	_refresh()


## Puts a material (or the crew) in a row: its icon and name.
func _fill_material_row(row: Dictionary, line: Dictionary) -> void:
	var labor: bool = line.id == "labor"
	var icon: TextureRect = row.icon
	icon.texture = UITheme.icon("population" if labor else str(line.id))
	icon.modulate = UITheme.TEXT_DIM if labor else Color.WHITE
	var name_label: Label = row.name
	name_label.text = "Construction crew" if labor else str(line.name)


## An empty materials row: [icon] Bricks ......... 400   in stock (filled by _fill_material_row).
func _add_material_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 25
	_materials.add_child(row)
	var icon := UITheme.icon_rect("population", 20)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var name_label := UITheme.label("")
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	var amount := UITheme.label("")
	amount.add_theme_font_override("font", UITheme.bold_font())
	amount.add_theme_font_size_override("font_size", 15)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	var status := UITheme.label("", "SmallLabel")
	status.add_theme_font_override("font", UITheme.bold_font())
	status.add_theme_font_size_override("font_size", 13)
	status.custom_minimum_size.x = 88
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(status)
	_material_rows.append({"row": row, "icon": icon, "name": name_label, "amount": amount, "status": status})


## What the building makes or does, in one line of icons and words.
func _fill_makes(type_id: String) -> void:
	for child in _makes.get_children():
		_makes.remove_child(child)
		child.queue_free()
	var def := _def(type_id)
	var r := BuildingInfo.recipe(type_id) if type_id != ROAD else {}
	var recipes: Array = def.get("recipes", [])
	if recipes.size() > 1:
		# Several products (plan.md §5.21): each building makes one; a Plantation can switch.
		_makes.add_child(_words("Grows one of" if def.category == "extractor" else "Makes one of"))
		for each in recipes:
			_makes.add_child(UITheme.icon_rect(BuildingInfo.output_of(each), 22))
		if Economy.power_on() and float(def.get("power_mw", 0.0)) > 0.0:
			_makes.add_child(UITheme.icon_rect("power", 20))
			_makes.add_child(_words(BuildingInfo.mw(float(def.power_mw))))
	match "" if recipes.size() > 1 else def.category:
		"extractor":
			_makes.add_child(_words("Grows"))
			_add_amounts(r.outputs)
			_makes.add_child(_words("an hour"))
		"processor":
			_add_amounts(r.inputs)
			_makes.add_child(UITheme.icon_rect("arrow", 22))
			_add_amounts(r.outputs)
			_makes.add_child(_words("an hour"))
			if Economy.power_on() and float(def.get("power_mw", 0.0)) > 0.0:
				_makes.add_child(UITheme.icon_rect("power", 20))
				_makes.add_child(_words("needs %s" % BuildingInfo.mw(float(def.power_mw))))
		"residential":
			# "6 households ⋅ for Broke, Poor ⋅ free ⋅ 0.3 MW when lived in" (plan.md §5.18)
			_makes.add_child(UITheme.icon_rect("population", 22))
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
			_add_parts(parts)
		"storage":
			_makes.add_child(UITheme.icon_rect("warehouse", 22))
			_makes.add_child(_words("Room for %s goods (%d workers)" % [UITheme.number(int(def.get("capacity", 0))), int(def.get("max_workers", 0))]))
		"construction":
			_makes.add_child(UITheme.icon_rect("build", 22))
			_makes.add_child(_words("%d construction workers" % int(def.get("max_workers", 0))))
		"service":
			# "Health for 100 people (4 workers)" (plan.md §5.23)
			var need := str(def.get("service_need", ""))
			_makes.add_child(UITheme.icon_rect(need, 22))
			_makes.add_child(_words("%s for %s people (%d workers)" % [Economy.need_name(need), UITheme.number(int(def.get("service_capacity", 0))), int(def.get("max_workers", 0))]))
		"utility":
			_makes.add_child(UITheme.icon_rect("water", 22))
			_makes.add_child(_words("Cleans %s m³ of water an hour (%d workers)" % [UITheme.number(int(def.get("water_supply", 0))), int(def.get("max_workers", 0))]))
		"power":
			# "Makes 5 MW ⋅ reaches 3 tiles" (plan.md §5.5)
			_makes.add_child(UITheme.icon_rect("power", 22))
			var parts: Array[String] = []
			if float(def.get("power_supply", 0.0)) > 0.0:
				parts.append("Makes %s" % BuildingInfo.mw(float(def.power_supply)))
				var workers := int(def.get("max_workers", 0))
				if workers > 0:
					parts.append("%d workers" % workers)
			else:
				parts.append("Makes no power: carries it")
			parts.append("reaches %s tiles" % _num(def.get("power_radius", 0)))
			_add_parts(parts)
		"road":
			_makes.add_child(UITheme.icon_rect("road", 22))
			_makes.add_child(_words("%s a tile" % UITheme.money(Economy.road_price())))
		"trade":
			_makes.add_child(UITheme.icon_rect("market", 22))
			_makes.add_child(_words("Buys and sells anything"))
		"retail":
			# "Sells Food on 4 shelves" (its "sells" categories), or the goods' icons if it has no list.
			var kinds: Array[String] = []
			for kind in def.get("sells", []):
				kinds.append(Economy.category_name(str(kind)))
			_makes.add_child(_words("Sells " + ", ".join(kinds) if not kinds.is_empty() else "Sells"))
			if kinds.is_empty():
				for res in Economy.store_products(type_id):
					_makes.add_child(UITheme.icon_rect(res, 22))
			_makes.add_child(_words("on %d shelves (%d workers)" % [int(def.get("shelves", 0)), int(def.get("max_workers", 0))]))


## The note above Build: why this building can't be built.
func _show_note() -> void:
	if _shown == "":
		return
	var def := _def(_shown)
	var locked: bool = not def.get("buildable", false)
	var note := ""
	var color := UITheme.BAD
	if locked:
		note = str(def.get("coming_soon", "Not available yet"))
		color = UITheme.TEXT_DIM
	elif _shown != ROAD and Economy.at_build_limit(_shown):
		note = "Already built: one is all you need"  # max_count (the Trading Post: 1)
	elif _shortfall(_shown) > 0:
		note = "You need %s more cash" % UITheme.money(_shortfall(_shown))
	_note.text = note
	_note.visible = note != ""
	UITheme.set_font_color(_note, color)


## Card lines, and the details' price tag, materials, note and Build button.
func _refresh() -> void:
	if not _window.visible:
		return
	for type_id in _cards:
		_show_card_status(type_id)
	if _shown == "":
		return
	var def := _def(_shown)
	var locked: bool = not def.get("buildable", false)
	var cost := Economy.road_price() if _shown == ROAD else 0
	if _shown != ROAD:
		var quote := Economy.build_quote(_shown)
		cost = int(quote.cost)
		_show_materials(quote)
	if locked:
		_set_tag("Locked", UITheme.TEXT_FAINT)
	elif _shown == ROAD:
		_set_tag("%s a tile" % UITheme.money(cost), UITheme.WARN)
	else:
		var buying := _buying(_shown)
		# The materials the warehouse doesn't have, bought at today's prices (Build's price adds the crew).
		_set_tag("Materials %s" % UITheme.money(buying) if buying > 0 else "Materials ready", UITheme.WARN if buying > 0 else UITheme.GOOD)
	_show_note()
	if _shown == ROAD:
		_build.text = "Build road"
	else:
		_build.text = "Build ⋅ %s" % UITheme.money(cost) if cost > 0 else "Build"
	_build.disabled = not _can_place(_shown)


## The materials rows' numbers: how many, and whether the warehouse has them or some are bought.
func _show_materials(quote: Dictionary) -> void:
	var lines: Array = quote.get("lines", [])
	if lines.size() != _material_count:
		return  # not shown for this building (locked)
	for i in lines.size():
		var line: Dictionary = lines[i]
		var row := _material_rows[i]
		var status: Label = row.status
		if line.id == "labor":
			row.amount.text = UITheme.number(int(line.amount))
			status.text = UITheme.duration(float(quote.get("seconds", 0)))
			UITheme.set_font_color(status, UITheme.TEXT_DIM)
			continue
		row.amount.text = UITheme.number(int(line.amount))
		var buy := int(line.get("buy", 0))
		status.text = "buy %s" % UITheme.number(buy) if buy > 0 else "in stock"
		UITheme.set_font_color(status, UITheme.WARN if buy > 0 else UITheme.GOOD)


## A card's line: locked, already built, cash missing, materials to buy, or ready.
func _show_card_status(type_id: String) -> void:
	var card: Dictionary = _cards[type_id]
	var def := _def(type_id)
	var text := ""
	var color := UITheme.TEXT_DIM
	var icon_name := ""
	if not def.get("buildable", false):
		text = "Coming soon"
	elif type_id == ROAD:
		text = "%s a tile" % UITheme.money(Economy.road_price())
	elif Economy.at_build_limit(type_id):
		text = "Already built"
	elif _shortfall(type_id) > 0:
		text = "Need %s more" % UITheme.money(_shortfall(type_id))
		color = UITheme.BAD
		icon_name = "cash"
	else:
		var buying := _buying(type_id)
		if buying > 0:
			text = "Buy %s" % UITheme.money(buying)
			color = UITheme.WARN
			icon_name = "cash"
		else:
			text = "Materials ready"
			color = UITheme.GOOD
			icon_name = "check"
	var status: Label = card.status
	status.text = text
	UITheme.set_font_color(status, color)
	var icon: TextureRect = card.status_icon
	icon.visible = icon_name != ""
	if icon_name != "":
		icon.texture = UITheme.icon(icon_name)
		icon.modulate = color


## What the materials that aren't in the warehouse cost to buy today (cents; the crew not counted).
func _buying(type_id: String) -> int:
	var total := 0
	for line: Dictionary in Economy.build_quote(type_id).lines:
		if line.id != "labor":
			total += int(line.get("cost", 0))
	return total


func _set_tag(text: String, color: Color) -> void:
	var words: Label = _tag.label
	words.text = text.to_upper()
	var dot: ColorRect = _tag.dot
	dot.color = color


func _can_place(type_id: String) -> bool:
	if type_id == "" or (type_id != ROAD and Economy.at_build_limit(type_id)):
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
			"description": "Buildings with workers need a road beside them that leads to City Hall. Drag across the map to lay road."}
	return GameData.buildings[type_id]


func _apply_layout() -> void:
	if not _window.visible:
		return
	var tall := size.x < size.y
	_body.vertical = tall
	_split.visible = not tall
	var bottom := size.y - Toolbars.TOOLBAR_SPACE
	if tall:
		# Tall screen (phone held upright): a sheet over the bottom, cards above the details.
		_frame.position = Vector2(0, roundf(size.y * SHEET_TOP))
		_frame.size = Vector2(size.x, bottom - _frame.position.y)
	else:
		# Wide screen (PC / landscape): a wide panel just above the toolbar, below the HUD strip. Its
		# height stays the same whatever building is shown (_fit_all).
		var height := minf(maxf(UITheme.BUILD_PANEL_HEIGHT, _fit), bottom - HUD_SPACE)
		_frame.size = Vector2(minf(UITheme.BUILD_PANEL_WIDTH, size.x - 24.0), height)
		_frame.position = Vector2(roundf((size.x - _frame.size.x) / 2.0), bottom - _frame.size.y)


# --- Small helpers -------------------------------------------------------------

## "6 households ⋅ for Poor ⋅ free": one label per part, so a long line wraps between the parts
## instead of making the details wider.
func _add_parts(parts: Array[String]) -> void:
	for i in parts.size():
		_makes.add_child(_words(parts[i] + (" ⋅" if i < parts.size() - 1 else "")))


## [icon] 40 for each item, e.g. [wheat] 40 [milk] 4.
func _add_amounts(items: Dictionary) -> void:
	for res in items:
		_makes.add_child(UITheme.icon_rect(res, 24))
		_makes.add_child(_words(str(int(items[res]))))


## A number from the data files as words: 3.0 -> "3", 2.5 -> "2.5".
func _num(value: Variant) -> String:
	var f := float(value)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(f)


func _words(text: String) -> Label:
	var label := UITheme.label(text, "SmallLabel")
	label.add_theme_color_override("font_color", UITheme.TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
