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
			"house": {"category": "residential", "build_cost": 0, "buildable": false, "population_capacity": 10},
			# The starter warehouse: 1000 room, no workers (so the other tests' people counts don't change).
			"store": {"category": "storage", "build_cost": 300, "buildable": true, "capacity": 1000},
			# A warehouse with workers: 4 of 4 working = 1000 room, 2 of 4 = 500.
			"crew_store": {"category": "storage", "build_cost": 0, "buildable": true, "capacity": 1000, "max_workers": 4, "fixed_workers": true, "staffed_first": true, "fixed_wage": true},
			"farm": {"category": "extractor", "build_cost": 100, "buildable": true, "storage_cap": 100,
				"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]},
			"mill": {"category": "processor", "build_cost": 200, "buildable": true, "storage_cap": 16, "queue_size": 4,
				"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 90}]},
			# Same as farm / mill, but they take time to build (the ones above are instant, to keep
			# the other tests simple). The cabin is a home that takes a long time to build.
			"slow_farm": {"category": "extractor", "build_cost": 100, "buildable": true, "build_time": 5, "storage_cap": 100,
				"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]},
			"slow_mill": {"category": "processor", "build_cost": 200, "buildable": true, "build_time": 5, "storage_cap": 16, "queue_size": 4,
				"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 90}]},
			"cabin": {"category": "residential", "build_cost": 0, "buildable": true, "build_time": 200, "population_capacity": 5},
			# Buildings that need workers (2 and 3 jobs). They slow down when there aren't enough people.
			"crew_farm": {"category": "extractor", "build_cost": 0, "buildable": true, "max_workers": 2, "storage_cap": 1000,
				"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]},
			"crew_mill": {"category": "processor", "build_cost": 0, "buildable": true, "max_workers": 3, "storage_cap": 100, "queue_size": 8,
				"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 90}]},
		},
		"config": {"starting_cash": 500, "population_growth_seconds": 10,
			"grid_size": [10, 10],
			"cancel_refund_in_progress": 0.5, "cancel_refund_waiting": 1.0, "demolish_refund": 0.5,
			"starting_buildings": [{"type": "office", "position": [0, 0]}, {"type": "house", "position": [1, 0]},
				{"type": "store", "position": [2, 0]}]},
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
	_check(state.profile.currency == 50000, "starting cash ($500 = 50000 cents)")
	_check(state.buildings.size() == 3, "starter buildings placed")
	_check(Sim.population_capacity(state, data, T0) == 10, "house gives population capacity")
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
	_check(Sim.can_build(state, data, "farm", Vector2i(3, 3)).ok, "can_build says yes on a free spot")
	_check(state.buildings.size() == before and state.profile.currency == 50000, "can_build changes nothing")
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


func test_can_enqueue_matches_enqueue() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	var no_wheat: Dictionary = Sim.can_enqueue(state, data, mill.id, "mill", T0)
	_check(not no_wheat.ok and no_wheat.error == "Not enough Wheat.", "can_enqueue explains missing inputs")
	state.inventory["wheat"] = 10
	_check(Sim.can_enqueue(state, data, mill.id, "mill", T0).ok, "can_enqueue says yes with enough wheat")
	_check(state.inventory.wheat == 10 and mill.queue.is_empty(), "can_enqueue changes nothing")
	var farm_id: String = Sim.build(state, data, "farm", Vector2i(6, 6), T0).building_id
	_check(not Sim.can_enqueue(state, data, farm_id, "grow", T0).ok, "extractors don't take orders")
	state.inventory["wheat"] = 40
	for i in 4:
		Sim.enqueue(state, data, mill.id, "mill", T0)
	state.inventory["wheat"] = 10
	_check(not Sim.can_enqueue(state, data, mill.id, "mill", T0).ok, "can_enqueue sees a full queue")


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
	_check(not Sim.sell(state, data, "wheat", 5, T0).ok, "can't sell more than you have")
	_check(not Sim.sell(state, data, "wheat", 0, T0).ok, "can't sell zero")
	var result := Sim.sell(state, data, "wheat", 3, T0)
	_check(result.ok and result.earned == 600, "3 wheat x $2 = $6 (600 cents)")
	_check(state.profile.currency == 50600 and not state.inventory.has("wheat"), "money in, wheat out")


func test_cancel_job() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 30
	for i in 3:
		Sim.enqueue(state, data, mill.id, "mill", T0)
	_check(not Sim.cancel_job(state, data, mill.id, 5, T0).ok, "can't cancel an empty slot")
	var preview: Dictionary = Sim.can_cancel_job(state, data, mill.id, 2)
	_check(preview.ok and preview.refund.wheat == 10 and mill.queue.size() == 3, "preview shows refund, changes nothing")
	var waiting := Sim.cancel_job(state, data, mill.id, 2, T0 + 30)
	_check(waiting.ok and state.inventory.get("wheat", 0) == 10, "waiting job refunds all its wheat")
	var active := Sim.cancel_job(state, data, mill.id, 0, T0 + 30)
	_check(active.ok and active.in_progress and state.inventory.wheat == 15, "job in progress refunds half")
	_check(mill.queue.size() == 1, "one job left")
	Sim.settle(state, data, T0 + 119)
	_check(mill.storage.is_empty(), "next job starts fresh from the cancel (not done at 119s)")
	Sim.settle(state, data, T0 + 120)
	_check(mill.storage.get("flour", 0) == 8, "next job done 90s after the cancel")


func test_cancel_finished_or_full() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 40
	for i in 4:
		Sim.enqueue(state, data, mill.id, "mill", T0)
	Sim.settle(state, data, T0 + 1000)  # 2 jobs fill storage, job 3 finished but waiting
	_check(not Sim.cancel_job(state, data, mill.id, 0, T0 + 1000).ok, "a finished batch can't be cancelled")
	state.inventory["flour"] = 1000  # warehouse full
	var full: Dictionary = Sim.cancel_job(state, data, mill.id, 1, T0 + 1000)
	_check(not full.ok and mill.queue.size() == 2, "no cancel when the refund won't fit")


func test_demolish() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	state.inventory["wheat"] = 20
	Sim.enqueue(state, data, mill.id, "mill", T0)
	Sim.enqueue(state, data, mill.id, "mill", T0)
	Sim.settle(state, data, T0 + 90)  # job 1 done (8 flour inside), job 2 just started
	var cash: int = state.profile.currency
	var result := Sim.demolish(state, data, mill.id, T0 + 90)
	_check(result.ok and Sim.find_building(state, mill.id).is_empty(), "mill is gone")
	_check(state.profile.currency == cash + 10000, "half the 200 build cost back")
	_check(state.inventory.get("flour", 0) == 8 and state.inventory.get("wheat", 0) == 5, "goods inside + half of the job in progress")
	_check(Sim.can_build(state, data, "farm", Vector2i(5, 5)).ok, "the spot is free again")
	_check(not Sim.demolish(state, data, "b1", T0).ok, "starter buildings can't be demolished")


func test_move() -> void:
	var s: Array = _setup("farm")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	_check(not Sim.move(state, farm.id, Vector2i(0, 0)).ok, "can't move onto another building")
	_check(not Sim.move(state, farm.id, Vector2i(10, 3)).ok, "can't move outside the land")
	_check(Sim.can_move(state, farm.id, Vector2i(5, 5)).ok, "dropping it back on its own tile is fine")
	Sim.settle(state, data, T0 + 30)  # half way through a cycle
	_check(Sim.move(state, farm.id, Vector2i(7, 2)).ok, "can move to a free tile")
	_check(Sim.building_at(state, Vector2i(7, 2)).id == farm.id, "farm is on its new tile")
	_check(Sim.can_build(state, data, "farm", Vector2i(5, 5)).ok, "old tile is free again")
	Sim.settle(state, data, T0 + 60)
	_check(farm.storage.get("wheat", 0) == 10, "production carries on through a move")
	_check(Sim.move(state, "b1", Vector2i(8, 8)).ok, "starter buildings can move too")


func test_fill_queue() -> void:
	var s: Array = _setup("mill")
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var mill: Dictionary = s[2]
	_check(Sim.batches_possible(state, data, mill.id, "mill", T0) == 0, "no wheat: 0 batches")
	_check(not Sim.fill_queue(state, data, mill.id, "mill", T0).ok, "fill refuses with nothing to add")
	state.inventory["wheat"] = 25
	_check(Sim.batches_possible(state, data, mill.id, "mill", T0) == 2, "25 wheat = 2 batches of 10")
	var result := Sim.fill_queue(state, data, mill.id, "mill", T0)
	_check(result.ok and result.added == 2 and result.used.wheat == 20, "fills 2, uses 20 wheat")
	_check(mill.queue.size() == 2 and state.inventory.wheat == 5, "queue has 2, 5 wheat left over")
	state.inventory["wheat"] = 100
	_check(Sim.fill_queue(state, data, mill.id, "mill", T0).added == 2, "stops at the queue size (4)")
	_check(state.inventory.wheat == 80, "only used what fitted")


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
	Sim.settle(state, data, T0 + 64)
	_check(farm.storage.is_empty(), "nothing grows while being built (first cycle starts when built)")
	Sim.settle(state, data, T0 + 65)
	_check(Sim.is_built(farm, T0 + 5) and int(farm.storage.get("wheat", 0)) == 10, "first batch 60s after construction ends")
	state.inventory["wheat"] = 50
	var mill := Sim.find_building(state, Sim.build(state, data, "slow_mill", Vector2i(4, 4), T0 + 100).building_id)
	var early: Dictionary = Sim.enqueue(state, data, mill.id, "mill", T0 + 101)
	_check(not early.ok and early.error == "Still under construction.", "can't queue jobs during construction")
	_check(int(state.inventory.wheat) == 50, "a refused job takes no ingredients")
	_check(Sim.enqueue(state, data, mill.id, "mill", T0 + 105).ok, "jobs can be queued once built")


func test_home_under_construction() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "cabin", Vector2i(3, 3), T0)  # +5 room, finished at T0 + 200
	_check(Sim.population_capacity(state, data, T0 + 199) == 10, "a home being built adds no room yet")
	_check(Sim.population_capacity(state, data, T0 + 200) == 15, "finished home adds its room")
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
	var rates := Sim.production_rates(state, data, T0 + 1)
	_check(is_equal_approx(float(rates.made.get("wheat", 0)), 10.0), "farm makes 10 wheat/min (the slow farm is still being built)")
	_check(rates.buildings.working == 1 and rates.buildings.idle == 1 and rates.buildings.building == 1, "counts working / idle / being built")
	state.inventory["wheat"] = 10
	Sim.enqueue(state, data, mill.id, "mill", T0 + 1)
	rates = Sim.production_rates(state, data, T0 + 2)
	_check(is_equal_approx(float(rates.used.wheat), 10.0 * 60.0 / 90.0), "mill uses wheat per minute while working")
	_check(is_equal_approx(float(rates.made.flour), 8.0 * 60.0 / 90.0), "mill makes flour per minute while working")
	Sim.settle(state, data, T0 + 700)  # both farms fill their storage (100) within 10 minutes
	rates = Sim.production_rates(state, data, T0 + 700)
	_check(rates.buildings.full == 2 and not rates.made.has("wheat"), "full farms make nothing")
	_check(farm.storage.wheat == 100, "farm really is full")


func test_employment() -> void:
	var data := _data()
	var state := Sim.new_game(data, T0)
	Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0)  # 2 jobs
	var mill_id: String = Sim.build(state, data, "crew_mill", Vector2i(4, 4), T0).building_id  # 3 jobs
	_check(Sim.employment(state, data, T0).jobs == 5, "a mill with nothing queued still offers its posts (its workers wait, unpaid)")
	state.inventory["wheat"] = 20
	Sim.fill_queue(state, data, mill_id, "mill", T0)  # 2 batches: busy for the whole test
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
	_check(is_equal_approx(Sim.staffing(state, data, T0), 0.5), "1 person for 2 jobs: half speed")
	Sim.settle(state, data, T0 + 119)
	_check(farm.storage.is_empty(), "at half speed a 60s batch isn't done after 119s")
	Sim.settle(state, data, T0 + 120)
	_check(int(farm.storage.get("wheat", 0)) == 10, "at half speed a 60s batch takes 120s")
	_check(is_equal_approx(float(Sim.production_rates(state, data, T0 + 120).made.wheat), 5.0), "rates show the slower speed")
	Sim.settle(state, data, T0 + 150)
	_check(is_equal_approx(Sim.job_progress(state, farm, data, T0 + 150), 0.25), "progress bar moves at half speed")
	state.population.current = 2  # fully staffed from T0 + 150
	Sim.settle(state, data, T0 + 195)
	_check(int(farm.storage.get("wheat", 0)) == 20, "full speed again once staffed (15s + 45s of work)")

	var empty := Sim.new_game(data, T0)
	var idle := Sim.find_building(empty, Sim.build(empty, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	Sim.settle(empty, data, T0 + 600)
	_check(idle.storage.is_empty(), "nobody to work: nothing is made")
	empty.population.current = 2
	Sim.settle(empty, data, T0 + 659)
	_check(idle.storage.is_empty(), "work starts from scratch when people arrive (not 10 minutes ahead)")
	Sim.settle(empty, data, T0 + 660)
	_check(int(idle.storage.get("wheat", 0)) == 10, "first batch 60s after people arrive")


## Being away for a long time must give exactly the same result as playing the whole time,
## even while people move in, a home finishes and the staffing keeps changing.
func test_away_matches_playing() -> void:
	var data := _data()
	var played := Sim.new_game(data, T0)
	var away := Sim.new_game(data, T0)
	for state in [played, away]:
		for x in 4:
			Sim.build(state, data, "crew_farm", Vector2i(x, 5), T0)  # 4 x 2 jobs
		var mill_id: String = Sim.build(state, data, "crew_mill", Vector2i(6, 6), T0).building_id  # 3 jobs: 11 in all
		Sim.build(state, data, "cabin", Vector2i(8, 8), T0)  # room for 15 people from T0 + 200
		state.inventory["wheat"] = 80
		Sim.fill_queue(state, data, mill_id, "mill", T0)
	var t := T0
	while t < T0 + 3000:
		t += 7.0
		Sim.settle(played, data, t)
	Sim.settle(away, data, t)
	var same: bool = played.population.current == away.population.current
	for i in played.buildings.size():
		same = same and played.buildings[i].storage == away.buildings[i].storage
		same = same and played.buildings[i].queue.size() == away.buildings[i].queue.size()
	_check(same, "one long absence = playing in 7-second steps (population, storage, queues)")
	_check(int(away.population.current) == 15 and Sim.staffing(away, data, t) == 1.0, "the cabin let enough people in to fill every job (15 people, 11 jobs)")
	var made := 0
	for b in away.buildings:
		made += int(b.storage.get("wheat", 0))
	_check(made > 0 and made < 4 * 10 * 3000 / 60, "short-staffed early on, so less wheat than 4 full-speed farms")


## A test town with one 8-worker farm, enough people, and wages of 36/hour per worker
## (so 8 workers cost 288/hour = 0.08 per second). Returns [state, data, farm].
func _wage_town() -> Array:
	var data := _data()
	data.config["population_growth_seconds"] = 0  # people only change when the test says so
	data.config["staffing_levels"] = {"low": 0.5, "medium": 0.75, "high": 1.0}
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	data.buildings["big_farm"] = {"category": "extractor", "build_cost": 0, "buildable": true,
		"max_workers": 8, "worker_type": "low_skilled", "storage_cap": 1000,
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
	_check(Sim.workers_wanted(data, farm) == 8 and is_equal_approx(Sim.building_speed(state, data, farm, T0), 1.0), "new buildings start at High: 8 of 8 workers, full speed")
	_check(Sim.set_staffing(state, data, farm.id, "low", T0).ok, "staffing can be changed")
	_check(Sim.workers_wanted(data, farm) == 4 and is_equal_approx(Sim.building_speed(state, data, farm, T0), 0.5), "Low: 4 workers, half speed")
	Sim.settle(state, data, T0 + 119)
	_check(farm.storage.is_empty(), "at Low a 60s batch isn't done after 119s")
	Sim.settle(state, data, T0 + 120)
	_check(int(farm.storage.get("wheat", 0)) == 10, "at Low a 60s batch takes 120s")
	Sim.set_staffing(state, data, farm.id, "medium", T0 + 120)
	_check(Sim.workers_wanted(data, farm) == 6 and is_equal_approx(Sim.building_speed(state, data, farm, T0 + 120), 0.75), "Medium: 6 workers, 75% speed")
	_check(Sim.employment(state, data, T0 + 120).jobs == 6, "jobs follow the staffing level")
	state.population.current = 3  # 7 people moved away
	Sim.settle(state, data, T0 + 120)
	_check(is_equal_approx(Sim.workers_working(state, data, farm, T0 + 120), 3.0) and is_equal_approx(Sim.building_speed(state, data, farm, T0 + 120), 3.0 / 8.0), "only 3 people for 6 jobs: 3 working, 3/8 speed")
	_check(not Sim.set_staffing(state, data, farm.id, "huge", T0).ok, "unknown staffing levels are refused")
	_check(not Sim.set_staffing(state, data, state.buildings[1].id, "low", T0).ok, "a house has no workers to set")


func test_wages_and_debt() -> void:
	var s := _wage_town()
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	state.profile.currency = 5000  # $50 (money is in cents)
	var report := Sim.settle(state, data, T0 + 1000)  # 8 workers x $36/h for 1000 s = $80
	_check(state.profile.currency == -3000, "wages are paid over time and cash can go below 0 (debt)")
	_check(int(report.get("wages", 0)) == 8000 and int(Sim.stats(state).spending.wages) == 8000, "wages show in the report and the statistics")
	_check(not Sim.build(state, data, "farm", Vector2i(5, 5), T0 + 1000).ok, "can't build while in debt")
	Sim.set_staffing(state, data, farm.id, "low", T0 + 1000)
	Sim.settle(state, data, T0 + 2000)  # 4 workers x $36/h for 1000 s = $40
	_check(state.profile.currency == -7000, "Low staffing halves the wages")
	state.population.current = 0
	Sim.settle(state, data, T0 + 3000)
	_check(state.profile.currency == -7000, "nobody working, no wages")

	var t := _wage_town()
	var steps: Dictionary = t[0]
	var at := T0
	while at < T0 + 1000:
		at = minf(at + 0.7, T0 + 1000)  # the last step ends exactly at 1000 s
		Sim.settle(steps, data, at)
	_check(int(Sim.stats(steps).spending.wages) == 8000, "wages in many tiny steps add up to the same $80 (parts of a cent carried over)")

	var u := _wage_town()
	var building: Dictionary = u[0]
	building.profile.currency = 10000
	Sim.build(building, data, "slow_farm", Vector2i(6, 6), T0)  # no workers needed
	data.buildings.slow_farm["max_workers"] = 8
	Sim.find_building(building, building.buildings[-1].id)["built_at"] = T0 + 10_000.0
	Sim.set_staffing(building, data, u[2].id, "low", T0)  # the big farm: 4 workers
	Sim.settle(building, data, T0 + 1000)
	_check(int(Sim.stats(building).spending.wages) == 4000, "a building under construction pays no wages")


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


## A town whose 8-worker farm fills its storage (100) after 600 s at full speed.
func _filling_town() -> Array:
	var s := _wage_town()
	s[1].buildings.big_farm["storage_cap"] = 100
	return s


func test_halted_buildings_pay_no_wages() -> void:
	var s := _filling_town()
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var farm: Dictionary = s[2]
	Sim.settle(state, data, T0 + 3600)  # away an hour; the farm filled up after 10 minutes
	_check(int(farm.storage.wheat) == 100 and Sim.is_halted(data, farm), "full storage halts the farm")
	_check(int(Sim.stats(state).spending.wages) == 4800, "wages stopped the moment it filled (600 s x 8 x $36/h = $48), not after the hour")
	_check(Sim.workers_working(state, data, farm, T0 + 3600) == 0.0 and Sim.hired(farm) == 8, "a halted building's workers stop working but stay tied to it")
	Sim.collect(state, data, farm.id, T0 + 3600)
	Sim.settle(state, data, T0 + 3660)
	_check(int(farm.storage.get("wheat", 0)) == 10 and not Sim.is_halted(data, farm), "collecting restarts it")

	var t := _filling_town()
	var steps: Dictionary = t[0]
	var at := T0
	while at < T0 + 3600:
		at = minf(at + 7.0, T0 + 3600)
		Sim.settle(steps, t[1], at)
	_check(int(Sim.stats(steps).spending.wages) == 4800, "same wages when playing in 7-second steps")

	var mill := {"type": "x", "blocked": true}
	data.buildings["x"] = {"category": "processor", "max_workers": 8}
	_check(Sim.is_halted(data, mill), "a mill with a finished batch and no room is halted too")


## A Mill or Bakery with nothing queued pays no wages (plan.md §5.6): workers are only paid while
## producing. Wages stop the moment the last job is done, even while the player is away.
func test_idle_buildings_pay_no_wages() -> void:
	var s := _wage_town()  # $36/hour per worker
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	data.buildings["big_mill"] = {"category": "processor", "build_cost": 0, "buildable": true,
		"max_workers": 8, "worker_type": "low_skilled", "storage_cap": 1000, "queue_size": 8,
		"recipes": [{"id": "mill", "inputs": {"wheat": 10}, "outputs": {"flour": 8}, "duration": 300}]}
	state.population.current = 20  # enough for the farm and the mill
	var mill := Sim.find_building(state, Sim.build(state, data, "big_mill", Vector2i(6, 6), T0).building_id)
	_check(Sim.is_idle(data, mill) and Sim.workers_working(state, data, mill, T0) == 0.0, "an empty mill is idle: nobody working")
	Sim.settle(state, data, T0 + 600)  # only the farm works: 8 x $36/h x 600 s = $48
	_check(int(Sim.stats(state).spending.wages) == 4800, "an idle mill pays no wages")
	state.inventory["wheat"] = 20
	Sim.fill_queue(state, data, mill.id, "mill", T0 + 600)  # 2 jobs = 600 s of work
	_check(Sim.workers_working(state, data, mill, T0 + 600) == 8.0, "queuing a job brings the workers in")
	Sim.settle(state, data, T0 + 3600)  # away; the mill finished at T0 + 1200
	# farm 3600 s ($288) + mill 600 s ($48)
	_check(int(Sim.stats(state).spending.wages) == 28800 + 4800, "wages stopped the moment the last job was done")
	_check(int(mill.storage.get("flour", 0)) == 16 and Sim.is_idle(data, mill), "both batches made, then idle")

	var t := _wage_town()
	var steps: Dictionary = t[0]
	t[1].buildings["big_mill"] = data.buildings.big_mill
	steps.population.current = 20
	var mill2: String = Sim.build(steps, t[1], "big_mill", Vector2i(6, 6), T0).building_id
	steps.inventory["wheat"] = 20
	Sim.fill_queue(steps, t[1], mill2, "mill", T0 + 600)
	var at := T0 + 600
	while at < T0 + 3600:
		at = minf(at + 7.0, T0 + 3600)
		Sim.settle(steps, t[1], at)
	Sim.settle(steps, t[1], T0 + 3600)
	_check(int(Sim.stats(steps).spending.wages) == 28800 + 4800, "same wages when playing in 7-second steps")


func test_halted_building_keeps_workers() -> void:
	var s := _filling_town()
	var state: Dictionary = s[0]
	var data: Dictionary = s[1]
	var first: Dictionary = s[2]
	data.buildings["roomy_farm"] = data.buildings.big_farm.duplicate()
	data.buildings.roomy_farm["storage_cap"] = 10_000
	var second := Sim.find_building(state, Sim.build(state, data, "roomy_farm", Vector2i(6, 6), T0).building_id)
	_check(Sim.hired(first) == 8 and Sim.hired(second) == 2, "10 people: the first farm hired its 8 when it opened, the second gets the other 2")
	state.population.current = 8  # 2 people moved away
	Sim.settle(state, data, T0)
	_check(Sim.hired(first) == 8 and Sim.hired(second) == 0, "with equal bonuses, the newest building loses its workers first")
	Sim.settle(state, data, T0 + 700)  # the first farm fills after 600 s
	_check(Sim.is_halted(data, first), "first farm full")
	_check(Sim.hired(first) == 8 and Sim.building_speed(state, data, second, T0 + 700) == 0.0, "its workers stay tied to it: the other farm doesn't get them")
	Sim.suspend(state, data, first.id, T0 + 700)
	_check(Sim.hired(first) == 0 and is_equal_approx(Sim.building_speed(state, data, second, T0 + 700), 1.0), "suspending frees them: they fill the other farm's open posts")


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
	var report := Sim.settle(s[0], s[1], T0 + 300)
	_check(report.get("wheat", 0) == 50, "report lists what was produced while away")


## Saving and loading part-way through changes nothing: the loaded game carries on exactly like
## one that was never closed (cash, wages, tax, storage, queues, people, statistics).
func test_save_round_trip() -> void:
	var data := _data()
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	data.config["sales_tax_brackets"] = [{"from": 0, "rate": 0.0}, {"from": 6, "rate": 0.5}]
	var kept := Sim.new_game(data, T0)
	for x in 3:
		Sim.build(kept, data, "crew_farm", Vector2i(x, 5), T0)
	var mill_id: String = Sim.build(kept, data, "crew_mill", Vector2i(6, 6), T0).building_id
	Sim.build(kept, data, "cabin", Vector2i(8, 8), T0)  # finishes after the save
	kept.inventory["wheat"] = 60
	Sim.fill_queue(kept, data, mill_id, "mill", T0)
	var saved_at := T0 + 123.456789  # an awkward time, to catch rounding in the file
	Sim.settle(kept, data, saved_at)
	Sim.set_staffing(kept, data, mill_id, "low", saved_at)
	kept.inventory["wheat"] = int(kept.inventory.get("wheat", 0)) + 5  # the mill's queue took the rest
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
	Sim.settle(state, data, T0 + 1063)
	_check(not Sim.collect(state, data, farm.id, T0 + 1063).ok, "over the room: nothing more comes in")

	var one := Sim.new_game(data, T0)
	_check(not Sim.can_demolish(one, data, one.buildings[2].id).ok, "the last warehouse can't be demolished")
	Sim.build(one, data, "store", Vector2i(5, 5), T0)
	one.inventory["wheat"] = 1500
	_check(not Sim.can_demolish(one, data, one.buildings[2].id).ok, "nor one whose goods wouldn't fit in the others")
	one.inventory["wheat"] = 900
	_check(Sim.demolish(one, data, one.buildings[2].id, T0).ok and Sim.warehouse_cap(one, data) == 1000, "a warehouse can go when the rest has room")


## Suspend = a "soft demolish" that keeps the building: progress lost, goods back, workers home.
func test_suspend_and_resume() -> void:
	var data := _data()
	data.config["population_growth_seconds"] = 0
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 36}}
	var state := Sim.new_game(data, T0)
	state.population.current = 10
	var mill := Sim.find_building(state, Sim.build(state, data, "crew_mill", Vector2i(5, 5), T0).building_id)
	state.inventory["wheat"] = 30
	Sim.fill_queue(state, data, mill.id, "mill", T0)  # 3 jobs of 10 wheat
	Sim.settle(state, data, T0 + 45)  # half way through the first
	_check(not Sim.can_suspend(state, data, state.buildings[1].id).ok, "a house has nothing to switch off")
	var check := Sim.can_suspend(state, data, mill.id)
	_check(check.ok and int(check.goods.wheat) == 5 + 20, "preview: half of the batch being made + all of the waiting ones")
	var result := Sim.suspend(state, data, mill.id, T0 + 45)
	_check(result.ok and int(state.inventory.wheat) == 25 and mill.queue.is_empty(), "suspending empties the queue into the warehouse")
	_check(Sim.is_suspended(mill) and Sim.workers_working(state, data, mill, T0 + 45) == 0.0 and Sim.employment(state, data, T0 + 45).jobs == 0, "its workers go home")
	var wages_before := int(Sim.stats(state).spending.wages)
	Sim.settle(state, data, T0 + 5000)
	_check(int(Sim.stats(state).spending.wages) == wages_before and mill.storage.is_empty(), "suspended: no wages, nothing made")
	_check(not Sim.can_enqueue(state, data, mill.id, "mill", T0 + 5000).ok, "no jobs while suspended")
	_check(not Sim.suspend(state, data, mill.id, T0 + 5000).ok, "can't suspend twice")
	_check(Sim.resume(state, data, mill.id, T0 + 5000).ok and not Sim.is_suspended(mill), "resume switches it back on")
	_check(Sim.enqueue(state, data, mill.id, "mill", T0 + 5000).ok, "and it takes jobs again")

	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(6, 6), T0 + 5000).building_id)
	Sim.settle(state, data, T0 + 5150)  # 2 batches + half of the third
	Sim.suspend(state, data, farm.id, T0 + 5150)
	_check(int(state.inventory.wheat) == 15 + 20, "a farm's wheat goes to the warehouse")
	Sim.resume(state, data, farm.id, T0 + 6000)
	Sim.settle(state, data, T0 + 6059)
	_check(farm.storage.is_empty(), "the half-grown field was lost: it starts from the beginning")
	Sim.settle(state, data, T0 + 6060)
	_check(int(farm.storage.get("wheat", 0)) == 10, "first batch a full cycle after resuming")

	state.inventory["flour"] = 1000 - Sim.warehouse_total(state) - 4  # room for only 4 more
	Sim.settle(state, data, T0 + 6120)
	result = Sim.suspend(state, data, farm.id, T0 + 6120)  # 20 wheat inside
	_check(int(result.moved.wheat) == 4 and int(farm.storage.wheat) == 16, "what doesn't fit stays inside, to collect later")
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


## Whole workers, tied to their building, hired by wage bonus (plan.md §5.6).
func test_hiring_by_bonus() -> void:
	var data := _bonus_data()
	var state := Sim.new_game(data, T0)
	var a := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	var b := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(4, 4), T0).building_id)
	_check(Sim.set_bonus(state, data, b.id, "good", T0).ok, "a bonus can be chosen")
	_check(not Sim.set_bonus(state, data, b.id, "huge", T0).ok and not Sim.set_bonus(state, data, state.buildings[1].id, "big", T0).ok, "unknown bonuses, or a house, are refused")
	_check(is_equal_approx(Sim.wage_per_worker(data, a), 15.0) and is_equal_approx(Sim.wage_per_worker(data, b), 21.0), "wage = minimum $15 + bonus ($15 + 40% = $21)")
	state.population.current = 3
	Sim.settle(state, data, T0)
	_check(Sim.hired(b) == 2 and Sim.hired(a) == 1, "the bigger bonus fills first: 2 there, the 3rd person to the other")
	_check(is_equal_approx(Sim.building_wages(state, data, b, T0), 42.0), "its wage bill: 2 x $21")
	Sim.set_staffing(state, data, b.id, "low", T0)  # 2 posts -> 1
	_check(Sim.hired(b) == 1 and Sim.hired(a) == 2, "lowering its staffing frees a worker, who takes the open post elsewhere")
	Sim.set_bonus(state, data, a.id, "none", T0)
	Sim.set_staffing(state, data, b.id, "high", T0)  # an open post again, but nobody is free
	_check(Sim.hired(b) == 1 and Sim.hired(a) == 2, "workers are tied: an open post never pulls them from another building")
	Sim.set_bonus(state, data, b.id, "big", T0)
	_check(Sim.hired(a) == 2, "not even with a bigger bonus")
	state.population.current = 4
	Sim.settle(state, data, T0)
	_check(Sim.hired(b) == 2, "but the next person to move in takes it")

	var even := Sim.new_game(data, T0)
	var farms: Array = []
	for x in 3:
		farms.append(Sim.find_building(even, Sim.build(even, data, "crew_farm", Vector2i(x, 5), T0).building_id))
	even.population.current = 3
	Sim.settle(even, data, T0)
	_check(Sim.hired(farms[0]) == 1 and Sim.hired(farms[1]) == 1 and Sim.hired(farms[2]) == 1, "equal bonuses: they take turns, one each")
	even.population.current = 2
	Sim.settle(even, data, T0)
	_check(Sim.hired(farms[2]) == 0 and Sim.hired(farms[0]) == 1, "fewer people: the newest building (same bonus) loses first")
	Sim.set_bonus(even, data, farms[2].id, "small", T0)
	even.population.current = 3
	Sim.settle(even, data, T0)
	Sim.set_bonus(even, data, farms[0].id, "big", T0)
	even.population.current = 2
	Sim.settle(even, data, T0)
	_check(Sim.hired(farms[1]) == 0 and Sim.hired(farms[0]) == 1 and Sim.hired(farms[2]) == 1, "fewer people: the smallest bonus loses first")
	var e := Sim.employment(even, data, T0)
	_check(e.jobs == 6 and e.employed == 2 and e.unemployed == 0 and e.open_jobs == 4, "employment counts whole, hired people")


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
	var played := Sim.new_game(data, T0)
	var away := Sim.new_game(data, T0)
	for state in [played, away]:
		Sim.build(state, data, "cabin", Vector2i(8, 8), T0)  # room for 5 more people from T0 + 200
		for x in 3:
			Sim.build(state, data, "crew_farm", Vector2i(x, 5), T0)
		Sim.build(state, data, "slow_farm", Vector2i(5, 5), T0)  # finishes at T0 + 5
		Sim.set_bonus(state, data, state.buildings[4].id, "good", T0)
		Sim.set_bonus(state, data, state.buildings[5].id, "small", T0)
	data.buildings.slow_farm["max_workers"] = 2
	var t := T0
	while t < T0 + 3000:
		t += 7.0
		Sim.settle(played, data, t)
	Sim.settle(away, data, t)
	var same: bool = played.population.current == away.population.current and played.profile.currency == away.profile.currency
	for i in played.buildings.size():
		same = same and Sim.hired(played.buildings[i]) == Sim.hired(away.buildings[i]) and played.buildings[i].storage == away.buildings[i].storage
	_check(same, "one long absence = playing in 7-second steps (people, hired workers, storage, cash)")
	_check(Sim.hired(away.buildings[4]) == 2 and Sim.hired(away.buildings[5]) == 2, "the buildings with bonuses were filled")


## The public water supply (plan.md §5.13): a meter records what buildings draw while they
## produce; every cycle the bill is charged at once (heavy users pay more for the extra).
func test_water_supply() -> void:
	var data := _bonus_data()  # people only change when the test says so
	# Bills every hour here (12 in the game), and the extra starts at 10 m³ per cycle.
	data.config["water"] = {"price_per_m3": 2.0, "billing_hours": 1, "tiers": [{"from": 0, "extra": 0.0}, {"from": 10, "extra": 0.25}]}
	data.buildings["wet_farm"] = {"category": "extractor", "build_cost": 0, "buildable": true, "max_workers": 2,
		"storage_cap": 50, "water_per_hour": 60,
		"recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]}
	_check(is_equal_approx(Sim.water_bill_cost(data, 8.0, 16.0), 16.0), "8 m³ at $2 = $16")
	_check(is_equal_approx(Sim.water_bill_cost(data, 14.0, 28.0), 10 * 2.0 + 4 * 2.5), "above 10 m³ in a cycle the extra costs 25% more: $20 + $10")
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "wet_farm", Vector2i(5, 5), T0).building_id)
	_check(Sim.water_use(state, data, farm, T0) == 0.0, "nobody working yet: no water drawn")
	state.population.current = 1  # 1 of 2 workers: half speed, half the water
	Sim.settle(state, data, T0)
	_check(is_equal_approx(Sim.water_use(state, data, farm, T0), 30.0), "at half speed it draws half its water")
	state.population.current = 2
	Sim.settle(state, data, T0 + 1)
	# Water follows the work done: its 5 batches (storage 50) take 5 minutes of full-speed work,
	# so 5 m³ = $10 in all, whatever the speed was along the way.
	Sim.settle(state, data, T0 + 1 + 300)
	_check(Sim.is_halted(data, farm) and is_equal_approx(float(Sim.water_meter(state, T0).m3), 5.0), "the meter recorded 5 m³; full storage: no more water drawn")
	var bill := Sim.water_bill_so_far(state, data, T0 + 1000)
	_check(int(Sim.stats(state).spending.get("water", 0)) == 0 and int(bill.cost) == 1000 and is_equal_approx(float(bill.due_at), T0 + 3600), "nothing paid yet: $10 so far, due at the end of the cycle")
	var cash := int(state.profile.currency)
	var report := Sim.settle(state, data, T0 + 3600)
	_check(int(state.profile.currency) == cash - 1000 and int(report.get("water", 0)) == 1000 and int(Sim.stats(state).spending.water) == 1000, "the bill is charged all at once when it falls due ($10)")
	_check(state.water_bills.size() == 1 and int(state.water_bills[0].cost) == 1000 and is_equal_approx(float(Sim.water_meter(state, T0).cycle_start), T0 + 3600), "it goes in the bill history, and the next cycle starts at that fixed moment")
	Sim.settle(state, data, T0 + 7300)
	_check(state.water_bills.size() == 1 and is_equal_approx(float(Sim.water_meter(state, T0).cycle_start), T0 + 7200), "a cycle with no water use sends no bill")

	var poor := Sim.new_game(data, T0)
	data.buildings["big_wet_farm"] = data.buildings.wet_farm.duplicate(true)
	data.buildings.big_wet_farm["storage_cap"] = 100_000
	Sim.build(poor, data, "big_wet_farm", Vector2i(5, 5), T0)
	poor.population.current = 2
	poor.profile.currency = 0
	poor["wage_carry"] = 0.0
	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 0}}  # only water costs money here
	Sim.settle(poor, data, T0 + 3600)  # 60 m³ in the hour: 10 x $2 + 50 x $2.50 = $145
	_check(int(poor.profile.currency) == -14500, "a heavy user pays the extra, and an unpaid bill just goes into debt")

	data.config["worker_types"] = {"low_skilled": {"name": "Low-skilled", "wage_per_hour": 15}}
	var steps := Sim.new_game(data, T0)
	Sim.build(steps, data, "big_wet_farm", Vector2i(5, 5), T0)
	Sim.build(steps, data, "wet_farm", Vector2i(6, 6), T0)
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
	for type_id in ["farm", "slow_farm", "crew_farm", "big_wet_farm"]:
		data.buildings.erase(type_id)
	data.config["pricing"] = {"payback_hours": 10, "typical_tax_rate": 0.0}
	# wet_farm: 2 workers x $15 x 1/60 h = $0.50, water 60 m³/h x 1/60 h x $2 = $2: $2.50 / 10
	_check(Sim.unit_price(data, "wheat") == 25, "water is part of the price per unit ($0.25)")


## Cost tags (plan.md §5.14): every stock knows what it cost to make, the cost moves with the
## goods, and mixing averages it. Minimum wage $15; crew_farm 2 workers, 10 wheat per 60 s (wages
## $0.50 a batch = 5 cents a wheat); crew_mill 3 workers, 10 wheat -> 8 flour in 90 s.
func test_cost_tags() -> void:
	var data := _bonus_data()
	data.config["water"] = {"price_per_m3": 2.0, "billing_hours": 12, "tiers": [{"from": 0, "extra": 0.0}]}
	var state := Sim.new_game(data, T0)
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	state.population.current = 2
	Sim.settle(state, data, T0)
	Sim.settle(state, data, T0 + 120)  # 2 batches
	_check(int(farm.storage.wheat) == 20 and is_equal_approx(float(farm.storage_cost.wheat), 100.0), "20 wheat made for $1.00 (wages only)")
	Sim.collect(state, data, farm.id, T0 + 120)
	_check(int(state.inventory.wheat) == 20 and is_equal_approx(Sim.average_cost(state, "wheat"), 5.0), "collected: the cost tag came along (5 cents each)")

	var half := Sim.new_game(data, T0)
	var slow := Sim.find_building(half, Sim.build(half, data, "crew_farm", Vector2i(3, 3), T0).building_id)
	half.population.current = 1  # 1 of 2 workers: half speed
	Sim.settle(half, data, T0)
	Sim.settle(half, data, T0 + 120)
	_check(int(slow.storage.wheat) == 10 and is_equal_approx(float(slow.storage_cost.wheat), 50.0), "half the workers: half as much, at the same cost per unit")

	state.population.current = 5  # the mill's 3 workers too
	var mill := Sim.find_building(state, Sim.build(state, data, "crew_mill", Vector2i(5, 5), T0 + 120).building_id)
	Sim.enqueue(state, data, mill.id, "mill", T0 + 120)
	_check(is_equal_approx(float(mill.queue[0].input_cost.wheat), 50.0) and is_equal_approx(float(state.inventory_cost.wheat), 50.0), "a queued batch takes its wheat's cost with it (10 x 5 cents)")
	Sim.settle(state, data, T0 + 210)  # 90 s later: wages 3 x $15 x 1.5 min = $1.125
	_check(int(mill.storage.flour) == 8 and is_equal_approx(float(mill.storage_cost.flour), 50.0 + 112.5), "8 flour made for $0.50 of wheat + $1.125 wages")

	state.inventory["wheat"] = int(state.inventory.wheat) + 10  # 10 bought at 15 cents each
	state.inventory_cost["wheat"] = float(state.inventory_cost.wheat) + 150.0
	_check(is_equal_approx(Sim.average_cost(state, "wheat"), 10.0), "own wheat (5) and bought wheat (15) mix to an average of 10 cents")
	var sale := Sim.sell(state, data, "wheat", 4, T0 + 210)  # wheat sells at a fixed $2 here
	_check(int(sale.cost) == 40 and int(sale.profit) == int(sale.earned) - 40, "a sale knows what the goods cost to make, and the profit")
	_check(is_equal_approx(Sim.average_cost(state, "wheat"), 10.0), "selling some keeps the average")
	state.inventory["wheat"] = int(state.inventory.wheat) + 4  # 4 more bought at 10 cents: 20 wheat
	state.inventory_cost["wheat"] = float(state.inventory_cost.wheat) + 40.0
	Sim.enqueue(state, data, mill.id, "mill", T0 + 210)
	Sim.enqueue(state, data, mill.id, "mill", T0 + 210)  # all 20 wheat now in 2 batches
	Sim.cancel_job(state, data, mill.id, 1, T0 + 210)  # the waiting one: all 10 wheat back
	_check(int(state.inventory.wheat) == 10 and is_equal_approx(float(state.inventory_cost.wheat), 100.0), "cancelling gives the wheat back with its cost tag (10 x 10 cents)")

	Sim.set_bonus(state, data, mill.id, "good", T0 + 210)
	var running := Sim.batch_running_cost(state, data, mill, data.buildings.crew_mill.recipes[0])
	_check(is_equal_approx(float(running.wages), 112.5 * 1.4), "a +40% bonus raises the wages in the cost by 40%")
	var breakdown := Sim.cost_breakdown(state, data, mill, T0 + 210)
	_check(breakdown.output == "flour" and is_equal_approx(float(breakdown.total), (100.0 + 157.5) / 8.0) and is_equal_approx(float(breakdown.ingredients[0].each), 10.0), "cost per unit: the batch being made's wheat (10 each) + wages, ÷ 8 flour")
	_check(int(breakdown.price) == 300 and is_equal_approx(float(breakdown.making_earns), 8 * 300 - 10 * 200 - 157.5), "and what milling earns over selling the wheat")

	data.buildings["wet_farm"] = {"category": "extractor", "build_cost": 0, "buildable": true, "max_workers": 2,
		"storage_cap": 100, "water_per_hour": 60, "recipes": [{"id": "grow", "inputs": {}, "outputs": {"wheat": 10}, "duration": 60}]}
	state.population.current = 7
	var wet := Sim.find_building(state, Sim.build(state, data, "wet_farm", Vector2i(7, 7), T0 + 210).building_id)
	Sim.settle(state, data, T0 + 270)  # one batch: wages 50 cents + 1 m³ x $2
	_check(is_equal_approx(float(wet.storage_cost.wheat), 250.0), "water used goes into the cost tag ($0.50 wages + $2.00 water)")
	Sim.suspend(state, data, wet.id, T0 + 270)
	_check(wet.storage.is_empty() and int(state.inventory.wheat) == 20 and is_equal_approx(float(state.inventory_cost.wheat), 100.0 + 250.0), "suspending sends the goods to the warehouse with their cost tags")


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
	var result := SaveFormat.from_text(JSON.stringify(old), data)
	_check(result.ok and is_equal_approx(Sim.average_cost(result.state, "wheat"), 5.0), "old stock gets the standard cost of making it (5 cents a wheat)")
	var real := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	_check(is_equal_approx(Sim.standard_unit_cost(real, "wheat"), 30.0) and is_equal_approx(Sim.standard_unit_cost(real, "flour"), 75.0) and is_equal_approx(Sim.standard_unit_cost(real, "bread"), 4400.0 / 24.0), "real data: wheat $0.30, flour $0.75, bread $1.83 (the plan's example)")


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
			_check(def.has("storage_cap") and def.recipes.size() > 0, "%s has storage and recipes" % type_id)
			for recipe in def.recipes:
				_check(recipe.duration > 0, "%s timer > 0" % recipe.id)
				for res in recipe.inputs.keys() + recipe.outputs.keys():
					_check(resources.has(res), "%s uses known resource '%s'" % [recipe.id, res])
		if def.category == "processor":
			_check(def.get("queue_size", 0) > 0, "%s has a queue" % type_id)
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
	_check(not check.ok and check.error.contains("already on a shelf"), "each product sells on one shelf at a time")
	Sim.stock_shelf(state, data, market.id, "bread", 10, "normal", T0)
	check = Sim.can_stock_shelf(state, data, market.id, "cake", 10, "normal", T0)
	_check(not check.ok and check.error.begins_with("Every shelf is full"), "only as many products as shelves")
	var second := Sim.find_building(state, Sim.build(state, data, "market", Vector2i(6, 6), T0).building_id)
	check = Sim.can_stock_shelf(state, data, second.id, "flour", 10, "normal", T0)
	_check(not check.ok and check.error.contains("already on a shelf"), "...in the whole village, not just this store")
	_check(Sim.can_stock_shelf(state, data, second.id, "cake", 10, "normal", T0).ok, "another store can sell another product")
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
	data.buildings["big_house"] = {"category": "residential", "build_cost": 0, "buildable": true, "population_capacity": 100}
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
	data.buildings["big_house"] = {"category": "residential", "build_cost": 0, "buildable": true, "population_capacity": 100}
	data.buildings["home"] = {"category": "residential", "build_cost": 0, "buildable": true, "population_capacity": 10}
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
	Sim.settle(state, data, T0 + 36000)
	_check(int(state.population.current) == 10 and int(Sim.people_stats(state).born) == 0, "homes full: no babies, however long")
	Sim.build(state, data, "big_house", Vector2i(5, 5), T0 + 36000)
	Sim.settle(state, data, T0 + 36000 + 3599)
	_check(int(state.population.current) == 10, "no baby before the first hour is up")
	var report := Sim.settle(state, data, T0 + 36000 + 3601)
	_check(int(state.population.current) == 11 and Sim.children_count(state) == 1 and Sim.adults(state) == 10, "a baby after an hour: a child, not an adult")
	_check(int(report.get("born", 0)) == 1, "the report counts the birth")
	var grows_up := float(Sim.children_groups(state)[0].grows_up_at)
	_check(grows_up > T0 + 36000 + 3601 and grows_up <= T0 + 36000 + 3600 + 7200, "it grows up within 2 hours of being born")
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


func test_demolish_home_who_leaves() -> void:
	var data := _life_data(0.0, 0.0)
	var state := Sim.new_game(data, T0)
	var home := Sim.find_building(state, Sim.build(state, data, "home", Vector2i(5, 5), T0).building_id)
	var farm := Sim.find_building(state, Sim.build(state, data, "crew_farm", Vector2i(6, 6), T0).building_id)
	state.population.current = 18  # 4 adults (2 at the farm) + 14 children, in room for 20
	state.population.children = [{"count": 7, "grows_up_at": T0 + 3600}, {"count": 7, "grows_up_at": T0 + 7200}]
	Sim._hire(state, data, T0)
	Sim.demolish(state, data, home.id, T0)  # room 10: 8 must leave
	_check(int(state.population.current) == 10, "8 people moved away")
	_check(Sim.adults(state) == 2 and Sim.hired(farm) == 2, "the 2 unemployed adults left first; the workers stayed")
	_check(Sim.children_count(state) == 8 and Sim.children_groups(state).size() == 2 and int(Sim.children_groups(state)[1].count) == 1, "then 6 children, youngest first")


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
	_check(result.ok and int(s.save_version) == 6, "a version 5 save loads as version 6")
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
	_check(float(data.config.population_growth_seconds) <= 0.0, "real data: nobody moves in (immigration is off for now)")
	_check(not data.config.get("life", {}).is_empty(), "real data: births and deaths are switched on")


## The real data: the needs are switched on and sensible.
func test_real_happiness_data() -> void:
	var data := {"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json")}
	_check(Sim._has_needs(data), "real data: needs are switched on")
	var state := Sim.new_game(data, T0)
	_check(Sim.happiness(state, data, T0).score == 1.0, "real data: a new game starts at 100% (too small to complain)")


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
	_check(int(data.buildings.supermarket.build_cost) + int(data.buildings.wheat_farm.build_cost) + int(data.buildings.flour_mill.build_cost) <= int(data.config.starting_cash), "real data: starting cash covers a Wheat Farm, a Flour Mill and a Supermarket")
