extends SceneTree
## Quick health check of the whole project, not just the game rules. Three parts:
##   1. Scripts: every .gd file compiles. The rule tests only load scripts/sim/, so a typo in a
##      screen's script would otherwise only show up when that screen opens.
##   2. Data: data/*.json is complete and consistent (every recipe's goods exist, every building
##      can actually produce, the starting kit fits on the plot, ...). The rule tests use their
##      own test data, so a mistake in the real data would slip past them.
##   3. Architecture rules from CLAUDE.md that a text search can check: one clock, a pure
##      simulation, no Resource files as saves, debug tools only in debug builds, screens that
##      don't change the game state behind Economy's back.
##   4. Performance rules from CLAUDE.md (plan.md §9.1.1): patterns that made the game slow once
##      (see _check_performance). A line that really needs one says why with "# perf-ok: ...".
## Run (from the project folder):
##   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/check_project.gd
## Exit code 0 = no problems. NOTE lines are worth a look but don't fail the check.

const Simulation = preload("res://scripts/sim/simulation.gd")
const GameDataScript = preload("res://scripts/autoload/game_data.gd")

## Folders that aren't the game's own code: Godot's cache, exports, and the 3D art sources.
## Folders with a .gdignore file are skipped too.
const SKIP_DIRS := [".godot", ".git", ".claude", "build", "art", "Sprites kit"]
const CATEGORIES := ["civic", "residential", "storage", "utility", "construction", "power", "extractor", "processor", "retail", "trade", "service"]
## Every setting buildings.json / resources.json / game_config.json may use. Anything else is
## reported as a NOTE: usually a typo the game would silently ignore ("storage_capp"), or a new
## setting, which then belongs in these lists.
const BUILDING_KEYS := ["name", "category", "description", "menu_tab", "build_cost", "buildable",
	"build_time", "max_workers", "worker_type", "fixed_workers", "staffed_first", "fixed_wage",
	"households", "housing_tier", "housing_quality", "hut", "wealth", "rent_per_household", "power_mw",
	"service_need", "service_capacity", "service_quality",
	"capacity", "water_per_hour", "water_supply", "recipes", "shelves", "upgrades", "materials", "crew", "road_hub",
	"construction_crew", "power_supply", "power_radius", "grid_mw", "coming_soon", "sells", "switch_fee", "max_count", "size", "suspendable"]
## What a level in "upgrades" may change (plus an optional fixed "cost" and own "time"), and the
## least each may be.
const UPGRADE_STATS := {"max_workers": 0, "capacity": 1, "shelves": 1, "households": 1, "water_supply": 1, "power_supply": 1, "power_radius": 1, "service_capacity": 1}
const RECIPE_KEYS := ["id", "inputs", "outputs", "duration", "cost_share"]
const RESOURCE_KEYS := ["name", "tier", "appetite", "price", "category", "unit"]
const CONFIG_KEYS := ["starting_cash", "starting_population", "population_growth_seconds", "move_in_group_size", "move_in_only_for_jobs", "move_in_needs_home", "life", "housing", "happiness", "grid_size", "autosave_seconds",
	"welcome_back_after_seconds", "cancel_refund_in_progress", "batch",
	"stats_sample_seconds", "stats_history_size", "money_log_minutes", "money_log_size", "pricing", "water", "sales_tax_window_hours",
	"sales_tax_brackets", "market_fee", "retail", "staffing_levels", "default_staffing", "wage_bonuses",
	"bonus_output", "default_bonus", "worker_types", "island", "starting_buildings", "construction", "roads", "power",
	"item_categories", "trade"]
## Every setting a sound in data/sounds.json may use, and the buses it may play on (plan.md §5.24).
const SOUND_KEYS := ["file", "bus", "volume_db", "pitch_jitter", "min_gap", "when"]
const SOUND_BUSES := ["UI", "Alerts"]
## A production recipe is one hour of work: the batch length the player picks is counted in them.
const BATCH_HOUR := 3600.0

var _fails: Array[String] = []
var _notes: Array[String] = []
var _errors := _ErrorCounter.new()


## Counts Godot's error messages (same idea as in test_simulation.gd), so a script that fails to
## compile or a JSON file that fails to parse is noticed even if Godot carries on.
class _ErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


func _initialize() -> void:
	Engine.set_meta("running_tests", true)  # keeps Economy away from the player's real save
	OS.add_logger(_errors)
	var scripts := _find_files("res://", ".gd")
	print("1. Scripts (%d files)" % scripts.size())
	_check_scripts(scripts)
	print("2. Data (data/*.json)")
	_check_data()
	print("3. Architecture rules (CLAUDE.md)")
	_check_rules(scripts)
	print("4. Performance rules (CLAUDE.md)")
	_check_performance(scripts)
	OS.remove_logger(_errors)
	print("")
	for note in _notes:
		print("NOTE: ", note)
	for fail in _fails:
		print("FAIL: ", fail)
	print("\n%d problems, %d notes" % [_fails.size(), _notes.size()])
	quit(1 if _fails.size() > 0 else 0)


func _fail(message: String) -> void:
	_fails.append(message)


func _note(message: String) -> void:
	_notes.append(message)


# --- 1. Scripts ------------------------------------------------------------------

func _check_scripts(paths: Array[String]) -> void:
	for path in paths:
		var errors_before := _errors.count
		var script := load(path) as Script
		if script == null or not script.can_instantiate() or _errors.count > errors_before:
			_fail("%s doesn't compile (see the error above)" % path)


# --- 2. Data ---------------------------------------------------------------------

func _check_data() -> void:
	var errors_before := _errors.count
	var data := {
		"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json"),
	}
	var menu := GameDataScript.load_json("res://data/build_menu.json")
	if _errors.count > errors_before:
		_fail("a data file couldn't be read (see the error above)")
	for part in data:
		if data[part].is_empty():
			_fail("data for '%s' is empty" % part)
			return
	var tabs := {}
	for tab in menu.get("tabs", []):
		if tabs.has(tab.get("id", "")):
			_fail("build_menu.json: tab '%s' is listed twice" % tab.get("id", ""))
		tabs[tab.get("id", "")] = true
		_icon_exists(str(tab.get("icon", "")), "build_menu.json tab '%s'" % tab.get("id", ""))
		_unknown_keys(tab, ["id", "name", "icon", "color", "about", "divider_before"], "build_menu.json tab '%s'" % tab.get("id", ""))
		if tab.has("color") and not Color.html_is_valid(str(tab.color)):
			_fail("build_menu.json: tab '%s' color '%s' isn't a colour like \"#d9b23a\"" % [tab.get("id", ""), tab.color])
	_check_buildings(data, tabs)
	_check_resources(data)
	_check_config(data)
	_check_look()
	_check_sounds(GameDataScript.load_json("res://data/sounds.json"))


## data/ui_look.json (the look, read by scenes/ui/ui_theme.gd): every setting UITheme.LOOK_KEYS
## lists is there, colours are colours, sizes are numbers, and swapped icons exist.
func _check_look() -> void:
	var look := GameDataScript.load_json("res://data/ui_look.json")
	var keys: Dictionary = load("res://scenes/ui/ui_theme.gd").LOOK_KEYS
	_unknown_keys(look, keys.keys() + ["icons"], "ui_look.json")
	for section in keys:
		var values: Dictionary = look.get(section, {})
		_unknown_keys(values, keys[section], "ui_look.json %s" % section)
		for key in keys[section]:
			if not values.has(key):
				_fail("ui_look.json: %s.%s is missing" % [section, key])
			elif section == "colors" and not Color.html_is_valid(str(values[key])):
				_fail("ui_look.json: colors.%s '%s' isn't a colour like \"#2f9cf0\"" % [key, values[key]])
			elif section != "colors" and not (values[key] is float and float(values[key]) >= 0.0):
				_fail("ui_look.json: %s.%s should be a number of pixels" % [section, key])
	var icons: Dictionary = look.get("icons", {})
	for name in icons:
		_icon_exists(str(name), "ui_look.json icons")
		if not FileAccess.file_exists("res://assets/ui/icons/%s.svg" % icons[name]):
			_fail("ui_look.json icons: '%s' is drawn as '%s', but there is no assets/ui/icons/%s.svg" % [name, icons[name], icons[name]])


func _check_buildings(data: Dictionary, tabs: Dictionary) -> void:
	var config: Dictionary = data.config
	for id in data.buildings:
		var def: Dictionary = data.buildings[id]
		var where := "buildings.json '%s'" % id
		_unknown_keys(def, BUILDING_KEYS, where)
		var category := str(def.get("category", ""))
		if category not in CATEGORIES:
			_fail("%s: unknown category '%s' (the rules would ignore it)" % [where, category])
		if str(def.get("name", "")) == "":
			_fail("%s: has no name" % where)
		_number_at_least(def, "build_cost", 0.0, where, false)
		_number_at_least(def, "build_time", 0.0, where, false)
		_check_materials(data, def, where)
		_whole_at_least(def, "max_workers", 0, where, false)
		_whole_at_least(def, "max_count", 1, where, false)
		_whole_at_least(def, "size", 1, where, false)
		if def.has("menu_tab") and not tabs.has(def.menu_tab):
			_fail("%s: menu_tab '%s' isn't a tab in build_menu.json" % [where, def.menu_tab])
		if def.get("buildable", false) and not def.has("menu_tab"):
			_note("%s: can be built but has no menu_tab, so it's not in the Build Menu" % where)
		if int(def.get("max_workers", 0)) > 0:
			var worker_type := str(def.get("worker_type", "low_skilled"))
			if not config.get("worker_types", {}).has(worker_type):
				_fail("%s: worker_type '%s' isn't in game_config.json worker_types" % [where, worker_type])
		match category:
			"residential":
				_check_home(config, def, where)
			"storage":
				_whole_at_least(def, "capacity", 1, where, true)
			"retail":
				_whole_at_least(def, "shelves", 1, where, true)
				# What it sells: categories from game_config.json item_categories.
				if typeof(def.get("sells", [])) != TYPE_ARRAY:
					_fail("%s: 'sells' must be a list of item categories" % where)
				else:
					for kind in def.get("sells", []):
						if not config.get("item_categories", {}).has(kind):
							_fail("%s sells: '%s' isn't in game_config.json item_categories" % [where, kind])
			"utility":
				_whole_at_least(def, "water_supply", 1, where, true)
			"service":
				_check_service(config, def, where)
			"construction":
				_check_crew_office(data, id, def, where)
			"power":
				_number_at_least(def, "power_radius", 1.0, where, true)
				_number_at_least(def, "power_supply", 0.0, where, false)
			"extractor", "processor":
				_check_producer(data, id, def, where)
		_number_at_least(def, "power_mw", 0.0, where, false)
		_number_at_least(def, "grid_mw", 0.0, where, false)
		if def.has("coming_soon") and (def.get("buildable", false) or str(def.coming_soon) == ""):
			_fail("%s: coming_soon needs buildable false and a reason to show" % where)
		_check_upgrades(def, where)
		if not FileAccess.file_exists("res://assets/buildings/%s.png" % id):
			_note("%s: no sprite in assets/buildings/ yet (it shows as a placeholder)" % where)


## data/sounds.json: each sound's file exists and its settings make sense, and every
## Sfx.play("...") in the scripts names a sound that exists (an unknown one would just stay silent).
func _check_sounds(data: Dictionary) -> void:
	var sounds: Dictionary = data.get("sounds", {})
	if sounds.is_empty():
		_fail("sounds.json: no sounds")
		return
	for id in sounds:
		var def: Dictionary = sounds[id]
		var where := "sounds.json '%s'" % id
		_unknown_keys(def, SOUND_KEYS, where)
		if not FileAccess.file_exists("res://assets/audio/sfx/%s" % def.get("file", "")):
			_fail("%s: no file assets/audio/sfx/%s" % [where, def.get("file", "")])
		if str(def.get("bus", "")) not in SOUND_BUSES:
			_fail("%s: bus '%s' isn't one of %s" % [where, def.get("bus", ""), SOUND_BUSES])
		_number_at_least(def, "min_gap", 0.0, where, true)
		_number_at_least(def, "pitch_jitter", 0.0, where, true)
		if _is_number(def.get("pitch_jitter")) and def.pitch_jitter > 0.5:
			_fail("%s: pitch_jitter %s is too much (0.5 = half or one and a half times the pitch)" % [where, def.pitch_jitter])
		if not _is_number(def.get("volume_db")):
			_fail("%s: 'volume_db' is missing or not a number" % where)
	var played := RegEx.create_from_string("Sfx\\.play\\(\"(\\w+)\"\\)")
	for path in _find_files("res://", ".gd"):
		for found in played.search_all(FileAccess.get_file_as_string(path)):
			if not sounds.has(found.get_string(1)):
				_fail("%s plays sound '%s', which isn't in sounds.json" % [path.trim_prefix("res://"), found.get_string(1)])


## What building it needs (plan.md §5.15): building materials (resources.json items of category
## building_material) in whole amounts, and a crew. A building you can build needs materials (or,
## like the test data, a fixed build_cost).
func _check_materials(data: Dictionary, def: Dictionary, where: String) -> void:
	_whole_at_least(def, "crew", 0, where, false)
	if def.get("buildable", false) and not def.has("materials") and not def.has("build_cost"):
		_fail("%s: can be built but has no materials (and no build_cost), so it would be free" % where)
	if not def.has("materials"):
		return
	if typeof(def.materials) != TYPE_DICTIONARY:
		_fail("%s: 'materials' must be a list of amounts" % where)
		return
	for m in def.materials:
		if not Simulation.is_building_material(data, m):
			_fail("%s materials: '%s' isn't a resources.json item of category building_material" % [where, m])
		elif float(data.resources[m].get("price", 0.0)) <= 0.0:
			_fail("%s materials: '%s' needs a base price in resources.json (the supplier's price)" % [where, m])
		_whole_at_least(def.materials, m, 0, where + " materials", true)


## Upgrades (plan.md §5.15): each level changes only numbers the building has (its cost comes from
## the building's materials and its time from game_config.json construction, unless it sets its
## own), and never makes it smaller than the level below.
func _check_upgrades(def: Dictionary, where: String) -> void:
	if not def.has("upgrades"):
		return
	if typeof(def.upgrades) != TYPE_ARRAY:
		_fail("%s: 'upgrades' must be a list of levels" % where)
		return
	var current := def.duplicate()
	for i in def.upgrades.size():
		var level: Dictionary = def.upgrades[i]
		var at := "%s upgrade to Level %d" % [where, i + 2]
		_unknown_keys(level, ["cost", "time"] + UPGRADE_STATS.keys(), at)
		_number_at_least(level, "cost", 0.0, at, false)
		_number_at_least(level, "time", 0.0, at, false)
		for key in UPGRADE_STATS:
			if not level.has(key):
				continue
			_whole_at_least(level, key, UPGRADE_STATS[key], at, true)
			if not def.has(key):
				_fail("%s: changes '%s', which this building doesn't have" % [at, key])
			elif _is_number(level[key]) and level[key] < current[key]:
				_fail("%s: '%s' goes down from %s to %s" % [at, key, current[key], level[key]])
			current[key] = level[key]


## Farms, mills, bakeries: their recipes must be valid, and each is one hour of work (the batch
## length the player picks counts them, plan.md §5.1).
func _check_producer(data: Dictionary, _id: String, def: Dictionary, where: String) -> void:
	var recipes: Array = def.get("recipes", [])
	if recipes.is_empty():
		_fail("%s: makes things but has no recipes" % where)
		return
	_number_at_least(def, "water_per_hour", 0.0, where, false)
	# Product choice (plan.md §5.21): switching costs a share of the building's value.
	if def.has("switch_fee"):
		_share(def.switch_fee, where + " switch_fee", true)
		if recipes.size() < 2:
			_note("%s: has a switch_fee but only one recipe, so there's nothing to switch to" % where)
	if def.category == "extractor" and not recipes[0].get("inputs", {}).is_empty():
		_note("%s: an extractor with ingredients works like a processor" % where)
	var ids := {}
	for recipe in recipes:
		var at := "%s recipe '%s'" % [where, recipe.get("id", "?")]
		_unknown_keys(recipe, RECIPE_KEYS, at)
		if ids.has(recipe.get("id", "")):
			_fail("%s: recipe id used twice in this building" % at)
		ids[recipe.get("id", "")] = true
		_number_at_least(recipe, "duration", 0.001, at, true)
		if _is_number(recipe.get("duration")) and not is_equal_approx(float(recipe.duration), BATCH_HOUR):
			_fail("%s: duration must be %d (one hour of work: batch lengths are counted in them)" % [at, int(BATCH_HOUR)])
		if recipe.get("outputs", {}).is_empty():
			_fail("%s: makes nothing" % at)
		for part in ["inputs", "outputs"]:
			for res in recipe.get(part, {}):
				if not data.resources.has(res):
					_fail("%s: %s '%s' isn't in resources.json" % [at, part, res])
				var qty = recipe[part][res]
				if not _is_whole(qty) or qty <= 0:
					_fail("%s: %s '%s' must be a whole number above 0 (is %s)" % [at, part, res, qty])
		# By-products (plan.md §5.14): cost_share splits the cost between exactly the outputs.
		if recipe.has("cost_share"):
			var shares: Dictionary = recipe.cost_share
			var sum := 0.0
			for res in shares:
				if not recipe.get("outputs", {}).has(res):
					_fail("%s cost_share: '%s' isn't one of its outputs" % [at, res])
				_share(shares[res], "%s cost_share '%s'" % [at, res], true)
				sum += float(shares[res]) if _is_number(shares[res]) else 0.0
			for res in recipe.get("outputs", {}):
				if not shares.has(res):
					_fail("%s cost_share: '%s' has no share (every output needs one)" % [at, res])
			if absf(sum - 1.0) > 0.0001:
				_fail("%s cost_share: the shares add up to %s, not 1" % [at, sum])


func _check_resources(data: Dictionary) -> void:
	var made := {}
	var used := {}
	for id in data.buildings:
		for recipe in data.buildings[id].get("recipes", []):
			for res in recipe.get("outputs", {}):
				made[res] = true
			for res in recipe.get("inputs", {}):
				used[res] = true
		for res in data.buildings[id].get("materials", {}):  # building materials (plan.md §5.15)
			used[res] = true
	for res in data.resources:
		var def: Dictionary = data.resources[res]
		var where := "resources.json '%s'" % res
		_unknown_keys(def, RESOURCE_KEYS, where)
		if str(def.get("name", "")) == "":
			_fail("%s: has no name" % where)
		_number_at_least(def, "appetite", 0.0, where, false)
		if not made.has(res) and not def.has("price"):
			_fail("%s: no building makes it and it has no fixed price, so it has no price" % where)
		var price := Simulation.unit_price(data, res)
		if price <= 0:
			_fail("%s: its price works out to %d cents" % [where, price])
		if not made.has(res) and not used.has(res) and float(def.get("appetite", 0.0)) <= 0.0:
			_note("%s: nothing makes, uses or buys it" % where)
		_icon_exists(res, where)
		# Its category (plan.md §5.16): a known one, food is something people buy, and whatever
		# people buy must be sold by some store, or nobody could ever buy it.
		var categories: Dictionary = data.config.get("item_categories", {})
		if not def.has("category"):
			_note("%s: has no category" % where)
		elif not categories.is_empty() and not categories.has(str(def.category)):
			_fail("%s: category '%s' isn't in game_config.json item_categories" % [where, def.category])
		if str(def.get("category", "")) == "food" and float(def.get("appetite", 0.0)) <= 0.0:
			_fail("%s: food needs an appetite (how much people buy), or no store could sell it" % where)
		if float(def.get("appetite", 0.0)) > 0.0:
			var sold := false
			for type_id in data.buildings:
				if data.buildings[type_id].get("category", "") == "retail" and data.buildings[type_id].get("buildable", false):
					sold = sold or Simulation.store_sells(data, type_id, res)
			if not sold:
				_fail("%s: people buy it (appetite) but no store you can build sells its category" % where)


func _check_config(data: Dictionary) -> void:
	var c: Dictionary = data.config
	var where := "game_config.json"
	_unknown_keys(c, CONFIG_KEYS, where)
	if c.has("trade"):
		# The trader (plan.md §5.22): it must pay less than it charges, or buying and selling
		# back would make money from nothing.
		_unknown_keys(c.trade, ["sell_share", "buy_share"], where + " trade")
		_number_at_least(c.trade, "sell_share", 0.0, where + " trade", true)
		_number_at_least(c.trade, "buy_share", 0.0, where + " trade", true)
		if float(c.trade.get("sell_share", 0.0)) >= float(c.trade.get("buy_share", 1.0)):
			_fail("%s trade: sell_share must be below buy_share (or buying and selling back makes money)" % where)
	for kind in c.get("item_categories", {}):
		_unknown_keys(c.item_categories[kind], ["name"], where + " item_categories '%s'" % kind)
		if str(c.item_categories[kind].get("name", "")) == "":
			_fail("%s item_categories '%s': needs a name to show" % [where, kind])
	_number_at_least(c, "starting_cash", 0.0, where, true)
	_number_at_least(c, "population_growth_seconds", 0.0, where, true)  # 0 = nobody moves in
	_whole_at_least(c, "move_in_group_size", 1, where, false)  # adults arriving together
	for flag in ["move_in_only_for_jobs", "move_in_needs_home"]:
		if c.has(flag) and typeof(c[flag]) != TYPE_BOOL:
			_fail("%s: '%s' must be true or false" % [where, flag])
	if not bool(c.get("move_in_needs_home", true)) and not bool(c.get("move_in_only_for_jobs", false)):
		_fail("%s: 'move_in_needs_home' false needs 'move_in_only_for_jobs' true (newcomers without homes are only allowed for open jobs)" % where)
	_whole_at_least(c, "starting_population", 0, where, false)
	if c.has("life"):
		var life: Dictionary = c.life
		var at := where + " life"
		_unknown_keys(life, ["birth_rate_per_hour", "death_rate_per_hour", "grow_up_hours", "child_group_hours", "grown_ups_leave_without_job"], at)
		_number_at_least(life, "birth_rate_per_hour", 0.0, at, true)
		_number_at_least(life, "death_rate_per_hour", 0.0, at, true)
		_number_at_least(life, "child_group_hours", 0.001, at, true)
		_number_at_least(life, "grow_up_hours", float(life.get("child_group_hours", 0.0)), at, true)
	# The founding villagers (adults) must fit in the starting homes.
	var room := 0
	for entry in c.get("starting_buildings", []):
		var home: Dictionary = data.buildings.get(str(entry.get("type", "")), {})
		if not home.get("hut", false):
			room += int(home.get("households", 0)) * int(c.get("housing", {}).get("adults_per_household", 2))
	if int(c.get("starting_population", 0)) > room:
		_fail("%s: starting_population %d is more than the starting homes hold (%d adults)" % [where, int(c.starting_population), room])
	if c.has("housing"):
		var h: Dictionary = c.housing
		var at := where + " housing"
		_unknown_keys(h, ["adults_per_household", "children_per_household", "rent_share", "wealth_classes"], at)
		_whole_at_least(h, "adults_per_household", 1, at, true)
		_whole_at_least(h, "children_per_household", 0, at, true)
		_share(h.get("rent_share"), at + " rent_share", true)
		var last := -1.0
		for wealth in h.get("wealth_classes", []):
			if str(wealth.get("id", "")) == "" or str(wealth.get("name", "")) == "":
				_fail("%s wealth_classes: every class needs an id and a name" % at)
			var from = wealth.get("from_wage")
			if not _is_number(from) or from <= last:
				_fail("%s wealth_classes: from_wage must go up, poorest first (%s after %s)" % [at, from, last])
			else:
				last = float(from)
		if float(h.get("wealth_classes", [{}])[0].get("from_wage", -1)) != 0.0:
			_fail("%s wealth_classes: the first (no job) class must start from 0" % at)
	_number_at_least(c, "autosave_seconds", 1.0, where, true)
	_number_at_least(c, "stats_sample_seconds", 1.0, where, true)
	_whole_at_least(c, "stats_history_size", 1, where, true)
	_number_at_least(c, "money_log_minutes", 1.0, where, false)
	_whole_at_least(c, "money_log_size", 2, where, false)
	_number_at_least(c, "sales_tax_window_hours", 0.001, where, true)
	_share(c.get("cancel_refund_in_progress"), "%s cancel_refund_in_progress" % where, true)
	if c.has("roads"):
		_check_roads(data)
	if c.has("batch"):
		var at := where + " batch"
		_unknown_keys(c.batch, ["max_hours", "default_hours"], at)
		_whole_at_least(c.batch, "max_hours", 1, at, true)
		_whole_at_least(c.batch, "default_hours", 1, at, true)
		if int(c.batch.get("default_hours", 0)) > int(c.batch.get("max_hours", 0)):
			_fail("%s: default_hours is more than max_hours" % at)
	for bonus in c.get("wage_bonuses", {}):
		if not c.get("bonus_output", {}).has(bonus):
			_fail("%s bonus_output: no entry for the '%s' bonus" % [where, bonus])
	for bonus in c.get("bonus_output", {}):
		if not c.get("wage_bonuses", {}).has(bonus):
			_fail("%s bonus_output: '%s' isn't one of wage_bonuses" % [where, bonus])
		_number_at_least(c.bonus_output, bonus, 0.0, where + " bonus_output", true)
	var grid: Array = c.get("grid_size", [])
	if grid.size() != 2 or not _is_whole(grid[0]) or not _is_whole(grid[1]) or grid[0] < 1 or grid[1] < 1:
		_fail("%s: grid_size must be two whole numbers above 0" % where)
		return
	# The starting kit: real buildings, on the plot, one per tile, with a warehouse for goods.
	var cells := {}
	var has_storage := false
	for entry in c.get("starting_buildings", []):
		var type := str(entry.get("type", ""))
		if not data.buildings.has(type):
			_fail("%s starting_buildings: '%s' isn't in buildings.json" % [where, type])
			continue
		has_storage = has_storage or data.buildings[type].get("category", "") == "storage"
		var pos: Array = entry.get("position", [])
		if pos.size() != 2 or pos[0] < 0 or pos[1] < 0 or pos[0] >= grid[0] or pos[1] >= grid[1]:
			_fail("%s starting_buildings: '%s' is off the plot (%s)" % [where, type, pos])
		elif cells.has(str(pos)):
			_fail("%s starting_buildings: '%s' and '%s' are on the same tile %s" % [where, cells[str(pos)], type, pos])
		else:
			cells[str(pos)] = type
	if not has_storage:
		_fail("%s starting_buildings: no warehouse, so a new game has no room for goods" % where)
	# Choices with a default: the default must be one of the choices.
	_default_in(c, "staffing_levels", "default_staffing", where)
	_default_in(c, "wage_bonuses", "default_bonus", where)
	_default_in(c.get("retail", {}), "price_tags", "default_tag", where + " retail")
	for level in c.get("staffing_levels", {}):
		var share = c.staffing_levels[level]
		if not _is_number(share) or share <= 0.0 or share > 1.0:
			_fail("%s staffing_levels '%s': must be above 0 and at most 1 (is %s)" % [where, level, share])
	for bonus in c.get("wage_bonuses", {}):
		_number_at_least(c.wage_bonuses, bonus, 0.0, where + " wage_bonuses", true)
	for type in c.get("worker_types", {}):
		_number_at_least(c.worker_types[type], "wage_per_hour", 0.01, "%s worker_types '%s'" % [where, type], true)
	for tag in c.get("retail", {}).get("price_tags", {}):
		var at := "%s retail price_tags '%s'" % [where, tag]
		_number_at_least(c.retail.price_tags[tag], "price", 0.01, at, true)
		_number_at_least(c.retail.price_tags[tag], "speed", 0.01, at, true)
	_ascending(c.get("sales_tax_brackets", []), "rate", where + " sales_tax_brackets")
	_ascending(c.get("water", {}).get("tiers", []), "extra", where + " water tiers")
	_number_at_least(c.get("water", {}), "billing_hours", 0.001, where + " water", true)
	_number_at_least(c.get("water", {}), "price_per_m3", 0.0, where + " water", true)
	if c.has("power"):
		_ascending(c.power.get("tiers", []), "extra", where + " power tiers")
		_number_at_least(c.power, "billing_hours", 0.001, where + " power", true)
		_number_at_least(c.power, "price_per_mwh", 0.0, where + " power", true)
	_number_at_least(c.get("pricing", {}), "payback_hours", 0.001, where + " pricing", true)
	_share(c.get("pricing", {}).get("typical_tax_rate"), where + " pricing typical_tax_rate", true)
	if c.has("happiness"):
		_check_happiness(data, c.happiness, where + " happiness")
	if c.has("construction"):
		_check_construction(c, where + " construction")


## A Construction Office (plan.md §5.15): its workers are the construction crew, so it needs
## workers, the "construction_crew" mark, and a new game must start with one (or nothing could be
## built). Only one building type may be the crew's.
func _check_crew_office(data: Dictionary, id: String, def: Dictionary, where: String) -> void:
	if not def.get("construction_crew", false):
		_fail("%s: a 'construction' building needs \"construction_crew\": true" % where)
	_whole_at_least(def, "max_workers", 1, where, true)
	var starts := false
	for entry in data.config.get("starting_buildings", []):
		starts = starts or entry.type == id
	if not starts:
		_fail("%s: a new game must start with one in starting_buildings, or nothing could be built" % where)
	for other in data.buildings:
		if other != id and data.buildings[other].get("construction_crew", false):
			_fail("%s: only one building type may have construction_crew (also '%s')" % [where, other])


## Building and upgrading (plan.md §5.15): a crew paid a share of the materials' value, a growth
## per level of at least 1 (never cheaper), times, and how much prices swing. (The materials and
## their base prices are items in resources.json, checked with the buildings.)
func _check_construction(c: Dictionary, where: String) -> void:
	var k: Dictionary = c.construction
	_unknown_keys(k, ["labor_share", "crew", "crew_per_level", "level_growth", "level_seconds", "price_swing", "price_change_seconds"], where)
	_share(k.get("labor_share", 0.0), where + " labor_share", false)
	_whole_at_least(k, "crew", 0, where, false)
	_whole_at_least(k, "crew_per_level", 0, where, false)
	_number_at_least(k, "level_growth", 1.0, where, true)
	_number_at_least(k, "price_change_seconds", 1.0, where, false)
	var swing = k.get("price_swing", 0.0)
	if not _is_number(swing) or swing < 0.0 or swing > 0.9:
		_fail("%s: price_swing must be between 0 and 0.9 (is %s)" % [where, swing])
	var times = k.get("level_seconds", [])
	if typeof(times) != TYPE_ARRAY:
		_fail("%s: level_seconds must be a list of seconds" % where)
		return
	for t in times:
		if not _is_number(t) or t < 0.0:
			_fail("%s: level_seconds must be numbers of at least 0 (has %s)" % [where, t])


## A home (plan.md §5.18): households, and only known wealth classes. A hut must be free and
## not buildable (it appears by itself).
## Roads (plan.md §5.20): a price, one road hub, starting roads on free tiles of the plot, and
## every starting building that needs a road linked to the hub in a new game.
func _check_roads(data: Dictionary) -> void:
	var at := "game_config.json roads"
	var roads: Dictionary = data.config.roads
	_unknown_keys(roads, ["price", "starting_roads"], at)
	_number_at_least(roads, "price", 0.0, at, true)
	var hubs := 0
	for type_id in data.buildings:
		if data.buildings[type_id].get("road_hub", false):
			hubs += 1
	if hubs != 1:
		_fail("%s: exactly one building in buildings.json needs \"road_hub\": true (found %d)" % [at, hubs])
	var grid: Array = data.config.get("grid_size", [0, 0])
	var standing := {}  # every tile of every starting building's footprint
	for entry in data.config.get("starting_buildings", []):
		for tile in Simulation.footprint(data, str(entry.type), Vector2i(int(entry.position[0]), int(entry.position[1]))):
			if standing.has(tile):
				_fail("%s starting_buildings: two starting buildings overlap at %s" % [at, tile])
			elif tile.x < 0 or tile.y < 0 or tile.x >= int(grid[0]) or tile.y >= int(grid[1]):
				_fail("%s starting_buildings: the %s reaches off the plot at %s" % [at, entry.type, tile])
			standing[tile] = true
	for cell in roads.get("starting_roads", []):
		if typeof(cell) != TYPE_ARRAY or cell.size() != 2:
			_fail("%s starting_roads: %s isn't [x, y]" % [at, cell])
			continue
		var c := Vector2i(int(cell[0]), int(cell[1]))
		if c.x < 0 or c.y < 0 or c.x >= int(grid[0]) or c.y >= int(grid[1]):
			_fail("%s starting_roads: %s is outside the plot" % [at, c])
		elif standing.has(c):
			_fail("%s starting_roads: %s is under a starting building" % [at, c])
	if hubs == 1:
		var state := Simulation.new_game(data, 0.0)
		for b in state.buildings:
			if not Simulation.on_road(data, b):
				_fail("%s: the starting %s at %s isn't linked to the road hub by starting_roads" % [at, b.type, b.position])


func _check_home(config: Dictionary, def: Dictionary, where: String) -> void:
	_whole_at_least(def, "households", 1, where, true)
	_whole_at_least(def, "housing_tier", 0, where, false)
	_number_at_least(def, "rent_per_household", 0.0, where, false)
	_number_at_least(def, "power_mw", 0.0, where, false)
	_share(def.get("housing_quality"), where + " housing_quality", false)
	var known := {}
	for wealth in config.get("housing", {}).get("wealth_classes", []):
		known[str(wealth.get("id", ""))] = true
	for id in def.get("wealth", []):
		if not known.has(str(id)):
			_fail("%s: wealth '%s' isn't in game_config.json housing wealth_classes" % [where, id])
	if def.get("hut", false) and (def.get("buildable", false) or float(def.get("rent_per_household", 0)) > 0.0):
		_fail("%s: a hut appears by itself: it can't be buildable or charge rent" % where)


## A service building (plan.md 5.23): it meets a need from game_config.json happiness (not one
## the game scores by itself, except Safety) for some people, with workers.
func _check_service(config: Dictionary, def: Dictionary, where: String) -> void:
	var need := str(def.get("service_need", ""))
	var needs: Dictionary = config.get("happiness", {}).get("needs", {})
	if need == "" or not needs.has(need):
		_fail("%s: service_need '%s' isn't a need in game_config.json happiness needs" % [where, need])
	elif need in ["food", "jobs", "housing"]:
		_fail("%s: service_need '%s' is scored by the game itself, not by service buildings" % [where, need])
	_whole_at_least(def, "service_capacity", 1, where, true)
	_share(def.get("service_quality"), where + " service_quality", false)
	_whole_at_least(def, "max_workers", 1, where, true)


## Needs & happiness (plan.md §5.6): needs with their settings, weights for known needs and
## wealth classes, expectations going up, and move-in speed bands starting at 0 and going up.
func _check_happiness(data: Dictionary, h: Dictionary, where: String) -> void:
	_unknown_keys(h, ["needs", "weights", "class_weights", "expectations", "content_at", "leave_group_size", "growth_speeds"], where)
	_whole_at_least(h, "leave_group_size", 1, where, false)  # people leave in groups this big
	var needs: Dictionary = h.get("needs", {})
	var extra := {"food": ["scores"], "jobs": ["quality"], "housing": ["unpowered"], "safety": ["crime", "crime_per_jobless", "crime_per_homeless"]}
	for need in needs:
		var at := "%s needs '%s'" % [where, need]
		var n: Dictionary = needs[need]
		_unknown_keys(n, ["name", "max_happiness_when_unmet"] + extra.get(need, []), at)
		if str(n.get("name", "")) == "":
			_fail("%s: has no name" % at)
		for key in ["unpowered", "crime", "crime_per_jobless", "crime_per_homeless", "max_happiness_when_unmet"]:
			_share(n.get(key), "%s %s" % [at, key], false)
		if need == "food":
			var scores: Array = n.get("scores", [])
			if scores.is_empty():
				_fail("%s scores: empty (one score for 0 foods, 1 food, ...)" % at)
			for score in scores:
				_share(score, at + " scores", true)
		if need == "jobs":
			for bonus in n.get("quality", {}):
				if not data.config.get("wage_bonuses", {}).has(bonus):
					_fail("%s quality: '%s' isn't one of game_config.json wage_bonuses" % [at, bonus])
				_share(n.quality[bonus], "%s quality %s" % [at, bonus], true)
		if not need in ["food", "jobs", "housing"]:
			var served := false
			for type_id in data.buildings:
				var def = data.buildings[type_id]
				served = served or (def is Dictionary and def.get("buildable", false) and str(def.get("service_need", "")) == need)
			if not served:
				_note("%s: no building you can build meets it, so it stays low" % at)
	var total := _check_weights(h.get("weights", {}), needs, where + " weights")
	var classes := {}
	for wealth in data.config.get("housing", {}).get("wealth_classes", []):
		classes[str(wealth.get("id", ""))] = true
	for id in h.get("class_weights", {}):
		if not classes.has(id):
			_fail("%s class_weights: '%s' isn't in game_config.json housing wealth_classes" % [where, id])
		total += _check_weights(h.class_weights[id], needs, "%s class_weights '%s'" % [where, id])
	if total <= 0.0:
		_fail("%s weights: no need counts (all weights are 0)" % where)
	var last_people := -1
	for point in h.get("expectations", []):
		_unknown_keys(point, ["people", "expected"], where + " expectations")
		_whole_at_least(point, "people", 0, where + " expectations", true)
		_share(point.get("expected"), where + " expectations expected", true)
		if _is_number(point.get("people")):
			if int(point.people) <= last_people:
				_fail("%s expectations: 'people' must go up (%s after %s)" % [where, point.people, last_people])
			last_people = int(point.people)
	if h.has("expectations") and (h.expectations.is_empty() or int(h.expectations[0].get("people", -1)) != 0):
		_fail("%s expectations: the first point must be for 0 people" % where)
	_share(h.get("content_at"), where + " content_at", false)
	var bands: Array = h.get("growth_speeds", [])
	if bands.is_empty() or float(bands[0].get("from", -1)) != 0.0:
		_fail("%s growth_speeds: the first band must start from 0" % where)
	var last := -1.0
	for band in bands:
		var from = band.get("from")
		if not _is_number(from) or from <= last:
			_fail("%s growth_speeds: 'from' values must go up (%s after %s)" % [where, from, last])
		else:
			last = float(from)
		_share(from, where + " growth_speeds from", true)
		_unknown_keys(band, ["from", "speed", "move_in", "leave_per_hour", "children_leave_per_hour", "homeless_workers_leave"], where + " growth_speeds")
		_number_at_least(band, "speed", 0.0, where + " growth_speeds", true)
		_number_at_least(band, "move_in", 0.0, where + " growth_speeds", false)
		_share(band.get("leave_per_hour", 0.0), where + " growth_speeds leave_per_hour", false)
		_share(band.get("children_leave_per_hour", 0.0), where + " growth_speeds children_leave_per_hour", false)
		if band.has("homeless_workers_leave") and typeof(band.homeless_workers_leave) != TYPE_BOOL:
			_fail("%s growth_speeds homeless_workers_leave: must be true or false" % where)


## Need weights: each a number of at least 0, for a need in happiness needs. Returns their total.
func _check_weights(weights: Dictionary, needs: Dictionary, where: String) -> float:
	var total := 0.0
	for need in weights:
		if not needs.has(need):
			_fail("%s: '%s' isn't a need in happiness needs" % [where, need])
		_number_at_least(weights, need, 0.0, where, true)
		total += float(weights[need]) if _is_number(weights[need]) else 0.0
	return total


## Brackets / tiers: start at 0, each "from" higher than the last, `value_key` a share 0-1.
func _ascending(list: Array, value_key: String, where: String) -> void:
	if list.is_empty():
		_fail("%s: empty" % where)
		return
	var last := -1.0
	for entry in list:
		var from = entry.get("from")
		if not _is_number(from) or from <= last:
			_fail("%s: 'from' values must go up (%s after %s)" % [where, from, last])
		last = float(from) if _is_number(from) else last
		_share(entry.get(value_key), "%s %s" % [where, value_key], true)
	if float(list[0].get("from", -1)) != 0.0:
		_fail("%s: the first one must start from 0" % where)


# --- 3. Architecture rules ---------------------------------------------------------

func _check_rules(scripts: Array[String]) -> void:
	# Rule 3, one clock: only TimeService reads the system clock (tools and tests aren't the game).
	var clock := RegEx.create_from_string("\\b(Time\\.get_\\w*_from_system|OS\\.get_unix_time|OS\\.get_datetime)\\b")
	# Rule 2, the rules are pure: no nodes, files, clock, randomness or autoloads in scripts/sim/.
	var impure := RegEx.create_from_string("\\b(TimeService|Economy|GameData|Settings|FileAccess|DirAccess|get_tree|Time|OS|Engine|randi|randf|randi_range|randf_range|randomize)\\b|extends\\s+Node")
	# Rule 4: player data is JSON, never a Godot Resource file.
	var resource_save := RegEx.create_from_string("\\bResourceSaver\\.save\\b")
	# Rule 2 again: screens must change the game only through Economy's actions.
	var state_write := RegEx.create_from_string("\\bEconomy\\.state(\\.\\w+|\\[[^\\]]*\\])*(\\s*(=|\\+=|-=|\\*=|/=)(?!=)|\\.(append|erase|clear|push_back|pop_front|pop_back|remove_at|merge|sort)\\()")
	for path in scripts:
		var in_tools := path.begins_with("res://tools/") or path.begins_with("res://tests/")
		var lines := FileAccess.get_file_as_string(path).split("\n")
		var mentions_debug := false
		var gated := false
		for i in lines.size():
			var line := _without_comment(lines[i])
			var at := "%s:%d" % [path.trim_prefix("res://"), i + 1]
			if not in_tools and path != "res://scripts/autoload/time_service.gd" and clock.search(line):
				_fail("%s reads the system clock; use TimeService.now() (one clock rule)" % at)
			if path.begins_with("res://scripts/sim/") and not line.strip_edges().begins_with("const "):
				var found := impure.search(line)
				if found:
					_fail("%s uses '%s' in the game rules; scripts/sim/ must stay pure (handed state, data and now)" % [at, found.get_string()])
			if not in_tools and resource_save.search(line):
				_fail("%s saves a Resource file; player data must be JSON (versioned saves rule)" % at)
			if path.begins_with("res://scenes/") and state_write.search(line):
				_fail("%s changes Economy.state directly; screens must call an Economy action" % at)
			mentions_debug = mentions_debug or line.contains("res://scenes/debug/")
			gated = gated or line.contains("OS.is_debug_build()")
		if mentions_debug and not gated and not path.begins_with("res://scenes/debug/"):
			_fail("%s loads a debug tool without checking OS.is_debug_build()" % path.trim_prefix("res://"))
	for scene in _find_files("res://scenes/", ".tscn"):
		if not scene.begins_with("res://scenes/debug/") and FileAccess.get_file_as_string(scene).contains("res://scenes/debug/"):
			_fail("%s includes a debug tool, so real players would get it too" % scene.trim_prefix("res://"))


# --- 4. Performance rules -----------------------------------------------------------

## Patterns that made the game slow before (plan.md §9.1.1), found by text search. A line that
## really needs one is marked with a "# perf-ok: why" comment.
## - Screens refresh on Economy.changed every second: their refresh function must not re-apply a
##   colour (UITheme.set_font_color does it only when it changes) or make or free nodes (update
##   labels in place; rebuild in a separate function, only when something changed).
## - In a loop, never look buildings or roads up one by one (building_at, is_road, find_building,
##   Economy.building): each walks every building or road. Make a map once (_plot_map, road_cells).
## - Economy hands out the heavy village-wide answers only through _remember.
## - A script with _process must switch it off when there's nothing to do (set_process).
func _check_performance(scripts: Array[String]) -> void:
	var lookup := RegEx.create_from_string("\\b(building_at|is_road|find_building|Economy\\.building)\\(")
	var heavy := RegEx.create_from_string("Simulation\\.(housing|happiness|employment|power_summary|power_network|water_summary|population_capacity|warehouse_cap|road_cells|linked_roads)\\(")
	var handler := RegEx.create_from_string("Economy\\.changed\\.connect\\((\\w+)\\)")
	for path in scripts:
		if path.begins_with("res://tests/") or path.begins_with("res://tools/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		var where := path.trim_prefix("res://")
		var refreshers := {}
		for found in handler.search_all(text):
			refreshers[found.get_string(1)] = true
		if text.contains("func _process(") and not text.contains("set_process("):
			_fail("%s has _process but never switches it off (set_process): only things that are moving should work every frame" % where)
		var loops: Array[int] = []  # indents of the for / while loops the current line is in
		var function := ""
		for i in lines.size():
			var raw: String = lines[i]
			var line := _without_comment(raw)
			if line.strip_edges() == "":
				continue
			var indent := line.length() - line.lstrip("\t").length()
			while not loops.is_empty() and indent <= loops[-1]:
				loops.pop_back()
			if indent == 0:
				function = line.trim_prefix("static ").trim_prefix("func ").get_slice("(", 0) if line.begins_with("func ") or line.begins_with("static func ") else ""
			var at := "%s:%d" % [where, i + 1]
			if raw.contains("perf-ok"):
				pass
			elif refreshers.has(function) and path.begins_with("res://scenes/"):
				if line.contains("add_theme_color_override("):
					_fail("%s: %s() refreshes every tick: use UITheme.set_font_color() (re-applying a colour re-lays-out the screen)" % [at, function])
				if line.contains("queue_free()") or line.contains(".new()"):
					_fail("%s: %s() refreshes every tick: don't make or free nodes there (update them in place; rebuild only when something changed)" % [at, function])
			if not loops.is_empty() and not raw.contains("perf-ok"):
				if lookup.search(line):
					_fail("%s: looks up a building or road one by one inside a loop: make a map once before the loop (_plot_map, road_cells)" % at)
				if line.contains("_footprint_problem(") and not line.contains("map"):
					_fail("%s: _footprint_problem in a loop without a plot map: make one with _plot_map() before the loop" % at)
			if path == "res://scripts/autoload/economy.gd" and heavy.search(line) and not line.contains("_remember("):
				_fail("%s: heavy village-wide question without _remember(): many screens ask it every tick" % at)
			var stripped := line.strip_edges()
			if stripped.begins_with("for ") or stripped.begins_with("while "):
				loops.append(indent)


## The line without a trailing # comment (a # inside a "string" is kept).
func _without_comment(line: String) -> String:
	var quotes := 0
	for i in line.length():
		if line[i] == "\"":
			quotes += 1
		elif line[i] == "#" and quotes % 2 == 0:
			return line.substr(0, i)
	return line


# --- Helpers -----------------------------------------------------------------------

## Every file ending in `ext` under `dir`, skipping SKIP_DIRS and folders with a .gdignore.
func _find_files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return out
	for sub in DirAccess.get_directories_at(dir):
		if sub not in SKIP_DIRS:
			out.append_array(_find_files(dir.path_join(sub), ext))
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(ext):
			out.append(dir.path_join(file))
	return out


func _unknown_keys(def: Dictionary, known: Array, where: String) -> void:
	for key in def:
		if key not in known and not String(key).begins_with("_"):  # "_comment" keys are notes for humans
			_note("%s: unknown setting '%s' (a typo? or a new setting: add it to tests/check_project.gd)" % [where, key])


func _icon_exists(name: String, where: String) -> void:
	if not FileAccess.file_exists("res://assets/ui/icons/%s.svg" % name):
		_note("%s: no icon assets/ui/icons/%s.svg" % [where, name])


func _default_in(holder: Dictionary, choices_key: String, default_key: String, where: String) -> void:
	if holder.has(default_key) and not holder.get(choices_key, {}).has(holder[default_key]):
		_fail("%s: %s '%s' isn't one of %s" % [where, default_key, holder[default_key], choices_key])


func _number_at_least(def: Dictionary, key: String, least: float, where: String, required: bool) -> void:
	if not def.has(key):
		if required:
			_fail("%s: '%s' is missing" % [where, key])
		return
	if not _is_number(def[key]) or def[key] < least:
		_fail("%s: '%s' must be a number of at least %s (is %s)" % [where, key, least, def[key]])


func _whole_at_least(def: Dictionary, key: String, least: int, where: String, required: bool) -> void:
	_number_at_least(def, key, least, where, required)
	if def.has(key) and _is_number(def[key]) and not _is_whole(def[key]):
		_fail("%s: '%s' must be a whole number (is %s)" % [where, key, def[key]])


## A share from 0 to 1 (refunds, tax rates).
func _share(value: Variant, where: String, required: bool) -> void:
	if value == null:
		if required:
			_fail("%s: missing" % where)
	elif not _is_number(value) or value < 0.0 or value > 1.0:
		_fail("%s: must be between 0 and 1 (is %s)" % [where, value])


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_whole(value: Variant) -> bool:
	return _is_number(value) and float(value) == floorf(float(value))
