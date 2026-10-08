extends ModalWindow
## Developer tools (plan.md §10). Only loaded in test builds (main.gd checks OS.is_debug_build()),
## so real players never see it. Opens with F12 on a computer, or 5 quick taps on the cash bar
## (top-right corner) on a phone. Everything goes through Economy like a player action, so the
## whole game follows at once, and the changes are kept in the save until "Reset all".
## Pages (tabs at the top):
## - Money & time: cash (set or add; not counted as income), skip time ahead (the real time-away
##   catch-up), rent per home type, the performance overlay (F11), Reset all developer changes.
## - Happiness: what happiness does right now, and locks that force the happiness %, what people
##   expect, or one need (Food, Jobs, Housing, Health...) to a value.
## - Tuning: game_config.json's happiness, births and migrant numbers, changed live (in memory
##   only; "Copy as JSON" puts the changed blocks on the clipboard to paste into the file).
## - People: adults in or out, children added or grown up at once.
## - Buildings & items: finish all construction now, put items in the warehouse.
## - Look: the game's colours, shapes, text, button and window sizes and icons
##   (data/ui_look.json), changed live; Save writes the file (when the game runs from Godot).
## A red "DEV" tag shows on screen while any developer change is on.

const QUICK_ADD := [1000, 10000, 100000]
const RENT_STEPS := [-1, 1, 10]  # dollars an hour per button
const SKIPS := [[600, "10 min"], [3600, "1 h"], [21600, "6 h"], [86400, "24 h"]]
const PAGES := [["money", "Money & time"], ["happiness", "Happiness"], ["tuning", "Tuning"], ["people", "People"], ["build", "Buildings & items"], ["look", "Look"]]
const LOCK_STEPS := [-10, -1, 1, 10]  # percentage points per button
const ADULT_STEPS := [-10, -1, 1, 10]
const CHILD_STEPS := [1, 10]
const ITEM_STEPS := [10, 100, 1000]
const TAPS_TO_OPEN := 5
const TAP_WINDOW_MS := 2000  # the taps must all land within this time
const CORNER := Vector2(280, 70)  # the top-right area holding the cash bar
## The Look page's rows. Colours: data/ui_look.json "colors" setting -> its name. Sizes: [section,
## title, shows only after Rebuild windows, {setting: [name, smallest, biggest]}].
const LOOK_COLORS := {
	"glass": "Window glass", "glass_solid": "Window glass (blur off)", "glass_high": "Tooltip glass",
	"glass_high_solid": "Tooltip glass (blur off)", "edge": "Rim", "edge_strong": "Strong rim (outlines)",
	"well": "Sunken boxes", "hover": "Under the pointer", "text": "Text", "text_dim": "Notes text",
	"text_faint": "Hint text", "accent": "Highlight", "accent_high": "Highlight (light)",
	"good": "Good news", "warn": "Warning", "bad": "Bad news", "outline": "Outline over the map",
	"dim": "Shade behind windows", "dim_light": "Shade behind side windows", "button": "Normal button",
	"go": "Go button", "go_rim": "Go button rim", "danger": "Danger button", "danger_rim": "Danger button rim",
	"chip_on": "Picked choice", "chip_on_rim": "Picked choice rim",
}
const LOOK_NUMBERS := [
	["shapes", "Shapes", false, {
		"button_radius": ["Button corners", 0, 30], "chip_radius": ["Choice chip corners", 0, 30],
		"window_radius": ["Window corners", 0, 30], "inset_radius": ["Box corners", 0, 30],
		"rim_width": ["Rim thickness", 0, 6], "window_padding": ["Space inside windows", 0, 40],
		"button_padding": ["Space beside button words", 0, 40], "window_shadow": ["Shadow (windows, bars; 0 = none)", 0, 40]}],
	["text", "Text sizes", false, {
		"small": ["Small notes", 8, 40], "body": ["Body text", 8, 40], "heading": ["Headings", 8, 40],
		"big": ["Big numbers", 8, 48], "title": ["Window titles", 8, 48], "map": ["Words over the map", 8, 40],
		"tooltip": ["Tooltips", 8, 40], "tag": ["Status tags", 8, 32]}],
	["buttons", "Buttons", true, {
		"small_width": ["Small: width", 0, 400], "small_height": ["Small: height", 20, 120], "small_font": ["Small: text", 8, 40],
		"normal_width": ["Normal: width", 0, 400], "normal_height": ["Normal: height", 20, 120], "normal_font": ["Normal: text", 8, 40],
		"big_width": ["Big: width", 0, 500], "big_height": ["Big: height", 20, 140], "big_font": ["Big: text", 8, 48],
		"round_icon": ["Icon tiles (close, tick)", 24, 120], "round_action": ["Tiles with a caption", 24, 140],
		"icon_on_button": ["Icons on buttons", 12, 64]}],
	["windows", "Windows", true, {
		"window_width": ["Window width", 300, 1000], "build_panel_width": ["Build panel width", 500, 1600],
		"build_panel_height": ["Build panel height", 200, 800], "build_details_width": ["Build details width", 200, 700],
		"build_card_width": ["Building card width", 80, 300], "build_card_height": ["Building card height", 80, 300],
		"building_card_width": ["Picked building card width", 250, 700],
		"toolbar_button": ["Bottom toolbar buttons", 32, 120], "screen_button": ["Top-left screen buttons", 24, 100]}],
]
const ICON_TILE := 40.0

var _message: Label
var _pages := {}  # page id -> VBoxContainer
var _tabs := {}  # page id -> Button
var _page := "money"
var _cash: Label
var _amount: LineEdit
var _rent_labels := {}  # home type id -> Label showing its rent
var _mood: Label  # what happiness does right now
var _lock_labels := {}  # lock key -> Label
var _tuning := []  # [{"spec", "label"}] one per tuning row
var _band_titles := []  # Label per mood ("Content 40–69%")
var _people: Label
var _store: Label
var _items: OptionButton
var _item_ids: Array[String] = []
var _dev_tag: Label
var _taps: Array = []  # times of recent taps on the cash bar (ms)
var _look := {}  # the look being edited (data/ui_look.json's shape)
var _look_file := {}  # data/ui_look.json as last loaded or saved (to mark changed sizes with *)
var _look_inputs := {}  # "section.key" -> its ColorPickerButton, or [HSlider, value Label]
var _look_timer: Timer  # restyles the screen a moment after the last change (sliders send many)
var _icon_names: Array[String] = []
var _icon_pick: OptionButton  # which icon to change
var _icon_now: TextureRect  # what it's drawn as now


func _ready() -> void:
	super()
	var hint := _text("Only in test builds. Opens with F12, or 5 quick taps on the cash bar. Changes are kept in the save until Reset all.")
	hint.theme_type_variation = "SmallLabel"
	hint.modulate.a = 0.75
	content.add_child(hint)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	content.add_child(tabs)
	for page in PAGES:
		var tab := _button(page[1], "ChipButton", _show_page.bind(page[0]))
		tabs.add_child(tab)
		_tabs[page[0]] = tab
	_message = _text("")
	content.add_child(_message)
	_pages.money = _money_page()
	_pages.happiness = _happiness_page()
	_pages.tuning = _tuning_page()
	_pages.people = _people_page()
	_pages.build = _build_page()
	_pages.look = _look_page()
	for id in _pages:
		content.add_child(_pages[id])
	_show_page(_page)
	_make_dev_tag()
	Economy.changed.connect(_refresh)
	Economy.changed.connect(_refresh_dev_tag)


## Opens the window (on `page`, if given).
func show_dev(page := "") -> void:
	_message.text = ""
	open("Developer")
	if page != "":
		_show_page(page)
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


func _show_page(id: String) -> void:
	_page = id
	for page_id in _pages:
		_pages[page_id].visible = page_id == id
		_tabs[page_id].theme_type_variation = "ChipOnButton" if page_id == id else "ChipButton"
	_refresh()


# --- Building the pages (once) ----------------------------------------------------

func _money_page() -> VBoxContainer:
	var page := _page_box()
	var box := _section(page, "Cash")
	_cash = _text("")
	_cash.theme_type_variation = "BigLabel"
	box.add_child(_cash)
	var row := _row(box)
	_amount = LineEdit.new()
	_amount.placeholder_text = "Amount in $, e.g. 5000"
	_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount.custom_minimum_size.y = UITheme.SIZES.small.min.y
	_amount.text_submitted.connect(func(_text: String): _add())
	row.add_child(_amount)
	row.add_child(_button("Add", "GoButton", _add))
	row.add_child(_button("Set to", "", _set_cash))
	var quick := _row(box)
	for amount in QUICK_ADD:
		var button := _button("+" + UITheme.dollars(amount), "", _quick_add.bind(amount))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick.add_child(button)
	quick.add_child(_button("Set $0", "DangerButton", func(): _apply(Economy.dev_set_cash(0), "Cash set to $0")))

	var time_box := _section(page, "Skip time ahead")
	time_box.add_child(_small("Works like time away: everything made, sold, born and paid in that time is caught up in one go."))
	var skips := _row(time_box)
	for skip in SKIPS:
		skips.add_child(_button("Skip " + skip[1], "", _skip.bind(skip[0], skip[1])))

	var rent_box := _section(page, "Rent per household (per hour)")
	rent_box.add_child(_small("Households that can't afford the new rent move to cheaper homes, or become homeless."))
	for type_id in GameData.buildings:
		var def: Dictionary = GameData.buildings[type_id]
		if int(def.get("households", 0)) <= 0 or def.get("hut", false):
			continue
		var value := _name_and_value(rent_box, def.name)
		_rent_labels[type_id] = value
		var line := _row(rent_box)
		for step in RENT_STEPS:
			line.add_child(_button("%+d" % step, "ChipOnButton" if step > 0 else "ChipButton", _change_rent.bind(type_id, step)))
		line.add_child(_button("Reset", "DangerButton", _reset_rent.bind(type_id)))

	var speed_box := _section(page, "Performance")
	speed_box.add_child(_button("Show or hide the performance overlay (F11)", "", func():
		var overlay := get_parent().get_node_or_null("PerfOverlay")
		if overlay:
			overlay.toggle()
			close()))

	var reset_box := _section(page, "Developer changes")
	reset_box.add_child(_small("Takes back every happiness lock, tuning change and rent change. Cash, time skips, people, buildings and items stay as they are."))
	reset_box.add_child(_button("Reset all developer changes", "DangerButton", func(): _apply(Economy.dev_reset_all(), "Every developer change taken back")))
	return page


func _happiness_page() -> VBoxContainer:
	var page := _page_box()
	var now_box := _section(page, "Right now")
	_mood = _text("")
	now_box.add_child(_mood)
	var lock_box := _section(page, "Locks")
	lock_box.add_child(_small("Force happiness or one need to a value: births, migrants, leaving and every screen follow at once. Off = worked out from the village again."))
	for lock in _lock_list():
		_lock_labels[lock[0]] = _name_and_value(lock_box, lock[1])
		var line := _row(lock_box)
		for step in LOCK_STEPS:
			line.add_child(_button("%+d" % step, "ChipOnButton" if step > 0 else "ChipButton", _change_lock.bind(lock[0], step)))
		line.add_child(_button("Off", "BackButton", func(): _apply(Economy.dev_lock_happiness(lock[0], -1.0), "%s worked out from the village again" % lock[1])))
	return page


func _tuning_page() -> VBoxContainer:
	var page := _page_box()
	var top := _section(page, "Tuning")
	top.add_child(_small("game_config.json's numbers, changed live from now on (the file itself isn't written). * = changed by you."))
	var buttons := _row(top)
	buttons.add_child(_button("Copy as JSON", "GoButton", _copy_tuning))
	buttons.add_child(_button("Reset tuning", "DangerButton", _reset_tuning))
	var happiness: Dictionary = GameData.config.get("happiness", {})
	_happiness_tuning(page, happiness)
	var bands: Array = happiness.get("moods", [])
	for i in bands.size():
		var band := _section(page, "")
		_band_titles.append(band.get_child(0))
		var at := "happiness.moods.%d." % i
		if i > 0:
			_tuning_row(band, {"path": at + "from", "name": "Starts at", "step": 0.01, "kind": "%", "band": i})
		_tuning_row(band, {"path": at + "births", "name": "Births", "step": 0.5, "kind": "x"})
		_tuning_row(band, {"path": at + "move_in", "name": "Migrant workers", "step": 0.5, "kind": "x", "fallback": at + "births"})
		_tuning_row(band, {"path": at + "leave_per_hour", "name": "Jobless adults leave / h", "step": 0.01, "kind": "%"})
	var life := _section(page, "Births, children and deaths")
	_tuning_row(life, {"path": "life.birth_rate_per_hour", "name": "Babies per adult / h", "step": 0.01})
	_tuning_row(life, {"path": "life.death_rate_per_hour", "name": "Deaths per person / h", "step": 0.001})
	_tuning_row(life, {"path": "life.grow_up_hours", "name": "Children grow up after (h)", "step": 1, "whole": true, "min": 1})
	_tuning_row(life, {"path": "life.grown_ups_leave_without_job", "name": "Grown-ups with no job leave", "kind": "bool"})
	var migrants := _section(page, "Migrant workers")
	_tuning_row(migrants, {"path": "population_growth_seconds", "name": "A group every (seconds)", "step": 10, "whole": true})
	_tuning_row(migrants, {"path": "move_in_group_size", "name": "Up to (adults a group)", "step": 1, "whole": true, "min": 1})
	return page


func _people_page() -> VBoxContainer:
	var page := _page_box()
	var box := _section(page, "People")
	_people = _text("")
	box.add_child(_people)
	box.add_child(_small("Not counted as moving in or away. Taking adults away lets the jobless go first, then workers."))
	var adults := _row(box)
	adults.add_child(_text("Adults"))
	for step in ADULT_STEPS:
		adults.add_child(_button("%+d" % step, "ChipOnButton" if step > 0 else "ChipButton", func(): _apply(Economy.dev_add_adults(step), "%+d adults" % step)))
	var children := _row(box)
	children.add_child(_text("Children"))
	for step in CHILD_STEPS:
		children.add_child(_button("+%d" % step, "ChipOnButton", func(): _apply(Economy.dev_add_children(step), "+%d children" % step)))
	children.add_child(_button("Grow up now", "", func(): _apply(Economy.dev_children_grow_up(), "Every child grew up; any with no job waiting left the island")))
	return page


func _build_page() -> VBoxContainer:
	var page := _page_box()
	var building := _section(page, "Buildings")
	building.add_child(_button("Finish all construction and upgrades now", "GoButton", func():
		var result := Economy.dev_finish_construction()
		_apply(result, "Finished %d building%s" % [int(result.get("finished", 0)), "" if int(result.get("finished", 0)) == 1 else "s"])))
	var items := _section(page, "Items into the warehouse")
	_store = _text("")
	items.add_child(_store)
	_items = OptionButton.new()
	_items.custom_minimum_size.y = UITheme.SIZES.small.min.y
	for res in GameData.resources:
		_items.add_item(str(GameData.resources[res].get("name", res)))
		_item_ids.append(res)
	items.add_child(_items)
	var add := _row(items)
	for qty in ITEM_STEPS:
		add.add_child(_button("+%d" % qty, "ChipOnButton", _add_item.bind(qty)))
	return page


func _look_page() -> VBoxContainer:
	var page := _page_box()
	_look_file = UITheme.load_look()
	_look = UITheme.look.duplicate(true)  # with changes not saved yet, after Rebuild windows
	UITheme.apply_look(_look)
	_look_timer = Timer.new()
	_look_timer.one_shot = true
	_look_timer.wait_time = 0.15
	_look_timer.timeout.connect(_restyle)
	add_child(_look_timer)
	var top := _section(page, "Look")
	top.add_child(_small("The game's colours and sizes (data/ui_look.json). Colours, shapes and text sizes change at once; button and window sizes and icons show after Rebuild windows. Save writes the file when the game runs from Godot; elsewhere it copies the file's text instead."))
	var buttons := _row(top)
	buttons.add_child(_button("Save", "GoButton", _save_look))
	buttons.add_child(_button("Rebuild windows", "", _rebuild_windows))
	buttons.add_child(_button("Copy as JSON", "", func():
		DisplayServer.clipboard_set(_look_json())
		_message.text = "Copied: paste it over everything in data/ui_look.json."))
	buttons.add_child(_button("Undo changes", "DangerButton", _undo_look))

	var colors := _section(page, "Colours")
	colors.add_child(_small("Tap a colour to change it. The picker's A (alpha) is how solid it is."))
	for key in LOOK_COLORS:
		var line := _row(colors)
		line.add_child(_look_name(LOOK_COLORS[key]))
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(120, UITheme.SIZES.small.min.y)
		picker.edit_alpha = true
		picker.color = Color.html(str(_look.colors[key]))
		picker.color_changed.connect(_set_look_color.bind(key))
		line.add_child(picker)
		_look_inputs["colors." + key] = picker

	for group in LOOK_NUMBERS:
		var box := _section(page, group[1])
		if group[2]:
			box.add_child(_small("Shows after Rebuild windows."))
		var rows: Dictionary = group[3]
		for key in rows:
			var line := _row(box)
			line.add_child(_look_name(rows[key][0]))
			var slider := HSlider.new()
			slider.min_value = rows[key][1]
			slider.max_value = rows[key][2]
			slider.step = 1
			slider.custom_minimum_size.x = 130
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.value = float(_look[group[0]][key])
			line.add_child(slider)
			var value := _text("")
			value.custom_minimum_size.x = 60
			value.autowrap_mode = TextServer.AUTOWRAP_OFF
			line.add_child(value)
			slider.value_changed.connect(_set_look_number.bind(group[0], key))
			_look_inputs[group[0] + "." + key] = [slider, value]
			_show_look_number(group[0], key)

	var icons := _section(page, "Icons")
	icons.add_child(_small("Pick an icon, then tap the one to draw in its place. Shows after Rebuild windows."))
	for file in DirAccess.get_files_at(UITheme.ICONS):
		var icon_name := file.trim_suffix(".remap").trim_suffix(".import").trim_suffix(".svg")
		if file.contains(".svg") and not _icon_names.has(icon_name):
			_icon_names.append(icon_name)
	var pick_row := _row(icons)
	_icon_pick = OptionButton.new()
	_icon_pick.custom_minimum_size.y = UITheme.SIZES.small.min.y
	_icon_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for icon_name in _icon_names:
		_icon_pick.add_item(icon_name)
	_icon_pick.item_selected.connect(func(_i: int): _show_icon_swap())
	pick_row.add_child(_icon_pick)
	pick_row.add_child(UITheme.label("drawn as", "SmallLabel"))
	_icon_now = UITheme.icon_rect("item", ICON_TILE)
	pick_row.add_child(_icon_now)
	pick_row.add_child(_button("Put back", "BackButton", _swap_icon.bind("")))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	icons.add_child(grid)
	for icon_name in _icon_names:
		var tile := UITheme.button("", "", "small")
		tile.custom_minimum_size = Vector2(ICON_TILE + 8, ICON_TILE + 8)
		tile.icon = load(UITheme.ICONS + icon_name + ".svg")
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.tooltip_text = icon_name
		tile.pressed.connect(_swap_icon.bind(icon_name))
		grid.add_child(tile)
	_show_icon_swap()
	return page


## One tuning row: name, value (* when changed), and − / + (or a switch for true/false). `spec`:
## "path", "name", "step", "kind" ("%" = a share shown in percent, "x" = a speed, "bool", or
## plain), "whole" (whole numbers), "min", "fallback" (the path used while this one is missing),
## "band" (a band's start: it can't pass its neighbours).
func _tuning_row(parent: Node, spec: Dictionary) -> void:
	var line := _row(parent)
	var name_label := _text(spec.name)
	name_label.custom_minimum_size.x = 150
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var value := _text("")
	value.custom_minimum_size.x = 80
	line.add_child(value)
	if spec.get("kind", "") == "bool":
		line.add_child(_button("Switch", "ChipButton", _change_tuning.bind(spec, 0)))
	else:
		line.add_child(_button("−", "ChipButton", _change_tuning.bind(spec, -1)))
		line.add_child(_button("+", "ChipOnButton", _change_tuning.bind(spec, 1)))
	_tuning.append({"spec": spec, "label": value})


## Puts the "DEV" tag on the game's UI layer (next to this window), shown while changes are on.
func _make_dev_tag() -> void:
	_dev_tag = UITheme.label("DEV", "HeadingLabel")
	_dev_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dev_tag.tooltip_text = "Developer changes are on (F12 → Money & time → Reset all)"
	UITheme.set_font_color(_dev_tag, UITheme.BAD)
	_refresh_dev_tag()
	_place_dev_tag.call_deferred()  # the parent is still setting up its own children now


func _place_dev_tag() -> void:
	get_parent().add_child(_dev_tag)
	_dev_tag.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)


# --- Refreshing (labels only) -------------------------------------------------------

func _refresh_dev_tag() -> void:
	if _dev_tag:
		_dev_tag.visible = Economy.dev_active()


func _refresh() -> void:
	if not visible:
		return
	match _page:
		"money":
			_cash.text = "Now: %s" % UITheme.money(Economy.currency())
			for type_id in _rent_labels:
				var rent := Economy.rent_per_household(type_id)
				_rent_labels[type_id].text = ("free" if rent <= 0.0 else UITheme.price(roundi(rent * 100.0))) + (" *" if Economy.rent_changed(type_id) else "")
		"happiness":
			_refresh_happiness()
		"tuning":
			_refresh_tuning()
		"people":
			var e := Economy.employment()
			_people.text = "%d adults (%d jobless) ⋅ %d children" % [e.adults, e.unemployed, e.children]
		"build":
			_store.text = "Warehouse: %s of %s" % [UITheme.number(Economy.warehouse_total()), UITheme.number(Economy.warehouse_cap())]


func _refresh_happiness() -> void:
	var happy := Economy.happiness()
	var locks := Economy.dev_locks()
	var leaving := "jobless adults %s%%/h" % _pct(float(happy.leave_per_hour)) if float(happy.leave_per_hour) > 0.0 else "nobody"
	var needs: Array[String] = []
	for need in happy.needs:
		needs.append("%s %s%%" % [Economy.need_name(need), _pct(float(happy.needs[need]))])
	var later: Dictionary = happy.get("later", {})
	for need in later:
		needs.append("%s from %d people" % [Economy.need_name(need), int(later[need])])
	_mood.text = "%d%% %s%s\nAverage of needs %s%%\nBabies ×%s ⋅ migrants ×%s ⋅ leaving: %s\n%s" % [
		int(happy.percent), str(happy.mood), " (locked)" if locks.has("score") else "",
		_pct(float(happy.needs_met)),
		str(happy.growth_speed), str(happy.move_in_speed), leaving, " ⋅ ".join(needs)]
	for key in _lock_labels:
		var locked := locks.has(key)
		_lock_labels[key].text = "%s%% %s" % [_pct(float(locks.get(key, _real_value(happy, key)))), "locked" if locked else "real"]
		UITheme.set_font_color(_lock_labels[key], UITheme.BAD if locked else UITheme.TEXT)


func _refresh_tuning() -> void:
	var changed := Economy.dev_config()
	for row in _tuning:
		var spec: Dictionary = row.spec
		row.label.text = _tuning_text(spec, _tuning_value(spec)) + (" *" if changed.has(spec.path) else "")
	var bands: Array = GameData.config.get("happiness", {}).get("moods", [])
	for i in mini(_band_titles.size(), bands.size()):
		var top := "100" if i + 1 >= bands.size() else str(Economy.happiness_percent(float(bands[i + 1].from)) - 1)
		_band_titles[i].text = "%s %d–%s%%" % [str(bands[i].get("name", "Mood")), Economy.happiness_percent(float(bands[i].from)), top]


# --- Look --------------------------------------------------------------------------

func _set_look_color(color: Color, key: String) -> void:
	_look.colors[key] = "#" + color.to_html(color.a < 1.0)
	_look_timer.start()


func _set_look_number(value: float, section: String, key: String) -> void:
	_look[section][key] = roundi(value)
	_show_look_number(section, key)
	_look_timer.start()


## A size's value next to its slider (* = not what the file has).
func _show_look_number(section: String, key: String) -> void:
	var file_value: Variant = _look_file.get(section, {}).get(key)
	var changed: bool = file_value == null or roundi(file_value) != int(_look[section][key])
	_look_inputs[section + "." + key][1].text = "%d%s" % [int(_look[section][key]), " *" if changed else ""]


## Restyles everything on screen with the edited look (the theme is built again).
func _restyle() -> void:
	UITheme.apply_look(_look)
	var main := get_tree().current_scene
	if main.has_method("restyle"):
		main.restyle()


## Makes every window again (the scene is loaded again), so sizes and icons show; this window
## opens again on the Look page.
func _rebuild_windows() -> void:
	UITheme.apply_look(_look)
	var main := get_tree().current_scene
	if main.has_method("rebuild_windows"):
		main.rebuild_windows()


## Back to what data/ui_look.json has.
func _undo_look() -> void:
	_look_file = UITheme.load_look()
	_look = _look_file.duplicate(true)
	for path in _look_inputs:
		var section := String(path).get_slice(".", 0)
		var key := String(path).get_slice(".", 1)
		var input: Variant = _look_inputs[path]
		if input is ColorPickerButton:
			input.color = Color.html(str(_look.colors[key]))
		else:
			input[0].set_value_no_signal(float(_look[section][key]))
			_show_look_number(section, key)
	_restyle()
	_show_icon_swap()
	_message.text = "Back to data/ui_look.json (Rebuild windows to see sizes and icons)."


## Draws the picked icon as `icon_name` instead ("" = its own picture again).
func _swap_icon(icon_name: String) -> void:
	if _icon_pick.selected < 0:
		return
	var slot := _icon_names[_icon_pick.selected]
	var icons: Dictionary = _look.get("icons", {})
	if icon_name == "" or icon_name == slot:
		icons.erase(slot)
	else:
		icons[slot] = icon_name
	_look["icons"] = icons
	UITheme.apply_look(_look)
	_show_icon_swap()
	_message.text = "%s is drawn as %s: Rebuild windows to see it everywhere." % [slot, icons.get(slot, slot)]


func _show_icon_swap() -> void:
	if _icon_pick.selected >= 0:
		_icon_now.texture = UITheme.icon(_icon_names[_icon_pick.selected])


## Writes data/ui_look.json (only possible while the game runs from Godot); otherwise copies it.
func _save_look() -> void:
	var file := FileAccess.open(UITheme.LOOK_FILE, FileAccess.WRITE) if OS.has_feature("editor") else null
	if file == null:
		DisplayServer.clipboard_set(_look_json())
		_message.text = "This copy of the game can't write its own files: the look was copied instead. Paste it over everything in data/ui_look.json."
		return
	file.store_string(_look_json())
	file.close()
	_look_file = _look.duplicate(true)
	for path in _look_inputs:
		if not _look_inputs[path] is ColorPickerButton:
			_show_look_number(String(path).get_slice(".", 0), String(path).get_slice(".", 1))
	_message.text = "Saved data/ui_look.json."


## The edited look as data/ui_look.json's text (its "_about" note kept, settings in file order).
func _look_json() -> String:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(UITheme.LOOK_FILE))
	var out := {}
	if raw is Dictionary and raw.has("_about"):
		out["_about"] = raw._about
	for section in _look:
		out[section] = _look[section]
	return JSON.stringify(out, "\t", false) + "\n"


func _look_name(text: String) -> Label:
	var label := _text(text)
	label.custom_minimum_size.x = 150
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


# --- Actions ----------------------------------------------------------------------

func _skip(seconds: float, label: String) -> void:
	TimeService.warp(seconds)
	var report := Economy.tick()
	var parts: Array[String] = []
	for key in [["born", "born"], ["grew_up", "grew up"], ["moved_away", "left the island"], ["population", "moved in"]]:
		if int(report.get(key[0], 0)) > 0:
			parts.append("%d %s" % [int(report[key[0]]), key[1]])
	var made: Array[String] = []
	for res in report:
		if GameData.resources.has(res) and int(report[res]) > 0:
			made.append("%d %s" % [int(report[res]), str(GameData.resources[res].get("name", res)).to_lower()])
	if not made.is_empty():
		parts.append("made " + ", ".join(made))
	_message.text = "Skipped %s%s" % [label, ": " + " ⋅ ".join(parts) if not parts.is_empty() else ""]
	_refresh()


## What can be locked, with its name: the score and each need.
func _lock_list() -> Array:
	var out := [["score", "Happiness"]]
	for key in Economy.dev_lock_keys():
		if key != "score":
			out.append([key, "%s need" % Economy.need_name(key)])
	return out


## The value a lock replaces, as the village really has it (0-1).
func _real_value(happy: Dictionary, key: String) -> float:
	if key == "score":
		return float(happy[key])
	return float(happy.needs.get(key, 0.0))


## Tuning rows for happiness (game_config.json happiness): when each need starts counting, and
## the Food and Housing needs' own numbers.
func _happiness_tuning(page: VBoxContainer, happiness: Dictionary) -> void:
	var needs: Dictionary = happiness.get("needs", {})
	var counts := _section(page, "Needs count from (people)")
	for need in needs:
		_tuning_row(counts, {"path": "happiness.needs.%s.from_people" % need, "name": Economy.need_name(need), "step": 25, "whole": true})
	var food := _section(page, "Food need by different foods selling")
	var scores: Array = needs.get("food", {}).get("scores", [])
	for i in scores.size():
		_tuning_row(food, {"path": "happiness.needs.food.scores.%d" % i, "name": "%d%s food%s" % [i, "+" if i == scores.size() - 1 else "", "" if i == 1 else "s"], "step": 0.05, "kind": "%"})
	if needs.get("food", {}).has("max_happiness_when_unmet"):
		_tuning_row(food, {"path": "happiness.needs.food.max_happiness_when_unmet", "name": "No food: happiness at most", "step": 0.05, "kind": "%"})
	var other := _section(page, "Homes and leaving")
	if needs.get("housing", {}).has("unpowered"):
		_tuning_row(other, {"path": "happiness.needs.housing.unpowered", "name": "A home without power counts", "step": 0.05, "kind": "%"})
	_tuning_row(other, {"path": "happiness.leave_group_size", "name": "People leave in groups of", "step": 1, "whole": true, "min": 1})


## A lock up or down by `step` percentage points, starting from the real value when it's off.
func _change_lock(key: String, step: int) -> void:
	var value := clampf(float(Economy.dev_locks().get(key, _real_value(Economy.happiness(), key))) + step / 100.0, 0.0, 1.0)
	value = roundf(value * 100.0) / 100.0  # whole percent
	_apply(Economy.dev_lock_happiness(key, value), "Locked at %s%%" % _pct(value))


## A tuning number up (+1) or down (-1) by its step, or a true/false switched (0). Back at the
## file's value, the change is taken back (no "*").
func _change_tuning(spec: Dictionary, direction: int) -> void:
	var current: Variant = _tuning_value(spec)
	var value: Variant
	if spec.get("kind", "") == "bool":
		value = not bool(current)
	else:
		var low := float(spec.get("min", 0.0))
		var high := 1.0 if spec.get("kind", "") == "%" else INF
		if spec.has("band"):  # a band's start stays between its neighbours'
			var bands: Array = GameData.config.happiness.moods
			low = float(bands[spec.band - 1].from) + 0.01
			if spec.band + 1 < bands.size():
				high = float(bands[spec.band + 1].from) - 0.01
		var number := clampf(float(current) + direction * float(spec.step), low, high)
		value = roundi(number) if spec.get("whole", false) else snappedf(number, 0.0001)
	var file_value: Variant = GameData.file_config_value(spec.path)
	var back_to_file: bool = file_value != null and (value == file_value if value is bool else is_equal_approx(float(value), float(file_value)))
	_apply(Economy.dev_set_config(spec.path, null if back_to_file else value), "%s: %s" % [spec.name, _tuning_text(spec, value)])


func _reset_tuning() -> void:
	for path in Economy.dev_config().keys():
		Economy.dev_set_config(path, null)
	_apply({"ok": true}, "Tuning back to game_config.json")


## Copies each changed block of game_config.json, with the changes, as JSON to paste into the file.
func _copy_tuning() -> void:
	var blocks: Array[String] = []
	for path in Economy.dev_config():
		var key := String(path).get_slice(".", 0)
		if not blocks.has(key):
			blocks.append(key)
	if blocks.is_empty():
		_message.text = "Nothing changed yet: nothing to copy."
		return
	var text: Array[String] = []
	for key in blocks:
		text.append("\"%s\": %s" % [key, JSON.stringify(GameData.config[key], "\t")])
	DisplayServer.clipboard_set(",\n".join(text))
	_message.text = "Copied %s: paste over those lines in data/game_config.json." % ", ".join(blocks)


func _add_item(qty: int) -> void:
	if _items.selected < 0:
		return
	var res := _item_ids[_items.selected]
	var result := Economy.dev_add_item(res, qty)
	_apply(result, "Added %d %s" % [int(result.get("added", 0)), str(GameData.resources[res].get("name", res))])


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


# --- Helpers ------------------------------------------------------------------------

## A tuning row's value now: the config's (with any changes), else its fallback's, else false/0.
func _tuning_value(spec: Dictionary) -> Variant:
	var value: Variant = GameData.config_value(spec.path)
	if value == null and spec.has("fallback"):
		value = GameData.config_value(spec.fallback)
	if value == null:
		value = false if spec.get("kind", "") == "bool" else 0.0
	return value


func _tuning_text(spec: Dictionary, value: Variant) -> String:
	match spec.get("kind", ""):
		"bool":
			return "yes" if bool(value) else "no"
		"%":
			return _pct(float(value)) + "%"
		"x":
			return "×" + str(snappedf(float(value), 0.01))
	return str(int(value)) if spec.get("whole", false) else str(snappedf(float(value), 0.0001))


## A share as a percent with at most one decimal: 0.05 -> "5", 0.125 -> "12.5".
func _pct(share: float) -> String:
	var percent := snappedf(share * 100.0, 0.1)
	return str(roundi(percent)) if is_equal_approx(percent, roundf(percent)) else str(percent)


func _page_box() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	flow_page(page)  # a long page carries on in a panel beside the window
	return page


func _section(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Inset"
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(UITheme.label(title, "HeadingLabel"))
	return column


## "Name ........ value" on one line (the buttons that change it go on a row under it). Returns
## the value label.
func _name_and_value(parent: Node, title: String) -> Label:
	var line := _row(parent)
	var name_label := UITheme.label(title)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var value := UITheme.label("")
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(value)
	return value


func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row


func _button(text: String, variation: String, action: Callable) -> Button:
	var button := UITheme.button(text, variation, "small")
	button.pressed.connect(action)
	return button


func _text(text: String) -> Label:
	return UITheme.wrapped(text, UITheme.WINDOW_WIDTH - 70)


func _small(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = "SmallLabel"
	label.modulate.a = 0.75
	return label
