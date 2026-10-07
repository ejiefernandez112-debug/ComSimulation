extends Camera2D
## Clash-of-Clans-style camera: drag to pan, mouse wheel / pinch to zoom, no rotation. You can't
## zoom out further than the whole-island view, or pan the view past the island's edges.
## Double-tap toggles: from the whole-island view it zooms straight in to the closest zoom; when
## zoomed in at all, it zooms back out to the whole island.
## Tells the village when the player taps (presses and releases without dragging). Taps are
## reported straight away; the second tap of a double-tap only zooms.
## In Placement Mode (`placing`), one finger moves the building's ghost instead of the map: the
## camera only reports where that finger is (finger_* signals). Two fingers still pan and zoom;
## on PC, dragging with the middle mouse button pans.

signal tapped(world_pos: Vector2)
## Placement Mode, one finger: pressed / dragged at this world point.
signal finger_down(world_pos: Vector2)
signal finger_moved(world_pos: Vector2)
## Placement Mode: that finger turned out to be the start of a two-finger pan/zoom.
signal finger_cancelled

const DRAG_THRESHOLD := 8.0  # pixels the finger/mouse must move before a press counts as a drag
const ZOOM_MAX := 1.6  # closest zoom, the same for pinch, mouse wheel and double-tap
const ZOOM_STEP := 1.15
const FIT_MARGIN := 0.97  # whole-island view: the island fills the screen, with a sliver of sea around it
const DOUBLE_TAP_TIME := 0.3  # seconds after a tap in which a second tap makes it a double-tap
const DOUBLE_TAP_DIST := 60.0  # pixels: the second tap must land this close to the first
const ZOOM_GLIDE := 0.25  # seconds the double-tap zoom takes

## The island's rectangle (set by the village). The view never goes past it.
var bounds := Rect2()
## Placement Mode (set by the village): one finger moves the ghost, not the map.
var placing := false

var _pressed := false
var _dragging := false
var _press_pos := Vector2.ZERO
var _player_moved := false  # once the player drags or zooms, stop re-framing the island
var _zoom_min := 1.0  # furthest zoom-out = the whole-island view; depends on the window size
## Fingers on the screen right now (finger number -> screen position). Phones also turn the FIRST
## finger into fake mouse events, which handle one-finger pan and tap below; two fingers = pinch.
var _touches := {}
var _pinch_dist := 0.0  # distance between the two fingers at the last pinch step
var _pinch_mid := Vector2.ZERO  # point halfway between them at the last pinch step
## Double-tap: after each tap this timer runs; a press near that tap before it runs out is the
## second half of a double-tap.
var _tap_timer := Timer.new()
var _last_tap := Vector2.ZERO  # screen position of the last tap
var _second_press := false  # the second press of a double-tap is down
var _glide: Tween  # the double-tap zoom animation, while it runs


func _ready() -> void:
	get_viewport().size_changed.connect(_on_window_resized)
	_tap_timer.one_shot = true
	_tap_timer.wait_time = DOUBLE_TAP_TIME
	add_child(_tap_timer)


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
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_finger_moved(event)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = true
				_dragging = false
				_press_pos = event.position
				_stop_glide()
				if placing:
					finger_down.emit(_screen_to_world(event.position))
				else:
					_on_press(event.position)
			else:
				if _pressed and not _dragging and not placing:
					_on_tap(event.position)
				_pressed = false
				_dragging = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and not _window_open():
			_zoom_at(ZOOM_STEP, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and not _window_open():
			_zoom_at(1.0 / ZOOM_STEP, event.position)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:  # PC: middle-drag always pans
			_player_moved = true
			position -= event.relative / zoom
			_clamp()
		elif placing:
			if _pressed:
				finger_moved.emit(_screen_to_world(event.position))
		else:
			if _pressed and not _dragging and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				_dragging = true
				_player_moved = true
				_second_press = false  # tap, then drag: just a pan, not a double-tap
			if _dragging:
				position -= event.relative / zoom
				_clamp()
	elif event is InputEventMagnifyGesture and not _window_open():  # pinch on PC trackpads (phones: below)
		_zoom_at(event.factor, event.position)


## Whether a window is open (Statistics, a building's window, Settings..., the Build panel or the
## building card at the bottom): the mouse wheel, a trackpad pinch or two fingers then don't zoom
## or move the map behind it. (Placing a building closes the Build panel, so zooming works again.)
func _window_open() -> bool:
	for window in get_tree().get_nodes_in_group("modal_windows"):
		if window.visible:
			return true
	return false


## A finger went down or came up. When a second finger lands, a pinch starts: the first finger's
## press is forgotten, so it neither pans the map nor counts as a tap when it lifts.
func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if event.index == 0:
			_touches.clear()  # a new first finger: forget fingers whose lift a button swallowed
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	if _touches.size() >= 2:
		if placing and _pressed:
			finger_cancelled.emit()  # the first finger was the start of a pinch, not a ghost drag
		_pressed = false
		_dragging = false
		_second_press = false  # a pinch is never a tap
		_tap_timer.stop()
		_stop_glide()
		_start_pinch_step()


## While two fingers are down: zoom by how much they spread apart or squeeze together, and pan
## by how far the point between them slid, so the map stays under the fingers.
func _on_finger_moved(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() < 2 or _window_open():
		return
	var fingers: Array = _touches.values()
	var dist: float = fingers[0].distance_to(fingers[1])
	var mid: Vector2 = (fingers[0] + fingers[1]) / 2.0
	if _pinch_dist > 0.0 and dist > 0.0:
		_zoom_at(dist / _pinch_dist, mid)
	position -= (mid - _pinch_mid) / zoom
	_clamp()
	_pinch_dist = dist
	_pinch_mid = mid


## Remembers where the two fingers are now, as the starting point for the next pinch step.
func _start_pinch_step() -> void:
	var fingers: Array = _touches.values()
	_pinch_dist = fingers[0].distance_to(fingers[1])
	_pinch_mid = (fingers[0] + fingers[1]) / 2.0


## A press soon after a tap, close to it, is the second half of a double-tap.
func _on_press(screen_pos: Vector2) -> void:
	_second_press = not _tap_timer.is_stopped() and screen_pos.distance_to(_last_tap) <= DOUBLE_TAP_DIST
	_tap_timer.stop()


## A press and release without dragging. A normal tap is reported straight away (so buildings
## select instantly); the second tap of a double-tap only zooms.
func _on_tap(screen_pos: Vector2) -> void:
	if _second_press:
		_second_press = false
		_double_tap_zoom(screen_pos)
		return
	tapped.emit(_screen_to_world(screen_pos))
	_last_tap = screen_pos
	_tap_timer.start()


## Zoomed in at all (by pinch or double-tap): glide out to the whole island. At the whole-island
## view: glide straight in to the closest zoom, on the tapped spot.
func _double_tap_zoom(screen_pos: Vector2) -> void:
	var target := _zoom_min if zoom.x > _zoom_min + 0.01 else ZOOM_MAX
	_stop_glide()
	_glide = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_glide.tween_method(func(level: float): _zoom_at(level / zoom.x, screen_pos), zoom.x, target, ZOOM_GLIDE)


## Touching the screen stops a running zoom glide, so the map never fights the player's finger.
func _stop_glide() -> void:
	if _glide and _glide.is_valid():
		_glide.kill()


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
