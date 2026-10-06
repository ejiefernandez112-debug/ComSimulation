extends SceneTree
## Saves the game's look (UITheme.build() in scenes/ui/ui_theme.gd) as a Godot theme file,
## assets/ui/game_theme.tres, so scenes made in the editor (like scenes/ui/settings_panel.tscn)
## show the real cream-and-honey style while you arrange them.
## Run it again after changing ui_theme.gd:
##   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tools/make_theme.gd

const OUT := "res://assets/ui/game_theme.tres"


func _initialize() -> void:
	# Loaded here, not named at the top: ui_theme.gd uses the game's autoloads, which only exist
	# once the game has started.
	var ui_theme: GDScript = load("res://scenes/ui/ui_theme.gd")
	var theme: Theme = ui_theme.build()
	# Godot's own fallback font is built in (it has no file), so it can't be saved; the game adds
	# it back when it builds the theme in code.
	for font: Font in [ui_theme.font(), ui_theme.bold_font()]:
		font.fallbacks = []
	var error := ResourceSaver.save(theme, OUT)
	print("Saved %s" % OUT if error == OK else "Could not save %s (error %d)" % [OUT, error])
	quit(0 if error == OK else 1)
