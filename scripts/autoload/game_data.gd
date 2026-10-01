extends Node
## Loads all game content from data/*.json (plan.md §3.1 rule 1).
## Read-only at runtime: simulation code looks numbers up here, never hard-codes them.

var resources: Dictionary = {}
var buildings: Dictionary = {}
var config: Dictionary = {}


func _ready() -> void:
	resources = load_json("res://data/resources.json")
	buildings = load_json("res://data/buildings.json")
	config = load_json("res://data/game_config.json")
	print("GameData loaded: %d resources, %d buildings" % [resources.size(), buildings.size()])


func get_building(type_id: String) -> Dictionary:
	return buildings.get(type_id, {})


func get_resource(resource_id: String) -> Dictionary:
	return resources.get(resource_id, {})


## Static so tests can load the real data files without the autoload running.
static func load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("GameData: could not read %s" % path)
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: %s is not a valid JSON object" % path)
		return {}
	# Keys starting with "_" are comments for humans, not content.
	for key in parsed.keys():
		if String(key).begins_with("_"):
			parsed.erase(key)
	return parsed
