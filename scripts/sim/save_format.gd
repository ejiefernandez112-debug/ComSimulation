extends RefCounted
## Turns the game state into save-file text and back (plan.md §8). Pure like simulation.gd: no
## files, no clock. Reading and writing the actual file is Economy's job.
##
## The file is plain JSON with "save_version" and "last_saved_at". When the state's shape changes,
## raise Simulation.SAVE_VERSION and add a step to _migrate() that upgrades older saves, so a
## player's old save keeps working.

const Simulation = preload("res://scripts/sim/simulation.gd")


## The save file's text for `state`, stamped with `now` as the time it was saved.
static func to_text(state: Dictionary, now: float) -> String:
	var copy := state.duplicate(true)
	copy["save_version"] = Simulation.SAVE_VERSION
	copy["last_saved_at"] = now
	# full precision: times are unix seconds with fractions, and losing digits would shift jobs.
	return JSON.stringify(copy, "\t", true, true)


## Reads save-file text back into a game state.
## Returns {"ok", "error", "state", "warnings" (things that were fixed or dropped on the way)}.
static func from_text(text: String, data: Dictionary) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _fail("The save file is damaged.")
	var state: Dictionary = _whole_numbers(json.data)
	var version := int(state.get("save_version", 0))
	if version > Simulation.SAVE_VERSION:
		return _fail("The save was made by a newer version of the game.")
	if version < 1:
		return _fail("This isn't a save file.")
	var warnings: Array[String] = []
	var problem := _check_shape(state, version)
	if problem != "":
		return _fail("The save file is damaged (%s)." % problem)
	_drop_unknown(state, data, warnings)
	_migrate(state, version, data, warnings)
	return {"ok": true, "error": "", "state": state, "warnings": warnings}


## Upgrades an older save one version at a time, so old saves keep working.
static func _migrate(state: Dictionary, version: int, data: Dictionary, warnings: Array[String] = []) -> void:
	if version < 11:
		# Version 11 renamed the headquarters to City Hall (plan.md §5.15): it was saved as
		# "construction_office", an id that now means the new Construction Office. Renamed before
		# the other steps, so the roads of step 10 start from City Hall.
		_headquarters_to_city_hall(state, data)
	if version < 2:
		# Version 2: the warehouse became a real building (plan.md §5.10). Older saves get the
		# starter warehouse, or they would have no room for goods at all.
		_add_starter_warehouse(state, data)
		version = 2
	if version < 3:
		# Version 3: each building keeps its own whole number of hired workers (plan.md §5.6,
		# "Hiring & wage bonuses"), instead of an even share. Hand the town's people out by the
		# new rules, as things stood when the game was saved.
		for b in state.buildings:
			b["hired"] = 0
		Simulation._hire(state, data, float(state.get("settled_at", 0.0)))
		version = 3
	if version < 4:
		# Version 4: money is kept in whole cents (plan.md §5.12). Older saves counted dollars.
		_dollars_to_cents(state)
		version = 4
	if version < 5:
		# Version 5: stock carries cost tags (plan.md §5.14). Older saves don't know what their
		# goods cost, so they get the standard cost of making them.
		_standard_cost_tags(state, data)
		version = 5
	if version < 6:
		# Version 6: children, births and deaths (plan.md §5.6). Everyone in an older save is an
		# adult; no part-people are on the way yet. There's no "started_at", so an older village
		# gets no new-village grace period.
		state.population["children"] = []
		state.population["life_carry"] = {}
		Simulation.people_stats(state)  # adds the zeroed counters
		version = 6
	if version < 7:
		# Version 7: housing types (plan.md §5.18). The Small House became the Regular House, which
		# charges rent; before, it was free, so jobless households in an older save would end up
		# homeless the moment it loads. A save from before housing types (no Public Housing, Villa
		# or hut anywhere) gets its Small Houses back as free homes: Public Housing.
		var has_types := false
		for b in state.buildings:
			has_types = has_types or b.type in ["public_housing", "villa", "makeshift_hut"]
		if not has_types and data.buildings.has("public_housing"):
			for b in state.buildings:
				if b.type == "small_house":
					b.type = "public_housing"
		version = 7
	if version < 8:
		# Version 8: the balance sheet (plan.md §5.19). Older saves didn't keep what was paid for
		# each building or what the company started with, so they get list prices, and a starting
		# cash that makes the cash check add up.
		_balance_sheet_start(state, data)
		version = 8
	if version < 9:
		# Version 9: production batches (plan.md §5.1). Farms, Mills and Bakeries no longer have a
		# job queue or their own storage: everything in them goes to the Warehouse.
		_queues_to_warehouse(state, data)
		version = 9
	if version < 10:
		# Version 10: roads (plan.md §5.20). Buildings with workers need a road to the Construction
		# Office, so older saves get free roads laid to every building that can be reached, and
		# the workers are handed out again by the new rule.
		state["roads"] = []
		if Simulation.stats(state).has("spending"):
			Simulation.stats(state).spending["roads"] = 0
		Simulation.lay_roads_to_all(state, data)
		Simulation._hire(state, data, float(state.get("settled_at", 0.0)))
		version = 10
	if version < 11:
		# Version 11: building and upgrading need workers from a Construction Office (plan.md
		# §5.15). Older saves get one free, already standing beside their roads, and the workers
		# are handed out again (it's staffed first).
		Simulation.add_free_crew_office(state, data)
		Simulation._hire(state, data, float(state.get("settled_at", 0.0)))
		version = 11
	if version < 12:
		# Version 12: electricity (plan.md §5.5). Mills and Bakeries need power, which reaches only
		# buildings inside the power network around City Hall. Older saves get a power meter, a
		# power line in the spending, and free Electric Substations so every building that uses
		# power is inside the network; then power is handed out by the new rule.
		var at := float(state.get("settled_at", 0.0))
		Simulation.utility_meter(state, "power", at)
		if Simulation.stats(state).has("spending"):
			Simulation.stats(state).spending["power"] = 0
		Simulation.cover_all_with_power(state, data)
		Simulation._hire(state, data, at)
		version = 12
	if version < 13:
		# Version 13: product choice (plan.md §5.21). A building with several recipes is set up for
		# one product, chosen by its first batch. Farms, Mills and Bakeries in an older save have
		# already made theirs, so they keep it: their batch's recipe, else their first recipe (an
		# old Flour Mill stays a flour mill even though mills can now grind corn and rice).
		_products_from_batches(state, data)
		version = 13
	if version < 14:
		# Version 14: big buildings stand on 2x2 tiles (plan.md §4) and the land grew to 26x26.
		# The village moves to the middle of the bigger land, then every building is fitted to
		# its footprint: roads under it go (paid back), one overlapping an older one moves, and
		# free road is laid to buildings that lost theirs. The player is told what changed.
		_grow_plot(state, data)
		warnings.append_array(Simulation.fit_footprints(state, data))
		Simulation._hire(state, data, float(state.get("settled_at", 0.0)))
		version = 14
	if version < 15:
		# Version 15: demolishing gives back materials, not money (plan.md §5.15), so every
		# building remembers what it was built with. Older saves don't know what was paid for
		# them, so they get their materials at base prices. Supermarkets have fewer shelves now:
		# shelves past the new number are taken down (what sold is paid, the rest goes back).
		_record_old_materials(state, data)
		_trim_shelves(state, data)
		version = 15
	state["save_version"] = version


## For a version 14 save: each building's materials (its level, plus an upgrade under way, whose
## materials were already bought). What they cost isn't known, only the building's total price
## ("paid": materials + crew, at the prices of its day), so the materials get their share of that
## price (their share of its value at base prices). Then demolishing an old building never makes
## the company worth more than it paid.
static func _record_old_materials(state: Dictionary, data: Dictionary) -> void:
	for b in state.buildings:
		if b.has("materials"):
			continue
		var level := Simulation.building_level(b) + (1 if b.has("upgrade_done_at") else 0)
		Simulation.record_base_materials(data, b, level)
		var costs: Dictionary = b.get("materials_cost", {})
		var value := 0
		for l in range(1, mini(level, Simulation.max_level(data, b.type)) + 1):
			value += Simulation.level_value(data, b.type, l)
		if costs.is_empty() or value <= 0 or int(b.get("paid", 0)) <= 0:
			continue
		var scale := float(b.paid) / value  # what was paid ÷ its value at base prices
		for res in costs:
			costs[res] = float(costs[res]) * scale


## For a version 14 save: stores keep only as many shelves as their level now has; the others are
## taken down as the game was saved.
static func _trim_shelves(state: Dictionary, data: Dictionary) -> void:
	var at := float(state.get("settled_at", 0.0))
	for b in state.buildings:
		var list: Array = b.get("shelves", [])
		var keep := int(Simulation.level_stat(data, b, "shelves", 0))
		if list.size() <= keep:
			continue
		for i in range(keep, list.size()):
			if not list[i].is_empty():
				var taken := Simulation._take_down_shelf(state, data, b, i, at)
				Simulation._add_to(state.inventory, taken.back)
				Simulation._put_cost(Simulation._costs(state, "inventory_cost"), taken.back_cost)
		list.resize(keep)


## For a version 13 save: the land grows to game_config.json's grid_size (it never shrinks), and
## every building and road moves by the same amount, so the village stays in the middle.
static func _grow_plot(state: Dictionary, data: Dictionary) -> void:
	var old: Array = state.plot.grid_size
	var target: Array = data.config.get("grid_size", old)
	var size := Vector2i(maxi(int(old[0]), int(target[0])), maxi(int(old[1]), int(target[1])))
	var shift := (size - Vector2i(int(old[0]), int(old[1]))) / 2
	state.plot.grid_size = [size.x, size.y]
	for b in state.buildings:
		b.position = [int(b.position[0]) + shift.x, int(b.position[1]) + shift.y]
	for road in state.get("roads", []):
		road[0] = int(road[0]) + shift.x
		road[1] = int(road[1]) + shift.y


## For a version 12 save: every building that makes batches gets its product (see _migrate).
static func _products_from_batches(state: Dictionary, data: Dictionary) -> void:
	for b in state.buildings:
		if not Simulation.makes_batches(data, b) or Simulation.product_of(data, b) != "":
			continue
		var recipes: Array = data.buildings.get(b.type, {}).get("recipes", [])
		var running := str(b.get("batch", {}).get("recipe_id", ""))
		if running != "" and not Simulation._recipe(data.buildings[b.type], running).is_empty():
			b["product"] = running
		elif not recipes.is_empty():
			b["product"] = str(recipes[0].id)


## Saves before version 11 called the headquarters "construction_office"; it is City Hall now.
static func _headquarters_to_city_hall(state: Dictionary, data: Dictionary) -> void:
	if not data.buildings.has("city_hall"):
		return
	for b in state.buildings:
		if b.type == "construction_office":
			b.type = "city_hall"


## For a version 8 save: each Farm, Mill and Bakery hands its stored goods (with their cost tags)
## and its queued jobs to the Warehouse: every job's ingredients come back in full, and a finished
## job that was waiting for room comes as its products, at their standard cost. The Warehouse may
## end up over full (nothing is thrown away; nothing new comes in until there's room again).
## Then the building is idle, ready for its first batch.
static func _queues_to_warehouse(state: Dictionary, data: Dictionary) -> void:
	var inventory_cost: Dictionary = Simulation._costs(state, "inventory_cost")
	for b in state.buildings:
		if Simulation.makes_batches(data, b):
			Simulation._add_to(state.inventory, b.get("storage", {}))
			Simulation._put_cost(inventory_cost, b.get("storage_cost", {}))
			var def: Dictionary = data.buildings.get(b.type, {})
			for i in b.get("queue", []).size():
				var job: Dictionary = b.queue[i]
				var recipe := Simulation._recipe(def, job.get("recipe_id", ""))
				if recipe.is_empty():
					continue
				if i == 0 and bool(b.get("blocked", false)):
					Simulation._add_to(state.inventory, recipe.outputs)
					for res in recipe.outputs:
						Simulation._put_cost(inventory_cost, {res: int(recipe.outputs[res]) * Simulation.standard_unit_cost(data, res)})
				else:
					Simulation._add_to(state.inventory, recipe.get("inputs", {}))
					Simulation._put_cost(inventory_cost, job.get("input_cost", {}))
			b["storage"] = {}
			b["storage_cost"] = {}
		b.erase("queue")
		b.erase("blocked")
		b["batch"] = {}


## Balance sheet numbers for a version 7 save: each building's price at its level ("paid"; an
## upgrade under way also "upgrade_paid"), and the starting capital: the starter buildings at
## list price, and the cash that "start + money in − money out = cash now" needs (any old dev
## tool changes, which weren't counted then, end up in it).
static func _balance_sheet_start(state: Dictionary, data: Dictionary) -> void:
	for b in state.buildings:
		var level := Simulation.building_level(b)
		var paid := Simulation.construction_value(data, b.type, level)
		if b.has("upgrade_done_at") and level < Simulation.max_level(data, b.type):
			b["upgrade_paid"] = Simulation.level_value(data, b.type, level + 1)
			paid += int(b.upgrade_paid)
		b["paid"] = paid
	var s := Simulation.stats(state)
	var starters := 0
	for entry in data.config.get("starting_buildings", []):
		starters += Simulation.construction_value(data, entry.type)
	var income: Dictionary = s.get("income", {})
	var spending: Dictionary = s.get("spending", {})
	s["capital"] = {"cash": int(state.profile.currency) - Simulation._total(income) + Simulation._total(spending),
		"buildings": starters}
	s["adjustments"] = 0
	s["money_log"] = []


## Cost tags for a version 4 save: every stock (warehouse, building storage, queued batches'
## ingredients) at the standard cost of making it.
static func _standard_cost_tags(state: Dictionary, data: Dictionary) -> void:
	var inventory_cost := {}
	for res in state.inventory:
		inventory_cost[res] = int(state.inventory[res]) * Simulation.standard_unit_cost(data, res)
	state["inventory_cost"] = inventory_cost
	for b in state.buildings:
		var storage_cost := {}
		for res in b.get("storage", {}):
			storage_cost[res] = int(b.storage[res]) * Simulation.standard_unit_cost(data, res)
		b["storage_cost"] = storage_cost
		var def: Dictionary = data.buildings.get(b.type, {})
		for job in b.get("queue", []):  # (a warehouse added by step 2 has none)
			var paid := {}
			for recipe in def.get("recipes", []):
				if recipe.id == job.get("recipe_id", ""):
					for res in recipe.get("inputs", {}):
						paid[res] = int(recipe.inputs[res]) * Simulation.standard_unit_cost(data, res)
			job["input_cost"] = paid


## Every money amount in a version 3 save, from dollars to cents: cash, the part-cent wage
## carry, the tax window's sales, and the statistics (money in / out, sales by item, graphs).
static func _dollars_to_cents(state: Dictionary) -> void:
	state.profile.currency = int(state.profile.currency) * 100
	state["wage_carry"] = float(state.get("wage_carry", 0.0)) * 100.0
	for entry in state.get("sales_log", []):
		entry[1] = int(entry[1]) * 100
	var stats: Dictionary = state.get("stats", {})
	for group in ["income", "spending", "sales_by_item"]:
		var amounts: Dictionary = stats.get(group, {})
		for key in amounts:
			amounts[key] = int(amounts[key]) * 100
	for point in stats.get("history", []):
		for key in ["cash", "income", "spending"]:
			if point.has(key):
				point[key] = int(point[key]) * 100


## Puts the starting kit's warehouse where the kit says, or on the first free tile.
static func _add_starter_warehouse(state: Dictionary, data: Dictionary) -> void:
	for entry in data.config.get("starting_buildings", []):
		if data.buildings.get(entry.type, {}).get("category", "") != "storage":
			continue
		var cell := Vector2i(int(entry.position[0]), int(entry.position[1]))
		if Simulation._footprint_problem(state, data, entry.type, cell) != "":  # perf-ok: one warehouse, once
			cell = _first_free_spot(state, data, entry.type)
		if cell.x >= 0:
			Simulation._add_building(state, entry.type, cell, float(state.get("settled_at", 0.0)), 0.0)
		return


## The first spot of the plot (row by row) where a building of this kind fits; (-1, -1) if none.
static func _first_free_spot(state: Dictionary, data: Dictionary, type_id: String) -> Vector2i:
	var grid: Array = state.plot.grid_size
	var map := Simulation._plot_map(state, data)
	for y in int(grid[1]):
		for x in int(grid[0]):
			if Simulation._footprint_problem(state, data, type_id, Vector2i(x, y), "", map) == "":
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## JSON keeps every number as a decimal (5750 comes back as 5750.0). Turn whole numbers back
## into whole numbers, so counts and money look exactly like they did in a fresh game.
static func _whole_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			if value == floorf(value) and absf(value) < 9.0e15:
				return int(value)
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[key] = _whole_numbers(value[key])
			return out
		TYPE_ARRAY:
			var out := []
			for item in value:
				out.append(_whole_numbers(item))
			return out
	return value


## "" if the state has everything the game rules expect (for a save of `version`), otherwise
## what's wrong.
static func _check_shape(state: Dictionary, version: int) -> String:
	for key in ["profile", "plot", "population", "inventory"]:
		if typeof(state.get(key)) != TYPE_DICTIONARY:
			return "no %s" % key
	if typeof(state.get("buildings")) != TYPE_ARRAY:
		return "no buildings"
	if not _is_number(state.profile.get("currency")):
		return "no cash"
	if typeof(state.plot.get("grid_size")) != TYPE_ARRAY or state.plot.grid_size.size() != 2:
		return "no plot size"
	if not _is_number(state.population.get("current")) or not _is_number(state.population.get("growth_anchor")):
		return "no population"
	if not _is_number(state.get("next_building_id")):
		return "no building counter"
	for b in state.buildings:
		if typeof(b) != TYPE_DICTIONARY or typeof(b.get("id")) != TYPE_STRING or typeof(b.get("type")) != TYPE_STRING:
			return "a building without a name"
		if typeof(b.get("position")) != TYPE_ARRAY or b.position.size() != 2:
			return "a building without a place"
		if typeof(b.get("storage")) != TYPE_DICTIONARY:
			return "a building without storage"
		if not _is_number(b.get("job_started_at")):
			return "a building without its timer"
		if version < 9 and typeof(b.get("queue", [])) != TYPE_ARRAY:
			return "a building with a broken queue"
		if version >= 9 and not _batch_ok(b.get("batch")):
			return "a building with a broken batch"
		if b.has("product") and typeof(b.product) != TYPE_STRING:
			return "a building with a broken product"
	if version >= 10:
		if typeof(state.get("roads")) != TYPE_ARRAY:
			return "no roads"
		for road in state.roads:
			if typeof(road) != TYPE_ARRAY or road.size() != 3 or not _is_number(road[0]) or not _is_number(road[1]) or not _is_number(road[2]):
				return "a broken road"
	return ""


## Buildings and goods the game no longer has (renamed or removed from data/*.json) would crash
## the screens that look them up, so they are left out, and the player is told.
static func _drop_unknown(state: Dictionary, data: Dictionary, warnings: Array[String]) -> void:
	var kept := []
	for b in state.buildings:
		if data.buildings.has(b.type):
			kept.append(b)
		else:
			warnings.append("Removed a building the game no longer has (%s)." % b.type)
	state.buildings = kept
	for res in state.inventory.keys():
		if not data.resources.has(res):
			state.inventory.erase(res)
			warnings.append("Removed goods the game no longer has (%s)." % res)


## A building's batch: {} (idle), or one with everything the rules read.
static func _batch_ok(batch: Variant) -> bool:
	if typeof(batch) != TYPE_DICTIONARY:
		return false
	if batch.is_empty():
		return true
	for key in ["units", "collected", "inputs", "input_cost"]:
		if typeof(batch.get(key)) != TYPE_DICTIONARY:
			return false
	for key in ["hours", "made_hours", "cost", "wages"]:
		if not _is_number(batch.get(key)):
			return false
	return typeof(batch.get("recipe_id")) == TYPE_STRING and typeof(batch.get("bonus")) == TYPE_STRING and int(batch.hours) >= 1


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "state": {}, "warnings": []}
