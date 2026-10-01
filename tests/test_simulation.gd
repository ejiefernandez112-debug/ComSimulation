extends SceneTree
## Automated checks for the game rules in scripts/sim/simulation.gd.
## Run (from the project folder):
##   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_simulation.gd
## Uses its own small test data (below), so retuning data/*.json never breaks these tests.

const Sim = preload("res://scripts/sim/simulation.gd")
const GameDataScript = preload("res://scripts/autoload/game_data.gd")
const T0 := 1_000_000.0  # a fixed "now" so results never depend on the real clock

var _checks := 0
var _failures := 0


func _initialize() -> void:
	for method in get_method_list():
		if String(method.name).begins_with("test_"):
			call(method.name)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _data() -> Dictionary:
	return {
		"resources": {
			"wheat": {"name": "Wheat", "retail_price": 2},
			"flour": {"name": "Flour", "retail_price": 3},
		},
		"buildings": {
			"office": {"category": "civic", "build_cost": 0, "buildable": false},
			"house": {"category": "residential", "build_cost": 0, "buildable": false, "population_capacity": 10},
			"farm": {"category": "extractor", "build_cost": 100, "buildable": true, "storage_cap": 100,
				"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]},
			"mill": {"category": "processor", "build_cost": 200, "buildable": true, "storage_cap": 16, "queue_size": 4,
				"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 90}]},
		},
		"config": {"starting_cash": 500, "population_growth_seconds": 10, "warehouse_cap": 1000,
			"grid_size": [10, 10],
			"starting_buildings": [{"type": "office", "position": [0, 0]}, {"type": "house", "position": [1, 0]}]},
	}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: ", label)


## New game + a built building of `type_id` at cell (5,5). Returns [state, data, building].
func _setup(type_id: String) -> Array:
	var data := _data()
	var state := Sim.new_game(data, T0)
	var result := Sim.build(state, data, type_id, Vector2i(5, 5), T0)
	return [state, data, Sim.find_building(state, result.building_id)]


# --- Tests ----------------------------------------------------------------------

func test_new_game() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	_check(state.profile.currency == 500, "starting cash")
	_check(state.buildings.size() == 2, "starter buildings placed")
	_check(Sim.population_capacity(state, data) == 10, "house gives population capacity")
	_check(state.save_version == Sim.SAVE_VERSION, "save version set")


func test_build_rules() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	_check(Sim.build(state, data, "farm", Vector2i(3, 3), T0).ok, "can build a farm")
	_check(state.profile.currency == 400, "farm cost deducted")
	_check(not Sim.build(state, data, "farm", Vector2i(3, 3), T0).ok, "can't build on a taken spot")
	_check(not Sim.build(state, data, "farm", Vector2i(10, 0), T0).ok, "can't build outside the land")
	_check(not Sim.build(state, data, "house", Vector2i(4, 4), T0).ok, "can't build non-buildable types")
	Sim.build(state, data, "mill", Vector2i(4, 4), T0)
	Sim.build(state, data, "mill", Vector2i(5, 4), T0)
	_check(not Sim.build(state, data, "farm", Vector2i(6, 4), T0).ok, "can't build without enough money")
	_check(state.profile.currency == 0, "money never goes negative")


func test_can_build_matches_build() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	var before: int = state.buildings.size()
	_check(Sim.can_build(state, data, "farm", Vector2i(3, 3)).ok, "can_build says yes on a free spot")
	_check(state.buildings.size() == before and state.profile.currency == 500, "can_build changes nothing")
	Sim.build(state, data, "farm", Vector2i(3, 3), T0)
	var taken: Dictionary = Sim.can_build(state, data, "farm", Vector2i(3, 3))
	_check(not taken.ok and taken.error == "That spot is taken.", "can_build explains why not")
	_check(not Sim.can_build(state, data, "farm", Vector2i(-1, 0)).ok, "can_build rejects outside the land")


func test_extractor_produces_on_its_own() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	Sim.settle(state, data, T0 + 59)
	_check(farm.storage.is_empty(), "nothing before the first cycle ends")
	Sim.settle(state, data, T0 + 60)
	_check(farm.storage.get("wheat", 0) == 10, "10 wheat after 60s")
	Sim.settle(state, data, T0 + 125)
	_check(farm.storage.get("wheat", 0) == 20, "20 wheat after 125s (partial cycle kept)")
	Sim.settle(state, data, T0 + 180)
	_check(farm.storage.get("wheat", 0) == 30, "30 wheat after 180s")


func test_extractor_stops_when_full_and_restarts_after_collect() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	Sim.settle(state, data, T0 + 5000)
	_check(farm.storage.get("wheat", 0) == 100, "stops at storage cap 100")
	var result := Sim.collect(state, data, farm.id, T0 + 6000)
	_check(result.ok and result.moved.wheat == 100, "collect moves all 100 wheat")
	_check(state.inventory.get("wheat", 0) == 100, "wheat is in the warehouse")
	Sim.settle(state, data, T0 + 6059)
	_check(farm.storage.is_empty(), "no free wheat for the time spent full")
	Sim.settle(state, data, T0 + 6060)
	_check(farm.storage.get("wheat", 0) == 10, "production restarts from the collect time")


func test_long_absence_is_instant() -> void:
	var s: Array = _setup("farm")
	var started := Time.get_ticks_msec()
	Sim.settle(s[0], s[1], T0 + 365.0 * 24 * 3600)  # one year away
	_check(s[2].storage.get("wheat", 0) == 100, "a year away still caps at storage")
	_check(Time.get_ticks_msec() - started < 50, "catch-up is one calculation, not a replay")


func test_clock_moved_backwards() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	Sim.settle(state, s[1], T0 - 5000)
	_check(s[2].storage.is_empty(), "no negative or bonus production")
	_check(state.population.current == 0, "population doesn't change")
	Sim.settle(state, s[1], T0 + 60)
	_check(s[2].storage.get("wheat", 0) == 10, "resumes normally once the clock is right")


func test_processor_queue() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	_check(not Sim.enqueue(state, data, mill.id, "mill", T0).ok, "can't queue without wheat")
	state.inventory["wheat"] = 40
	for i in 4:
		_check(Sim.enqueue(state, data, mill.id, "mill", T0).ok, "queue job %d" % (i + 1))
	_check(not state.inventory.has("wheat"), "inputs taken when queued")
	state.inventory["wheat"] = 10
	_check(not Sim.enqueue(state, data, mill.id, "mill", T0).ok, "queue size limit")
	Sim.settle(state, data, T0 + 89)
	_check(mill.storage.is_empty(), "first job not done at 89s")
	Sim.settle(state, data, T0 + 180)
	_check(mill.storage.get("flour", 0) == 16, "two jobs done at 180s")
	# Storage cap is 16: job 3 finishes at 270s but must wait for space.
	Sim.settle(state, data, T0 + 1000)
	_check(mill.storage.get("flour", 0) == 16 and mill.blocked, "job 3 waits while storage is full")
	var result := Sim.collect(state, data, mill.id, T0 + 1000)
	_check(result.moved.flour == 16, "collect moves the flour")
	_check(mill.storage.get("flour", 0) == 8, "waiting job 3 lands once there's room")
	# Job 4 only starts now (t=1000), not back when job 3 originally finished.
	Sim.settle(state, data, T0 + 1089)
	_check(mill.storage.get("flour", 0) == 8, "job 4 not done at 1089s")
	Sim.settle(state, data, T0 + 1090)
	_check(mill.storage.get("flour", 0) == 16 and mill.queue.is_empty(), "job 4 done at 1090s")


func test_idle_processor_starts_fresh() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 10
	Sim.enqueue(state, s[1], mill.id, "mill", T0 + 500)  # idle for 500s first
	Sim.settle(state, s[1], T0 + 589)
	_check(mill.storage.is_empty(), "idle time doesn't count toward a new job")
	Sim.settle(state, s[1], T0 + 590)
	_check(mill.storage.get("flour", 0) == 8, "job takes its full 90s from when queued")


func test_warehouse_cap() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var farm: Dictionary = s[2]
	state.inventory["flour"] = 960  # cap is 1000, so only 40 more fit
	Sim.settle(state, s[1], T0 + 5000)
	var result := Sim.collect(state, s[1], farm.id, T0 + 5000)
	_check(result.moved.wheat == 40, "only what fits is moved")
	_check(farm.storage.wheat == 60, "the rest stays in the building")
	_check(not Sim.collect(state, s[1], farm.id, T0 + 5000).ok, "full warehouse refuses more")


func test_sell() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	state.inventory["wheat"] = 3
	_check(not Sim.sell(state, data, "wheat", 5).ok, "can't sell more than you have")
	_check(not Sim.sell(state, data, "wheat", 0).ok, "can't sell zero")
	var result := Sim.sell(state, data, "wheat", 3)
	_check(result.ok and result.earned == 6, "3 wheat x 2 = 6")
	_check(state.profile.currency == 506 and not state.inventory.has("wheat"), "money in, wheat out")


func test_population_growth() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.settle(state, data, T0 + 55)
	_check(state.population.current == 5, "+1 every 10s")
	var report := Sim.settle(state, data, T0 + 5000)
	_check(state.population.current == 10, "stops at house capacity")
	_check(report.get("population", 0) == 5, "report counts growth")


func test_offline_report() -> void:
	var s: Array = _setup("farm")
	var report := Sim.settle(s[0], s[1], T0 + 300)
	_check(report.get("wheat", 0) == 50, "report lists what was produced while away")


## The real data files must be valid: every recipe uses known resources, numbers make sense.
func test_real_data_files() -> void:
	var resources := GameDataScript.load_json("res://data/resources.json")
	var buildings := GameDataScript.load_json("res://data/buildings.json")
	var config := GameDataScript.load_json("res://data/game_config.json")
	_check(not resources.is_empty() and not buildings.is_empty() and not config.is_empty(), "data files load")
	for type_id in buildings:
		var def: Dictionary = buildings[type_id]
		if def.category in ["extractor", "processor"]:
			_check(def.has("storage_cap") and def.recipes.size() > 0, "%s has storage and recipes" % type_id)
			for recipe in def.recipes:
				_check(recipe.duration > 0, "%s timer > 0" % recipe.id)
				for res in recipe.inputs.keys() + recipe.outputs.keys():
					_check(resources.has(res), "%s uses known resource '%s'" % [recipe.id, res])
		if def.category == "processor":
			_check(def.get("queue_size", 0) > 0, "%s has a queue" % type_id)
	for entry in config.starting_buildings:
		_check(buildings.has(entry.type), "starting building '%s' exists" % entry.type)
	var state := Sim.new_game({"resources": resources, "buildings": buildings, "config": config}, T0)
	_check(state.buildings.size() == config.starting_buildings.size(), "real data starts a game")
