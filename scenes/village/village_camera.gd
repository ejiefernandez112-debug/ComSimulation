extends Camera2D
## Clash-of-Clans-style camera: drag to pan, mouse wheel / pinch to zoom, no rotation. You can't
## zoom out further than the whole-island view, or pan the view past the island's edges.
## Also tells the village where the pointer is, and when the player taps (presses and
## releases without dragging).

signal tapped(world_pos: Vector2)
signal hovered(world_pos: Vector2)

const DRAG_THRESHOLD := 8.0  # pixels the finger/mouse must move before a press counts as a drag
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.15
const FIT_MARGIN := 0.97  # whole-island view: the island fills the screen, with a sliver of sea around it

## The island's rectangle (set by the village). The view never goes past it.
var bounds := Rect2()

var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _player_moved := false  # once the player drags or zooms, stop re-framing the island
var _zoom_min := 1.0  # furthest zoom-out = the whole-island view; depends on the window size


func _ready() -> void:
	get_viewport().size_changed.connect(_on_window_resized)


## Zooms out to the whole-island view (as large as the screen allows), centred.
func show_whole_island() -> void:
	_zoom_min = _whole_island_zoom()
	zoom = Vector2(_zoom_min, _zoom_min)
	position = bounds.get_center()


## The window can change size just after start-up (the editor's game panel, a phone settling its
## screen) or later (resizing, rotating). Until the player takes over, re-frame the island; after
## that, just make sure the new window can't zoom out past the island.
func _on_window_resized() -> void:
	if not _player_moved:
		show_whole_island()
		return
	_zoom_min = _whole_island_zoom()
	if zoom.x < _zoom_min:
		zoom = Vector2(_zoom_min, _zoom_min)
	_clamp()


func _whole_island_zoom() -> float:
	if bounds.size == Vector2.ZERO:
		return 1.0  # the village hasn't said where the island is yet
	var fit := get_viewport_rect().size / bounds.size
	return minf(minf(fit.x, fit.y) * FIT_MARGIN, ZOOM_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_dragging = false
				_press_pos = event.position
			else:
				if _pressed and not _dragging:
					tapped.emit(_screen_to_world(event.position))
				_pressed = false
				_dragging = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(ZOOM_STEP, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / ZOOM_STEP, event.position)
	elif event is InputEventMouseMotion:
		if _pressed and not _dragging and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
			_player_moved = true
		if _dragging:
			position -= event.relative / zoom
			_clamp()
		hovered.emit(_screen_to_world(event.position))
	elif event is InputEventMagnifyGesture:  # pinch on touchscreens / trackpads
		_zoom_at(event.factor, event.position)


## Zooms while keeping the point under the cursor (or between the fingers) in place.
func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	_player_moved = true
	var under := _screen_to_world(screen_pos)
	var new_zoom := clampf(zoom.x * factor, _zoom_min, ZOOM_MAX)
	zoom = Vector2(new_zoom, new_zoom)
	position = under - (screen_pos - get_viewport_rect().size / 2.0) / zoom
	_clamp()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size / 2.0) / zoom


## Keeps the view inside the island's rectangle. Where the view is wider (or taller) than the
## island, as in the whole-island view, it stays centred that way instead.
func _clamp() -> void:
	var half_view := get_viewport_rect().size / zoom / 2.0
	var lo := bounds.position + half_view
	var hi := bounds.end - half_view
	position.x = clampf(position.x, lo.x, hi.x) if lo.x <= hi.x else bounds.get_center().x
	position.y = clampf(position.y, lo.y, hi.y) if lo.y <= hi.y else bounds.get_center().y
