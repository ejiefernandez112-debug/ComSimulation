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
	}
	for entry in config.starting_buildings:
		_add_building(state, entry.type, Vector2i(int(entry.position[0]), int(entry.position[1])), now)
	return state


# --- Settling time ------------------------------------------------------------

## Brings every building and the population up to `now`.
## Returns everything produced, e.g. {"wheat": 30, "population": 2} (for the offline summary).
static func settle(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var report := {}
	for b in state.buildings:
		_add_to(report, settle_building(b, data, now))
	var grown := _settle_population(state, data, now)
	if grown > 0:
		report["population"] = grown
	return report


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


static func _settle_population(state: Dictionary, data: Dictionary, now: float) -> int:
	var pop: Dictionary = state.population
	var cap := population_capacity(state, data)
	var step := float(data.config.population_growth_seconds)
	if step <= 0.0 or now < pop.growth_anchor:
		return 0
	if pop.current >= cap:
		pop.growth_anchor = now
		return 0
	var grown := mini(int((now - pop.growth_anchor) / step), cap - int(pop.current))
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
	var grid: Array = state.plot.grid_size
	if cell.x < 0 or cell.y < 0 or cell.x >= int(grid[0]) or cell.y >= int(grid[1]):
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
	state.profile.currency -= int(data.buildings[type_id].build_cost)
	var b := _add_building(state, type_id, cell, now)
	return _ok({"building_id": b.id})


## Queue a job. Inputs leave the Warehouse now, so a queued job can never stall for inputs.
static func enqueue(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	var def: Dictionary = data.buildings.get(b.type, {})
	if def.get("category", "") != "processor":
		return _fail("This building doesn't take orders.")
	var recipe := _recipe(def, recipe_id)
	if recipe.is_empty():
		return _fail("Unknown recipe.")
	settle_building(b, data, now)
	if b.queue.size() >= int(def.queue_size):
		return _fail("The queue is full.")
	for res in recipe.inputs:
		if int(state.inventory.get(res, 0)) < int(recipe.inputs[res]):
			return _fail("Not enough %s." % _resource_name(data, res))
	_remove_from(state.inventory, recipe.inputs)
	if b.queue.is_empty():
		b.job_started_at = now
		b.blocked = false
	b.queue.append({"recipe_id": recipe_id})
	return _ok()


## Move finished goods from the building into the Warehouse (as much as fits).
static func collect(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	settle_building(b, data, now)
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
	settle_building(b, data, now)  # a job that was waiting for space can finish now
	return _ok({"moved": moved})


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


static func population_capacity(state: Dictionary, data: Dictionary) -> int:
	var cap := 0
	for b in state.buildings:
		cap += int(data.buildings.get(b.type, {}).get("population_capacity", 0))
	return cap


static func warehouse_cap(data: Dictionary) -> int:
	return int(data.config.warehouse_cap)


static func warehouse_total(state: Dictionary) -> int:
	return _total(state.inventory)


## 0.0 to 1.0 progress of the current cycle/job, for progress bars.
static func job_progress(b: Dictionary, data: Dictionary, now: float) -> float:
	var def: Dictionary = data.buildings.get(b.type, {})
	var recipe := {}
	if def.get("category", "") == "extractor":
		recipe = def.recipes[0]
	elif not b.queue.is_empty():
		recipe = _recipe(def, b.queue[0].recipe_id)
	if recipe.is_empty():
		return 0.0
	return clampf((now - b.job_started_at) / float(recipe.duration), 0.0, 1.0)


# --- Helpers ------------------------------------------------------------------

static func _add_building(state: Dictionary, type_id: String, cell: Vector2i, now: float) -> Dictionary:
	var b := {
		"id": "b%d" % int(state.next_building_id),
		"type": type_id,
		"level": 1,
		"position": [cell.x, cell.y],
		"storage": {},
		"queue": [],  # [{recipe_id}], first entry is the job being worked on
		"job_started_at": now,  # start of the current cycle (extractor) or current job (processor)
		"blocked": false,  # processor: finished job is waiting for storage space
	}
	state.next_building_id = int(state.next_building_id) + 1
	state.buildings.append(b)
	return b


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
