extends ModalWindow
## Developer tools (plan.md §10). Only loaded in test builds (main.gd checks OS.is_debug_build()),
## so real players never see it. Opens with F12 on a computer, or 5 quick taps on the cash bar
## (top-right corner) on a phone. Everything goes through Economy like a player action, so the
## whole game follows at once, and the changes are kept in the save until "Reset all".
## Pages (tabs at the top):
## - Money & time: cash (set or add; not counted as income), skip time ahead (the real time-away
##   catch-up), rent per home type, the performance overlay (F11), Reset all developer changes.
## - Happiness: what happiness does right now, and locks that force the happiness % or one need
##   (Food, Jobs, Housing, hut penalty) to a value.
## - Tuning: game_config.json's happiness, births and migrant numbers, changed live (in memory
##   only; "Copy as JSON" puts the changed blocks on the clipboard to paste into the file).
## - People: adults in or out, children added or grown up at once, end the new-village grace.
## - Buildings & items: finish all construction now, put items in the warehouse.
## A red "DEV" tag shows on screen while any developer change is on.

const QUICK_ADD := [1000, 10000, 100000]
const RENT_STEPS := [-1, 1, 10]  # dollars an hour per button
const SKIPS := [[600, "10 min"], [3600, "1 h"], [21600, "6 h"], [86400, "24 h"]]
const PAGES := [["money", "Money & time"], ["happiness", "Happiness"], ["tuning", "Tuning"], ["people", "People"], ["build", "Buildings & items"]]
const LOCKS := [["score", "Happiness"], ["food", "Food need"], ["jobs", "Jobs need"], ["housing", "Housing need"], ["penalty", "Hut penalty"]]
const LOCK_STEPS := [-10, -1, 1, 10]  # percentage points per button
const ADULT_STEPS := [-10, -1, 1, 10]
const CHILD_STEPS := [1, 10]
const ITEM_STEPS := [10, 100, 1000]
const TAPS_TO_OPEN := 5
const TAP_WINDOW_MS := 2000  # the taps must all land within this time
const CORNER := Vector2(280, 70)  # the top-right area holding the cash bar

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
var _band_titles := []  # Label per happiness band ("Band from 21%")
var _people: Label
var _store: Label
var _items: OptionButton
var _item_ids: Array[String] = []
var _dev_tag: Label
var _taps: Array = []  # times of recent taps on the cash bar (ms)


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
	for id in _pages:
		content.add_child(_pages[id])
	_show_page(_page)
	_make_dev_tag()
	Economy.changed.connect(_refresh)
	Economy.changed.connect(_refresh_dev_tag)


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
		var line := _row(rent_box)
		var name_label := _text(def.name)
		name_label.custom_minimum_size.x = 150
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value := _text("")
		value.custom_minimum_size.x = 110
		line.add_child(value)
		_rent_labels[type_id] = value
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
	lock_box.add_child(_small("Force happiness, or one need, to a value: births, migrants, leaving and every screen follow at once. A lock counts even in a new or small village. Off = worked out from the village again."))
	for lock in LOCKS:
		var line := _row(lock_box)
		var name_label := _text(lock[1])
		name_label.custom_minimum_size.x = 120
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var value := _text("")
		value.custom_minimum_size.x = 110
		line.add_child(value)
		_lock_labels[lock[0]] = value
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
	var mix := _section(page, "Needs mix (weights)")
	for need in ["food", "jobs", "housing"]:
		_tuning_row(mix, {"path": "happiness.weights." + need, "name": need.capitalize(), "step": 0.5})
	var food := _section(page, "Food need by different foods selling")
	var scores: Array = happiness.get("food_scores", [])
	for i in scores.size():
		_tuning_row(food, {"path": "happiness.food_scores.%d" % i, "name": "%d%s food%s" % [i, "+" if i == scores.size() - 1 else "", "" if i == 1 else "s"], "step": 0.05, "kind": "%"})
	var huts := _section(page, "Hut penalty and when needs count")
	_tuning_row(huts, {"path": "happiness.homeless_penalty.per_household", "name": "Per household in a hut", "step": 0.01, "kind": "%"})
	_tuning_row(huts, {"path": "happiness.homeless_penalty.max", "name": "At most", "step": 0.05, "kind": "%"})
	_tuning_row(huts, {"path": "happiness.needs_from_population", "name": "Needs count from (people)", "step": 5, "whole": true})
	_tuning_row(huts, {"path": "happiness.grace_hours", "name": "New-village grace (hours)", "step": 1, "whole": true})
	_tuning_row(huts, {"path": "happiness.leave_group_size", "name": "People leave in groups of", "step": 1, "whole": true, "min": 1})
	var bands: Array = happiness.get("growth_speeds", [])
	for i in bands.size():
		var band := _section(page, "")
		_band_titles.append(band.get_child(0))
		var at := "happiness.growth_speeds.%d." % i
		if i > 0:
			_tuning_row(band, {"path": at + "from", "name": "Starts at", "step": 0.01, "kind": "%", "band": i})
		_tuning_row(band, {"path": at + "speed", "name": "Births", "step": 0.5, "kind": "x"})
		_tuning_row(band, {"path": at + "move_in", "name": "Migrant workers", "step": 0.5, "kind": "x", "fallback": at + "speed"})
		_tuning_row(band, {"path": at + "leave_per_hour", "name": "Jobless adults leave / h", "step": 0.01, "kind": "%"})
		_tuning_row(band, {"path": at + "children_leave_per_hour", "name": "Children leave / h", "step": 0.01, "kind": "%", "fallback": at + "leave_per_hour"})
		_tuning_row(band, {"path": at + "homeless_workers_leave", "name": "Workers in huts leave too", "kind": "bool"})
	var life := _section(page, "Births, children and deaths")
	_tuning_row(life, {"path": "life.birth_rate_per_hour", "name": "Babies per adult / h", "step": 0.01})
	_tuning_row(life, {"path": "life.death_rate_per_hour", "name": "Deaths per person / h", "step": 0.001})
	_tuning_row(life, {"path": "life.grow_up_hours", "name": "Children grow up after (h)", "step": 1, "whole": true, "min": 1})
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
	children.add_child(_button("Grow up now", "", func(): _apply(Economy.dev_children_grow_up(), "Every child grew up")))
	box.add_child(_button("End the new-village grace period (needs count from now)", "", func(): _apply(Economy.dev_end_grace(), "Grace period over: needs count from now")))
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


## One tuning row: name, value (* when changed), and − / + (or a switch for true/false). `spec`:
## "path", "name", "step", "kind" ("%" = a share shown in percent, "x" = a speed, "bool", or
## plain), "whole" (whole numbers), "min", "fallback" (the path used while this one is missing),
## "band" (a band's start: it can't pass its neighbours).
func _tuning_row(parent: Node, spec: Dictionary) -> void:
	var line := _row(parent)
	var name_label := _text(spec.name)
	name_label.custom_minimum_size.x = 200
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var value := _text("")
	value.custom_minimum_size.x = 90
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
			var grace := float(Economy.happiness().grace_left)
			_people.text = "%d adults (%d jobless) · %d children · %s" % [e.adults, e.unemployed, e.children,
				"grace: %s left" % UITheme.duration(grace) if grace > 0.0 else "grace period over"]
		"build":
			_store.text = "Warehouse: %s of %s" % [UITheme.number(Economy.warehouse_total()), UITheme.number(Economy.warehouse_cap())]


func _refresh_happiness() -> void:
	var happy := Economy.happiness()
	var locks := Economy.dev_locks()
	var bands: Array = GameData.config.get("happiness", {}).get("growth_speeds", [])
	var band := 0
	for i in bands.size():
		if float(happy.score) + 0.000001 >= float(bands[i].from):
			band = i
	var top := "100" if band + 1 >= bands.size() else str(Economy.happiness_percent(float(bands[band + 1].from)) - 1)
	var leaving: Array[String] = []
	if float(happy.leave_per_hour) > 0.0:
		leaving.append("jobless adults%s %s%%/h" % [" + workers in huts" if happy.homeless_workers_leave else "", _pct(float(happy.leave_per_hour))])
	if float(happy.children_leave_per_hour) > 0.0:
		leaving.append("children %s%%/h" % _pct(float(happy.children_leave_per_hour)))
	_mood.text = "%d%% happy%s · band %d–%s%%\nBabies ×%s · migrants ×%s · leaving: %s\nFood %s%% · Jobs %s%% · Housing %s%% · hut penalty −%s%%%s" % [
		int(happy.percent), " (locked)" if locks.has("score") else "",
		Economy.happiness_percent(float(bands[band].from)) if not bands.is_empty() else 0, top,
		str(happy.growth_speed), str(happy.move_in_speed), ", ".join(leaving) if not leaving.is_empty() else "nobody",
		_pct(float(happy.food)), _pct(float(happy.jobs)), _pct(float(happy.housing)), _pct(float(happy.homeless_penalty)),
		"" if happy.needs_count else "\n(needs don't count yet: %s)" % ("new village" if float(happy.grace_left) > 0.0 else "small village")]
	var real := {"score": happy.score, "food": happy.food, "jobs": happy.jobs, "housing": happy.housing, "penalty": happy.homeless_penalty}
	for key in _lock_labels:
		var locked := locks.has(key)
		_lock_labels[key].text = "%s%% %s" % [_pct(float(locks.get(key, real[key]))), "locked" if locked else "real"]
		UITheme.set_font_color(_lock_labels[key], UITheme.BAD if locked else UITheme.TEXT)


func _refresh_tuning() -> void:
	var changed := Economy.dev_config()
	for row in _tuning:
		var spec: Dictionary = row.spec
		row.label.text = _tuning_text(spec, _tuning_value(spec)) + (" *" if changed.has(spec.path) else "")
	var bands: Array = GameData.config.get("happiness", {}).get("growth_speeds", [])
	for i in mini(_band_titles.size(), bands.size()):
		var top := "100" if i + 1 >= bands.size() else str(Economy.happiness_percent(float(bands[i + 1].from)) - 1)
		_band_titles[i].text = "Happiness %d–%s%%" % [Economy.happiness_percent(float(bands[i].from)), top]


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
	_message.text = "Skipped %s%s" % [label, ": " + " · ".join(parts) if not parts.is_empty() else ""]
	_refresh()


## A lock up or down by `step` percentage points, starting from the real value when it's off.
func _change_lock(key: String, step: int) -> void:
	var happy := Economy.happiness()
	var real := {"score": happy.score, "food": happy.food, "jobs": happy.jobs, "housing": happy.housing, "penalty": happy.homeless_penalty}
	var value := clampf(float(Economy.dev_locks().get(key, real[key])) + step / 100.0, 0.0, 1.0)
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
			var bands: Array = GameData.config.happiness.growth_speeds
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
	return UITheme.wrapped(text, WIDTH - 70)


func _small(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = "SmallLabel"
	label.modulate.a = 0.75
	return label
