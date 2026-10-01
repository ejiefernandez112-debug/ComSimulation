extends Control
## Placeholder scene: proves the pipeline works (project runs, autoloads load data).
## Will be replaced by the Village View.

func _ready() -> void:
	var label := Label.new()
	label.position = Vector2(40, 40)
	var lines: Array[String] = ["Pipeline check OK", "Clock: %d" % int(TimeService.now()), ""]
	for type_id in GameData.buildings:
		lines.append("- %s (cost %s)" % [GameData.buildings[type_id].name, GameData.buildings[type_id].build_cost])
	label.text = "\n".join(lines)
	add_child(label)
	print(label.text)
