extends ModalWindow
## The Settings window (gear button): sound and display options. Each switch saves straight away
## through the Settings autoload, which remembers it between sessions.

## "Start over" was pressed; main asks "Are you sure?" before anything is thrown away.
signal new_game_requested

var _switches := {}  # setting key -> [Button, on text, off text]


func _ready() -> void:
	super()
	_heading("Sound")
	_switch("music", "music", "Music")
	_switch("sound", "sound", "Sound effects")
	_heading("Display")
	_switch("building_names", "names", "Building names")
	_switch("water_detail", "water", "Water detail", "High", "Low")
	if Settings.can_go_fullscreen():
		_switch("fullscreen", "screen", "Full screen")
	_heading("Game")
	var note := Label.new()
	note.theme_type_variation = "BodyLabel"
	note.text = "Your game saves by itself on this device."
	content.add_child(note)
	var restart := Button.new()
	restart.theme_type_variation = "RedButton"
	restart.text = "Start over"
	restart.custom_minimum_size = Vector2(200, 56)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.pressed.connect(new_game_requested.emit)
	content.add_child(restart)
	_heading("About")
	var about := Label.new()
	about.theme_type_variation = "BodyLabel"
	about.text = "Company Sim - early prototype. Settings are saved on this device.\nBuilding models: Kenney (kenney.nl), CC0"
	content.add_child(about)
	if Settings.can_go_fullscreen():  # computers only; phones leave apps their own way
		var quit := Button.new()
		quit.theme_type_variation = "RedButton"
		quit.text = "Quit game"
		quit.custom_minimum_size = Vector2(200, 56)
		quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		quit.pressed.connect(func(): get_tree().quit())
		content.add_child(quit)


func show_settings() -> void:
	for key in _switches:
		_show_switch(key)
	open("Settings")


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	content.add_child(label)


## One row: icon, name, and an On/Off button that flips the setting.
func _switch(key: String, icon_name: String, title: String, on_text := "On", off_text := "Off") -> void:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	content.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UITheme.icon(icon_name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon)
	var label := Label.new()
	label.theme_type_variation = "BodyLabel"
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(112, 46)
	button.pressed.connect(func():
		Settings.set_value(key, not Settings.get_value(key))
		_show_switch(key))
	row.add_child(button)
	_switches[key] = [button, on_text, off_text]
	_show_switch(key)


func _show_switch(key: String) -> void:
	var parts: Array = _switches[key]
	var on: bool = Settings.get_value(key)
	parts[0].text = parts[1] if on else parts[2]
	parts[0].theme_type_variation = "GreenButton" if on else "RedButton"
