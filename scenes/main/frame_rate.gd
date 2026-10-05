extends Node
## Decides how many pictures ("frames") per second the game draws, to save battery and keep
## phones cool without the game looking different (plan.md §9.1). Like other mobile games:
## - about 60 a second while the player is using the game (touching, dragging, typing, moving
##   the mouse),
## - 30 once nobody has touched it for IDLE_AFTER seconds: then only the water and small bobbing
##   things move, and they look the same at 30. Any touch brings it straight back.
## The Settings "Frame rate" choice changes this: Saver = 30 always, Max = as fast as the screen.
## Godot itself stops drawing while the game is minimised or in the background on a phone.
##
## "About 60": a screen shows a new picture at fixed moments (120 times a second on a 120 Hz
## phone). If the game's speed doesn't fit evenly into the screen's, some pictures stay up longer
## than others and movement looks jerky. So the speed is fitted to the screen: 60 on a 120 Hz
## phone, 55 on a 165 Hz laptop screen, 72 on a 144 Hz one; a 60 Hz screen just runs at 60.

const ACTIVE_FPS := {"saver": 30, "smooth": 60, "max": 0}  # 0 = no limit: the screen's own speed
const IDLE_FPS := 30
const IDLE_AFTER := 10.0  # seconds without any input before dropping to IDLE_FPS

var _last_input_ms := 0
var _idle := false


func _ready() -> void:
	_last_input_ms = Time.get_ticks_msec()
	# Every input reaches the window first, before any button or window can claim it.
	get_window().window_input.connect(_on_input)
	var check := Timer.new()
	check.wait_time = 0.5
	check.timeout.connect(_apply)
	add_child(check)
	check.start()
	Settings.changed.connect(_apply)
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_on_input(null)  # back in the game: full speed straight away


func _on_input(_event: InputEvent) -> void:
	_last_input_ms = Time.get_ticks_msec()
	if _idle:
		_apply()


## Sets the speed limit for right now.
func _apply() -> void:
	_idle = Time.get_ticks_msec() - _last_input_ms > IDLE_AFTER * 1000.0
	var choice: String = Settings.get_value("frame_rate")
	var target: int = ACTIVE_FPS.get(choice, ACTIVE_FPS.smooth)
	if _idle:
		target = IDLE_FPS
	var limit := fitted(target, DisplayServer.screen_get_refresh_rate(), DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED)
	if Engine.max_fps != limit:
		Engine.max_fps = limit


## The speed limit to set for `target` frames a second on a screen refreshing `refresh` times a
## second: the screen's speed divided by a whole number, as close to `target` as possible.
## 0 means "no limit": the screen itself then sets the pace (only when it waits for the screen,
## which is called V-Sync).
static func fitted(target: int, refresh: float, waits_for_screen: bool) -> int:
	if not waits_for_screen:
		return target  # nothing else would hold it back (0 stays "no limit")
	if target <= 0 or refresh <= 0.0:
		return target  # no limit wanted, or the screen's speed is unknown
	var every := maxi(1, floori(refresh / target + 0.25))  # show each picture for this many refreshes
	var limit := roundi(refresh / every)
	return 0 if limit >= roundi(refresh) else limit
