extends ModalWindow
## The Settings window (gear button): sound and display options. Each switch saves straight away
## through the Settings autoload, which remembers it between sessions.
## Laid out in the Godot editor: open scenes/ui/settings_panel.tscn to move, add or restyle rows.
## This script only connects the buttons, found by their unique names (the % in the scene tree).

## "Start over" was pressed; main asks "Are you sure?" before anything is thrown away.
signal new_game_requested

## Setting key -> [its button's unique name, text when on, text when off].
const SWITCHES := {
	"music": ["MusicButton", "On", "Off"],
	"sound": ["SoundButton", "On", "Off"],
	"building_names": ["NamesButton", "On", "Off"],
	"water_detail": ["WaterButton", "High", "Low"],
	"fullscreen": ["FullscreenButton", "On", "Off"],
}


func _ready() -> void:
	super()
	for key in SWITCHES:
		var button: Button = get_node("%" + SWITCHES[key][0])
		button.pressed.connect(func():
			Settings.set_value(key, not Settings.get_value(key))
			_show_switch(key))
	# Full screen and Quit only make sense on a computer; phones leave apps their own way.
	%FullscreenRow.visible = Settings.can_go_fullscreen()
	%QuitButton.visible = Settings.can_go_fullscreen()
	%StartOverButton.pressed.connect(new_game_requested.emit)
	%QuitButton.pressed.connect(func(): get_tree().quit())


func show_settings() -> void:
	for key in SWITCHES:
		_show_switch(key)
	open("Settings")


## On: a honey chip with the "on" text; off: a cream chip with the "off" text.
func _show_switch(key: String) -> void:
	var button: Button = get_node("%" + SWITCHES[key][0])
	var on: bool = Settings.get_value(key)
	button.text = SWITCHES[key][1] if on else SWITCHES[key][2]
	button.theme_type_variation = "ChipOnButton" if on else "ChipButton"
