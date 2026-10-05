extends SceneTree
## Random-play stress test of the game rules (scripts/sim/), with the REAL data/*.json.
##
## test_simulation.gd checks the cases we thought of. This plays hundreds of games nobody thought
## of: random player actions (sensible and silly ones), random waits from half a second to days,
## and now and then a clock that jumps backwards. After every step it checks rules that must
## ALWAYS hold ("invariants"): no negative or broken numbers, nothing over its storage limit,
## never more workers than people, every cent of cash explained by the statistics, a refused
## action changes nothing, ... If one breaks, that's a bug, whatever led to it.
##
## It also checks the promises of plan.md §8 / §9.1:
##   - time away (one settle) ends exactly like playing through it (a settle every second)
##   - a save loads back exactly as it was and plays on the same way
##   - every old save in tests/saves/ still loads (add one before raising SAVE_VERSION)
##
## Every game has a number (its seed), so a problem can be replayed step by step:
##   "C:\Program Files\Godot\Godot.exe.exe" --headless --path . -s tests/test_invariants.gd -- --seed=37
## Options after "--": --games=N (default 50), --from=N (first game number, default 1: the same
## games every run catch problems coming back; a deep bug hunt uses new numbers to find new ones),
## --steps=N (default 120), --seed=N (one game, every step printed), --make-save-sample (writes
## tests/saves/save_v<SAVE_VERSION>.json).
## Exit code 0 = no problems found.

const Sim = preload("res://scripts/sim/simulation.gd")
const SaveFormat = preload("res://scripts/sim/save_format.gd")
const GameDataScript = preload("res://scripts/autoload/game_data.gd")
const T0 := 1_000_000.0
const SAVES_DIR := "res://tests/saves/"
const PARITY_EVERY := 4  # every 4th game also compares "away" with "playing through it" (slower)
const GODOT := "\"C:\\Program Files\\Godot\\Godot.exe.exe\" --headless --path . -s tests/test_invariants.gd --"

var _data: Dictionary
var _problems := {}  # kind of problem -> how many games hit it (each kind is printed once)
var _counts := {"games": 0, "steps": 0, "refused": 0, "parity": 0, "round_trips": 0}
var _log: Array[String] = []  # what the current game did, for the problem report
var _errors := _ErrorCounter.new()


## Counts Godot's error messages (as in test_simulation.gd): a rules function that crashes on a
## missing key is a problem too, even though Godot carries on.
class _ErrorCounter extends Logger:
	var count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1


func _initialize() -> void:
	Engine.set_meta("running_tests", true)  # keeps Economy away from the player's real save
	_data = {
		"resources": GameDataScript.load_json("res://data/resources.json"),
		"buildings": GameDataScript.load_json("res://data/buildings.json"),
		"config": GameDataScript.load_json("res://data/game_config.json"),
	}
	var args := _args()
	if args.has("make-save-sample"):
		quit(_write_save_sample())
		return
	OS.add_logger(_errors)
	var steps := int(args.get("steps", "120"))
	if args.has("seed"):
		_run_game(int(args.seed), steps, true)
	else:
		var first := int(args.get("from", "1"))
		for game_seed in range(first, first + int(args.get("games", "50"))):
			_run_game(game_seed, steps, false)
	_check_old_saves()
	OS.remove_logger(_errors)
	print("\n%d games, %d steps (%d actions refused), %d away-vs-playing comparisons, %d save round trips" % [
		_counts.games, _counts.steps, _counts.refused, _counts.parity, _counts.round_trips])
	print("%d kinds of problem found" % _problems.size())
	quit(1 if _problems.size() > 0 else 0)


func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return out


# --- One game ----------------------------------------------------------------------

func _run_game(game_seed: int, steps: int, verbose: bool) -> void:
	_log.clear()
	_counts.games += 1
	var errors_before := _errors.count
	var result = _play(game_seed, steps, verbose)  # untyped: a script error inside returns null
	var problem := str(result) if result is String else ""
	if _errors.count > errors_before:
		problem = "Godot reported a script error while playing (see the error message above)"
	if problem != "":
		_report(problem, game_seed, verbose)


## Plays one random game. Returns "" or what went wrong.
func _play(game_seed: int, steps: int, verbose: bool) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = game_seed
	var now := T0
	var state := Sim.new_game(_data, now)
	if rng.randf() < 0.6:  # often a richer start, so the later buildings get built too
		Sim.dev_set_cash(state, rng.randi_range(20_000, 300_000) * 100)
	var baseline := _ledger(state)
	var ever_suspended := {}
	var parity_step := rng.randi_range(steps / 3, steps - 1) if game_seed % PARITY_EVERY == 0 else -1
	for step in steps:
		_counts.steps += 1
		var wait := _random_wait(rng)
		now += wait
		var before := state.duplicate(true)
		var action := _random_action(rng, state, now, ever_suspended)
		_log.append("step %d, %s (%s): %s" % [step, _clock(now), _signed_time(wait), action.text])
		if verbose:
			print(_log[-1])
		if not action.result.get("ok", true):
			_counts.refused += 1
		var problem := _invariants(state, now, before, baseline, ever_suspended)
		if problem == "" and not action.result.get("ok", true):
			problem = _refusal_changed_nothing(before, state, now, action.result)
		if problem == "":
			problem = _settling_twice_changes_nothing(state, now)
		if problem == "" and step % 25 == 24:
			problem = _round_trip(state, now)
		if problem == "" and step == parity_step:
			problem = _away_matches_playing(rng, state, now)
		if problem != "":
			return problem
	return ""


## How long the player waits before the next action. Mostly short (tapping around), sometimes
## the game is closed for hours or days, and now and then the clock jumps back.
func _random_wait(rng: RandomNumberGenerator) -> float:
	var roll := rng.randf()
	if roll < 0.30:
		return rng.randf_range(0.0, 2.0)
	if roll < 0.60:
		return rng.randf_range(2.0, 120.0)
	if roll < 0.80:
		return rng.randf_range(120.0, 1800.0)
	if roll < 0.92:
		return rng.randf_range(3600.0, 8.0 * 3600.0)
	if roll < 0.97:
		return rng.randf_range(86400.0, 5.0 * 86400.0)
	return -rng.randf_range(1.0, 2.0 * 3600.0)  # the phone's clock was set back


## Does one player action at `now`: usually what a sensible player would do next (so the economy
## gets busy, where most bugs live), otherwise anything at all, including silly things.
## Returns {"text": what was done, "result": its answer}.
func _random_action(rng: RandomNumberGenerator, state: Dictionary, now: float, ever_suspended: Dictionary) -> Dictionary:
	if rng.randf() < 0.65:
		var sensible := _sensible_action(rng, state, now)
		if not sensible.is_empty():
			return sensible
	var roll := rng.randi_range(0, 99)
	var result := {}
	var text := ""
	if roll < 12:
		var type: String = _pick(rng, _buildable())
		var cell := _free_cell(rng, state) if rng.randf() < 0.85 else Vector2i(rng.randi_range(-1, 21), rng.randi_range(-1, 21))
		result = Sim.build(state, _data, type, cell, now)
		text = "build %s at %s" % [type, cell]
	elif roll < 30:
		var b := _some_building(rng, state, ["extractor", "processor"])
		if rng.randf() < 0.5:
			result = Sim.collect(state, _data, b.get("id", "none"), now)
			text = "collect from %s" % _name(b)
		else:
			result = Sim.collect_group(state, _data, b.get("id", "none"), now)
			text = "collect from %s and the others of its type" % _name(b)
	elif roll < 45:
		var b := _some_building(rng, state, ["extractor", "processor"])
		var recipe: String = _pick(rng, _recipe_ids(b) + ["nonsense"])
		var hours := rng.randi_range(-1, Sim.batch_hours_limit(_data) + 1)
		var bonus: String = _pick(rng, _data.config.get("wage_bonuses", {}).keys() + ["nonsense"])
		result = Sim.start_batch(state, _data, b.get("id", "none"), recipe, hours, bonus, now)
		text = "start a %d-hour batch of %s at %s (bonus %s)" % [hours, recipe, _name(b), bonus]
	elif roll < 50:
		var b := _some_building(rng, state, ["extractor", "processor"])
		result = Sim.cancel_batch(state, _data, b.get("id", "none"), now)
		text = "cancel the batch at %s" % _name(b)
	elif roll < 53:
		var b := _some_building(rng, state, [])
		result = Sim.demolish(state, _data, b.get("id", "none"), now)
		text = "demolish %s" % _name(b)
	elif roll < 57:
		var b := _some_building(rng, state, ["extractor", "processor", "retail", "storage", "utility"])
		result = Sim.suspend(state, _data, b.get("id", "none"), now)
		if result.get("ok", false):
			ever_suspended[b.id] = true
		text = "suspend %s" % _name(b)
	elif roll < 61:
		var b := _some_building(rng, state, ["extractor", "processor", "retail", "storage", "utility"])
		result = Sim.resume(state, _data, b.get("id", "none"), now)
		text = "resume %s" % _name(b)
	elif roll < 65:
		var b := _some_building(rng, state, ["extractor", "processor"])
		var level: String = _pick(rng, _data.config.get("staffing_levels", {}).keys() + ["nonsense"])
		result = Sim.set_staffing(state, _data, b.get("id", "none"), level, now)
		text = "set staffing of %s to %s" % [_name(b), level]
	elif roll < 68:
		var b := _some_building(rng, state, ["extractor", "processor"])
		var bonus: String = _pick(rng, _data.config.get("wage_bonuses", {}).keys() + ["nonsense"])
		result = Sim.set_bonus(state, _data, b.get("id", "none"), bonus, now)
		text = "set wage bonus of %s to %s" % [_name(b), bonus]
	elif roll < 73:
		var res: String = _pick(rng, _data.resources.keys())
		var qty := rng.randi_range(0, int(state.inventory.get(res, 0)) + 3)
		result = Sim.sell(state, _data, res, qty, now)
		text = "sell %d %s to the Retailer" % [qty, res]
	elif roll < 85:
		var b := _some_building(rng, state, ["retail"])
		var res: String = _pick(rng, Sim.shop_products(_data) + ["wheat"])
		var qty := rng.randi_range(0, int(state.inventory.get(res, 0)) + 3)
		var tag: String = _pick(rng, Sim.price_tags(_data).keys() + ["nonsense"])
		result = Sim.stock_shelf(state, _data, b.get("id", "none"), res, qty, tag, now)
		text = "put %d %s on a shelf at %s (%s)" % [qty, res, _name(b), tag]
	elif roll < 89:
		var b := _some_building(rng, state, ["retail"])
		var index := rng.randi_range(-1, 4)
		result = Sim.clear_shelf(state, _data, b.get("id", "none"), index, now)
		text = "take shelf %d down at %s" % [index, _name(b)]
	elif roll < 92:
		var b := _some_building(rng, state, [])
		var cell := Vector2i(rng.randi_range(-1, 21), rng.randi_range(-1, 21))
		result = Sim.move(state, _data, b.get("id", "none"), cell, now)
		text = "move %s to %s" % [_name(b), cell]
	elif roll < 95:
		var b := _some_building(rng, state, [])
		result = Sim.upgrade(state, _data, b.get("id", "none"), now)
		text = "upgrade %s" % _name(b)
	elif roll < 97:
		# A random straight line of road (sometimes over buildings or off the land).
		var from := Vector2i(rng.randi_range(-1, 20), rng.randi_range(-1, 20))
		var step := Vector2i(1, 0) if rng.randf() < 0.5 else Vector2i(0, 1)
		var cells := []
		for i in rng.randi_range(1, 6):
			cells.append(from + step * i)
		result = Sim.build_roads(state, _data, cells, now)
		text = "build road on %s" % [cells]
	elif roll < 98:
		var roads: Array = state.get("roads", [])
		var cells := []
		if not roads.is_empty():
			var road: Array = _pick(rng, roads)
			cells.append(Vector2i(int(road[0]), int(road[1])))
		cells.append(Vector2i(rng.randi_range(0, 19), rng.randi_range(0, 19)))
		result = Sim.remove_roads(state, _data, cells, now)
		text = "remove road on %s" % [cells]
	else:
		Sim.settle(state, _data, now)
		result = {"ok": true}
		text = "just wait"
	var answer := "ok" if result.get("ok", false) else "refused: %s" % result.get("error", "")
	return {"text": "%s -> %s" % [text, answer], "result": result}


## One of the useful things a player could do right now, picked at random: build what the chain
## is missing, collect, fill queues, stock shelves, sell, resume. {} if there's nothing useful.
func _sensible_action(rng: RandomNumberGenerator, state: Dictionary, now: float) -> Dictionary:
	var options: Array[Callable] = []
	for type in _buildable():
		var have := 0
		for b in state.buildings:
			have += 1 if b.type == type else 0
		if have < 2 and state.profile.currency >= int(Sim.construction_quote(_data, type, 1, now).cost):
			options.append(func(): return ["build %s" % type, Sim.build(state, _data, type, _free_cell(rng, state), now)])
	for b in state.buildings:
		var road := Sim.road_path_for(state, _data, b.id)
		if not road.is_empty():
			options.append(func(): return ["build a road to %s" % _name(b), Sim.build_roads(state, _data, road, now)])
		if Sim.is_suspended(b):
			options.append(func(): return ["resume %s" % _name(b), Sim.resume(state, _data, b.id, now)])
		elif not Sim.waiting_goods(b).is_empty():
			options.append(func(): return ["collect from %s and the others of its type" % _name(b), Sim.collect_group(state, _data, b.id, now)])
		if rng.randf() < 0.15 and Sim.can_upgrade(state, _data, b.id, now).ok:
			options.append(func(): return ["upgrade %s" % _name(b), Sim.upgrade(state, _data, b.id, now)])
		if rng.randf() < 0.1 and Sim.batch_running(b):
			options.append(func(): return ["cancel the batch at %s" % _name(b), Sim.cancel_batch(state, _data, b.id, now)])
		for recipe in _recipe_ids(b):
			var bonus: String = _pick(rng, _data.config.get("wage_bonuses", {"none": 0.0}).keys())
			var most := Sim.batch_max_hours(state, _data, b.id, recipe, bonus)
			if most > 0 and not Sim.has_batch(b):
				var hours := rng.randi_range(1, most)
				options.append(func(): return ["start a %d-hour batch of %s at %s (bonus %s)" % [hours, recipe, _name(b), bonus], Sim.start_batch(state, _data, b.id, recipe, hours, bonus, now)])
		if _data.buildings[b.type].get("category", "") == "retail":
			for res in Sim.store_products(_data, b.type):
				var qty := int(state.inventory.get(res, 0))
				if qty > 0 and not Sim.store_has_product(b, res):
					var tag: String = _pick(rng, Sim.price_tags(_data).keys())
					var amount := rng.randi_range(1, qty)
					options.append(func(): return ["put %d %s on a shelf at %s (%s)" % [amount, res, _name(b), tag], Sim.stock_shelf(state, _data, b.id, res, amount, tag, now)])
	for res in state.inventory:
		if int(state.inventory[res]) > 0 and rng.randf() < 0.3:
			var amount := rng.randi_range(1, int(state.inventory[res]))
			options.append(func(): return ["sell %d %s to the Retailer" % [amount, res], Sim.sell(state, _data, res, amount, now)])
	if options.is_empty():
		return {}
	var done: Array = _pick(rng, options).call()
	var answer := "ok" if done[1].get("ok", false) else "refused: %s" % done[1].get("error", "")
	return {"text": "%s -> %s" % [done[0], answer], "result": done[1]}


# --- The invariants ------------------------------------------------------------------

## Rules that must hold after anything. Returns "" or the first one that's broken.
func _invariants(state: Dictionary, now: float, before: Dictionary, baseline: int, _ever_suspended: Dictionary) -> String:
	var broken := _bad_number(state, "state")
	if broken != "":
		return broken
	if typeof(state.profile.currency) != TYPE_INT:
		return "cash isn't a whole number of cents (%s)" % state.profile.currency
	if _ledger(state) != baseline:
		return "cash doesn't match the statistics: %d cents came or went without being counted" % (_ledger(state) - baseline)
	var check := Sim.cash_check(state)
	if not check.ok:
		return "cash check: start + in - out + dev = %d cents, but cash is %d" % [check.expected, check.cash]
	broken = _balance_sheet_ok(Sim.balance_sheet(state, _data, now))
	if broken != "":
		return broken
	if float(state.settled_at) < float(before.settled_at):
		return "settled_at went backwards in time"
	var settled := float(state.settled_at)
	broken = _goods_ok("the warehouse", state.inventory, state.get("inventory_cost", {}))
	if broken != "":
		return broken
	var total_before := Sim.warehouse_total(before)
	var total := Sim.warehouse_total(state)
	if total > total_before and total > Sim.warehouse_cap(state, _data):
		return "goods were put into the warehouse past its room (%d of %d)" % [total, Sim.warehouse_cap(state, _data)]
	var ids := {}
	var cells := {}
	var workers := 0
	var linked := Sim.linked_roads(state, _data)
	var road_tiles := {}
	for road in state.get("roads", []):
		var road_cell := Vector2i(int(road[0]), int(road[1]))
		if road_tiles.has(road_cell):
			return "two roads on the tile %s" % road_cell
		road_tiles[road_cell] = true
		if not Sim._in_plot(state, road_cell) or int(road[2]) < 0:
			return "a road at %s (paid %s)" % [road_cell, road[2]]
	var on_shelves := {}
	for b in state.buildings:
		var def: Dictionary = _data.buildings.get(b.type, {})
		var name := _name(b)
		if def.is_empty():
			return "%s isn't in buildings.json" % name
		if ids.has(b.id):
			return "two buildings share the id %s" % b.id
		ids[b.id] = true
		var cell := Vector2i(int(b.position[0]), int(b.position[1]))
		if cells.has(cell):
			return "%s and %s stand on the same tile %s" % [cells[cell], name, cell]
		if Sim.is_road(state, cell):
			return "%s stands on a road at %s" % [name, cell]
		if Sim.needs_road(_data, b) and Sim.on_road(_data, b) != Sim._touches(linked, cell):
			return "%s says it's %s the road, but it isn't" % [name, "on" if Sim.on_road(_data, b) else "off"]
		cells[cell] = name
		if not Sim._in_plot(state, cell):
			return "%s stands outside the plot at %s" % [name, cell]
		broken = _goods_ok(name, b.get("storage", {}), b.get("storage_cost", {}))
		if broken != "":
			return broken
		broken = _batch_ok(b, def)
		if broken != "":
			return broken
		workers += Sim.hired(b)
		if Sim.hired(b) < 0 or Sim.hired(b) > Sim.posts(_data, b, settled):
			return "%s has %d workers but only %d posts" % [name, Sim.hired(b), Sim.posts(_data, b, settled)]
		if Sim.is_suspended(b) and Sim.hired(b) > 0:
			return "%s is suspended but still has %d workers" % [name, Sim.hired(b)]
		if Sim.building_level(b) > Sim.max_level(_data, b.type) or (Sim.is_upgrading(b, settled) and Sim.building_level(b) >= Sim.max_level(_data, b.type)):
			return "%s is at Level %d, above its highest" % [name, Sim.building_level(b)]
		if b.has("upgrade_done_at") and not Sim.is_upgrading(b, settled):
			return "%s finished its upgrade but didn't reach the next level" % name
		if Sim.is_upgrading(b, settled) and not Sim.stays_open_while_upgrading(_data, b) and Sim.hired(b) > 0:
			return "%s is closed for an upgrade but still has %d workers" % [name, Sim.hired(b)]
		if Sim.makes_batches(_data, b) and not b.get("storage", {}).is_empty():
			return "%s keeps goods in its own storage (it should have none: they wait in its batch)" % name
		if b.has("queue") or b.has("blocked"):
			return "%s still has a job queue" % name
		var shelves: Array = b.get("shelves", [])
		if shelves.size() > Sim.shelves(_data, b).size():
			return "%s has %d shelves, more than its %d" % [name, shelves.size(), Sim.shelves(_data, b).size()]
		for shelf in shelves:
			if shelf.is_empty():
				continue
			if not Sim.store_sells(_data, b.type, shelf.res):
				return "%s sells %s, which this store can't sell" % [name, shelf.res]
			# Several stores may sell the same product, but each store has it on one shelf at most.
			if on_shelves.has("%s|%s" % [b.id, shelf.res]):
				return "%s is on two shelves of %s" % [shelf.res, name]
			on_shelves["%s|%s" % [b.id, shelf.res]] = true
			if int(shelf.qty) <= 0 or float(shelf.sold) < 0.0 or float(shelf.sold) > float(shelf.qty) + 0.000001:
				return "a shelf at %s sold %s of %s" % [name, shelf.sold, shelf.qty]
			if int(shelf.price) <= 0 or float(shelf.cost) < -0.01:
				return "a shelf at %s has price %s and cost %s" % [name, shelf.price, shelf.cost]
	var people := int(state.population.current)
	if people < 0:
		return "%d people" % people
	# Housing: every homeless household has a hut (unless the plot is full), and no home holds
	# more households than it has room for.
	var homes := Sim.housing(state, _data, settled)
	var huts := 0
	for b in state.buildings:
		if Sim.is_hut(_data, b):
			huts += 1
	if huts > int(homes.homeless) or (huts < int(homes.homeless) and Sim._free_cell_near_centre(state, _data).x >= 0):
		return "%d huts for %d homeless households" % [huts, homes.homeless]
	for id in homes.homes:
		var home: Dictionary = Sim.find_building(state, id)
		if int(homes.homes[id].households) > Sim.home_households(_data, home):
			return "%s holds %d households, more than its %d" % [_name(home), homes.homes[id].households, Sim.home_households(_data, home)]
	if float(homes.rent_per_hour) < 0.0 or float(state.get("rent_carry", 0.0)) < 0.0:
		return "rent below 0"
	if workers > Sim.adults(state):
		return "%d workers but only %d adults" % [workers, Sim.adults(state)]
	# Children: whole, positive age groups, oldest first, never more than everyone.
	var last_grows_up := -INF
	for group in Sim.children_groups(state):
		if typeof(group.count) != TYPE_INT or int(group.count) <= 0:
			return "a children's age group of %s" % group.count
		if float(group.grows_up_at) < last_grows_up:
			return "children's age groups out of order"
		if float(group.grows_up_at) <= settled - 0.001:
			return "children who should have grown up at %s" % group.grows_up_at
		last_grows_up = float(group.grows_up_at)
	if Sim.children_count(state) > people:
		return "%d children but only %d people" % [Sim.children_count(state), people]
	for key in Sim._life_carry(state):  # part-people wait for a whole group (1 = one by one)
		var group := float(Sim.life_group_size(_data, key))
		if float(state.population.life_carry[key]) < 0.0 or float(state.population.life_carry[key]) >= group + 0.000001:
			return "part-people of %s at %s" % [key, state.population.life_carry[key]]
	if float(state.water_meter.m3) < 0.0:
		return "the water meter went below 0"
	# Power (plan.md §5.5): the meter never goes below 0, and buildings never get more power than
	# the network has.
	if Sim.power_on(_data):
		if float(state.get("power_meter", {}).get("mwh", 0.0)) < 0.0:
			return "the power meter went below 0"
		var power := Sim.power_summary(state, _data, settled)
		if float(power.used) > float(power.own) + float(power.grid) + 0.001:
			return "buildings get %s MW but the network only has %s" % [power.used, float(power.own) + float(power.grid)]
		var given := 0.0  # MW of the buildings marked as powered
		for b in state.buildings:
			if str(b.get("power", "")) == "on":
				given += Sim.power_need(_data, b)
		if given > float(power.own) + float(power.grid) + 0.001:
			return "buildings marked powered need %s MW but the network only has %s" % [given, float(power.own) + float(power.grid)]
	return ""


## Goods must be whole, not negative, and of a known kind; their cost tags not negative, and no
## cost tag left behind on goods that are gone.
func _goods_ok(where: String, goods: Dictionary, costs: Dictionary) -> String:
	for res in goods:
		if not _data.resources.has(res):
			return "%s holds unknown goods '%s'" % [where, res]
		if typeof(goods[res]) != TYPE_INT or int(goods[res]) < 0:
			return "%s holds %s %s" % [where, goods[res], res]
	for res in costs:
		if float(costs[res]) < -0.5:
			return "%s: the cost tag of %s is negative (%s cents)" % [where, res, costs[res]]
		if int(goods.get(res, 0)) <= 0 and absf(float(costs[res])) > 0.5:
			return "%s: a cost tag of %s cents is left on %s that are gone" % [where, costs[res], res]
	return ""


## A building's batch (plan.md §5.1): only a Farm, Mill or Bakery has one; it uses a known recipe;
## its finished hours are between 0 and its length; it never hands out more than it has made; its
## cost and wages aren't negative; and a finished batch with nothing left to collect is gone.
func _batch_ok(b: Dictionary, def: Dictionary) -> String:
	var name := _name(b)
	if not Sim.has_batch(b):
		return ""
	if not Sim.makes_batches(_data, b):
		return "%s has a batch but makes nothing" % name
	var batch: Dictionary = b.batch
	if Sim._recipe(def, str(batch.recipe_id)).is_empty():
		return "%s has a batch of an unknown recipe %s" % [name, batch.recipe_id]
	var hours := int(batch.hours)
	var made := int(batch.get("made_hours", 0))
	if hours < 1 or hours > Sim.batch_hours_limit(_data) or made < 0 or made > hours:
		return "%s has made %d of its batch's %d hours" % [name, made, hours]
	if float(batch.cost) < -0.5 or int(batch.wages) < 0:
		return "%s's batch costs %s cents (wages %s)" % [name, batch.cost, batch.wages]
	# By-products (plan.md §5.14): each unit's cost, times the units, adds up to the batch's cost.
	var parts := 0.0
	for res in batch.units:
		if Sim.batch_unit_cost(batch, res) < 0.0:
			return "%s's batch: a %s costs %s cents" % [name, res, Sim.batch_unit_cost(batch, res)]
		parts += Sim.batch_unit_cost(batch, res) * int(batch.units[res])
	if absf(parts - float(batch.cost)) > 0.5:
		return "%s's batch: its units' costs add up to %s cents, not its %s" % [name, parts, batch.cost]
	var broken := _goods_ok(name + "'s batch", batch.units, {})
	if broken == "":
		broken = _goods_ok(name + "'s collected units", batch.collected, {})
	if broken != "":
		return broken
	var made_units := Sim._units_after(batch, made)
	for res in batch.collected:
		if int(batch.collected[res]) > int(made_units.get(res, 0)):
			return "%s handed out %d %s but has only made %d" % [name, batch.collected[res], res, made_units.get(res, 0)]
	if not Sim.batch_running(b) and Sim.ready_units(b).is_empty():
		return "%s's batch is finished and collected but still there" % name
	return ""


## Cash minus (all income − all spending) in the statistics. Every cent that comes or goes must
## be counted there, so this never changes during a game (dev cash is set before it's measured).
func _ledger(state: Dictionary) -> int:
	var s: Dictionary = Sim.stats(state)
	return int(state.profile.currency) - (Sim._total(s.income) - Sim._total(s.spending))


## Every line of the balance sheet is a whole number of cents, none below 0 (debt and the bills
## are owed, never negative assets), and the totals add up.
func _balance_sheet_ok(sheet: Dictionary) -> String:
	var owned := 0
	for key in ["cash", "receivable", "in_production", "buildings", "being_built", "roads", "debt", "water_due"]:
		if typeof(sheet[key]) != TYPE_INT or int(sheet[key]) < 0:
			return "balance sheet: %s is %s" % [key, sheet[key]]
	for res in sheet.goods:
		if int(sheet.goods[res].value) < 0 or int(sheet.goods[res].qty) <= 0:
			return "balance sheet: %s goods at %s" % [res, sheet.goods[res]]
		owned += int(sheet.goods[res].value)
	owned += int(sheet.cash) + int(sheet.receivable) + int(sheet.in_production) + int(sheet.buildings) + int(sheet.being_built) + int(sheet.roads)
	if owned != int(sheet.total_owned) or int(sheet.company_value) != owned - int(sheet.total_owed):
		return "balance sheet: the totals don't add up (%s)" % sheet
	return ""


## A NaN or infinite number anywhere in the state: "path" of the first one, or "".
func _bad_number(value: Variant, path: String) -> String:
	match typeof(value):
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value):
				return "%s became %s" % [path, value]
		TYPE_DICTIONARY:
			for key in value:
				var found := _bad_number(value[key], "%s.%s" % [path, key])
				if found != "":
					return found
		TYPE_ARRAY:
			for i in value.size():
				var found := _bad_number(value[i], "%s[%d]" % [path, i])
				if found != "":
					return found
	return ""


## A refused action must say why and change nothing, apart from bringing time up to date
## (many actions settle first). So the state must equal either `before` or `before` settled.
func _refusal_changed_nothing(before: Dictionary, state: Dictionary, now: float, result: Dictionary) -> String:
	if str(result.get("error", "")) == "":
		return "an action was refused without saying why"
	if _difference(before, state, "state") == "":
		return ""
	var settled := before.duplicate(true)
	Sim.settle(settled, _data, now)
	var diff := _difference(settled, state, "state")
	if diff == "":
		return ""
	return "a refused action ('%s') still changed the game: %s" % [result.error, diff]


## Settling twice at the same moment must change nothing the second time.
func _settling_twice_changes_nothing(state: Dictionary, now: float) -> String:
	var once := state.duplicate(true)
	Sim.settle(once, _data, now)
	var twice := once.duplicate(true)
	Sim.settle(twice, _data, now)
	var diff := _difference(once, twice, "state")
	return "" if diff == "" else "settling twice at the same moment changed %s" % diff


## Save and load: the game must come back exactly as it was, and play on the same way.
func _round_trip(state: Dictionary, now: float) -> String:
	_counts.round_trips += 1
	var loaded := SaveFormat.from_text(SaveFormat.to_text(state, now), _data)
	if not loaded.ok:
		return "a save couldn't be loaded back: %s" % loaded.error
	if not loaded.warnings.is_empty():
		return "loading a fresh save gave warnings: %s" % ", ".join(loaded.warnings)
	var original := state.duplicate(true)
	original.save_version = Sim.SAVE_VERSION
	original.last_saved_at = now
	var diff := _difference(original, loaded.state, "state")
	if diff != "":
		return "a save didn't load back the same: %s" % diff
	var later := maxf(now, float(state.settled_at)) + 3.0 * 3600.0
	var saved_copy := original.duplicate(true)
	var loaded_copy: Dictionary = loaded.state.duplicate(true)
	Sim.settle(saved_copy, _data, later)
	Sim.settle(loaded_copy, _data, later)
	diff = _difference(saved_copy, loaded_copy, "state")
	if diff != "":
		# Godot's JSON reader can get the last digit of a 17-digit time wrong (1052903.1231145263
		# comes back as ...265), so a batch due exactly at `later` may land a billionth of a second
		# either side of it. That's not a real difference: both have played it out a second later.
		# (Fresh copies, because the graph point taken at `later` would keep the difference.)
		Sim.settle(original, _data, later + 1.0)
		Sim.settle(loaded.state, _data, later + 1.0)
		diff = _difference(original, loaded.state, "state")
	return "" if diff == "" else "a loaded game played on differently from the one that was saved: %s" % diff


## The idle-game promise: being away for a while (the game works it out in one settle when it
## opens) ends exactly like playing through it (the open game settles every second).
func _away_matches_playing(rng: RandomNumberGenerator, state: Dictionary, now: float) -> String:
	_counts.parity += 1
	var start := maxf(now, float(state.settled_at))
	var away := state.duplicate(true)
	var playing := state.duplicate(true)
	Sim.settle(away, _data, start)
	Sim.settle(playing, _data, start)
	var minutes := rng.randi_range(5, 120)
	var until := start + minutes * 60.0
	Sim.settle(away, _data, until)
	var t := start
	while t < until:
		t = minf(t + 1.0, until)
		Sim.settle(playing, _data, t)
	var diff := _outcome_difference(away, playing)
	return "" if diff == "" else "%d min away ended differently from playing through them (away vs playing): %s" % [minutes, diff]


## What the player can see: cash, goods, workers, people, queues and shelves.
func _outcome_difference(a: Dictionary, b: Dictionary) -> String:
	if int(a.profile.currency) != int(b.profile.currency):
		return "cash %d vs %d cents" % [a.profile.currency, b.profile.currency]
	var value_a := int(Sim.balance_sheet(a, _data, float(a.settled_at)).company_value)
	var value_b := int(Sim.balance_sheet(b, _data, float(b.settled_at)).company_value)
	if value_a != value_b:
		return "company value %d vs %d cents" % [value_a, value_b]
	if int(a.population.current) != int(b.population.current):
		return "people %d vs %d" % [a.population.current, b.population.current]
	if Sim.children_count(a) != Sim.children_count(b):
		return "children %d vs %d" % [Sim.children_count(a), Sim.children_count(b)]
	if str(Sim.people_stats(a)) != str(Sim.people_stats(b)):
		return "births and deaths %s vs %s" % [Sim.people_stats(a), Sim.people_stats(b)]
	var diff := _difference(a.inventory, b.inventory, "warehouse")
	for i in a.buildings.size():
		if diff != "":
			break
		var x: Dictionary = a.buildings[i]
		var y: Dictionary = b.buildings[i]
		diff = _difference(x.get("storage", {}), y.get("storage", {}), "%s storage" % _name(x))
		if diff == "":
			diff = _difference(x.get("batch", {}), y.get("batch", {}), "%s batch" % _name(x))
		if diff == "" and Sim.hired(x) != Sim.hired(y):
			diff = "%s: workers %d vs %d" % [_name(x), Sim.hired(x), Sim.hired(y)]
		if diff == "":
			diff = _difference(x.get("shelves", []), y.get("shelves", []), "%s shelves" % _name(x))
	return diff


# --- Old saves -----------------------------------------------------------------------

## Every save in tests/saves/ (one per old save_version) must still load and play on for a week.
func _check_old_saves() -> void:
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		return
	for file in DirAccess.get_files_at(SAVES_DIR):
		if not file.ends_with(".json"):
			continue
		_log = ["load tests/saves/%s, then play on for a week" % file]
		var errors_before := _errors.count
		var loaded := SaveFormat.from_text(FileAccess.get_file_as_string(SAVES_DIR + file), _data)
		var problem := ""
		if not loaded.ok:
			problem = "an old save doesn't load any more (%s): %s" % [file, loaded.error]
		else:
			var state: Dictionary = loaded.state
			var before := state.duplicate(true)
			var later := float(state.settled_at) + 7.0 * 86400.0
			Sim.settle(state, _data, later)
			problem = _invariants(state, later, before, _ledger(before), {})
			if problem != "":
				problem = "old save %s: %s" % [file, problem]
		if _errors.count > errors_before:
			problem = "old save %s: Godot reported a script error (see above)" % file
		print("Old save %s: %s" % [file, "loads and plays on" if problem == "" else "PROBLEM"])
		if problem != "":
			_report(problem, -1, false)


## Writes a save of the current version, made by a scripted game that uses every building, to
## tests/saves/. Do this BEFORE raising SAVE_VERSION, so the new version must load it.
func _write_save_sample() -> int:
	var path := "%ssave_v%d.json" % [SAVES_DIR, Sim.SAVE_VERSION]
	if FileAccess.file_exists(path):
		print("%s already exists" % path)
		return 1
	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var now := T0
	var state := Sim.new_game(_data, now)
	Sim.dev_set_cash(state, 100_000 * 100)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for type in ["small_house", "small_house", "small_house", "wheat_farm", "wheat_farm", "flour_mill", "bakery", "supermarket", "warehouse"]:
		Sim.build(state, _data, type, _free_cell(rng, state), now)
	for hour in 3:
		now += 3600.0
		for b in state.buildings:
			Sim.collect(state, _data, b.id, now)
			for recipe in _recipe_ids(b):
				var hours := mini(Sim.batch_max_hours(state, _data, b.id, recipe, "small"), 2)
				Sim.start_batch(state, _data, b.id, recipe, hours, "small", now)
	for res in Sim.shop_products(_data):
		var qty := int(state.inventory.get(res, 0)) / 2
		if qty > 0:
			Sim.stock_shelf(state, _data, _some_building(rng, state, ["retail"]).id, res, qty, "normal", now)
	now += 600.0
	var farm := _some_building(rng, state, ["extractor"])
	Sim.set_staffing(state, _data, farm.id, "low", now)
	Sim.suspend(state, _data, state.buildings[-1].id, now)  # the last warehouse, so "suspended" is in it
	Sim.settle(state, _data, now)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(SaveFormat.to_text(state, now))
	file.close()
	print("Wrote %s" % path)
	return 0


# --- Reporting -------------------------------------------------------------------------

## Prints the first game that hit each kind of problem, with the steps that led to it.
func _report(problem: String, game_seed: int, verbose: bool) -> void:
	var kind := RegEx.create_from_string("-?\\d+(\\.\\d+)?").sub(problem, "#", true)
	_problems[kind] = int(_problems.get(kind, 0)) + 1
	if _problems[kind] > 1 and not verbose:
		return  # already shown for an earlier game
	print("\nPROBLEM: %s" % problem)
	if game_seed >= 0:
		print("  game %d, the last steps before it:" % game_seed)
		for line in _log.slice(maxi(_log.size() - 8, 0)):
			print("    ", line)
		print("  Replay it step by step: %s --seed=%d --steps=%d" % [GODOT, game_seed, _log.size()])
	else:
		print("  ", _log[0])


# --- Helpers ---------------------------------------------------------------------------

## The first difference between two values ("" if equal). Numbers compare by value (a save
## turns 5.0 into 5), to a millionth: times are unix seconds (about 1,700,000,000), so an
## allowance that grew with the number would hide whole seconds.
func _difference(a: Variant, b: Variant, path: String) -> String:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return "" if absf(float(a) - float(b)) <= 0.000001 else "%s is %s vs %s" % [path, a, b]
	if typeof(a) != typeof(b):
		return "%s is %s vs %s" % [path, a, b]
	if a is Dictionary:
		for key in a:
			if not b.has(key):
				return "%s.%s is missing on one side" % [path, key]
			var found := _difference(a[key], b[key], "%s.%s" % [path, key])
			if found != "":
				return found
		for key in b:
			if not a.has(key):
				return "%s.%s is missing on one side" % [path, key]
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s has %d vs %d entries" % [path, a.size(), b.size()]
		for i in a.size():
			var found := _difference(a[i], b[i], "%s[%d]" % [path, i])
			if found != "":
				return found
		return ""
	return "" if a == b else "%s is %s vs %s" % [path, a, b]


func _buildable() -> Array:
	var out := []
	for id in _data.buildings:
		if _data.buildings[id].get("buildable", false):
			out.append(id)
	return out


func _recipe_ids(b: Dictionary) -> Array:
	var out := []
	for recipe in _data.buildings.get(b.get("type", ""), {}).get("recipes", []):
		out.append(recipe.id)
	return out if not out.is_empty() else ["nonsense"]


## Mostly a building of one of `categories` (any building when empty), sometimes any other
## building or none at all, so the "wrong building" answers get tried too.
func _some_building(rng: RandomNumberGenerator, state: Dictionary, categories: Array) -> Dictionary:
	if state.buildings.is_empty() or rng.randf() < 0.03:
		return {}
	var fitting := []
	for b in state.buildings:
		if categories.is_empty() or _data.buildings.get(b.type, {}).get("category", "") in categories:
			fitting.append(b)
	if fitting.is_empty() or rng.randf() < 0.1:
		return _pick(rng, state.buildings)
	return _pick(rng, fitting)


func _free_cell(rng: RandomNumberGenerator, state: Dictionary) -> Vector2i:
	var grid: Array = state.plot.grid_size
	for attempt in 50:
		var cell := Vector2i(rng.randi_range(0, int(grid[0]) - 1), rng.randi_range(0, int(grid[1]) - 1))
		if Sim.building_at(state, cell).is_empty():
			return cell
	return Vector2i(0, 0)


func _pick(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi_range(0, list.size() - 1)] if not list.is_empty() else ""


func _name(b: Dictionary) -> String:
	return "%s %s" % [b.type, b.id] if not b.is_empty() else "(no building)"


func _clock(now: float) -> String:
	var s := int(now - T0)
	return "day %d %02d:%02d:%02d" % [s / 86400, s % 86400 / 3600, s % 3600 / 60, s % 60] if s >= 0 else "before the start"


func _signed_time(seconds: float) -> String:
	var size := absf(seconds)
	var text := "%.1fs" % size if size < 120.0 else ("%.0f min" % (size / 60.0) if size < 7200.0 else "%.1f h" % (size / 3600.0))
	return ("-" if seconds < 0.0 else "+") + text
