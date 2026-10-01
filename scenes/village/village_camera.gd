extends Camera2D
## Clash-of-Clans-style camera: drag to pan, mouse wheel / pinch to zoom, no rotation.
## Also tells the village where the pointer is, and when the player taps (presses and
## releases without dragging).

signal tapped(world_pos: Vector2)
signal hovered(world_pos: Vector2)

const DRAG_THRESHOLD := 8.0  # pixels the finger/mouse must move before a press counts as a drag
const ZOOM_MIN := 0.35
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.15

## World area the camera centre may move within (set by the village).
var bounds := Rect2()

var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO


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
		if _dragging:
			position -= event.relative / zoom
			_clamp()
		hovered.emit(_screen_to_world(event.position))
	elif event is InputEventMagnifyGesture:  # pinch on touchscreens / trackpads
		_zoom_at(event.factor, event.position)


## Zooms while keeping the point under the cursor (or between the fingers) in place.
func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var under := _screen_to_world(screen_pos)
	var new_zoom := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(new_zoom, new_zoom)
	position = under - (screen_pos - get_viewport_rect().size / 2.0) / zoom
	_clamp()


func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return position + (screen_pos - get_viewport_rect().size / 2.0) / zoom


func _clamp() -> void:
	position = position.clamp(bounds.position, bounds.end)
