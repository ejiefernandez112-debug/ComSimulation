extends RefCounted
## Pure Phase 1a game rules (plan.md §5). No nodes, no clock, no files:
## every function is handed the game state, the content data and "now".
##
## Money: the data files use plain dollars (build_cost 2000, wage 15); the state and every
## function here use whole CENTS (cash 575000 = $5,750.00), so sums never drift (plan.md §5.12).
## Keeping it pure makes it testable, and it's the part a Phase 4 server would port (plan.md §3.1).
##
## `data`  = { "resources": {...}, "buildings": {...}, "config": {...} } from data/*.json
## `state` = the player's save, shaped like plan.md §8.
## Player actions return { "ok": bool, "error": String, ...extra }.
##
## Time model: buildings store when their current cycle/job started (`job_started_at`).
## "Settling" turns elapsed time into finished output in one calculation, never tick-by-tick.

const SAVE_VERSION := 5  # 2: warehouses are buildings; 3: buildings keep their own hired workers;
# 4: money is stored in cents; 5: stock carries cost tags
## Used when game_config.json has no staffing_levels: share of max_workers per level.
const DEFAULT_STAFFING_LEVELS := {"low": 0.5, "medium": 0.75, "high": 1.0}


# --- New game -----------------------------------------------------------------

static func new_game(data: Dictionary, now: float) -> Dictionary:
	var config: Dictionary = data.config
	var state := {
		"save_version": SAVE_VERSION,
		"last_saved_at": now,
		"profile": {"currency": cents(float(config.starting_cash))},  # cash, in cents
		"plot": {"grid_size": [int(config.grid_size[0]), int(config.grid_size[1])]},
		"next_building_id": 1,
		"buildings": [],
		"inventory": {},  # the Warehouse
		"population": {"current": 0, "growth_anchor": now},
		"settled_at": now,  # everything has been worked out up to this moment
		"stats": _new_stats(),
		"water_meter": {"m3": 0.0, "base_cost": 0.0, "cycle_start": now},  # the first bill is due in 12 h
	}
	for entry in config.starting_buildings:
		# Starting buildings are already standing: no construction time.
		_add_building(state, entry.type, Vector2i(int(entry.position[0]), int(entry.position[1])), now, 0.0)
	return state


# --- Settling time ------------------------------------------------------------

## Brings every building, the population and wages up to `now`.
## Returns everything produced, e.g. {"wheat": 30, "population": 2, "wages": 12000, "water": 71800}
## (money in cents; "water" = water bills charged; for the offline summary).
##
## A building's speed depends on how many workers are actually working in it (see
## building_speed), and wages are paid for each of them. That only changes at a few moments
## (a person moves in and is hired, a building finishes or stops, the player changes staffing,
## which settles first),
## so the time since the last settle is split at those moments and each piece is worked out in
## one go. That's a handful of steps however long the player was away, never a minute-by-minute
## replay.
static func settle(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var report := {}
	var grown := 0
	var wages := 0
	var water := 0
	var t := float(state.get("settled_at", state.get("last_saved_at", now)))
	if now <= t:
		# No time to add (or the clock moved backwards): only settle what can happen instantly,
		# e.g. a finished batch that was waiting for storage space the player just freed.
		for b in state.buildings:
			_add_to(report, _settle_one(state, b, data, now))
	else:
		var steps := 0
		while t < now and steps < 100000:  # the cap is only a safety net
			steps += 1
			_hire(state, data, t)  # people who just moved in, or posts that just opened
			# Read every speed, the wage bill and the water use as they stand at the start of this
			# piece, before any building moves on (a building filling up changes the others' staffing).
			var speeds: Array[float] = []
			for b in state.buildings:
				speeds.append(building_speed(state, data, b, t))
			var wage_rate := _wages_per_hour(state, data, t)
			var water_m3_per_hour := water_use_total(state, data, t)
			# Split at the next staffing change, and at the next water bill (a fixed moment) when
			# there is water to bill; empty cycles are skipped in one go, so a long absence stays quick.
			var next := _next_staffing_change(state, data, t, now)
			if water_m3_per_hour > 0.0 or float(water_meter(state, t).m3) > 0.0:
				next = minf(next, maxf(water_bill_due_at(state, data, t), t + 0.000001))
			for i in state.buildings.size():
				_add_to(report, _settle_span(state, state.buildings[i], data, t, next, speeds[i]))
			wages += _pay_wages(state, wage_rate * (next - t) / 3600.0)
			_meter_water(state, data, water_m3_per_hour * (next - t) / 3600.0, t)
			grown += _grow_population(state, data, next)
			t = next
			water += _bill_water_if_due(state, data, t)
		state["settled_at"] = now
	_hire(state, data, now)
	if grown > 0:
		report["population"] = grown
	if wages > 0:
		report["wages"] = wages
	if water > 0:
		report["water"] = water
	_record_history(state, data, now)
	return report


## Settles one building over [t0, t1] while it works at `speed` (1 = full speed). A building
## at 70% speed gets 70% of the time's work: it is settled up to t0 + 0.7 x (t1 - t0), then its
## current job's start is moved later by the other 30%, so at t1 it is exactly as far along as
## that work allows.
static func _settle_span(state: Dictionary, b: Dictionary, data: Dictionary, t0: float, t1: float, speed: float) -> Dictionary:
	if speed >= 1.0 or float(b.job_started_at) > t0:
		return _settle_one(state, b, data, t1)  # full speed (or not started yet, e.g. being built)
	var span := t1 - t0
	var produced := _settle_one(state, b, data, t0 + speed * span)
	b.job_started_at = float(b.job_started_at) + span * (1.0 - speed)
	return produced


## Takes wages (`dollars`) out of cash. Cash may go below 0 (debt); sales pay it back. Parts of a
## cent are kept in "wage_carry" until they add up, so many short settles cost exactly the same
## as one long one. Returns the cents paid.
static func _pay_wages(state: Dictionary, dollars: float) -> int:
	return _pay_over_time(state, dollars, "wage_carry", "wages")


## A running cost paid out of cash over time (into debt if need be), counted in the statistics
## under `spending_key`; parts of a cent wait in `carry_key`. Returns the cents paid.
static func _pay_over_time(state: Dictionary, dollars: float, carry_key: String, spending_key: String) -> int:
	if dollars <= 0.0:
		return 0
	var owed := float(state.get(carry_key, 0.0)) + dollars * 100.0  # in cents
	var whole := floori(owed)
	state[carry_key] = owed - whole
	state.profile.currency -= whole
	var spending: Dictionary = stats(state).spending
	spending[spending_key] = int(spending.get(spending_key, 0)) + whole
	return whole


## The first moment after t (and before `until`) when staffing or wages can change: a building
## finishing construction (new posts or new homes), a building stopping because its storage
## filled up or its last job is done (its workers wait, unpaid), or, while posts are open, the
## next person moving in (they're hired straight away).
static func _next_staffing_change(state: Dictionary, data: Dictionary, t: float, until: float) -> float:
	var next := until
	for b in state.buildings:
		var finish := built_at(b)
		if finish > t and finish < next:
			next = finish
		next = minf(next, maxf(_stop_time(state, data, b, t), t + 0.000001))
	var pop: Dictionary = state.population
	var step := float(data.config.population_growth_seconds)
	var e := employment(state, data, t)
	if step > 0.0 and e.open_jobs > 0 and int(pop.current) < population_capacity(state, data, t):
		var arrival := float(pop.growth_anchor) + step * (floorf((t - float(pop.growth_anchor)) / step + 0.000001) + 1.0)
		if arrival > t and arrival < next:
			next = arrival
	return next


## Grows the population up to `now`. A home finishing construction raises the cap partway through,
## so grow up to each such moment with the cap that applied before it.
static func _grow_population(state: Dictionary, data: Dictionary, now: float) -> int:
	var grown := 0
	var finishes: Array[float] = []
	for b in state.buildings:
		var t := built_at(b)
		if t > float(state.population.growth_anchor) and t <= now and int(data.buildings.get(b.type, {}).get("population_capacity", 0)) > 0:
			finishes.append(t)
	finishes.sort()
	for t in finishes:
		grown += _settle_population(state, data, t, _capacity(state, data, t, false))
	grown += _settle_population(state, data, now, population_capacity(state, data, now))
	return grown


## settle_building, plus counting what was made for the statistics. Rules code uses this one.
static func _settle_one(state: Dictionary, b: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var produced := settle_building(b, data, now, state)
	_add_to(stats(state).made, produced)
	return produced


## Moves a building's work forward to `now`. With `state`, finished batches also get their cost
## tags (ingredients + wages + water, plan.md §5.14).
static func settle_building(b: Dictionary, data: Dictionary, now: float, state: Dictionary = {}) -> Dictionary:
	if is_suspended(b):
		return {}  # switched off: nothing moves (resume starts its work afresh)
	var def: Dictionary = data.buildings.get(b.type, {})
	match def.get("category", ""):
		"extractor":
			return _settle_extractor(b, def, now, state, data)
		"processor":
			return _settle_processor(b, def, now, state, data)
	return {}


## The running cost (cents) of one batch of `recipe` here, or 0 when not tracking costs.
static func _running_cost_cents(state: Dictionary, data: Dictionary, b: Dictionary, recipe: Dictionary) -> float:
	if state.is_empty():
		return 0.0
	var running := batch_running_cost(state, data, b, recipe)
	return float(running.wages) + float(running.water)


## Extractors (Wheat Farm) produce on their own, one batch per cycle, until storage is full.
static func _settle_extractor(b: Dictionary, def: Dictionary, now: float, state: Dictionary, data: Dictionary) -> Dictionary:
	var recipe: Dictionary = def.recipes[0]
	var duration := float(recipe.duration)
	var per_cycle := _total(recipe.outputs)
	var space := int(def.storage_cap) - _total(b.storage)
	if per_cycle <= 0 or now < b.job_started_at:
		return {}  # clock moved backwards: wait for it to catch up, never go negative
	if space < per_cycle:
		b.job_started_at = now  # full: production is paused until the player collects
		return {}
	var cycles := int((now - b.job_started_at) / duration)
	var fits := floori(float(space) / per_cycle)
	var done := mini(cycles, fits)
	var produced := _scaled(recipe.outputs, done)
	_add_to(b.storage, produced)
	if done > 0:
		_put_cost(_costs(b, "storage_cost"), _spread_cost(produced, done * _running_cost_cents(state, data, b, recipe)))
	if cycles >= fits:
		b.job_started_at = now  # it filled up somewhere in that time; restart once collected
	else:
		b.job_started_at += done * duration
	return produced


## Processors (Mill, Bakery) work through their job queue one job at a time.
## A finished job waits ("blocked") if the building's storage has no room for its output.
static func _settle_processor(b: Dictionary, def: Dictionary, now: float, state: Dictionary, data: Dictionary) -> Dictionary:
	var produced := {}
	while not b.queue.is_empty():
		var recipe := _recipe(def, b.queue[0].recipe_id)
		if recipe.is_empty():
			b.queue.pop_front()  # recipe no longer exists in data: drop the job
			continue
		var finish: float = b.job_started_at + float(recipe.duration)
		if finish > now:
			break  # still working (also covers a clock that moved backwards)
		if int(def.storage_cap) - _total(b.storage) < _total(recipe.outputs):
			b.blocked = true
			break
		var outputs := _scaled(recipe.outputs, 1)
		_add_to(b.storage, outputs)
		_add_to(produced, outputs)
		# Its cost tag: what its ingredients cost when it was queued + wages + water.
		var batch_cost := _running_cost_cents(state, data, b, recipe)
		for res in b.queue[0].get("input_cost", {}):
			batch_cost += float(b.queue[0].input_cost[res])
		_put_cost(_costs(b, "storage_cost"), _spread_cost(outputs, batch_cost))
		b.queue.pop_front()
		# The next job starts when this one finished, or right now if it had been waiting for space.
		b.job_started_at = now if b.blocked else finish
		b.blocked = false
	return produced


static func _settle_population(state: Dictionary, data: Dictionary, now: float, cap: int) -> int:
	var pop: Dictionary = state.population
	var step := float(data.config.population_growth_seconds)
	if step <= 0.0 or now < pop.growth_anchor:
		return 0
	if pop.current >= cap:
		pop.growth_anchor = now
		return 0
	# (The tiny extra stops rounding from losing a person who arrives exactly at `now`.)
	var grown := mini(int((now - pop.growth_anchor) / step + 0.000001), cap - int(pop.current))
	pop.current += grown
	if pop.current >= cap:
		pop.growth_anchor = now
	else:
		pop.growth_anchor += grown * step
	return grown


# --- Player actions -----------------------------------------------------------

## Whether a building could go on this cell right now (changes nothing).
## The placement preview uses this too, so preview and real build always agree.
static func can_build(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i) -> Dictionary:
	var def: Dictionary = data.buildings.get(type_id, {})
	if def.is_empty() or not def.get("buildable", false):
		return _fail("This building can't be built.")
	if not _in_plot(state, cell):
		return _fail("That spot is outside your land.")
	if not building_at(state, cell).is_empty():
		return _fail("That spot is taken.")
	if state.profile.currency < cents(float(def.build_cost)):
		return _fail("Not enough money.")
	return _ok({})


static func build(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i, now: float) -> Dictionary:
	var check := can_build(state, data, type_id, cell)
	if not check.ok:
		return check
	settle(state, data, now)  # time so far was worked with the old staffing
	var def: Dictionary = data.buildings[type_id]
	state.profile.currency -= cents(float(def.build_cost))
	stats(state).spending.construction += cents(float(def.build_cost))
	var b := _add_building(state, type_id, cell, now, now + float(def.get("build_time", 0.0)))
	_hire(state, data, now)  # a building ready at once hires now; others when construction ends
	return _ok({"building_id": b.id})


## Whether a building could be moved to this cell (changes nothing). Moving is free, any building
## can move, and everything inside keeps going: production doesn't depend on where it stands.
## Its own cell counts as free (dropping it back where it was is fine).
static func can_move(state: Dictionary, building_id: String, cell: Vector2i) -> Dictionary:
	if find_building(state, building_id).is_empty():
		return _fail("Building not found.")
	if not _in_plot(state, cell):
		return _fail("That spot is outside your land.")
	var there := building_at(state, cell)
	if not there.is_empty() and there.id != building_id:
		return _fail("That spot is taken.")
	return _ok()


static func move(state: Dictionary, building_id: String, cell: Vector2i) -> Dictionary:
	var check := can_move(state, building_id, cell)
	if not check.ok:
		return check
	find_building(state, building_id).position = [cell.x, cell.y]
	return _ok()


## Whether the building's staffing could be set to `level` ("low", "medium", "high"); changes nothing.
static func can_set_staffing(state: Dictionary, data: Dictionary, building_id: String, level: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if max_workers(data, b) <= 0:
		return _fail("This building has no workers.")
	if has_fixed_workers(data, b):
		return _fail("Its number of workers is fixed. Upgrading it adds more.")
	if not data.config.get("staffing_levels", DEFAULT_STAFFING_LEVELS).has(level):
		return _fail("Unknown staffing level.")
	return _ok()


## Choose how many workers the building employs: fewer = slower but cheaper wages.
## Time before the change is worked out with the old staffing first.
static func set_staffing(state: Dictionary, data: Dictionary, building_id: String, level: String, now: float) -> Dictionary:
	var check := can_set_staffing(state, data, building_id, level)
	if not check.ok:
		return check
	settle(state, data, now)
	find_building(state, building_id)["staffing"] = level
	_hire(state, data, now)  # lower: the extra workers are freed for other posts; higher: new posts
	return _ok()


## Whether the building's wage bonus could be set to `level` ("none", "small", "good", "big").
static func can_set_bonus(state: Dictionary, data: Dictionary, building_id: String, level: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if max_workers(data, b) <= 0:
		return _fail("This building has no workers.")
	if has_fixed_wage(data, b):
		return _fail("It always pays the minimum wage: no bonus here.")
	if not data.config.get("wage_bonuses", {}).has(level):
		return _fail("Unknown bonus.")
	return _ok()


## Choose the wage bonus: a bigger bonus costs more per worker and puts the building first in
## line for free workers. It never pulls workers from other buildings (they're tied there).
static func set_bonus(state: Dictionary, data: Dictionary, building_id: String, level: String, now: float) -> Dictionary:
	var check := can_set_bonus(state, data, building_id, level)
	if not check.ok:
		return check
	settle(state, data, now)  # time so far is paid at the old wage
	find_building(state, building_id)["bonus"] = level
	_hire(state, data, now)
	return _ok()


## Whether a job could be queued right now (changes nothing). The UI uses this to grey out its
## button, and enqueue uses it too, so the button and the real action always agree.
static func can_enqueue(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	var def: Dictionary = data.buildings.get(b.type, {})
	if def.get("category", "") != "processor":
		return _fail("This building doesn't take orders.")
	if not is_built(b, now):
		return _fail("Still under construction.")
	if is_suspended(b):
		return _fail("It's suspended. Resume it first.")
	var recipe := _recipe(def, recipe_id)
	if recipe.is_empty():
		return _fail("Unknown recipe.")
	if b.queue.size() >= int(def.queue_size):
		return _fail("The queue is full.")
	for res in recipe.inputs:
		if int(state.inventory.get(res, 0)) < int(recipe.inputs[res]):
			return _fail("Not enough %s." % _resource_name(data, res))
	return _ok()


## Queue a job. Inputs leave the Warehouse now, so a queued job can never stall for inputs.
static func enqueue(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # a job may have just finished, freeing a queue slot
	var check := can_enqueue(state, data, building_id, recipe_id, now)
	if not check.ok:
		return check
	var recipe := _recipe(data.buildings[b.type], recipe_id)
	# The ingredients take their cost tags with them into the batch (plan.md §5.14).
	var input_cost := _take_cost(state.inventory, _costs(state, "inventory_cost"), recipe.inputs)
	_remove_from(state.inventory, recipe.inputs)
	if b.queue.is_empty():
		b.job_started_at = now
		b.blocked = false
	b.queue.append({"recipe_id": recipe_id, "input_cost": input_cost})
	return _ok()


## How many more batches could be queued right now: limited by free queue slots and by
## ingredients in the Warehouse. 0 means none (can_enqueue says why).
static func batches_possible(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, now: float) -> int:
	if not can_enqueue(state, data, building_id, recipe_id, now).ok:
		return 0
	var b := find_building(state, building_id)
	var def: Dictionary = data.buildings[b.type]
	var count: int = int(def.queue_size) - b.queue.size()
	var inputs: Dictionary = _recipe(def, recipe_id).inputs
	for res in inputs:
		if int(inputs[res]) > 0:
			count = mini(count, floori(float(state.inventory.get(res, 0)) / int(inputs[res])))
	return count


## Queue as many batches as fit (see batches_possible). Returns "added" and the ingredients "used".
static func fill_queue(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # a job may have just finished, freeing a slot
	var check := can_enqueue(state, data, building_id, recipe_id, now)
	if not check.ok:
		return check
	var count := batches_possible(state, data, building_id, recipe_id, now)
	for i in count:
		enqueue(state, data, building_id, recipe_id, now)
	return _ok({"added": count, "used": _scaled(_recipe(data.buildings[b.type], recipe_id).inputs, count)})


## Move finished goods from the building into the Warehouse (as much as fits).
static func collect(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	settle(state, data, now)
	if b.storage.is_empty():
		return _fail("Nothing to collect.")
	var free := warehouse_cap(state, data) - warehouse_total(state)
	var moved := {}
	for res in b.storage:
		var qty := mini(int(b.storage[res]), free)
		if qty > 0:
			moved[res] = qty
			free -= qty
	if moved.is_empty():
		return _fail("The warehouse is full.")
	var moved_cost := _take_cost(b.storage, _costs(b, "storage_cost"), moved)  # cost tags go along
	_remove_from(b.storage, moved)
	_add_to(state.inventory, moved)
	_put_cost(_costs(state, "inventory_cost"), moved_cost)
	settle(state, data, now)  # a job that was waiting for space can finish now
	return _ok({"moved": moved})


## What cancelling job `index` of a processor's queue would give back (changes nothing).
## Jobs still waiting refund config.cancel_refund_waiting of their inputs; the job being worked on
## refunds config.cancel_refund_in_progress (rounded down). A finished job can't be cancelled.
static func can_cancel_job(state: Dictionary, data: Dictionary, building_id: String, index: int) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if index < 0 or index >= b.queue.size():
		return _fail("There's no job there.")
	if index == 0 and b.blocked:
		return _fail("That batch is finished. Collect it instead.")
	var recipe := _recipe(data.buildings[b.type], b.queue[index].recipe_id)
	var key := "cancel_refund_in_progress" if index == 0 else "cancel_refund_waiting"
	var refund := _share(recipe.get("inputs", {}), float(data.config.get(key, 0.0)))
	if warehouse_total(state) + _total(refund) > warehouse_cap(state, data):
		return _fail("Not enough room in the warehouse for the refund.")
	return _ok({"refund": refund, "in_progress": index == 0})


static func cancel_job(state: Dictionary, data: Dictionary, building_id: String, index: int, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # the job may have just finished
	var check := can_cancel_job(state, data, building_id, index)
	if not check.ok:
		return check
	var job: Dictionary = b.queue[index]
	var refund_cost := _refund_cost(job, _recipe(data.buildings[b.type], job.recipe_id), check.refund)
	b.queue.remove_at(index)
	_add_to(state.inventory, check.refund)
	_put_cost(_costs(state, "inventory_cost"), refund_cost)  # what's given back keeps its cost tag
	if index == 0:
		b.job_started_at = now  # the next job (if any) starts from scratch now
	return check


## What demolishing a building would give back (changes nothing): config.demolish_refund of its
## build cost, the goods in its storage, and the inputs of its queued jobs (same rules as
## cancelling). Only buildings the player can build can be demolished, so starters stay.
static func can_demolish(state: Dictionary, data: Dictionary, building_id: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	var def: Dictionary = data.buildings.get(b.type, {})
	if not def.get("buildable", false):
		return _fail("This building can't be demolished.")
	if def.get("category", "") == "storage" and _count_category(state, data, "storage") <= 1:
		return _fail("You need at least one warehouse.")
	var goods := _goods_inside(data, b)
	var room := warehouse_cap(state, data) - storage_capacity(state, data, b)  # a warehouse takes its room with it
	if warehouse_total(state) + _total(goods) > room:
		if def.get("category", "") == "storage":
			return _fail("The other warehouses don't have room for your goods. Make room first.")
		return _fail("Not enough room in the warehouse for what's inside. Make room first.")
	var money := roundi(cents(float(def.get("build_cost", 0))) * float(data.config.get("demolish_refund", 0.0)))
	return _ok({"money": money, "goods": goods})


## What a building hands back when its work is stopped for good (demolish, suspend): the goods in
## its storage, a finished batch waiting for room, and its queued jobs' ingredients (the batch
## being made gives back cancel_refund_in_progress of them, waiting ones cancel_refund_waiting).
static func _goods_inside(data: Dictionary, b: Dictionary) -> Dictionary:
	var def: Dictionary = data.buildings.get(b.type, {})
	var goods: Dictionary = b.storage.duplicate()
	for i in b.queue.size():
		if i == 0 and b.blocked:
			_add_to(goods, _recipe(def, b.queue[0].recipe_id).get("outputs", {}))  # finished, so it's yours
			continue
		var key := "cancel_refund_in_progress" if i == 0 else "cancel_refund_waiting"
		_add_to(goods, _share(_recipe(def, b.queue[i].recipe_id).get("inputs", {}), float(data.config.get(key, 0.0))))
	return goods


## The cost tags (cents) of _goods_inside, the same pieces in the same order: storage's tags, a
## finished batch's ingredients + running cost, and each refund's share of what it cost.
static func _goods_inside_cost(state: Dictionary, data: Dictionary, b: Dictionary) -> Dictionary:
	var def: Dictionary = data.buildings.get(b.type, {})
	var costs: Dictionary = _costs(b, "storage_cost").duplicate()
	for i in b.queue.size():
		var recipe := _recipe(def, b.queue[i].recipe_id)
		if i == 0 and b.blocked:
			var batch_cost := _running_cost_cents(state, data, b, recipe)
			for res in b.queue[0].get("input_cost", {}):
				batch_cost += float(b.queue[0].input_cost[res])
			_put_cost(costs, _spread_cost(recipe.get("outputs", {}), batch_cost))
			continue
		var key := "cancel_refund_in_progress" if i == 0 else "cancel_refund_waiting"
		_put_cost(costs, _refund_cost(b.queue[i], recipe, _share(recipe.get("inputs", {}), float(data.config.get(key, 0.0)))))
	return costs


static func _count_category(state: Dictionary, data: Dictionary, category: String) -> int:
	var count := 0
	for b in state.buildings:
		if data.buildings.get(b.type, {}).get("category", "") == category:
			count += 1
	return count


## Whether the building could be suspended now (changes nothing):
## {"ok", "error", "goods" (what goes to the warehouse)}. Suspending is a "soft demolish" that
## keeps the building: work in progress is lost, everything already made or paid for comes back,
## and its workers go home (no wages, no power) until it's resumed, for free (plan.md §5.10).
static func can_suspend(state: Dictionary, data: Dictionary, building_id: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if max_workers(data, b) <= 0:
		return _fail("This building has nothing to switch off.")
	if is_suspended(b):
		return _fail("It's already suspended.")
	if not is_built(b, float(state.get("settled_at", 0.0))):
		return _fail("Still under construction.")
	if warehouse_total(state) > warehouse_cap(state, data) - storage_capacity(state, data, b):
		return _fail("The other warehouses don't have room for your goods. Make room first.")
	return _ok({"goods": _goods_inside(data, b)})


## Suspend: the queue and storage are emptied into the warehouse (what doesn't fit stays inside
## to be collected later), the current batch or growing field is lost, and the workers go home.
## Returns "moved" (into the warehouse) and "kept" (left in the building).
static func suspend(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)
	var check := can_suspend(state, data, building_id)
	if not check.ok:
		return check
	var costs := _goods_inside_cost(state, data, b)  # the goods keep their cost tags
	b.storage = {}
	b.queue = []
	b.blocked = false
	b["suspended"] = true
	var free := warehouse_cap(state, data) - warehouse_total(state)  # after its workers left
	var moved := {}
	var kept := {}
	var moved_cost := {}
	var kept_cost := {}
	for res in check.goods:
		var all := int(check.goods[res])
		var qty := mini(all, maxi(free, 0))
		free -= qty
		var cost := float(costs.get(res, 0.0))
		if qty > 0:
			moved[res] = qty
			moved_cost[res] = cost * qty / all
		if all > qty:
			kept[res] = all - qty
			kept_cost[res] = cost * (all - qty) / all
	_add_to(state.inventory, moved)
	_put_cost(_costs(state, "inventory_cost"), moved_cost)
	b.storage = kept
	b["storage_cost"] = kept_cost
	b["hired"] = 0  # its workers are freed: they take open posts elsewhere
	_hire(state, data, now)
	return _ok({"moved": moved, "kept": kept})


## Resume a suspended building: the workers come back and its work starts from the beginning.
static func resume(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if not is_suspended(b):
		return _fail("It isn't suspended.")
	settle(state, data, now)
	b.erase("suspended")
	b.job_started_at = now
	b.blocked = false
	_hire(state, data, now)  # it queues for free workers again (its old ones went elsewhere)
	return _ok()


static func demolish(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)
	var check := can_demolish(state, data, building_id)
	if not check.ok:
		return check
	var costs := _goods_inside_cost(state, data, b)
	state.buildings.erase(b)
	state.profile.currency += int(check.money)
	stats(state).income.demolish += int(check.money)
	_add_to(state.inventory, check.goods)
	_put_cost(_costs(state, "inventory_cost"), costs)  # the goods keep their cost tags
	# Fewer homes can mean less room: people over the new capacity move away.
	var cap := population_capacity(state, data, now)
	if state.population.current > cap:
		state.population.current = cap
	_hire(state, data, now)  # its workers are freed; if people moved away, others may lose workers
	return check


## Sell to the NPC Retailer at its price (plan.md §5.2 channel 1, price §5.12), minus sales tax
## (§5.9). Returns, in cents: "earned" (what reaches cash), "gross" (before tax), "tax", "rate"
## (tax ÷ gross), "cost" (what the goods cost to make, their cost tags §5.14) and "profit"
## (earned − cost).
static func sell(state: Dictionary, data: Dictionary, resource_id: String, qty: int, now: float) -> Dictionary:
	var res_def: Dictionary = data.resources.get(resource_id, {})
	if res_def.is_empty():
		return _fail("Unknown item.")
	if qty <= 0:
		return _fail("Choose how many to sell.")
	if int(state.inventory.get(resource_id, 0)) < qty:
		return _fail("You don't have that many.")
	var gross := qty * unit_price(data, resource_id)
	var tax := sales_tax(state, data, gross, now)
	var earned := gross - tax
	# What the sold goods cost to make (their cost tags), so the sale can show the profit.
	var made_for := float(_take_cost(state.inventory, _costs(state, "inventory_cost"), {resource_id: qty}).get(resource_id, 0.0))
	_remove_from(state.inventory, {resource_id: qty})
	state.profile.currency += earned
	# Remember this sale for the 24-hour tax window, and forget sales that have left it.
	var window := float(data.config.get("sales_tax_window_hours", 24)) * 3600.0
	var log: Array = state.get("sales_log", [])
	while not log.is_empty() and float(log[0][0]) <= now - window:
		log.pop_front()
	log.append([now, gross])
	state["sales_log"] = log
	var s := stats(state)
	s.income.sales += gross
	s.spending["tax"] = int(s.spending.get("tax", 0)) + tax
	_add_to(s.sales_by_item, {resource_id: gross})
	_add_to(s.sold, {resource_id: qty})
	return _ok({"earned": earned, "gross": gross, "tax": tax, "rate": float(tax) / gross if gross > 0 else 0.0,
		"cost": roundi(made_for), "profit": earned - roundi(made_for)})


## Sales tax, in cents, on a sale worth `gross` cents (changes nothing). Progressive, like
## income-tax brackets, on the company's Retailer sales over the last sales_tax_window_hours (24):
## each part of the sale pays the rate of the bracket it falls in (first $5,000 0%, then 8%,
## 15%, 22%; "from" is in dollars in the config), so selling more never leaves you with less.
static func sales_tax(state: Dictionary, data: Dictionary, gross: int, now: float) -> int:
	var brackets: Array = data.config.get("sales_tax_brackets", [])
	var from := float(sales_last_day(state, data, now))
	var to := from + gross
	var tax := 0.0
	for i in brackets.size():
		var low := float(cents(float(brackets[i].from)))
		var high: float = float(cents(float(brackets[i + 1].from))) if i + 1 < brackets.size() else INF
		tax += maxf(minf(to, high) - maxf(from, low), 0.0) * float(brackets[i].rate)
	return roundi(tax)


## Retailer sales (before tax) over the tax window. Changes nothing (sell tidies the log).
static func sales_last_day(state: Dictionary, data: Dictionary, now: float) -> int:
	var window := float(data.config.get("sales_tax_window_hours", 24)) * 3600.0
	var total := 0
	for entry in state.get("sales_log", []):
		if float(entry[0]) > now - window and float(entry[0]) <= now:
			total += int(entry[1])
	return total


## The tax bracket the company's next sale starts in: {"sold" (last 24 h, cents), "rate",
## "next_at" (sales total in cents where the next bracket starts, or -1 at the top)}.
static func tax_bracket(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var sold := sales_last_day(state, data, now)
	var brackets: Array = data.config.get("sales_tax_brackets", [])
	var result := {"sold": sold, "rate": 0.0, "next_at": -1}
	for i in brackets.size():
		if sold >= cents(float(brackets[i].from)):
			result.rate = float(brackets[i].rate)
			result.next_at = cents(float(brackets[i + 1].from)) if i + 1 < brackets.size() else -1
	return result


# --- Prices (plan.md §5.12) ------------------------------------------------------

## Retail price of one unit, in cents, worked out live from what it costs to make (plan.md
## §5.12): for the building that makes it, at full staff, one batch costs its ingredients (at
## their own prices) + wages (max_workers at the minimum wage) + water (at the base price) + a
## share of the build cost (so it pays for itself in pricing.payback_hours of production);
## divided by the units made, then by (1 - pricing.typical_tax_rate) so a typical company keeps
## that after sales tax. Rounded to the cent. A resource with a fixed "price" (dollars) in
## resources.json uses that instead.
static func unit_price(data: Dictionary, resource_id: String) -> int:
	return _unit_price(data, resource_id, {})


static func _unit_price(data: Dictionary, resource_id: String, visiting: Dictionary) -> int:
	var res_def: Dictionary = data.resources.get(resource_id, {})
	if res_def.has("price"):
		return cents(float(res_def.price))
	if visiting.has(resource_id):
		return 0  # recipes that go round in a circle: stop instead of looping forever
	visiting[resource_id] = true
	var pricing: Dictionary = data.config.get("pricing", {})
	var payback := maxf(float(pricing.get("payback_hours", 12.0)), 0.01)
	var keep := 1.0 - clampf(float(pricing.get("typical_tax_rate", 0.0)), 0.0, 0.9)
	var price := 0
	for type_id in data.buildings:
		var def: Dictionary = data.buildings[type_id]
		for recipe in def.get("recipes", []):
			if not recipe.outputs.has(resource_id):
				continue
			var hours := float(recipe.duration) / 3600.0
			var cost := 0.0  # dollars per batch
			for input in recipe.get("inputs", {}):
				cost += int(recipe.inputs[input]) * _unit_price(data, input, visiting) / 100.0
			cost += int(def.get("max_workers", 0)) * _minimum_wage_of(data, def) * hours
			cost += float(def.get("water_per_hour", 0.0)) * hours * float(data.config.get("water", {}).get("price_per_m3", 0.0))
			cost += float(def.get("build_cost", 0)) / payback * hours
			price = cents(cost / maxf(_total(recipe.outputs), 1) / keep)
			visiting.erase(resource_id)
			return price
	visiting.erase(resource_id)
	return price  # nothing makes it and it has no fixed price: worthless


## The minimum wage per hour (dollars) for a building type's workers.
static func _minimum_wage_of(data: Dictionary, def: Dictionary) -> float:
	var type: String = def.get("worker_type", "low_skilled")
	return float(data.config.get("worker_types", {}).get(type, {}).get("wage_per_hour", 0.0))


## Dollars to whole cents ($5.30 -> 530).
static func cents(dollars: float) -> int:
	return roundi(dollars * 100.0)


# --- Developer tools (scenes/debug/, test builds only; plan.md §10) --------------
# They change cash directly (amounts in cents) and aren't counted as income or spending in
# the statistics.

static func dev_set_cash(state: Dictionary, amount: int) -> Dictionary:
	state.profile.currency = amount
	return _ok()


static func dev_add_cash(state: Dictionary, amount: int) -> Dictionary:
	state.profile.currency += amount
	return _ok()


# --- Questions the UI can ask -------------------------------------------------

static func find_building(state: Dictionary, building_id: String) -> Dictionary:
	for b in state.buildings:
		if b.id == building_id:
			return b
	return {}


static func building_at(state: Dictionary, cell: Vector2i) -> Dictionary:
	for b in state.buildings:
		if int(b.position[0]) == cell.x and int(b.position[1]) == cell.y:
			return b
	return {}


## Room for people in finished homes (homes still under construction don't count yet).
static func population_capacity(state: Dictionary, data: Dictionary, now: float) -> int:
	return _capacity(state, data, now, true)


## When the building is (or was) finished. Saves from before construction time existed have no
## "built_at", so those buildings count as finished long ago.
static func built_at(b: Dictionary) -> float:
	return float(b.get("built_at", 0.0))


static func is_built(b: Dictionary, now: float) -> bool:
	return now >= built_at(b)


## 0.0 to 1.0 progress of construction (1.0 = finished), for progress bars.
static func construction_progress(b: Dictionary, data: Dictionary, now: float) -> float:
	var build_time := float(data.buildings.get(b.type, {}).get("build_time", 0.0))
	if is_built(b, now) or build_time <= 0.0:
		return 1.0
	return clampf(1.0 - (built_at(b) - now) / build_time, 0.0, 1.0)


## Room in all warehouses together (one shared stock), as things stand at the last settle.
## Each finished, working warehouse holds its "capacity" times the share of its workers who are
## working (2 of 4 = half). Goods are never thrown away when room shrinks; nothing new comes in
## until there's room again.
static func warehouse_cap(state: Dictionary, data: Dictionary) -> int:
	var cap := 0
	for b in state.buildings:
		cap += storage_capacity(state, data, b)
	return cap


## The room this one building adds to the warehouse stock (0 for anything but a warehouse).
static func storage_capacity(state: Dictionary, data: Dictionary, b: Dictionary) -> int:
	var def: Dictionary = data.buildings.get(b.type, {})
	if def.get("category", "") != "storage":
		return 0
	var now := float(state.get("settled_at", 0.0))
	if not is_built(b, now) or is_suspended(b):
		return 0
	var full := int(def.get("capacity", 0))
	if max_workers(data, b) <= 0:
		return full
	return floori(full * workers_working(state, data, b, now) / float(max_workers(data, b)) + 0.000001)


static func warehouse_total(state: Dictionary) -> int:
	return _total(state.inventory)


## 0.0 to 1.0 progress of the current cycle/job, for progress bars. Time since the last settle
## counts at the building's current speed, so a short-staffed building's bar moves slower.
static func job_progress(state: Dictionary, b: Dictionary, data: Dictionary, now: float) -> float:
	var def: Dictionary = data.buildings.get(b.type, {})
	var recipe := {}
	if def.get("category", "") == "extractor":
		recipe = def.recipes[0]
	elif not b.queue.is_empty():
		recipe = _recipe(def, b.queue[0].recipe_id)
	if recipe.is_empty():
		return 0.0
	var started := float(b.job_started_at)
	var settled := float(state.get("settled_at", now))
	var worked := now - started
	if now > settled and started <= settled:
		worked = (settled - started) + (now - settled) * building_speed(state, data, b, now)
	return clampf(worked / float(recipe.duration), 0.0, 1.0)


## How fast a building works: workers actually working ÷ max_workers (6 of 8 = 0.75).
## Buildings without workers (homes, the office) always work at full speed.
static func building_speed(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	var most := max_workers(data, b)
	if most <= 0:
		return 1.0
	return workers_working(state, data, b, now) / float(most)


## The most workers this building can employ (at its level; level 1 for now).
static func max_workers(data: Dictionary, b: Dictionary) -> int:
	return int(data.buildings.get(b.type, {}).get("max_workers", 0))


## The building's chosen staffing level: "low", "medium" or "high".
static func staffing_level(data: Dictionary, b: Dictionary) -> String:
	return str(b.get("staffing", data.config.get("default_staffing", "high")))


## How many workers the building asks for at its staffing level (Low 4 / Medium 6 / High 8 of 8).
## Buildings with "fixed_workers" (warehouses) have no choice: they always ask for all of them.
static func workers_wanted(data: Dictionary, b: Dictionary) -> int:
	if has_fixed_workers(data, b):
		return max_workers(data, b)
	var levels: Dictionary = data.config.get("staffing_levels", DEFAULT_STAFFING_LEVELS)
	return roundi(max_workers(data, b) * float(levels.get(staffing_level(data, b), 1.0)))


## True when the player can't choose Low / Medium / High here: the number of workers is set by
## the building (and later by its level: upgrading a warehouse to level 2 doubles them).
static func has_fixed_workers(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("fixed_workers", false))


## How many people are working there right now: its hired workers (always a whole number) while
## it's producing; 0 while it's still being built or isn't producing (halted, idle, suspended).
## Halted and idle buildings keep their workers (tied, unpaid) until they restart.
static func workers_working(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	if not is_built(b, now) or not is_producing(data, b):
		return 0.0
	return float(hired(b))


## Workers tied to this building (hired, whether working right now or waiting unpaid).
static func hired(b: Dictionary) -> int:
	return int(b.get("hired", 0))


## Posts the building offers: what its staffing level asks for, once built and while not
## suspended. Halted or idle buildings keep offering them.
static func posts(data: Dictionary, b: Dictionary, now: float) -> int:
	if not is_built(b, now) or is_suspended(b):
		return 0
	return workers_wanted(data, b)


## Hands out free people (plan.md §5.6 "Hiring & wage bonuses"). Workers are tied to their
## building, so only free people move: warehouses ("staffed_first") are filled before anything
## else; then each takes an open post at the building with the biggest wage bonus; with equal
## bonuses they take turns, the emptiest building first (fewest hired for what it asked for),
## then the older one. With more workers than people (a home was demolished) workers leave the
## buildings with the smallest bonus first, the newest building first, and warehouses last.
static func _hire(state: Dictionary, data: Dictionary, now: float) -> void:
	var free := int(state.population.current)
	for b in state.buildings:
		b["hired"] = mini(hired(b), posts(data, b, now))  # e.g. staffing was lowered: the rest are freed
		free -= hired(b)
	while free < 0:
		var leave := -1
		for i in state.buildings.size():
			var b: Dictionary = state.buildings[i]
			if hired(b) > 0 and (leave < 0 or _leaves_before(data, b, state.buildings[leave])):
				leave = i
		state.buildings[leave]["hired"] = hired(state.buildings[leave]) - 1
		free += 1
	while free > 0:
		var best := -1
		for i in state.buildings.size():
			var b: Dictionary = state.buildings[i]
			if hired(b) < posts(data, b, now) and (best < 0 or _hires_before(data, b, state.buildings[best], now)):
				best = i
		if best < 0:
			return  # every post is filled: the rest stay unemployed
		state.buildings[best]["hired"] = hired(state.buildings[best]) + 1
		free -= 1


## Whether building `a` gets the next free worker before `b` (both have an open post): buildings
## that are "staffed_first" (warehouses) before all others, then the bigger bonus, then the
## emptier one (compared without decimals: a.hired / a.posts < b.hired / b.posts). Equal on all:
## the one found first, i.e. the older building.
static func _hires_before(data: Dictionary, a: Dictionary, b: Dictionary, now: float) -> bool:
	if is_staffed_first(data, a) != is_staffed_first(data, b):
		return is_staffed_first(data, a)
	var rate_a := bonus_rate(data, a)
	var rate_b := bonus_rate(data, b)
	if not is_equal_approx(rate_a, rate_b):
		return rate_a > rate_b
	return hired(a) * posts(data, b, now) < hired(b) * posts(data, a, now)


## With fewer people than workers: whether a worker at `a` leaves before one at `b` (`b` was
## found earlier, so it's the older one). "staffed_first" buildings lose workers last; then the
## smaller bonus goes first; equal: the newer building (`a`) goes first.
static func _leaves_before(data: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	if is_staffed_first(data, a) != is_staffed_first(data, b):
		return not is_staffed_first(data, a)
	return bonus_rate(data, a) <= bonus_rate(data, b)


## Gets free workers before every other building and loses them last (warehouses: their room
## must not vanish just because other buildings pay more). "staffed_first" in buildings.json.
static func is_staffed_first(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("staffed_first", false))


## Producing: has work to do and room for it, and isn't suspended. Workers are only hired (and
## paid), and from Phase 2/3 power only used, while a building is producing (plan.md §5.5, §5.6).
## Warehouses count as always producing (storing) unless suspended: their workers make the room.
static func is_producing(data: Dictionary, b: Dictionary) -> bool:
	return not is_suspended(b) and not is_halted(data, b) and not is_idle(data, b)


## Suspended by the player: switched off, no workers, no wages, no power (plan.md §5.10).
static func is_suspended(b: Dictionary) -> bool:
	return bool(b.get("suspended", false))


## Idle: a Mill or Bakery with no jobs queued. Like a halted building, it pays no wages; its
## workers stay tied to it, waiting unpaid for the next job.
static func is_idle(data: Dictionary, b: Dictionary) -> bool:
	return data.buildings.get(b.type, {}).get("category", "") == "processor" and b.queue.is_empty()


## Halted: its storage is full (a farm with no room for the next batch, or a finished batch
## waiting for room), so it makes nothing until the player collects. It pays no wages; its
## workers stay tied to it, waiting unpaid.
static func is_halted(data: Dictionary, b: Dictionary) -> bool:
	var def: Dictionary = data.buildings.get(b.type, {})
	match def.get("category", ""):
		"extractor":
			return int(def.storage_cap) - _total(b.storage) < _total(def.recipes[0].outputs)
		"processor":
			return bool(b.blocked)
	return false


## When a producing building will stop if nothing changes, at its current speed: its storage
## fills (halted) or its last queued job is done (idle). INF if it won't. Settling splits time at
## this moment so wages stop exactly then, even while the player is away.
static func _stop_time(state: Dictionary, data: Dictionary, b: Dictionary, t: float) -> float:
	var def: Dictionary = data.buildings.get(b.type, {})
	if max_workers(data, b) <= 0 or not is_built(b, t) or not is_producing(data, b) or float(b.job_started_at) > t:
		return INF
	if def.get("category", "") not in ["extractor", "processor"]:
		return INF  # a warehouse never stops by itself
	var speed := building_speed(state, data, b, t)
	if speed <= 0.0:
		return INF
	var space := int(def.get("storage_cap", 0)) - _total(b.storage)
	var done := t - float(b.job_started_at)  # work already done on the current cycle / job
	if def.get("category", "") == "extractor":
		var recipe: Dictionary = def.recipes[0]
		var fits := floori(float(space) / _total(recipe.outputs))
		return t + (fits * float(recipe.duration) - done) / speed + 0.000001
	var work := -done
	for job in b.queue:
		var recipe := _recipe(def, job.recipe_id)
		work += float(recipe.get("duration", 0.0))
		var out := _total(recipe.get("outputs", {}))
		if space < out:
			return t + work / speed + 0.000001  # this batch finishes with nowhere to go
		space -= out
	return t + work / speed + 0.000001  # the last job is done: idle from then on


## Wage per hour (dollars) for one worker here: the minimum wage for its worker type (game_config.json
## worker_types, set by the game) plus the building's bonus (None 0% / Small 20% / ...).
static func wage_per_worker(data: Dictionary, b: Dictionary) -> float:
	return minimum_wage(data, b) * (1.0 + bonus_rate(data, b))


## The minimum wage per hour (dollars) for this building's worker type, before any bonus.
static func minimum_wage(data: Dictionary, b: Dictionary) -> float:
	return _minimum_wage_of(data, data.buildings.get(b.type, {}))


## The building's chosen wage bonus: "none", "small", "good" or "big" (wage_bonuses in config).
## Always "none" for "fixed_wage" buildings (warehouses), whatever an older save says.
static func bonus_level(data: Dictionary, b: Dictionary) -> String:
	if has_fixed_wage(data, b):
		return "none"
	return str(b.get("bonus", data.config.get("default_bonus", "none")))


## Its bonus as a share of the minimum wage (0.4 = +40%).
static func bonus_rate(data: Dictionary, b: Dictionary) -> float:
	return float(data.config.get("wage_bonuses", {}).get(bonus_level(data, b), 0.0))


## True when the building always pays the minimum wage: no bonus choice ("fixed_wage" in
## buildings.json; warehouses, which are staffed first anyway).
static func has_fixed_wage(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("fixed_wage", false))


## What the building's workers cost per hour right now (dollars).
static func building_wages(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	return workers_working(state, data, b, now) * wage_per_worker(data, b)


## What all workers in town cost per hour right now (dollars).
static func _wages_per_hour(state: Dictionary, data: Dictionary, now: float) -> float:
	var total := 0.0
	for b in state.buildings:
		total += building_wages(state, data, b, now)
	return total


# --- Water (plan.md §5.13) ------------------------------------------------------
# The government's public water supply: unlimited, so it never slows a building down. A meter
# records what the company draws (and what it cost at the price of the moment); every
# water.billing_hours (12) the bill is charged at once, heavy users paying more for the part of
# the cycle's m³ above each tier. Unpaid bills simply take cash below 0 (debt).

## m³ of water per hour this building draws right now: its water_per_hour while producing, times
## its speed (6 of 8 workers = 75% of it). 0 while built, halted, idle or suspended.
static func water_use(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	var per_hour := float(data.buildings.get(b.type, {}).get("water_per_hour", 0.0))
	if per_hour <= 0.0 or not is_built(b, now) or not is_producing(data, b):
		return 0.0
	return per_hour * building_speed(state, data, b, now)


## The whole company's water use right now, m³ per hour.
static func water_use_total(state: Dictionary, data: Dictionary, now: float) -> float:
	var total := 0.0
	for b in state.buildings:
		total += water_use(state, data, b, now)
	return total


## The water meter: {"m3" (drawn this cycle), "base_cost" (dollars, each m³ at the price when it
## was drawn), "cycle_start" (when this billing cycle began)}. Older saves get one starting `now`.
static func water_meter(state: Dictionary, now: float) -> Dictionary:
	if not state.has("water_meter"):
		state["water_meter"] = {"m3": 0.0, "base_cost": 0.0, "cycle_start": now}
	return state.water_meter


## Seconds in one billing cycle (water.billing_hours, 12 = one game day).
static func billing_seconds(data: Dictionary) -> float:
	return maxf(float(data.config.get("water", {}).get("billing_hours", 12.0)), 0.02) * 3600.0


## When the current water bill falls due (a fixed moment: cycle start + one cycle).
static func water_bill_due_at(state: Dictionary, data: Dictionary, now: float) -> float:
	return float(water_meter(state, now).cycle_start) + billing_seconds(data)


## The base price per m³ (dollars) right now. Later it can drift (market mood).
static func water_price(data: Dictionary) -> float:
	return float(data.config.get("water", {}).get("price_per_m3", 0.0))


## Records `m3` drawn, at the price of the moment.
static func _meter_water(state: Dictionary, data: Dictionary, m3: float, now: float) -> void:
	if m3 <= 0.0:
		return
	var meter := water_meter(state, now)
	meter.m3 = float(meter.m3) + m3
	meter.base_cost = float(meter.base_cost) + m3 * water_price(data)


## A cycle's bill (dollars) for `m3` that cost `base_cost` at the base price: plus each tier's
## extra on the part of the m³ above where that tier starts (first 1,200 m³ normal, above +25%).
static func water_bill_cost(data: Dictionary, m3: float, base_cost: float) -> float:
	if m3 <= 0.0:
		return 0.0
	var average_price := base_cost / m3
	var cost := 0.0
	var tiers: Array = data.config.get("water", {}).get("tiers", [{"from": 0, "extra": 0.0}])
	for i in tiers.size():
		var low := float(tiers[i].from)
		var high: float = float(tiers[i + 1].from) if i + 1 < tiers.size() else INF
		cost += maxf(minf(m3, high) - low, 0.0) * average_price * (1.0 + float(tiers[i].extra))
	return cost


## The bill so far this cycle: {"m3", "cost" (cents), "due_at"}. Changes nothing.
static func water_bill_so_far(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var meter := water_meter(state, now)
	return {"m3": float(meter.m3), "cost": cents(water_bill_cost(data, float(meter.m3), float(meter.base_cost))),
		"due_at": water_bill_due_at(state, data, now)}


## If the bill is due at `now`, charges it all at once (into debt if need be), keeps it in the
## bill history and starts the next cycle at the fixed moment it was due. Returns cents charged.
static func _bill_water_if_due(state: Dictionary, data: Dictionary, now: float) -> int:
	var charged := 0
	while now >= water_bill_due_at(state, data, now) - 0.000001:
		var meter := water_meter(state, now)
		var due := water_bill_due_at(state, data, now)
		var amount := cents(water_bill_cost(data, float(meter.m3), float(meter.base_cost)))
		if amount > 0:
			state.profile.currency -= amount
			var spending: Dictionary = stats(state).spending
			spending["water"] = int(spending.get("water", 0)) + amount
			var bills: Array = state.get("water_bills", [])
			bills.append({"t": due, "m3": float(meter.m3), "cost": amount})
			while bills.size() > int(data.config.get("water", {}).get("bill_history", 10)):
				bills.pop_front()
			state["water_bills"] = bills
			charged += amount
		state["water_meter"] = {"m3": 0.0, "base_cost": 0.0, "cycle_start": due}
	return charged


# --- Cost tags and cost per unit (plan.md §5.14) ----------------------------------
# Every stock carries its total cost in cents next to its amount: the warehouse in
# state.inventory_cost, a building's storage in b.storage_cost, a queued batch's ingredients in
# its queue entry ("input_cost"). Average cost = total cost ÷ amount, so mixing averages it.
# Moving goods moves their share of the cost with them. Missing tags count as 0 (older saves get
# standard tags when loaded, save_format.gd).

## The cost dictionary `key` of `holder` (made empty on first use).
static func _costs(holder: Dictionary, key: String) -> Dictionary:
	if not holder.has(key):
		holder[key] = {}
	return holder[key]


## Average cost per unit (cents) of what's in the warehouse; 0 when there's none.
static func average_cost(state: Dictionary, resource_id: String) -> float:
	var qty := int(state.inventory.get(resource_id, 0))
	if qty <= 0:
		return 0.0
	return float(_costs(state, "inventory_cost").get(resource_id, 0.0)) / qty


## Removes the cost of `items` from `costs` (the stock's tags; call BEFORE the goods leave
## `stock`): each takes its share of its stock's total. Returns {resource: cents taken}.
static func _take_cost(stock: Dictionary, costs: Dictionary, items: Dictionary) -> Dictionary:
	var taken := {}
	for res in items:
		var have := int(stock.get(res, 0))
		var qty := mini(int(items[res]), have)
		if have <= 0 or qty <= 0:
			continue
		var share := float(costs.get(res, 0.0)) * qty / have
		taken[res] = share
		if qty >= have:
			costs.erase(res)
		else:
			costs[res] = float(costs.get(res, 0.0)) - share
	return taken


## Adds cents to a stock's cost tags: {resource: cents}.
static func _put_cost(costs: Dictionary, amounts: Dictionary) -> void:
	for res in amounts:
		costs[res] = float(costs.get(res, 0.0)) + float(amounts[res])


## Spreads `cents` over `outputs` by quantity: {resource: cents}.
static func _spread_cost(outputs: Dictionary, cents_total: float) -> Dictionary:
	var units := _total(outputs)
	var out := {}
	for res in outputs:
		out[res] = cents_total * int(outputs[res]) / maxf(units, 1)
	return out


## What running one batch of `recipe` costs here right now, in cents: {"wages", "water"}.
## Wages = max_workers × wage per worker (minimum + bonus) × batch time: the same whatever the
## staffing, since fewer workers simply take longer. Water = water_per_hour × batch time × the
## price per m³ right now.
static func batch_running_cost(state: Dictionary, data: Dictionary, b: Dictionary, recipe: Dictionary) -> Dictionary:
	var def: Dictionary = data.buildings.get(b.type, {})
	var hours := float(recipe.get("duration", 0.0)) / 3600.0
	var wages := max_workers(data, b) * wage_per_worker(data, b) * hours
	var water := float(def.get("water_per_hour", 0.0)) * hours * water_unit_price(state, data)
	return {"wages": wages * 100.0, "water": water * 100.0}


## The price of the next m³ (dollars): the base price, plus the extra of the tier this cycle's
## use has reached (+25% once past 1,200 m³).
static func water_unit_price(state: Dictionary, data: Dictionary) -> float:
	var used := float(state.get("water_meter", {}).get("m3", 0.0))
	var extra := 0.0
	for tier in data.config.get("water", {}).get("tiers", []):
		if used >= float(tier.from):
			extra = float(tier.extra)
	return water_price(data) * (1.0 + extra)


## What making one unit costs with standard numbers (cents): ingredients at their standard cost,
## a full crew at the minimum wage, water at the base price; no building share, no tax. Used for
## cost tags of older saves, and as the estimate when an ingredient isn't in stock. A resource
## with a fixed "price" costs that price (it's bought).
static func standard_unit_cost(data: Dictionary, resource_id: String) -> float:
	return _standard_unit_cost(data, resource_id, {})


static func _standard_unit_cost(data: Dictionary, resource_id: String, visiting: Dictionary) -> float:
	var res_def: Dictionary = data.resources.get(resource_id, {})
	if res_def.has("price"):
		return float(cents(float(res_def.price)))
	if visiting.has(resource_id):
		return 0.0
	visiting[resource_id] = true
	for type_id in data.buildings:
		var def: Dictionary = data.buildings[type_id]
		for recipe in def.get("recipes", []):
			if not recipe.outputs.has(resource_id):
				continue
			var hours := float(recipe.duration) / 3600.0
			var cost := 0.0  # cents per batch
			for input in recipe.get("inputs", {}):
				cost += int(recipe.inputs[input]) * _standard_unit_cost(data, input, visiting)
			cost += int(def.get("max_workers", 0)) * _minimum_wage_of(data, def) * hours * 100.0
			cost += float(def.get("water_per_hour", 0.0)) * hours * water_price(data) * 100.0
			visiting.erase(resource_id)
			return cost / maxf(_total(recipe.outputs), 1)
	visiting.erase(resource_id)
	return 0.0


## The cost tags of what a job gives back when stopped (cancel, demolish, suspend): each
## ingredient's share of what it cost when the job was queued. `refund` = {resource: qty back}.
static func _refund_cost(job: Dictionary, recipe: Dictionary, refund: Dictionary) -> Dictionary:
	var paid: Dictionary = job.get("input_cost", {})
	var out := {}
	for res in refund:
		var put_in := int(recipe.get("inputs", {}).get(res, 0))
		if put_in > 0:
			out[res] = float(paid.get(res, 0.0)) * int(refund[res]) / put_in
	return out


## Cost per unit of what this building makes, right now, for its window (plan.md §5.14), in
## cents: {"output", "units", "ingredients": [{"res", "qty", "each", "per_unit"}], "wages",
## "water", "total" (all per unit), "price" (selling price), "estimated" (an ingredient isn't in
## stock, so its standard cost was used), "workers", "wage_each" (dollars/h), "minutes",
## "inputs_value", "batch_value", "making_earns" (per batch: what making it adds over selling the
## ingredients)}. {} for buildings that make nothing.
static func cost_breakdown(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> Dictionary:
	var def: Dictionary = data.buildings.get(b.type, {})
	var recipes: Array = def.get("recipes", [])
	if recipes.is_empty():
		return {}
	var recipe: Dictionary = recipes[0]
	if not b.get("queue", []).is_empty() and not _recipe(def, b.queue[0].recipe_id).is_empty():
		recipe = _recipe(def, b.queue[0].recipe_id)
	var units := maxf(_total(recipe.outputs), 1)
	var running := batch_running_cost(state, data, b, recipe)
	var result := {"output": recipe.outputs.keys()[0], "units": int(units), "ingredients": [],
		"wages": float(running.wages) / units, "water": float(running.water) / units,
		"estimated": false, "workers": max_workers(data, b), "wage_each": wage_per_worker(data, b),
		"minutes": float(recipe.duration) / 60.0}
	var total := float(result.wages) + float(result.water)
	var inputs_value := 0
	for res in recipe.get("inputs", {}):
		var qty := int(recipe.inputs[res])
		var each := 0.0
		var job_cost: Dictionary = b.queue[0].get("input_cost", {}) if not b.get("queue", []).is_empty() else {}
		if job_cost.has(res):
			each = float(job_cost[res]) / qty  # the batch being made: what its ingredients cost
		elif int(state.inventory.get(res, 0)) > 0:
			each = average_cost(state, res)  # the next batch would use these
		else:
			each = standard_unit_cost(data, res)
			result.estimated = true
		result.ingredients.append({"res": res, "qty": qty / units, "each": each, "per_unit": each * qty / units})
		total += each * qty / units
		inputs_value += qty * unit_price(data, res)
	result["total"] = total
	result["price"] = unit_price(data, result.output)
	result["inputs_value"] = inputs_value
	result["batch_value"] = int(units) * int(result.price)
	result["making_earns"] = float(result.batch_value) - inputs_value - float(running.wages) - float(running.water)
	return result


# --- Statistics ---------------------------------------------------------------
# Lifetime counters live in state.stats and are updated by the actions above; rates and
# employment are worked out from the buildings on the spot, so they never go stale.

## The statistics counters. Saves from before statistics existed get empty ones.
static func stats(state: Dictionary) -> Dictionary:
	if not state.has("stats"):
		state["stats"] = _new_stats()
	return state.stats


## How much each item is being made and used per minute right now, counting only buildings that
## are actually working, plus how many production buildings are in each state:
## {"made": {res: per_min}, "used": {res: per_min},
##  "buildings": {"working", "idle" (empty queue), "full" (storage full), "building" (under construction),
##   "suspended"}}
static func production_rates(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var made := {}
	var used := {}
	var counts := {"working": 0, "idle": 0, "full": 0, "building": 0, "suspended": 0}
	for b in state.buildings:
		var def: Dictionary = data.buildings.get(b.type, {})
		var category: String = def.get("category", "")
		if category not in ["extractor", "processor"]:
			continue
		if not is_built(b, now):
			counts.building += 1
			continue
		if is_suspended(b):
			counts.suspended += 1
			continue
		var recipe := {}
		if category == "extractor":
			recipe = def.recipes[0]
			if int(def.storage_cap) - _total(b.storage) < _total(recipe.outputs):
				counts.full += 1
				continue
		elif b.blocked:
			counts.full += 1
			continue
		elif b.queue.is_empty():
			counts.idle += 1
			continue
		else:
			recipe = _recipe(def, b.queue[0].recipe_id)
		counts.working += 1
		var per_minute := 60.0 / float(recipe.duration) * building_speed(state, data, b, now)
		for res in recipe.outputs:
			made[res] = float(made.get(res, 0.0)) + int(recipe.outputs[res]) * per_minute
		for res in recipe.get("inputs", {}):
			used[res] = float(used.get(res, 0.0)) + int(recipe.inputs[res]) * per_minute
	return {"made": made, "used": used, "buildings": counts}


## Share of the town's posts that are filled, 0.0 to 1.0 (1.0 when every post is filled or there
## are none). Below 1 the town is short of people: some buildings have open posts.
static func staffing(state: Dictionary, data: Dictionary, now: float) -> float:
	var e := employment(state, data, now)
	if e.jobs <= 0:
		return 1.0
	return float(e.employed) / float(e.jobs)


## Jobs = posts at finished, non-suspended buildings; employed = workers hired into them (whole
## people, tied to their building). {"population", "jobs", "employed", "unemployed", "open_jobs"}
static func employment(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var jobs := 0
	var employed := 0
	for b in state.buildings:
		jobs += posts(data, b, now)
		employed += mini(hired(b), posts(data, b, now))
	var people := int(state.population.current)
	employed = mini(employed, people)
	return {"population": people, "jobs": jobs, "employed": employed, "unemployed": people - employed, "open_jobs": jobs - employed}


## Money in and out over at least the last `window` seconds (or since the first history point),
## counted from the newest point at or before the window's start:
## {"income", "spending", "seconds" (how much time that really covers; 0 = no history yet)}.
## Time away is a single history point, so after 4 hours away this covers those 4 hours.
static func cash_flow(state: Dictionary, window: float, now: float) -> Dictionary:
	var s := stats(state)
	var from := {}
	for point in s.history:
		if float(point.t) <= now - window or from.is_empty():
			from = point
	if from.is_empty():
		return {"income": 0, "spending": 0, "seconds": 0.0}
	return {
		"income": _total(s.income) - int(from.income),
		"spending": _total(s.spending) - int(from.spending),
		"seconds": maxf(now - float(from.t), 0.0),
	}


## Adds a point to the graphs' history if config.stats_sample_seconds have passed since the
## last one. Time spent away becomes a single point, not one per minute.
static func _record_history(state: Dictionary, data: Dictionary, now: float) -> void:
	var s := stats(state)
	var history: Array = s.history
	var every := float(data.config.get("stats_sample_seconds", 60))
	if not history.is_empty() and now < float(history[-1].t) + every:
		return  # too soon (also covers a clock that moved backwards)
	var e := employment(state, data, now)
	history.append({
		"t": now,
		"cash": int(state.profile.currency),
		"income": _total(s.income),
		"spending": _total(s.spending),
		"population": e.population,
		"employed": e.employed,
		"jobs": e.jobs,
		"made": s.made.duplicate(),
	})
	var keep := int(data.config.get("stats_history_size", 360))
	while history.size() > keep:
		history.pop_front()


static func _new_stats() -> Dictionary:
	return {
		"income": {"sales": 0, "demolish": 0},  # money in (cents), by where it came from
		"spending": {"construction": 0, "wages": 0, "water": 0, "tax": 0},  # money out (cents), by what it went on
		"sales_by_item": {},  # resource -> cents earned selling it
		"made": {},  # resource -> amount ever produced
		"sold": {},  # resource -> amount ever sold
		"history": [],  # graph points: {t, cash, income, spending, population, employed, jobs, made}
	}


# --- Helpers ------------------------------------------------------------------

## `finished_at` = when construction ends. Until then the building makes nothing and takes no orders.
static func _add_building(state: Dictionary, type_id: String, cell: Vector2i, now: float, finished_at: float) -> Dictionary:
	var b := {
		"id": "b%d" % int(state.next_building_id),
		"type": type_id,
		"level": 1,
		"position": [cell.x, cell.y],
		"built_at": finished_at,
		"storage": {},
		"queue": [],  # [{recipe_id}], first entry is the job being worked on
		# Start of the current cycle (extractor) or job (processor). For a new extractor that's the
		# moment construction ends: settling waits until then, so nothing grows while it's being built.
		"job_started_at": maxf(now, finished_at),
		"blocked": false,  # processor: finished job is waiting for storage space
		"hired": 0,  # workers tied to it (whole people, see _hire)
	}
	state.next_building_id = int(state.next_building_id) + 1
	state.buildings.append(b)
	return b


## Population room from homes finished by time t. inclusive = false leaves out homes finishing
## exactly at t (the cap that applied just before that moment).
static func _capacity(state: Dictionary, data: Dictionary, t: float, inclusive: bool) -> int:
	var cap := 0
	for b in state.buildings:
		if built_at(b) < t or (inclusive and built_at(b) == t):
			cap += int(data.buildings.get(b.type, {}).get("population_capacity", 0))
	return cap


static func _in_plot(state: Dictionary, cell: Vector2i) -> bool:
	var grid: Array = state.plot.grid_size
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(grid[0]) and cell.y < int(grid[1])


static func _recipe(def: Dictionary, recipe_id: String) -> Dictionary:
	for r in def.get("recipes", []):
		if r.id == recipe_id:
			return r
	return {}


static func _resource_name(data: Dictionary, resource_id: String) -> String:
	return str(data.resources.get(resource_id, {}).get("name", resource_id))


static func _total(amounts: Dictionary) -> int:
	var sum := 0
	for k in amounts:
		sum += int(amounts[k])
	return sum


static func _scaled(amounts: Dictionary, times: int) -> Dictionary:
	var out := {}
	if times <= 0:
		return out
	for k in amounts:
		out[k] = int(amounts[k]) * times
	return out


## Each amount times `fraction`, rounded down; amounts that round to 0 are left out.
static func _share(amounts: Dictionary, fraction: float) -> Dictionary:
	var out := {}
	for k in amounts:
		var qty := floori(int(amounts[k]) * fraction)
		if qty > 0:
			out[k] = qty
	return out


static func _add_to(target: Dictionary, amounts: Dictionary) -> void:
	for k in amounts:
		target[k] = int(target.get(k, 0)) + int(amounts[k])


static func _remove_from(target: Dictionary, amounts: Dictionary) -> void:
	for k in amounts:
		var left := int(target.get(k, 0)) - int(amounts[k])
		if left > 0:
			target[k] = left
		else:
			target.erase(k)


static func _ok(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "error": ""}
	result.merge(extra)
	return result


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message}
