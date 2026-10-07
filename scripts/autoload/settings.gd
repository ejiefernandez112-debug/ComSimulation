extends Node
## Player preferences (sound, display). Kept in their own small JSON file in user://, apart from
## the game save, so restarting a game never resets them. The Settings panel changes them through
## set_value(); anything that cares (the map, audio, the window) reacts to `changed`.

signal changed

const PATH := "user://settings.json"
const VERSION := 1
const DEFAULTS := {
	"music": true,
	"sound": true,
	"building_names": false,
	"water_detail": true,
	"fullscreen": false,
	"glass_blur": true,  # frosted glass windows (blur the map behind them); off on phones, see _ready
}

var _values := DEFAULTS.duplicate()


func _ready() -> void:
	# Blurring what's behind every panel costs some speed and battery, so phones start without it.
	if OS.has_feature("mobile"):
		_values["glass_blur"] = false
	# Sound buses that music and effects will play through once the game has audio.
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_load()
	_apply()


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	_values[key] = value
	_save()
	_apply()
	changed.emit()


## Fullscreen only makes sense on a computer; phones are always full screen.
func can_go_fullscreen() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")


func _apply() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not get_value("music"))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not get_value("sound"))
	if can_go_fullscreen():
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return  # damaged file: keep the defaults
	for key in DEFAULTS:
		if parsed.has(key) and typeof(parsed[key]) == typeof(DEFAULTS[key]):
			_values[key] = parsed[key]


func _save() -> void:
	var data := _values.duplicate()
	data["settings_version"] = VERSION
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
