extends RefCounted
## Pure Phase 1a game rules (plan.md §5). No nodes, no clock, no files:
## every function is handed the game state, the content data and "now".
## Keeping it pure makes it testable, and it's the part a Phase 4 server would port (plan.md §3.1).
##
## `data`  = { "resources": {...}, "buildings": {...}, "config": {...} } from data/*.json
## `state` = the player's save, shaped like plan.md §8.
## Player actions return { "ok": bool, "error": String, ...extra }.
##
## Time model: buildings store when their current cycle/job started (`job_started_at`).
## "Settling" turns elapsed time into finished output in one calculation, never tick-by-tick.

const SAVE_VERSION := 1


# --- New game -----------------------------------------------------------------

static func new_game(data: Dictionary, now: float) -> Dictionary:
	var config: Dictionary = data.config
	var state := {
		"save_version": SAVE_VERSION,
		"last_saved_at": now,
		"profile": {"currency": int(config.starting_cash)},
		"plot": {"grid_size": [int(config.grid_size[0]), int(config.grid_size[1])]},
		"next_building_id": 1,
		"buildings": [],
		"inventory": {},  # the Warehouse
		"population": {"current": 0, "growth_anchor": now},
		"settled_at": now,  # everything has been worked out up to this moment
		"stats": _new_stats(),
	}
	for entry in config.starting_buildings:
		# Starting buildings are already standing: no construction time.
		_add_building(state, entry.type, Vector2i(int(entry.position[0]), int(entry.position[1])), now, 0.0)
	return state


# --- Settling time ------------------------------------------------------------

## Brings every building and the population up to `now`.
## Returns everything produced, e.g. {"wheat": 30, "population": 2} (for the offline summary).
##
## Buildings short of workers run slower (see staffing). Staffing only changes at a few moments
## (a person moves in, a building finishes), so the time since the last settle is split at those
## moments and each piece is worked out in one go at a fixed speed. That's a handful of steps
## however long the player was away, never a minute-by-minute replay.
static func settle(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var report := {}
	var grown := 0
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
			var next := _next_staffing_change(state, data, t, now)
			var speed := staffing(state, data, t)
			for b in state.buildings:
				_add_to(report, _settle_span(state, b, data, t, next, speed))
			grown += _grow_population(state, data, next)
			t = next
		state["settled_at"] = now
	if grown > 0:
		report["population"] = grown
	_record_history(state, data, now)
	return report


## Settles one building over [t0, t1] while it works at `speed` (1 = fully staffed). A building
## at 70% speed gets 70% of the time's work: it is settled up to t0 + 0.7 x (t1 - t0), then its
## current job's start is moved later by the other 30%, so at t1 it is exactly as far along as
## that work allows.
static func _settle_span(state: Dictionary, b: Dictionary, data: Dictionary, t0: float, t1: float, speed: float) -> Dictionary:
	var needs_workers := int(data.buildings.get(b.type, {}).get("workers", 0)) > 0
	if not needs_workers or speed >= 1.0 or float(b.job_started_at) > t0:
		return _settle_one(state, b, data, t1)  # full speed (or not started yet, e.g. being built)
	var span := t1 - t0
	var produced := _settle_one(state, b, data, t0 + speed * span)
	b.job_started_at = float(b.job_started_at) + span * (1.0 - speed)
	return produced


## The first moment after t (and before `until`) when staffing can change: a building finishing
## construction (new jobs or new homes), or, while short of workers, the next person moving in.
static func _next_staffing_change(state: Dictionary, data: Dictionary, t: float, until: float) -> float:
	var next := until
	for b in state.buildings:
		var finish := built_at(b)
		if finish > t and finish < next:
			next = finish
	var pop: Dictionary = state.population
	var step := float(data.config.population_growth_seconds)
	var e := employment(state, data, t)
	if step > 0.0 and e.jobs > e.population and int(pop.current) < population_capacity(state, data, t):
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
	var produced := settle_building(b, data, now)
	_add_to(stats(state).made, produced)
	return produced


static func settle_building(b: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var def: Dictionary = data.buildings.get(b.type, {})
	match def.get("category", ""):
		"extractor":
			return _settle_extractor(b, def, now)
		"processor":
			return _settle_processor(b, def, now)
	return {}


## Extractors (Wheat Farm) produce on their own, one batch per cycle, until storage is full.
static func _settle_extractor(b: Dictionary, def: Dictionary, now: float) -> Dictionary:
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
	if cycles >= fits:
		b.job_started_at = now  # it filled up somewhere in that time; restart once collected
	else:
		b.job_started_at += done * duration
	return produced


## Processors (Mill, Bakery) work through their job queue one job at a time.
## A finished job waits ("blocked") if the building's storage has no room for its output.
static func _settle_processor(b: Dictionary, def: Dictionary, now: float) -> Dictionary:
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
	if state.profile.currency < int(def.build_cost):
		return _fail("Not enough money.")
	return _ok({})


static func build(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i, now: float) -> Dictionary:
	var check := can_build(state, data, type_id, cell)
	if not check.ok:
		return check
	settle(state, data, now)  # time so far was worked with the old staffing
	var def: Dictionary = data.buildings[type_id]
	state.profile.currency -= int(def.build_cost)
	stats(state).spending.construction += int(def.build_cost)
	var b := _add_building(state, type_id, cell, now, now + float(def.get("build_time", 0.0)))
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
	_remove_from(state.inventory, recipe.inputs)
	if b.queue.is_empty():
		b.job_started_at = now
		b.blocked = false
	b.queue.append({"recipe_id": recipe_id})
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
	var free := warehouse_cap(data) - warehouse_total(state)
	var moved := {}
	for res in b.storage:
		var qty := mini(int(b.storage[res]), free)
		if qty > 0:
			moved[res] = qty
			free -= qty
	if moved.is_empty():
		return _fail("The warehouse is full.")
	_remove_from(b.storage, moved)
	_add_to(state.inventory, moved)
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
	if warehouse_total(state) + _total(refund) > warehouse_cap(data):
		return _fail("Not enough room in the warehouse for the refund.")
	return _ok({"refund": refund, "in_progress": index == 0})


static func cancel_job(state: Dictionary, data: Dictionary, building_id: String, index: int, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # the job may have just finished
	var check := can_cancel_job(state, data, building_id, index)
	if not check.ok:
		return check
	b.queue.remove_at(index)
	_add_to(state.inventory, check.refund)
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
	var goods: Dictionary = b.storage.duplicate()
	for i in b.queue.size():
		if i == 0 and b.blocked:
			_add_to(goods, _recipe(def, b.queue[0].recipe_id).get("outputs", {}))  # finished, so it's yours
			continue
		var key := "cancel_refund_in_progress" if i == 0 else "cancel_refund_waiting"
		_add_to(goods, _share(_recipe(def, b.queue[i].recipe_id).get("inputs", {}), float(data.config.get(key, 0.0))))
	if warehouse_total(state) + _total(goods) > warehouse_cap(data):
		return _fail("Not enough room in the warehouse for what's inside. Make room first.")
	var money := int(int(def.get("build_cost", 0)) * float(data.config.get("demolish_refund", 0.0)))
	return _ok({"money": money, "goods": goods})


static func demolish(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)
	var check := can_demolish(state, data, building_id)
	if not check.ok:
		return check
	state.buildings.erase(b)
	state.profile.currency += int(check.money)
	stats(state).income.demolish += int(check.money)
	_add_to(state.inventory, check.goods)
	# Fewer homes can mean less room: people over the new capacity move away.
	var cap := population_capacity(state, data, now)
	if state.population.current > cap:
		state.population.current = cap
	return check


## Sell to the NPC Retailer at its fixed price (plan.md §5.2 channel 1).
static func sell(state: Dictionary, data: Dictionary, resource_id: String, qty: int) -> Dictionary:
	var res_def: Dictionary = data.resources.get(resource_id, {})
	if res_def.is_empty():
		return _fail("Unknown item.")
	if qty <= 0:
		return _fail("Choose how many to sell.")
	if int(state.inventory.get(resource_id, 0)) < qty:
		return _fail("You don't have that many.")
	var earned := int(qty * float(res_def.retail_price))
	_remove_from(state.inventory, {resource_id: qty})
	state.profile.currency += earned
	var s := stats(state)
	s.income.sales += earned
	_add_to(s.sales_by_item, {resource_id: earned})
	_add_to(s.sold, {resource_id: qty})
	return _ok({"earned": earned})


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


static func warehouse_cap(data: Dictionary) -> int:
	return int(data.config.warehouse_cap)


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


## How fast a building works: 1.0 = full speed. Buildings that need workers share the people
## there are (see staffing); others always work at full speed.
static func building_speed(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	if int(data.buildings.get(b.type, {}).get("workers", 0)) <= 0:
		return 1.0
	return staffing(state, data, now)


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
##  "buildings": {"working", "idle" (empty queue), "full" (storage full), "building" (under construction)}}
static func production_rates(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var made := {}
	var used := {}
	var counts := {"working": 0, "idle": 0, "full": 0, "building": 0}
	for b in state.buildings:
		var def: Dictionary = data.buildings.get(b.type, {})
		var category: String = def.get("category", "")
		if category not in ["extractor", "processor"]:
			continue
		if not is_built(b, now):
			counts.building += 1
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


## Share of jobs that are filled, 0.0 to 1.0 (1.0 when there are enough people or no jobs).
## Every building that needs workers runs at this speed: with 10 people and 14 jobs they all
## work at 71% (plan.md §5.6: short-staffed buildings slow down rather than stop).
static func staffing(state: Dictionary, data: Dictionary, now: float) -> float:
	var e := employment(state, data, now)
	if e.jobs <= 0:
		return 1.0
	return float(e.employed) / float(e.jobs)


## Jobs come from finished buildings ("workers" in buildings.json); people fill them up to the
## population. {"population", "jobs", "employed", "unemployed", "open_jobs"}
static func employment(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var jobs := 0
	for b in state.buildings:
		if is_built(b, now):
			jobs += int(data.buildings.get(b.type, {}).get("workers", 0))
	var people := int(state.population.current)
	var employed := mini(people, jobs)
	return {"population": people, "jobs": jobs, "employed": employed, "unemployed": people - employed, "open_jobs": jobs - employed}


## Money in and out over (up to) the last `window` seconds, from the history points:
## {"income", "spending", "seconds" (how much time that really covers; 0 = no history yet)}.
static func cash_flow(state: Dictionary, window: float, now: float) -> Dictionary:
	var s := stats(state)
	var from := {}
	for point in s.history:
		if float(point.t) >= now - window:
			from = point
			break
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
		"income": {"sales": 0, "demolish": 0},  # money in, by where it came from
		"spending": {"construction": 0},  # money out, by what it went on
		"sales_by_item": {},  # resource -> money earned selling it
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
