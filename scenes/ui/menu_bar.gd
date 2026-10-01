extends Control
## The main menu along the bottom centre of the screen, Tropico-style: a row of paper cards, each
## with an icon, clipped onto a blue folder with its name underneath. Pointing at a card lifts it.
## Cards for screens that aren't built yet are greyed with a lock ("coming soon").
## It steps aside (slides down) while something else is using the bottom of the screen, such as a
## building's action bar or Placement Mode. The cards only ask (signals); main.gd opens things.

signal tile_pressed(id: String)
signal coming_soon(title: String)

## The cards, left to right. "soon" = that screen isn't built yet.
const TILES := [
	{"id": "build", "title": "Build", "icon": "build"},
	{"id": "warehouse", "title": "Warehouse", "icon": "warehouse", "soon": true},
	{"id": "market", "title": "Market", "icon": "market", "soon": true},
	{"id": "stats", "title": "Stats", "icon": "stats"},
	{"id": "settings", "title": "Menu", "icon": "gear"},
]
const TILE_SIZE := Vector2(104, 124)
const CARD_SIZE := Vector2(88, 88)
const TILTS := [-3.0, 2.0, -2.0, 3.0]  # degrees: the cards look clipped on by hand
const MARGIN := 10.0
const DROP := 150.0  # how far the bar slides down to get out of the way

var _row: HBoxContainer
var _watched: Array[Control] = []
var _away := false
var _slide: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for i in TILES.size():
		_row.add_child(_make_tile(TILES[i], TILTS[i % TILTS.size()]))
	_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, MARGIN)
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN


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
		_row.show()
	_slide = create_tween().set_parallel()
	_slide.tween_method(_set_drop, _drop(), DROP if busy else 0.0, 0.18).set_trans(Tween.TRANS_QUAD)
	_slide.tween_property(_row, "modulate:a", 0.0 if busy else 1.0, 0.18)
	if busy:
		_slide.chain().tween_callback(_row.hide)  # hidden, so it can't be clicked while away


## How far the bar is slid down from its place (0 = in place).
func _drop() -> float:
	return _row.offset_bottom + MARGIN


func _set_drop(drop: float) -> void:
	_row.offset_bottom = -MARGIN + drop
	_row.offset_top = _row.offset_bottom - TILE_SIZE.y


## One tile: the blue folder, the tilted paper card with the icon, the name, and an invisible
## button over the lot that catches taps and the pointer.
func _make_tile(tile: Dictionary, tilt: float) -> Control:
	var soon: bool = tile.get("soon", false)
	var root := Control.new()
	root.custom_minimum_size = TILE_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := _picture(load(UITheme.SKINS + "menu_tile.svg"), TILE_SIZE)
	root.add_child(base)
	var card := Control.new()
	card.size = CARD_SIZE
	card.position = Vector2((TILE_SIZE.x - CARD_SIZE.x) / 2.0, 0)
	card.pivot_offset = CARD_SIZE / 2.0
	card.rotation_degrees = tilt
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	card.add_child(_picture(load(UITheme.SKINS + "menu_card.svg"), CARD_SIZE))
	var icon := _picture(UITheme.icon(tile.icon), Vector2(56, 56))
	icon.position = Vector2(14, 10)
	card.add_child(icon)
	var caption := Label.new()
	caption.text = tile.title
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	caption.position = Vector2(4, 90)
	caption.size = Vector2(TILE_SIZE.x - 8, 24)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(caption)
	if soon:
		card.modulate = Color(0.72, 0.72, 0.72)
		base.modulate = Color(0.75, 0.75, 0.8)
		var lock := _picture(UITheme.icon("lock"), Vector2(28, 28))
		lock.position = Vector2(56, 2)
		card.add_child(lock)

	var hit := Button.new()
	hit.flat = true
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.tooltip_text = "%s (coming soon)" % tile.title if soon else tile.title
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	root.add_child(hit)
	var rest := card.position
	hit.mouse_entered.connect(func(): _pose(card, rest + Vector2(0, -10), 0.0, 1.0))
	hit.mouse_exited.connect(func(): _pose(card, rest, tilt, 1.0))
	hit.button_down.connect(func(): _pose(card, card.position, card.rotation_degrees, 0.92))
	hit.button_up.connect(func(): _pose(card, card.position, card.rotation_degrees, 1.0))
	if soon:
		hit.pressed.connect(func(): coming_soon.emit(tile.title))
	else:
		hit.pressed.connect(func(): tile_pressed.emit(tile.id))
	return root


## Eases a card to a position, tilt and size (hover lifts and straightens it; a press squishes it).
func _pose(card: Control, at: Vector2, tilt: float, squish: float) -> void:
	if card.has_meta("tween"):
		card.get_meta("tween").kill()  # don't let an older move fight this one
	var tween := card.create_tween().set_parallel()
	card.set_meta("tween", tween)
	tween.tween_property(card, "position", at, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "rotation_degrees", tilt, 0.12)
	tween.tween_property(card, "scale", Vector2.ONE * squish, 0.08)


func _picture(texture: Texture2D, side: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size = side
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
