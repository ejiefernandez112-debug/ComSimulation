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
	var problem := _check_shape(state)
	if problem != "":
		return _fail("The save file is damaged (%s)." % problem)
	_drop_unknown(state, data, warnings)
	_migrate(state, version, data)
	return {"ok": true, "error": "", "state": state, "warnings": warnings}


## Upgrades an older save one version at a time, so old saves keep working.
static func _migrate(state: Dictionary, version: int, data: Dictionary) -> void:
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
		# Version 4: money is kept in whole cents (plan.md §5.11). Older saves counted dollars.
		_dollars_to_cents(state)
		version = 4
	state["save_version"] = version


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
		if not Simulation.building_at(state, cell).is_empty():
			cell = _first_free_cell(state)
		if cell.x >= 0:
			Simulation._add_building(state, entry.type, cell, float(state.get("settled_at", 0.0)), 0.0)
		return


## The first empty tile of the plot, row by row; (-1, -1) if every tile is taken.
static func _first_free_cell(state: Dictionary) -> Vector2i:
	var grid: Array = state.plot.grid_size
	for y in int(grid[1]):
		for x in int(grid[0]):
			if Simulation.building_at(state, Vector2i(x, y)).is_empty():
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


## "" if the state has everything the game rules expect, otherwise what's wrong.
static func _check_shape(state: Dictionary) -> String:
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
		if typeof(b.get("storage")) != TYPE_DICTIONARY or typeof(b.get("queue")) != TYPE_ARRAY:
			return "a building without storage"
		if not _is_number(b.get("job_started_at")) or typeof(b.get("blocked")) != TYPE_BOOL:
			return "a building without its timer"
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


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "state": {}, "warnings": []}
