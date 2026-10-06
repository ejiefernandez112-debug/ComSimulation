extends Control
## The main menu: a dark glass toolbar along the bottom centre of the screen, one button per screen
## (an icon with its name under it). Buttons for screens that aren't built yet are dimmed and carry
## a small lock ("coming soon").
## It steps aside (slides down) while something else is using the bottom of the screen or the map,
## such as a building's card, Placement Mode or a window. The buttons only ask (signals); main.gd
## opens things.

signal tile_pressed(id: String)
signal coming_soon(title: String)

## The buttons, left to right. "soon" = that screen isn't built yet.
const TILES := [
	{"id": "build", "title": "Build", "icon": "build"},
	{"id": "warehouse", "title": "Warehouse", "icon": "warehouse"},
	{"id": "market", "title": "Market", "icon": "market", "soon": true},
	{"id": "stats", "title": "Stats", "icon": "stats"},
	{"id": "settings", "title": "Menu", "icon": "gear"},
]
const TILE_HEIGHT := 62.0
const MARGIN := 12.0
const DROP := 110.0  # how far the bar slides down to get out of the way

var _bar: PanelContainer
var _watched: Array[Control] = []
var _away := false
var _slide: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = PanelContainer.new()
	_bar.theme_type_variation = "HudBar"
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_bar.add_child(row)
	for tile in TILES:
		row.add_child(_make_tile(tile))
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN


## The bar gets out of the way whenever any of these is showing (and comes back after).
func hide_while_visible(controls: Array) -> void:
	for control: Control in controls:
		_watched.append(control)
		control.visibility_changed.connect(_update)
	_update()


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
		_bar.show()
	_slide = create_tween().set_parallel()
	_slide.tween_method(_set_drop, _drop(), DROP if busy else 0.0, 0.18).set_trans(Tween.TRANS_QUAD)
	_slide.tween_property(_bar, "modulate:a", 0.0 if busy else 1.0, 0.18)
	if busy:
		_slide.chain().tween_callback(_bar.hide)  # hidden, so it can't be clicked while away


## How far the bar is slid down from its place (0 = in place).
func _drop() -> float:
	return _bar.offset_bottom + MARGIN


func _set_drop(drop: float) -> void:
	var height := _bar.offset_bottom - _bar.offset_top
	_bar.offset_bottom = -MARGIN + drop
	_bar.offset_top = _bar.offset_bottom - height


## One button: a plain tile (no box until pointed at) with the icon and the screen's name.
func _make_tile(tile: Dictionary) -> Control:
	var soon: bool = tile.get("soon", false)
	var b := RoundButton.make("IconButton", tile.icon, tile.title, TILE_HEIGHT)
	b.button.tooltip_text = "%s (coming soon)" % tile.title if soon else tile.title
	if soon:
		b.modulate.a = 0.5
		var lock := UITheme.icon_rect("lock", 16)
		lock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lock.offset_left = -22
		lock.offset_right = -6
		lock.offset_top = 6
		lock.offset_bottom = 22
		b.button.add_child(lock)
		b.pressed.connect(func(): coming_soon.emit(tile.title))
	else:
		b.pressed.connect(func(): tile_pressed.emit(tile.id))
	return b
