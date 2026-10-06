extends Node
## Loads all game content from data/*.json (plan.md §3.1 rule 1).
## Read-only at runtime: simulation code looks numbers up here, never hard-codes them. The one
## exception is the Developer window's tuning (apply_dev_config), which changes `config` in memory
## only; the files are never written.

const Simulation = preload("res://scripts/sim/simulation.gd")

var resources: Dictionary = {}
var buildings: Dictionary = {}
var config: Dictionary = {}
var build_menu: Dictionary = {}  # {"tabs": [{id, name, icon}]}
var _file_config: Dictionary = {}  # game_config.json as in the file, to undo developer tuning


func _ready() -> void:
	resources = load_json("res://data/resources.json")
	buildings = load_json("res://data/buildings.json")
	config = load_json("res://data/game_config.json")
	_file_config = config.duplicate(true)
	build_menu = load_json("res://data/build_menu.json")
	print("GameData loaded: %d resources, %d buildings" % [resources.size(), buildings.size()])


## Developer tuning: `config` becomes game_config.json's numbers with these changes on top
## ({path: value}, see Simulation.dev_set_config); {} puts the file's numbers back.
func apply_dev_config(overrides: Dictionary) -> void:
	Simulation.apply_config_overrides(config, _file_config, overrides)


## A game_config.json value by its path ("happiness.growth_speeds.2.speed"), with any developer
## tuning, or null.
func config_value(path: String) -> Variant:
	return Simulation.config_value(config, path)


## A game_config.json number as it is in the file (before any developer tuning), or null.
func file_config_value(path: String) -> Variant:
	return Simulation.config_value(_file_config, path)


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
