extends SceneTree
## Performance benchmark (plan.md §9.1): how long the game's regular work takes, in milliseconds,
## for a small village (a new game) and a big one (a full 26x26 plot: ~60 factories and farms, ~70
## homes, shops, warehouses, power, ~800 people, batches running). Not a pass/fail test: timings
## differ from computer to computer, so run it before and after a change and compare.
##   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/bench_performance.gd
## Part 1 times the game rules (scripts/sim/) on their own. Part 2 loads the real main scene (no
## window) and times one tick of the game: the rules plus every screen refreshing, with each
## window open in turn, and how long each window takes to open.
## Each number is the middle one (median) of several runs, so one slow run doesn't skew it.

const Sim = preload("res://scripts/sim/simulation.gd")
const GameDataScript = preload("res://scripts/autoload/game_data.gd")
const T0 := 1_000_000.0
const RUNS := 9

var _data: Dictionary
var _frames := 0
var _main: Node


func _initialize() -> void:
	Engine.set_meta("running_tests", true)  # keeps Economy away from the player's real save
	_data = {
		"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json"),
		"cache": {},  # like the game's data (Economy.data()): prices are remembered
	}


## Waits a frame so the autoloads (Economy, ...) are ready, then runs everything once.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_run_rules()
		_start_screens()
	elif _frames == 4:
		_run_screens()
		quit(0)
	return false


# --- Part 1: the rules on their own -----------------------------------------------------

func _run_rules() -> void:
	var small := _small_village(T0)
	var big := _big_village(T0)
	print("\nVillages: small = %s; big = %s" % [_describe(small), _describe(big)])
	print("\nPART 1: game rules (ms)                          small        big")
	for row in [
		["settle: one second (every tick)", _time_ticks],
		["settle: 24 hours away (one catch-up)", _time_day_away],
		["housing()", func(s): return _median(func(): Sim.housing(s, _data, _now(s)))],
		["employment()", func(s): return _median(func(): Sim.employment(s, _data, _now(s)))],
		["power_summary()", func(s): return _median(func(): Sim.power_summary(s, _data, _now(s)))],
		["happiness()", func(s): return _median(func(): Sim.happiness(s, _data, _now(s)))],
		["HUD numbers (happiness, room, warehouse)", _time_hud],
		["traffic: workers of every building", _time_traffic],
		["unit_price() of every item", _time_prices],
		["build quote of every building type", _time_quotes],
		["batch_quote() for a farm", _time_batch_quote],
		["spot for a new hut", _time_hut_spot],
		["placement: find the free spot nearest a tile", _time_free_spot],
	]:
		print("  %-44s %9s  %9s" % [row[0], _ms(row[1].call(small)), _ms(row[1].call(big))])


func _now(state: Dictionary) -> float:
	return float(state.settled_at)


## Ticks one second at a time on a copy, like the game does while it's open (handing each tick's
## hiring on to the next, as Economy.tick does).
func _time_ticks(state: Dictionary) -> float:
	var s: Dictionary = state.duplicate(true)
	var t := _now(s)
	var hiring := {}
	Sim.settle(s, _data, t, hiring)
	var times: Array[float] = []
	for i in RUNS:
		t += 1.0
		var start := Time.get_ticks_usec()
		Sim.settle(s, _data, t, hiring)
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	return _middle(times)


func _time_day_away(state: Dictionary) -> float:
	var times: Array[float] = []
	for i in 3:
		var s: Dictionary = state.duplicate(true)
		var start := Time.get_ticks_usec()
		Sim.settle(s, _data, _now(s) + 24 * 3600.0)
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	return _middle(times)


func _time_hud(s: Dictionary) -> float:
	return _median(func():
		Sim.happiness(s, _data, _now(s))
		Sim.population_capacity(s, _data, _now(s))
		Sim.warehouse_cap(s, _data)
		Sim.warehouse_total(s))


## What traffic.gd asks about every building each second (Economy.workers + needs_road).
func _time_traffic(s: Dictionary) -> float:
	return _median(func():
		for b in s.buildings:
			Sim.workers_working(s, _data, b, _now(s))
			Sim.building_wages(s, _data, b, _now(s))
			Sim.workers_wanted(_data, b)
			Sim.needs_road(_data, b))


func _time_prices(_s: Dictionary) -> float:
	return _median(func():
		for res in _data.resources:
			if not str(res).begins_with("_"):
				Sim.unit_price(_data, res))


func _time_quotes(s: Dictionary) -> float:
	return _median(func():
		for type_id in _data.buildings:
			if not str(type_id).begins_with("_"):
				Sim.construction_plan(s, _data, type_id, 1, _now(s)))


func _time_batch_quote(s: Dictionary) -> float:
	for b in s.buildings:
		if b.type == "wheat_farm":
			var recipe: String = _data.buildings.wheat_farm.recipes[0].id
			return _median(func(): Sim.batch_quote(s, _data, b, recipe, 24, "none", _now(s)))
	return 0.0


func _time_hut_spot(s: Dictionary) -> float:
	var hut := Sim.hut_type_of(_data)
	return _median(func(): Sim._free_spot_near_centre(s, _data, hut))


## Where Placement Mode puts a new farm's ghost first (the far corner: the longest search).
func _time_free_spot(s: Dictionary) -> float:
	return _median(func(): Sim.free_spot_near(s, _data, "wheat_farm", Vector2i(25, 25)))


# --- Part 2: the real screens ----------------------------------------------------------

func _economy() -> Node:
	return root.get_node("/root/Economy")


## Loads the main scene with the big village, so every view and window is made for it.
func _start_screens() -> void:
	var economy := _economy()
	economy.state = _big_village(root.get_node("/root/TimeService").now())
	_main = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(_main)


func _run_screens() -> void:
	var economy := _economy()
	var time_service := root.get_node("/root/TimeService")
	print("\nPART 2: the real screens, big village (ms)")
	print("  nodes in the game: %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var tick := func() -> float:
		var times: Array[float] = []
		for i in RUNS:
			time_service.warp(1.0)
			var start := Time.get_ticks_usec()
			economy.tick()
			times.append((Time.get_ticks_usec() - start) / 1000.0)
		return _middle(times)
	var screens := func() -> float:
		# Each run forgets Economy's remembered answers first, as a real tick does.
		return _median(func(): economy._memo.clear(); economy.changed.emit())
	print("  %-44s %9s" % ["one tick, nothing open (rules + screens)", _ms(tick.call())])
	print("  %-44s %9s" % ["  of which screens refreshing", _ms(screens.call())])
	for connection in economy.changed.get_connections():
		var callable: Callable = connection.callable
		var owner: Object = callable.get_object()
		var who := str(owner.name) if owner is Node else str(owner)
		print("  %-44s %9s" % ["    %s.%s" % [who, callable.get_method()], _ms(_median(func(): economy._memo.clear(); callable.call()))])
	var farm := ""
	var home := ""
	for b in economy.state.buildings:
		if b.type == "wheat_farm" and farm == "":
			farm = b.id
		elif b.type == "public_housing" and home == "":
			home = b.id
	var windows := [
		["a home tapped (its bar)", func(): _main._on_building_tapped(home), func(): _main._deselect()],
		["building window (a farm)", func(): _main.building_panel.show_building(farm), func(): _main.building_panel.close()],
		["build menu", func(): _main.build_menu.open(), func(): _main.build_menu._close()],
		["warehouse window", func(): _main._warehouse_panel.show_stock(), func(): _main._warehouse_panel.close()],
		["statistics: production", func(): _main.stats_panel.show_stats("production"), func(): _main.stats_panel.close()],
		["statistics: people", func(): _main.stats_panel.show_stats("people"), func(): _main.stats_panel.close()],
		["statistics: cash", func(): _main.stats_panel.show_stats("cash"), func(): _main.stats_panel.close()],
		["statistics: balance", func(): _main.stats_panel.show_stats("balance"), func(): _main.stats_panel.close()],
	]
	for w in windows:
		var start := Time.get_ticks_usec()
		w[1].call()
		var opening := (Time.get_ticks_usec() - start) / 1000.0
		print("  %-44s %9s   (opening it: %s)" % ["screens refreshing, " + w[0] + " open", _ms(screens.call()), _ms(opening)])
		w[2].call()
	# The performance overlay itself (test builds only): one update, with each switch flipped twice.
	var overlay: Control = _main.ui_root.get_node_or_null("PerfOverlay")
	if overlay:
		overlay.toggle()
		for button in overlay.find_children("*", "Button", true, false):
			button.pressed.emit()
			button.pressed.emit()
		print("  %-44s %9s" % ["performance overlay: one update", _ms(_median(func(): overlay._update()))])
		overlay.toggle()
	var start := Time.get_ticks_usec()
	_main.village.start_placement("wheat_farm")
	print("  %-44s %9s" % ["start placing a farm (find a free spot)", _ms((Time.get_ticks_usec() - start) / 1000.0)])
	_main.village.stop_placement()


# --- Villages --------------------------------------------------------------------------

## A new game: today's starting village, settled once so everyone is hired.
func _small_village(now: float) -> Dictionary:
	var state := Sim.new_game(_data, now)
	Sim.settle(state, _data, now)
	return state


## A full plot. Road rows every third row plus a road down the right edge (all linked to City
## Hall); 2x2 lots between them; a column of 1x1 lots beside the edge road.
func _big_village(now: float) -> Dictionary:
	var state := Sim.new_game(_data, now)
	state.buildings.clear()
	state.roads.clear()
	state.next_building_id = 1
	var price := Sim.road_price(_data)
	for y in range(0, 26, 3):
		for x in 25:
			state.roads.append([x, y, price])
	for y in 26:
		state.roads.append([25, y, price])
	var producers: Array[String] = []
	for type_id in _data.buildings:
		var def: Dictionary = _data.buildings[type_id]
		if def.get("category", "") in ["extractor", "processor"] and def.get("buildable", false):
			producers.append(type_id)
	# What stands on the 96 big lots (12 across, 8 down), in order; "" = left empty (huts go there).
	var lots: Array[String] = ["city_hall"]
	lots.append_array(["construction_office", "construction_office", "warehouse", "warehouse", "warehouse", "warehouse",
		"water_treatment_plant", "water_treatment_plant", "trading_post", "supermarket", "supermarket", "supermarket", "supermarket"])
	for i in 16:
		lots.append("homes")  # four 1x1 homes
	for i in 8:
		lots.append("")
	var p := 0
	while lots.size() < 96:
		lots.append(producers[p % producers.size()])
		p += 1
	var i := 0
	for row in 8:
		for col in 12:
			var cell := Vector2i(col * 2, 1 + row * 3)
			var type_id: String = lots[i]
			i += 1
			if type_id == "homes":
				for k in 4:
					var home: String = ["public_housing", "public_housing", "small_house", "villa"][k]
					Sim._add_building(state, home, cell + Vector2i(k % 2, k / 2), now, 0.0)
			elif type_id != "":
				Sim._add_building(state, type_id, cell, now, 0.0)
	var column := 0
	for y in 26:
		if y % 3 != 0:
			var small: String = ["electric_substation", "wind_turbine", "public_housing"][column % 3]
			Sim._add_building(state, small, Vector2i(24, y), now, 0.0)
			column += 1
	state.population.current = 800
	state.population.children = [{"count": 200, "grows_up_at": now + 20 * 3600.0}]
	state.profile.currency = 100_000_000_00
	for res in _data.resources:
		if not str(res).begins_with("_"):
			state.inventory[res] = 100_000
	Sim.settle(state, _data, now)  # hires everyone and puts up huts
	for b in state.buildings:
		var recipes: Array = _data.buildings[b.type].get("recipes", [])
		if not recipes.is_empty():
			var recipe: Dictionary = recipes[int(str(b.id).trim_prefix("b")) % recipes.size()]
			Sim.start_batch(state, _data, b.id, recipe.id, 24, "none", now)
		elif _data.buildings[b.type].get("category", "") == "retail":
			var products := Sim.store_products(_data, b.type)
			for k in mini(3, products.size()):
				Sim.stock_shelf(state, _data, b.id, products[(k + int(str(b.id).trim_prefix("b"))) % products.size()], 200, "normal", now)
	return state


func _describe(state: Dictionary) -> String:
	var running := 0
	var huts := 0
	for b in state.buildings:
		running += 1 if Sim.batch_running(b) else 0
		huts += 1 if Sim.is_hut(_data, b) else 0
	return "%d buildings (%d huts, %d batches running), %d road tiles, %d people" % [
		state.buildings.size(), huts, running, state.roads.size(), int(state.population.current)]


# --- Timing helpers --------------------------------------------------------------------

## Runs `work` RUNS times and returns the middle time, in ms.
func _median(work: Callable) -> float:
	var times: Array[float] = []
	for i in RUNS:
		var start := Time.get_ticks_usec()
		work.call()
		times.append((Time.get_ticks_usec() - start) / 1000.0)
	return _middle(times)


func _middle(times: Array[float]) -> float:
	times.sort()
	return times[times.size() / 2]


func _ms(value: float) -> String:
	return "%.2f" % value if value < 100.0 else "%.0f" % value
