extends SceneTree
## Automated checks for the game rules in scripts/sim/simulation.gd.
## Run (from the project folder):
##   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_simulation.gd
## Uses its own small test data (below), so retuning data/*.json never breaks these tests.

const Sim = preload("res://scripts/sim/simulation.gd")
const GameDataScript = preload("res://scripts/autoload/game_data.gd")
const SaveFormat = preload("res://scripts/sim/save_format.gd")
const T0 := 1_000_000.0  # a fixed "now" so results never depend on the real clock

var _checks := 0
var _failures := 0
var _errors := _ErrorCounter.new()


## Godot doesn't stop when a test hits an error (like reading a missing key): it prints the error,
## skips the rest of that test and carries on. This listens to Godot's error messages and counts
## them, so a test that broke is reported as failed instead of quietly looking like a pass.
class _ErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:  # warnings are fine, real errors are not
			count += 1


func _initialize() -> void:
	# Godot still starts the game's autoloads after the tests; this keeps Economy away from the
	# player's real save file.
	Engine.set_meta("running_tests", true)
	var sim_script: Script = Sim
	if not sim_script.can_instantiate():  # the rules script has an error: don't report "0 failed"
		print("FAIL: scripts/sim/simulation.gd doesn't compile (see the error above)")
		quit(1)
		return
	OS.add_logger(_errors)
	for method in get_method_list():
		if String(method.name).begins_with("test_"):
			var errors_before := _errors.count
			call(method.name)
			if _errors.count > errors_before:  # the test hit an error, so it didn't finish properly
				_failures += 1
				print("FAIL: %s hit an error (see the message above)" % method.name)
	OS.remove_logger(_errors)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _data() -> Dictionary:
	return {
		"resources": {
			"wheat": {"name": "Wheat", "price": 2},
			"flour": {"name": "Flour", "price": 3},
		},
		"buildings": {
			"office": {"category": "civic", "build_cost": 0, "buildable": false},
			"house": {"category": "residential", "build_cost": 0, "buildable": false, "households": 5},
			# The starter warehouse: 1000 room, no workers (so the other tests' people counts don't change).
			"store": {"category": "storage", "build_cost": 300, "buildable": true, "capacity": 1000},
			# A warehouse with workers: 4 of 4 working = 1000 room, 2 of 4 = 500.
			"crew_store": {"category": "storage", "build_cost": 0, "buildable": true, "capacity": 1000, "max_workers": 4, "fixed_workers": true, "staffed_first": true, "fixed_wage": true},
			# A batch "hour" here is the recipe's duration (60 s / 90 s), to keep the tests short.
			"farm": {"category": "extractor", "build_cost": 100, "buildable": true,
				"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]},
			"mill": {"category": "processor", "build_cost": 200, "buildable": true,
				"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 90}]},
			# Same as farm / mill, but they take time to build (the ones above are instant, to keep
			# the other tests simple). The cabin is a home that takes a long time to build.
			"slow_farm": {"category": "extractor", "build_cost": 100, "buildable": true, "build_time": 5,
				"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]},
			"slow_mill": {"category": "processor", "build_cost": 200, "buildable": true, "build_time": 5,
				"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 90}]},
			"cabin": {"category": "residential", "build_cost": 0, "buildable": true, "build_time": 200, "households": 3},
			# Buildings that need workers (2 and 3 jobs). They slow down when there aren't enough people.
			"crew_farm": {"category": "extractor", "build_cost": 0, "buildable": true, "max_workers": 2,
				"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]},
			"crew_mill": {"category": "processor", "build_cost": 0, "buildable": true, "max_workers": 3,
				"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 90}]},
		},
		"config": {"starting_cash": 500, "population_growth_seconds": 10,
			"grid_size": [10, 10],
			"cancel_refund_in_progress": 0.5, "demolish_refund": 0.5,
			"batch": {"max_hours": 1000, "default_hours": 10},  # long batches, for the long tests
			"starting_buildings": [{"type": "office", "position": [0, 0]}, {"type": "house", "position": [1, 0]},
				{"type": "store", "position": [2, 0]}]},
	}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: ", label)


## Starts a batch of `hours` of the building's first recipe (bonus `bonus`). Returns the result.
func _batch(state: Dictionary, data: Dictionary, b: Dictionary, hours: int, bonus := "none", now := T0) -> Dictionary:
	return Sim.start_batch(state, data, b.id, data.buildings[b.type].recipes[0].id, hours, bonus, now)


## How many of `res` the building has made and not yet collected.
func _ready(b: Dictionary, res: String) -> int:
	return int(Sim.ready_units(b).get(res, 0))


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
	_check(state.profile.currency == 50000, "starting cash ($500 = 50000 cents)")
	_check(state.buildings.size() == 3, "starter buildings placed")
	_check(Sim.adult_room(state, data, T0) == 10 and Sim.population_capacity(state, data, T0) == 20, "house: 5 households = room for 10 adults (20 people with children)")
	_check(state.save_version == Sim.SAVE_VERSION, "save version set")


func test_build_rules() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	_check(Sim.build(state, data, "farm", Vector2i(3, 3), T0).ok, "can build a farm")
	_check(state.profile.currency == 40000, "farm cost deducted")
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
	_check(Sim.can_build(state, data, "farm", Vector2i(3, 3), T0).ok, "can_build says yes on a free spot")
	_check(state.buildings.size() == before and state.profile.currency == 50000, "can_build changes nothing")
	Sim.build(state, data, "farm", Vector2i(3, 3), T0)
	var taken: Dictionary = Sim.can_build(state, data, "farm", Vector2i(3, 3), T0)
	_check(not taken.ok and taken.error == "That spot is taken.", "can_build explains why not")
	_check(not Sim.can_build(state, data, "farm", Vector2i(-1, 0), T0).ok, "can_build rejects outside the land")


## A batch makes its share of the units every finished hour (in the test data an "hour" is the
## recipe's 60 s), and they wait in the building until collected (plan.md §5.1).
func test_batch_makes_hourly_portions() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	Sim.settle(state, data, T0 + 500)
	_check(Sim.ready_units(farm).is_empty() and Sim.is_idle(data, farm), "a farm without a batch makes nothing")
	var started := _batch(state, data, farm, 3, "none", T0 + 500)
	_check(started.ok and int(started.units.wheat) == 30, "a 3-hour batch of 10 an hour: 30 wheat")
	Sim.settle(state, data, T0 + 559)
	_check(Sim.ready_units(farm).is_empty(), "nothing before the first hour ends")
	Sim.settle(state, data, T0 + 560)
	_check(_ready(farm, "wheat") == 10, "10 wheat after the first hour")
	Sim.settle(state, data, T0 + 625)
	_check(_ready(farm, "wheat") == 20, "20 after two (part of the third kept)")
	Sim.settle(state, data, T0 + 5000)
	_check(_ready(farm, "wheat") == 30 and not Sim.batch_running(farm) and Sim.is_idle(data, farm), "30 once all 3 hours are done, then it stops")
	var result := Sim.collect(state, data, farm.id, T0 + 5000)
	_check(result.ok and int(result.moved.wheat) == 30 and int(state.inventory.wheat) == 30, "collect moves them into the warehouse")
	_check(not Sim.has_batch(farm), "everything made and collected: the batch is over")
	_check(not Sim.collect(state, data, farm.id, T0 + 5000).ok, "nothing left to collect")


## Collecting part-way takes the hours made so far; the batch carries on.
func test_collect_part_way() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	_batch(state, data, farm, 4)
	Sim.settle(state, data, T0 + 130)
	var result := Sim.collect(state, data, farm.id, T0 + 130)
	_check(result.ok and int(result.moved.wheat) == 20 and Sim.batch_running(farm), "2 hours collected; the batch carries on")
	Sim.settle(state, data, T0 + 240)
	_check(_ready(farm, "wheat") == 20, "the next 2 hours wait to be collected")
	Sim.collect(state, data, farm.id, T0 + 240)
	_check(int(state.inventory.wheat) == 40 and not Sim.has_batch(farm), "all 40 collected: the batch is over")


func test_long_absence_is_instant() -> void:
	var s: Array = _setup("farm")
	_batch(s[0], s[1], s[2], 1000)
	var started := Time.get_ticks_msec()
	var report := Sim.settle(s[0], s[1], T0 + 365.0 * 24 * 3600)  # one year away
	_check(_ready(s[2], "wheat") == 10000 and int(report.get("wheat", 0)) == 10000, "a year away: the whole batch is made, and no more")
	_check(Time.get_ticks_msec() - started < 50, "catch-up is one calculation, not a replay")


func test_clock_moved_backwards() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	_batch(state, s[1], s[2], 5)
	Sim.settle(state, s[1], T0 - 5000)
	_check(Sim.ready_units(s[2]).is_empty(), "no negative or bonus production")
	_check(state.population.current == 0, "population doesn't change")
	Sim.settle(state, s[1], T0 + 130)
	_check(_ready(s[2], "wheat") == 20, "resumes normally once the clock is right")
	Sim.settle(state, s[1], T0 + 10)
	_check(_ready(s[2], "wheat") == 20, "a clock set back never undoes finished hours")
	Sim.settle(state, s[1], T0 + 180)
	_check(_ready(s[2], "wheat") == 30, "and it carries on from there")


## A Mill's batch takes all its ingredients when it starts; one batch at a time.
func test_processor_batch() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	var none := _batch(state, data, mill, 4)
	_check(not none.ok and none.error == "Not enough Wheat for 4 hours.", "can't start without the wheat, and it says why")
	state.inventory["wheat"] = 45
	_check(_batch(state, data, mill, 4).ok and int(state.inventory.wheat) == 5, "a 4-hour batch takes 4 x 10 wheat at the start")
	_check(_batch(state, data, mill, 1).error == "It's already making a batch.", "one batch at a time")
	Sim.settle(state, data, T0 + 89)
	_check(Sim.ready_units(mill).is_empty(), "first hour not done at 89 s")
	Sim.settle(state, data, T0 + 180)
	_check(_ready(mill, "flour") == 16, "two hours done at 180 s: 16 flour")
	Sim.settle(state, data, T0 + 1000)
	_check(_ready(mill, "flour") == 32 and Sim.is_idle(data, mill), "all 4 hours: 32 flour, then idle")
	_check(_batch(state, data, mill, 1, "none", T0 + 1000).error == "Collect what it made first.", "a new batch waits until this one is collected")
	Sim.collect(state, data, mill.id, T0 + 1000)
	_check(int(state.inventory.flour) == 32, "collected")
	_check(_batch(state, data, mill, 0, "none", T0 + 1000).error == "Pick between 1 and 1000 hours.", "the length is checked")
	state.inventory["wheat"] = 10
	_check(_batch(state, data, mill, 1, "none", T0 + 1000).ok, "then the next batch can start")


func test_can_start_batch_matches_start_batch() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 30
	var check := Sim.can_start_batch(state, data, mill.id, "mill", 3, "none", T0)
	_check(check.ok and int(check.units.flour) == 24, "can_start_batch says yes, with the quote")
	_check(int(state.inventory.wheat) == 30 and not Sim.has_batch(mill), "and changes nothing")
	_check(not Sim.can_start_batch(state, data, mill.id, "mill", 4, "none", T0).ok, "4 hours need 40 wheat")
	_check(not Sim.can_start_batch(state, data, mill.id, "bake", 1, "none", T0).ok, "unknown recipe")
	_check(not Sim.can_start_batch(state, data, mill.id, "mill", 1, "huge", T0).ok, "unknown bonus")
	_check(not Sim.can_start_batch(state, data, state.buildings[1].id, "mill", 1, "none", T0).ok, "a house makes nothing")
	_check(Sim.batch_max_hours(state, data, mill.id, "mill", "none") == 3, "the longest batch the wheat allows: 3 hours")
	data.config.batch.max_hours = 2
	_check(Sim.batch_max_hours(state, data, mill.id, "mill", "none") == 2, "never longer than batch.max_hours")
	state.inventory.erase("wheat")
	_check(Sim.batch_max_hours(state, data, mill.id, "mill", "none") == 0, "no wheat: no batch")


func test_idle_processor_starts_fresh() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 10
	_batch(state, s[1], mill, 1, "none", T0 + 500)  # idle for 500 s first
	Sim.settle(state, s[1], T0 + 589)
	_check(Sim.ready_units(mill).is_empty(), "idle time doesn't count toward a new batch")
	Sim.settle(state, s[1], T0 + 590)
	_check(_ready(mill, "flour") == 8, "it takes its full 90 s from when it started")


func test_warehouse_cap() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var farm: Dictionary = s[2]
	_batch(state, s[1], farm, 10)
	state.inventory["flour"] = 960  # cap is 1000, so only 40 more fit
	Sim.settle(state, s[1], T0 + 5000)
	var result := Sim.collect(state, s[1], farm.id, T0 + 5000)
	_check(result.moved.wheat == 40, "only what fits is moved")
	_check(_ready(farm, "wheat") == 60 and Sim.has_batch(farm), "the rest waits in the building")
	_check(Sim.collect(state, s[1], farm.id, T0 + 5000).error == "The warehouse is full.", "a full warehouse refuses more")
	state.inventory.erase("flour")
	_check(Sim.collect(state, s[1], farm.id, T0 + 5000).ok and int(state.inventory.wheat) == 100 and not Sim.has_batch(farm), "with room again, the rest comes and the batch is over")


func test_collect_group_takes_every_building_of_that_type() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm_a: Dictionary = s[2]
	var farm_b := Sim.find_building(state, Sim.build(state, data, "farm", Vector2i(6, 6), T0).building_id)
	var mill := Sim.find_building(state, Sim.build(state, data, "mill", Vector2i(7, 7), T0).building_id)
	_check(not Sim.collect_group(state, data, farm_a.id, T0).ok, "nothing waiting: nothing to collect")
	state.inventory["wheat"] = 10
	_batch(state, data, farm_a, 3)
	_batch(state, data, farm_b, 2)
	_batch(state, data, mill, 1)
	Sim.settle(state, data, T0 + 180)
	var result := Sim.collect_group(state, data, farm_a.id, T0 + 180)
	_check(result.ok and int(result.moved.wheat) == 50, "one tap collects both farms' wheat")
	_check(result.by_building.has(farm_a.id) and result.by_building.has(farm_b.id), "both farms are listed")
	_check(not Sim.has_batch(farm_b) and _ready(mill, "flour") == 8, "the other farm is emptied; the mill isn't touched")
	_check(not result.left_over, "everything fitted")
	# Warehouse nearly full: the tapped farm goes first, the other keeps the rest.
	_batch(state, data, farm_a, 3, "none", T0 + 180)
	_batch(state, data, farm_b, 3, "none", T0 + 180)
	Sim.settle(state, data, T0 + 400)
	state.inventory = {"flour": 960}  # cap is 1000, so 40 fit
	result = Sim.collect_group(state, data, farm_b.id, T0 + 400)
	_check(int(result.moved.wheat) == 40 and not Sim.has_batch(farm_b), "the tapped farm is emptied first")
	_check(_ready(farm_a, "wheat") == 20 and result.left_over, "the rest waits in the other farm")


func test_sell() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	state.inventory["wheat"] = 3
	_check(not Sim.sell(state, data, "wheat", 5, T0).ok, "can't sell more than you have")
	_check(not Sim.sell(state, data, "wheat", 0, T0).ok, "can't sell zero")
	var result := Sim.sell(state, data, "wheat", 3, T0)
	_check(result.ok and result.earned == 600, "3 wheat x $2 = $6 (600 cents)")
	_check(state.profile.currency == 50600 and not state.inventory.has("wheat"), "money in, wheat out")


## Cancelling a running batch keeps the hours already made and gives back half of the
## ingredients (and wages) of the hours not made yet.
func test_cancel_batch() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	_check(not Sim.cancel_batch(state, data, mill.id, T0).ok, "nothing to cancel")
	state.inventory["wheat"] = 40
	_batch(state, data, mill, 4)
	Sim.settle(state, data, T0 + 100)  # 1 hour made, the 2nd under way
	var preview := Sim.can_cancel_batch(state, data, mill.id)
	_check(preview.ok and int(preview.hours_left) == 3 and int(preview.refund.wheat) == 15, "preview: half of the 30 wheat of the 3 hours not made")
	_check(Sim.batch_running(mill) and not state.inventory.has("wheat"), "and it changes nothing")
	var result := Sim.cancel_batch(state, data, mill.id, T0 + 100)
	_check(result.ok and int(state.inventory.wheat) == 15, "15 wheat back")
	_check(not Sim.batch_running(mill) and _ready(mill, "flour") == 8, "the hour already made stays, to collect")
	_check(not Sim.cancel_batch(state, data, mill.id, T0 + 100).ok, "a finished batch can't be cancelled")
	Sim.collect(state, data, mill.id, T0 + 100)
	_check(not Sim.has_batch(mill) and int(state.inventory.flour) == 8, "collected: the mill is free again")
	_batch(state, data, mill, 1, "none", T0 + 100)
	Sim.settle(state, data, T0 + 120)
	_check(Sim.cancel_batch(state, data, mill.id, T0 + 120).ok and not Sim.has_batch(mill), "cancelled before its first hour: nothing is left of it")


func test_cancel_finished_or_no_room() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 20
	_batch(state, data, mill, 2)
	Sim.settle(state, data, T0 + 1000)
	_check(not Sim.cancel_batch(state, data, mill.id, T0 + 1000).ok, "a finished batch can't be cancelled")
	Sim.collect(state, data, mill.id, T0 + 1000)
	state.inventory["wheat"] = 10
	_batch(state, data, mill, 1, "none", T0 + 1000)
	state.inventory["flour"] = 1000  # warehouse full
	var full: Dictionary = Sim.cancel_batch(state, data, mill.id, T0 + 1000)
	_check(not full.ok and Sim.batch_running(mill), "no cancel when the refund won't fit")


func test_demolish() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 20
	_batch(state, data, mill, 2)
	Sim.settle(state, data, T0 + 90)  # hour 1 made (8 flour waiting), hour 2 under way
	_check(Sim.demolish(state, data, mill.id, T0 + 90).error == Sim.BATCH_BUSY, "not while it has a batch")
	Sim.cancel_batch(state, data, mill.id, T0 + 90)
	Sim.collect(state, data, mill.id, T0 + 90)
	var cash: int = state.profile.currency
	var result := Sim.demolish(state, data, mill.id, T0 + 90)
	_check(result.ok and Sim.find_building(state, mill.id).is_empty(), "mill is gone")
	_check(state.profile.currency == cash + 10000, "half the 200 build cost back")
	_check(state.inventory.get("flour", 0) == 8 and state.inventory.get("wheat", 0) == 5, "its flour and half the unused wheat came back first")
	_check(Sim.can_build(state, data, "farm", Vector2i(5, 5), T0).ok, "the spot is free again")
	_check(not Sim.demolish(state, data, "b1", T0).ok, "starter buildings can't be demolished")


func test_move() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	_check(not Sim.move(state, data, farm.id, Vector2i(0, 0), T0).ok, "can't move onto another building")
	_check(not Sim.move(state, data, farm.id, Vector2i(10, 3), T0).ok, "can't move outside the land")
	_check(Sim.can_move(state, data, farm.id, Vector2i(5, 5)).ok, "dropping it back on its own tile is fine")
	_batch(state, data, farm, 2)
	Sim.settle(state, data, T0 + 30)  # half way through an hour
	_check(Sim.move(state, data, farm.id, Vector2i(7, 2), T0 + 30).ok, "can move to a free tile")
	_check(Sim.building_at(state, Vector2i(7, 2)).id == farm.id, "farm is on its new tile")
	_check(Sim.can_build(state, data, "farm", Vector2i(5, 5), T0).ok, "old tile is free again")
	Sim.settle(state, data, T0 + 60)
	_check(_ready(farm, "wheat") == 10, "production carries on through a move")
	_check(Sim.move(state, data, "b1", Vector2i(8, 8), T0 + 60).ok, "starter buildings can move too")


func test_population_growth() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.settle(state, data, T0 + 55)
	_check(state.population.current == 5, "+1 every 10s")
	var report := Sim.settle(state, data, T0 + 5000)
	_check(state.population.current == 10, "stops at house capacity")
	_check(report.get("population", 0) == 5, "report counts growth")


## Building a home adds room, not people: they move in one at a time and fill homes oldest first.
func test_home_adds_room_not_people() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.settle(state, data, T0 + 100)  # the starting house fills up: 10 people
	var cabin := Sim.find_building(state, Sim.build(state, data, "cabin", Vector2i(3, 3), T0 + 100).building_id)
	_check(int(state.population.current) == 10, "building a home adds nobody")
	_check(Sim.home_residents(state, data, cabin, T0 + 100) == 0, "nobody lives in a home being built")
	_check(is_inf(Sim.next_arrival_at(state, data, T0 + 100)), "homes full: nobody is on the way")
	var house: Dictionary = state.buildings[1]
	_check(Sim.home_residents(state, data, house, T0 + 100) == 10, "the starting house holds the 10 people")
	Sim.settle(state, data, T0 + 300)  # the cabin is finished: room for 5 more
	_check(int(state.population.current) == 10, "a finished home still adds nobody at once")
	_check(is_equal_approx(Sim.next_arrival_at(state, data, T0 + 300), T0 + 310.0), "the first newcomer arrives 10 s after it's finished")
	Sim.settle(state, data, T0 + 330)
	_check(int(state.population.current) == 13 and Sim.home_residents(state, data, cabin, T0 + 330) == 3, "people move in one at a time: 3 in the cabin after 30 s")


func test_construction_time() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	_check(Sim.is_built(state.buildings[0], T0 - 100), "starting buildings are already built (even if the clock jumps back)")
	var farm := Sim.find_building(state, Sim.build(state, data, "slow_farm", Vector2i(3, 3), T0).building_id)
	_check(not Sim.is_built(farm, T0 + 4), "still under construction after 4s")
	_check(is_equal_approx(Sim.construction_progress(farm, data, T0 + 2.5), 0.5), "construction progress halfway at 2.5s")
	var early := _batch(state, data, farm, 1, "none", T0 + 1)
	_check(not early.ok and early.error == "Still under construction.", "no batch while it's being built")
	_check(_batch(state, data, farm, 1, "none", T0 + 5).ok, "a batch can start once it's built")
	Sim.settle(state, data, T0 + 64)
	_check(Sim.ready_units(farm).is_empty(), "its first hour isn't done yet")
	Sim.settle(state, data, T0 + 65)
	_check(_ready(farm, "wheat") == 10, "first hour done 60s after it started")
	state.inventory["wheat"] = 50
	var mill := Sim.find_building(state, Sim.build(state, data, "slow_mill", Vector2i(4, 4), T0 + 100).building_id)
	var refused := _batch(state, data, mill, 1, "none", T0 + 101)
	_check(not refused.ok and int(state.inventory.wheat) == 50, "a refused batch takes no ingredients")
	_check(_batch(state, data, mill, 1, "none", T0 + 105).ok, "the mill takes a batch once built")


func test_home_under_construction() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "cabin", Vector2i(3, 3), T0)  # +5 room, finished at T0 + 200
	_check(Sim.adult_room(state, data, T0 + 199) == 10, "a home being built adds no room yet")
	_check(Sim.adult_room(state, data, T0 + 200) == 16, "finished home adds its room (3 households: 6 adults)")
	# Town is full (10) from T0+100; growth only resumes when the cabin is done at T0+200.
	# One settle covering the whole time must give the same answer: 10 + 2 by T0+220, not 15.
	Sim.settle(state, data, T0 + 220)
	_check(state.population.current == 12, "growth resumes when the home is finished, not before")


func test_statistics_counters() -> void:
	var s: Array = _setup("farm")  # farm built at T0 for 100
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	_check(Sim.stats(state).spending.construction == 10000, "construction spending counted")
	_batch(state, data, farm, 2)
	Sim.settle(state, data, T0 + 120)
	_check(int(Sim.stats(state).made.get("wheat", 0)) == 20, "production counted when it happens")
	Sim.collect(state, data, farm.id, T0 + 125)
	_check(int(Sim.stats(state).made.get("wheat", 0)) == 20, "collecting doesn't count it twice")
	Sim.sell(state, data, "wheat", 10, T0)
	var st := Sim.stats(state)
	_check(st.income.sales == 2000 and int(st.sales_by_item.wheat) == 2000 and int(st.sold.wheat) == 10, "sales counted (money, per item, amount)")
	Sim.demolish(state, data, farm.id, T0 + 130)
	_check(Sim.stats(state).income.demolish == 5000, "demolish refund counted as income")
	var old_save := Sim.new_game(data, T0)
	old_save.erase("stats")
	_check(Sim.stats(old_save).made.is_empty(), "saves without statistics get empty counters")


func test_production_rates() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "farm", Vector2i(3, 3), T0).building_id)
	var mill := Sim.find_building(state, Sim.build(state, data, "mill", Vector2i(4, 4), T0).building_id)
	Sim.build(state, data, "slow_farm", Vector2i(5, 5), T0)
	_batch(state, data, farm, 10)
	var rates := Sim.production_rates(state, data, T0 + 1)
	_check(is_equal_approx(float(rates.made.get("wheat", 0)), 10.0), "farm makes 10 wheat/min (the slow farm is still being built)")
	_check(rates.buildings.working == 1 and rates.buildings.idle == 1 and rates.buildings.building == 1, "counts working / idle / being built")
	state.inventory["wheat"] = 10
	_batch(state, data, mill, 1, "none", T0 + 1)
	rates = Sim.production_rates(state, data, T0 + 2)
	_check(is_equal_approx(float(rates.used.wheat), 10.0 * 60.0 / 90.0), "mill uses wheat per minute while working")
	_check(is_equal_approx(float(rates.made.flour), 8.0 * 60.0 / 90.0), "mill makes flour per minute while working")
	Sim.settle(state, data, T0 + 700)  # the farm's 10 hours and the mill's 1 are done
	rates = Sim.production_rates(state, data, T0 + 700)
	_check(rates.buildings.done == 2 and not rates.made.has("wheat"), "finished batches make nothing more (waiting to be collected)")


func test_employment() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0)  # 2 jobs
	var mill_id: String = Sim.build(state, data, "crew_mill", Vector2i(4, 4), T0).building_id  # 3 jobs
	_check(Sim.employment(state, data, T0).jobs == 5, "a mill with no batch still offers its posts (its workers wait)")
	state.inventory["wheat"] = 20
	Sim.start_batch(state, data, mill_id, "mill", 2, "none", T0)  # busy for the whole test
	var e := Sim.employment(state, data, T0)
	_check(e.jobs == 5 and e.employed == 0 and e.open_jobs == 5, "no people yet: all jobs open")
	Sim.settle(state, data, T0 + 30)  # 3 people
	e = Sim.employment(state, data, T0 + 30)
	_check(e.employed == 3 and e.unemployed == 0 and e.open_jobs == 2, "3 people fill 3 of 5 jobs")
	Sim.settle(state, data, T0 + 100)  # 10 people
	e = Sim.employment(state, data, T0 + 100)
	_check(e.employed == 5 and e.unemployed == 5 and e.open_jobs == 0, "10 people, 5 jobs: 5 unemployed")


func test_short_staffed_buildings_slow_down() -> void:
	var data := _data()
	data.config["population_growth_seconds"] = 0  # people only change when the test says so
	var state := Sim.new_game(data, T0)
	state.population.current = 1
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	_batch(state, data, farm, 10)
	_check(is_equal_approx(Sim.staffing(state, data, T0), 0.5), "1 person for 2 jobs: half speed")
	Sim.settle(state, data, T0 + 119)
	_check(Sim.ready_units(farm).is_empty(), "at half speed a 60s hour isn't done after 119s")
	Sim.settle(state, data, T0 + 120)
	_check(_ready(farm, "wheat") == 10, "at half speed a 60s hour takes 120s")
	_check(is_equal_approx(float(Sim.production_rates(state, data, T0 + 120).made.wheat), 5.0), "rates show the slower speed")
	Sim.settle(state, data, T0 + 150)
	_check(is_equal_approx(Sim.job_progress(state, farm, data, T0 + 150), 75.0 / 600.0), "progress bar moves at half speed")
	_check(is_equal_approx(Sim.batch_finishes_at(state, data, farm, T0 + 150), T0 + 150 + 525.0 * 2), "the finish time counts the speed")
	state.population.current = 2  # fully staffed from T0 + 150
	Sim.settle(state, data, T0 + 195)
	_check(_ready(farm, "wheat") == 20, "full speed again once staffed (15s + 45s of work)")

	var empty := Sim.new_game(data, T0)
	var idle := Sim.find_building(empty, Sim.build(empty, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	_batch(empty, data, idle, 10)
	Sim.settle(empty, data, T0 + 600)
	_check(Sim.ready_units(idle).is_empty() and is_inf(Sim.batch_finishes_at(empty, data, idle, T0 + 600)), "nobody to work: nothing is made, no finish time")
	empty.population.current = 2
	Sim.settle(empty, data, T0 + 659)
	_check(Sim.ready_units(idle).is_empty(), "work starts from scratch when people arrive (not 10 minutes ahead)")
	Sim.settle(empty, data, T0 + 660)
	_check(_ready(idle, "wheat") == 10, "first hour 60s after people arrive")


## Being away for a long time must give exactly the same result as playing the whole time,
## even while people move in, a home finishes and the staffing keeps changing.
func test_away_matches_playing() -> void:
	var data := _data()
	data.config["wage_bonuses"] = {"none": 0.0, "small": 0.2}
	data.config["bonus_output"] = {"none": 0.0, "small": 0.15}
	var played := Sim.new_game(data, T0)
	var away := Sim.new_game(data, T0)
	for state in [played, away]:
		for x in 4:
			var farm_id: String = Sim.build(state, data, "crew_farm", Vector2i(x, 5), T0).building_id  # 4 x 2 jobs
			Sim.start_batch(state, data, farm_id, "grow", 30 + 3 * x, "small" if x % 2 == 0 else "none", T0)
		var mill_id: String = Sim.build(state, data, "crew_mill", Vector2i(6, 6), T0).building_id  # 3 jobs: 11 in all
		Sim.build(state, data, "cabin", Vector2i(8, 8), T0)  # room for 16 adults from T0 + 200
		state.inventory["wheat"] = 80
		Sim.start_batch(state, data, mill_id, "mill", 8, "none", T0)
	var t := T0
	while t < T0 + 3000:
		t += 7.0
		Sim.settle(played, data, t)
	Sim.settle(away, data, t)
	var diff := "" if played.population.current == away.population.current else "population"
	for i in played.buildings.size():
		if diff == "":
			diff = _difference(played.buildings[i], away.buildings[i], "buildings[%d]" % i)
	_check(diff == "", "one long absence = playing in 7-second steps (population, batches, hired workers; first difference: %s)" % diff)
	_check(int(away.population.current) == 16 and Sim.staffing(away, data, t) == 1.0, "the cabin let enough people in to fill every job (16 people, 11 jobs)")
	var made := 0
	for b in away.buildings:
		made += _ready(b, "wheat")
	_check(made > 0 and made < 4 * 10 * 3000 / 60, "short-staffed early on, so less wheat than 4 full-speed farms")


## A test town with one 8-worker farm, enough people, and wages of 36/hour per worker. A batch
## "hour" is 60 s in the test data, so an hour of the farm costs 8 x $36 / 60 = $4.80.
## Returns [state, data, farm].
func _wage_town() -> Array:
	var data := _data()
	data.config["population_growth_seconds"] = 0  # people only change when the test says so
	data.config["staffing_levels"] = {"low": 0.5, "medium": 0.75, "high": 1.0}
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	data.buildings["big_farm"] = {"category": "extractor", "build_cost": 0, "buildable": true,
		"max_workers": 8, "worker_type": "low_skilled",
		"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]}
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var farm := Sim.find_building(state, Sim.build(state, data, "big_farm", Vector2i(3, 3), T0).building_id)
	return [state, data, farm]


func test_staffing_levels() -> void:
	var s := _wage_town()
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	_batch(state, data, farm, 10)
	_check(Sim.workers_wanted(data, farm) == 8 and is_equal_approx(Sim.building_speed(state, data, farm, T0), 1.0), "new buildings start at High: 8 of 8 workers, full speed")
	_check(Sim.set_staffing(state, data, farm.id, "low", T0).ok, "staffing can be changed")
	_check(Sim.workers_wanted(data, farm) == 4 and is_equal_approx(Sim.building_speed(state, data, farm, T0), 0.5), "Low: 4 workers, half speed")
	Sim.settle(state, data, T0 + 119)
	_check(Sim.ready_units(farm).is_empty(), "at Low a 60s hour isn't done after 119s")
	Sim.settle(state, data, T0 + 120)
	_check(_ready(farm, "wheat") == 10, "at Low a 60s hour takes 120s")
	Sim.set_staffing(state, data, farm.id, "medium", T0 + 120)
	_check(Sim.workers_wanted(data, farm) == 6 and is_equal_approx(Sim.building_speed(state, data, farm, T0 + 120), 0.75), "Medium: 6 workers, 75% speed")
	_check(Sim.employment(state, data, T0 + 120).jobs == 6, "jobs follow the staffing level")
	state.population.current = 3  # 7 people moved away
	Sim.settle(state, data, T0 + 120)
	_check(is_equal_approx(Sim.workers_working(state, data, farm, T0 + 120), 3.0) and is_equal_approx(Sim.building_speed(state, data, farm, T0 + 120), 3.0 / 8.0), "only 3 people for 6 jobs: 3 working, 3/8 speed")
	_check(not Sim.set_staffing(state, data, farm.id, "huge", T0).ok, "unknown staffing levels are refused")
	_check(not Sim.set_staffing(state, data, state.buildings[1].id, "low", T0).ok, "a house has no workers to set")


## A batch pays all its wages when it starts (plan.md §5.6): the full crew for every hour, whatever
## the staffing; fewer workers just take longer. Other buildings (warehouses) pay as they go.
func test_wages_and_debt() -> void:
	var s := _wage_town()
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	state.profile.currency = 5000  # $50 (money is in cents)
	var quote := Sim.can_start_batch(state, data, farm.id, "grow", 10, "none", T0)
	_check(quote.ok and int(quote.wages) == 4800, "10 hours of 8 workers at $36/h (an hour is 60 s here): $48")
	_check(Sim.batch_max_hours(state, data, farm.id, "grow", "none") == 10, "the cash covers at most 10 hours")
	_check(Sim.can_start_batch(state, data, farm.id, "grow", 11, "none", T0).error == "Not enough money for the wages.", "11 hours need more cash than there is")
	_batch(state, data, farm, 10)
	_check(state.profile.currency == 200 and int(Sim.stats(state).spending.wages) == 4800, "paid at once, counted as wages")
	Sim.set_staffing(state, data, farm.id, "low", T0)
	var report := Sim.settle(state, data, T0 + 1300)  # half speed: the 10 hours take 1200 s
	_check(state.profile.currency == 200 and not report.has("wages"), "nothing more is paid while it works, at any staffing")
	_check(_ready(farm, "wheat") == 100 and not Sim.batch_running(farm), "Low staffing: the batch took twice as long, for the same wages")

	var t := _wage_town()
	var town: Dictionary = t[0]
	town.population.current = 14
	Sim.build(town, data, "crew_store", Vector2i(6, 6), T0)  # 4 workers, paid as they go
	Sim.settle(town, data, T0)
	town.profile.currency = 1000  # $10
	Sim.settle(town, data, T0 + 1000)  # 4 x $36/h for 1000 s = $40
	_check(town.profile.currency == -3000, "a warehouse's wages are paid over time, and cash can go below 0 (debt)")
	_check(not Sim.build(town, data, "farm", Vector2i(5, 5), T0 + 1000).ok, "can't build while in debt")
	_check(Sim.batch_max_hours(town, data, t[2].id, "grow", "none") == 0, "nor start a batch")

	var u := _wage_town()
	var steps: Dictionary = u[0]
	steps.population.current = 14
	Sim.build(steps, data, "crew_store", Vector2i(6, 6), T0)
	var at := T0
	while at < T0 + 1000:
		at = minf(at + 0.7, T0 + 1000)  # the last step ends exactly at 1000 s
		Sim.settle(steps, data, at)
	_check(int(Sim.stats(steps).spending.wages) == 4000, "wages in many tiny steps add up to the same $40 (parts of a cent carried over)")


func test_sales_tax_brackets() -> void:
	var data := _data()  # wheat sells for $2
	data.config["sales_tax_brackets"] = [{"from": 0, "rate": 0.0}, {"from": 5000, "rate": 0.08},
		{"from": 25000, "rate": 0.15}, {"from": 100000, "rate": 0.22}]
	var state := Sim.new_game(data, T0)
	state.inventory["wheat"] = 100_000
	# Money is in cents: $4,000 = 400000.
	var r: Dictionary = Sim.sell(state, data, "wheat", 2000, T0)  # $4,000: inside the 0% allowance
	_check(r.tax == 0 and r.earned == 400000 and state.profile.currency == 450000, "first $5,000 a day is tax-free")
	r = Sim.sell(state, data, "wheat", 1000, T0 + 10)  # $2,000: $1,000 at 0% + $1,000 at 8%
	_check(r.tax == 8000 and r.earned == 192000, "only the part above $5,000 pays 8% ($80 tax)")
	r = Sim.sell(state, data, "wheat", 15000, T0 + 20)  # $30,000 from $6,000 to $36,000
	_check(r.tax == (19000 * 8 / 100 + 11000 * 15 / 100) * 100, "a big sale is split across brackets (8% then 15%)")
	var bracket := Sim.tax_bracket(state, data, T0 + 20)
	_check(bracket.sold == 3600000 and is_equal_approx(bracket.rate, 0.15) and bracket.next_at == 10000000, "bracket status: sold today, rate, next step")
	_check(Sim.stats(state).spending.tax == 8000 + r.tax and Sim.stats(state).income.sales == 3600000, "statistics: sales before tax, tax as money out")
	_check(Sim.sales_tax(state, data, 100000, T0 + 24 * 3600 + 30) == 0, "sales older than 24 hours no longer count")
	_check(Sim.sales_tax(state, data, 10000, T0 + 30) == 1500, "preview of the tax on a sale changes nothing")
	_check(Sim.sales_tax(state, data, 333, T0 + 30) == 50, "tax is rounded to the cent (15% of $3.33 = $0.4995 -> $0.50)")


## A Farm, Mill or Bakery's workers only work while a batch is being made: idle (no batch, or
## every hour made) they wait, tied to it, and pay nothing more. Its wages were paid at the start.
func test_idle_buildings_pay_no_wages() -> void:
	var s := _wage_town()
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	_check(Sim.is_idle(data, farm) and Sim.workers_working(state, data, farm, T0) == 0.0 and Sim.hired(farm) == 8, "no batch: idle, its 8 workers wait (tied to it)")
	Sim.settle(state, data, T0 + 600)
	_check(int(Sim.stats(state).spending.wages) == 0, "an idle building pays nothing")
	_batch(state, data, farm, 5, "none", T0 + 600)
	_check(Sim.workers_working(state, data, farm, T0 + 600) == 8.0, "a batch brings the workers in")
	Sim.settle(state, data, T0 + 3600)
	_check(Sim.is_idle(data, farm) and Sim.workers_working(state, data, farm, T0 + 3600) == 0.0, "its last hour was done at +900: idle again")
	_check(int(Sim.stats(state).spending.wages) == 2400, "only the batch's wages, paid when it started (5 x 8 x $36 / 60)")


## An idle building keeps its workers: they don't move to a building with work.
func test_idle_building_keeps_workers() -> void:
	var s := _wage_town()
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var first: Dictionary = s[2]
	var second := Sim.find_building(state, Sim.build(state, data, "big_farm", Vector2i(6, 6), T0).building_id)
	_check(Sim.hired(first) == 8 and Sim.hired(second) == 2, "10 people: the first farm hired its 8 when it opened, the second gets the other 2")
	state.population.current = 8  # 2 people moved away
	Sim.settle(state, data, T0)
	_check(Sim.hired(first) == 8 and Sim.hired(second) == 0, "the newest building loses its workers first")
	_batch(state, data, second, 10)
	_check(Sim.hired(first) == 8 and Sim.building_speed(state, data, second, T0) == 0.0, "the idle farm keeps its workers: the one with a batch doesn't get them")
	Sim.suspend(state, data, first.id, T0)
	_check(Sim.hired(first) == 0 and is_equal_approx(Sim.building_speed(state, data, second, T0), 1.0), "suspending frees them: they fill the other farm's open posts")


func test_dev_cash_tools() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.dev_add_cash(state, 1000)
	_check(state.profile.currency == 50000 + 1000, "dev: add cash (in cents)")
	Sim.dev_set_cash(state, -250)
	_check(state.profile.currency == -250, "dev: set cash (negative to test debt)")
	_check(Sim.stats(state).income.sales == 0 and Sim.stats(state).spending.construction == 0, "dev cash isn't counted as income or spending")


## The real data: worker types exist with wages, and staffing levels give whole workers.
func test_real_worker_data() -> void:
	var buildings := GameDataScript.load_json("res://data/buildings.json")
	var config := GameDataScript.load_json("res://data/game_config.json")
	var types: Dictionary = config.get("worker_types", {})
	_check(config.get("staffing_levels", {}).has(config.get("default_staffing", "")), "default staffing is one of the levels")
	for type_id in buildings:
		var def: Dictionary = buildings[type_id]
		var most := int(def.get("max_workers", 0))
		if most <= 0:
			continue
		var kind: String = def.get("worker_type", "")
		_check(types.has(kind) and float(types[kind].get("wage_per_hour", -1)) >= 0, "%s's worker type '%s' exists with a wage" % [type_id, kind])
		if def.get("buildable", false):  # "coming soon" buildings may wait for schools
			_check(types.get(kind, {}).get("available", false), "%s uses a worker type that can be hired" % type_id)
		for level in config.staffing_levels:
			var wanted: float = most * float(config.staffing_levels[level])
			_check(is_equal_approx(wanted, roundf(wanted)), "%s at %s staffing is a whole number of workers" % [type_id, level])


func test_history_and_cash_flow() -> void:
	var data := _data()
	data.config["stats_sample_seconds"] = 60
	var state := Sim.new_game(data, T0)
	Sim.settle(state, data, T0)
	Sim.settle(state, data, T0 + 30)
	_check(Sim.stats(state).history.size() == 1, "one point per minute, not per settle")
	Sim.build(state, data, "farm", Vector2i(3, 3), T0 + 40)  # spend 100
	Sim.settle(state, data, T0 + 60)
	_check(Sim.stats(state).history.size() == 2, "a new point after a minute")
	_check(int(Sim.stats(state).history[-1].cash) == 40000, "points record cash")
	Sim.settle(state, data, T0 + 100_000)
	_check(Sim.stats(state).history.size() == 3, "time away is one point, not one per minute")
	var flow := Sim.cash_flow(state, 3600, T0 + 100_000)
	_check(flow.spending == 0 and is_equal_approx(flow.seconds, 99_940.0), "\"last hour\" stretches back over the time away (one point), and the farm was bought before that")
	flow = Sim.cash_flow(state, 200_000, T0 + 100_000)
	_check(flow.spending == 10000 and is_equal_approx(flow.seconds, 100_000.0), "the whole history covers the farm purchase")
	Sim.settle(state, data, T0 + 99_000)
	_check(Sim.stats(state).history.size() == 3, "a clock that moved backwards adds no point")
	data.config["stats_history_size"] = 2
	Sim.settle(state, data, T0 + 101_000)
	_check(Sim.stats(state).history.size() == 2, "old points are dropped beyond the history size")


func test_offline_report() -> void:
	var s: Array = _setup("farm")
	_batch(s[0], s[1], s[2], 10)
	var report := Sim.settle(s[0], s[1], T0 + 300)
	_check(report.get("wheat", 0) == 50, "report lists what was produced while away")


## Saving and loading part-way through changes nothing: the loaded game carries on exactly like
## one that was never closed (cash, wages, tax, batches, people, statistics).
func test_save_round_trip() -> void:
	var data := _data()
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	data.config["sales_tax_brackets"] = [{"from": 0, "rate": 0.0}, {"from": 6, "rate": 0.5}]
	var kept := Sim.new_game(data, T0)
	for x in 3:
		var farm_id: String = Sim.build(kept, data, "crew_farm", Vector2i(x, 5), T0).building_id
		Sim.start_batch(kept, data, farm_id, "grow", 30, "none", T0)
	var mill_id: String = Sim.build(kept, data, "crew_mill", Vector2i(6, 6), T0).building_id
	Sim.build(kept, data, "cabin", Vector2i(8, 8), T0)  # finishes after the save
	kept.inventory["wheat"] = 60
	Sim.start_batch(kept, data, mill_id, "mill", 6, "none", T0)
	var saved_at := T0 + 123.456789  # an awkward time, to catch rounding in the file
	Sim.settle(kept, data, saved_at)
	Sim.set_staffing(kept, data, mill_id, "low", saved_at)
	kept.inventory["wheat"] = int(kept.inventory.get("wheat", 0)) + 5  # the mill's batch took the rest
	_check(Sim.sell(kept, data, "wheat", 5, saved_at).ok, "(setup) a sale before saving")
	var text := SaveFormat.to_text(kept, saved_at)
	var result := SaveFormat.from_text(text, data)
	_check(result.ok and result.warnings.is_empty(), "a save loads back without problems")
	var loaded: Dictionary = result.state
	_check(typeof(loaded.profile.currency) == TYPE_INT and typeof(loaded.next_building_id) == TYPE_INT, "cash and counters come back as whole numbers")
	_check(float(loaded.last_saved_at) == saved_at and int(loaded.save_version) == Sim.SAVE_VERSION, "the file says when it was saved, and its version")
	_check(_difference(kept, loaded, "") == "" or _difference(kept, loaded, "") == "last_saved_at", "the loaded game is the same as the one saved")
	Sim.settle(kept, data, T0 + 5000)
	Sim.settle(loaded, data, T0 + 5000)
	var diff := _difference(kept, loaded, "")
	_check(diff == "" or diff == "last_saved_at", "after an hour more, the loaded game still matches (first difference: %s)" % diff)
	_check(Sim.sales_last_day(loaded, data, T0 + 5000) == 1000, "the tax window remembers sales made before the save")


## Path of the first place two states differ ("" = same). Numbers only need to be equal to 6
## decimals, because the file stores whole numbers as whole numbers.
func _difference(a: Variant, b: Variant, path: String) -> String:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return "" if absf(float(a) - float(b)) < 0.000001 else path
	if typeof(a) != typeof(b):
		return path
	if a is Dictionary:
		for key in a.keys() + b.keys():
			if not (a.has(key) and b.has(key)):
				return "%s.%s" % [path, key] if path != "" else str(key)
			var d := _difference(a[key], b[key], "%s.%s" % [path, key] if path != "" else str(key))
			if d != "":
				return d
		return ""
	if a is Array:
		if a.size() != b.size():
			return path
		for i in a.size():
			var d := _difference(a[i], b[i], "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	return "" if a == b else path


func test_save_rejects_bad_files() -> void:
	var data := _data()
	var good := JSON.parse_string(SaveFormat.to_text(Sim.new_game(data, T0), T0)) as Dictionary
	_check(not SaveFormat.from_text("{ not json", data).ok, "a damaged file is refused")
	_check(not SaveFormat.from_text("[1, 2]", data).ok, "a file that isn't a save is refused")
	var newer := good.duplicate(true)
	newer.save_version = Sim.SAVE_VERSION + 1
	var refused := SaveFormat.from_text(JSON.stringify(newer), data)
	_check(not refused.ok and "newer" in refused.error, "a save from a newer game version is refused, not misread")
	var no_buildings := good.duplicate(true)
	no_buildings.erase("buildings")
	_check(not SaveFormat.from_text(JSON.stringify(no_buildings), data).ok, "a save missing its buildings is refused")
	var broken_building := good.duplicate(true)
	broken_building.buildings[0].erase("job_started_at")
	_check(not SaveFormat.from_text(JSON.stringify(broken_building), data).ok, "a building missing its timer is refused")
	_check(SaveFormat.from_text(JSON.stringify(good), data).ok, "the untouched save still loads")


## Buildings or goods removed from the data files are left out (with a note), instead of
## crashing the screens that look them up.
func test_save_drops_unknown_things() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "farm", Vector2i(5, 5), T0)
	state.inventory["wheat"] = 5
	var text := SaveFormat.to_text(state, T0)
	data.buildings.erase("farm")
	data.resources.erase("wheat")
	var result := SaveFormat.from_text(text, data)
	_check(result.ok and result.state.buildings.size() == 3 and not result.state.inventory.has("wheat"), "an unknown building and unknown goods are dropped")
	_check(result.warnings.size() == 2, "the player is told what was dropped")


## Warehouses are buildings: their room adds up, and their workers make the room.
func test_warehouse_buildings() -> void:
	var data := _data()
	data.config["population_growth_seconds"] = 0  # people only change when the test says so
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	var state := Sim.new_game(data, T0)
	_check(Sim.warehouse_cap(state, data) == 1000, "the starter warehouse gives the room")
	var crew := Sim.find_building(state, Sim.build(state, data, "crew_store", Vector2i(5, 5), T0).building_id)
	_check(Sim.warehouse_cap(state, data) == 1000, "a warehouse with no one to work adds no room")
	state.population.current = 4
	Sim.settle(state, data, T0 + 1)
	_check(Sim.warehouse_cap(state, data) == 2000 and Sim.storage_capacity(state, data, crew) == 1000, "4 of 4 workers: its full room is added")
	_check(not Sim.set_staffing(state, data, crew.id, "low", T0 + 1).ok, "a warehouse's workers are fixed: no Low / High choice")
	crew["staffing"] = "low"  # as if an older save had chosen Low before the workers were fixed
	_check(Sim.workers_wanted(data, crew) == 4, "it always asks for all 4, whatever a save says")
	state.population.current = 2
	Sim.settle(state, data, T0 + 2)
	_check(Sim.warehouse_cap(state, data) == 1500, "only 2 people for its 4 jobs: half its room")
	var paid_before := int(Sim.stats(state).spending.wages)
	Sim.settle(state, data, T0 + 1002)  # 2 workers x $36/h x 1000 s = $20
	_check(int(Sim.stats(state).spending.wages) - paid_before == 2000, "warehouse workers are paid even with nothing stored ($20)")
	state.inventory["wheat"] = 1400
	state.population.current = 0
	Sim.settle(state, data, T0 + 1003)
	_check(Sim.warehouse_cap(state, data) == 1000 and int(state.inventory.wheat) == 1400, "less room never throws goods away")
	var farm := Sim.find_building(state, Sim.build(state, data, "farm", Vector2i(6, 6), T0 + 1003).building_id)
	_batch(state, data, farm, 1, "none", T0 + 1003)
	Sim.settle(state, data, T0 + 1063)
	_check(not Sim.collect(state, data, farm.id, T0 + 1063).ok, "over the room: nothing more comes in")

	var one := Sim.new_game(data, T0)
	_check(not Sim.can_demolish(one, data, one.buildings[2].id).ok, "the last warehouse can't be demolished")
	Sim.build(one, data, "store", Vector2i(5, 5), T0)
	one.inventory["wheat"] = 1500
	_check(not Sim.can_demolish(one, data, one.buildings[2].id).ok, "nor one whose goods wouldn't fit in the others")
	one.inventory["wheat"] = 900
	_check(Sim.demolish(one, data, one.buildings[2].id, T0).ok and Sim.warehouse_cap(one, data) == 1000, "a warehouse can go when the rest has room")


## Suspend = a "soft demolish" that keeps the building: its workers go home. A building with a
## batch must let it finish (or cancel it) and be collected first.
func test_suspend_and_resume() -> void:
	var data := _data()
	data.config["population_growth_seconds"] = 0
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var mill := Sim.find_building(state, Sim.build(state, data, "crew_mill", Vector2i(5, 5), T0).building_id)
	state.inventory["wheat"] = 30
	_batch(state, data, mill, 3)
	Sim.settle(state, data, T0 + 45)  # half way through the first hour
	_check(not Sim.can_suspend(state, data, state.buildings[1].id).ok, "a house has nothing to switch off")
	_check(Sim.can_suspend(state, data, mill.id).error == Sim.BATCH_BUSY, "not while it has a batch")
	Sim.cancel_batch(state, data, mill.id, T0 + 45)
	var check := Sim.can_suspend(state, data, mill.id)
	_check(check.ok and check.goods.is_empty(), "with the batch cancelled it can")
	var result := Sim.suspend(state, data, mill.id, T0 + 45)
	_check(result.ok and Sim.is_suspended(mill) and Sim.workers_working(state, data, mill, T0 + 45) == 0.0 and Sim.employment(state, data, T0 + 45).jobs == 0, "its workers go home")
	_check(_batch(state, data, mill, 1, "none", T0 + 5000).error == "It's suspended. Resume it first.", "no batches while suspended")
	_check(not Sim.suspend(state, data, mill.id, T0 + 5000).ok, "can't suspend twice")
	_check(Sim.resume(state, data, mill.id, T0 + 5000).ok and not Sim.is_suspended(mill), "resume switches it back on")
	_check(_batch(state, data, mill, 1, "none", T0 + 5000).ok, "and it takes batches again")
	_check(not Sim.can_suspend(state, data, state.buildings[2].id).ok, "a warehouse can't be suspended if the goods wouldn't fit elsewhere")


## Saves from before warehouses were buildings (version 1) get the starter warehouse.
func test_old_save_gets_a_warehouse() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	state.buildings.remove_at(2)  # what a version 1 game looked like: no warehouse building
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 1
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	var store: Dictionary = result.state.buildings[-1] if result.ok else {}
	_check(result.ok and store.get("type", "") == "store" and int(store.position[0]) == 2, "the starter warehouse is added where the kit puts it")
	_check(int(result.state.save_version) == Sim.SAVE_VERSION and Sim.warehouse_cap(result.state, data) == 1000, "upgraded to the new version, with room again")
	Sim.build(state, data, "farm", Vector2i(2, 0), T0)  # the kit's spot is taken
	old = JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 1
	result = SaveFormat.from_text(JSON.stringify(old), data)
	store = result.state.buildings[-1]
	_check(store.type == "store" and Vector2i(int(store.position[0]), int(store.position[1])) == Vector2i(3, 0), "or on the first free tile")

	# Version 2 saves shared workers out evenly and kept no headcount: hand them out again.
	var data2 := _bonus_data()
	var town := Sim.new_game(data2, T0)
	var crew := Sim.find_building(town, Sim.build(town, data2, "crew_farm", Vector2i(5, 5), T0).building_id)
	town.population.current = 1
	var v2 := JSON.parse_string(SaveFormat.to_text(town, T0)) as Dictionary
	v2.save_version = 2
	for building in v2.buildings:
		building.erase("hired")
	result = SaveFormat.from_text(JSON.stringify(v2), data2)
	_check(result.ok and Sim.hired(Sim.find_building(result.state, crew.id)) == 1, "an older save gets its workers handed out by the new rules")


## A town for the hiring tests: minimum wage $15, bonuses 0 / 20 / 40 / 60%, people only change
## when the test says so. crew_farm has 2 posts.
func _bonus_data() -> Dictionary:
	var data := _data()
	data.config["population_growth_seconds"] = 0
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 15}}
	data.config["wage_bonuses"] = {"none": 0.0, "small": 0.2, "good": 0.4, "big": 0.6}
	return data


## The wage bonus is chosen per batch (plan.md §5.6): it pays each worker more and makes more
## units, it's locked in once the batch starts, and it doesn't decide who gets hired.
func test_bonus_per_batch() -> void:
	var data := _bonus_data()
	data.config["bonus_output"] = {"none": 0.0, "small": 0.1, "good": 0.2, "big": 0.3}
	var state := Sim.new_game(data, T0)
	var a := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	var b := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(4, 4), T0).building_id)
	_check(Sim.set_bonus(state, data, b.id, "good", T0).ok, "a bonus can be chosen for the next batch")
	_check(not Sim.set_bonus(state, data, b.id, "huge", T0).ok and not Sim.set_bonus(state, data, state.buildings[1].id, "big", T0).ok, "unknown bonuses, or a house, are refused")
	_check(is_equal_approx(Sim.wage_per_worker(data, a), 15.0) and is_equal_approx(Sim.wage_per_worker(data, b), 21.0), "wage = minimum $15 + bonus ($15 + 40% = $21)")
	state.population.current = 3
	Sim.settle(state, data, T0)
	_check(Sim.hired(a) == 2 and Sim.hired(b) == 1, "the bonus doesn't decide hiring: they take turns, the older one first")
	var quote := Sim.batch_quote(state, data, b, "grow", 10, "good", T0)
	_check(int(quote.units.wheat) == 120 and int(quote.wages) == 700, "Good: +20% units (120 instead of 100) for +40% wages ($7.00 instead of $5.00)")
	_batch(state, data, b, 10, "good")
	_check(Sim.bonus_level(data, b) == "good" and not Sim.set_bonus(state, data, b.id, "none", T0).ok, "locked in once the batch starts")
	Sim.settle(state, data, T0 + 10000)
	Sim.collect(state, data, b.id, T0 + 10000)
	_check(int(state.inventory.wheat) == 120 and Sim.set_bonus(state, data, b.id, "none", T0 + 10000).ok, "120 wheat made; once collected, the bonus can change for the next batch")

	var even := Sim.new_game(data, T0)
	var farms: Array = []
	for x in 3:
		farms.append(Sim.find_building(even, Sim.build(even, data, "crew_farm", Vector2i(x, 5), T0).building_id))
	even.population.current = 3
	Sim.settle(even, data, T0)
	_check(Sim.hired(farms[0]) == 1 and Sim.hired(farms[1]) == 1 and Sim.hired(farms[2]) == 1, "they take turns, one each")
	even.population.current = 2
	Sim.settle(even, data, T0)
	_check(Sim.hired(farms[2]) == 0 and Sim.hired(farms[0]) == 1, "fewer people: the newest building loses first")
	Sim.set_bonus(even, data, farms[1].id, "big", T0)
	even.population.current = 1
	Sim.settle(even, data, T0)
	_check(Sim.hired(farms[1]) == 0 and Sim.hired(farms[0]) == 1, "a bonus doesn't keep workers either")
	var e := Sim.employment(even, data, T0)
	_check(e.jobs == 6 and e.employed == 1 and e.unemployed == 0 and e.open_jobs == 5, "employment counts whole, hired people")


## Warehouses are staffed before any other building, whatever bonus the others pay, and lose
## their workers last (their room must not vanish).
func test_warehouses_staffed_first() -> void:
	var data := _bonus_data()
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	Sim.set_bonus(state, data, farm.id, "big", T0)
	var store := Sim.find_building(state, Sim.build(state, data, "crew_store", Vector2i(5, 5), T0).building_id)
	state.population.current = 3
	Sim.settle(state, data, T0)
	_check(Sim.hired(store) == 3 and Sim.hired(farm) == 0, "3 people: all go to the warehouse, even though the farm pays +60%")
	state.population.current = 6
	Sim.settle(state, data, T0)
	_check(Sim.hired(store) == 4 and Sim.hired(farm) == 2, "once the warehouse is full, the rest go to the farm")
	state.population.current = 3
	Sim.settle(state, data, T0)
	_check(Sim.hired(store) == 3 and Sim.hired(farm) == 0, "fewer people: the farm loses its workers before the warehouse does")
	_check(not Sim.set_bonus(state, data, store.id, "big", T0).ok, "a warehouse can't get a wage bonus")
	store["bonus"] = "big"  # as if an older save had given it one
	_check(is_equal_approx(Sim.wage_per_worker(data, store), 15.0) and Sim.bonus_level(data, store) == "none", "it always pays the minimum wage, whatever a save says")


## Being away gives exactly the same hiring, production and wages as playing all along, with
## bonuses, people moving in and a building finishing partway.
func test_hiring_away_matches_playing() -> void:
	var data := _bonus_data()
	data.config["population_growth_seconds"] = 10
	data.config["bonus_output"] = {"none": 0.0, "small": 0.1, "good": 0.2, "big": 0.3}
	var played := Sim.new_game(data, T0)
	var away := Sim.new_game(data, T0)
	for state in [played, away]:
		Sim.build(state, data, "cabin", Vector2i(8, 8), T0)  # room for 5 more people from T0 + 200
		for x in 3:
			Sim.build(state, data, "crew_farm", Vector2i(x, 5), T0)
		Sim.build(state, data, "slow_farm", Vector2i(5, 5), T0)  # finishes at T0 + 5
		for i in [4, 5, 6]:
			var bonus: String = ["good", "small", "none"][i - 4]
			Sim.start_batch(state, data, state.buildings[i].id, "grow", 40, bonus, T0)
	data.buildings.slow_farm["max_workers"] = 2
	var t := T0
	while t < T0 + 3000:
		t += 7.0
		Sim.settle(played, data, t)
	Sim.settle(away, data, t)
	var same: bool = played.population.current == away.population.current and played.profile.currency == away.profile.currency
	for i in played.buildings.size():
		same = same and Sim.hired(played.buildings[i]) == Sim.hired(away.buildings[i]) and Sim.ready_units(played.buildings[i]) == Sim.ready_units(away.buildings[i])
	_check(same, "one long absence = playing in 7-second steps (people, hired workers, batches, cash)")
	_check(_ready(away.buildings[4], "wheat") == 480 and _ready(away.buildings[5], "wheat") == 440, "the bonuses made more: Good +20%, Small +10%")


## The public water supply (plan.md §5.13): a meter records what buildings draw while they
## produce; every cycle the bill is charged at once (heavy users pay more for the extra).
func test_water_supply() -> void:
	var data := _bonus_data()  # people only change when the test says so
	# Bills every hour here (12 in the game), and the extra starts at 10 m³ per cycle.
	data.config["water"] = {"price_per_m3": 2.0, "billing_hours": 1, "tiers": [{"from": 0, "extra": 0.0}, {"from": 10, "extra": 0.25}]}
	data.buildings["wet_farm"] = {"category": "extractor", "build_cost": 0, "buildable": true, "max_workers": 2,
		"water_per_hour": 60,
		"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]}
	_check(is_equal_approx(Sim.water_bill_cost(data, 8.0, 16.0), 16.0), "8 m³ at $2 = $16")
	_check(is_equal_approx(Sim.water_bill_cost(data, 14.0, 28.0), 10 * 2.0 + 4 * 2.5), "above 10 m³ in a cycle the extra costs 25% more: $20 + $10")
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "wet_farm", Vector2i(5, 5), T0).building_id)
	_batch(state, data, farm, 5)
	_check(Sim.water_use(state, data, farm, T0) == 0.0, "nobody working yet: no water drawn")
	state.population.current = 1  # 1 of 2 workers: half speed, half the water
	Sim.settle(state, data, T0)
	_check(is_equal_approx(Sim.water_use(state, data, farm, T0), 30.0), "at half speed it draws half its water")
	state.population.current = 2
	Sim.settle(state, data, T0 + 1)
	# Water follows the work done: its 5 hours (here 60 s each) take 5 minutes of full-speed work,
	# so 5 m³ = $10 in all, whatever the speed was along the way.
	Sim.settle(state, data, T0 + 1 + 300)
	_check(not Sim.batch_running(farm) and is_equal_approx(float(Sim.water_meter(state, T0).m3), 5.0), "the meter recorded 5 m³; the batch is done: no more water drawn")
	var bill := Sim.water_bill_so_far(state, data, T0 + 1000)
	_check(int(Sim.stats(state).spending.get("water", 0)) == 0 and int(bill.cost) == 1000 and is_equal_approx(float(bill.due_at), T0 + 3600), "nothing paid yet: $10 so far, due at the end of the cycle")
	var cash := int(state.profile.currency)
	var report := Sim.settle(state, data, T0 + 3600)
	_check(int(state.profile.currency) == cash - 1000 and int(report.get("water", 0)) == 1000 and int(Sim.stats(state).spending.water) == 1000, "the bill is charged all at once when it falls due ($10)")
	_check(state.water_bills.size() == 1 and int(state.water_bills[0].cost) == 1000 and is_equal_approx(float(Sim.water_meter(state, T0).cycle_start), T0 + 3600), "it goes in the bill history, and the next cycle starts at that fixed moment")
	Sim.settle(state, data, T0 + 7300)
	_check(state.water_bills.size() == 1 and is_equal_approx(float(Sim.water_meter(state, T0).cycle_start), T0 + 7200), "a cycle with no water use sends no bill")

	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 0}}  # only water costs money here
	var poor := Sim.new_game(data, T0)
	var big := Sim.find_building(poor, Sim.build(poor, data, "wet_farm", Vector2i(5, 5), T0).building_id)
	poor.population.current = 2
	poor.profile.currency = 0
	_batch(poor, data, big, 1000)
	Sim.settle(poor, data, T0 + 3600)  # 60 m³ in the hour: 10 x $2 + 50 x $2.50 = $145
	_check(int(poor.profile.currency) == -14500, "a heavy user pays the extra, and an unpaid bill just goes into debt")

	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 15}}
	var steps := Sim.new_game(data, T0)
	for x in 2:
		var wet := Sim.find_building(steps, Sim.build(steps, data, "wet_farm", Vector2i(5 + x, 5), T0).building_id)
		_batch(steps, data, wet, 150 + 50 * x)
	steps.population.current = 4
	var away := steps.duplicate(true)
	var at := T0
	while at < T0 + 3 * 3600 + 100:
		at = minf(at + 7.0, T0 + 3 * 3600 + 100)
		Sim.settle(steps, data, at)
	Sim.settle(away, data, T0 + 3 * 3600 + 100)
	var same: bool = steps.water_bills.size() == 3 and away.water_bills.size() == 3 and steps.profile.currency == away.profile.currency
	for i in mini(steps.water_bills.size(), away.water_bills.size()):
		same = same and int(steps.water_bills[i].cost) == int(away.water_bills[i].cost) and is_equal_approx(float(steps.water_bills[i].t), float(away.water_bills[i].t))
	_check(same, "three bills while away = the same three bills playing in 7-second steps")

	data.resources.wheat.erase("price")
	for type_id in ["farm", "slow_farm", "crew_farm"]:
		data.buildings.erase(type_id)
	data.config["pricing"] = {"payback_hours": 10, "typical_tax_rate": 0.0}
	# wet_farm: 2 workers x $15 x 1/60 h = $0.50, water 60 m³/h x 1/60 h x $2 = $2: $2.50 / 10
	_check(Sim.unit_price(data, "wheat") == 25, "water is part of the price per unit ($0.25)")


## Own water (plan.md §5.13.1): a Water Treatment Plant cleans water_supply m³ an hour with all its
## workers; buildings use it first and only the rest is metered on the public bill. Its water
## costs its wages: 2 workers x $15 / 40 m³ = $0.75 a m³ (public $2).
func test_own_water_plant() -> void:
	var data := _bonus_data()
	data.config["water"] = {"price_per_m3": 2.0, "billing_hours": 1, "tiers": [{"from": 0, "extra": 0.0}]}
	data.buildings["wet_farm"] = {"category": "extractor", "build_cost": 0, "buildable": true, "max_workers": 2,
		"water_per_hour": 60, "recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]}
	data.buildings["plant"] = {"category": "utility", "build_cost": 0, "buildable": true, "max_workers": 2,
		"fixed_workers": true, "fixed_wage": true, "water_supply": 40,
		"upgrades": [{"max_workers": 4, "water_supply": 100}]}
	var state := Sim.new_game(data, T0)
	var plant := Sim.find_building(state, Sim.build(state, data, "plant", Vector2i(3, 3), T0).building_id)
	var farm := Sim.find_building(state, Sim.build(state, data, "wet_farm", Vector2i(5, 5), T0).building_id)
	state.population.current = 1  # 1 of the plant's 2 workers (the older building hires first)
	Sim.settle(state, data, T0)
	_check(is_equal_approx(Sim.water_supply(state, data, plant, T0), 20.0), "1 of 2 workers: half its water (20 m³/h)")
	state.population.current = 4
	Sim.settle(state, data, T0)
	_check(is_equal_approx(Sim.water_supply(state, data, plant, T0), 40.0) and is_equal_approx(Sim.own_water_price(state, data, T0), 0.75), "all workers: 40 m³/h at $0.75 a m³ (its wages)")
	_check(is_equal_approx(Sim.public_water_use(state, data, T0), 0.0), "the farm is idle: nothing drawn, the plant's water is spare")
	# A 60-hour batch (60 s each = 1 real hour): 60 m³/h, 40 from the plant at $0.75 + 20 public at $2.
	var quote := Sim.batch_quote(state, data, farm, "grow", 60, "none", T0)
	_check(is_equal_approx(float(quote.water), 7000.0), "the batch's water estimate: 40 x $0.75 + 20 x $2 = $70")
	_batch(state, data, farm, 60)
	_check(is_equal_approx(Sim.public_water_use(state, data, T0), 20.0) and is_equal_approx(Sim.water_cost_per_hour(state, data, farm, T0), 70.0), "the farm draws 60: the plant covers 40, the public supply 20 ($70 an hour)")
	var cash := int(state.profile.currency)
	Sim.settle(state, data, T0 + 3600)
	_check(state.water_bills.size() == 1 and is_equal_approx(float(state.water_bills[0].m3), 20.0) and int(state.water_bills[0].cost) == 4000, "only the public 20 m³ are billed ($40)")
	_check(int(state.profile.currency) == cash - 4000 - 3000, "and the plant's 2 workers are paid by the hour ($30)")

	Sim.suspend(state, data, plant.id, T0 + 3600)
	_check(is_equal_approx(Sim.own_water_total(state, data, T0 + 3600), 0.0), "a suspended plant cleans nothing")
	Sim.resume(state, data, plant.id, T0 + 3600)

	# One long absence = playing in short steps, with the plant and a farm that stops halfway.
	var steps := Sim.new_game(data, T0)
	Sim.build(steps, data, "plant", Vector2i(3, 3), T0)
	var wet := Sim.find_building(steps, Sim.build(steps, data, "wet_farm", Vector2i(5, 5), T0).building_id)
	steps.population.current = 4
	Sim.settle(steps, data, T0)
	_batch(steps, data, wet, 150)
	var away := steps.duplicate(true)
	var at := T0
	while at < T0 + 3 * 3600 + 100:
		at = minf(at + 7.0, T0 + 3 * 3600 + 100)
		Sim.settle(steps, data, at)
	Sim.settle(away, data, T0 + 3 * 3600 + 100)
	var same: bool = steps.water_bills.size() == away.water_bills.size() and steps.profile.currency == away.profile.currency
	for i in mini(steps.water_bills.size(), away.water_bills.size()):
		same = same and int(steps.water_bills[i].cost) == int(away.water_bills[i].cost)
	_check(same and steps.water_bills.size() == 3, "away = playing in 7-second steps (bills and cash)")

	plant["level"] = 2  # upgraded: 4 workers clean 100 m³/h
	_check(int(Sim.level_stat(data, plant, "water_supply", 0)) == 100, "Level 2 cleans 100 m³/h")


## Electricity test data (plan.md §5.5): the office is City Hall with a 4 MW grid link reaching 3
## tiles; a farm using 2 MW, a mill using 3 MW, a "lamp" farm using 1 MW, a 2 MW turbine (reach 2)
## and a substation (reach 3). Power costs $30 a MWh, billed every hour.
func _power_data() -> Dictionary:
	var data := _bonus_data()
	data.config["power"] = {"price_per_mwh": 30, "billing_hours": 1, "tiers": [{"from": 0, "extra": 0.0}]}
	data.buildings.office["grid_mw"] = 4
	data.buildings.office["power_radius"] = 3
	for type_id in ["crew_farm", "crew_mill"]:
		data.buildings[type_id] = data.buildings[type_id].duplicate(true)
	data.buildings.crew_farm["power_mw"] = 2
	data.buildings.crew_mill["power_mw"] = 3
	data.buildings["lamp"] = data.buildings.crew_farm.duplicate(true)
	data.buildings.lamp["power_mw"] = 1
	data.buildings["turbine"] = {"category": "power", "build_cost": 0, "buildable": true, "power_supply": 2, "power_radius": 2}
	data.buildings["sub"] = {"category": "power", "build_cost": 0, "buildable": true, "power_radius": 3}
	data.buildings["atom"] = {"category": "power", "build_cost": 0, "buildable": false, "power_supply": 50, "power_radius": 3,
		"coming_soon": "Needs College graduates."}
	return data


## Power (plan.md §5.5), Tropico-style: only inside the network around City Hall, oldest building
## first, and a building that doesn't fit gets none and stops; own plants first, the rest billed.
func test_power() -> void:
	var data := _power_data()
	var state := Sim.new_game(data, T0)
	_check(Sim.power_on(data) and state.has("power_meter"), "a new game has a power meter")
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(2, 2), T0).building_id)
	var mill := Sim.find_building(state, Sim.build(state, data, "crew_mill", Vector2i(8, 8), T0).building_id)
	var lamp := Sim.find_building(state, Sim.build(state, data, "lamp", Vector2i(1, 1), T0).building_id)
	state.population.current = 10
	state.inventory["wheat"] = 1000
	Sim.settle(state, data, T0)
	var quote := Sim.batch_quote(state, data, farm, "grow", 60, "none", T0)
	_check(is_equal_approx(float(quote.power), 6000.0), "a 1-hour batch's power estimate: 2 MW x 1 h x $30 = $60")
	_check(Sim.power_problem(farm) == "" and str(farm.power) == "", "an idle farm needs no power yet")
	_batch(state, data, farm, 100)
	_batch(state, data, mill, 50)
	_batch(state, data, lamp, 100)
	_check(Sim.power_problem(mill) == "no_grid" and Sim.workers_working(state, data, mill, T0) == 0.0, "the mill is outside City Hall's reach: no power, nobody works")
	_check(str(farm.power) == "on" and str(lamp.power) == "on", "the farm and the lamp are inside it: powered")
	var summary := Sim.power_summary(state, data, T0)
	_check(is_equal_approx(float(summary.used), 3.0) and is_equal_approx(float(summary.public), 3.0), "3 MW used, all from the public grid")

	Sim.build(state, data, "sub", Vector2i(3, 3), T0)  # its circle overlaps City Hall's: joined
	Sim.build(state, data, "sub", Vector2i(6, 6), T0)  # overlaps the first one, and reaches the mill
	_check(Sim.power_problem(mill) == "short", "in the network now, but the farm (older) took 2 of the 4 MW: 3 don't fit")
	_check(str(lamp.power) == "on", "the newer lamp still fits in the 2 MW left")
	_check(Sim.workers_working(state, data, mill, T0) == 0.0 and Sim.workers_working(state, data, farm, T0) == 2.0, "the mill doesn't work at all (no slowing down)")

	Sim.build(state, data, "turbine", Vector2i(1, 2), T0)  # +2 MW of its own
	_check(str(mill.power) == "on" and str(farm.power) == "on" and str(lamp.power) == "on", "with the turbine all three fit (6 MW)")
	summary = Sim.power_summary(state, data, T0)
	_check(is_equal_approx(float(summary.own), 2.0) and is_equal_approx(float(summary.public), 4.0), "own power first (2 MW), the public grid adds 4")
	Sim.settle(state, data, T0 + 3600)
	_check(state.power_bills.size() == 1 and is_equal_approx(float(state.power_bills[0].mwh), 4.0) and int(state.power_bills[0].cost) == 12000, "only the public 4 MWh are billed ($120)")
	_check(int(Sim.stats(state).spending.power) == 12000 and Sim.cash_check(state).ok, "the bill is in the spending and the cash check adds up")
	_check(_ready(mill, "flour") > 0, "the mill worked once it had power")

	var check := Sim.can_build(state, data, "atom", Vector2i(4, 1), T0)
	_check(not check.ok and check.error == "Needs College graduates.", "a coming-soon building can't be built, and says why")
	var free := Sim.find_building(state, Sim.build(state, data, "sub", Vector2i(9, 0), T0 + 3600).building_id)
	_check(not Sim.power_network(state, data, T0 + 3600).ids.has(free.id), "a substation whose circle touches nothing isn't joined")


## Away = playing with power: the mill is short until the farm's batch ends, then gets its power.
func test_power_away_matches_playing() -> void:
	var data := _power_data()
	var steps := Sim.new_game(data, T0)
	var farm := Sim.find_building(steps, Sim.build(steps, data, "crew_farm", Vector2i(2, 2), T0).building_id)
	var mill := Sim.find_building(steps, Sim.build(steps, data, "crew_mill", Vector2i(1, 2), T0).building_id)
	steps.population.current = 10
	steps.inventory["wheat"] = 1000
	Sim.settle(steps, data, T0)
	_batch(steps, data, farm, 30)  # 30 minutes
	_batch(steps, data, mill, 20)  # 30 minutes of work, once it has power
	_check(Sim.power_problem(mill) == "short", "2 + 3 MW don't fit in 4: the mill waits")
	var away := steps.duplicate(true)
	var early := steps.duplicate(true)
	Sim.settle(early, data, T0 + 1700)
	_check(_ready(Sim.find_building(early, mill.id), "flour") == 0, "nothing milled while it had no power")
	var at := T0
	while at < T0 + 5000:
		at = minf(at + 7.0, T0 + 5000)
		Sim.settle(steps, data, at)
	Sim.settle(away, data, T0 + 5000)
	var a := Sim.find_building(away, mill.id)
	_check(_ready(a, "flour") == 160 and _ready(mill, "flour") == 160, "the mill made its whole batch after the farm stopped")
	var same: bool = steps.profile.currency == away.profile.currency and steps.power_bills.size() == away.power_bills.size()
	for i in mini(steps.power_bills.size(), away.power_bills.size()):
		same = same and int(steps.power_bills[i].cost) == int(away.power_bills[i].cost)
	_check(same and steps.power_bills.size() == 1, "away = playing in 7-second steps (power bills and cash)")


## Saves from before electricity (version 11) get a power meter and free substations so their
## buildings that use power are inside the network.
func test_old_save_gets_power() -> void:
	var data := _power_data()
	var state := Sim.new_game(data, T0)
	var mill := Sim.find_building(state, Sim.build(state, data, "crew_mill", Vector2i(8, 8), T0).building_id)
	state.save_version = 11
	state.erase("power_meter")
	Sim.stats(state).spending.erase("power")
	var result := SaveFormat.from_text(JSON.stringify(state), data)
	_check(result.ok and int(result.state.save_version) == Sim.SAVE_VERSION, "a version 11 save loads")
	var loaded: Dictionary = result.state
	var subs := 0
	for b in loaded.buildings:
		subs += 1 if b.type == "sub" else 0
	var network := Sim.power_network(loaded, data, T0)
	_check(subs >= 1 and Sim.is_powered_cell(network, Vector2i(8, 8)), "it was given substations reaching the mill (%d)" % subs)
	_check(loaded.has("power_meter") and Sim.stats(loaded).spending.has("power") and Sim.cash_check(loaded).ok, "with a power meter, a power line and a cash check that adds up")
	_check(Sim.find_building(loaded, mill.id).get("power", "x") == "", "the idle mill needs no power yet")


## Cost tags (plan.md §5.14): a batch's cost (ingredients + wages + water) is locked in when it
## starts, and every unit collected carries its share. Minimum wage $15; crew_farm 2 workers, 10
## wheat an "hour" of 60 s (wages $0.50 an hour = 5 cents a wheat); crew_mill 3 workers, 10
## wheat -> 8 flour an "hour" of 90 s.
func test_cost_tags() -> void:
	var data := _bonus_data()
	data.config["water"] = {"price_per_m3": 2.0, "billing_hours": 12, "tiers": [{"from": 0, "extra": 0.0}]}
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	state.population.current = 2
	Sim.settle(state, data, T0)
	var started := _batch(state, data, farm, 2)
	_check(started.ok and is_equal_approx(float(farm.batch.cost), 100.0) and int(Sim.stats(state).spending.wages) == 100, "a 2-hour batch: 20 wheat for $1.00 of wages, paid at the start")
	Sim.settle(state, data, T0 + 120)
	Sim.collect(state, data, farm.id, T0 + 120)
	_check(int(state.inventory.wheat) == 20 and is_equal_approx(Sim.average_cost(state, "wheat"), 5.0), "collected: each wheat carries its share (5 cents)")

	var half := Sim.new_game(data, T0)
	var slow := Sim.find_building(half, Sim.build(half, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	half.population.current = 1  # 1 of 2 workers: half speed
	Sim.settle(half, data, T0)
	_batch(half, data, slow, 2)
	_check(int(Sim.stats(half).spending.wages) == 100, "half the workers: the same wages (they just take longer)")
	Sim.settle(half, data, T0 + 120)
	_check(_ready(slow, "wheat") == 10, "half as much made in the same time")
	Sim.collect(half, data, slow.id, T0 + 120)
	_check(is_equal_approx(Sim.average_cost(half, "wheat"), 5.0), "at the same cost per unit")

	state.population.current = 5  # the mill's 3 workers too
	var mill := Sim.find_building(state, Sim.build(state, data, "crew_mill", Vector2i(5, 5), T0 + 120).building_id)
	_batch(state, data, mill, 1, "none", T0 + 120)
	# 10 wheat at 5 cents + wages 3 x $15 x 1.5 min = $1.125, paid in whole cents: $1.13
	_check(is_equal_approx(float(mill.batch.cost), 50.0 + 113.0) and is_equal_approx(float(state.inventory_cost.wheat), 50.0), "the batch takes its wheat's cost with it (10 x 5 cents), plus its wages")
	Sim.settle(state, data, T0 + 210)
	Sim.collect(state, data, mill.id, T0 + 210)
	_check(int(state.inventory.flour) == 8 and is_equal_approx(float(state.inventory_cost.flour), 163.0), "8 flour made for $0.50 of wheat + $1.13 wages")

	state.inventory["wheat"] = int(state.inventory.wheat) + 10  # 10 bought at 15 cents each
	state.inventory_cost["wheat"] = float(state.inventory_cost.wheat) + 150.0
	_check(is_equal_approx(Sim.average_cost(state, "wheat"), 10.0), "own wheat (5) and bought wheat (15) mix to an average of 10 cents")
	var sale := Sim.sell(state, data, "wheat", 4, T0 + 210)  # wheat sells at a fixed $2 here
	_check(int(sale.cost) == 40 and int(sale.profit) == int(sale.earned) - 40, "a sale knows what the goods cost to make, and the profit")
	_check(is_equal_approx(Sim.average_cost(state, "wheat"), 10.0), "selling some keeps the average")
	state.inventory["wheat"] = int(state.inventory.wheat) + 4  # 4 more bought at 10 cents: 20 wheat
	state.inventory_cost["wheat"] = float(state.inventory_cost.wheat) + 40.0

	data.config["bonus_output"] = {"none": 0.0, "small": 0.1, "good": 0.2, "big": 0.3}
	var quote := Sim.batch_quote(state, data, mill, "mill", 2, "good", T0 + 210)
	# 20 wheat at 10 cents + wages 3 x $21 x 3 min = $3.15: $5.15 for 16 x 1.2 = 19 flour
	_check(int(quote.units.flour) == 19 and int(quote.wages) == 315 and is_equal_approx(float(quote.total), 515.0), "quote: 2 hours with a Good bonus: 19 flour (+20%), wages $3.15 (+40%), $5.15 in all")
	_check(is_equal_approx(float(quote.per_unit), 515.0 / 19.0) and is_equal_approx(float(quote.ingredients[0].each), 10.0) and int(quote.price) == 300, "cost per unit, what each ingredient costs, and the selling price")
	_batch(state, data, mill, 2, "good", T0 + 210)
	Sim.settle(state, data, T0 + 300)  # 1 of its 2 hours made
	var cash := int(state.profile.currency)
	var cancelled := Sim.cancel_batch(state, data, mill.id, T0 + 300)
	_check(int(state.inventory.wheat) == 5 and is_equal_approx(float(state.inventory_cost.wheat), 50.0), "cancelling gives back a quarter of the wheat (half of the hour not made), with its cost tag")
	_check(int(state.profile.currency) == cash + 78 and int(cancelled.money) == 78 and int(Sim.stats(state).income.batch_refunds) == 78, "and a quarter of the wages ($0.78), counted as money in")
	Sim.collect(state, data, mill.id, T0 + 300)
	_check(int(state.inventory.flour) == 8 + 9 and is_equal_approx(float(state.inventory_cost.flour), 163.0 + 515.0 * 9.0 / 19.0), "the hour made (9 flour) keeps the batch's cost per unit")

	data.buildings["wet_farm"] = {"category": "extractor", "build_cost": 0, "buildable": true, "max_workers": 2,
		"water_per_hour": 60, "recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]}
	state.population.current = 7
	var wet := Sim.find_building(state, Sim.build(state, data, "wet_farm", Vector2i(7, 7), T0 + 300).building_id)
	_batch(state, data, wet, 1, "none", T0 + 300)
	_check(is_equal_approx(float(wet.batch.cost), 250.0), "the water it will use is part of its cost ($0.50 wages + 1 m³ x $2)")


## Older saves get cost tags at the standard cost of making things.
func test_old_save_gets_cost_tags() -> void:
	var data := _bonus_data()
	data.resources.wheat.erase("price")
	data.buildings.erase("farm")
	data.buildings.erase("slow_farm")  # crew_farm makes wheat: 2 x $15 / 60 per 10 = 5 cents each
	var state := Sim.new_game(data, T0)
	state.inventory["wheat"] = 10
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 4
	old.erase("inventory_cost")
	for b in old.buildings:  # what a version 4 save looked like
		b.erase("batch")
		b["queue"] = []
		b["blocked"] = false
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	_check(result.ok and is_equal_approx(Sim.average_cost(result.state, "wheat"), 5.0), "old stock gets the standard cost of making it (5 cents a wheat)")
	var real := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	# Plus each hour's power at the grid price (plan.md §5.5): a Mill 3 MW, a Bakery 4 MW.
	var mwh := Sim.cents(float(real.config.power.price_per_mwh))
	var flour := 750.0 + 3 * mwh / 32.0
	var bread := (20 * flour + 12000.0 + 4 * mwh) / 15.0
	_check(is_equal_approx(Sim.standard_unit_cost(real, "wheat"), 300.0) and is_equal_approx(Sim.standard_unit_cost(real, "flour"), flour) and is_equal_approx(Sim.standard_unit_cost(real, "bread"), bread), "real data: wheat $3.00, flour $7.50, bread $18.00 (plan.md §5.14), plus power")


## Retail prices come from costs (plan.md §5.12): ingredients + standard wages + building share
## (pays back in payback_hours), ÷ units, ÷ (1 - typical tax). In cents, rounded.
func test_cost_based_prices() -> void:
	var data := _bonus_data()  # minimum wage $15
	data.resources.wheat.erase("price")
	data.resources.flour.erase("price")
	data.config["pricing"] = {"payback_hours": 10, "typical_tax_rate": 0.2}
	# crew_farm: 2 workers, build cost 0, 10 wheat per 60 s. Per batch: wages 2 x $15 x 1/60 h
	# = $0.50; nothing to pay back. $0.50 / 10 = $0.05, / 0.8 = $0.0625 -> 6 cents.
	data.buildings.erase("farm")
	data.buildings.erase("slow_farm")
	_check(Sim.unit_price(data, "wheat") == 6, "wheat: (wages) / units / (1 - tax), rounded to the cent")
	data.buildings.crew_farm["build_cost"] = 600  # $600 over 10 h = $1 per 60 s batch
	_check(Sim.unit_price(data, "wheat") == 19, "a building share is added: ($0.50 + $1) / 10 / 0.8 = $0.1875 -> 19 cents")
	# crew_mill: 3 workers, 10 wheat -> 8 flour in 90 s, build cost 0. Per batch: 10 x $0.19 +
	# 3 x $15 x 0.025 h = $1.90 + $1.125 = $3.025, / 8 = $0.378, / 0.8 = $0.4727 -> 47 cents.
	data.buildings.erase("mill")
	data.buildings.erase("slow_mill")
	_check(Sim.unit_price(data, "flour") == 47, "flour includes its wheat at wheat's price")
	data.resources.flour["price"] = 3
	_check(Sim.unit_price(data, "flour") == 300, "a fixed price in resources.json wins ($3)")
	var state := Sim.new_game(data, T0)
	state.inventory["wheat"] = 10
	_check(int(Sim.sell(state, data, "wheat", 10, T0).gross) == 190, "selling uses the worked-out price (10 x 19 cents)")
	state.profile.currency = 100000  # $1,000, enough for the $600 farm
	var farm :=Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	Sim.set_bonus(state, data, farm.id, "big", T0)
	_check(Sim.unit_price(data, "wheat") == 19, "a player's own bonus never changes the price")

	var real := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	_check(Sim.unit_price(real, "wheat") > 0 and Sim.unit_price(real, "flour") > Sim.unit_price(real, "wheat") and Sim.unit_price(real, "bread") > Sim.unit_price(real, "flour"), "real data: every product has a price, and processed goods are worth more")
	print("  (real prices: wheat %d, flour %d, bread %d cents)" % [Sim.unit_price(real, "wheat"), Sim.unit_price(real, "flour"), Sim.unit_price(real, "bread")])


## Version 3 saves counted dollars; version 4 counts cents.
func test_old_save_money_becomes_cents() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 3
	old.profile.currency = 5750
	old["sales_log"] = [[T0, 120]]
	old.stats.spending.wages = 80
	old.stats.history = [{"t": T0, "cash": 5750, "income": 0, "spending": 80}]
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	var s: Dictionary = result.state if result.ok else {}
	_check(result.ok and int(s.profile.currency) == 575000, "cash: $5,750 becomes 575000 cents")
	_check(int(s.sales_log[0][1]) == 12000 and int(s.stats.spending.wages) == 8000 and int(s.stats.history[0].cash) == 575000, "the tax window, statistics and graphs too")


## The real data files must be valid: every recipe uses known resources, numbers make sense.
func test_real_data_files() -> void:
	var resources := GameDataScript.load_json("res://data/resources.json")
	var buildings := GameDataScript.load_json("res://data/buildings.json")
	var config := GameDataScript.load_json("res://data/game_config.json")
	_check(not resources.is_empty() and not buildings.is_empty() and not config.is_empty(), "data files load")
	for type_id in buildings:
		var def: Dictionary = buildings[type_id]
		if def.category in ["extractor", "processor"]:
			_check(def.recipes.size() > 0, "%s has recipes" % type_id)
			for recipe in def.recipes:
				_check(float(recipe.duration) == 3600.0, "%s is one hour of work" % recipe.id)
				for res in recipe.inputs.keys() + recipe.outputs.keys():
					_check(resources.has(res), "%s uses known resource '%s'" % [recipe.id, res])
	_check(int(config.batch.max_hours) >= int(config.batch.default_hours), "batch lengths make sense")
	for entry in config.starting_buildings:
		_check(buildings.has(entry.type), "starting building '%s' exists" % entry.type)
	var tabs := {}
	for tab in GameDataScript.load_json("res://data/build_menu.json").get("tabs", []):
		tabs[tab.id] = true
		_check(ResourceLoader.exists("res://assets/ui/icons/%s.svg" % tab.icon), "tab '%s' icon exists" % tab.id)
	for type_id in buildings:
		if buildings[type_id].has("menu_tab"):
			_check(tabs.has(buildings[type_id].menu_tab), "%s's menu_tab is a Build Menu tab" % type_id)
	var state := Sim.new_game({"resources": resources, "buildings": buildings, "config": config}, T0)
	_check(state.buildings.size() == config.starting_buildings.size(), "real data starts a game")


# --- Whole production chains with the real data (plan.md §5.21) -----------------
# Raw goods to the shop shelf, with the real data/*.json: buildings need a road, power and a
# construction worker, like in the game. Test buildings stand beside the starting road (y = 10),
# inside the power network around City Hall, with a Wind Turbine for extra power.

## A new game with the real data and $1,000,000 more cash (a developer top-up, so the cash check
## still adds up). Returns [state, data].
func _real_town() -> Array:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	var state := Sim.new_game(data, T0)
	Sim.dev_add_cash(state, 100000000)
	return [state, data]


## Builds `type_id` at `x` beside the starting road (y = 9, above it). Returns the building.
func _real_build(state: Dictionary, data: Dictionary, type_id: String, x: int, now: float) -> Dictionary:
	var result := Sim.build(state, data, type_id, Vector2i(x, 9), now)
	_check(result.ok, "real chain: build %s (%s)" % [type_id, result.get("error", "")])
	return Sim.find_building(state, str(result.get("building_id", "")))


## Runs a batch of `hours` of `recipe_id`, waits (an hour at a time) until it's made, and
## collects it. Returns the time it was collected.
func _real_batch(state: Dictionary, data: Dictionary, b: Dictionary, recipe_id: String, hours: int, now: float) -> float:
	var started := Sim.start_batch(state, data, b.id, recipe_id, hours, "none", now)
	_check(started.ok, "real chain: %s starts %s (%s)" % [b.type, recipe_id, started.get("error", "")])
	var t := now
	while Sim.batch_running(b) and t < now + 7 * 86400.0:
		t += 3600.0
		Sim.settle(state, data, t)
	_check(not Sim.batch_running(b) and Sim.collect(state, data, b.id, t).ok, "real chain: %s made and collected its %s" % [b.type, recipe_id])
	return t


## Puts all of `res` on a shelf and waits until it has sold out. Returns the time.
func _real_sell_out(state: Dictionary, data: Dictionary, market: Dictionary, res: String, now: float) -> float:
	var qty := int(state.inventory.get(res, 0))
	var stocked := Sim.stock_shelf(state, data, market.id, res, qty, "normal", now)
	_check(stocked.ok, "real chain: %d %s go on a shelf (%s)" % [qty, res, stocked.get("error", "")])
	var t := now
	while Sim.store_has_product(market, res) and t < now + 7 * 86400.0:
		t += 3600.0
		Sim.settle(state, data, t)
	_check(int(Sim.stats(state).sold.get(res, 0)) == qty, "real chain: all %d %s sold to the village" % [qty, res])
	return t


## Corn -> Cornmeal, Sugarcane -> Sugar, then Cornmeal + Sugar -> Cereal, sold in the Supermarket
## for more than it cost to make.
func test_real_chain_corn_to_cereal() -> void:
	var town := _real_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var t := T0
	_real_build(state, data, "wind_turbine", 7, t)
	var corn := _real_build(state, data, "wheat_farm", 8, t)
	var cane := _real_build(state, data, "wheat_farm", 10, t)
	var mill := _real_build(state, data, "flour_mill", 11, t)
	t += 3600.0  # a Construction Office has 4 workers: 4 buildings at a time, an hour each
	Sim.settle(state, data, t)
	var sugar_mill := _real_build(state, data, "sugar_mill", 13, t)
	var factory := _real_build(state, data, "food_factory", 14, t)
	var market := _real_build(state, data, "supermarket", 16, t)
	t += 3600.0
	Sim.settle(state, data, t)
	t = _real_batch(state, data, corn, "grow_corn", 2, t)
	t = _real_batch(state, data, cane, "grow_sugarcane", 1, t)
	_check(int(state.inventory.corn) == 120 and int(state.inventory.sugarcane) == 80, "real chain: 120 corn and 80 sugarcane grown")
	t = _real_batch(state, data, mill, "mill_cornmeal", 2, t)
	t = _real_batch(state, data, sugar_mill, "make_sugar", 1, t)
	_check(int(state.inventory.cornmeal) == 64 and int(state.inventory.sugar) == 30, "real chain: 64 cornmeal and 30 sugar")
	_check(Sim.product_of(data, mill) == "mill_cornmeal" and not Sim.can_start_batch(state, data, mill.id, "mill_flour", 1, "none", t).ok, "real chain: this mill grinds corn for good")
	t = _real_batch(state, data, factory, "make_cereal", 2, t)
	_check(int(state.inventory.cereal) == 50, "real chain: 40 cornmeal + 10 sugar -> 50 cereal")
	var made_for := float(state.inventory_cost.cereal)
	t = _real_sell_out(state, data, market, "cereal", t)
	_check(int(Sim.stats(state).sales_by_item.cereal) > made_for, "real chain: cereal sells for more than it cost to make ($%d > $%d)" % [int(Sim.stats(state).sales_by_item.cereal) / 100, int(made_for) / 100])
	_check(Sim.cash_check(state).ok, "real chain: cash check adds up")


## Soybeans -> Cooking Oil + Soy Meal (a by-product), Potatoes + Oil -> Chips for the Supermarket,
## and the Soy Meal sold to the Trading Post's trader.
func test_real_chain_soy_oil_to_chips() -> void:
	var town := _real_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var t := T0
	_real_build(state, data, "wind_turbine", 7, t)
	var soy := _real_build(state, data, "wheat_farm", 8, t)
	var spuds := _real_build(state, data, "wheat_farm", 10, t)
	var press := _real_build(state, data, "oil_press", 11, t)
	t += 3600.0
	Sim.settle(state, data, t)
	var factory := _real_build(state, data, "food_factory", 13, t)
	var market := _real_build(state, data, "supermarket", 14, t)
	_real_build(state, data, "trading_post", 16, t)
	t += 3600.0
	Sim.settle(state, data, t)
	t = _real_batch(state, data, soy, "grow_soybeans", 1, t)
	t = _real_batch(state, data, spuds, "grow_potatoes", 1, t)
	var started := Sim.start_batch(state, data, press.id, "press_soybeans", 1, "none", t)
	var batch_cost := float(press.batch.cost)
	_check(started.ok and int(started.units.vegetable_oil) == 8 and int(started.units.soy_meal) == 30, "real chain: 40 soybeans -> 8 oil + 30 soy meal")
	while Sim.batch_running(press):
		t += 3600.0
		Sim.settle(state, data, t)
	Sim.collect(state, data, press.id, t)
	var oil_cost := float(state.inventory_cost.vegetable_oil)
	var meal_cost := float(state.inventory_cost.soy_meal)
	_check(absf(oil_cost + meal_cost - batch_cost) < 1.0 and absf(oil_cost - batch_cost * 0.6) < 1.0, "real chain: the oil carries 60% of the batch's cost, the meal 40%")
	t = _real_batch(state, data, factory, "make_chips", 2, t)
	_check(int(state.inventory.chips) == 60 and int(state.inventory.vegetable_oil) == 2, "real chain: 60 potatoes + 6 oil -> 60 chips")
	var made_for := float(state.inventory_cost.chips)
	t = _real_sell_out(state, data, market, "chips", t)
	_check(int(Sim.stats(state).sales_by_item.chips) > made_for, "real chain: chips sell for more than they cost to make")
	var sold := Sim.trade_sell(state, data, "soy_meal", 30, t)
	_check(sold.ok and int(sold.gross) == 30 * Sim.trade_price(data, "soy_meal", "sell") and not state.inventory.has("soy_meal"), "real chain: the soy meal sold to the trader")
	_check(Sim.cash_check(state).ok, "real chain: cash check adds up")


## Corn -> Animal Feed -> Cattle (a Ranch) -> Beef + Hides (a Slaughterhouse) -> Burgers (a Meat
## Plant) sold in the Supermarket; the hides (a by-product) go to the trader.
func test_real_chain_feed_to_burgers() -> void:
	var town := _real_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var t := T0
	_real_build(state, data, "wind_turbine", 7, t)
	var corn := _real_build(state, data, "wheat_farm", 8, t)
	var feed := _real_build(state, data, "feed_mill", 10, t)
	var ranch := _real_build(state, data, "ranch", 11, t)
	t += 3600.0
	Sim.settle(state, data, t)
	var slaughter := _real_build(state, data, "slaughterhouse", 13, t)
	var meat := _real_build(state, data, "meat_plant", 14, t)
	var market := _real_build(state, data, "supermarket", 16, t)
	_real_build(state, data, "trading_post", 17, t)
	t += 3600.0
	Sim.settle(state, data, t)
	t = _real_batch(state, data, corn, "grow_corn", 1, t)
	t = _real_batch(state, data, feed, "feed_from_corn", 1, t)
	_check(int(state.inventory.animal_feed) == 40, "real chain: 40 corn -> 40 animal feed")
	t = _real_batch(state, data, ranch, "raise_cattle", 1, t)
	_check(int(state.inventory.cattle) == 4, "real chain: 40 feed -> 4 cattle")
	_check(Sim.is_switchable(data, "ranch") and Sim.can_switch_product(state, data, ranch.id, "milk_cows").ok, "real chain: the ranch could switch to dairy cows, for a fee")
	t = _real_batch(state, data, slaughter, "slaughter_cattle", 1, t)
	_check(int(state.inventory.beef) == 40 and int(state.inventory.hide) == 4, "real chain: 4 cattle -> 40 beef + 4 hides")
	t = _real_batch(state, data, meat, "make_processed_meat", 1, t)
	_check(int(state.inventory.processed_meat) == 30, "real chain: 30 beef -> 30 burgers")
	var made_for := float(state.inventory_cost.processed_meat)
	t = _real_sell_out(state, data, market, "processed_meat", t)
	_check(int(Sim.stats(state).sales_by_item.processed_meat) > made_for, "real chain: burgers sell for more than they cost to make")
	_check(Sim.trade_sell(state, data, "hide", 4, t).ok and not state.inventory.has("hide"), "real chain: the hides sold to the trader")
	_check(Sim.cash_check(state).ok, "real chain: cash check adds up")


## Specialising: no plantation at all. Coffee beans bought from the trader, roasted in a
## Beverage Plant and sold in the Supermarket still earn more than they cost.
func test_real_chain_bought_beans_to_coffee() -> void:
	var town := _real_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var t := T0
	_real_build(state, data, "wind_turbine", 7, t)
	_real_build(state, data, "trading_post", 8, t)
	var plant := _real_build(state, data, "beverage_plant", 10, t)
	var market := _real_build(state, data, "supermarket", 11, t)
	t += 3600.0
	Sim.settle(state, data, t)
	var bought := Sim.trade_buy(state, data, "coffee_beans", 30, t)
	_check(bought.ok and int(bought.cost) == 30 * Sim.trade_price(data, "coffee_beans", "buy"), "real chain: 30 coffee beans bought from the trader at 150%")
	t = _real_batch(state, data, plant, "roast_coffee", 2, t)
	_check(int(state.inventory.coffee) == 30, "real chain: 30 beans -> 30 coffee")
	var made_for := float(state.inventory_cost.coffee)
	_check(made_for / 30.0 < Sim.unit_price(data, "coffee"), "real chain: even with bought beans, a coffee costs less to make than it sells for")
	t = _real_sell_out(state, data, market, "coffee", t)
	_check(int(Sim.stats(state).sales_by_item.coffee) > made_for, "real chain: the coffee earns more than it cost")
	_check(Sim.cash_check(state).ok, "real chain: cash check adds up")


# --- By-products (plan.md §5.14) -------------------------------------------------

## Test data with a butcher: 1 cattle ($9, bought) -> 9 beef + 1 hide an "hour" (60 s), the hide
## carrying 5% of the cost (cost_share). No workers, no build cost: a batch costs its cattle only.
func _butcher_data() -> Dictionary:
	var data := _data()
	data.resources["cattle"] = {"name": "Cattle", "price": 9}
	data.resources["beef"] = {"name": "Beef"}
	data.resources["hide"] = {"name": "Hide"}
	data.buildings["butcher"] = {"category": "processor", "build_cost": 0, "buildable": true,
		"recipes": [{"id": "cut", "inputs": {"cattle": 1}, "outputs": {"beef": 9, "hide": 1},
			"cost_share": {"beef": 0.95, "hide": 0.05}, "duration": 60}]}
	return data


## Prices split a batch's cost by cost_share; without one, every unit costs the same.
func test_cost_share_prices() -> void:
	var data := _butcher_data()
	_check(Sim.unit_price(data, "beef") == 95 and Sim.unit_price(data, "hide") == 45, "$9 of cattle: 9 beef share 95% ($0.95 each), 1 hide 5% ($0.45)")
	_check(is_equal_approx(Sim.standard_unit_cost(data, "beef"), 95.0) and is_equal_approx(Sim.standard_unit_cost(data, "hide"), 45.0), "the standard cost splits the same way")
	var shares := Sim.output_shares(data.buildings.butcher.recipes[0])
	_check(is_equal_approx(shares.beef, 0.95) and is_equal_approx(shares.hide, 0.05), "output_shares reads cost_share")
	data.buildings.butcher.recipes[0].erase("cost_share")
	_check(Sim.unit_price(data, "beef") == 90 and Sim.unit_price(data, "hide") == 90, "no cost_share: every unit costs the same ($9 / 10)")


## A batch's units carry their share as cost tags, the tags add up to the batch's cost, and
## cancelling keeps each unit's cost.
func test_cost_share_batch_tags() -> void:
	var data := _butcher_data()
	var state := Sim.new_game(data, T0)
	var butcher := Sim.find_building(state, Sim.build(state, data, "butcher", Vector2i(5, 5), T0).building_id)
	state.inventory["cattle"] = 6
	state["inventory_cost"] = {"cattle": 6000.0}  # $10 each
	var quote := Sim.batch_quote(state, data, butcher, "cut", 2, "none", T0)
	_check(is_equal_approx(float(quote.unit_costs.beef), 2000.0 * 0.95 / 18) and is_equal_approx(float(quote.unit_costs.hide), 2000.0 * 0.05 / 2), "the quote splits $20 of cattle: beef $1.06, hide $0.50 each")
	_check(is_equal_approx(float(quote.per_unit), float(quote.unit_costs.beef)) and int(quote.prices.hide) == 45, "per_unit is the main product's; each has its price")
	_check(_batch(state, data, butcher, 2).ok, "a 2-hour batch: 2 cattle -> 18 beef + 2 hides")
	var before := Sim.balance_sheet(state, data, T0)
	Sim.settle(state, data, T0 + 120)
	Sim.collect(state, data, butcher.id, T0 + 120)
	var tags: Dictionary = state.inventory_cost
	_check(is_equal_approx(float(tags.beef), 1900.0) and is_equal_approx(float(tags.hide), 100.0), "collected: beef carries $19, the hides $1")
	_check(int(Sim.balance_sheet(state, data, T0 + 120).company_value) == int(before.company_value), "making and collecting doesn't change the company's value")
	# Cancel a 4-hour batch after 1 hour: the hour made keeps its units' costs.
	_check(_batch(state, data, butcher, 4, "none", T0 + 120).ok, "a 4-hour batch")
	Sim.settle(state, data, T0 + 180)
	Sim.cancel_batch(state, data, butcher.id, T0 + 180)
	_check(int(butcher.batch.units.beef) == 9 and int(butcher.batch.units.hide) == 1, "cancelled after 1 hour: 9 beef + 1 hide kept")
	_check(is_equal_approx(float(butcher.batch.cost), 1000.0), "they keep their cost: $10 of cattle")
	_check(is_equal_approx(Sim.batch_unit_cost(butcher.batch, "hide"), 50.0), "a hide still costs $0.50")


## A batch started before by-products has no unit_cost: every unit of it costs the same.
func test_old_batch_without_unit_cost() -> void:
	var data := _butcher_data()
	var state := Sim.new_game(data, T0)
	var butcher := Sim.find_building(state, Sim.build(state, data, "butcher", Vector2i(5, 5), T0).building_id)
	state.inventory["cattle"] = 1
	state["inventory_cost"] = {"cattle": 1000.0}
	_batch(state, data, butcher, 1)
	butcher.batch.erase("unit_cost")
	_check(is_equal_approx(Sim.batch_unit_cost(butcher.batch, "hide"), 100.0), "no unit_cost: $10 / 10 units each")
	Sim.settle(state, data, T0 + 60)
	Sim.collect(state, data, butcher.id, T0 + 60)
	_check(is_equal_approx(float(state.inventory_cost.beef), 900.0) and is_equal_approx(float(state.inventory_cost.hide), 100.0), "collected at the even split")


# --- Product choice (plan.md §5.21) ----------------------------------------------

## Test data with two buildings that make one of two products: a "plot" (switchable for 50% of
## its $100 value) and a "kitchen" (no switch_fee: its first product is for good).
func _choice_data() -> Dictionary:
	var data := _data()
	data.buildings["plot"] = {"category": "extractor", "build_cost": 100, "buildable": true, "switch_fee": 0.5,
		"recipes": [{"id": "grow_wheat", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60},
			{"id": "grow_flour", "inputs": {}, "outputs": {"flour": 5}, "duration": 60}]}
	data.buildings["kitchen"] = {"category": "processor", "build_cost": 0, "buildable": true,
		"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 60},
			{"id": "toast", "inputs": {"wheat": 5}, "outputs": {"flour": 2}, "duration": 60}]}
	return data


## A new building hasn't chosen: its first batch chooses, and then it only makes that.
func test_first_batch_sets_product() -> void:
	var data := _choice_data()
	var state := Sim.new_game(data, T0)
	var plot := Sim.find_building(state, Sim.build(state, data, "plot", Vector2i(5, 5), T0).building_id)
	_check(Sim.product_of(data, plot) == "", "a new plot hasn't chosen yet")
	_check(Sim.batch_max_hours(state, data, plot.id, "grow_wheat", "none") > 0 and Sim.batch_max_hours(state, data, plot.id, "grow_flour", "none") > 0, "it could start either")
	_check(Sim.start_batch(state, data, plot.id, "grow_flour", 1, "none", T0).ok and Sim.product_of(data, plot) == "grow_flour", "its first batch chooses flour, for free")
	_check(state.profile.currency == 50000 - 10000, "only the plot itself was paid for")
	Sim.settle(state, data, T0 + 60)
	Sim.collect(state, data, plot.id, T0 + 60)
	var refused := Sim.can_start_batch(state, data, plot.id, "grow_wheat", 1, "none", T0 + 60)
	_check(not refused.ok and refused.error.contains("set up for Flour"), "now it only makes flour: wheat needs a switch")
	_check(Sim.batch_max_hours(state, data, plot.id, "grow_wheat", "none") == 0, "and the longest wheat batch is 0 h")
	_check(Sim.start_batch(state, data, plot.id, "grow_flour", 1, "none", T0 + 60).ok, "flour again is fine")


## A switchable building pays its switch_fee to change product, only while it has no batch.
func test_switch_product_fee() -> void:
	var data := _choice_data()
	var state := Sim.new_game(data, T0)
	var plot := Sim.find_building(state, Sim.build(state, data, "plot", Vector2i(5, 5), T0).building_id)
	_check(not Sim.can_switch_product(state, data, plot.id, "grow_flour").ok, "nothing chosen yet: nothing to switch")
	Sim.start_batch(state, data, plot.id, "grow_wheat", 1, "none", T0)
	var busy := Sim.switch_product(state, data, plot.id, "grow_flour", T0 + 10)
	_check(not busy.ok and busy.error.contains("batch") and Sim.product_of(data, plot) == "grow_wheat", "not while it has a batch")
	Sim.settle(state, data, T0 + 60)
	Sim.collect(state, data, plot.id, T0 + 60)
	_check(not Sim.can_switch_product(state, data, plot.id, "grow_wheat").ok, "switching to what it already makes is refused")
	_check(not Sim.can_switch_product(state, data, plot.id, "grow_gold").ok, "an unknown product is refused")
	_check(Sim.switch_fee(data, plot) == 5000, "the fee: 50% of its $100 value")
	var cash: int = state.profile.currency
	state.profile.currency = 4999
	var poor := Sim.switch_product(state, data, plot.id, "grow_flour", T0 + 60)
	_check(not poor.ok and poor.error.contains("$50") and state.profile.currency == 4999 and Sim.product_of(data, plot) == "grow_wheat", "short of cash: refused, and nothing changes")
	state.profile.currency = cash
	var switched := Sim.switch_product(state, data, plot.id, "grow_flour", T0 + 60)
	_check(switched.ok and int(switched.fee) == 5000 and state.profile.currency == cash - 5000, "switched to flour for $50")
	_check(Sim.product_of(data, plot) == "grow_flour" and int(Sim.stats(state).spending.switch_fees) == 5000, "it makes flour now; the fee is in the statistics")
	_check(Sim.start_batch(state, data, plot.id, "grow_flour", 1, "none", T0 + 60).ok, "and a flour batch can start")
	_check(Sim.cash_check(state).ok, "cash check adds up")


## A building without a switch_fee keeps its first product for good.
func test_fixed_product_cannot_switch() -> void:
	var data := _choice_data()
	var state := Sim.new_game(data, T0)
	var kitchen := Sim.find_building(state, Sim.build(state, data, "kitchen", Vector2i(5, 5), T0).building_id)
	state.inventory["wheat"] = 100
	_check(Sim.start_batch(state, data, kitchen.id, "toast", 1, "none", T0).ok, "its first batch chooses toast")
	Sim.settle(state, data, T0 + 60)
	Sim.collect(state, data, kitchen.id, T0 + 60)
	var refused := Sim.switch_product(state, data, kitchen.id, "mill", T0 + 60)
	_check(not refused.ok and refused.error.contains("for good") and Sim.product_of(data, kitchen) == "toast", "it can't switch: build another kitchen")
	_check(not Sim.can_start_batch(state, data, kitchen.id, "mill", 1, "none", T0 + 60).ok, "and can't start the other recipe")
	_check(not Sim.is_switchable(data, "kitchen") and Sim.is_switchable(data, "plot"), "is_switchable reads switch_fee")


## A version 12 save: every Farm, Mill and Bakery keeps what it was making (its running batch's
## recipe, else its first recipe), so an old mill doesn't get a free choice.
func test_old_save_gets_product() -> void:
	var data := _choice_data()
	var state := Sim.new_game(data, T0)
	var idle := Sim.find_building(state, Sim.build(state, data, "kitchen", Vector2i(5, 5), T0).building_id)
	var busy := Sim.find_building(state, Sim.build(state, data, "plot", Vector2i(6, 6), T0).building_id)
	Sim.start_batch(state, data, busy.id, "grow_flour", 2, "none", T0)
	var old := state.duplicate(true)
	old.save_version = 12
	for b in old.buildings:
		b.erase("product")
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	_check(result.ok and int(result.state.save_version) == Sim.SAVE_VERSION, "a version 12 save loads")
	var loaded_idle := Sim.find_building(result.state, idle.id)
	var loaded_busy := Sim.find_building(result.state, busy.id)
	_check(Sim.product_of(data, loaded_idle) == "mill", "an idle building keeps its first recipe")
	_check(Sim.product_of(data, loaded_busy) == "grow_flour", "a busy one keeps its batch's recipe")
	_check(Sim.product_of(data, Sim.find_building(result.state, state.buildings[0].id)) == "", "buildings that make nothing get no product")
	var round_trip := SaveFormat.from_text(SaveFormat.to_text(result.state, T0), data)
	_check(Sim.product_of(data, Sim.find_building(round_trip.state, busy.id)) == "grow_flour", "the product is kept in the save")


# --- Trading Post (plan.md §5.22) ------------------------------------------------

## Test data with a Trading Post (instant, no workers, one per village) whose trader pays half
## the normal price and charges double: wheat ($2) sells for $1 and costs $4; flour ($3): $1.50 / $6.
func _trade_data() -> Dictionary:
	var data := _data()
	data.buildings["post"] = {"name": "Trading Post", "category": "trade", "build_cost": 0, "buildable": true, "max_count": 1}
	data.config["trade"] = {"sell_share": 0.5, "buy_share": 2.0}
	return data


## [state, data] with a Trading Post built.
func _trade_town() -> Array:
	var data := _trade_data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "post", Vector2i(5, 5), T0)
	return [state, data]


func test_trade_needs_trading_post() -> void:
	var data := _trade_data()
	var state := Sim.new_game(data, T0)
	state.inventory["wheat"] = 10
	var refused := Sim.trade_sell(state, data, "wheat", 5, T0)
	_check(not refused.ok and refused.error.contains("Trading Post") and int(state.inventory.wheat) == 10, "no Trading Post: no trader, nothing changes")
	_check(not Sim.can_trade_buy(state, data, "flour", 1, T0).ok, "and nothing to buy")
	Sim.build(state, data, "post", Vector2i(5, 5), T0)
	_check(Sim.has_trading_post(state, data, T0) and Sim.can_trade_sell(state, data, "wheat", 5, T0).ok, "with one, the trader buys")


## Selling to the trader: half price, at once, paid like any sale (statistics, sales tax).
func test_trade_sell() -> void:
	var town := _trade_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	state.inventory["wheat"] = 10
	state["inventory_cost"] = {"wheat": 500.0}  # made for $0.50 each
	_check(Sim.trade_price(data, "wheat", "sell") == 100 and Sim.trade_price(data, "wheat", "buy") == 400, "wheat: the trader pays $1, charges $4")
	var preview := Sim.can_trade_sell(state, data, "wheat", 10, T0)
	_check(preview.ok and int(preview.gross) == 1000 and int(preview.cost) == 500 and int(preview.profit) == 500 and int(state.inventory.wheat) == 10, "the preview: $10 for 10, made for $5, $5 profit; nothing changes")
	var sold := Sim.trade_sell(state, data, "wheat", 10, T0)
	_check(sold.ok and int(sold.earned) == 1000 and state.profile.currency == 50000 + 1000, "sold 10 wheat for $10, cash at once")
	_check(int(state.inventory.get("wheat", 0)) == 0 and not state.inventory_cost.has("wheat"), "they left the warehouse with their cost tag")
	_check(int(Sim.stats(state).income.sales) == 1000 and int(Sim.stats(state).sold.wheat) == 10, "it's a sale in the statistics")
	_check(not Sim.trade_sell(state, data, "wheat", 1, T0).ok and not Sim.trade_sell(state, data, "wheat", 0, T0).ok, "can't sell what you don't have, or nothing")
	_check(Sim.cash_check(state).ok, "cash check adds up")


## Buying from the trader: double price, paid now, the goods carry what was paid; it needs the
## cash and room in the warehouse.
func test_trade_buy() -> void:
	var town := _trade_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var before := int(Sim.balance_sheet(state, data, T0).company_value)
	var bought := Sim.trade_buy(state, data, "flour", 5, T0)
	_check(bought.ok and int(bought.cost) == 3000 and state.profile.currency == 50000 - 3000, "5 flour at $6 each: $30")
	_check(int(state.inventory.flour) == 5 and is_equal_approx(float(state.inventory_cost.flour), 3000.0), "in the warehouse, carrying what was paid")
	_check(int(Sim.stats(state).spending.purchases) == 3000 and Sim.cash_check(state).ok, "counted as purchases; cash check adds up")
	_check(int(Sim.balance_sheet(state, data, T0).company_value) == before, "buying turns cash into goods: worth the same")
	state.profile.currency = 500
	var poor := Sim.trade_buy(state, data, "flour", 1, T0)
	_check(not poor.ok and poor.error.contains("$6") and state.profile.currency == 500 and int(state.inventory.flour) == 5, "short of cash: refused, nothing changes")
	state.profile.currency = 10000000
	var full := Sim.trade_buy(state, data, "wheat", 996, T0)
	_check(not full.ok and full.error.contains("room") and not state.inventory.has("wheat"), "no room for 996 more in a 1000 warehouse: refused")


## One Trading Post per village (max_count); after demolishing it, another can be built.
func test_trade_one_per_village() -> void:
	var town := _trade_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	_check(Sim.at_build_limit(state, data, "post") and not Sim.at_build_limit(state, data, "farm"), "one built: at its limit (farms have none)")
	var second := Sim.build(state, data, "post", Vector2i(6, 6), T0)
	_check(not second.ok and second.error.contains("already have") and state.buildings.size() == 4, "a second Trading Post is refused")
	var post := Sim.find_building(state, state.buildings[3].id)
	_check(Sim.demolish(state, data, post.id, T0).ok, "demolish it")
	_check(Sim.build(state, data, "post", Vector2i(6, 6), T0).ok, "then another can be built")


# --- Supermarket (plan.md §5.16) ------------------------------------------------

## Test data with a Supermarket ("market": 2 shelves, 2 workers at $36/hour). Flour and bread
## have an appetite (shops sell them), wheat doesn't. Nobody moves in by themselves, and there's
## no sales tax, so the sums stay simple.
func _shop_data() -> Dictionary:
	var data := _data()
	data.config["population_growth_seconds"] = 0
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	data.config["retail"] = {"variety_bonus": 0.5, "price_tags": {
		"sale": {"name": "Sale", "price": 0.5, "speed": 2.0},
		"normal": {"name": "Normal", "price": 1.0, "speed": 1.0},
		"luxury": {"name": "Luxury", "price": 2.0, "speed": 0.5}}}
	data.resources["flour"]["appetite"] = 1.0  # 10 people buy 10 flour an hour at the Normal price
	data.resources["bread"] = {"name": "Bread", "price": 5, "appetite": 2.0}  # 10 people: 20 an hour
	data.resources["cake"] = {"name": "Cake", "price": 9, "appetite": 1.0}
	data.buildings["market"] = {"category": "retail", "build_cost": 0, "buildable": true, "max_workers": 2,
		"worker_type": "low_skilled", "shelves": 2}
	return data


## 10 people, a Supermarket with both its workers, 100 each of flour, bread and cake in the
## warehouse. Returns [state, data, market].
func _shop_town() -> Array:
	var data := _shop_data()
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var market := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(5, 5), T0).building_id)
	for res in ["flour", "bread", "cake"]:
		state.inventory[res] = 100
	return [state, data, market]


func test_supermarket_sells_over_time() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	var result := Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	_check(result.ok and result.price == 300, "10 flour go on a shelf at the normal price ($3.00)")
	_check(int(state.inventory.flour) == 90, "they leave the warehouse at once")
	Sim.settle(state, data, T0 + 1800)
	_check(is_equal_approx(Sim.shelf_sold_now(state, data, market, 0, T0 + 1800), 5.0), "10 people buy 10 an hour: 5 sold after half an hour")
	_check(state.profile.currency == 50000 - 3600, "not paid yet, only the wages (2 x $36 for half an hour)")
	_check(is_equal_approx(Sim.shelf_time_left(state, data, market, 0, T0 + 1800), 1800.0), "half an hour left")
	Sim.settle(state, data, T0 + 3600)
	_check(Sim.shelves(data, market)[0].is_empty(), "sold out after an hour: the shelf is free again")
	_check(state.profile.currency == 50000 - 7200 + 3000, "paid when it sold out: 10 x $3.00")
	Sim.settle(state, data, T0 + 7200)
	_check(state.profile.currency == 50000 - 7200 + 3000, "empty shelves: the store is idle and pays no wages")
	_check(int(Sim.stats(state).sold.get("flour", 0)) == 10 and int(Sim.stats(state).income.sales) == 3000, "the sale is in the statistics")


func test_supermarket_price_tags() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	var preview := Sim.stock_preview(state, data, market.id, "flour", 10, "luxury", T0)
	_check(preview.price == 600 and preview.gross == 6000 and is_equal_approx(preview.seconds, 7200.0), "Luxury: twice the price, half the speed (10 flour in 2 hours)")
	preview = Sim.stock_preview(state, data, market.id, "flour", 10, "sale", T0)
	_check(preview.price == 150 and is_equal_approx(preview.seconds, 1800.0), "Sale: half the price, twice the speed")
	_check(Sim.stock_shelf(state, data, market.id, "flour", 10, "luxury", T0).ok, "(setup) flour on a Luxury shelf")
	Sim.settle(state, data, T0 + 7199)
	_check(not Sim.shelves(data, market)[0].is_empty(), "not sold out just before 2 hours")
	Sim.settle(state, data, T0 + 7201)
	_check(Sim.shelves(data, market)[0].is_empty() and state.profile.currency == 50000 - 14400 + 6000, "sold out at 2 hours for $60 (wages: $72/hour while selling)")


func test_supermarket_variety_brings_shoppers() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)  # 10 an hour alone
	Sim.stock_shelf(state, data, market.id, "bread", 10, "normal", T0)  # 20 an hour alone
	_check(is_equal_approx(Sim.shoppers(data, market), 1.5), "two products: +50% shoppers (this test's bonus)")
	# Together: flour 15/h, bread 30/h. Bread sells out after 20 minutes (flour: 5 sold); then
	# flour is alone again (10/h), so its last 5 take 30 minutes more: sold out at 50 minutes.
	Sim.settle(state, data, T0 + 1201)
	_check(Sim.shelves(data, market)[1].is_empty(), "bread sold out after 20 minutes")
	_check(absf(float(Sim.shelves(data, market)[0].sold) - 5.0) < 0.01, "5 flour sold by then")
	Sim.settle(state, data, T0 + 2999)
	_check(not Sim.shelves(data, market)[0].is_empty(), "flour slows down once it's alone: still selling at 49:59")
	Sim.settle(state, data, T0 + 3001)
	_check(Sim.shelves(data, market)[0].is_empty(), "flour sold out at 50 minutes")
	_check(state.profile.currency == 50000 - 6000 + 3000 + 5000, "both paid: $30 flour + $50 bread (wages for 50 minutes)")


func test_supermarket_rules() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	state.inventory["wheat"] = 50
	var check := Sim.can_stock_shelf(state, data, market.id, "wheat", 10, "normal", T0)
	_check(not check.ok and check.error.begins_with("Shops don't sell Wheat"), "raw wheat can't be sold in shops")
	_check(not Sim.can_stock_shelf(state, data, market.id, "flour", 0, "normal", T0).ok, "can't stock zero")
	_check(not Sim.can_stock_shelf(state, data, market.id, "flour", 101, "normal", T0).ok, "can't stock more than you have")
	_check(not Sim.can_stock_shelf(state, data, market.id, "flour", 10, "half_price", T0).ok, "unknown price tag")
	var farm_id: String = Sim.build(state, data, "farm", Vector2i(1, 1), T0).building_id
	_check(not Sim.can_stock_shelf(state, data, farm_id, "flour", 10, "normal", T0).ok, "only shops have shelves")
	_check(Sim.can_stock_shelf(state, data, market.id, "flour", 10, "normal", T0).ok, "flour can go on a shelf")
	_check(state.inventory.flour == 100, "asking changes nothing")
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	check = Sim.can_stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	_check(not check.ok and check.error.contains("already on a shelf in this store"), "a product goes on only one shelf per store")
	Sim.stock_shelf(state, data, market.id, "bread", 10, "normal", T0)
	check = Sim.can_stock_shelf(state, data, market.id, "cake", 10, "normal", T0)
	_check(not check.ok and check.error.begins_with("Every shelf is full"), "only as many products as shelves")
	var second := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(6, 6), T0).building_id)
	_check(Sim.can_stock_shelf(state, data, second.id, "flour", 10, "normal", T0).ok, "another store can sell the same product on its own")
	_check(Sim.can_stock_shelf(state, data, second.id, "cake", 10, "normal", T0).ok, "...or another product")
	state.population.current = 0
	check = Sim.can_stock_shelf(state, data, second.id, "cake", 10, "normal", T0)
	_check(not check.ok and check.error.begins_with("Nobody lives"), "nobody to buy without people")


func test_supermarket_workers() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	Sim.set_staffing(state, data, market.id, "low", T0)  # 1 of 2 workers
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	Sim.settle(state, data, T0 + 3601)
	_check(not Sim.shelves(data, market)[0].is_empty(), "half the workers: half the speed (not sold out after an hour)")
	Sim.settle(state, data, T0 + 7201)
	_check(Sim.shelves(data, market)[0].is_empty(), "sold out after 2 hours")
	_check(state.profile.currency == 50000 - 7200 + 3000, "1 worker paid for 2 hours, $30 earned")


func test_supermarket_away_matches_playing() -> void:
	var played: Dictionary = _shop_town()[0]
	var away: Dictionary = _shop_town()[0]
	var data := _shop_data()
	for state in [played, away]:
		var market_id: String = state.buildings[-1].id
		Sim.stock_shelf(state, data, market_id, "flour", 17, "sale", T0)
		Sim.stock_shelf(state, data, market_id, "bread", 23, "luxury", T0)
	var t := T0
	while t < T0 + 9000:
		t += 7.0
		Sim.settle(played, data, t)
	Sim.settle(away, data, t)
	_check(played.profile.currency == away.profile.currency, "one long absence pays exactly what playing in 7-second steps does")
	_check(_difference(played.buildings[-1], away.buildings[-1], "") == "", "and the shelves end up the same")
	var report: Dictionary = Sim.settle(_shop_town()[0], data, T0 + 60)  # nothing on the shelves
	_check(not report.has("store_sales"), "no sales when nothing is on the shelves")


## Two stores selling the same product: each sells on its own, sharing the village's appetite.
## 10 people buy 10 flour an hour; store A has 5 on its shelf, store B 10.
func _two_stores() -> Array:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var a: Dictionary = town[2]
	var b := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(6, 6), T0).building_id)
	Sim.stock_shelf(state, data, a.id, "flour", 5, "normal", T0)
	return [state, data, a, b]


func test_stores_share_a_product() -> void:
	var town := _two_stores()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var a: Dictionary = town[2]
	var b: Dictionary = town[3]
	var preview := Sim.stock_preview(state, data, b.id, "flour", 10, "normal", T0)
	_check(is_equal_approx(float(preview.per_hour), 5.0) and int(preview.other_stores) == 1, "preview: shared with the other store, 5 an hour")
	_check(Sim.stock_shelf(state, data, b.id, "flour", 10, "normal", T0).ok, "the second store puts flour on its own shelf")
	_check(int(Sim.selling_counts(state, data, T0).get("flour", 0)) == 2, "2 stores sell flour")
	Sim.settle(state, data, T0 + 1800)
	_check(is_equal_approx(Sim.shelf_sold_now(state, data, a, 0, T0 + 1800), 2.5) and is_equal_approx(Sim.shelf_sold_now(state, data, b, 0, T0 + 1800), 2.5), "they share the 10 an hour: 5 each")
	Sim.settle(state, data, T0 + 3600)
	_check(Sim.shelves(data, a)[0].is_empty() and is_equal_approx(Sim.shelf_sold_now(state, data, b, 0, T0 + 3600), 5.0), "A sells out after an hour, B has sold 5")
	_check(is_equal_approx(Sim.shelf_time_left(state, data, b, 0, T0 + 3600), 1800.0), "B now sells alone, at 10 an hour: 30 minutes left")
	Sim.settle(state, data, T0 + 5400)
	_check(Sim.shelves(data, b)[0].is_empty() and int(Sim.stats(state).sold.get("flour", 0)) == 15, "B sells out at 1.5 hours: 15 flour sold in all")
	_check(Sim.foods_selling(state, data, T0) <= 1, "the same food in two stores still counts as one food for happiness")


func test_stores_sharing_away_matches_playing() -> void:
	var played: Array = _two_stores()
	var away: Array = _two_stores()
	var data: Dictionary = played[1]
	for town in [played, away]:
		Sim.stock_shelf(town[0], data, town[3].id, "flour", 10, "sale", T0)
		Sim.stock_shelf(town[0], data, town[3].id, "bread", 23, "luxury", T0)
	var t := T0
	while t < T0 + 9000:
		t += 7.0
		Sim.settle(played[0], data, t)
	Sim.settle(away[0], data, t)
	_check(played[0].profile.currency == away[0].profile.currency, "two stores sharing flour: one long absence pays what playing in 7-second steps does")
	_check(_difference(played[0].buildings, away[0].buildings, "") == "", "and the shelves end up the same")


func test_supermarket_report() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	Sim.stock_shelf(state, data, town[2].id, "bread", 10, "normal", T0)
	var report: Dictionary = Sim.settle(state, data, T0 + 3600)
	_check(int(report.get("store_sales", 0)) == 5000 and int(report.get("sold:bread", 0)) == 10, "the settle report says what sold out and what it earned")
	_check(not report.has("bread") and not Sim.stats(state).made.has("bread"), "selling isn't counted as making")


func test_supermarket_clear_shelf() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	_check(not Sim.can_clear_shelf(state, data, market.id, 0).ok, "nothing to take down from an empty shelf")
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	Sim.settle(state, data, T0 + 1800)
	var check := Sim.can_clear_shelf(state, data, market.id, 0)
	_check(check.ok and check.sold == 5 and check.paid == 1500 and check.back == {"flour": 5}, "half sold: 5 paid for, 5 to come back")
	var result := Sim.clear_shelf(state, data, market.id, 0, T0 + 1800)
	_check(result.ok and result.earned == 1500 and int(state.inventory.flour) == 95, "taking it down pays for the 5 sold and brings back the rest")
	_check(Sim.shelves(data, market)[0].is_empty() and Sim.is_idle(data, market), "the shelf is free and the store idle")


func test_supermarket_keeps_cost_tags() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	state["inventory_cost"] = {"flour": 2000.0}  # 100 flour that cost $20 to make: 20 cents each
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	_check(is_equal_approx(float(state.inventory_cost.flour), 1800.0), "the shelf takes its goods' cost tags along")
	Sim.settle(state, data, T0 + 1800)
	Sim.clear_shelf(state, data, market.id, 0, T0 + 1800)
	_check(is_equal_approx(float(state.inventory_cost.flour), 1900.0), "the unsold half comes back with its cost")


func test_supermarket_demolish_and_suspend() -> void:
	for action in ["demolish", "suspend"]:
		var town := _shop_town()
		var state: Dictionary = town[0]
		var data: Dictionary = town[1]
		var market: Dictionary = town[2]
		Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
		Sim.settle(state, data, T0 + 1800)
		var cash: int = state.profile.currency
		var result: Dictionary = Sim.demolish(state, data, market.id, T0 + 1800) if action == "demolish" else Sim.suspend(state, data, market.id, T0 + 1800)
		_check(result.ok and int(state.inventory.flour) == 95, "%s: the unsold flour goes back to the warehouse" % action)
		var refund := int(result.get("money", 0))
		_check(state.profile.currency == cash + 1500 + refund, "%s: the 5 already sold are paid for" % action)
		if action == "suspend":
			_check(Sim.shelves(data, market)[0].is_empty() and Sim.is_suspended(market), "suspended with empty shelves")


func test_supermarket_clock_moved_backwards() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	Sim.settle(state, data, T0 + 1800)
	Sim.settle(state, data, T0 + 100)  # the clock went back
	_check(is_equal_approx(float(Sim.shelves(data, market)[0].sold), 5.0), "a clock set back never un-sells anything")
	Sim.settle(state, data, T0 + 3601)
	_check(Sim.shelves(data, market)[0].is_empty() and int(Sim.stats(state).sold.flour) == 10, "and it still sells out once, paid once")


func test_supermarket_save_round_trip() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	Sim.stock_shelf(state, data, town[2].id, "bread", 10, "luxury", T0)
	Sim.settle(state, data, T0 + 333.3)
	var result := SaveFormat.from_text(SaveFormat.to_text(state, T0 + 333.3), data)
	_check(result.ok, "a save with stocked shelves loads")
	var loaded: Dictionary = result.state
	Sim.settle(state, data, T0 + 9000)
	Sim.settle(loaded, data, T0 + 9000)
	_check(_difference(state, loaded, "") in ["", "last_saved_at"], "the loaded shelves go on selling exactly the same")


## A store with fixed workers (like the real Supermarket): no staffing or bonus choice, it waits
## its turn for free people, and short of people it sells slower.
func test_supermarket_fixed_workers() -> void:
	var data := _shop_data()
	data.buildings.market["fixed_workers"] = true
	data.buildings.market["fixed_wage"] = true
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var market := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(5, 5), T0).building_id)
	state.inventory["flour"] = 100
	_check(not Sim.can_set_staffing(state, data, market.id, "low").ok, "fixed workers: no Low / Medium / High choice")
	_check(not Sim.can_set_bonus(state, data, market.id, "big").ok, "fixed wage: no bonus")
	_check(not Sim.is_staffed_first(data, market), "it isn't staffed first: it waits its turn")
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)  # 10 people: 10 an hour
	state.population.current = 1  # then people move away: one person left for its 2 posts
	Sim._hire(state, data, T0)
	Sim.settle(state, data, T0 + 3601)
	_check(not Sim.shelves(data, market)[0].is_empty(), "1 of 2 workers: half speed, not sold out after an hour")
	Sim.settle(state, data, T0 + 7201)
	_check(Sim.shelves(data, market)[0].is_empty(), "sold out after 2 hours")


# --- Needs & happiness (plan.md §5.6) ----------------------------------------------

## Shop test data with needs switched on: Food (0 / 1 / 2+ foods selling = 0 / 70% / 100%) and
## Jobs, half and half; needs count from 10 people; a big house with room for 100 more, and
## people moving in every 10 s at normal speed.
func _needs_data() -> Dictionary:
	var data := _shop_data()
	data.config["population_growth_seconds"] = 10
	data.config["happiness"] = {"needs_from_population": 10, "food_scores": [0.0, 0.7, 1.0],
		"weights": {"food": 0.5, "jobs": 0.5},
		"growth_speeds": [{"from": 0, "speed": 0.0}, {"from": 0.2, "speed": 0.5}, {"from": 0.5, "speed": 1.0}, {"from": 0.8, "speed": 1.5}]}
	data.buildings["big_house"] = {"category": "residential", "build_cost": 0, "buildable": true, "households": 50}
	return data


func test_happiness_score() -> void:
	var plain := _data()
	var happy := Sim.happiness(Sim.new_game(plain, T0), plain, T0)
	_check(happy.score == 1.0 and happy.growth_speed == 1.0, "no happiness block in the config: no needs, normal speed")
	var data := _needs_data()
	var state := Sim.new_game(data, T0)
	state.population.current = 5
	happy = Sim.happiness(state, data, T0)
	_check(not happy.needs_count and happy.score == 1.0 and happy.growth_speed == 1.5, "5 people: a small village doesn't complain (100%, x1.5)")
	state.population.current = 10
	happy = Sim.happiness(state, data, T0)
	_check(happy.needs_count and happy.food == 0.0 and happy.jobs == 0.0 and happy.growth_speed == 0.0, "10 people, no food, no jobs: 0%, nobody moves in")
	var market := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(5, 5), T0).building_id)
	state.inventory["flour"] = 100
	state.inventory["bread"] = 100
	Sim.stock_shelf(state, data, market.id, "flour", 100, "normal", T0)
	Sim._hire(state, data, T0)
	happy = Sim.happiness(state, data, T0)
	_check(happy.foods == 1 and is_equal_approx(happy.food, 0.7) and is_equal_approx(happy.jobs, 0.2), "one food selling (70%), 2 of 10 people work (20%)")
	_check(is_equal_approx(happy.score, 0.45) and happy.growth_speed == 0.5, "45%: half speed")
	Sim.stock_shelf(state, data, market.id, "bread", 100, "normal", T0)
	happy = Sim.happiness(state, data, T0)
	_check(happy.foods == 2 and is_equal_approx(happy.score, 0.6) and happy.growth_speed == 1.0, "two foods (100%): 60%, normal speed")
	Sim.build(state, data, "crew_farm", Vector2i(6, 6), T0)
	Sim.build(state, data, "crew_mill", Vector2i(7, 7), T0)
	Sim._hire(state, data, T0)
	happy = Sim.happiness(state, data, T0)
	_check(is_equal_approx(happy.jobs, 0.7) and is_equal_approx(happy.score, 0.85) and happy.growth_speed == 1.5, "7 of 10 work: 85%, x1.5")
	state.population.current = 7  # 3 people moved away: everyone left has a job...
	Sim._hire(state, data, T0)
	_check(Sim.happiness(state, data, T0).score == 1.0, "...but below 10 people needs don't count")
	state.population.current = 10
	Sim._hire(state, data, T0)
	market.hired = 0  # a store with nobody working sells nothing, so feeds nobody
	_check(Sim.foods_selling(state, data, T0) == 0, "no workers at the store: no food selling")


## Stores sell the item categories in their "sells" list (plan.md §5.16); a store without that
## list sells anything people buy. Items without a category but with an appetite count as food.
func test_store_sells_only_its_categories() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	data.resources["shirt"] = {"name": "Shirt", "price": 20, "appetite": 1.0, "category": "clothing"}
	data.buildings["grocer"] = data.buildings.market.duplicate()
	data.buildings.grocer["sells"] = ["food"]
	state.inventory["shirt"] = 50
	_check(Sim.item_category(data, "flour") == "food" and Sim.item_category(data, "wheat") == "" and Sim.item_category(data, "shirt") == "clothing", "flour (bought, no category) is food; wheat has no category")
	_check(Sim.store_sells(data, "grocer", "flour") and not Sim.store_sells(data, "grocer", "shirt"), "a grocer selling food sells flour, not shirts")
	_check(not Sim.store_sells(data, "grocer", "wheat") and not Sim.store_sells(data, "market", "wheat"), "nobody buys wheat, whatever the store")
	_check(Sim.store_sells(data, "market", "shirt"), "a store with no 'sells' list sells anything people buy")
	_check(Sim.store_products(data, "grocer") == ["flour", "bread", "cake"], "the grocer's products, in data order")
	var grocer := Sim.find_building(state, Sim.build(state, data, "grocer", Vector2i(6, 6), T0).building_id)
	Sim._hire(state, data, T0)
	var refused := Sim.stock_shelf(state, data, grocer.id, "shirt", 10, "normal", T0)
	_check(not refused.ok and refused.error.contains("doesn't sell") and int(state.inventory.shirt) == 50, "shirts can't go on the grocer's shelves, and nothing changes")
	_check(Sim.stock_shelf(state, data, market.id, "shirt", 10, "normal", T0).ok, "they can in the market")


## The Food need counts only food on shelves, and more different foods count for more
## (happiness.food_scores, the last number for that many or more).
func test_food_need_counts_only_food() -> void:
	var data := _needs_data()
	data.config.happiness["food_scores"] = [0.0, 0.4, 0.6, 1.0]
	data.buildings.market["shelves"] = 5
	data.resources["shirt"] = {"name": "Shirt", "price": 20, "appetite": 1.0, "category": "clothing"}
	data.resources["pie"] = {"name": "Pie", "price": 7, "appetite": 1.0, "category": "food"}
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var market := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(5, 5), T0).building_id)
	for res in ["flour", "bread", "cake", "pie", "shirt"]:
		state.inventory[res] = 100
	Sim._hire(state, data, T0)
	Sim.stock_shelf(state, data, market.id, "shirt", 100, "normal", T0)
	_check(Sim.foods_selling(state, data, T0) == 0 and Sim.happiness(state, data, T0).food == 0.0, "shirts on a shelf feed nobody: 0 foods")
	_check(Sim.selling_counts(state, data, T0).has("shirt"), "but they are selling (they still share shoppers)")
	Sim.stock_shelf(state, data, market.id, "flour", 100, "normal", T0)
	_check(Sim.foods_selling(state, data, T0) == 1 and is_equal_approx(Sim.happiness(state, data, T0).food, 0.4), "1 food: 40%")
	Sim.stock_shelf(state, data, market.id, "bread", 100, "normal", T0)
	_check(is_equal_approx(Sim.happiness(state, data, T0).food, 0.6), "2 foods: 60%")
	Sim.stock_shelf(state, data, market.id, "cake", 100, "normal", T0)
	_check(is_equal_approx(Sim.happiness(state, data, T0).food, 1.0), "3 foods: 100%")
	Sim.stock_shelf(state, data, market.id, "pie", 100, "normal", T0)
	_check(Sim.foods_selling(state, data, T0) == 4 and is_equal_approx(Sim.happiness(state, data, T0).food, 1.0), "4 foods: still 100% (the last score is for that many or more)")


## Happiness changes how fast people move in, and settling follows it exactly while away.
func test_happiness_move_in_speed() -> void:
	var data := _needs_data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "big_house", Vector2i(3, 3), T0)
	state.population.current = 10
	state.inventory["flour"] = 100
	var market := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(5, 5), T0).building_id)
	Sim.build(state, data, "crew_farm", Vector2i(6, 6), T0)
	Sim.build(state, data, "crew_mill", Vector2i(7, 7), T0)
	Sim.stock_shelf(state, data, market.id, "flour", 100, "normal", T0)  # sells for 10 hours
	var away := state.duplicate(true)
	# Food 70% and 7 jobs: happiness = 35% + 3.5 / people. Normal speed (10 s) while it's 50% or
	# more, i.e. up to 23 people; the 24th arrives at T0 + 140, then it's half speed (20 s).
	Sim.settle(state, data, T0 + 140)
	_check(int(state.population.current) == 24, "one person every 10 s while happiness is 50% or more")
	Sim.settle(state, data, T0 + 159)
	_check(int(state.population.current) == 24, "below 50%: the next one waits 20 s")
	Sim.settle(state, data, T0 + 160)
	_check(int(state.population.current) == 25, "...and arrives at T0 + 160")
	var played := away.duplicate(true)
	var t := T0
	while t < T0 + 400:
		t = minf(t + 7.0, T0 + 400)
		Sim.settle(played, data, t)
	Sim.settle(away, data, T0 + 400)
	_check(int(away.population.current) == 37 and int(played.population.current) == 37, "one long absence = playing in 7-second steps (37 people after 400 s)")


## Nobody moves in at 0%; once food and jobs come, the wait for the next person starts from then.
func test_happiness_stops_and_restarts_growth() -> void:
	var data := _needs_data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "big_house", Vector2i(3, 3), T0)
	state.population.current = 10
	Sim.settle(state, data, T0 + 1000)
	_check(int(state.population.current) == 10, "no food and no jobs: nobody moves in")
	var market := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(5, 5), T0 + 1000).building_id)
	state.inventory["flour"] = 100
	Sim.stock_shelf(state, data, market.id, "flour", 100, "normal", T0 + 1000)  # 45%: half speed
	Sim.settle(state, data, T0 + 1019)
	_check(int(state.population.current) == 10, "the 20-second wait starts when the store opens, not before")
	Sim.settle(state, data, T0 + 1020)
	_check(int(state.population.current) == 11, "the first person arrives 20 s after the store opens")


# --- Job seekers (move_in_only_for_jobs, plan.md §5.6) -------------------------------

## Test data where newcomers are job seekers: one every 10 s, only for open jobs, only while
## a home has room (the starting house: room for 10 adults). Nobody lives here at the start.
func _seeker_data() -> Dictionary:
	var data := _data()
	data.config["move_in_only_for_jobs"] = true
	return data


func test_job_seekers_fill_open_jobs() -> void:
	var data := _seeker_data()
	var state := Sim.new_game(data, T0)
	Sim.settle(state, data, T0 + 1000)
	_check(int(state.population.current) == 0, "no jobs: no job seekers, however long you wait")
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0 + 1000).building_id)
	Sim.settle(state, data, T0 + 1009)
	_check(int(state.population.current) == 0, "the 10-second wait starts when the jobs open")
	Sim.settle(state, data, T0 + 1010)
	_check(int(state.population.current) == 1, "the first job seeker arrives 10 s after the jobs open")
	Sim.settle(state, data, T0 + 2000)
	_check(int(state.population.current) == 2 and Sim.hired(farm) == 2, "2 jobs: 2 job seekers, both hired, then nobody else")
	_check(int(Sim.people_stats(state).moved_in) == 2, "they count as moved in")
	Sim.build(state, data, "crew_mill", Vector2i(6, 6), T0 + 2000)
	Sim.build(state, data, "crew_mill", Vector2i(7, 7), T0 + 2000)
	Sim.build(state, data, "crew_mill", Vector2i(8, 8), T0 + 2000)
	_check(is_equal_approx(Sim.next_arrival_at(state, data, T0 + 2000), T0 + 2010), "next_arrival_at: 10 s after the new jobs open")
	Sim.settle(state, data, T0 + 9000)
	_check(int(state.population.current) == 10, "11 jobs but room for 10 adults: they stop when the homes are full")
	_check(is_inf(Sim.next_arrival_at(state, data, T0 + 9000)), "next_arrival_at: none while the homes are full")


## With move_in_group_size, job seekers arrive together: up to a full group each time, but never
## more than the open jobs (or the homes) allow. Time away = playing through.
func test_job_seekers_arrive_in_groups() -> void:
	var data := _seeker_data()
	data.config["move_in_group_size"] = 5
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0)  # 2 jobs
	_check(Sim.next_arrival_count(state, data, T0) == 2, "2 jobs open: the next group brings only 2")
	Sim.settle(state, data, T0 + 10)
	_check(int(state.population.current) == 2, "...and they arrive together after 10 s")
	_check(Sim.next_arrival_count(state, data, T0 + 10) == 0, "jobs filled: nobody else is coming")
	for cell in [Vector2i(6, 6), Vector2i(7, 7), Vector2i(8, 8)]:
		Sim.build(state, data, "crew_mill", cell, T0 + 10)  # 9 more jobs, room for only 8 more adults
	var played := state.duplicate(true)
	_check(Sim.next_arrival_count(state, data, T0 + 10) == 5, "9 jobs open: a full group of 5 comes next")
	Sim.settle(state, data, T0 + 19)
	_check(int(state.population.current) == 2, "nobody before the 10 s are up")
	Sim.settle(state, data, T0 + 20)
	_check(int(state.population.current) == 7 and int(Sim.people_stats(state).moved_in) == 7, "5 arrive at once")
	_check(Sim.next_arrival_count(state, data, T0 + 20) == 3, "room for only 3 more adults: the next group is 3")
	Sim.settle(state, data, T0 + 100)
	_check(int(state.population.current) == 10, "then 3 more: the homes are full")
	var t := T0 + 10
	while t < T0 + 100:
		t = minf(t + 3.0, T0 + 100)
		Sim.settle(played, data, t)
	_check(int(played.population.current) == 10 and str(Sim.people_stats(played)) == str(Sim.people_stats(state)), "playing in 3-second steps gives the same")


## Adults already here take open jobs first; job seekers only come for the rest.
func test_job_seekers_come_after_the_unemployed() -> void:
	var data := _seeker_data()
	var state := Sim.new_game(data, T0)
	state.population.current = 3
	Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0)  # 2 jobs: 1 adult left without one
	Sim.settle(state, data, T0 + 1000)
	_check(int(state.population.current) == 3, "an adult is out of work: no job seekers")
	Sim.build(state, data, "crew_mill", Vector2i(6, 6), T0 + 1000)  # 3 more jobs: 1 for him, 2 open
	Sim.settle(state, data, T0 + 2000)
	var e := Sim.employment(state, data, T0 + 2000)
	_check(int(state.population.current) == 5 and int(e.unemployed) == 0 and int(e.open_jobs) == 0, "2 job seekers for the 2 jobs nobody here could take")


## Happiness bands set the job seekers' speed (move_in) apart from the babies' speed.
func test_job_seekers_need_happiness() -> void:
	var data := _seeker_data()
	data.config["happiness"] = {"needs_from_population": 0, "food_scores": [0.0, 1.0], "weights": {"food": 1},
		"growth_speeds": [{"from": 0, "speed": 0.5, "move_in": 0.0}, {"from": 0.5, "speed": 1.0}]}
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0)
	var happy := Sim.happiness(state, data, T0)
	_check(happy.move_in_speed == 0.0 and happy.growth_speed == 0.5, "no food: babies at half speed, no job seekers")
	Sim.settle(state, data, T0 + 1000)
	_check(int(state.population.current) == 0 and is_inf(Sim.next_arrival_at(state, data, T0 + 1000)), "too unhappy: open jobs stay open")
	data.config.happiness.weights = {}  # nothing counts: 100%, the top band (no move_in: same as speed)
	_check(Sim.happiness(state, data, T0 + 1000).move_in_speed == 1.0, "a band without move_in uses its birth speed")
	Sim.settle(state, data, T0 + 1000.5)  # happiness is read at the start of each piece of time
	Sim.settle(state, data, T0 + 1011)
	_check(int(state.population.current) == 1, "happy again: the wait starts over and the first one comes")


## Job seekers while away = playing through it, with jobs and homes opening partway.
func test_job_seekers_away_matches_playing() -> void:
	var data := _seeker_data()
	data.buildings.slow_farm["max_workers"] = 2
	var played := Sim.new_game(data, T0)
	for x in 3:
		Sim.build(played, data, "crew_mill", Vector2i(x, 5), T0)
	Sim.build(played, data, "crew_farm", Vector2i(4, 5), T0)
	Sim.build(played, data, "slow_farm", Vector2i(5, 5), T0)  # 2 jobs from T0 + 5
	Sim.build(played, data, "cabin", Vector2i(8, 8), T0)  # room for 6 more adults from T0 + 200
	var away := played.duplicate(true)
	var t := T0
	while t < T0 + 3000:
		t += 7.0
		Sim.settle(played, data, t)
	Sim.settle(away, data, t)
	_check(int(away.population.current) == 13, "13 jobs, room for 16: 13 job seekers")
	var same: bool = played.population.current == away.population.current and played.profile.currency == away.profile.currency
	same = same and is_equal_approx(float(played.population.growth_anchor), float(away.population.growth_anchor))
	for i in played.buildings.size():
		same = same and Sim.hired(played.buildings[i]) == Sim.hired(away.buildings[i]) and played.buildings[i].storage == away.buildings[i].storage
	_check(same, "one long absence = playing in 7-second steps (people, hired, storage, cash)")
	var halfway := Sim.new_game(data, T0)
	for x in 3:
		Sim.build(halfway, data, "crew_mill", Vector2i(x, 5), T0)
	Sim.settle(halfway, data, T0 + 100)
	_check(int(halfway.population.current) == 9, "9 jobs: 9 job seekers, one every 10 s (the last at T0 + 90)")


## Migrant workers who don't need a home (move_in_needs_home false): 10 adults fill the starting
## house (room for 10), so migrants for the open jobs live in Makeshift Huts.
func _migrant_data() -> Dictionary:
	var data := _seeker_data()
	data.config["move_in_needs_home"] = false
	data.buildings["hut"] = {"category": "residential", "build_cost": 0, "buildable": false, "households": 1, "hut": true}
	return data


## 10 adults in a full house, 14 jobs (4 mills + a farm): 4 posts open. Returns the state.
func _migrant_town(data: Dictionary) -> Dictionary:
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	for x in 4:
		Sim.build(state, data, "crew_mill", Vector2i(x, 5), T0)
	Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0)
	return state


func _huts(state: Dictionary) -> int:
	return state.buildings.filter(func(b): return b.type == "hut").size()


func test_migrants_live_in_huts() -> void:
	var data := _migrant_data()
	var state := _migrant_town(data)
	Sim.settle(state, data, T0 + 39)
	_check(int(state.population.current) == 13, "homes full, jobs open: migrants still come, one every 10 s")
	Sim.settle(state, data, T0 + 1000)
	var e := Sim.employment(state, data, T0 + 1000)
	_check(int(state.population.current) == 14 and int(e.open_jobs) == 0, "they stop when every job is filled (14 adults, 14 jobs)")
	var homes := Sim.housing(state, data, T0 + 1000)
	_check(int(homes.homeless) == 2 and _huts(state) == 2, "7 households, room for 5: 2 live in Makeshift Huts")
	_check(is_inf(Sim.next_arrival_at(state, data, T0 + 1000)), "next_arrival_at: none once the jobs are filled")
	var needs := _migrant_data()
	needs.config["move_in_needs_home"] = true
	var housed := _migrant_town(needs)
	Sim.settle(housed, needs, T0 + 1000)
	_check(int(housed.population.current) == 10, "move_in_needs_home true: nobody comes while the homes are full")


## Huts lower the Housing need; below the move-in band migrants stop coming.
func test_migrants_stop_when_unhappy() -> void:
	var data := _migrant_data()
	data.config["happiness"] = {"needs_from_population": 0, "weights": {"housing": 1},
		"growth_speeds": [{"from": 0, "speed": 0.0, "move_in": 0.0}, {"from": 0.8, "speed": 1.0}]}
	var state := _migrant_town(data)
	Sim.settle(state, data, T0 + 1000)
	# 12 adults = 6 households, 1 in a hut: 83%, still coming. 13 adults = 7 households, 2 in huts: 71%.
	_check(int(state.population.current) == 13, "the 13th migrant brings happiness under 80%: no more come (13 people)")
	_check(is_inf(Sim.next_arrival_at(state, data, T0 + 1000)), "next_arrival_at: none while too unhappy, though a job is open")


## Migrants and huts while away = playing through it; a new home later takes them out of the huts.
func test_migrants_away_matches_playing() -> void:
	var data := _migrant_data()
	var played := _migrant_town(data)
	Sim.build(played, data, "cabin", Vector2i(8, 8), T0)  # room for 3 more households from T0 + 200
	var away := played.duplicate(true)
	var t := T0
	while t < T0 + 3000:
		t += 7.0
		Sim.settle(played, data, t)
	Sim.settle(away, data, t)
	var same: bool = played.population.current == away.population.current and played.profile.currency == away.profile.currency
	same = same and played.buildings.size() == away.buildings.size()
	for i in mini(played.buildings.size(), away.buildings.size()):
		same = same and played.buildings[i].type == away.buildings[i].type and Sim.hired(played.buildings[i]) == Sim.hired(away.buildings[i])
	_check(same, "one long absence = playing in 7-second steps (people, buildings, hired, cash)")
	_check(int(away.population.current) == 14 and _huts(away) == 0 and _huts(played) == 0, "once the cabin is built, the migrants leave their huts for real homes")


# --- Births, children & deaths (plan.md §5.6) ----------------------------------------

## Test data with births and deaths and no immigration: 10 founding adults in the starting house
## (room 10), a buildable "big_house" (room 100) and "home" (room 10), both ready at once.
## `birth` and `death` are per person per hour; children grow up after 2 hours, one age group
## per hour.
func _life_data(birth: float, death: float) -> Dictionary:
	var data := _data()
	data.config["population_growth_seconds"] = 0
	data.config["starting_population"] = 10
	data.config["life"] = {"birth_rate_per_hour": birth, "death_rate_per_hour": death, "grow_up_hours": 2, "child_group_hours": 1}
	data.buildings["big_house"] = {"category": "residential", "build_cost": 0, "buildable": true, "households": 50}
	data.buildings["home"] = {"category": "residential", "build_cost": 0, "buildable": true, "households": 5}
	return data


func test_starting_population() -> void:
	var data := _data()
	data.config["starting_population"] = 25
	data.config.starting_buildings.append({"type": "crew_store", "position": [3, 0]})
	var state := Sim.new_game(data, T0)
	_check(int(state.population.current) == 10, "the founders never outnumber the starting homes (25 asked, room for 10)")
	_check(Sim.adults(state) == 10 and Sim.children_count(state) == 0, "the founders are all adults")
	_check(Sim.hired(state.buildings[3]) == 4, "the starting warehouse is staffed at once")
	_check(int(Sim.new_game(_data(), T0).population.current) == 0, "no starting_population: an empty village, as before")


func test_births_and_growing_up() -> void:
	var data := _life_data(0.1, 0.0)  # 10 adults: one baby an hour
	var state := Sim.new_game(data, T0)
	Sim.settle(state, data, T0 + 3599)
	_check(int(state.population.current) == 10, "no baby before the first hour is up")
	var report := Sim.settle(state, data, T0 + 3601)
	_check(int(state.population.current) == 11 and Sim.children_count(state) == 1 and Sim.adults(state) == 10, "a baby after an hour: a child, not an adult")
	_check(int(report.get("born", 0)) == 1, "the report counts the birth")
	var grows_up := float(Sim.children_groups(state)[0].grows_up_at)
	_check(grows_up > T0 + 3601 and grows_up <= T0 + 3600 + 7200, "it grows up within 2 hours of being born")
	Sim.settle(state, data, grows_up - 1.0)
	_check(Sim.children_count(state) == 2 and Sim.adults(state) == 10, "a second baby, and nobody has grown up yet")
	report = Sim.settle(state, data, grows_up)
	_check(Sim.adults(state) == 11 and Sim.children_count(state) == 1 and int(report.get("grew_up", 0)) == 1, "the first child grows up right on time")
	_check(int(Sim.people_stats(state).born) == 2 and int(Sim.people_stats(state).grew_up) == 1, "lifetime counters")


func test_deaths_in_proportion() -> void:
	var data := _life_data(0.0, 0.1)  # 10% of each group an hour
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "big_house", Vector2i(5, 5), T0)
	state.population.current = 20
	state.population.children = [{"count": 5, "grows_up_at": T0 + 90000}, {"count": 5, "grows_up_at": T0 + 93600}]
	var report := Sim.settle(state, data, T0 + 3601)
	_check(Sim.adults(state) == 9 and Sim.children_count(state) == 9, "10 adults and 10 children: one of each died in an hour")
	_check(int(Sim.children_groups(state)[1].count) == 4 and int(Sim.children_groups(state)[0].count) == 5, "the child came from the youngest group")
	_check(int(report.get("died", 0)) == 2 and int(Sim.people_stats(state).died) == 2, "deaths are counted")
	# Everyone works: an adult who dies leaves a post open.
	var town := Sim.new_game(_life_data(0.0, 0.5), T0)
	var farm := Sim.find_building(town, Sim.build(town, _life_data(0.0, 0.5), "crew_farm", Vector2i(5, 5), T0).building_id)
	town.population.current = 2
	Sim._hire(town, _life_data(0.0, 0.5), T0)
	Sim.settle(town, _life_data(0.0, 0.5), T0 + 3601)  # 2 adults x 50% an hour: one dies
	_check(Sim.adults(town) == 1 and Sim.hired(farm) == 1, "a worker died: the farm has one worker left")


## Babies need a free child place: 2 per family (household). A house isn't needed: homeless
## families have child places and babies too.
func test_babies_need_a_child_place() -> void:
	var data := _life_data(0.1, 0.0)
	var state := Sim.new_game(data, T0)  # room for 5 households in the house
	state.population.current = 28  # 14 adults (7 households, 2 of them homeless) + 14 children
	state.population.children = [{"count": 14, "grows_up_at": T0 + 900000}]
	_check(int(Sim.housing(state, data, T0).homeless) == 2, "2 households have no home")
	_check(int(Sim.housing(state, data, T0).child_places) == 14, "7 families x 2: the homeless have child places too")
	Sim.settle(state, data, T0 + 36000)
	_check(int(Sim.people_stats(state).born) == 0, "every family has 2 children: no babies, however long")
	var homeless := Sim.new_game(data, T0)
	homeless.population.current = 24  # 14 adults + 10 children: the homeless families have room
	homeless.population.children = [{"count": 10, "grows_up_at": T0 + 900000}]
	Sim.settle(homeless, data, T0 + 3600)
	_check(int(Sim.people_stats(homeless).born) >= 1, "families without a house still have babies")
	# All adults have babies, housed or not: 14 adults, room in homes for 10, no children yet.
	var crowded := Sim.new_game(data, T0)
	crowded.population.current = 14
	_check(is_equal_approx(Sim.next_birth_at(crowded, data, T0), T0 + 3600.0 / 1.4), "14 adults x 0.1 an hour: a baby in 1/1.4 of an hour (the 4 homeless count too)")


## Demolishing a home: nobody leaves. Its households move into other homes, or become homeless
## and put up Makeshift Huts, which go again once there's a home for them.
func test_demolish_home_makes_huts() -> void:
	var data := _life_data(0.0, 0.0)
	data.buildings["hut"] = {"category": "residential", "build_cost": 0, "buildable": false, "households": 1, "hut": true}
	var state := Sim.new_game(data, T0)
	var home := Sim.find_building(state, Sim.build(state, data, "home", Vector2i(5, 5), T0).building_id)
	state.population.current = 20  # 10 households: 5 in the house, 5 in the home
	Sim.settle(state, data, T0)
	var huts := func(): return state.buildings.filter(func(b): return b.type == "hut")
	_check(huts.call().is_empty(), "everyone has a home: no huts")
	Sim.demolish(state, data, home.id, T0)
	_check(int(state.population.current) == 20, "nobody leaves")
	_check(huts.call().size() == 5, "5 homeless households: 5 huts appear")
	var cells := {}
	for hut in huts.call():
		cells[str(hut.position)] = true
		_check(Sim.home_residents(state, data, hut, T0) == 2, "a homeless household of 2 in each hut")
	_check(cells.size() == 5, "each hut on its own tile")
	_check(not Sim.can_demolish(state, data, huts.call()[0].id).ok, "huts can't be demolished: they go by themselves")
	Sim.build(state, data, "home", Vector2i(5, 5), T0)
	_check(huts.call().is_empty(), "a new home: the huts are gone")


# --- Housing: households, wealth & rent (plan.md §5.18) ----------------------------------

## Life test data plus wealth classes (Broke / Poor / Rich), $15 workers ($30 with the "big"
## bonus = Rich), and three home types: Public (2 households, Broke / Poor, free, 0.3 MW),
## Regular (2, Poor / Rich, $2 rent, 0.5 MW), Villa (1, Rich, $15 rent, 1 MW), plus huts.
## A new game has no homes and nobody in it.
func _housing_data() -> Dictionary:
	var data := _life_data(0.0, 0.0)
	data.config["starting_population"] = 0
	data.config["starting_buildings"] = [{"type": "office", "position": [0, 0]}, {"type": "store", "position": [2, 0]}]
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 15}}
	data.config["wage_bonuses"] = {"none": 0.0, "big": 1.0}
	data.config["housing"] = {"adults_per_household": 2, "children_per_household": 2, "rent_share": 0.3,
		"wealth_classes": [{"id": "broke", "name": "Broke", "from_wage": 0}, {"id": "poor", "name": "Poor", "from_wage": 0.01},
			{"id": "rich", "name": "Rich", "from_wage": 30}]}
	data.buildings["hut"] = {"category": "residential", "build_cost": 0, "buildable": false, "households": 1, "hut": true}
	data.buildings["public"] = {"category": "residential", "build_cost": 0, "buildable": true, "households": 2, "housing_tier": 1,
		"wealth": ["broke", "poor"], "rent_per_household": 0, "power_mw": 0.3}
	data.buildings["regular"] = {"category": "residential", "build_cost": 0, "buildable": true, "households": 2, "housing_tier": 2,
		"wealth": ["poor", "rich"], "rent_per_household": 2, "power_mw": 0.5}
	data.buildings["villa"] = {"category": "residential", "build_cost": 0, "buildable": true, "households": 1, "housing_tier": 3,
		"wealth": ["rich"], "rent_per_household": 15, "power_mw": 1.0}
	return data


## 10 adults: 2 Rich (farm with the big bonus), 2 Poor (farm at $15), 6 Broke; a Public, a
## Regular and a Villa. Returns [state, data].
func _housing_town() -> Array:
	var data := _housing_data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "public", Vector2i(5, 5), T0)
	Sim.build(state, data, "regular", Vector2i(6, 5), T0)
	Sim.build(state, data, "villa", Vector2i(7, 5), T0)
	Sim.build(state, data, "crew_farm", Vector2i(5, 7), T0)
	var rich_farm: String = Sim.build(state, data, "crew_farm", Vector2i(6, 7), T0).building_id
	Sim.set_bonus(state, data, rich_farm, "big", T0)
	state.population.current = 10
	Sim.settle(state, data, T0)  # hires, then houses everyone
	return [state, data]


func test_wealth_classes() -> void:
	var town := _housing_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	_check(Sim.wealth_class_of(data, 0.0) == "broke" and Sim.wealth_class_of(data, 15.0) == "poor" and Sim.wealth_class_of(data, 30.0) == "rich", "class from the wage: none = Broke, $15 = Poor, $30 = Rich")
	var classes := Sim.adults_by_class(state, data, T0)
	_check(int(classes.rich.adults) == 2 and int(classes.poor.adults) == 2 and int(classes.broke.adults) == 6, "2 Rich, 2 Poor and 6 Broke adults")
	_check(is_equal_approx(float(classes.rich.wages), 60.0), "the Rich earn $30 an hour each")


func test_who_lives_where() -> void:
	var town := _housing_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var homes := {}
	for b in state.buildings:
		homes[b.type] = b.id
	var h := Sim.housing(state, data, T0)
	_check(int(h.homes[homes.villa].households) == 1 and int(h.homes[homes.villa].adults) == 2, "the Rich household takes the Villa (rent $15 <= 30% of $60)")
	_check(int(h.homes[homes.regular].households) == 1, "the Poor household takes a Regular House (rent $2 <= 30% of $30)")
	_check(int(h.homes[homes.public].households) == 2, "Broke households fill the free Public Housing")
	_check(int(h.homeless) == 1 and int(h.classes.broke.homeless) == 1, "one Broke household is left without a home")
	_check(state.buildings.filter(func(b): return b.type == "hut").size() == 1, "...so a Makeshift Hut appears for it")
	_check(is_equal_approx(float(h.rent_per_hour), 17.0), "rent: $15 + $2 an hour")
	_check(is_equal_approx(float(h.power_mw), 1.8), "every home is lived in: 1 + 0.5 + 0.3 MW")
	Sim.settle(state, data, T0 + 3600)
	_check(int(Sim.stats(state).income.get("rent", 0)) == 1700, "an hour later: $17 rent collected")


## A developer can change a home type's rent; households that can't afford it move out.
func test_dev_rent() -> void:
	var town := _housing_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	_check(Sim.dev_set_rent(state, data, "regular", 20.0, T0).ok, "rent for a Regular House set to $20")
	var h := Sim.housing(state, data, T0)
	_check(is_equal_approx(Sim.rent_per_household(state, data, "regular"), 20.0), "the new rent is used")
	_check(int(h.classes.poor.homeless) == 0 and int(h.homeless) == 2, "the Poor household moves to Public Housing (it can't pay $20); 2 Broke households are now homeless")
	_check(state.buildings.filter(func(b): return b.type == "hut").size() == 2, "2 huts now")
	_check(is_equal_approx(float(h.rent_per_hour), 15.0), "only the Villa pays rent now")
	Sim.dev_set_rent(state, data, "regular", -1.0, T0)
	_check(is_equal_approx(Sim.rent_per_household(state, data, "regular"), 2.0), "reset: back to the data file's rent")
	_check(not Sim.dev_set_rent(state, data, "crew_farm", 5.0, T0).ok, "only homes have rent")


## Life test data where only the Housing need counts (no grace, needs from 1 person), with the
## real bands' shape: below 20% no births and 3% an hour leave; 20-49% half speed and 1% leave;
## 50% and up nobody leaves. A "duo" home has room for 2 households.
func _leaving_data(birth: float, death: float) -> Dictionary:
	var data := _life_data(birth, death)
	data.config["happiness"] = {"needs_from_population": 1, "food_scores": [1.0], "weights": {"housing": 1},
		"growth_speeds": [{"from": 0, "speed": 0.0, "leave_per_hour": 0.03}, {"from": 0.2, "speed": 0.5, "leave_per_hour": 0.01},
			{"from": 0.5, "speed": 1.0, "leave_per_hour": 0.0}]}
	data.buildings["duo"] = {"category": "residential", "build_cost": 0, "buildable": true, "households": 2}
	return data


## The Housing need: the share of households with a real home.
func test_housing_need() -> void:
	var data := _leaving_data(0.0, 0.0)
	var state := Sim.new_game(data, T0)  # the house: 5 households
	Sim.build(state, data, "home", Vector2i(5, 5), T0)  # 5 more
	Sim.build(state, data, "duo", Vector2i(6, 6), T0)  # 2 more: 12 in all
	state.population.current = 30  # 15 households: 3 homeless
	var happy := Sim.happiness(state, data, T0)
	_check(int(happy.homeless) == 3 and int(happy.households) == 15, "15 households, 3 of them homeless")
	_check(is_equal_approx(float(happy.housing), 0.8) and is_equal_approx(float(happy.score), 0.8), "Housing need 80% (12 of 15 have a home)")
	_check(float(happy.leave_per_hour) == 0.0, "80%: nobody leaves")


## On top of the Housing need, every household in a hut takes a share off (up to a limit).
func test_homeless_penalty() -> void:
	var data := _leaving_data(0.0, 0.0)
	data.config.happiness["homeless_penalty"] = {"per_household": 0.02, "max": 0.3}
	var state := Sim.new_game(data, T0)  # the house: 5 households
	var happy := Sim.happiness(state, data, T0)
	_check(float(happy.homeless_penalty) == 0.0 and float(happy.score) == 1.0, "everyone has a home: no penalty")
	state.population.current = 16  # 8 households: 3 homeless
	happy = Sim.happiness(state, data, T0)
	_check(is_equal_approx(float(happy.homeless_penalty), 0.06), "3 households in huts: 2% each = 6% off")
	_check(is_equal_approx(float(happy.score), 0.625 - 0.06), "score = Housing need (5 of 8) minus the penalty")
	state.population.current = 50  # 25 households: 20 homeless
	happy = Sim.happiness(state, data, T0)
	_check(is_equal_approx(float(happy.homeless_penalty), 0.3), "20 households in huts: at most 30% off")
	_check(float(happy.score) == 0.0, "the score never goes below 0 (20% Housing need - 30%)")
	data.config.happiness.needs_from_population = 100
	happy = Sim.happiness(state, data, T0)
	_check(float(happy.homeless_penalty) == 0.0 and float(happy.score) == 1.0, "while needs don't count, huts don't either")


## An unhappy village loses people: the homeless first, workers keep their posts; time away
## gives the same result as playing through it.
func test_unhappy_people_leave() -> void:
	var data := _leaving_data(0.0, 0.0)
	var state := Sim.new_game(data, T0)  # room for 5 households
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	state.population.current = 60  # 30 households, 25 homeless: Housing 17% -> 3% an hour leave
	Sim.settle(state, data, T0)
	var happy := Sim.happiness(state, data, T0)
	_check(is_equal_approx(float(happy.leave_per_hour), 0.03) and float(happy.growth_speed) == 0.0, "below 20%: no babies, 3% an hour leave")
	var played := state.duplicate(true)
	var report := Sim.settle(state, data, T0 + 3600)
	_check(int(state.population.current) == 59 and int(report.get("moved_away", 0)) == 1, "60 people x 3% = 1.8 an hour: 1 left in the first hour")
	_check(Sim.hired(farm) == 2, "the workers stay: the jobless leave first")
	Sim.settle(state, data, T0 + 4 * 3600)
	var t := T0
	while t < T0 + 4 * 3600:
		t = minf(t + 7.0, T0 + 4 * 3600)
		Sim.settle(played, data, t)
	_check(int(played.population.current) == int(state.population.current) and str(Sim.people_stats(played)) == str(Sim.people_stats(state)), "4 hours away = 4 hours played (%d vs %d people)" % [int(state.population.current), int(played.population.current)])
	_check(int(Sim.people_stats(state).moved_away) >= 6, "about 7 people left in 4 hours")


## With leave_group_size, people wait until a whole group is ready, then leave together, at the
## moment settling predicts. Time away = playing through.
func test_unhappy_people_leave_in_groups() -> void:
	var data := _leaving_data(0.0, 0.0)
	data.config.happiness["leave_group_size"] = 5
	var state := Sim.new_game(data, T0)
	state.population.current = 60  # 25 households homeless: 3% an hour = 1.8 an hour, a group of 5 in 10000 s
	Sim.settle(state, data, T0)
	var played := state.duplicate(true)
	Sim.settle(state, data, T0 + 9990)
	_check(int(state.population.current) == 60, "nobody leaves before a whole group is ready (%d people)" % int(state.population.current))
	var report := Sim.settle(state, data, T0 + 10001)
	_check(int(state.population.current) == 55 and int(report.get("moved_away", 0)) == 5, "then 5 leave at once")
	Sim.settle(state, data, T0 + 8 * 3600)
	var t := T0
	while t < T0 + 8 * 3600:
		t = minf(t + 7.0, T0 + 8 * 3600)
		Sim.settle(played, data, t)
	var left := int(Sim.people_stats(state).moved_away)
	_check(left % 5 == 0 and left >= 10, "only whole groups leave (%d in 8 hours)" % left)
	_check(int(played.population.current) == int(state.population.current) and str(Sim.people_stats(played)) == str(Sim.people_stats(state)), "8 hours away = 8 hours played (%d vs %d people)" % [int(state.population.current), int(played.population.current)])


## With births, deaths and leaving, the village can't outgrow its homes forever.
func test_village_stays_bounded() -> void:
	var data := _leaving_data(0.01, 0.005)
	data.buildings["hut"] = {"category": "residential", "build_cost": 0, "buildable": false, "households": 1, "hut": true}
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "home", Vector2i(5, 5), T0)  # room for 10 households (20 adults)
	state.population.current = 100  # 50 households, 40 homeless
	Sim.settle(state, data, T0)
	var huts_at_start: int = state.buildings.filter(func(b): return b.type == "hut").size()
	Sim.settle(state, data, T0 + 30 * 86400.0)
	var huts_after: int = state.buildings.filter(func(b): return b.type == "hut").size()
	_check(int(state.population.current) < 100, "30 days later the village has shrunk (%d people)" % int(state.population.current))
	_check(huts_after < huts_at_start, "and the huts with it (%d -> %d)" % [huts_at_start, huts_after])


## Saves from before "moved_away" existed settle without errors.
func test_old_counters_settle() -> void:
	var data := _leaving_data(0.0, 0.0)
	var state := Sim.new_game(data, T0)
	state.stats.people = {"moved_in": 0, "born": 0, "grew_up": 0, "died": 0}
	Sim.settle(state, data, T0 + 60)
	_check(int(Sim.people_stats(state).moved_away) == 0, "a missing counter starts at 0")


## A save from before housing types (version 6, homes = Small Houses that were free) loads with
## its Small Houses as Public Housing, so nobody becomes homeless on loading.
func test_old_small_houses_become_public_housing() -> void:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	var state := Sim.new_game(data, T0)
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 6
	for b in old.buildings:
		if b.type == "public_housing":
			b.type = "small_house"
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	var s: Dictionary = result.state if result.ok else {}
	var types := {}
	for b in s.get("buildings", []):
		types[b.type] = int(types.get(b.type, 0)) + 1
	_check(result.ok and int(types.get("public_housing", 0)) == 5 and not types.has("small_house"), "the 5 Small Houses are Public Housing now")
	Sim.settle(s, data, T0 + 1.0)
	_check(int(Sim.housing(s, data, T0 + 1.0).homeless) == 0, "and nobody is homeless")
	# A version 6 save that already has housing types keeps its Regular Houses.
	var newer := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	newer.save_version = 6
	newer.buildings[1].type = "small_house"
	var kept := SaveFormat.from_text(JSON.stringify(newer), data)
	_check(kept.ok and kept.state.buildings[1].type == "small_house", "a save with Public Housing keeps its Regular Houses")


## An empty home uses no power.
func test_empty_home_uses_no_power() -> void:
	var data := _housing_data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "villa", Vector2i(5, 5), T0)
	_check(float(Sim.housing(state, data, T0).power_mw) == 0.0, "nobody lives there: 0 MW")


## Births, deaths and children growing up while away = the same while playing in 7-second steps.
func test_life_away_equals_playing() -> void:
	var data := _life_data(0.5, 0.2)
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "big_house", Vector2i(5, 5), T0)
	Sim.build(state, data, "crew_farm", Vector2i(6, 6), T0)
	Sim.build(state, data, "crew_mill", Vector2i(7, 7), T0)
	var played := state.duplicate(true)
	var t := T0
	while t < T0 + 20000:
		t = minf(t + 7.0, T0 + 20000)
		Sim.settle(played, data, t)
	Sim.settle(state, data, T0 + 20000)
	var same: bool = int(played.population.current) == int(state.population.current) \
		and Sim.children_count(played) == Sim.children_count(state) \
		and str(Sim.people_stats(played)) == str(Sim.people_stats(state)) \
		and Sim.children_groups(played).size() == Sim.children_groups(state).size()
	_check(same, "one long absence = playing in 7-second steps (%s vs %s)" % [Sim.people_stats(state), Sim.people_stats(played)])
	_check(int(Sim.people_stats(state).born) > 0 and int(Sim.people_stats(state).died) > 0 and int(Sim.people_stats(state).grew_up) > 0, "(the test saw births, deaths and children growing up)")


## A new village gets a grace period: needs don't count for its first hours.
func test_happiness_grace_period() -> void:
	var data := _needs_data()
	data.config.happiness["grace_hours"] = 1
	var state := Sim.new_game(data, T0)
	state.population.current = 10  # no food, no jobs: 0% once needs count
	var happy := Sim.happiness(state, data, T0 + 100)
	_check(not happy.needs_count and happy.score == 1.0 and is_equal_approx(float(happy.grace_left), 3500.0), "in the first hour needs don't count")
	_check(Sim.happiness(state, data, T0 + 3600).needs_count and Sim.happiness(state, data, T0 + 3600).score == 0.0, "after it, they do")
	state.erase("started_at")  # a village from before the grace period existed
	_check(Sim.happiness(state, data, T0 + 100).needs_count, "older villages get no grace")


## Jobs counts adults only: children don't need a job.
func test_jobs_need_counts_adults() -> void:
	var data := _needs_data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "big_house", Vector2i(3, 3), T0)
	Sim.build(state, data, "crew_farm", Vector2i(6, 6), T0)
	state.population.current = 14
	state.population.children = [{"count": 10, "grows_up_at": T0 + 90000}]
	Sim._hire(state, data, T0)  # 4 adults, 2 of them at the farm
	_check(is_equal_approx(float(Sim.happiness(state, data, T0).jobs), 0.5), "2 of 4 adults have a job: 50% (children don't count)")
	_check(int(Sim.employment(state, data, T0).unemployed) == 2, "2 adults unemployed")


## Version 5 saves had no children: everyone in them is an adult.
func test_old_save_gets_children() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	state.population.current = 7
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 5
	old.population.erase("children")
	old.population.erase("life_carry")
	old.stats.erase("people")
	old.erase("started_at")
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	var s: Dictionary = result.state if result.ok else {}
	_check(result.ok and int(s.save_version) == Sim.SAVE_VERSION, "a version 5 save loads as the newest version")
	_check(result.ok and Sim.adults(s) == 7 and Sim.children_count(s) == 0 and s.population.children.is_empty(), "everyone in it is an adult")
	_check(result.ok and int(Sim.people_stats(s).born) == 0 and not s.has("started_at"), "zeroed counters and no grace period")


## The real data: founders, no immigration, births and deaths switched on.
func test_real_life_data() -> void:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	var state := Sim.new_game(data, T0)
	_check(int(state.population.current) == int(data.config.starting_population) and int(state.population.current) > 0, "real data: a new game starts with its founders")
	var store := {}
	for b in state.buildings:
		if data.buildings[b.type].get("category", "") == "storage":
			store = b
	_check(Sim.storage_capacity(state, data, store) == int(data.buildings[store.type].capacity), "real data: the starting warehouse is fully staffed")
	_check(float(data.config.population_growth_seconds) > 0.0 and bool(data.config.get("move_in_only_for_jobs", false)), "real data: newcomers are migrant workers")
	_check(not bool(data.config.get("move_in_needs_home", true)), "real data: migrant workers come even when the homes are full")
	Sim.settle(state, data, T0 + 3600)
	_check(int(Sim.people_stats(state).moved_in) == 0, "real data: a new game's founders fill its jobs, so no job seekers come")
	_check(not data.config.get("life", {}).is_empty(), "real data: births and deaths are switched on")


## The real data: the needs are switched on and sensible.
func test_real_happiness_data() -> void:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	_check(Sim._has_needs(data), "real data: needs are switched on")
	var state := Sim.new_game(data, T0)
	_check(Sim.happiness(state, data, T0).score == 1.0, "real data: a new game starts at 100% (too small to complain)")
	_check(float(data.config.happiness.get("homeless_penalty", {}).get("per_household", 0.0)) > 0.0, "real data: households in huts lower happiness on top of the Housing need")
	_check(float(Sim.happiness(state, data, T0 + 4 * 3600.0).homeless_penalty) == 0.0, "real data: a new game has no homeless, so no penalty")


## The real data: the Supermarket and the goods it sells make sense.
func test_real_shop_data() -> void:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	_check(data.buildings.get("supermarket", {}).get("category", "") == "retail" and int(data.buildings.supermarket.get("shelves", 0)) > 0, "real data: the Supermarket is a shop with shelves")
	var shop: Dictionary = data.buildings.supermarket
	_check(shop.get("fixed_workers", false) and shop.get("fixed_wage", false) and not shop.get("staffed_first", false), "real data: the Supermarket has fixed workers at the minimum wage and waits its turn for people")
	_check(Sim.shop_products(data).has("bread") and Sim.shop_products(data).has("flour") and not Sim.shop_products(data).has("wheat"), "real data: shops sell flour and bread, not raw wheat")
	var tags := Sim.price_tags(data)
	_check(tags.has(str(data.config.retail.get("default_tag", ""))), "real data: the default price tag exists")
	var last_price := 0.0
	var last_speed := INF
	for tag in tags:
		_check(float(tags[tag].price) > last_price and float(tags[tag].speed) < last_speed, "real data: tag '%s' costs more and sells slower than the one before" % tag)
		last_price = float(tags[tag].price)
		last_speed = float(tags[tag].speed)
	# Construction (plan.md §5.15): at the worst prices (every material at its highest swing).
	var construction: Dictionary = data.config.construction
	var worst := 0.0
	for type in ["supermarket", "wheat_farm", "flour_mill"]:
		for line in Sim.construction_quote(data, type, 1, T0).lines:
			var base := Sim.cents(float(construction.materials.get(line.id, {}).get("price", 0)))
			worst += float(line.cost) if line.id == "labor" else int(line.amount) * base * (1.0 + float(construction.price_swing))
	_check(worst <= Sim.cents(float(data.config.starting_cash)), "real data: starting cash covers a Wheat Farm, a Flour Mill and a Supermarket even at the highest material prices")
	var times := [3600.0, 3600.0, 7200.0, 10800.0]
	for type in data.buildings:
		if not data.buildings[type].get("buildable", false):
			continue
		if data.buildings[type].has("upgrades"):  # a Trading Post has nothing to upgrade
			_check(Sim.max_level(data, type) == 4, "real data: %s goes up to Level 4" % type)
		for level in range(1, Sim.max_level(data, type) + 1):
			_check(Sim.construction_seconds(data, type, level) == times[level - 1], "real data: %s Level %d takes %s s" % [type, level, times[level - 1]])


# --- Construction materials (plan.md §5.15) --------------------------------------

## Test data where building and upgrading need materials and a crew: a lodge (a home) needs
## 100 Bricks + 2 Steel at Level 1. Bricks cost $1 and Steel $50, give or take 20% each hour;
## the crew is 8 at $15 an hour.
func _construction_data() -> Dictionary:
	var data := _data()
	data.config["starting_cash"] = 100000
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 15}}
	data.config["construction"] = {
		"materials": {"bricks": {"name": "Bricks", "price": 1}, "steel": {"name": "Steel", "unit": "beam", "price": 50}},
		"labor_worker_type": "low_skilled", "crew": 8, "level_growth": 2,
		"level_seconds": [3600, 3600, 7200, 10800], "price_swing": 0.2, "price_change_seconds": 3600}
	data.buildings["lodge"] = {"category": "residential", "buildable": true, "households": 2,
		"materials": {"bricks": 100, "steel": 2},
		"upgrades": [{"households": 3}, {"households": 4}, {"households": 5}]}
	return data


func test_construction_needs_double_each_level() -> void:
	var data := _construction_data()
	var expect := [[100, 2, 8], [200, 4, 16], [400, 8, 32], [800, 16, 64]]
	var times := [3600.0, 3600.0, 7200.0, 10800.0]
	for level in range(1, 5):
		var needs := Sim.construction_needs(data, "lodge", level)
		var e: Array = expect[level - 1]
		_check(int(needs.bricks) == e[0] and int(needs.steel) == e[1] and int(needs.crew) == e[2], "Level %d needs %d Bricks, %d Steel and a crew of %d (doubling each level)" % [level, e[0], e[1], e[2]])
		_check(Sim.construction_seconds(data, "lodge", level) == times[level - 1], "Level %d takes %s s" % [level, times[level - 1]])
	_check(Sim.construction_seconds(data, "lodge", 9) == 10800.0, "levels past the list take its last time")
	_check(Sim.construction_seconds(data, "slow_farm", 1) == 5.0, "a building's own build_time still counts")
	_check(int(Sim.construction_needs(data, "office", 1).crew) == 0 and Sim.construction_value(data, "office") == 0, "a building without materials needs no crew (the office stays free)")
	var labor := {}
	for line in Sim.construction_quote(data, "lodge", 3, T0).lines:
		if line.id == "labor":
			labor = line
	_check(int(labor.get("amount", 0)) == 32 and is_equal_approx(float(labor.get("hours", 0)), 2.0) and int(labor.get("cost", 0)) == 96000, "Level 3 labor: a crew of 32 for 2 h at $15 = $960")
	_check(Sim.level_value(data, "lodge", 1) == 100 * 100 + 2 * 5000 + 8 * 1500, "at base prices Level 1 is worth $100 of Bricks + $100 of Steel + $120 of labor")
	_check(Sim.construction_value(data, "lodge", 2) == Sim.level_value(data, "lodge", 1) + Sim.level_value(data, "lodge", 2), "a building's value adds its upgrades")
	data.buildings.lodge["crew"] = 3
	_check(int(Sim.construction_needs(data, "lodge", 3).crew) == 12, "a building can have its own crew (3, so 12 at Level 3)")


func test_material_prices_move_with_the_market() -> void:
	var data := _construction_data()
	var hour := floorf(T0 / 3600.0) * 3600.0
	var seen := {}
	var in_range := true
	var steady := true
	for h in 48:
		var p := Sim.material_price(data, "steel", hour + h * 3600.0)
		in_range = in_range and p >= 4000 and p <= 6000
		steady = steady and Sim.material_price(data, "steel", hour + h * 3600.0 + 3599.0) == p
		seen[p] = true
	_check(in_range, "Steel stays between $40 and $60 ($50 give or take 20%)")
	_check(steady, "the price stays the same for the whole hour")
	_check(seen.size() > 10, "the price changes from hour to hour")
	_check(Sim.next_price_change_at(data, hour + 10.0) == hour + 3600.0, "the next price comes at the turn of the hour")
	data.config.construction.price_swing = 0.0
	_check(Sim.material_price(data, "steel", T0) == 5000, "with no swing it's the base price")


func test_building_buys_materials_and_pays_the_crew() -> void:
	var data := _construction_data()
	var state := Sim.new_game(data, T0)
	var expected := 100 * Sim.material_price(data, "bricks", T0) + 2 * Sim.material_price(data, "steel", T0) + 8 * 1500
	var quote := Sim.construction_quote(data, "lodge", 1, T0)
	_check(int(quote.cost) == expected and float(quote.seconds) == 3600.0, "building costs the materials at today's prices + the crew, and takes 1 h")
	var cash: int = state.profile.currency
	var result := Sim.build(state, data, "lodge", Vector2i(5, 5), T0)
	var lodge := Sim.find_building(state, result.building_id)
	_check(result.ok and state.profile.currency == cash - expected and int(lodge.paid) == expected and int(Sim.stats(state).spending.construction) == expected, "it's all paid at once, counted as construction and as the building's value")
	_check(not Sim.is_built(lodge, T0 + 3599) and Sim.is_built(lodge, T0 + 3600), "ready after 1 h")
	_check(is_equal_approx(Sim.construction_progress(lodge, data, T0 + 1800), 0.5), "half built after 30 min")
	var t := T0 + 3600.0
	Sim.settle(state, data, t)
	var up := 200 * Sim.material_price(data, "bricks", t) + 4 * Sim.material_price(data, "steel", t) + 16 * 1500
	var check := Sim.can_upgrade(state, data, lodge.id, t)
	_check(check.ok and int(check.cost) == up and float(check.seconds) == 3600.0, "Level 2: twice the materials and crew, at that hour's prices, and 1 h")
	cash = state.profile.currency
	Sim.upgrade(state, data, lodge.id, t)
	_check(state.profile.currency == cash - up and int(lodge.paid) == expected + up, "the upgrade is paid at once and adds to the building's value")
	Sim.settle(state, data, t + 3600.0)
	_check(Sim.building_level(lodge) == 2 and float(Sim.can_upgrade(state, data, lodge.id, t + 3600.0).seconds) == 7200.0, "Level 3 takes 2 h")
	var poor := Sim.new_game(data, T0)
	poor.profile.currency = expected - 1
	_check(Sim.can_build(poor, data, "lodge", Vector2i(5, 5), T0).error == "Not enough money.", "it needs the money for the materials and crew")


# --- Upgrades (plan.md §5.15) ----------------------------------------------------

## Test data with upgrades: the crew farm (2 workers) and crew mill (3) grow, the house gets
## more households. No one moves in, so the worker counts stay put.
func _upgrade_data() -> Dictionary:
	var data := _data()
	data.config["population_growth_seconds"] = 0
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	data.buildings.crew_farm["upgrades"] = [
		{"cost": 50, "time": 600, "max_workers": 3},
		{"cost": 100, "time": 1200, "max_workers": 4}]
	data.buildings.crew_mill["upgrades"] = [{"cost": 50, "time": 100, "max_workers": 6}]
	data.buildings.house["upgrades"] = [{"cost": 0, "time": 100, "households": 8}]
	return data


func test_upgrade_rules() -> void:
	var data := _upgrade_data()
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	var check := Sim.can_upgrade(state, data, farm.id, T0)
	_check(check.ok and int(check.level) == 2 and int(check.cost) == 5000 and float(check.seconds) == 600.0, "Level 2 costs $50 and takes 10 minutes")
	_check(Sim.building_level(farm) == 1 and Sim.max_level(data, "crew_farm") == 3, "built at Level 1, can reach Level 3")
	_check(not Sim.can_upgrade(state, data, state.buildings[0].id, T0).ok, "a building without upgrades can't be upgraded")
	var slow := Sim.find_building(state, Sim.build(state, data, "slow_farm", Vector2i(6, 6), T0).building_id)
	_check(Sim.can_upgrade(state, data, slow.id, T0).error == "Still under construction.", "not while it's being built")
	var cash: int = state.profile.currency
	_check(Sim.upgrade(state, data, farm.id, T0).ok, "upgrade starts")
	_check(state.profile.currency == cash - 5000 and int(Sim.stats(state).spending.construction) >= 5000, "its cost is paid at once and counted as construction")
	_check(Sim.can_upgrade(state, data, farm.id, T0 + 1).error == "It's already being upgraded.", "one upgrade at a time")
	_check(Sim.building_level(farm) == 1 and Sim.is_upgrading(farm, T0 + 599), "still Level 1 while it's being upgraded")
	Sim.settle(state, data, T0 + 600)
	_check(Sim.building_level(farm) == 2 and not Sim.is_upgrading(farm, T0 + 600) and Sim.max_workers(data, farm) == 3, "Level 2 when it's done: 3 workers")
	Sim.upgrade(state, data, farm.id, T0 + 600)
	Sim.settle(state, data, T0 + 1800)
	_check(Sim.building_level(farm) == 3 and Sim.max_workers(data, farm) == 4, "Level 3: 4 workers")
	_check(Sim.can_upgrade(state, data, farm.id, T0 + 1800).error == "It's at the highest level (3).", "no upgrade past the highest level")
	var poor := Sim.new_game(data, T0)
	var other := Sim.find_building(poor, Sim.build(poor, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	poor.profile.currency = 4999
	_check(Sim.can_upgrade(poor, data, other.id, T0).error == "Not enough money.", "it needs the money")
	poor.profile.currency = 5000
	Sim.settle(poor, data, T0 + 1000)
	Sim.upgrade(poor, data, other.id, T0 + 500)  # the clock was set back 500 s
	_check(float(other.upgrade_done_at) == T0 + 1600.0, "a clock set backwards starts the upgrade from the time already worked out, never earlier")


## A farm closes while it's upgraded (its workers go home), so it can't have a batch then.
## Afterwards its bigger crew works faster (3 of 2 = 1.5x), and a batch costs the same wages.
func test_upgrade_closes_and_works_faster() -> void:
	var data := _upgrade_data()
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	var batch_wages := int(Sim.batch_quote(state, data, farm, "grow", 6, "none", T0).wages)
	_batch(state, data, farm, 1)
	_check(Sim.can_upgrade(state, data, farm.id, T0 + 30).error == Sim.BATCH_BUSY, "not while it has a batch")
	Sim.settle(state, data, T0 + 60)
	Sim.collect(state, data, farm.id, T0 + 60)
	Sim.upgrade(state, data, farm.id, T0 + 60)
	_check(Sim.hired(farm) == 0 and Sim.posts(data, farm, T0 + 60) == 0, "closed: its workers go home")
	_check(_batch(state, data, farm, 1, "none", T0 + 100).error == "It's being upgraded.", "no batch while it's closed, and it says why")
	_check(is_equal_approx(Sim.construction_progress(farm, data, T0 + 360), 0.5), "half way through the upgrade")
	Sim.settle(state, data, T0 + 660)
	_check(Sim.hired(farm) == 3, "open again with 3 workers")
	_batch(state, data, farm, 6, "none", T0 + 660)
	_check(is_equal_approx(Sim.building_speed(state, data, farm, T0 + 660), 1.5), "3 of 2 workers: 1.5x speed")
	Sim.settle(state, data, T0 + 699)
	_check(Sim.ready_units(farm).is_empty(), "an hour takes 40 s at 1.5x")
	Sim.settle(state, data, T0 + 700)
	_check(_ready(farm, "wheat") == 10, "first hour done 40 s after it started")
	Sim.settle(state, data, T0 + 900)
	_check(_ready(farm, "wheat") == 60, "all 6 hours in 240 s instead of 360")
	_check(int(farm.batch.wages) == batch_wages, "a batch costs the same wages at any level")


## Homes stay lived in while they're upgraded; the new households move in when it's done.
func test_upgrade_home_stays_open() -> void:
	var data := _upgrade_data()
	var state := Sim.new_game(data, T0)
	state.population.current = 16  # 8 households, room for 5
	Sim.settle(state, data, T0)
	var house: Dictionary = state.buildings[1]
	_check(int(Sim.housing(state, data, T0).homeless) == 3, "3 households have no home")
	Sim.upgrade(state, data, house.id, T0)
	Sim.settle(state, data, T0 + 99)
	_check(int(Sim.housing(state, data, T0 + 99).homes[house.id].households) == 5, "the 5 households stay while it's upgraded")
	Sim.settle(state, data, T0 + 100)
	_check(int(Sim.housing(state, data, T0 + 100).homeless) == 0 and Sim.home_households(data, house) == 8, "room for 8 when it's done")


## Being away through an upgrade ends exactly like playing through it.
func test_upgrade_away_matches_playing() -> void:
	var data := _upgrade_data()
	var away := Sim.new_game(data, T0)
	away.population.current = 10
	var farm := Sim.find_building(away, Sim.build(away, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	var mill := Sim.find_building(away, Sim.build(away, data, "crew_mill", Vector2i(6, 6), T0).building_id)
	away.inventory["wheat"] = 40
	Sim.start_batch(away, data, mill.id, "mill", 4, "none", T0)
	Sim.settle(away, data, T0 + 25)
	Sim.upgrade(away, data, farm.id, T0 + 25)
	var playing: Dictionary = away.duplicate(true)
	Sim.settle(away, data, T0 + 2000)
	var t := T0 + 25
	while t < T0 + 2000:
		t = minf(t + 7.0, T0 + 2000)
		Sim.settle(playing, data, t)
	_check(away.profile.currency == playing.profile.currency, "same cash away and playing")
	_check(_difference(away.buildings[4].batch, playing.buildings[4].batch, "") == "" and _ready(away.buildings[4], "flour") == 32, "same goods made away and playing")
	_check(Sim.building_level(away.buildings[3]) == 2 and Sim.building_level(playing.buildings[3]) == 2, "the upgrade is done either way")
	_check(Sim.hired(away.buildings[3]) == Sim.hired(playing.buildings[3]), "the same workers either way")


# --- Balance sheet, cash check and money log (plan.md §5.19) -------------------------

## A new game: the company is worth its starting capital (cash + starter buildings at their build
## cost), nothing has been earned yet, and the cash check adds up.
func test_balance_sheet_new_game() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	var sheet := Sim.balance_sheet(state, data, T0)
	_check(int(sheet.cash) == 50000 and int(sheet.buildings) == 30000, "$500 cash + the $300 starter warehouse")
	_check(int(sheet.capital) == 80000 and int(sheet.company_value) == 80000 and int(sheet.profit_kept) == 0, "worth its starting capital, no profit yet")
	_check(int(sheet.total_owed) == 0 and int(sheet.debt) == 0, "owes nothing")
	_check(Sim.cash_check(state).ok and int(Sim.cash_check(state).start) == 50000, "cash check: starts at $500 and adds up")


## Building turns cash into a building: the company is worth the same. It counts as "being built"
## until it's finished.
func test_balance_sheet_build() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	_check(Sim.build(state, data, "slow_farm", Vector2i(5, 5), T0).ok, "a farm that takes 5 s to build")
	var sheet := Sim.balance_sheet(state, data, T0)
	_check(int(sheet.cash) == 40000 and int(sheet.being_built) == 10000 and int(sheet.buildings) == 30000, "$100 moved from cash to being built")
	_check(int(sheet.company_value) == 80000, "worth the same")
	Sim.settle(state, data, T0 + 5)
	sheet = Sim.balance_sheet(state, data, T0 + 5)
	_check(int(sheet.being_built) == 0 and int(sheet.buildings) == 40000, "finished: it counts as a building")
	_check(Sim.cash_check(state).ok, "cash check adds up")
	sheet = Sim.balance_sheet(state, data, T0 + 1)  # the clock was set back 4 s
	_check(int(sheet.being_built) == 0 and int(sheet.buildings) == 40000, "a clock set backwards doesn't make it unfinished again")


## An upgrade's cost is "being built" until it's done, then part of the building's value.
func test_balance_sheet_upgrade() -> void:
	var data := _upgrade_data()
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	var before := int(Sim.balance_sheet(state, data, T0).company_value)
	Sim.upgrade(state, data, farm.id, T0)
	var sheet := Sim.balance_sheet(state, data, T0)
	_check(int(farm.paid) == 5000 and int(sheet.being_built) == 5000 and int(sheet.company_value) == before, "the $50 upgrade is being built; worth the same")
	Sim.settle(state, data, T0 + 600)
	sheet = Sim.balance_sheet(state, data, T0 + 600)
	_check(int(sheet.being_built) == 0 and not farm.has("upgrade_paid") and int(sheet.buildings) == 30000 + 5000, "done: part of the building's value")


## Demolishing gives back half the price: the company loses the other half.
func test_balance_sheet_demolish() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "farm", Vector2i(5, 5), T0).building_id)
	Sim.demolish(state, data, farm.id, T0)
	var sheet := Sim.balance_sheet(state, data, T0)
	_check(int(sheet.company_value) == 80000 - 5000 and int(sheet.profit_kept) == -5000, "$50 of the $100 farm is lost")
	_check(Sim.cash_check(state).ok, "the refund is counted: cash check adds up")


## Selling goods turns their cost into money: the profit kept grows by what they earned over
## what they cost to make.
func test_balance_sheet_sell() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	state.inventory["wheat"] = 3
	state["inventory_cost"] = {"wheat": 150.0}  # they cost $0.50 each to make
	var sheet := Sim.balance_sheet(state, data, T0)
	_check(int(sheet.goods.wheat.qty) == 3 and int(sheet.goods.wheat.value) == 150, "3 wheat worth $1.50 (what they cost)")
	var before := int(sheet.profit_kept)
	Sim.sell(state, data, "wheat", 3, T0)
	sheet = Sim.balance_sheet(state, data, T0)
	_check(int(sheet.profit_kept) == before + 600 - 150 and not sheet.goods.has("wheat"), "sold for $6: $4.50 more profit kept")
	_check(Sim.cash_check(state).ok, "cash check adds up")


## Supermarket goods sold but not paid yet count as "shop sales not paid yet"; the unsold ones
## still count as goods.
func test_balance_sheet_shop_sales_not_paid_yet() -> void:
	var town := _shop_town()
	var state: Dictionary = town[0]
	var data: Dictionary = town[1]
	var market: Dictionary = town[2]
	Sim.stock_shelf(state, data, market.id, "flour", 10, "normal", T0)
	Sim.settle(state, data, T0 + 1800)
	var sheet := Sim.balance_sheet(state, data, T0 + 1800)
	_check(int(sheet.receivable) == 1500, "5 sold at $3.00, not paid yet: $15")
	_check(int(sheet.goods.flour.qty) == 95, "90 in the warehouse + 5 unsold on the shelf")
	Sim.settle(state, data, T0 + 3600)
	sheet = Sim.balance_sheet(state, data, T0 + 3600)
	_check(int(sheet.receivable) == 0 and Sim.cash_check(state).ok, "sold out and paid: nothing waiting, cash check adds up")


## Wages paid with no cash: cash below 0 is debt, owed on the balance sheet.
func test_balance_sheet_debt() -> void:
	var data := _upgrade_data()
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	Sim.build(state, data, "crew_store", Vector2i(5, 5), T0)  # its workers are paid as they go
	Sim.dev_set_cash(state, 0)
	Sim.settle(state, data, T0 + 3600)  # 4 workers x $36 for an hour
	var sheet := Sim.balance_sheet(state, data, T0 + 3600)
	_check(int(sheet.cash) == 0 and int(sheet.debt) == 14400, "$144 of wages took cash to -$144: that's debt")
	_check(int(sheet.company_value) == int(sheet.total_owned) - int(sheet.total_owed), "value = owned - owed")
	_check(Sim.cash_check(state).ok, "cash check adds up")


## Dev tools change cash, and the cash check counts it, so it still adds up.
func test_cash_check_counts_dev_tools() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.dev_add_cash(state, 1000)
	_check(int(Sim.cash_check(state).dev) == 1000 and Sim.cash_check(state).ok, "added $10: counted")
	Sim.dev_set_cash(state, -250)
	_check(int(Sim.cash_check(state).dev) == -50250 and Sim.cash_check(state).ok, "set to -$2.50: counted")
	_check(Sim._total(Sim.stats(state).income) == 0, "not counted as income")


## The money log: one entry per 30 minutes, time away = one entry, and the entries add up to the
## all-time totals.
func test_money_log() -> void:
	var data := _upgrade_data()
	data.config["money_log_minutes"] = 30
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	Sim.build(state, data, "crew_store", Vector2i(5, 5), T0)  # 4 workers at $36/hour, paid as they go
	for i in 6:
		Sim.settle(state, data, T0 + 300 * (i + 1))  # playing for 30 minutes
	var rows := Sim.money_log(state, T0 + 1800)
	_check(rows.size() == 1 and float(rows[0].from) == T0 and float(rows[0].to) == T0 + 1800 and not rows[0].open, "one block of 30 minutes")
	_check(rows.size() == 1 and int(rows[0].spending.get("wages", 0)) == 7200 and int(rows[0].net) == -7200, "it paid $72 of wages")
	Sim.settle(state, data, T0 + 1800 + 21600)  # 6 hours away
	rows = Sim.money_log(state, T0 + 1800 + 21700)
	_check(rows.size() == 3 and rows[0].open and float(rows[1].to) - float(rows[1].from) == 21600.0, "6 hours away = one block; the next one is still running")
	var wages := 0
	for row in rows:
		wages += int(row.spending.get("wages", 0))
	_check(wages == int(Sim.stats(state).spending.wages), "the blocks add up to the all-time wages")
	data.config["money_log_size"] = 3
	for i in 5:
		Sim.settle(state, data, T0 + 30000 + 1800 * i)
	_check(Sim.stats(state).money_log.size() == 3, "only the latest money_log_size snapshots are kept")
	Sim.settle(state, data, T0)  # the clock moved backwards
	_check(Sim.stats(state).money_log.size() == 3 and float(Sim.stats(state).money_log[-1].t) == T0 + 30000 + 7200, "a clock set backwards adds nothing")


## A version 7 save (from before the balance sheet) gets list prices for its buildings, and a
## starting cash that makes the cash check add up.
func test_old_save_gets_balance_sheet() -> void:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	var state := Sim.new_game(data, T0)
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 7
	old.buildings = old.buildings.filter(func(b): return b.type != "construction_office")  # came in version 11
	for b in old.buildings:
		b.erase("paid")
		if b.type == "city_hall":
			b.type = "construction_office"  # its id before version 11
	for key in ["capital", "adjustments", "money_log"]:
		old.stats.erase(key)
	old.stats.income.sales = 12345  # it earned and spent some money before
	old.stats.spending.wages = 345
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	var s: Dictionary = result.state if result.ok else {}
	var house: Dictionary = s.get("buildings", [{}, {}])[1]
	_check(result.ok and int(house.get("paid", -1)) == Sim.construction_value(data, house.type) and int(house.paid) > 0, "buildings get their value (materials and labor at base prices)")
	_check(result.ok and Sim.cash_check(s).ok and int(Sim.cash_check(s).start) == int(s.profile.currency) - 12000, "the cash check adds up")


## Each hour's share is rounded down, so the shares add up exactly to the whole batch.
func test_portions_add_up() -> void:
	var data := _data()
	data.config["wage_bonuses"] = {"none": 0.0, "small": 0.2}
	data.config["bonus_output"] = {"none": 0.0, "small": 0.15}
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "farm", Vector2i(5, 5), T0).building_id)
	_check(int(_batch(state, data, farm, 7, "small").units.wheat) == 80, "7 hours x 10 x 1.15 = 80.5: 80 wheat (rounded down)")
	var got: Array = []
	for hour in range(1, 8):
		Sim.settle(state, data, T0 + 60 * hour)
		got.append(_ready(farm, "wheat"))
	_check(got == [11, 22, 34, 45, 57, 68, 80], "each hour adds its share, ending exactly at 80: %s" % [got])


## Version 8 saves had job queues and building storage: on loading, everything in them goes to
## the Warehouse (queued ingredients back in full, a finished batch as its products).
func test_old_save_queues_go_to_warehouse() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	var mill := Sim.find_building(state, Sim.build(state, data, "mill", Vector2i(5, 5), T0).building_id)
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 8
	for b in old.buildings:
		b.erase("batch")
		b["queue"] = []
		b["blocked"] = false
	var m: Dictionary = old.buildings[-1]
	m.storage = {"flour": 16}
	m["storage_cost"] = {"flour": 160.0}
	m.queue = [{"recipe_id": "mill", "input_cost": {"wheat": 50.0}}, {"recipe_id": "mill", "input_cost": {"wheat": 70.0}}]
	m.blocked = true  # the first job is finished, waiting for room
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	_check(result.ok and int(result.state.save_version) == Sim.SAVE_VERSION, "a version 8 save with queues loads")
	var s: Dictionary = result.state if result.ok else {"inventory": {}, "inventory_cost": {}, "buildings": []}
	var loaded := Sim.find_building(s, mill.id)
	_check(int(s.inventory.get("flour", 0)) == 16 + 8 and int(s.inventory.get("wheat", 0)) == 10, "stored flour + the finished batch's 8 flour, and the waiting job's 10 wheat, are in the warehouse")
	_check(is_equal_approx(float(s.inventory_cost.get("wheat", 0.0)), 70.0) and is_equal_approx(float(s.inventory_cost.get("flour", 0.0)), 160.0 + 8 * 300.0), "with their cost tags (the finished batch at its standard cost)")
	_check(not loaded.is_empty() and loaded.get("batch", null) == {} and not loaded.has("queue") and loaded.storage.is_empty(), "the mill is idle, with no queue and nothing stored")
	_check(_batch(s, data, loaded, 1).ok, "and it takes a batch")


## The test data with roads (plan.md §5.20): the office at (0, 0) is the road hub; $10 a tile.
func _road_data() -> Dictionary:
	var data := _data()
	data.buildings.office["road_hub"] = true
	data.config["roads"] = {"price": 10}
	return data


func _cells(list: Array) -> Array:
	var out := []
	for c in list:
		out.append(Vector2i(int(c[0]), int(c[1])))
	return out


func test_roads() -> void:
	var data := _road_data()
	var state := Sim.new_game(data, T0)
	_check(state.roads.is_empty(), "no starting roads in this data")
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	state.population.current = 2
	Sim.settle(state, data, T0)
	_check(Sim.needs_road(data, farm) and not Sim.on_road(data, farm), "a building with workers needs a road and has none")
	_check(Sim.posts(data, farm, T0) == 0 and Sim.hired(farm) == 0, "no road: no posts, no workers")
	_check(not Sim.needs_road(data, Sim.building_at(state, Vector2i(1, 0))) and not Sim.needs_road(data, state.buildings[0]), "homes and the hub need no road")

	var path := Sim.road_path_for(state, data, farm.id)
	_check(path.size() == 9 and Sim._touches({Vector2i(5, 5): true}, path[0]) and Sim._touches({Vector2i(0, 0): true}, path[-1]), "the shortest road: 9 tiles from beside the farm to beside the office")
	var quote := Sim.road_quote(state, data, path)
	_check(quote.ok and int(quote.cost) == 9000 and state.profile.currency == 50000, "9 tiles at $10 = $90 (a quote changes nothing)")
	_check(Sim.build_roads(state, data, path, T0).ok, "road built")
	_check(state.profile.currency == 41000 and int(state.stats.spending.roads) == 9000 and Sim.cash_check(state).ok, "$90 paid, counted as roads")
	_check(int(Sim.balance_sheet(state, data, T0).roads) == 9000, "the roads count at their price on the balance sheet")
	_check(Sim.on_road(data, farm) and Sim.hired(farm) == 2, "linked: the farm hires its 2 workers at once")
	_check(Sim.road_path_for(state, data, farm.id).is_empty(), "nothing more to lay")

	_check(not Sim.road_quote(state, data, path).ok, "a road on a road: nothing to build")
	var more := Sim.road_quote(state, data, path + _cells([[9, 0], [9, 1]]))
	_check(more.ok and int(more.cost) == 2000, "tiles that are already a road are free")
	_check(not Sim.road_quote(state, data, _cells([[1, 0]])).ok, "no road on a building")
	_check(not Sim.road_quote(state, data, _cells([[10, 0]])).ok, "no road off the land")
	_check(not Sim.can_build(state, data, "farm", path[0], T0).ok, "no building on a road")
	_check(not Sim.can_move(state, data, farm.id, path[0]).ok, "no moving onto a road")
	var cash := int(state.profile.currency)
	state.profile.currency = 500
	_check(not Sim.road_quote(state, data, _cells([[9, 9]])).ok, "no road without the money")
	state.profile.currency = cash
	var hut_spot := Sim._free_cell_near_centre(state, data)
	_check(Sim.is_free_cell(state, hut_spot) and not Sim.is_road(state, hut_spot), "huts go up on free tiles, never on roads")

	# Cut the road: the farm stops and lets its workers go. Mend it: it hires again.
	var middle: Vector2i = path[4]
	_check(Sim.remove_roads(state, data, [middle], T0).ok and not Sim.is_road(state, middle), "a road tile removed")
	_check(not Sim.on_road(data, farm) and Sim.hired(farm) == 0, "cut off: no workers")
	_check(int(state.profile.currency) == cash, "removing is free and pays nothing back")
	_check(not Sim.remove_roads(state, data, [middle], T0).ok, "nothing to remove there any more")
	Sim.build_roads(state, data, [middle], T0)
	_check(Sim.hired(farm) == 2, "mended: workers back")

	# Moving off the road stops it; moving back starts it again.
	_check(Sim.move(state, data, farm.id, Vector2i(9, 9), T0).ok and Sim.hired(farm) == 0, "moved away from the road: no workers")
	_check(Sim.move(state, data, farm.id, Vector2i(5, 5), T0).ok and Sim.hired(farm) == 2, "moved back: workers again")

	# A warehouse can't be cut off while the goods wouldn't fit without it.
	_check(path[-1] == Vector2i(0, 1), "the road reaches the office at (0, 1) (the house is at (1, 0))")
	var store_spot := Vector2i(1, 1) if Sim.is_free_cell(state, Vector2i(1, 1)) else Vector2i(0, 2)  # beside (0, 1)
	var store := Sim.find_building(state, Sim.build(state, data, "crew_store", store_spot, T0).building_id)
	state.population.current = 6
	Sim.settle(state, data, T0)
	_check(Sim.on_road(data, store) and Sim.warehouse_cap(state, data) == 2000, "the linked warehouse with its 4 workers: 2000 room")
	state.inventory["wheat"] = 1500
	_check(not Sim.can_remove_roads(state, data, [Vector2i(0, 1)]).ok, "removing its road would leave goods without room: refused")
	_check(not Sim.can_move(state, data, store.id, Vector2i(9, 8)).ok, "and so would moving it off the road")
	state.inventory["wheat"] = 500
	_check(Sim.can_remove_roads(state, data, [Vector2i(0, 1)]).ok, "with room left in the other warehouse it's fine")


## A building with no road waits; time away gives the same as playing through it.
func test_roads_away_matches_playing() -> void:
	var data := _road_data()
	var make := func() -> Dictionary:
		var s := Sim.new_game(data, T0)
		Sim.build(s, data, "crew_farm", Vector2i(5, 5), T0)
		s.population.current = 2
		Sim.settle(s, data, T0)
		_batch(s, data, s.buildings[-1], 5)
		return s
	var away: Dictionary = make.call()
	var playing: Dictionary = make.call()
	var farm_id: String = away.buildings[-1].id
	var path := Sim.road_path_for(away, data, farm_id)
	Sim.settle(away, data, T0 + 600)
	_check(int(away.buildings[-1].batch.get("made_hours", 0)) == 0, "no road: the batch waits")
	Sim.build_roads(away, data, path, T0 + 600)
	Sim.settle(away, data, T0 + 900)
	for t in range(10, 600, 37):
		Sim.settle(playing, data, T0 + t)
	Sim.build_roads(playing, data, path, T0 + 600)
	for t in range(600, 900, 23):
		Sim.settle(playing, data, T0 + t)
	Sim.settle(playing, data, T0 + 900)
	_check(int(away.buildings[-1].batch.made_hours) == 5, "linked at 600 s: all 5 hours of 60 s are made by 900 s")
	_check(away.buildings[-1].batch == playing.buildings[-1].batch and away.profile.currency == playing.profile.currency, "away = playing through it")


## Saves from before roads get free roads laid to every building that can be reached.
func test_old_save_gets_roads() -> void:
	var data := _road_data()
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(5, 5), T0).building_id)
	# A farm walled in by other farms on every side: no road can reach it.
	var walled := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(8, 8), T0).building_id)
	for c in [[7, 8], [9, 8], [8, 7], [8, 9]]:
		Sim.build(state, data, "farm", Vector2i(c[0], c[1]), T0)
	state.population.current = 10
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 9
	old.erase("roads")
	old.stats.spending.erase("roads")
	for b in old.buildings:
		b.erase("road")
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	_check(result.ok and int(result.state.save_version) == Sim.SAVE_VERSION, "a version 9 save loads")
	var s: Dictionary = result.state if result.ok else new_game_fallback(data)
	_check(s.roads.size() == 9 and Sim.on_road(data, Sim.find_building(s, farm.id)) and Sim.hired(Sim.find_building(s, farm.id)) == 2, "free roads were laid to the farm, and it has its workers")
	_check(not Sim.on_road(data, Sim.find_building(s, walled.id)), "the walled-in farm can't be reached: it says so")
	_check(int(s.stats.spending.roads) == 0 and Sim.cash_check(s).ok and int(Sim.balance_sheet(s, data, T0).roads) == 0, "the free roads cost nothing and are worth nothing")


func new_game_fallback(data: Dictionary) -> Dictionary:
	return Sim.new_game(data, T0)


## Test data with a Construction Office (plan.md §5.15): "crew_office" employs 2 construction
## workers (3 at Level 2) and stays open while upgraded; slow_farm and slow_mill need 1 to build
## (5 s), and each upgrade one more per level. Minimum wage $15.
func _crew_data() -> Dictionary:
	var data := _data()
	data.buildings["crew_office"] = {"category": "construction", "build_cost": 50, "buildable": true, "build_time": 5,
		"max_workers": 2, "fixed_workers": true, "staffed_first": true, "fixed_wage": true, "construction_crew": true,
		"crew": 1, "upgrades": [{"max_workers": 3, "cost": 0, "time": 100}]}
	for type_id in ["slow_farm", "slow_mill"]:
		data.buildings[type_id]["crew"] = 1
	data.buildings.slow_farm["upgrades"] = [{"cost": 0, "time": 50}, {"cost": 0, "time": 50}]
	data.config["construction"] = {"crew_per_level": 1}
	data.config["worker_types"] = {"low_skilled": {"wage_per_hour": 15}}
	data.config.starting_buildings.append({"type": "crew_office", "position": [3, 0]})
	return data


func test_construction_workers() -> void:
	var data := _crew_data()
	var state := Sim.new_game(data, T0)
	_check(Sim.crew_total(state, data, T0) == 0, "nobody lives here yet: no construction workers")
	var none := Sim.can_build(state, data, "slow_farm", Vector2i(5, 5), T0)
	_check(not none.ok and none.error.begins_with("No construction workers"), "no construction workers: nothing can be built")
	_check(Sim.can_build(state, data, "farm", Vector2i(5, 5), T0).ok, "a building that needs no crew can still be built")
	state.population.current = 10
	Sim._hire(state, data, T0)
	var office := Sim.building_at(state, Vector2i(3, 0))
	_check(Sim.hired(office) == 2 and Sim.crew_total(state, data, T0) == 2 and Sim.crew_free(state, data, T0) == 2, "the office hires its 2 construction workers")
	var needs := [int(Sim.construction_needs(data, "slow_farm", 1).crew), int(Sim.construction_needs(data, "slow_farm", 2).crew), int(Sim.construction_needs(data, "slow_farm", 3).crew)]
	_check(needs == [1, 2, 3], "1 worker to build, one more for each level (%s)" % str(needs))
	var farm_id: String = Sim.build(state, data, "slow_farm", Vector2i(5, 5), T0).building_id
	_check(Sim.crew_busy(state, data, T0) == 1 and Sim.crew_free(state, data, T0) == 1, "building the farm keeps 1 busy")
	var labor: Array = Sim.construction_quote(data, "slow_farm", 1, T0).lines.filter(func(l): return l.id == "labor")
	_check(labor.size() == 1 and int(labor[0].amount) == 1, "the quote shows the 1 construction worker")
	_check(Sim.build(state, data, "slow_mill", Vector2i(6, 6), T0).ok and Sim.crew_free(state, data, T0) == 0, "the mill takes the other one")
	var busy := Sim.can_build(state, data, "slow_farm", Vector2i(7, 7), T0 + 1)
	_check(not busy.ok and "only 0 are free" in busy.error and float(busy.get("crew_free_at", 0.0)) == T0 + 5, "all busy: it can't start, and says when one is free (%s)" % busy.error)
	_check(Sim.can_build(state, data, "slow_farm", Vector2i(7, 7), T0 + 5).ok, "once the farm is built its worker is free again")
	# Upgrades: Level 2 needs 2, Level 3 needs 3, more than the office has.
	_check(Sim.upgrade(state, data, farm_id, T0 + 10).ok and Sim.crew_free(state, data, T0 + 10) == 0, "upgrading to Level 2 keeps both busy")
	Sim.settle(state, data, T0 + 60)  # the farm reaches Level 2
	var short := Sim.can_upgrade(state, data, farm_id, T0 + 60)
	_check(not short.ok and "have only 2" in short.error and not short.has("crew_free_at"), "Level 3 needs 3: more than the office has (%s)" % short.error)
	# A bigger office: it stays open while upgraded, and has 3 workers afterwards.
	_check(Sim.upgrade(state, data, office.id, T0 + 60).ok and Sim.crew_total(state, data, T0 + 61) == 2, "the office stays open while upgraded")
	Sim.settle(state, data, T0 + 160)
	_check(Sim.crew_total(state, data, T0 + 160) == 3 and Sim.can_upgrade(state, data, farm_id, T0 + 160).ok, "Level 2 office: 3 workers, enough for Level 3")
	_check(Sim.building_wages(state, data, office, T0 + 160) == 0.0, "construction workers aren't paid by the hour")
	var wages := int(Sim.stats(state).spending.wages)
	Sim.settle(state, data, T0 + 7360)
	_check(int(Sim.stats(state).spending.wages) == wages, "two hours later still no wages for them (paid per project)")
	# The last office can't go; with a second one it can.
	_check(not Sim.can_demolish(state, data, office.id).ok, "the last Construction Office can't be demolished")
	var second: String = Sim.build(state, data, "crew_office", Vector2i(8, 8), T0 + 7360).building_id
	_check(second != "" and Sim.can_demolish(state, data, office.id).ok, "with a second office, one can go")
	# Without a Construction Office in the data (the other tests), nothing needs a crew.
	_check(not Sim.crew_on(_data()) and Sim.crew_on(data), "no Construction Office type: building needs no workers")


## A version 10 save: its headquarters (saved as "construction_office") becomes City Hall, and it
## gets a free Construction Office beside its roads, staffed first.
func test_old_save_gets_construction_office() -> void:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	var state := Sim.new_game(data, T0)
	var old := JSON.parse_string(SaveFormat.to_text(state, T0)) as Dictionary
	old.save_version = 10
	old.buildings = old.buildings.filter(func(b): return b.type != "construction_office")
	for b in old.buildings:
		if b.type == "city_hall":
			b.type = "construction_office"  # its id before version 11
	var capital := int(old.stats.capital.buildings) - Sim.construction_value(data, "construction_office")
	old.stats.capital.buildings = capital
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	_check(result.ok and int(result.state.save_version) == Sim.SAVE_VERSION, "a version 10 save loads")
	var s: Dictionary = result.state if result.ok else new_game_fallback(data)
	var halls: Array = s.buildings.filter(func(b): return b.type == "city_hall")
	var offices: Array = s.buildings.filter(func(b): return b.type == "construction_office")
	_check(halls.size() == 1 and Sim.is_road_hub(data, halls[0]), "the old headquarters is City Hall, where roads start")
	_check(offices.size() == 1 and Sim.on_road(data, offices[0]) and Sim.is_built(offices[0], T0), "it got a Construction Office, standing beside a linked road")
	_check(offices.size() == 1 and Sim.hired(offices[0]) == 4 and Sim.crew_free(s, data, T0) == 4, "its 4 construction workers are hired")
	_check(int(s.stats.capital.buildings) == capital + Sim.construction_value(data, "construction_office") and Sim.cash_check(s).ok, "it counts in the starting capital at its value")
