class_name BuildingInfo
## Turns a building's state into words for the UI ("Making Flour · 2m 31s left"). Only reads
## Economy and GameData; the game rules themselves live in scripts/sim/.


## The building's (first) recipe, or {} if it has none.
static func recipe(type_id: String) -> Dictionary:
	var recipes: Array = GameData.buildings[type_id].get("recipes", [])
	return recipes[0] if not recipes.is_empty() else {}


## The recipe this building is working on or set up for (plan.md §5.21): its batch's, else its
## product, else its first recipe (a new building that hasn't chosen yet). {} if it makes nothing.
static func recipe_of(b: Dictionary) -> Dictionary:
	var recipes: Array = GameData.buildings[b.type].get("recipes", [])
	var id := str(b.get("batch", {}).get("recipe_id", ""))
	if id == "":
		id = Economy.product_of(b)
	for r in recipes:
		if r.id == id:
			return r
	return recipes[0] if not recipes.is_empty() else {}


## True when a building makes one of several products and hasn't chosen yet.
static func choosing(b: Dictionary) -> bool:
	return GameData.buildings[b.type].get("recipes", []).size() > 1 and Economy.product_of(b) == ""


## The first resource a recipe makes, e.g. "flour".
static func output_of(r: Dictionary) -> String:
	return r.outputs.keys()[0] if not r.is_empty() else ""


## Goods waiting in the building to be collected (a batch's finished hours).
static func stored(b: Dictionary) -> int:
	var total := 0
	var waiting := Economy.waiting_goods(b)
	for res in waiting:
		total += int(waiting[res])
	return total


static func resource_name(resource_id: String) -> String:
	return str(GameData.resources.get(resource_id, {}).get("name", resource_id))


## "40 Wheat" / "32 Flour + 4 Milk".
static func amounts(items: Dictionary) -> String:
	var parts: Array[String] = []
	for res in items:
		parts.append("%d %s" % [int(items[res]), resource_name(res)])
	return " + ".join(parts)


## What building or upgrading needs, from a quote (Economy.build_quote / upgrade_quote):
## "400 Bricks · 40 Cement · 10 Steel · 20 Construction materials · 1 construction worker for 1h".
static func construction_needs(quote: Dictionary) -> String:
	var parts: Array[String] = []
	for line in quote.get("lines", []):
		if line.id == "labor":
			parts.append("%s for %s" % [crew_count(int(line.amount)), UITheme.duration(float(quote.seconds))])
		else:
			parts.append("%s %s" % [UITheme.number(int(line.amount)), line.name])
	return " · ".join(parts)


## "1 construction worker" / "3 construction workers".
static func crew_count(n: int) -> String:
	return "1 construction worker" if n == 1 else "%s construction workers" % UITheme.number(n)


## The construction workers of all Construction Offices (plan.md §5.15) and what they're on:
## "3 of 4 construction workers free" plus a line per job ("1 building Wheat Farm · 35m left").
static func crew_status() -> String:
	var crew := Economy.crew()
	var lines: Array[String] = ["%d of %s free (all your Construction Offices)" % [int(crew.free), crew_count(int(crew.total))]]
	for job in crew.jobs:
		var b := Economy.building(str(job.building_id))
		if b.is_empty():
			continue
		var what := "building %s" % GameData.buildings[b.type].name
		if Economy.is_upgrading(b):
			what = "upgrading %s to Level %d" % [GameData.buildings[b.type].name, Economy.building_level(b) + 1]
		lines.append("%d %s · %s left" % [int(job.crew), what, UITheme.duration(float(job.until) - TimeService.now())])
	return "\n".join(lines)


## "3 MW" / "0.5 MW".
static func mw(value: float) -> String:
	return "%s MW" % (UITheme.number(roundi(value)) if is_equal_approx(value, roundf(value)) else str(snappedf(value, 0.1)))


## Why a building has no power (plan.md §5.5), in words; "" when it has power or needs none.
static func power_warning(b: Dictionary) -> String:
	match Economy.power_problem(b):
		"no_grid":
			return "No power: it's outside your power network. Build an Electric Substation near it (Build → Power)"
		"short":
			return "No power: it needs %s and only %s is left (older buildings come first). Build a Wind Turbine, or suspend something" % [mw(Economy.power_need(b)), mw(float(Economy.power_summary().left))]
	return ""


## The power network in one line: "Power: 7 of 15 MW used (5 MW your plants + up to 10 MW grid)".
static func power_line() -> String:
	var p := Economy.power_summary()
	var text := "Power: %s of %s used (%s your plants + up to %s from the grid)" % [mw(float(p.used)), mw(float(p.own) + float(p.grid)), mw(float(p.own)), mw(float(p.grid))]
	var short := float(p.wanted) - float(p.used)
	if short > 0.001:
		text += " · %s short" % mw(short)
	return text


## Below full speed: say how slow and why. Open posts it couldn't fill are a warning; a lower
## staffing level the player chose is not.
static func _with_speed(b: Dictionary, text: String, progress: float, speed: float) -> Dictionary:
	if speed >= 0.999:
		return {"text": text, "progress": progress, "good": true}
	var w := Economy.workers(b)
	if int(w.hired) < int(w.wanted):
		return {"text": "%s · %d%% speed, short of workers" % [text, floori(speed * 100.0 + 0.001)], "progress": progress, "good": false}
	return {"text": "%s · %d%% speed" % [text, floori(speed * 100.0 + 0.001)], "progress": progress, "good": true}


## Workers are always whole people: "3".
static func _count(workers: float) -> String:
	return str(roundi(workers))


static func _no_workers(_b: Dictionary, progress: float) -> Dictionary:
	return {"text": "Stopped: no workers. Build houses", "progress": progress, "good": false}


## A Farm, Mill or Bakery's batch (plan.md §5.1): "Making Flour · 6 of 14 h · done at 6:00 PM",
## or what's waiting to be collected, or idle.
static func _batch_status(b: Dictionary, r: Dictionary) -> Dictionary:
	var item := resource_name(output_of(r))
	var waiting := stored(b)
	if not Economy.has_batch(b):
		if choosing(b):
			return {"text": "Idle: choose what it makes and start a batch", "progress": -1.0, "good": false}
		return {"text": "Idle: start a batch to make %s" % item, "progress": -1.0, "good": false}
	if not Economy.batch_running(b):
		return {"text": "Batch done: collect %s %s" % [UITheme.number(waiting), item], "progress": 1.0, "good": true}
	var batch: Dictionary = b.batch
	var p := Economy.job_progress(b)
	var speed := Economy.building_speed(b)
	if speed <= 0.0:
		return _no_workers(b, p)
	var text := "Making %s · %d of %d h · done at %s" % [item, int(batch.made_hours), int(batch.hours), UITheme.clock(Economy.batch_finishes_at(b), TimeService.now())]
	if waiting > 0:
		text += " · %s ready" % UITheme.number(waiting)
	return _with_speed(b, text, p, speed)


## What the building is doing: {"text": String, "progress": 0..1, or -1 for no bar, "good": bool}.
## A home or warehouse being upgraded keeps working, so it says so after what it's doing.
static func status(b: Dictionary) -> Dictionary:
	var now := _status_now(b)
	if Economy.is_upgrading(b) and Economy.is_built(b):
		now.text += " · upgrading to Level %d, %s left" % [Economy.building_level(b) + 1, UITheme.duration(Economy.upgrade_left(b))]
	return now


static func _status_now(b: Dictionary) -> Dictionary:
	var def: Dictionary = GameData.buildings[b.type]
	var r := recipe_of(b)
	if Economy.is_upgrading(b) and not Economy.is_built(b):
		return {"text": "Closed for its upgrade to Level %d · %s left. No workers, no wages; work in progress waits" % [Economy.building_level(b) + 1, UITheme.duration(Economy.upgrade_left(b))], "progress": Economy.construction_progress(b), "good": true}
	if not Economy.is_built(b):
		return {"text": "Under construction · %s left" % UITheme.duration(Economy.construction_left(b)), "progress": Economy.construction_progress(b), "good": true}
	if Economy.is_suspended(b):
		return {"text": "Suspended: switched off, no workers, no wages. Resume to start again", "progress": -1.0, "good": false}
	if not Economy.on_road(b):
		return {"text": "Stopped: no road, so no workers can get here. Build a road from it to your roads (Build → Roads)", "progress": -1.0, "good": false}
	var no_power := power_warning(b)
	if no_power != "" and def.category != "residential":
		return {"text": "Stopped. " + no_power, "progress": Economy.job_progress(b) if Economy.batch_running(b) else -1.0, "good": false}
	match def.category:
		"construction":
			return {"text": crew_status(), "progress": -1.0, "good": int(Economy.crew().free) > 0}
		"storage":
			var room := Economy.storage_capacity(b)
			var full := int(Economy.level_stat(b, "capacity"))
			if room < full:  # its workers are fixed, so only a lack of people can cut its room
				var w := Economy.workers(b)
				return {"text": "Room for %s of %s goods (%s of %d workers: not enough people, build houses)" % [UITheme.number(room), UITheme.number(full), _count(w.working), int(w.max)], "progress": -1.0, "good": false}
			return {"text": "Room for %s goods" % UITheme.number(room), "progress": -1.0, "good": true}
		"utility":
			# A Water Treatment Plant (plan.md §5.13.1): what it cleans, and how much is used.
			var cleaned := Economy.water_supply(b)
			var full := float(Economy.level_stat(b, "water_supply"))
			var water := Economy.water_summary()
			var text := "Cleaning %s m³/h · your buildings use %s" % [UITheme.number(roundi(cleaned)), UITheme.number(roundi(float(water.used)))]
			if float(water.spare) > 0.5:
				text += " · %s spare" % UITheme.number(roundi(float(water.spare)))
			elif float(water.public) > 0.5:
				text += " · %s more from the public supply" % UITheme.number(roundi(float(water.public)))
			if cleaned < full - 0.001:
				var w := Economy.workers(b)
				return {"text": "%s (%s of %d workers: not enough people, build houses)" % [text, _count(w.working), int(w.max)], "progress": -1.0, "good": false}
			return {"text": text, "progress": -1.0, "good": true}
		"extractor", "processor":
			return _batch_status(b, r)
		"power":
			return _power_status(b)
		"trade":
			# The Trading Post (plan.md §5.22): the trader's prices, as shares of the normal price.
			var shares: Dictionary = GameData.config.get("trade", {})
			return {"text": "Open: the trader buys anything at %d%% of its price and sells anything at %d%%" % [roundi(float(shares.get("sell_share", 1.0)) * 100.0), roundi(float(shares.get("buy_share", 1.0)) * 100.0)], "progress": -1.0, "good": true}
		"retail":
			var selling := 0
			var soonest := INF  # seconds until the first shelf sells out
			var list := Economy.shelves(b)
			for i in list.size():
				if not list[i].is_empty():
					selling += 1
					soonest = minf(soonest, Economy.shelf_time_left(b, i))
			if selling == 0:
				return {"text": "Shelves empty: put food on a shelf to sell it (no wages meanwhile)", "progress": -1.0, "good": false}
			var speed := Economy.building_speed(b)
			if speed <= 0.0:
				return _no_workers(b, -1.0)
			return _with_speed(b, "Selling %d product%s · next sells out in %s" % [selling, "" if selling == 1 else "s", UITheme.duration(soonest)], -1.0, speed)
		"residential":
			# Who lives here comes from the housing rules (plan.md §5.18): households of 2 adults
			# + 2 children, by wealth class and what they can afford.
			var room := int(Economy.level_stat(b, "households"))
			var home: Dictionary = Economy.housing().homes.get(b.id, {})
			var households := int(home.get("households", 0))
			var progress := float(households) / maxf(room, 1)
			var people := "%d adults, %d children" % [int(home.get("adults", 0)), int(home.get("children", 0))]
			if def.get("hut", false):
				return {"text": "A homeless household lives here (%s). The hut goes once they have a home they can afford" % people, "progress": -1.0, "good": false}
			var text := "%d of %d households · %s" % [households, room, people]
			if float(home.get("rent", 0.0)) > 0.0:
				text += " · rent %s/h" % UITheme.price(roundi(float(home.rent) * 100.0))
			if households <= 0 and int(Economy.housing().homeless) == 0:
				return {"text": text + " · empty: everyone already has a home", "progress": progress, "good": true}
			if households <= 0:
				return {"text": text + " · empty: the homeless can't afford it or it isn't for their class", "progress": progress, "good": false}
			if Economy.power_problem(b) != "":  # nothing happens yet to a home without power; just say so
				text += " · no power (%s)" % ("outside your power network" if Economy.power_problem(b) == "no_grid" else "not enough left")
			return {"text": text, "progress": progress, "good": true}
	if Economy.power_on() and float(Economy.level_stat(b, "grid_mw", 0)) > 0.0:
		return {"text": "Your headquarters · its grid link supplies up to %s · %s" % [mw(float(Economy.level_stat(b, "grid_mw", 0))), power_line()], "progress": -1.0, "good": true}
	return {"text": "Your headquarters", "progress": -1.0, "good": true}


## A power plant or Electric Substation (plan.md §5.5): connected to the network or not, what it
## makes, and the whole network's power.
static func _power_status(b: Dictionary) -> Dictionary:
	var joined: bool = Economy.power_network().ids.has(b.id)
	var makes := float(Economy.level_stat(b, "power_supply", 0))
	if not joined:
		var why := "its power can't reach your buildings" if makes > 0.0 else "it carries no power"
		return {"text": "Not connected: its circle doesn't touch your power network, so %s. Move it closer, or build a Substation in between" % why, "progress": -1.0, "good": false}
	var text := "Connected · reaches %s tiles" % str(roundi(Economy.power_radius(b)))
	if makes > 0.0:
		text = "Making %s · connected" % mw(Economy.power_supply(b))
	return {"text": text + " · " + power_line(), "progress": -1.0, "good": true}
