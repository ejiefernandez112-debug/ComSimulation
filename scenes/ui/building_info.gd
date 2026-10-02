class_name BuildingInfo
## Turns a building's state into words for the UI ("Making Flour · 2m 31s left"). Only reads
## Economy and GameData; the game rules themselves live in scripts/sim/.


## The building's (first) recipe, or {} if it has none.
static func recipe(type_id: String) -> Dictionary:
	var recipes: Array = GameData.buildings[type_id].get("recipes", [])
	return recipes[0] if not recipes.is_empty() else {}


## The first resource a recipe makes, e.g. "flour".
static func output_of(r: Dictionary) -> String:
	return r.outputs.keys()[0] if not r.is_empty() else ""


static func stored(b: Dictionary) -> int:
	var total := 0
	for res in b.storage:
		total += int(b.storage[res])
	return total


static func resource_name(resource_id: String) -> String:
	return str(GameData.resources.get(resource_id, {}).get("name", resource_id))


## "40 Wheat" / "32 Flour + 4 Milk".
static func amounts(items: Dictionary) -> String:
	var parts: Array[String] = []
	for res in items:
		parts.append("%d %s" % [int(items[res]), resource_name(res)])
	return " + ".join(parts)


## Below full speed: say how slow and why. Too few people in town is a warning; a lower
## staffing level the player chose is not.
static func _with_speed(text: String, progress: float, speed: float) -> Dictionary:
	if speed >= 0.999:
		return {"text": text, "progress": progress, "good": true}
	if Economy.staffing() < 1.0:
		return {"text": "%s · %d%% speed, short of workers" % [text, floori(speed * 100.0 + 0.001)], "progress": progress, "good": false}
	return {"text": "%s · %d%% speed" % [text, floori(speed * 100.0 + 0.001)], "progress": progress, "good": true}


static func _no_workers(progress: float) -> Dictionary:
	return {"text": "Stopped: no workers yet. Build houses so people move in", "progress": progress, "good": false}


## What the building is doing: {"text": String, "progress": 0..1, or -1 for no bar, "good": bool}.
static func status(b: Dictionary) -> Dictionary:
	var def: Dictionary = GameData.buildings[b.type]
	var r := recipe(b.type)
	if not Economy.is_built(b):
		return {"text": "Under construction · %s left" % UITheme.duration(Economy.construction_left(b)), "progress": Economy.construction_progress(b), "good": true}
	match def.category:
		"extractor":
			var per_cycle := 0
			for res in r.outputs:
				per_cycle += int(r.outputs[res])
			if int(def.storage_cap) - stored(b) < per_cycle:
				return {"text": "Halted: storage full. Collect to restart (no wages meanwhile)", "progress": 1.0, "good": false}
			var p := Economy.job_progress(b)
			var speed := Economy.building_speed(b)
			if speed <= 0.0:
				return _no_workers(p)
			var left := (1.0 - p) * float(r.duration) / speed
			return _with_speed("Growing %s · next in %s" % [resource_name(output_of(r)), UITheme.duration(left)], p, speed)
		"processor":
			if b.blocked:
				return {"text": "Halted: done, no room. Collect to restart (no wages meanwhile)", "progress": 1.0, "good": false}
			if b.queue.is_empty():
				return {"text": "Idle: add a job to start (no wages meanwhile)", "progress": -1.0, "good": false}
			var p := Economy.job_progress(b)
			var speed := Economy.building_speed(b)
			if speed <= 0.0:
				return _no_workers(p)
			var left: float = ((1.0 - p) * float(r.duration) + (b.queue.size() - 1) * float(r.duration)) / speed
			return _with_speed("Making %s · %s left" % [resource_name(output_of(r)), UITheme.duration(left)], p, speed)
		"residential":
			return {"text": "Home for %d people" % int(def.get("population_capacity", 0)), "progress": -1.0, "good": true}
	return {"text": "Your headquarters", "progress": -1.0, "good": true}
