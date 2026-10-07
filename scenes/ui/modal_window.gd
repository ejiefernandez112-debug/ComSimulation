class_name ModalWindow
extends Control
## A pop-up window over the game: a dark glass panel with the title strip across its top (title +
## close ✕, UITheme.title_bar) that fades in. Every pop-up window uses this, so they all look the
## same. Wide screens (PC) dock the window along the left edge, so the map stays in view, with the
## map dimmed only a little; small questions ("Are you sure?", "Welcome back!") sit in the middle
## instead (docked = false). Tall (phone) screens get a sheet along the bottom (plan.md §6).
## BuildingPanel and SettingsPanel build on this: they fill `content` with their own rows.
##
## No scroll bar on wide screens: when the rows don't fit the window's height, the ones that don't
## fit move to a second glass panel beside it (a third, and so on, while the screen is wide enough).
## The rows are the children of `content`; a page (a container marked with flow_page(), e.g. one
## tab of Statistics) lends its own children instead, so a long page can be split too. Only when
## even that doesn't fit (or on a phone held upright) do the rows scroll.

signal closed

const SHEET_TOP := 0.35  # on tall screens the sheet covers the bottom 65%
const GAP := 12  # space between a docked window and the screen's edges
## A docked window starts below the screen buttons in the top-left corner (menu_bar.gd).
const DOCK_TOP := 72.0
const FRAME_HEIGHT := 84.0  # the title strip and the window's edges: what's left over is for the rows
## The most of the screen's height a window may take (more rows go on to an extra panel beside it),
## so the map stays in view: docked at the side, and in the middle of the screen.
const MAX_DOCKED_HEIGHT := 0.72
const MAX_MIDDLE_HEIGHT := 0.8
## For this long after opening, tapping outside doesn't close the window: a quick second tap (a
## double-tap on the building that opened it) would otherwise shut it straight away.
const IGNORE_OUTSIDE_TAPS_MS := 300
const ROW_GAP := 8  # space between rows, in the window and in the extra panels
## Every window is in this group (and the Build panel and the building card at the bottom): while
## one is open the map behind it doesn't zoom (village_camera.gd).
const GROUP := "modal_windows"

var content: VBoxContainer
## Wide screens: dock along the left edge (true) or sit in the middle (false). Set it in _init().
var docked := true
var _opened_at_ms := 0  # when the window last opened (milliseconds since the game started)
var _title: Label
var _dim: ColorRect
var _window: PanelContainer
var _scroll: ScrollContainer
## The extra panels beside the window and their row columns (made when first needed, then reused).
var _panels: Array[PanelContainer] = []
var _columns: Array[VBoxContainer] = []
var _last_rows: Array[Control] = []  # the rows and where they went at the last layout
var _last_place: Array[int] = []


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_node("Window"):
		_use_scene_frame()
	else:
		_make_frame()
	hide()
	resized.connect(_layout)
	content.minimum_size_changed.connect(_queue_layout)  # rows grew, shrank, showed or hid


## Marks a container in `content` as a page: its children are rows that may move to the extra
## panels one by one (instead of the whole page moving as one).
static func flow_page(page: Control) -> void:
	page.set_meta("flow_page", true)


## A window laid out in the Godot editor (a .tscn, e.g. settings_panel.tscn) brings its own frame:
## nodes named Dim, Window, and (unique names) %Title, %Close, %Scroll and %Content.
func _use_scene_frame() -> void:
	_dim = get_node("Dim")
	_dim.gui_input.connect(_on_dim_input)
	_window = get_node("Window")
	UITheme.frost(_window)
	_title = get_node("%Title")
	(get_node("%Close") as BaseButton).pressed.connect(close)
	_scroll = get_node("%Scroll")
	content = get_node("%Content")


## Other windows build the same frame in code.
func _make_frame() -> void:
	_dim = ColorRect.new()
	_dim.color = UITheme.DIM
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim_input)  # tapping outside the window closes it
	add_child(_dim)
	_window = PanelContainer.new()
	UITheme.frost(_window)
	add_child(_window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_window.add_child(column)
	var header := UITheme.title_bar()
	column.add_child(header.bar)
	_title = header.label
	header.close.pressed.connect(close)
	# The rows scroll if the screen is too short to show them all.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)


func open(title_text: String) -> void:
	_title.text = title_text
	_opened_at_ms = Time.get_ticks_msec()
	if not visible:  # opening again while open (another building) just refreshes it
		Sfx.play("panel_open")
	show()
	_layout()
	_layout.call_deferred()  # again once new text has been measured
	UITheme.pop_in(_window)


func close() -> void:
	if visible:
		hide()
		Sfx.play("panel_close")
		closed.emit()


## Empties `content` (and the extra panels), ready to be filled again.
func clear_content() -> void:
	_last_rows.clear()
	var boxes: Array[Control] = [content]
	boxes.append_array(_columns)
	for box in boxes:
		for child in box.get_children():
			box.remove_child(child)  # out right away, so the window's size is measured without it
			child.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Time.get_ticks_msec() - _opened_at_ms >= IGNORE_OUTSIDE_TAPS_MS:
			close()


## Rows grew, shrank, showed or hid: lay out again on the next frame, once. Laying out moves rows
## and resizes the window, which changes sizes again; so it only happens when the rows would go
## somewhere else or the window no longer fits them, never again and again.
func _queue_layout() -> void:
	if visible and not get_tree().process_frame.is_connected(_relayout):
		get_tree().process_frame.connect(_relayout, CONNECT_ONE_SHOT)


func _relayout() -> void:
	if not visible or size.x < size.y:
		return  # a phone's sheet keeps its size and scrolls
	var rows := _flow_rows()
	if rows == _last_rows and _flow_place(rows) == _last_place and _sizes_fit():
		return
	_layout()


## Whether the window and the extra panels are exactly as big as their rows need.
func _sizes_fit() -> bool:
	var boxes: Array[Control] = [_window]
	for panel in _panels:
		if panel.visible:
			boxes.append(panel)
	for box in boxes:
		if not box.size.is_equal_approx(box.get_combined_minimum_size()):
			return false
	return true


## How much room the window has for rows: as tall as they need, but no taller than the screen
## allows (then they go on to an extra panel, or scroll on a phone).
func _room() -> float:
	var tall := size.x < size.y
	if docked and not tall:
		return minf(size.y - DOCK_TOP - GAP, size.y * MAX_DOCKED_HEIGHT) - FRAME_HEIGHT
	return size.y * (1.0 - SHEET_TOP if tall else MAX_MIDDLE_HEIGHT) - FRAME_HEIGHT


## Which panel each row goes in (see _flow_plan). Once the rows need more than one panel anyway,
## the panels may use the whole height of the screen (the extra panels have no title strip: that
## room is theirs too).
func _flow_place(rows: Array[Control]) -> Array[int]:
	var room := _room()
	var place := _flow_plan(rows, room, room)
	if place.is_empty() or int(place.back()) > 0:
		var full := (size.y - DOCK_TOP - GAP if docked else size.y - 2.0 * GAP) - FRAME_HEIGHT
		place = _flow_plan(rows, full, full + FRAME_HEIGHT - 2.0 * UITheme.WINDOW_PADDING)
	return place


func _layout() -> void:
	if not visible:
		return
	var tall := size.x < size.y
	var side := docked and not tall
	_dim.color = UITheme.DIM_LIGHT if side else UITheme.DIM
	var room := _room()
	var columns := 1
	if not tall:
		var rows := _flow_rows()
		var place := _flow_place(rows)
		columns = 0 if place.is_empty() else int(place.back()) + 1
		_flow_apply(rows, place)
		_last_rows = rows
		_last_place = place
	var scrolls := tall or columns == 0  # a phone, or too much even for the extra panels
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if scrolls else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, room) if scrolls else 0.0
	_window.reset_size()
	if tall:
		# Tall screen (phone held upright): sheet across the bottom.
		_window.custom_minimum_size.x = 0
		_window.set_anchors_preset(Control.PRESET_FULL_RECT)
		_window.anchor_top = SHEET_TOP
		_window.offset_left = 0
		_window.offset_right = 0
		_window.offset_top = 0
		_window.offset_bottom = 0
	elif side:
		# Wide screen (PC / landscape): docked along the left edge, below the screen buttons and
		# clear of the HUD in the top-right corner.
		_window.custom_minimum_size.x = UITheme.WINDOW_WIDTH
		_window.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, GAP)
		_window.position.y = DOCK_TOP
		_window.grow_horizontal = Control.GROW_DIRECTION_END
		_window.grow_vertical = Control.GROW_DIRECTION_END
	else:
		# Wide screen, small question: a window in the middle.
		_window.custom_minimum_size.x = UITheme.WINDOW_WIDTH
		_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		_window.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_window.grow_vertical = Control.GROW_DIRECTION_BOTH
	_place_flow_panels(0 if tall else maxi(columns, 1), side)


# --- Extra panels beside the window ----------------------------------------------

## Which panel each row goes in (0 = the window), in order: the window holds `room` of rows, each
## extra panel `panel_room`. Empty when they need more panels than the screen is wide enough for.
func _flow_plan(rows: Array[Control], room: float, panel_room: float) -> Array[int]:
	var most := maxi(floori((size.x - GAP) / (UITheme.WINDOW_WIDTH + GAP)), 1)
	var place: Array[int] = []
	var panel := 0
	var used := 0.0
	for row in rows:
		var height := row.get_combined_minimum_size().y
		if used > 0.0 and used + ROW_GAP + height > (room if panel == 0 else panel_room):
			panel += 1
			used = 0.0
		used += (ROW_GAP if used > 0.0 else 0.0) + height
		place.append(panel)
	if panel + 1 > most:
		place.clear()
	return place


## Moves the rows to their panels (`place` from _flow_plan; empty = all in the window). Rows only
## move when they have to, so laying out again with nothing changed moves nothing.
func _flow_apply(rows: Array[Control], place: Array[int]) -> void:
	var panels := 0 if place.is_empty() else int(place.back())
	while _columns.size() < panels:
		_add_flow_panel()
	# The window's rows go back where they belong (content, or their page); the others to their
	# panel, in order.
	var counts := {}  # panel -> rows put in it so far
	for i in rows.size():
		var row := rows[i]
		if place.is_empty() or place[i] == 0:
			_flow_home(row)
			continue
		var column := _columns[place[i] - 1]
		var at := int(counts.get(place[i], 0))
		counts[place[i]] = at + 1
		if row.get_parent() != column:
			_move_row(row, column)
		if row.get_index() != at:
			column.move_child(row, at)
	# Rows of a hidden page (another tab) that were out in a panel go home too.
	for column in _columns:
		for child in column.get_children():
			if not rows.has(child):
				_flow_home(child)


## The rows in order: the shown children of `content`, with each shown page's own children in its
## place. Rows out in an extra panel right now count where they belong.
func _flow_rows() -> Array[Control]:
	var out: Array[Control] = []
	for item in _flow_children(content):
		if not item.visible:
			continue
		if not item.has_meta("flow_page"):
			out.append(item)
			continue
		for row in _flow_children(item):
			if row.visible:
				out.append(row)
	return out


## The rows that belong in `home` (content, or a page), in their order: the ones in it now and the
## ones out in an extra panel.
func _flow_children(home: Control) -> Array[Control]:
	var mine: Array[Control] = []
	for child in home.get_children():
		if child is Control:
			_flow_remember(child, home)
			mine.append(child)
	for column in _columns:
		for row in column.get_children():
			if row.has_meta("flow_home") and row.get_meta("flow_home") == home:
				mine.append(row)
	mine.sort_custom(func(a: Control, b: Control) -> bool: return int(a.get_meta("flow_order")) < int(b.get_meta("flow_order")))
	return mine


## Notes where a row belongs and its place there, the first time it's seen.
func _flow_remember(row: Control, home: Control) -> void:
	if not row.has_meta("flow_home"):
		row.set_meta("flow_home", home)
		row.set_meta("flow_order", row.get_index())


## Puts a row back where it belongs, in its place among the rows there.
func _flow_home(row: Control) -> void:
	var home: Control = row.get_meta("flow_home", content)
	if row.get_parent() != home:
		_move_row(row, home)
	var at := 0
	for child in home.get_children():
		if child != row and int(child.get_meta("flow_order", -1)) < int(row.get_meta("flow_order", 0)):
			at += 1
	if row.get_index() != at:
		home.move_child(row, at)


## Moves a row to another column. A window laid out in the editor (Settings) names its rows for
## its script (%MusicRow...); taking the row out and putting it back by hand, then giving it its
## owner again, keeps those names working (Godot's reparent() crashed on them).
func _move_row(row: Control, to: Control) -> void:
	var owner_was := row.owner
	row.get_parent().remove_child(row)
	to.add_child(row)
	if owner_was != null and owner_was.is_ancestor_of(row):
		row.owner = owner_was


func _add_flow_panel() -> void:
	var panel := PanelContainer.new()
	UITheme.frost(panel)
	panel.custom_minimum_size.x = UITheme.WINDOW_WIDTH
	panel.hide()
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", ROW_GAP)
	column.minimum_size_changed.connect(_queue_layout)
	panel.add_child(column)
	_panels.append(panel)
	_columns.append(column)


## Shows the extra panels that have rows (count includes the window), side by side to the right of
## the window and level with it; a centred window moves left so they're centred together.
func _place_flow_panels(count: int, side: bool) -> void:
	var width := _window.size.x
	if not side and count > 1:
		_window.position.x = roundf((size.x - count * width - (count - 1) * GAP) / 2.0)
	for i in _panels.size():
		var panel := _panels[i]
		var show_it := i < count - 1
		if not show_it:
			panel.hide()
			continue
		panel.reset_size()
		panel.position = Vector2(_window.position.x + (i + 1) * (width + GAP), _window.position.y)
		if not panel.visible:
			panel.show()
			UITheme.pop_in(panel)