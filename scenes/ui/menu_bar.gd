extends Control
## The always-on buttons, in thin frosted glass strips (plan.md §6 "UI look", the Harbor Glass
## mockup):
## - top-left: the screens (Menu, Statistics, Warehouse, Market), small icon buttons,
## - bottom centre: the build toolbar, one button per Build Menu category (data/build_menu.json).
##   Picking one opens its buildings in the Build panel just above it, and that button turns blue.
## The build toolbar steps aside (slides down) while something else is using the bottom of the
## screen or the map: a building's card, a window, Road or Move mode. The buttons only ask
## (signals); main.gd opens things.

signal tile_pressed(id: String)  # a screen button: "settings", "stats", "warehouse"
signal category_pressed(tab_id: String)  # a build toolbar button (a tab id from build_menu.json)
signal coming_soon(title: String)

## The screen buttons, left to right. "soon" = that screen isn't built yet; "divider" = a thin line
## after it.
const SCREENS := [
	{"id": "settings", "title": "Menu", "icon": "menu", "divider": true},
	{"id": "stats", "title": "Statistics", "icon": "stats"},
	{"id": "warehouse", "title": "Warehouse", "icon": "warehouse"},
	{"id": "market", "title": "Market", "icon": "market", "soon": true},
]
const MARGIN := 12.0  # space between the strips and the screen's edges
const DROP := 110.0  # how far the toolbar slides down to get out of the way
## From the screen's bottom edge to just above the build toolbar: the Build panel sits here.
const TOOLBAR_SPACE := 94.0

var _toolbar: PanelContainer
var _tools := {}  # tab id -> its RoundButton
var _open := ""  # the category whose buildings the Build panel shows ("" = closed)
var _watched: Array[Control] = []
var _away := false
var _slide: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_screen_strip()
	_make_toolbar()


## The Build panel opened this category ("" = it closed): its button shows blue.
func set_open(tab_id: String) -> void:
	_open = tab_id
	for id in _tools:
		_tools[id].set_style("GoButton" if id == tab_id else "IconButton")


## The toolbar gets out of the way whenever any of these is showing (and comes back after).
func hide_while_visible(controls: Array) -> void:
	for control: Control in controls:
		_watched.append(control)
		control.visibility_changed.connect(_update)
	_update()


func _make_screen_strip() -> void:
	var strip := PanelContainer.new()
	strip.theme_type_variation = "HudBar"
	UITheme.frost(strip)
	add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	strip.add_child(row)
	for screen: Dictionary in SCREENS:
		row.add_child(_make_screen_button(screen))
		if screen.get("divider", false):
			row.add_child(UITheme.divider(true, 22))
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(MARGIN))


func _make_screen_button(screen: Dictionary) -> Control:
	var soon: bool = screen.get("soon", false)
	var b := RoundButton.make("IconButton", screen.icon, "", UITheme.SCREEN_BUTTON)
	b.button.tooltip_text = "%s (coming soon)" % screen.title if soon else screen.title
	if soon:
		b.modulate.a = 0.45
		b.pressed.connect(func(): coming_soon.emit(screen.title))
	else:
		b.pressed.connect(func(): tile_pressed.emit(screen.id))
	return b


func _make_toolbar() -> void:
	_toolbar = PanelContainer.new()
	_toolbar.theme_type_variation = "HudBar"
	UITheme.frost(_toolbar)
	add_child(_toolbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_toolbar.add_child(row)
	for tab in BuildingInfo.menu_tabs():
		if tab.get("divider_before", false) and row.get_child_count() > 0:
			row.add_child(UITheme.divider(true, 34))
		var b := RoundButton.make("IconButton", str(tab.icon), str(tab.name), UITheme.TOOLBAR_BUTTON)
		b.button.tooltip_text = str(tab.get("about", tab.name))
		b.pressed.connect(func(): category_pressed.emit(str(tab.id)))
		row.add_child(b)
		_tools[str(tab.id)] = b
	_toolbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_toolbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toolbar.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _update() -> void:
	var busy := false
	for control in _watched:
		busy = busy or control.visible
	if busy == _away:
		return
	_away = busy
	if _slide:
		_slide.kill()
	if not busy:
		_toolbar.show()
	_slide = create_tween().set_parallel()
	_slide.tween_method(_set_drop, _drop(), DROP if busy else 0.0, 0.18).set_trans(Tween.TRANS_QUAD)
	_slide.tween_property(_toolbar, "modulate:a", 0.0 if busy else 1.0, 0.18)
	if busy:
		_slide.chain().tween_callback(_toolbar.hide)  # hidden, so it can't be clicked while away


## How far the toolbar is slid down from its place (0 = in place).
func _drop() -> float:
	return _toolbar.offset_bottom + MARGIN


func _set_drop(drop: float) -> void:
	var height := _toolbar.offset_bottom - _toolbar.offset_top
	_toolbar.offset_bottom = -MARGIN + drop
	_toolbar.offset_top = _toolbar.offset_bottom - height
