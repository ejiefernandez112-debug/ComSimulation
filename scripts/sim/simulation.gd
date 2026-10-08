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
## Time model: buildings store when their current batch started (`job_started_at`).
## "Settling" turns elapsed time into finished output in one calculation, never tick-by-tick.

const SAVE_VERSION := 15  # 2: warehouses are buildings; 3: buildings keep their own hired workers;
# 4: money is stored in cents; 5: stock carries cost tags; 6: children, births and deaths;
# 7: housing types (old free Small Houses become Public Housing); 8: balance sheet (buildings
# keep what was paid for them, starting capital, money log); 9: production batches (a Farm,
# Mill or Bakery runs one batch of chosen hours instead of a job queue and its own storage);
# 10: roads (state.roads; buildings with workers need a road link to the Construction Office);
# 11: the old headquarters is City Hall; a new Construction Office's workers build everything;
# 12: electricity (power meter and bills; Mills and Bakeries need power from the grid);
# 13: each producer keeps its product (b.product): older ones keep what they were making;
# 14: big buildings stand on 2x2 tiles and the land grew to 26x26 (see fit_footprints);
# 15: buildings keep the materials they were built with (b.materials / b.materials_cost);
# Supermarkets have fewer shelves
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
		"roads": [],  # road tiles: [x, y, cents paid] (plan.md §5.20)
		"inventory": {},  # the Warehouse
		# current = everyone (adults + children); children = age groups, oldest first (see
		# _settle_life); life_carry = part-people of births and deaths still to come.
		"population": {"current": 0, "growth_anchor": now, "growth_speed": 1.0,  # see happiness()
			"children": [], "life_carry": {}},
		"started_at": now,  # when this village was founded
		"settled_at": now,  # everything has been worked out up to this moment
		"stats": _new_stats(),
		"water_meter": {"m3": 0.0, "base_cost": 0.0, "cycle_start": now},  # the first bill is due in 12 h
		"power_meter": {"mwh": 0.0, "base_cost": 0.0, "cycle_start": now},  # power from the public grid
	}
	var capital: Dictionary = state.stats.capital  # what the company started with (balance sheet)
	capital.cash = state.profile.currency
	for entry in config.starting_buildings:
		# Starting buildings are already standing: no construction time. They were free, but count
		# at their value (materials and labor at base prices), as part of the starting capital.
		var b := _add_building(state, entry.type, Vector2i(int(entry.position[0]), int(entry.position[1])), now, 0.0)
		b.paid = construction_value(data, entry.type)
		record_base_materials(data, b, 1)  # what demolishing it would give back
		capital.buildings = int(capital.buildings) + int(b.paid)
	# The starting roads link the starting buildings to City Hall. They count at
	# their price as part of the starting capital, like the buildings.
	for cell in _roads_config(data).get("starting_roads", []):
		var road_cell := Vector2i(int(cell[0]), int(cell[1]))
		if is_free_cell(state, data, road_cell):
			state.roads.append([road_cell.x, road_cell.y, road_price(data)])
			capital.buildings = int(capital.buildings) + road_price(data)
	# The founding villagers: all adults, never more than the starting homes hold.
	state.population.current = mini(int(config.get("starting_population", 0)), adult_room(state, data, now))
	_hire(state, data, now)  # also puts up huts if the homes are too few
	_record_money_log(state, data, now)  # the money log's first block starts now
	return state


# --- Settling time ------------------------------------------------------------

## Brings every building, the population and wages up to `now`.
## Returns everything produced, e.g. {"wheat": 30, "population": 2, "wages": 12000, "water": 71800}
## (money in cents; "water" / "power" = water and power bills charged; "rent" = rent collected; "population" = people
## who moved in; "born", "grew_up", "died", "moved_away" = births, children who became adults,
## deaths, people who left the island; "left_for_work" = the part of moved_away who grew up with
## no job waiting; for the offline summary).
##
## A building's speed depends on how many workers are actually working in it (see
## building_speed), and wages are paid for each of them. That only changes at a few moments
## (a person moves in and is hired, a building finishes or stops, the player changes staffing,
## which settles first),
## so the time since the last settle is split at those moments and each piece is worked out in
## one go. That's a handful of steps however long the player was away, never a minute-by-minute
## replay.
## `moment` is what the last hiring worked out ({"at", "housing", "power"}, see _hire). On return
## it holds the hiring as things stand at `now`, so the caller doesn't have to work it out again.
## Handed back in at the next settle with nothing changed in between (no player action), it also
## saves hiring again where the last settle ended: hiring twice in a row changes nothing and gives
## the same answers. A moment from any other time is simply not used.
static func settle(state: Dictionary, data: Dictionary, now: float, moment := {}) -> Dictionary:
	var known := moment.duplicate()
	moment.clear()
	var report := {}
	var grown := 0
	var wages := 0
	var water := 0
	var power := 0
	var rent := 0
	var life := {"born": 0, "grew_up": 0, "died": 0, "moved_away": 0, "left_for_work": 0}
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
			# People who just moved in, or posts that just opened (and huts). It also works out who
			# lives where and the power, which stay the same for this whole piece of time, so they are
			# worked out once here and handed on (each one walks every building).
			var hiring := known if steps == 1 and float(known.get("at", -INF)) == t else _hire(state, data, t)
			var homes: Dictionary = hiring.housing if not hiring.housing.is_empty() else housing(state, data, t)
			var homes_adults := adults(state)  # who lives where only changes if this does (see _settle_life)
			var e := employment(state, data, t)
			var happy := happiness(state, data, t, homes, e)
			_update_growth_speed(state, data, t, happy)  # happiness may have changed at this moment
			# Read every speed, the wage bill and the water use as they stand at the start of this
			# piece, before any building moves on (a building filling up changes the others' staffing).
			var speeds: Array[float] = []
			for b in state.buildings:
				speeds.append(building_speed(state, data, b, t))
			var wage_rate := _wages_per_hour(state, data, t)
			var water_m3_per_hour := public_water_use(state, data, t)  # own plants' water isn't billed
			var grid_mw := float(hiring.power.get("public", 0.0))  # nor is own plants' power (public_power_draw)
			var rent_rate := float(homes.rent_per_hour)
			var life_rates := _life_rates(state, data, t, happy, homes)
			var selling := selling_counts(state, data, t)  # stores selling each product share its shoppers
			var job_cap := _job_cap(state, data, t, e)  # job seekers come only for the posts open now
			# Split at the next staffing change, at the next birth, death or child growing up, and at
			# the next water bill (a fixed moment) when there is water to bill; empty cycles are
			# skipped in one go, so a long absence stays quick.
			var next := _next_staffing_change(state, data, t, now, e)
			next = minf(next, maxf(_next_life_event(state, data, t, life_rates), t + 0.000001))
			if water_m3_per_hour > 0.0 or float(water_meter(state, t).m3) > 0.0:
				next = minf(next, maxf(water_bill_due_at(state, data, t), t + 0.000001))
			if power_on(data) and (grid_mw > 0.0 or float(utility_meter(state, "power", t).mwh) > 0.0):
				next = minf(next, maxf(bill_due_at(state, data, "power", t), t + 0.000001))
			for i in state.buildings.size():
				_add_to(report, _settle_span(state, state.buildings[i], data, t, next, speeds[i], selling))
			wages += _pay_wages(state, wage_rate * (next - t) / 3600.0)
			rent += _collect_rent(state, rent_rate * (next - t) / 3600.0)
			_meter_use(state, data, "water", water_m3_per_hour * (next - t) / 3600.0, t)
			_meter_use(state, data, "power", grid_mw * (next - t) / 3600.0, t)
			grown += _grow_population(state, data, next, job_cap)
			_add_to(life, _settle_life(state, data, t, next, life_rates, homes, homes_adults, _leave_pool(happy), e))
			t = next
			water += _bill_if_due(state, data, "water", t)
			if power_on(data):
				power += _bill_if_due(state, data, "power", t)
		state["settled_at"] = now
	moment.merge(_hire(state, data, now), true)
	moment["at"] = now
	if rent > 0:
		report["rent"] = rent
	var counters := people_stats(state)
	counters.moved_in = int(counters.moved_in) + grown
	for key in life:
		if counters.has(key):  # left_for_work is only for the report: they're in moved_away too
			counters[key] = int(counters[key]) + int(life[key])
		if int(life[key]) > 0:
			report[key] = int(life[key])
	if grown > 0:
		report["population"] = grown
	if wages > 0:
		report["wages"] = wages
	if water > 0:
		report["water"] = water
	if power > 0:
		report["power"] = power
	_record_history(state, data, now)
	_record_money_log(state, data, now)
	return report


## Settles one building over [t0, t1] while it works at `speed` (1 = full speed). A building
## at 70% speed gets 70% of the time's work: it is settled up to t0 + 0.7 x (t1 - t0), then its
## current job's start is moved later by the other 30%, so at t1 it is exactly as far along as
## that work allows. An upgraded building above full speed (1.5) works the same way the other
## way round: settled up to t0 + 1.5 x (t1 - t0), then its job's start is moved earlier.
## `selling` = selling_counts at t0 (stores share a product's shoppers).
static func _settle_span(state: Dictionary, b: Dictionary, data: Dictionary, t0: float, t1: float, speed: float, selling: Dictionary) -> Dictionary:
	if data.buildings.get(b.type, {}).get("category", "") == "retail":
		return _settle_retail(state, data, b, t0, t1, speed, selling)  # sells, makes nothing
	if is_equal_approx(speed, 1.0) or float(b.job_started_at) > t0 or not batch_running(b):
		return _settle_one(state, b, data, t1)  # full speed, not started yet, or no batch to move along
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
## filled up or its last job is done (its workers wait, unpaid), or the next person moving in
## (hired straight away while posts are open; with needs switched on, every arrival can also
## change happiness, so the move-in speed). `e` = employment at t if already worked out.
static func _next_staffing_change(state: Dictionary, data: Dictionary, t: float, until: float, e := {}) -> float:
	var next := until
	for b in state.buildings:
		var finish := built_at(b)
		if finish > t and finish < next:
			next = finish
		if is_upgrading(b, t):  # the new level's posts or room count from then
			next = minf(next, float(b.upgrade_done_at))
		next = minf(next, maxf(_stop_time(state, data, b, t), t + 0.000001))
	var pop: Dictionary = state.population
	var step := _growth_step(state, data)
	if e.is_empty():
		e = employment(state, data, t)
	# Each arrival can change happiness (needs), and who lives where, so which homes use power.
	var arrival_matters: bool = e.open_jobs > 0 or _has_needs(data) or power_on(data)
	if not is_inf(step) and arrival_matters and adults(state) < mini(_arrival_room(state, data, t, true), _job_cap(state, data, t, e)):
		var arrival := float(pop.growth_anchor) + step * (floorf((t - float(pop.growth_anchor)) / step + 0.000001) + 1.0)
		if arrival > t and arrival < next:
			next = arrival
	return next


## Grows the population (people moving in: adults) up to `now`. A home finishing construction
## raises the room partway through, so grow up to each such moment with the room before it.
## The cap passed on is for everyone: today's children plus the room for adults, and never more
## adults than `job_cap` (see _job_cap; read at the start of the piece of time).
static func _grow_population(state: Dictionary, data: Dictionary, now: float, job_cap: int) -> int:
	var grown := 0
	var finishes: Array[float] = []
	for b in state.buildings:
		var t := built_at(b)
		if t > float(state.population.growth_anchor) and t <= now and is_real_home(data, b):
			finishes.append(t)
	finishes.sort()
	for t in finishes:
		grown += _settle_population(state, data, t, children_count(state) + mini(_arrival_room(state, data, t, false), job_cap))
	grown += _settle_population(state, data, now, children_count(state) + mini(_arrival_room(state, data, now, true), job_cap))
	return grown


const NO_LIMIT := 1 << 30


## The most adults people moving in may bring the village to. With move_in_only_for_jobs
## (game_config.json), newcomers are migrant workers: they only come for posts that are open and
## that no adult already here could take. Otherwise there's no limit but the homes.
## `e` = employment at t if already worked out.
static func _job_cap(state: Dictionary, data: Dictionary, t: float, e := {}) -> int:
	if not bool(data.config.get("move_in_only_for_jobs", false)):
		return NO_LIMIT
	if e.is_empty():
		e = employment(state, data, t)
	return adults(state) + jobs_waiting(e)


## Open jobs that no jobless adult already here could take: the jobs a migrant worker, or a child
## growing up, could get. `e` = employment().
static func jobs_waiting(e: Dictionary) -> int:
	return maxi(int(e.open_jobs) - int(e.unemployed), 0)


## The most adults the homes let move in: the room in real homes (see _adult_room for
## `inclusive`). Migrant workers who come only for jobs may come without a free home when
## move_in_needs_home is false: they live in Makeshift Huts (lowering the Housing need) until the
## player builds homes. The jobs still limit them (_job_cap).
static func _arrival_room(state: Dictionary, data: Dictionary, t: float, inclusive: bool) -> int:
	if bool(data.config.get("move_in_only_for_jobs", false)) and not bool(data.config.get("move_in_needs_home", true)):
		return NO_LIMIT
	return _adult_room(state, data, t, inclusive)


## settle_building, plus counting what was made for the statistics. Rules code uses this one.
static func _settle_one(state: Dictionary, b: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var produced := settle_building(b, data, now)
	_add_to(stats(state).made, produced)
	return produced


## Moves a building's work forward to `now`. Supermarkets only move inside settle(), which knows
## where each stretch of time starts (_settle_retail).
static func settle_building(b: Dictionary, data: Dictionary, now: float) -> Dictionary:
	if is_suspended(b):
		return {}  # switched off: nothing moves (resume starts its work afresh)
	if makes_batches(data, b):
		return _settle_batch(b, data, now)
	return {}


## A Farm, Mill or Bakery's batch (plan.md §5.1): counts the hours of work finished since the last
## settle and returns the units they made (for the statistics and the Welcome back window). The
## units wait in the batch until collected (ready_units). Progress comes only from timestamps:
## work done = now - job_started_at (moved later by _settle_span while short of workers), so being
## away is one calculation, and a clock set backwards never undoes finished hours.
static func _settle_batch(b: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var batch: Dictionary = b.get("batch", {})
	if batch.is_empty():
		return {}
	var hours := int(batch.hours)
	var done := int(batch.get("made_hours", 0))
	var recipe := _recipe(data.buildings.get(b.type, {}), batch.recipe_id)
	if done >= hours or recipe.is_empty():
		return {}
	var finished := clampi(floori((now - float(b.job_started_at)) / float(recipe.duration)), done, hours)
	if finished == done:
		return {}
	batch.made_hours = finished
	var produced := _units_after(batch, finished)
	_remove_from(produced, _units_after(batch, done))
	return produced


static func _settle_population(state: Dictionary, data: Dictionary, now: float, cap: int) -> int:
	var pop: Dictionary = state.population
	var step := _growth_step(state, data)
	if now < pop.growth_anchor:
		return 0
	if pop.current >= cap or is_inf(step):  # full, or nobody is moving in: the wait starts later
		pop.growth_anchor = now
		return 0
	# Each arrival moment brings a group (move_in_group_size), never more than the cap allows.
	# (The tiny extra stops rounding from losing a group that arrives exactly at `now`.)
	var moments := int((now - pop.growth_anchor) / step + 0.000001)
	var grown := mini(moments * _move_in_group(data), cap - int(pop.current))
	pop.current += grown
	if pop.current >= cap:
		pop.growth_anchor = now
	else:
		pop.growth_anchor += moments * step
	return grown


## The most adults who move in together at each arrival moment (game_config.json
## move_in_group_size; 1 when left out).
static func _move_in_group(data: Dictionary) -> int:
	return maxi(int(data.config.get("move_in_group_size", 1)), 1)


# --- Happiness (plan.md §5.6 "Needs & happiness") ------------------------------------
# Tropico-style, kept to group counts: each wealth class (Broke, Poor, Well off...) scores every
# need from 0 to 1 and mixes them with its own weights (happiness.class_weights; rich people care
# more about housing, poor people about food). The village's "needs met" is the classes' scores,
# weighted by how many people are in each. Happiness is needs met compared with what people
# expect, which rises as the village grows (happiness.expectations), and picks the band that sets
# births, migrants and people leaving (happiness.growth_speeds).
# Happiness is never stored: it's worked out from the state. Every input only changes at moments
# settling already splits on (people arriving, born, dying or leaving; a building finished,
# upgraded, staffed or switched off, and the power that goes with it; a shelf selling out; a player
# action), so time away stays one calculation.

## Needs the game scores by its own rules. Any other need (Health, Fun, Faith...) is met by
## service buildings ("service_need" in buildings.json); Safety is too, against crime.
const BUILT_IN_NEEDS := ["food", "jobs", "housing", "safety"]


## How the village feels and what that does to births, the move-in speed and people leaving:
## {"score" (0-1, what counts), "percent" (the score as shown: whole percent rounded DOWN, so
##  "19%" always means the band below 20%), "needs_met" (0-1, the classes' needs mixed),
##  "expected" (0-1, what people expect at this size), "cap" (happiness_cap: {"need", "max"} while
##  an unmet need limits it, e.g. no food: at most 40%; else {}), "next_expected" ({"people", "expected"}: the
##  next step up; {} after the last), "needs" ({need: 0-1} for the whole village),
##  "classes" ({class: {"people" (adults + their share of the children), "adults", "households",
##  "score", "needs" {need: 0-1}, "weights", ...the parts happiness_gains needs}}),
##  "foods" (different foods selling), "households", "homeless" (households in huts),
##  "unpowered" (households in homes without power), "crime" (0-1), "police" (0-1, how much of
##  it police keep down), "coverage" ({need: {"places",
##  "people", "quality"}} for needs met by service buildings), "jobless" (adults without a job),
##  "homeless_workers" (adults with a job living in huts), "growth_speed" (1.5 = babies come 1.5x
##  as fast, 0 = none), "move_in_speed" (migrant workers), "leave_per_hour" (share of ADULTS who
##  leave the island each hour, only the jobless; 0 when happy enough), "children_leave_per_hour",
##  "homeless_workers_leave" (true: adults in huts leave too, even with a job), "dev_locks"}.
## Without a "happiness" block in game_config.json there are no needs: score 1, speed 1.
## `homes` (housing) and `e` (employment) at `now` can be handed in when already worked out.
static func happiness(state: Dictionary, data: Dictionary, now: float, homes := {}, e := {}) -> Dictionary:
	var config: Dictionary = data.config.get("happiness", {})
	if e.is_empty():
		e = employment(state, data, now)
	if homes.is_empty():
		homes = housing(state, data, now)
	var locks := dev_locks(state)
	var people := int(e.population)
	var ids := need_ids(data)
	var parts := _happiness_walk(state, data, homes, now)
	# Needs that are the same for everyone: food on the shelves, service buildings, safety.
	var foods := foods_selling(state, data, now)
	var shared := {"food": _food_score(config, foods)}
	var coverage := {}
	for need in parts.places:
		coverage[need] = {"places": float(parts.places[need]), "people": people,
			"quality": float(parts.quality[need]) / float(parts.places[need]) if float(parts.places[need]) > 0.0 else 0.0}
	for need in ids:
		if not BUILT_IN_NEEDS.has(need):
			shared[need] = _covered(coverage, need, people)
	var crime := _crime(config, int(e.unemployed), int(e.adults), int(homes.homeless), int(homes.households))
	var police := _covered(coverage, "safety", people)
	shared["safety"] = 1.0 - crime * (1.0 - police)
	# Each class's own needs, and its score.
	var classes := {}
	var hut_quality := _hut_quality(data)
	for id in homes.classes:
		var c: Dictionary = homes.classes[id]
		var adults_here := int(c.adults)
		if adults_here <= 0:
			continue
		var households := int(c.households)
		var needs := {}
		for need in ids:
			if need == "jobs":
				needs[need] = float(c.get("job_quality", 0.0)) / adults_here
			elif need == "housing":
				needs[need] = (float(parts.home_quality.get(id, 0.0)) + int(c.homeless) * hut_quality) / households if households > 0 else 1.0
			else:
				needs[need] = float(shared.get(need, 1.0))
			needs[need] = float(locks.get(need, needs[need]))  # a developer lock replaces it for everyone
		var weights := _weights_for(config, id)
		classes[id] = {"people": adults_here + _children_share(int(e.children), households, int(homes.households)),
			"adults": adults_here, "households": households, "score": _class_score(weights, needs),
			"needs": needs, "weights": weights, "homeless": int(c.homeless), "workers": int(c.get("workers", 0)),
			"job_quality": float(c.get("job_quality", 0.0)), "home_quality": float(parts.home_quality.get(id, 0.0)),
			"unpowered_loss": float(parts.unpowered_loss.get(id, 0.0))}
	var village := _village_needs(classes, ids)
	var needs_met := _needs_met(classes)
	if classes.is_empty():
		# Nobody lives here: newcomers judge the village by what it offers (food, services), with
		# no jobs or homes lacking yet.
		for need in ids:
			village[need] = float(locks.get(need, shared.get(need, 1.0)))
		needs_met = _class_score(config.get("weights", {}), village)
	var expected := float(locks.get("expected", expected_happiness(config, people)))
	var cap := happiness_cap(config, village)
	var score := float(locks.get("score", _happiness_from(config, needs_met, expected, cap)))
	var jobless_class := wealth_class_of(data, 0.0)
	var homeless_workers := 0
	for id in homes.classes:
		if id != jobless_class:
			homeless_workers += int(homes.classes[id].get("homeless_adults", 0))
	var band := _band_for(config, score)
	var leave := float(band.get("leave_per_hour", 0.0))
	return {"score": score, "percent": happiness_percent(score), "needs_met": needs_met, "expected": expected,
		"cap": {} if locks.has("score") else cap,
		"next_expected": next_expectation(config, people), "needs": village, "classes": classes,
		"foods": foods, "households": int(homes.households), "homeless": int(homes.homeless),
		"unpowered": int(parts.unpowered), "crime": crime, "police": police, "coverage": coverage,
		"jobless": int(e.unemployed), "homeless_workers": homeless_workers,
		"growth_speed": float(band.get("speed", 1.0)),
		"move_in_speed": float(band.get("move_in", band.get("speed", 1.0))),
		"leave_per_hour": leave, "children_leave_per_hour": float(band.get("children_leave_per_hour", leave)),
		"homeless_workers_leave": bool(band.get("homeless_workers_leave", false)),
		"dev_locks": locks}


## The needs that count, in the order to show them: those in happiness.needs, then any other
## with a weight (happiness.weights or class_weights). A need nobody gives a weight doesn't count.
static func need_ids(data: Dictionary) -> Array:
	var config: Dictionary = data.config.get("happiness", {})
	var all: Array = config.get("needs", {}).keys()
	var weighted := {}
	for weights in [config.get("weights", {})] + config.get("class_weights", {}).values():
		for need in weights:
			if not all.has(need):
				all.append(need)
			if float(weights[need]) > 0.0:
				weighted[need] = true
	return all.filter(func(need): return weighted.has(need))


## A need's name on screen (happiness.needs[need].name; else the id, capitalised).
static func need_name(data: Dictionary, need: String) -> String:
	return str(data.config.get("happiness", {}).get("needs", {}).get(need, {}).get("name", need.capitalize()))


## One walk over the buildings for what happiness needs from them: {"home_quality" {class: sum
## of households x home quality}, "unpowered_loss" {class: the quality their homes lose for lack
## of power}, "unpowered" (households in homes without power), "places" {need: places in service
## buildings}, "quality" {need: places x their quality}}. `homes` = housing() at `now`.
static func _happiness_walk(state: Dictionary, data: Dictionary, homes: Dictionary, now: float) -> Dictionary:
	var out := {"home_quality": {}, "unpowered_loss": {}, "unpowered": 0, "places": {}, "quality": {}}
	for b in state.buildings:
		var home: Dictionary = homes.homes.get(b.id, {})
		if not home.is_empty() and home.has("classes"):  # a real home (huts have no "classes")
			var full := float(data.buildings.get(b.type, {}).get("housing_quality", 1.0))
			var quality := home_quality(data, b)
			for id in home.classes:
				var households := int(home.classes[id])
				out.home_quality[id] = float(out.home_quality.get(id, 0.0)) + households * quality
				out.unpowered_loss[id] = float(out.unpowered_loss.get(id, 0.0)) + households * (full - quality)
				if quality < full:
					out.unpowered = int(out.unpowered) + households
		var need := service_need(data, b)
		if need != "":
			var places := service_places(state, data, b, now)
			out.places[need] = float(out.places.get(need, 0.0)) + places
			out.quality[need] = float(out.quality.get(need, 0.0)) + places * service_quality(data, b)
	return out


## The Food need: happiness.needs.food.scores for that many different foods selling (the last
## number = that many or more). Without scores, food doesn't matter (1).
static func _food_score(config: Dictionary, foods: int) -> float:
	var scores: Array = config.get("needs", {}).get("food", {}).get("scores", [1.0])
	return float(scores[mini(foods, scores.size() - 1)]) if not scores.is_empty() else 1.0


## How good a home is to live in, 0-1: housing_quality in buildings.json (a home without one: 1),
## times happiness.needs.housing.unpowered while it needs power and has none.
static func home_quality(data: Dictionary, b: Dictionary) -> float:
	var quality := float(data.buildings.get(b.type, {}).get("housing_quality", 1.0))
	if power_need(data, b) > 0.0 and power_problem(b) != "":
		quality *= float(data.config.get("happiness", {}).get("needs", {}).get("housing", {}).get("unpowered", 1.0))
	return quality


## A Makeshift Hut's quality (its housing_quality; 0 without one): what a homeless household gets.
static func _hut_quality(data: Dictionary) -> float:
	var hut := hut_type_of(data)
	return float(data.buildings.get(hut, {}).get("housing_quality", 0.0)) if hut != "" else 0.0


## How good a job at this building is right now, 0-1: happiness.needs.jobs.quality for the wage
## bonus its workers are paid now (bonus_earned_now: None, Small, Good, Big; a bonus not listed,
## or no list at all: 1).
static func job_quality(data: Dictionary, b: Dictionary) -> float:
	return _job_quality_for(data.config.get("happiness", {}), bonus_earned_now(data, b))


static func _job_quality_for(config: Dictionary, bonus: String) -> float:
	return float(config.get("needs", {}).get("jobs", {}).get("quality", {}).get(bonus, 1.0))


## The need this service building meets ("service_need" in buildings.json; "" for any other).
static func service_need(data: Dictionary, b: Dictionary) -> String:
	return str(data.buildings.get(b.type, {}).get("service_need", ""))


## How good its service is, 0-1 ("service_quality"; 1 when left out).
static func service_quality(data: Dictionary, b: Dictionary) -> float:
	return float(data.buildings.get(b.type, {}).get("service_quality", 1.0))


## People this service building serves right now: its service_capacity (at its level) times the
## share of its workers who are working (2 of 4 = half). 0 while it's being built, suspended,
## without power or without workers.
static func service_places(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	var full := float(level_stat(data, b, "service_capacity", 0.0))
	if full <= 0.0 or not is_built(b, now) or not is_producing(data, b):
		return 0.0
	var most := max_workers(data, b)
	if most <= 0:
		return full
	return full * workers_working(state, data, b, now) / most


## A need met by service buildings, 0-1: the share of people they have places for (at most all),
## times the places' quality. No people: nobody goes without (1).
static func _covered(coverage: Dictionary, need: String, people: int) -> float:
	if people <= 0:
		return 1.0
	var c: Dictionary = coverage.get(need, {})
	return minf(float(c.get("places", 0.0)) / people, 1.0) * float(c.get("quality", 0.0))


## Crime, 0-1 (happiness.needs.safety): a base level, plus more for the share of adults without a
## job and the share of households in huts. Police (Safety service buildings) keep it down.
static func _crime(config: Dictionary, jobless: int, adults_now: int, homeless: int, households: int) -> float:
	var safety: Dictionary = config.get("needs", {}).get("safety", {})
	var crime := float(safety.get("crime", 0.0))
	if adults_now > 0:
		crime += float(safety.get("crime_per_jobless", 0.0)) * jobless / adults_now
	if households > 0:
		crime += float(safety.get("crime_per_homeless", 0.0)) * homeless / households
	return clampf(crime, 0.0, 1.0)


## A class's need weights: happiness.weights, with that class's own (class_weights) on top.
static func _weights_for(config: Dictionary, class_id: String) -> Dictionary:
	var weights: Dictionary = config.get("weights", {}).duplicate()
	weights.merge(config.get("class_weights", {}).get(class_id, {}), true)
	return weights


## The children counted with a class: their share of all children, by its households (children
## live with the households). Only used as a weight, so it may be a fraction.
static func _children_share(children: int, households: int, all_households: int) -> float:
	return children * float(households) / all_households if all_households > 0 else 0.0


## A class's needs mixed by its weights (shares of their total), 0-1. No weights: 1.
static func _class_score(weights: Dictionary, needs: Dictionary) -> float:
	var total := 0.0
	var weighted := 0.0
	for need in needs:
		var w := maxf(float(weights.get(need, 0.0)), 0.0)
		total += w
		weighted += w * float(needs[need])
	return clampf(weighted / total, 0.0, 1.0) if total > 0.0 else 1.0


## The village's needs met, 0-1: each class's score weighted by its people. Nobody: 1.
static func _needs_met(classes: Dictionary) -> float:
	var people := 0.0
	var weighted := 0.0
	for id in classes:
		people += float(classes[id].people)
		weighted += float(classes[id].people) * float(classes[id].score)
	return weighted / people if people > 0.0 else 1.0


## Each need for the whole village, 0-1: the classes' values weighted by their people.
static func _village_needs(classes: Dictionary, ids: Array) -> Dictionary:
	var out := {}
	for need in ids:
		var people := 0.0
		var weighted := 0.0
		for id in classes:
			people += float(classes[id].people)
			weighted += float(classes[id].people) * float(classes[id].needs.get(need, 1.0))
		out[need] = weighted / people if people > 0.0 else 1.0
	return out


## What people expect at this size, 0-1 (happiness.expectations: [{"people", "expected"}], people
## going up): in a straight line between the points, the last one's after it. None: 0.
static func expected_happiness(config: Dictionary, people: int) -> float:
	var points: Array = config.get("expectations", [])
	if points.is_empty():
		return 0.0
	var before: Dictionary = points[0]
	if people <= int(before.people):
		return float(before.expected)
	for point in points:
		if people <= int(point.people):
			var span := float(int(point.people) - int(before.people))
			var along := (people - int(before.people)) / span if span > 0.0 else 1.0
			return lerpf(float(before.expected), float(point.expected), along)
		before = point
	return float(before.expected)


## The next expectation point above this many people ({"people", "expected"}), or {} after the last.
static func next_expectation(config: Dictionary, people: int) -> Dictionary:
	for point in config.get("expectations", []):
		if int(point.people) > people and float(point.expected) > expected_happiness(config, people) + 0.000001:
			return {"people": int(point.people), "expected": float(point.expected)}
	return {}


## Happiness from needs met and expectations: content_at (0.5) when needs met equals what people
## expect, higher or lower by the difference (0-1). Without expectations: needs met itself.
## `cap` (happiness_cap) holds it down while a need it can't do without is unmet.
static func _happiness_from(config: Dictionary, needs_met: float, expected: float, cap := {}) -> float:
	var score := clampf(needs_met, 0.0, 1.0)
	if config.has("expectations"):
		score = clampf(float(config.get("content_at", 0.5)) + needs_met - expected, 0.0, 1.0)
	return minf(score, float(cap.max)) if not cap.is_empty() else score


## The lowest limit an unmet need puts on happiness: happiness.needs[need].max_happiness_when_unmet
## while that need is at 0 for the whole village (no food selling: at most 40%, whatever the other
## needs). {"need", "max"}, or {} while no such need is unmet. `village` = needs for the village.
static func happiness_cap(config: Dictionary, village: Dictionary) -> Dictionary:
	var cap := {}
	var needs: Dictionary = config.get("needs", {})
	for need in needs:
		if not needs[need].has("max_happiness_when_unmet") or float(village.get(need, 1.0)) > 0.000001:
			continue
		var most := float(needs[need].max_happiness_when_unmet)
		if cap.is_empty() or most < float(cap.max):
			cap = {"need": need, "max": most}
	return cap


## A happiness score as the whole percent shown on screen, rounded DOWN (0.196 -> 19), with the
## same tiny allowance as _band_for, so the shown number always falls in the band that counts.
static func happiness_percent(score: float) -> int:
	return floori(score * 100.0 + 0.0001)


## What each fix would add to happiness right now (0-1 each; 0 = nothing to gain), for the needs
## that count: "food" (one more different food selling), "jobs" (a job for every jobless adult),
## "housing" (a real home for every household in a hut), "power" (power for every home without),
## and each need met by service buildings, "safety" too (enough places for everyone, at the best
## quality buildable). A locked need gains nothing; all 0 while a developer lock decides the score.
## `happy` = happiness() now.
static func happiness_gains(data: Dictionary, happy: Dictionary) -> Dictionary:
	var config: Dictionary = data.config.get("happiness", {})
	var ids := need_ids(data)
	var gains := {}
	for need in ids:
		gains[need] = 0.0
	if ids.has("housing"):
		gains["power"] = 0.0
	var locks: Dictionary = happy.get("dev_locks", {})
	var classes: Dictionary = happy.get("classes", {})
	if locks.has("score") or classes.is_empty():
		return gains
	var fixes := _happiness_fixes(data, happy, ids)
	for fix in fixes:
		if not gains.has(fix):
			continue
		var changed := {}
		for id in classes:
			var needs: Dictionary = classes[id].needs.duplicate()
			var after: Dictionary = fixes[fix].get(id, {})
			for need in after:
				if needs.has(need) and not locks.has(need):
					needs[need] = maxf(float(needs[need]), float(after[need]))
			changed[id] = {"people": classes[id].people, "score": _class_score(classes[id].weights, needs), "needs": needs}
		var cap := happiness_cap(config, _village_needs(changed, ids))  # e.g. one food lifts the no-food limit
		var score := _happiness_from(config, _needs_met(changed), float(happy.expected), cap)
		gains[fix] = maxf(score - float(happy.score), 0.0)
	return gains


## What each fix (see happiness_gains) would make each class's needs: {fix: {class: {need: value}}}.
static func _happiness_fixes(data: Dictionary, happy: Dictionary, ids: Array) -> Dictionary:
	var config: Dictionary = data.config.get("happiness", {})
	var classes: Dictionary = happy.classes
	var crime := float(happy.get("crime", 0.0))
	var police := float(happy.get("police", 0.0))
	var adults_now := 0
	for id in classes:
		adults_now += int(classes[id].adults)
	# Jobs for everyone also takes away the crime that joblessness brings.
	var per_jobless := float(config.get("needs", {}).get("safety", {}).get("crime_per_jobless", 0.0))
	var crime_after_jobs := clampf(crime - per_jobless * int(happy.jobless) / maxf(adults_now, 1.0), 0.0, 1.0)
	var job_none := _job_quality_for(config, "none")
	var food := _food_score(config, int(happy.foods) + 1)
	var best_police := _best_service_quality(data, "safety")
	var cheapest_home := _cheapest_home_quality(data)
	var hut := _hut_quality(data)
	var fixes := {"food": {}, "jobs": {}, "housing": {}, "power": {}, "safety": {}}
	var best_service := {}  # need -> the best quality buildable for it
	for need in ids:
		if not BUILT_IN_NEEDS.has(need):
			fixes[need] = {}
			best_service[need] = _best_service_quality(data, need)
	for id in classes:
		var c: Dictionary = classes[id]
		var households := int(c.households)
		fixes.food[id] = {"food": food}
		fixes.jobs[id] = {"jobs": (float(c.job_quality) + (int(c.adults) - int(c.workers)) * job_none) / int(c.adults),
			"safety": 1.0 - crime_after_jobs * (1.0 - police)}
		if households > 0:
			fixes.housing[id] = {"housing": (float(c.home_quality) + int(c.homeless) * cheapest_home) / households}
			fixes.power[id] = {"housing": (float(c.home_quality) + float(c.unpowered_loss) + int(c.homeless) * hut) / households}
		fixes.safety[id] = {"safety": 1.0 - crime * (1.0 - best_police)}
		for need in best_service:
			fixes[need][id] = {need: best_service[need]}
	return fixes


## The quality of the cheapest kind of real home the player can build (the lowest
## housing_quality; 1 when no home sets one): what moving out of a hut would at least give.
static func _cheapest_home_quality(data: Dictionary) -> float:
	var lowest := INF
	for type_id in data.buildings:
		var def: Dictionary = data.buildings[type_id]
		if bool(def.get("buildable", false)) and int(def.get("households", 0)) > 0 and not bool(def.get("hut", false)):
			lowest = minf(lowest, float(def.get("housing_quality", 1.0)))
	return lowest if lowest < INF else 1.0


## The best quality of service the player can build for `need` (0 when nothing buildable meets it).
static func _best_service_quality(data: Dictionary, need: String) -> float:
	var best := 0.0
	for type_id in data.buildings:
		var def: Dictionary = data.buildings[type_id]
		if bool(def.get("buildable", false)) and str(def.get("service_need", "")) == need:
			best = maxf(best, float(def.get("service_quality", 1.0)))
	return best


## The building type that meets `need` (the first buildable one in buildings.json), or "".
static func service_building_for(data: Dictionary, need: String) -> String:
	for type_id in data.buildings:
		var def: Dictionary = data.buildings[type_id]
		if bool(def.get("buildable", false)) and str(def.get("service_need", "")) == need:
			return type_id
	return ""


## Different foods on sale right now: on a shelf of a store that is selling (built, not
## suspended, with at least one worker). A store with nobody working feeds nobody. Only food
## counts (is_food): clothes or furniture on a shelf don't feed anyone.
static func foods_selling(state: Dictionary, data: Dictionary, now: float) -> int:
	var foods := 0
	for res in selling_counts(state, data, now):
		if is_food(data, res):
			foods += 1
	return foods


## How many stores are selling each product right now: {resource_id: stores}. Only stores that
## are selling count (built, not suspended, with at least one worker). The village's appetite for a
## product is shared between them (plan.md §5.16): 2 stores selling flour each sell it half as fast.
static func selling_counts(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var counts := {}
	for b in state.buildings:
		if data.buildings.get(b.type, {}).get("category", "") != "retail" or building_speed(state, data, b, now) <= 0.0:
			continue
		for shelf in b.get("shelves", []):
			if not shelf.is_empty():
				counts[shelf.res] = int(counts.get(shelf.res, 0)) + 1
	return counts


## This store's share of the village's shoppers for `resource_id` (1 = it sells it alone).
static func _demand_share(selling: Dictionary, resource_id: String) -> float:
	return 1.0 / maxi(int(selling.get(resource_id, 1)), 1)


## True when game_config.json switches needs on (a "happiness" block).
static func _has_needs(data: Dictionary) -> bool:
	return not data.config.get("happiness", {}).is_empty()


## The happiness band a score falls in: the highest band it reaches (happiness.growth_speeds,
## "from" going up): {"from", "speed", "leave_per_hour"}. No bands = {} (normal speed, nobody leaves).
static func _band_for(config: Dictionary, score: float) -> Dictionary:
	var found := {}
	for band in config.get("growth_speeds", []):
		if score + 0.000001 >= float(band.from):  # the tiny allowance: 0.3 + 0.5 must reach 0.8
			found = band
	return found


## Seconds between people moving in at the move-in speed in force (INF = nobody moves in).
static func _growth_step(state: Dictionary, data: Dictionary) -> float:
	var base := float(data.config.population_growth_seconds)
	var speed := _move_in_speed(state.population)
	if base <= 0.0 or speed <= 0.0:
		return INF
	return base / speed


## The move-in speed in force (saves from before it had its own number use the birth speed).
static func _move_in_speed(pop: Dictionary) -> float:
	return float(pop.get("move_in_speed", pop.get("growth_speed", 1.0)))


## Happiness only changes at moments settling splits on (a shelf sells out, a person moves in, a
## building finishes or changes workers, a player action), so the birth and move-in speeds are
## read at the start of each piece of time. When the move-in speed changes, the wait for the next
## person starts again from t. `happy` = happiness at t if already worked out.
static func _update_growth_speed(state: Dictionary, data: Dictionary, t: float, happy := {}) -> void:
	var pop: Dictionary = state.population
	if happy.is_empty():
		happy = happiness(state, data, t)
	var move_in := float(happy.move_in_speed)
	if not is_equal_approx(move_in, _move_in_speed(pop)):
		pop.growth_anchor = maxf(float(pop.growth_anchor), t)
	pop["move_in_speed"] = move_in
	pop["growth_speed"] = float(happy.growth_speed)


# --- Births, children & deaths (plan.md §5.6) ------------------------------------------
# People are kept as group counts, not individuals. population.current is everyone; the
# children are age groups {count, grows_up_at} (oldest first); everyone else is an adult.
# Births and deaths come at a steady rate with part-people carried over (like part-cents of
# wages), so they happen at predictable moments and time away stays one calculation.

## Adults: everyone who isn't a child. Only adults work and have babies.
static func adults(state: Dictionary) -> int:
	return int(state.population.current) - children_count(state)


static func children_count(state: Dictionary) -> int:
	var total := 0
	for group in state.population.get("children", []):
		total += int(group.count)
	return total


## The children's age groups, oldest first: [{"count", "grows_up_at"}]. Read it; don't change it.
static func children_groups(state: Dictionary) -> Array:
	return state.population.get("children", [])


## The lifetime counters of who came and went, in this order.
const PEOPLE_COUNTERS := ["moved_in", "born", "grew_up", "died", "moved_away"]


## Lifetime counters of who came and went: {"moved_in", "born", "grew_up", "died", "moved_away"}.
## Counters an older save doesn't have yet start at 0.
static func people_stats(state: Dictionary) -> Dictionary:
	var s := stats(state)
	if not s.has("people"):
		s["people"] = {}
	for key in PEOPLE_COUNTERS:
		if not s.people.has(key):
			s.people[key] = 0
	return s.people


## Births, deaths and people leaving, per second, as things stand at t: {"born",
## "adult_deaths", "child_deaths", "adult_leaves", "child_leaves"}. Babies come from all adults,
## at the speed happiness gives, and only while a family has a free child place (2 per
## household; a house isn't needed, families in huts have babies too). Everyone dies at the same steady
## rate, so adults and children each lose their share. In an unhappy village people leave the
## island in groups (life_group_size): adults at happiness leave_per_hour, but only while someone
## may leave (_leave_pool: the jobless; at the lowest happiness also workers living in huts), and
## children at children_leave_per_hour. Births and deaths are all 0
## without a "life" block in game_config.json. `happy` (happiness) and `homes` (housing) at t can be
## handed in when already worked out.
static func _life_rates(state: Dictionary, data: Dictionary, t: float, happy := {}, homes := {}) -> Dictionary:
	var life: Dictionary = data.config.get("life", {})
	var rates := {"born": 0.0, "adult_deaths": 0.0, "child_deaths": 0.0, "adult_leaves": 0.0, "child_leaves": 0.0}
	if _has_needs(data):
		if happy.is_empty():
			happy = happiness(state, data, t, homes)
		if _leave_pool(happy) > 0:
			rates.adult_leaves = adults(state) * float(happy.leave_per_hour) / 3600.0
		rates.child_leaves = children_count(state) * float(happy.children_leave_per_hour) / 3600.0
	if life.is_empty():
		return rates
	if homes.is_empty():
		homes = housing(state, data, t)
	if children_count(state) < int(homes.child_places):
		rates.born = adults(state) * float(life.get("birth_rate_per_hour", 0.0)) * float(state.population.get("growth_speed", 1.0)) / 3600.0
	var death := float(life.get("death_rate_per_hour", 0.0)) / 3600.0
	rates.adult_deaths = adults(state) * death
	rates.child_deaths = children_count(state) * death
	return rates


## The most adults who may leave the island now (`happy` = happiness then): the jobless, and at
## the lowest happiness (the band's homeless_workers_leave) also the workers living in huts.
## Workers with a real home never leave. While it's 0, nobody leaves however unhappy.
static func _leave_pool(happy: Dictionary) -> int:
	var pool := int(happy.get("jobless", 0))
	if bool(happy.get("homeless_workers_leave", false)):
		pool += int(happy.get("homeless_workers", 0))
	return pool


## Part-people of births and deaths not yet happened: {"born", "adult_deaths", "child_deaths"}.
static func _life_carry(state: Dictionary) -> Dictionary:
	if not state.population.has("life_carry"):
		state.population["life_carry"] = {}
	return state.population.life_carry


## How many people one event of `key` (a key of _life_rates) moves at once: people leaving the
## island go in groups of happiness.leave_group_size (1 when left out); births and deaths one by one.
## Their part-people carry fills up to this size before anyone goes.
static func life_group_size(data: Dictionary, key: String) -> int:
	if key == "adult_leaves" or key == "child_leaves":
		return maxi(int(data.config.get("happiness", {}).get("leave_group_size", 1)), 1)
	return 1


## The next birth, death, group leaving or child growing up after t, at `rates` (INF if none is coming).
static func _next_life_event(state: Dictionary, data: Dictionary, t: float, rates: Dictionary) -> float:
	var next := INF
	var carry := _life_carry(state)
	for key in rates:
		if float(rates[key]) > 0.0:
			var group := float(life_group_size(data, key))
			next = minf(next, t + maxf(group - float(carry.get(key, 0.0)), 0.0) / float(rates[key]) + 0.000001)
	var groups := children_groups(state)
	if not groups.is_empty() and float(groups[0].grows_up_at) > t:
		next = minf(next, float(groups[0].grows_up_at))
	return next


## Over [t0, t1] at `rates` (read at t0; settling ends the piece at the next event, so they can't
## change midway): children whose time has come grow up, then deaths, then people leaving (a whole
## group at once), then births. Adults who die or leave are simply gone (hiring then frees a post, the unemployed
## first, so the homeless are the first to go); a child is taken from the youngest group; a baby
## joins the age group of its hour. With life.grown_ups_leave_without_job, a child growing up
## with no job waiting (jobs_waiting) leaves the island to find work instead of staying jobless.
## Returns {"born", "grew_up", "died", "moved_away", "left_for_work" (the part of moved_away that
## left on growing up)}.
## `homes` = housing at t0 (after hiring) and `homes_adults` = the adults then: births need the
## child places of t1, which are still those of t0 as long as the number of adults is the same
## (nobody is hired or let go in between; only households, made of adults, decide them).
## `leave_cap` = _leave_pool at t0: never more adults leave than that, less those who just died
## (deaths take the jobless first too). `e` = employment at t0 (after hiring), if worked out.
static func _settle_life(state: Dictionary, data: Dictionary, t0: float, t1: float, rates: Dictionary, homes := {}, homes_adults := -1, leave_cap := NO_LIMIT, e := {}) -> Dictionary:
	var out := {"born": 0, "grew_up": 0, "died": 0, "moved_away": 0, "left_for_work": 0}
	var pop: Dictionary = state.population
	if not pop.has("children"):
		pop["children"] = []
	var groups: Array = pop.children
	var waiting := _jobs_for_grown_ups(state, data, t0, t1, e)
	while not groups.is_empty() and float(groups[0].grows_up_at) <= t1:
		var grown := int(groups[0].count)  # they're adults now: still counted in current
		out.grew_up += grown
		groups.pop_front()
		if waiting >= 0:  # only the ones a job is waiting for stay
			var gone := maxi(grown - waiting, 0)
			waiting -= grown - gone
			pop.current = int(pop.current) - gone
			out.moved_away += gone
			out.left_for_work += gone
	var carry := _life_carry(state)
	var events := {}
	for key in rates:
		# Whole groups only: people leaving wait until a full group is ready (life_group_size).
		var group := life_group_size(data, key)
		var total := float(carry.get(key, 0.0)) + float(rates[key]) * (t1 - t0)
		events[key] = floori(total / group + 0.000001) * group
		carry[key] = maxf(total - events[key], 0.0)
	var adult_deaths := mini(int(events.adult_deaths), adults(state))
	pop.current = int(pop.current) - adult_deaths
	out.died = adult_deaths + _remove_children(state, int(events.child_deaths))
	var adults_leaving := mini(int(events.get("adult_leaves", 0)), mini(adults(state), maxi(leave_cap - adult_deaths, 0)))
	pop.current = int(pop.current) - adults_leaving
	out.moved_away += adults_leaving + _remove_children(state, int(events.get("child_leaves", 0)))
	var life: Dictionary = data.config.get("life", {})
	if homes.is_empty() or adults(state) != homes_adults:
		homes = housing(state, data, t1)
	var born := mini(int(events.born), maxi(int(homes.child_places) - children_count(state), 0))
	if born > 0:
		var group_seconds := maxf(float(life.get("child_group_hours", 1.0)), 0.001) * 3600.0
		var grows_up_at := floorf(t1 / group_seconds) * group_seconds + float(life.get("grow_up_hours", 24.0)) * 3600.0
		if not groups.is_empty() and is_equal_approx(float(groups[-1].grows_up_at), grows_up_at):
			groups[-1].count = int(groups[-1].count) + born
		else:
			groups.append({"count": born, "grows_up_at": grows_up_at})
		pop.current = int(pop.current) + born
		out.born = born
	return out


## How many children growing up over [t0, t1] may stay (life.grown_ups_leave_without_job): the
## jobs waiting at t0 for them, less any migrant worker who arrived during the piece (not hired
## until the next one). -1 = everyone stays (the rule is off, or nobody grows up then).
## `e` = employment at t0 (after hiring), if worked out.
static func _jobs_for_grown_ups(state: Dictionary, data: Dictionary, t0: float, t1: float, e := {}) -> int:
	var groups: Array = state.population.children
	if groups.is_empty() or float(groups[0].grows_up_at) > t1:
		return -1
	if not bool(data.config.get("life", {}).get("grown_ups_leave_without_job", false)):
		return -1
	if e.is_empty():
		e = employment(state, data, t0)
	var jobless_now := adults(state) - int(e.employed)  # the jobless at t0 plus migrants since
	return maxi(int(e.open_jobs) - jobless_now, 0)


## Takes up to n children away, youngest group first (they died). Returns how many were taken.
static func _remove_children(state: Dictionary, n: int) -> int:
	var groups: Array = state.population.get("children", [])
	var taken := 0
	while taken < n and not groups.is_empty():
		var take := mini(n - taken, int(groups[-1].count))
		groups[-1].count = int(groups[-1].count) - take
		taken += take
		if int(groups[-1].count) <= 0:
			groups.pop_back()
	state.population.current = int(state.population.current) - taken
	return taken


## When the next baby is born (INF when none is coming: every family has 2 children, no adults, too
## unhappy, or no births in this game). Counted from the last settle, which happens every few
## seconds.
static func next_birth_at(state: Dictionary, data: Dictionary, now: float) -> float:
	var t := float(state.get("settled_at", now))
	var rate := float(_life_rates(state, data, t).born)
	if rate <= 0.0:
		return INF
	return t + maxf(1.0 - float(_life_carry(state).get("born", 0.0)), 0.0) / rate


# --- Housing: households, wealth & rent (plan.md §5.18) --------------------------------
# Still group counts, never individuals: who lives where is worked out from the counts each
# time (housing()), so nothing can drift. Only the Makeshift Huts are stored, because they
# stand on the map.

## Up to this many adults (and children) share a household (game_config.json housing).
static func adults_per_household(data: Dictionary) -> int:
	return maxi(int(data.config.get("housing", {}).get("adults_per_household", 2)), 1)


static func children_per_household(data: Dictionary) -> int:
	return maxi(int(data.config.get("housing", {}).get("children_per_household", 2)), 0)


## Households this home has room for (0 = not a home).
static func home_households(data: Dictionary, b: Dictionary) -> int:
	return int(level_stat(data, b, "households", 0))


## A Makeshift Hut: it appears by itself for a homeless household (see _update_huts).
static func is_hut(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("hut", false))


## A home the player builds (not a hut).
static func is_real_home(data: Dictionary, b: Dictionary) -> bool:
	return home_households(data, b) > 0 and not is_hut(data, b)


## Room for adults in finished real homes at `now` (huts left out: they only shelter the homeless).
static func adult_room(state: Dictionary, data: Dictionary, now: float) -> int:
	return _adult_room(state, data, now, true)


## inclusive = false leaves out homes finishing exactly at t (the room just before that moment).
static func _adult_room(state: Dictionary, data: Dictionary, t: float, inclusive: bool) -> int:
	return _real_households(state, data, t, inclusive) * adults_per_household(data)


## Households the finished real homes have room for at t (see _adult_room for `inclusive`).
static func _real_households(state: Dictionary, data: Dictionary, t: float, inclusive: bool) -> int:
	var households := 0
	for b in state.buildings:
		if is_real_home(data, b) and (built_at(b) < t or (inclusive and built_at(b) == t)):
			households += home_households(data, b)
	return households


## The wealth classes, poorest first: [{"id", "name", "from_wage"}] (game_config.json housing).
static func wealth_classes(data: Dictionary) -> Array:
	return data.config.get("housing", {}).get("wealth_classes", [])


## The wealth class of someone earning `wage` dollars an hour (0 = no job): the richest class
## whose from_wage it reaches. "" when the game has no wealth classes.
static func wealth_class_of(data: Dictionary, wage: float) -> String:
	var id := ""
	for c in wealth_classes(data):
		if wage + 0.000001 >= float(c.from_wage):
			id = str(c.id)
	return id


## Adults by wealth class, poorest first: {class: {"adults", "wages" (dollars an hour, all of
## them together), "workers" (adults with a job), "job_quality" (their jobs' quality added up,
## see job_quality)}}. A worker's class comes from the wage they earn now (wage_earned_now: an
## idle farm's next-batch bonus doesn't count); no job = Broke.
static func adults_by_class(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var out := {}
	for c in wealth_classes(data):
		out[str(c.id)] = {"adults": 0, "wages": 0.0, "workers": 0, "job_quality": 0.0}
	var jobless := wealth_class_of(data, 0.0)
	if not out.has(jobless):
		out[jobless] = {"adults": 0, "wages": 0.0, "workers": 0, "job_quality": 0.0}
	var employed := 0
	for b in state.buildings:
		if hired(b) <= 0:
			continue  # nobody works there (most buildings of a big village are homes)
		var n := mini(hired(b), posts(data, b, now))
		if n <= 0:
			continue
		var wage := wage_earned_now(data, b)
		var group: Dictionary = out.get(wealth_class_of(data, wage), out[jobless])
		group.adults = int(group.adults) + n
		group.wages = float(group.wages) + n * wage
		group.workers = int(group.workers) + n
		group.job_quality = float(group.job_quality) + n * job_quality(data, b)
		employed += n
	out[jobless].adults = int(out[jobless].adults) + maxi(adults(state) - employed, 0)
	return out


## Rent per household per hour (dollars) for a home type: the developer's override if one is set
## (dev_set_rent), else rent_per_household in buildings.json.
static func rent_per_household(state: Dictionary, data: Dictionary, type_id: String) -> float:
	var dev: Dictionary = state.get("dev_rent", {})
	if dev.has(type_id):
		return float(dev[type_id])
	return float(data.buildings.get(type_id, {}).get("rent_per_household", 0.0))


## Whether a household of wealth class `id` may live in this home ("wealth" in buildings.json;
## none listed = anyone).
static func _may_live(data: Dictionary, b: Dictionary, id: String) -> bool:
	var allowed: Array = data.buildings.get(b.type, {}).get("wealth", [])
	return allowed.is_empty() or id == "" or allowed.has(id)


## Who lives where right now (plan.md §5.18). Each class's households (adults paired up, richest
## class first) take the best homes meant for them that they can afford (rent at most
## housing.rent_share of the household's wages): highest housing_tier first, then the oldest
## home. Then any household still without a home takes any leftover home it can afford (a Well
## off household in Public Housing rather than on the street), so the classes a home is meant
## for get first claim on it. Households left over are homeless and live in Makeshift Huts.
## Children live with the households in real homes first (2 places each). Returns:
## {"homes": {building_id: {"households", "adults", "children", "rent" (dollars an hour),
##   "classes" {class: households}; a hut has no "classes"}},
##  "classes": {class: {"households", "adults", "homeless" (households), "homeless_adults",
##   "workers", "job_quality" (see adults_by_class)}},
##  "homeless" (households),
##  "rent_per_hour" (dollars), "child_places" (2 per household, house or hut alike),
##  "power_mw" (homes lived in), "households" (all)}.
static func housing(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var per_household := adults_per_household(data)
	var share := float(data.config.get("housing", {}).get("rent_share", 1.0))
	# Real homes, best first: highest tier, then the oldest (lowest place in the list).
	var order: Array = []
	for i in state.buildings.size():
		var b: Dictionary = state.buildings[i]
		if is_real_home(data, b) and is_built(b, now):
			order.append([int(data.buildings[b.type].get("housing_tier", 0)), i])
	order.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	var homes := {}
	var free := {}
	for entry in order:
		var b: Dictionary = state.buildings[entry[1]]
		homes[b.id] = {"households": 0, "adults": 0, "children": 0, "rent": 0.0, "classes": {}}
		free[b.id] = home_households(data, b)
	var out := {"homes": homes, "classes": {}, "homeless": 0, "rent_per_hour": 0.0, "child_places": 0,
		"power_mw": 0.0, "households": 0}
	var by_class := adults_by_class(state, data, now)
	var ids: Array = by_class.keys()
	ids.reverse()  # richest first
	var left := {}  # class -> [households, adults] still without a home
	var income := {}  # class -> wages per household (dollars an hour)
	for id in ids:
		var households := ceili(int(by_class[id].adults) / float(per_household))
		left[id] = [households, int(by_class[id].adults)]
		income[id] = float(by_class[id].wages) / households if households > 0 else 0.0
		out.classes[id] = {"households": households, "adults": int(by_class[id].adults), "homeless": 0,
			"workers": int(by_class[id].get("workers", 0)), "job_quality": float(by_class[id].get("job_quality", 0.0))}
		out.households += households
	for any_home in [false, true]:  # first homes meant for them, then any leftover home
		for id in ids:
			for entry in order:
				if int(left[id][0]) <= 0:
					break
				var b: Dictionary = state.buildings[entry[1]]
				var rent := rent_per_household(state, data, b.type)
				if int(free[b.id]) <= 0 or (not any_home and not _may_live(data, b, id)) or rent > share * float(income[id]) + 0.000001:
					continue
				var take := mini(int(left[id][0]), int(free[b.id]))
				var moved_in := mini(int(left[id][1]), take * per_household)  # full households first
				homes[b.id].households += take
				homes[b.id].adults += moved_in
				homes[b.id].classes[id] = int(homes[b.id].classes.get(id, 0)) + take
				homes[b.id].rent += take * rent
				free[b.id] = int(free[b.id]) - take
				left[id] = [int(left[id][0]) - take, int(left[id][1]) - moved_in]
				out.rent_per_hour += take * rent
	var homeless_adults := 0
	for id in ids:
		out.classes[id].homeless = int(left[id][0])
		out.classes[id].homeless_adults = int(left[id][1])
		out.homeless += int(left[id][0])
		homeless_adults += int(left[id][1])
	# Children: 2 places in every household, house or hut. They fill the real homes first; any
	# others live with the homeless.
	out.child_places = int(out.households) * children_per_household(data)
	var children_left := children_count(state)
	for entry in order:
		var b: Dictionary = state.buildings[entry[1]]
		var places := int(homes[b.id].households) * children_per_household(data)
		homes[b.id].children = mini(children_left, places)
		children_left -= int(homes[b.id].children)
		if int(homes[b.id].households) > 0:
			out.power_mw += float(data.buildings[b.type].get("power_mw", 0.0))
	# The homeless, one household per hut (oldest hut first).
	var homeless := int(out.homeless)
	for b in state.buildings:
		if not is_hut(data, b) or homeless <= 0:
			continue
		var adults_here := mini(homeless_adults, per_household)
		var children_here := mini(children_left, children_per_household(data))
		homes[b.id] = {"households": 1, "adults": adults_here, "children": children_here, "rent": 0.0}
		homeless -= 1
		homeless_adults -= adults_here
		children_left -= children_here
	return out


## Makeshift Huts appear by themselves, one for each homeless household, and go once their
## household has a real home, newest first (plan.md §5.18). A new hut goes on the free tile
## nearest City Hall, in a fixed order (no dice). With no hut type in
## buildings.json, or no free tile left, the homeless have no hut.
## Returns who lives where at `now` (housing) when that is still true afterwards, so _hire can
## hand it on; {} when huts came or went (or it looked at another moment).
static func _update_huts(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var hut_type := hut_type_of(data)
	if hut_type == "":
		return {}
	# A clock set backwards never undoes time already worked out: use the later of the two.
	var at := maxf(now, float(state.get("settled_at", now)))
	var homes := housing(state, data, at)
	var homeless := int(homes.homeless)
	_move_huts_off_hub(state, data, hut_type)
	var huts: Array = state.buildings.filter(func(b): return is_hut(data, b))
	if huts.size() != homeless:
		homes = {}
	while huts.size() > homeless:
		state.buildings.erase(huts.pop_back())
	while huts.size() < homeless:
		var cell := _free_spot_near_centre(state, data, hut_type)
		if cell.x < 0:
			return {}  # the plot is full
		huts.append(_add_building(state, hut_type, cell, now, now))
	return homes if at == now else {}


## A hut right beside City Hall would block its roads (plan.md §5.20): such huts
## move to the next free tile (older saves; new huts never go there).
static func _move_huts_off_hub(state: Dictionary, data: Dictionary, hut_type: String) -> void:
	if not roads_on(data):
		return
	var hubs := _hub_cells(state, data)
	for b in state.buildings:
		if b.type == hut_type and _beside(hubs, cells_of(data, b)):
			var cell := _free_spot_near_centre(state, data, hut_type)
			if cell.x >= 0:
				b.position = [cell.x, cell.y]


## The tiles the road hub (City Hall) stands on: Vector2i -> true.
static func _hub_cells(state: Dictionary, data: Dictionary) -> Dictionary:
	var hubs := {}
	for b in state.buildings:
		if is_road_hub(data, b):
			for cell in cells_of(data, b):
				hubs[cell] = true
	return hubs


## The free spot for a building of `type_id` nearest City Hall (or the middle of the plot), ring
## by ring, in a fixed order, but never right beside City Hall, where its roads start. A spot is
## the building's position: its whole footprint must be free. (-1, -1) when there's no room.
static func _free_spot_near_centre(state: Dictionary, data: Dictionary, type_id: String) -> Vector2i:
	var grid: Array = state.plot.grid_size
	var centre := Vector2i(floori(int(grid[0]) / 2.0), floori(int(grid[1]) / 2.0))
	for b in state.buildings:
		if data.buildings.get(b.type, {}).get("category", "") == "civic":
			centre = Vector2i(int(b.position[0]), int(b.position[1]))
			break
	var hubs := _hub_cells(state, data)
	var map := _plot_map(state, data)
	for ring in range(1, maxi(int(grid[0]), int(grid[1])) + 1):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var cell := centre + Vector2i(dx, dy)
				if _footprint_problem(state, data, type_id, cell, "", map) == "" and not (roads_on(data) and _beside(hubs, footprint(data, type_id, cell))):
					return cell
	return Vector2i(-1, -1)


## Rent comes in over time like wages go out: parts of a cent wait in "rent_carry" until they add
## up, so many short settles earn exactly the same as one long one. Counted as income "rent".
## Returns the cents earned.
static func _collect_rent(state: Dictionary, dollars: float) -> int:
	if dollars <= 0.0:
		return 0
	var owed := float(state.get("rent_carry", 0.0)) + dollars * 100.0
	var whole := floori(owed)
	state["rent_carry"] = owed - whole
	state.profile.currency += whole
	var income: Dictionary = stats(state).income
	income["rent"] = int(income.get("rent", 0)) + whole
	return whole


# --- Player actions -----------------------------------------------------------

## Whether a building could go on this cell right now (changes nothing). Also returns what it
## would cost at `now`'s prices: "cost" (cents), "seconds", "lines" (see construction_plan: the
## warehouse's own materials are used first).
## The placement preview uses this too, so preview and real build always agree.
static func can_build(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i, now: float) -> Dictionary:
	var def: Dictionary = data.buildings.get(type_id, {})
	if def.has("coming_soon"):
		return _fail(str(def.coming_soon))
	if def.is_empty() or not def.get("buildable", false):
		return _fail("This building can't be built.")
	if at_build_limit(state, data, type_id):
		return _fail("You can have only %d %s." % [int(def.max_count), def.get("name", "of these")] if int(def.max_count) != 1 else "You already have a %s: one is all you need." % def.get("name", "building"))
	var problem := _footprint_problem(state, data, type_id, cell)
	if problem != "":
		return _fail(problem)
	var crew := _check_crew(state, data, int(construction_needs(data, type_id, 1).crew), now)
	if not crew.is_empty():
		return crew
	var quote := construction_plan(state, data, type_id, 1, now)
	if state.profile.currency < int(quote.cost):
		return _fail("Not enough money.")
	return _ok(quote)


## True when the village already has as many of this building as it may ("max_count" in
## buildings.json; the Trading Post: 1). Ones still being built count too.
static func at_build_limit(state: Dictionary, data: Dictionary, type_id: String) -> bool:
	var def: Dictionary = data.buildings.get(type_id, {})
	if not def.has("max_count"):
		return false
	var have := 0
	for b in state.buildings:
		have += 1 if b.type == type_id else 0
	return have >= int(def.max_count)


## Build: take the materials the warehouse has, buy the rest, and pay its crew now
## (construction_plan); it's ready after the construction time.
static func build(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i, now: float) -> Dictionary:
	var check := can_build(state, data, type_id, cell, now)
	if not check.ok:
		return check
	settle(state, data, now)  # time so far was worked with the old staffing
	# Check again: while catching up, a Makeshift Hut may have gone up on that very tile, or
	# wages may have used up the money.
	check = can_build(state, data, type_id, cell, now)
	if not check.ok:
		return check
	state.profile.currency -= int(check.cost)
	stats(state).spending.construction += int(check.cost)
	var b := _add_building(state, type_id, cell, now, now + float(check.seconds))
	# Its value on the balance sheet: the money paid plus the cost tags of the warehouse's
	# materials it used (they move from the goods into the building).
	b.paid = int(check.cost) + _use_materials(state, b, check)
	_hire(state, data, now)  # a building ready at once hires (and a home takes households in) now
	return _ok({"building_id": b.id, "cost": int(check.cost), "seconds": float(check.seconds)})


## Whether a building could be moved to this cell (changes nothing). Moving is free, any building
## can move, and everything inside keeps going. But a building with workers needs a road
## (plan.md §5.20): moved away from one it stops until a road reaches it again. A warehouse can't
## be moved off its road while the goods wouldn't fit in the other warehouses.
## Its own tiles count as free (dropping it back where it was, or nudging it, is fine).
static func can_move(state: Dictionary, data: Dictionary, building_id: String, cell: Vector2i) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	var problem := _footprint_problem(state, data, b.type, cell, building_id)
	if problem != "":
		return _fail(problem)
	var old_position: Array = b.position
	b.position = [cell.x, cell.y]
	var room_left := _room_after_road_change(state, data)
	b.position = old_position
	if room_left < warehouse_total(state):
		return _fail("Away from the road this warehouse loses its workers, and the other warehouses don't have room for your goods.")
	return _ok()


static func move(state: Dictionary, data: Dictionary, building_id: String, cell: Vector2i, now: float) -> Dictionary:
	var check := can_move(state, data, building_id, cell)
	if not check.ok:
		return check
	settle(state, data, now)  # time so far was worked where it stood
	check = can_move(state, data, building_id, cell)  # a hut may have gone up there meanwhile
	if not check.ok:
		return check
	find_building(state, building_id).position = [cell.x, cell.y]
	_hire(state, data, now)  # it may have gained or lost its road
	return _ok()


# --- Roads (plan.md §5.20) -------------------------------------------------------
# Road tiles go on free tiles of the plot, are paid at once and are ready at once. The road
# network starts at City Hall ("road_hub" in buildings.json): a road tile is
# linked when roads lead from it to a tile beside the hub. A building with workers is "on the
# road" when one of the 4 tiles beside it (not diagonal) is a linked road; without that it offers
# no posts, so it has no workers and stops, like a suspended building. Links only change when the
# player acts (roads, building, moving, demolishing), and every such action settles first, so time
# away stays one calculation. Data without a "roads" block (the test data) needs no roads at all.

const _SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


static func _roads_config(data: Dictionary) -> Dictionary:
	return data.config.get("roads", {})


## Whether this game has roads at all (game_config.json has a "roads" block).
static func roads_on(data: Dictionary) -> bool:
	return not _roads_config(data).is_empty()


## The price of one road tile, in cents.
static func road_price(data: Dictionary) -> int:
	return cents(float(_roads_config(data).get("price", 0.0)))


static func _cell_of(b: Dictionary) -> Vector2i:
	return Vector2i(int(b.position[0]), int(b.position[1]))


# --- Footprints (plan.md §4) ---
# A building stands on a square of size x size tiles ("size" in buildings.json, default 1).
# Its "position" is the square's tile with the smallest x and y (its top corner on screen).

## How many tiles wide and deep this kind of building stands.
static func size_of(data: Dictionary, type_id: String) -> int:
	return maxi(1, int(data.buildings.get(type_id, {}).get("size", 1)))


## The tiles a building of this kind covers when its position is `cell`.
static func footprint(data: Dictionary, type_id: String, cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var size := size_of(data, type_id)
	for dy in size:
		for dx in size:
			cells.append(cell + Vector2i(dx, dy))
	return cells


## The tiles this building covers.
static func cells_of(data: Dictionary, b: Dictionary) -> Array[Vector2i]:
	return footprint(data, b.type, _cell_of(b))


## The middle of a building of this kind standing at `cell`, in tiles: the tile's centre for
## 1x1, the corner its 4 tiles share for 2x2. Power reach is measured from here.
static func centre_at(data: Dictionary, type_id: String, cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2.ONE * (size_of(data, type_id) - 1) / 2.0


static func centre_of(data: Dictionary, b: Dictionary) -> Vector2:
	return centre_at(data, b.type, _cell_of(b))


## Whether a building of this kind fits at `cell`: every tile of its footprint on the plot, with no
## other building and no road on it. `ignore_id` = a building allowed to be there (the one being
## moved). "" when it fits, else the reason, friendly enough to show. Checking many spots in a
## row? Make the plot map once (_plot_map) and hand it in as `map`: far quicker in a big village.
static func _footprint_problem(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i, ignore_id := "", map := {}) -> String:
	if map.is_empty():
		map = _plot_map(state, data)
	var cells := footprint(data, type_id, cell)
	for c in cells:
		if not _in_plot(state, c):
			return "That spot is outside your land."
	for c in cells:
		if map.buildings.has(c) and map.buildings[c] != ignore_id:
			return "That spot is taken."
	for c in cells:
		if map.roads.has(c):
			return "There's a road there. Remove the road first."
	return ""


## What stands where, for _footprint_problem: {"buildings": Vector2i -> the id of the building on
## that tile (the first in the list, like building_at), "roads": road_cells}.
static func _plot_map(state: Dictionary, data: Dictionary) -> Dictionary:
	var tiles := {}
	for b in state.buildings:
		for c in cells_of(data, b):
			if not tiles.has(c):
				tiles[c] = str(b.id)
	return {"buildings": tiles, "roads": road_cells(state)}


## The free spot for a building of this kind closest to `near` (where Placement Mode puts the
## ghost first), or `near` itself when there's none. Equally close: the lowest x, then y.
static func free_spot_near(state: Dictionary, data: Dictionary, type_id: String, near: Vector2i) -> Vector2i:
	var map := _plot_map(state, data)
	var grid: Array = state.plot.grid_size
	var best := near
	var best_dist := INF
	for x in int(grid[0]):
		for y in int(grid[1]):
			var cell := Vector2i(x, y)
			var dist := Vector2(cell - near).length()
			if dist < best_dist and _footprint_problem(state, data, type_id, cell, "", map) == "":
				best = cell
				best_dist = dist
	return best


## Whether any tile beside `area` (on the 4 sides of its tiles, outside the area) is in `cells`.
static func _beside(cells: Dictionary, area: Array[Vector2i]) -> bool:
	for cell in area:
		for side in _SIDES:
			var next: Vector2i = cell + side
			if cells.has(next) and not area.has(next):
				return true
	return false


## Every road tile: Vector2i -> cents paid for it.
static func road_cells(state: Dictionary) -> Dictionary:
	var cells := {}
	for road in state.get("roads", []):
		cells[Vector2i(int(road[0]), int(road[1]))] = int(road[2]) if road.size() > 2 else 0
	return cells


static func is_road(state: Dictionary, cell: Vector2i) -> bool:
	for road in state.get("roads", []):
		if int(road[0]) == cell.x and int(road[1]) == cell.y:
			return true
	return false


## A tile of the plot with no building and no road on it.
static func is_free_cell(state: Dictionary, data: Dictionary, cell: Vector2i) -> bool:
	return _in_plot(state, cell) and building_at(state, data, cell).is_empty() and not is_road(state, cell)


## Tiles taken by a building or a road: Vector2i -> true.
static func _taken_cells(state: Dictionary, data: Dictionary) -> Dictionary:
	var taken := road_cells(state)
	for b in state.buildings:
		for cell in cells_of(data, b):
			taken[cell] = true
	return taken


## Where the road network starts: City Hall.
static func is_road_hub(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("road_hub", false))


## Every building with workers needs a road, except the hub itself. Homes don't (yet).
static func needs_road(data: Dictionary, b: Dictionary) -> bool:
	return roads_on(data) and int(data.buildings.get(b.type, {}).get("max_workers", 0)) > 0 and not is_road_hub(data, b)


## True unless the building needs a road and has none (worked out by _update_road_links).
static func on_road(data: Dictionary, b: Dictionary) -> bool:
	return not needs_road(data, b) or bool(b.get("road", true))


## The road tiles linked to the hub: a search outward from the road tiles beside it.
static func linked_roads(state: Dictionary, data: Dictionary) -> Dictionary:
	var roads := road_cells(state)
	var linked := {}
	var todo: Array[Vector2i] = []
	for b in state.buildings:
		if is_road_hub(data, b):
			for hub_cell in cells_of(data, b):
				for side in _SIDES:
					var cell: Vector2i = hub_cell + side
					if roads.has(cell) and not linked.has(cell):
						linked[cell] = true
						todo.append(cell)
	while not todo.is_empty():
		var cell: Vector2i = todo.pop_back()
		for side in _SIDES:
			var next: Vector2i = cell + side
			if roads.has(next) and not linked.has(next):
				linked[next] = true
				todo.append(next)
	return linked


static func _touches(cells: Dictionary, cell: Vector2i) -> bool:
	for side in _SIDES:
		if cells.has(cell + side):
			return true
	return false


## Marks every building that needs a road with whether it has one ("road"). Run first thing when
## hiring, so posts() always knows.
static func _update_road_links(state: Dictionary, data: Dictionary) -> void:
	if not roads_on(data) or not state.has("roads"):
		return  # no roads in this game, or an old save still being upgraded (it gets roads at 10)
	var linked := linked_roads(state, data)
	for b in state.buildings:
		if needs_road(data, b):
			b["road"] = _beside(linked, cells_of(data, b))
		else:
			b.erase("road")


## The warehouses' room once the roads (or a building's position) changed as they stand now: a
## warehouse that would lose its road counts 0. Lets a change be refused before goods are left
## without room.
static func _room_after_road_change(state: Dictionary, data: Dictionary) -> int:
	var linked := linked_roads(state, data)
	var room := 0
	for b in state.buildings:
		if needs_road(data, b) and not _beside(linked, cells_of(data, b)):
			continue
		room += storage_capacity(state, data, b)
	return room


## What building road on these tiles would cost (changes nothing): {"ok", "error", "cost" (cents),
## "new_cells" (tiles that aren't a road yet; tiles that are already a road are free)}.
static func road_quote(state: Dictionary, data: Dictionary, cells: Array) -> Dictionary:
	if not roads_on(data):
		return _fail("Roads can't be built.")
	var taken := _taken_cells(state, data)
	var buildings: Dictionary = _plot_map(state, data).buildings
	var new_cells: Array[Vector2i] = []
	for cell in cells:
		if not _in_plot(state, cell):
			return _fail("The road would go off your land.")
		if buildings.has(cell):
			return _fail("A building is in the way.")
		if not taken.has(cell) and not new_cells.has(cell):
			new_cells.append(cell)
	if new_cells.is_empty():
		return _fail("That's a road already.")
	var cost := road_price(data) * new_cells.size()
	if int(state.profile.currency) < cost:
		return _fail("Not enough money.")
	return _ok({"cost": cost, "new_cells": new_cells})


## Build road on these tiles (Vector2i): paid now, ready now.
static func build_roads(state: Dictionary, data: Dictionary, cells: Array, now: float) -> Dictionary:
	var check := road_quote(state, data, cells)
	if not check.ok:
		return check
	settle(state, data, now)  # time so far was worked with the old roads
	check = road_quote(state, data, cells)  # a hut may have gone up there, or wages used the money
	if not check.ok:
		return check
	for cell in check.new_cells:
		state.roads.append([cell.x, cell.y, road_price(data)])
	state.profile.currency -= int(check.cost)
	stats(state).spending.roads = int(stats(state).spending.get("roads", 0)) + int(check.cost)
	_hire(state, data, now)  # buildings that just got a road hire now
	return check


## Whether the road on these tiles could be removed (changes nothing): {"ok", "error", "cells"
## (the tiles that really are road)}. Refused when a warehouse would lose its road and the goods
## wouldn't fit in the others.
static func can_remove_roads(state: Dictionary, data: Dictionary, cells: Array) -> Dictionary:
	var kept := []
	var gone: Array[Vector2i] = []
	for road in state.get("roads", []):
		var cell := Vector2i(int(road[0]), int(road[1]))
		if cells.has(cell):
			gone.append(cell)
		else:
			kept.append(road)
	if gone.is_empty():
		return _fail("There's no road there to remove.")
	var all_roads: Array = state.roads
	state.roads = kept
	var room_left := _room_after_road_change(state, data)
	state.roads = all_roads
	if room_left < warehouse_total(state):
		return _fail("That would cut a warehouse off the road, and the other warehouses don't have room for your goods.")
	return _ok({"cells": gone})


## Remove the road on these tiles. Free, and nothing is paid back.
static func remove_roads(state: Dictionary, data: Dictionary, cells: Array, now: float) -> Dictionary:
	var check := can_remove_roads(state, data, cells)
	if not check.ok:
		return check
	settle(state, data, now)  # time so far was worked with the old roads
	check = can_remove_roads(state, data, cells)
	if not check.ok:
		return check
	state.roads = state.roads.filter(func(road): return not check.cells.has(Vector2i(int(road[0]), int(road[1]))))
	_hire(state, data, now)  # buildings that lost their road let their workers go
	return check


## The shortest road (tiles, from beside the building outward) that would link this building to
## the road network, over free tiles; [] when it's linked already or no road can reach it. Ties are
## broken in a fixed order, so it's always the same road.
static func road_path_for(state: Dictionary, data: Dictionary, building_id: String) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var b := find_building(state, building_id)
	if b.is_empty() or not needs_road(data, b):
		return none
	var linked := linked_roads(state, data)
	var area := cells_of(data, b)
	if _beside(linked, area):
		return none
	var hubs := _hub_cells(state, data)
	var taken := _taken_cells(state, data)
	var came_from := {}  # tile -> the tile before it (itself for a first step, beside the building)
	var todo: Array[Vector2i] = []
	for start in area:
		for side in _SIDES:
			var first: Vector2i = start + side
			if _in_plot(state, first) and not taken.has(first) and not came_from.has(first):
				came_from[first] = first
				todo.append(first)
	var i := 0
	while i < todo.size():
		var cell: Vector2i = todo[i]
		i += 1
		if _touches(linked, cell) or _touches(hubs, cell):
			var path: Array[Vector2i] = [cell]
			while came_from[cell] != cell:
				cell = came_from[cell]
				path.push_front(cell)
			return path
		for side in _SIDES:
			var next: Vector2i = cell + side
			if _in_plot(state, next) and not taken.has(next) and not came_from.has(next):
				came_from[next] = cell
				todo.append(next)
	return none


## Lays free road from every building that needs one to the network, oldest building first (for
## saves made before roads existed). A building no road can reach is left without one.
static func lay_roads_to_all(state: Dictionary, data: Dictionary) -> void:
	if not state.has("roads"):
		state["roads"] = []
	if not roads_on(data):
		return
	for type_id in data.buildings:  # Makeshift Huts around the office would block every road
		if bool(data.buildings[type_id].get("hut", false)):
			_move_huts_off_hub(state, data, type_id)
	for b in state.buildings:
		for cell in road_path_for(state, data, b.id):
			state.roads.append([cell.x, cell.y, 0])


## Makes every building fit its footprint (plan.md §4), for saves from before buildings had
## sizes. Oldest buildings first: one whose tiles are all on the plot and not taken by an older
## building stays put, and the road tiles under it are removed, their price given back (counted
## like a demolish refund). One that doesn't fit moves to the nearest spot with no building and no
## road. Buildings then left without a road get free road (lay_roads_to_all). Returns notes for
## the player (none when nothing changed).
static func fit_footprints(state: Dictionary, data: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var placed := {}  # tile -> true: taken by a building that has its place
	var to_move: Array = []
	for b in state.buildings:
		var cells := cells_of(data, b)
		if cells.all(func(c: Vector2i) -> bool: return _in_plot(state, c) and not placed.has(c)):
			for c in cells:
				placed[c] = true
		else:
			to_move.append(b)

	var kept := []
	var refund := 0
	for road in state.get("roads", []):
		if placed.has(Vector2i(int(road[0]), int(road[1]))):
			refund += int(road[2]) if road.size() > 2 else 0
		else:
			kept.append(road)
	var removed: int = state.get("roads", []).size() - kept.size()
	if removed > 0:
		state.roads = kept
		state.profile.currency += refund
		var income: Dictionary = stats(state).income
		income["demolish"] = int(income.get("demolish", 0)) + refund
		notes.append("Big buildings now stand on 2x2 tiles: %d road %s under them %s removed and $%s given back." % [
			removed, "tile" if removed == 1 else "tiles", "was" if removed == 1 else "were", _whole_dollars(refund)])

	var moved: Array[String] = []
	var grid: Array = state.plot.grid_size
	for b in to_move:
		var home := _cell_of(b)
		var best := Vector2i(-1, -1)
		for ring in range(0, maxi(int(grid[0]), int(grid[1])) + 1):
			for dy in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					var cell := home + Vector2i(dx, dy)
					if best.x < 0 and maxi(absi(dx), absi(dy)) == ring and _fits_among(state, data, b.type, cell, placed):
						best = cell
			if best.x >= 0:
				break
		if best.x < 0:
			continue  # no room anywhere: it stays where it was
		b.position = [best.x, best.y]
		for c in cells_of(data, b):
			placed[c] = true
		moved.append(str(data.buildings.get(b.type, {}).get("name", b.type)))
	if not moved.is_empty():
		notes.append("Moved to make room for the bigger buildings: %s." % ", ".join(moved))

	if removed > 0 or not moved.is_empty():
		var roads_before: int = state.roads.size()
		lay_roads_to_all(state, data)
		var laid: int = state.roads.size() - roads_before
		if laid > 0:
			notes.append("%d free road %s laid so every building still reaches City Hall." % [laid, "tile was" if laid == 1 else "tiles were"])
	return notes


## Whether a building of this kind fits at `cell` on tiles not in `placed` and with no road.
static func _fits_among(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i, placed: Dictionary) -> bool:
	for c in footprint(data, type_id, cell):
		if not _in_plot(state, c) or placed.has(c) or is_road(state, c):  # perf-ok: only when an old save is upgraded
			return false
	return true


## Cents as whole dollars with thousands separators, for notes: 125000 -> "1,250".
static func _whole_dollars(amount: int) -> String:
	var text := str(roundi(amount / 100.0))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return text + out


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
	if has_batch(b):
		return _fail("The bonus is locked in until this batch is done and collected.")
	return _ok()


## Choose the bonus for the next batch (plan.md §5.6): a bigger bonus pays each worker more and
## makes more units per batch (bonus_output). Once a batch starts, its bonus is locked in.
static func set_bonus(state: Dictionary, data: Dictionary, building_id: String, level: String, now: float) -> Dictionary:
	var check := can_set_bonus(state, data, building_id, level)
	if not check.ok:
		return check
	settle(state, data, now)
	find_building(state, building_id)["bonus"] = level
	return _ok()


# --- Production batches (plan.md §5.1) --------------------------------------------
# A Farm, Mill or Bakery runs one batch at a time, of as many hours as the player chooses (one
# "hour" = one cycle of its recipe, 3600 s in the data). Starting it takes all the ingredients
# from the Warehouse and pays all the wages at once, so its cost (and cost per unit) is locked in.
# Each finished hour makes its share of the units, which wait in the batch until the player
# collects them into the Warehouse. b.batch = {} when idle, else:
#   {"recipe_id", "hours", "bonus", "units" {res: qty for the whole batch}, "cost" (cents, the
#    whole batch: ingredients + wages + water estimate), "unit_cost" {res: cents each, the cost
#    split by the recipe's cost_share; older batches don't have it}, "wages" (cents paid),
#    "inputs" {res: qty taken}, "input_cost" {res: cents}, "collected" {res: qty}, "made_hours"}

## True for buildings that make things in batches (Farm, Mill, Bakery).
static func makes_batches(data: Dictionary, b: Dictionary) -> bool:
	return data.buildings.get(b.type, {}).get("category", "") in ["extractor", "processor"]


## True while the building has a batch: being made, or finished with units still to collect.
static func has_batch(b: Dictionary) -> bool:
	return not b.get("batch", {}).is_empty()


## True while the batch still has hours of work left.
static func batch_running(b: Dictionary) -> bool:
	return has_batch(b) and int(b.batch.get("made_hours", 0)) < int(b.batch.hours)


## batch.max_hours / batch.default_hours from game_config.json.
static func batch_hours_limit(data: Dictionary) -> int:
	return maxi(int(data.config.get("batch", {}).get("max_hours", 48)), 1)


static func batch_default_hours(data: Dictionary) -> int:
	return clampi(int(data.config.get("batch", {}).get("default_hours", 24)), 1, batch_hours_limit(data))


## Extra share of units a bonus makes (bonus_output in game_config.json: 0.1 = +10%).
static func bonus_output(data: Dictionary, level: String) -> float:
	return float(data.config.get("bonus_output", {}).get(level, 0.0))


## How a recipe's cost is split between the things it makes (by-products, plan.md §5.14): its
## "cost_share" ({item: share}, adding up to 1) when it has one, else by units, so every unit
## costs the same. E.g. 4 cattle -> 40 beef + 4 hides with cost_share beef 0.9, hide 0.1: the
## hides carry a tenth of the cost, so a hide isn't priced like ten steaks. {item: share}.
static func output_shares(recipe: Dictionary) -> Dictionary:
	var outputs: Dictionary = recipe.get("outputs", {})
	var shares: Dictionary = recipe.get("cost_share", {})
	var total := maxf(_total(outputs), 1)
	var out := {}
	for res in outputs:
		out[res] = float(shares[res]) if shares.has(res) else float(outputs[res]) / total
	return out


## What each unit of a batch costs (cents) when `units` were made for `cost` cents: split by the
## recipe's cost_share, or evenly per unit without one. {item: cents each}. The parts add up to
## `cost` exactly (unit cost × units, summed).
static func _unit_costs(recipe: Dictionary, units: Dictionary, cost: float) -> Dictionary:
	var shares: Dictionary = recipe.get("cost_share", {})
	var out := {}
	for res in units:
		if shares.is_empty():
			out[res] = cost / maxf(_total(units), 1)
		else:
			out[res] = cost * float(shares.get(res, 0.0)) / maxf(float(units[res]), 1.0)
	return out


## What one unit of `res` from this batch cost to make (cents): its share of the batch's cost,
## locked in when the batch started (batch.unit_cost). Batches started before by-products have
## no unit_cost: every unit of them costs the same.
static func batch_unit_cost(batch: Dictionary, res: String) -> float:
	var each: Dictionary = batch.get("unit_cost", {})
	if each.has(res):
		return float(each[res])
	return float(batch.get("cost", 0.0)) / maxf(_total(batch.get("units", {})), 1)


## Units made once `hours` of the batch are finished: each hour's share, rounded down so the
## shares add up exactly to the whole batch at the end.
static func _units_after(batch: Dictionary, hours: int) -> Dictionary:
	var out := {}
	var total_hours := maxi(int(batch.hours), 1)
	for res in batch.units:
		var qty := floori(float(int(batch.units[res])) * hours / total_hours)
		if qty > 0:
			out[res] = qty
	return out


## What the batch has made and nobody has collected yet: {res: qty}. What the map's bubble shows.
static func ready_units(b: Dictionary) -> Dictionary:
	if not has_batch(b):
		return {}
	var ready := _units_after(b.batch, int(b.batch.get("made_hours", 0)))
	_remove_from(ready, b.batch.get("collected", {}))
	return ready


## Goods waiting in a building to be collected: a batch's ready units, or what a suspended
## Supermarket couldn't fit in the Warehouse.
static func waiting_goods(b: Dictionary) -> Dictionary:
	var goods: Dictionary = b.get("storage", {}).duplicate()
	_add_to(goods, ready_units(b))
	return goods


## The work speed a building would have if it were working now: its hired workers ÷ Level 1's
## crew (while idle nobody is working, so building_speed says 0).
static func _speed_if_working(data: Dictionary, b: Dictionary) -> float:
	var most := _full_speed_workers(data, b)
	return 1.0 if most <= 0 else float(hired(b)) / most


## Wage per hour (dollars) of one worker here with bonus `level`.
static func _wage_with_bonus(data: Dictionary, b: Dictionary, level: String) -> float:
	return minimum_wage(data, b) * (1.0 + float(data.config.get("wage_bonuses", {}).get(level, 0.0)))


## What a batch of `hours` of `recipe_id` with bonus `level` would make and cost, in cents
## (changes nothing): {"recipe_id", "hours", "bonus", "units" {res: qty}, "output" (main product),
## "count" (all units), "ingredients" [{"res", "qty", "each", "cost", "estimated"}], "wages",
## "water", "power", "total", "per_unit", "price" (selling price each), "workers" (full crew), "wage_each"
## (dollars/h), "seconds" (work time at full speed), "finishes_at" (at today's workers; INF with
## none), "estimated" (an ingredient isn't in stock: its standard cost was used)}.
## {} if the building makes nothing or the recipe is unknown.
static func batch_quote(state: Dictionary, data: Dictionary, b: Dictionary, recipe_id: String, hours: int, level: String, now: float) -> Dictionary:
	var def: Dictionary = data.buildings.get(b.type, {})
	var recipe := _recipe(def, recipe_id)
	if recipe.is_empty() or recipe.get("outputs", {}).is_empty():
		return {}
	hours = maxi(hours, 1)
	var real_hours := float(recipe.duration) * hours / 3600.0
	var units := {}
	for res in recipe.outputs:
		units[res] = floori(int(recipe.outputs[res]) * hours * (1.0 + bonus_output(data, level)) + 0.000001)
	var quote := {"recipe_id": recipe_id, "hours": hours, "bonus": level, "units": units,
		"output": recipe.outputs.keys()[0], "count": _total(units), "ingredients": [], "estimated": false,
		"workers": _full_speed_workers(data, b), "wage_each": _wage_with_bonus(data, b, level),
		"seconds": float(recipe.duration) * hours}
	var total := 0.0
	for res in recipe.get("inputs", {}):
		var qty := int(recipe.inputs[res]) * hours
		var have := int(state.inventory.get(res, 0))
		var each := average_cost(state, res) if have > 0 else standard_unit_cost(data, res)
		quote.ingredients.append({"res": res, "qty": qty, "each": each, "cost": each * qty, "estimated": have <= 0})
		quote.estimated = quote.estimated or have <= 0
		total += each * qty
	# Wages: the full crew for the whole time, whatever the staffing (fewer workers just take longer).
	quote["wages"] = cents(float(quote.workers) * float(quote.wage_each) * real_hours)
	# Water: an estimate (it's metered as it's used). Own plants' spare water first, then public.
	var water_per_hour := float(def.get("water_per_hour", 0.0))
	quote["water"] = water_per_hour * real_hours * extra_water_price(state, data, water_per_hour, now) * 100.0
	# Power: an estimate too (the public grid's part is metered). Own plants' spare power first.
	var mw := power_need(data, b)
	quote["power"] = mw * real_hours * extra_power_price(state, data, mw, now) * 100.0
	total += int(quote.wages) + float(quote.water) + float(quote.power)
	quote["total"] = total
	# Cost and selling price of each thing it makes (by-products carry their cost_share);
	# per_unit and price are the main product's (the recipe's first output).
	quote["unit_costs"] = _unit_costs(recipe, units, total)
	quote["per_unit"] = float(quote.unit_costs.get(quote.output, 0.0))
	var prices := {}
	for res in units:
		prices[res] = unit_price(data, res)
	quote["prices"] = prices
	quote["price"] = unit_price(data, quote.output)
	var speed := _speed_if_working(data, b)
	var start := maxf(now, float(state.get("settled_at", now)))
	quote["finishes_at"] = start + float(quote.seconds) / speed if speed > 0.0 else INF
	return quote


## The longest batch the player could start now, in hours (0 = none): at most batch.max_hours,
## and only as long as the Warehouse's ingredients and the cash for the wages last.
static func batch_max_hours(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, level: String) -> int:
	var b := find_building(state, building_id)
	if b.is_empty():
		return 0
	var recipe := _recipe(data.buildings.get(b.type, {}), recipe_id)
	if recipe.is_empty():
		return 0
	if product_of(data, b) != "" and product_of(data, b) != recipe_id:
		return 0  # set up for another product (can_start_batch says the same)
	var most := batch_hours_limit(data)
	for res in recipe.get("inputs", {}):
		if int(recipe.inputs[res]) > 0:
			most = mini(most, floori(float(state.inventory.get(res, 0)) / int(recipe.inputs[res])))
	var wages_per_hour := float(_full_speed_workers(data, b)) * _wage_with_bonus(data, b, level) * float(recipe.duration) / 3600.0 * 100.0
	if wages_per_hour > 0.0:
		var cash := float(state.profile.currency)
		while most > 0 and cents(wages_per_hour * most / 100.0) > cash:
			most -= 1  # counted the way start_batch counts it, so the two always agree
	return maxi(most, 0)


## Whether this batch could start now (changes nothing): {"ok", "error"} plus the batch_quote.
## The UI uses it to grey out Produce, and start_batch uses it too, so they always agree.
static func can_start_batch(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, hours: int, level: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if not makes_batches(data, b):
		return _fail("This building doesn't make anything.")
	if not is_built(b, now):
		return _fail(_unfinished(b, now))
	if is_suspended(b):
		return _fail("It's suspended. Resume it first.")
	if batch_running(b):
		return _fail("It's already making a batch.")
	if has_batch(b):
		return _fail("Collect what it made first.")
	if (has_fixed_wage(data, b) and level != "none") or not data.config.get("wage_bonuses", {"none": 0.0}).has(level):
		return _fail("Unknown bonus.")
	if hours < 1 or hours > batch_hours_limit(data):
		return _fail("Pick between 1 and %d hours." % batch_hours_limit(data))
	var quote := batch_quote(state, data, b, recipe_id, hours, level, now)
	if quote.is_empty():
		return _fail("Unknown recipe.")
	var chosen := product_of(data, b)  # once chosen, it only makes that (plan.md §5.21)
	if chosen != "" and chosen != recipe_id:
		if is_switchable(data, b.type):
			return _fail("It's set up for %s. Switch it to %s first (%s)." % [_product_name(data, b.type, chosen), _product_name(data, b.type, recipe_id), _money_text(switch_fee(data, b))])
		return _fail("A %s makes %s for good. Build another one to make %s." % [data.buildings[b.type].get("name", "building"), _product_name(data, b.type, chosen), _product_name(data, b.type, recipe_id)])
	for item in quote.ingredients:
		if int(state.inventory.get(item.res, 0)) < int(item.qty):
			return _fail("Not enough %s for %d hours." % [_resource_name(data, item.res), hours])
	if state.profile.currency < int(quote.wages):
		return _fail("Not enough money for the wages.")
	return _ok(quote)


## Start a batch: the ingredients leave the Warehouse (with their cost tags) and the wages are paid
## now, so the batch's cost is locked in; so is its bonus. Work starts now.
static func start_batch(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, hours: int, level: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # the last batch may have just finished
	var check := can_start_batch(state, data, building_id, recipe_id, hours, level, now)
	if not check.ok:
		return check
	var inputs := {}
	for item in check.ingredients:
		inputs[item.res] = int(item.qty)
	var input_cost := _take_cost(state.inventory, _costs(state, "inventory_cost"), inputs)
	_remove_from(state.inventory, inputs)
	var wages := int(check.wages)
	state.profile.currency -= wages
	stats(state).spending.wages = int(stats(state).spending.get("wages", 0)) + wages
	var cost := wages + float(check.water) + float(check.power)  # the real ingredient tags, not the quote's estimate
	for res in input_cost:
		cost += float(input_cost[res])
	b["bonus"] = level  # also the choice offered for the next batch
	b["product"] = recipe_id  # the first batch chooses what it makes (plan.md §5.21)
	b["batch"] = {"recipe_id": recipe_id, "hours": hours, "bonus": level, "units": check.units,
		"cost": cost, "wages": wages, "inputs": inputs, "input_cost": input_cost,
		"unit_cost": _unit_costs(_recipe(data.buildings[b.type], recipe_id), check.units, cost),
		"collected": {}, "made_hours": 0}
	# A clock set backwards never moves the start before the time already worked out.
	b.job_started_at = maxf(now, float(state.get("settled_at", now)))
	# Its wage bonus raises its workers' wages, which can move a household into a richer class
	# (and so change who needs a hut); then it asks for power from now.
	_update_huts(state, data, b.job_started_at)
	_update_power(state, data, b.job_started_at)
	return check


## Clears a batch once every hour is made and every unit collected: the building is idle again.
static func _end_batch_if_done(b: Dictionary) -> void:
	if has_batch(b) and not batch_running(b) and ready_units(b).is_empty():
		b.batch = {}


## Move what the building has made into the Warehouse (as much as fits; the rest keeps waiting).
## A batch's units take their share of its cost: cost per unit stays what it was when it started.
static func collect(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	settle(state, data, now)
	var waiting := waiting_goods(b)
	if waiting.is_empty():
		return _fail("Nothing to collect.")
	var free := warehouse_cap(state, data) - warehouse_total(state)
	var moved := {}
	for res in waiting:
		var qty := mini(int(waiting[res]), free)
		if qty > 0:
			moved[res] = qty
			free -= qty
	if moved.is_empty():
		return _fail("The warehouse is full.")
	var moved_cost := {}
	var from_batch := ready_units(b)
	var from_storage := {}
	for res in moved:
		var qty := mini(int(moved[res]), int(from_batch.get(res, 0)))
		if qty > 0:
			_add_to(b.batch.collected, {res: qty})
			_put_cost(moved_cost, {res: batch_unit_cost(b.batch, res) * qty})
		if int(moved[res]) > qty:
			from_storage[res] = int(moved[res]) - qty
	if not from_storage.is_empty():
		_put_cost(moved_cost, _take_cost(b.storage, _costs(b, "storage_cost"), from_storage))
		_remove_from(b.storage, from_storage)
	_add_to(state.inventory, moved)
	_put_cost(_costs(state, "inventory_cost"), moved_cost)
	_end_batch_if_done(b)
	return _ok({"moved": moved})


## One tap collects the whole group: the tapped building, then every other building of the same
## type with goods waiting. The tapped one goes first, so it wins if the Warehouse runs out of room.
## {"moved": totals, "by_building": {id: moved}, "left_over": some goods didn't fit}
static func collect_group(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var tapped := find_building(state, building_id)
	if tapped.is_empty():
		return _fail("Building not found.")
	var ids: Array = [building_id]
	for b in state.buildings:
		if b.type == tapped.type and b.id != building_id:
			ids.append(b.id)
	var total := {}
	var by_building := {}
	var first_error := ""
	for id in ids:
		var result := collect(state, data, id, now)
		if result.ok:
			by_building[id] = result.moved
			_add_to(total, result.moved)
		elif first_error == "":
			first_error = result.error
	if by_building.is_empty():
		return _fail(first_error)
	# Left over = the Warehouse is full and goods still wait.
	var left_over := false
	if warehouse_total(state) >= warehouse_cap(state, data):
		for id in ids:
			if not waiting_goods(find_building(state, id)).is_empty():  # perf-ok: once per tap, a few buildings
				left_over = true
	return _ok({"moved": total, "by_building": by_building, "left_over": left_over})


## What cancelling the running batch would give back (changes nothing): {"ok", "error",
## "hours_left" (hours not finished; work on the current hour is lost), "refund" {res: qty},
## "money" (cents)}: cancel_refund_in_progress (0.5) of the ingredients and wages of those hours.
## Hours already finished stay in the batch, to be collected as usual.
static func can_cancel_batch(state: Dictionary, data: Dictionary, building_id: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if not batch_running(b):
		return _fail("It isn't making a batch.")
	var batch: Dictionary = b.batch
	var hours := int(batch.hours)
	var hours_left := hours - int(batch.get("made_hours", 0))
	var share := float(data.config.get("cancel_refund_in_progress", 0.0)) * hours_left / hours
	var refund := _share(batch.get("inputs", {}), share)
	if warehouse_total(state) + _total(refund) > warehouse_cap(state, data):
		return _fail("Not enough room in the warehouse for the refund.")
	return _ok({"hours_left": hours_left, "refund": refund, "money": floori(int(batch.get("wages", 0)) * share)})


## Cancel the running batch (see can_cancel_batch). The batch shrinks to the hours already
## finished, keeping their units and their cost per unit; the rest of its cost is gone.
static func cancel_batch(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # an hour may have just finished
	var check := can_cancel_batch(state, data, building_id)
	if not check.ok:
		return check
	var batch: Dictionary = b.batch
	# What's given back keeps its share of what the ingredients cost.
	var refund_cost := {}
	for res in check.refund:
		refund_cost[res] = float(batch.input_cost.get(res, 0.0)) * int(check.refund[res]) / maxi(int(batch.inputs[res]), 1)
	_add_to(state.inventory, check.refund)
	_put_cost(_costs(state, "inventory_cost"), refund_cost)
	state.profile.currency += int(check.money)
	var income: Dictionary = stats(state).income
	income["batch_refunds"] = int(income.get("batch_refunds", 0)) + int(check.money)
	var made := int(batch.get("made_hours", 0))
	var units := _units_after(batch, made)
	var kept := 0.0  # what the hours already made cost: each unit keeps its cost (by-products too)
	for res in units:
		kept += batch_unit_cost(batch, res) * int(units[res])
	batch.cost = kept
	batch.units = units
	batch.hours = maxi(made, 1)  # (an empty batch is cleared just below)
	batch.made_hours = made
	if made == 0:
		b.batch = {}
	_end_batch_if_done(b)
	return check


# --- Product choice (plan.md §5.21) -----------------------------------------------
# A building with several recipes (a Plantation's crops, a Dairy's cheese / butter / yogurt) is
# set up for ONE of them: its product (b.product, a recipe id). Its first batch chooses it, for
# free. A building with "switch_fee" in buildings.json (Plantation, Ranch, Fishery) can switch to
# another product later, for that share of its value, while it has no batch; any other building
# keeps its product for good: build another one to make something else.

## The recipe this building is set up for, or "" while it hasn't chosen yet (its first batch
## chooses, for free). A product the data no longer has counts as not chosen.
static func product_of(data: Dictionary, b: Dictionary) -> String:
	var id := str(b.get("product", ""))
	if id != "" and not _recipe(data.buildings.get(b.type, {}), id).is_empty():
		return id
	return ""


## True when this type of building can switch to another product later (it has a switch_fee).
static func is_switchable(data: Dictionary, type_id: String) -> bool:
	return data.buildings.get(type_id, {}).has("switch_fee")


## What switching costs, in cents: switch_fee (a share) of what the building is worth at base
## prices (building it plus its upgrades so far).
static func switch_fee(data: Dictionary, b: Dictionary) -> int:
	var share := float(data.buildings.get(b.type, {}).get("switch_fee", 0.0))
	return roundi(construction_value(data, b.type, building_level(b)) * share)


## The name of what a recipe makes (its main product): "Corn".
static func _product_name(data: Dictionary, type_id: String, recipe_id: String) -> String:
	var outputs: Dictionary = _recipe(data.buildings.get(type_id, {}), recipe_id).get("outputs", {})
	return _resource_name(data, str(outputs.keys()[0])) if not outputs.is_empty() else recipe_id


## Whether this building could switch to `recipe_id` now (changes nothing): {"ok", "error",
## "fee" (cents)}. The UI uses it to grey out its buttons, and switch_product uses it too.
static func can_switch_product(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if not makes_batches(data, b):
		return _fail("This building doesn't make anything.")
	var def: Dictionary = data.buildings.get(b.type, {})
	if _recipe(def, recipe_id).is_empty():
		return _fail("It can't make that.")
	var current := product_of(data, b)
	if current == "":
		return _fail("Nothing chosen yet: the first batch chooses what it makes, for free.")
	if current == recipe_id:
		return _fail("It already makes %s." % _product_name(data, b.type, recipe_id))
	if not is_switchable(data, b.type):
		return _fail("A %s makes %s for good. Build another one to make %s." % [def.get("name", "building"), _product_name(data, b.type, current), _product_name(data, b.type, recipe_id)])
	if has_batch(b):
		return _fail("Finish (or cancel) its batch and collect it first.")
	var fee := switch_fee(data, b)
	if int(state.profile.currency) < fee:
		return _fail("Not enough money: switching costs %s." % _money_text(fee))
	return _ok({"fee": fee})


## Switch the building to another product (see can_switch_product): the fee is paid now, and
## its next batch makes the new product.
static func switch_product(state: Dictionary, data: Dictionary, building_id: String, recipe_id: String, now: float) -> Dictionary:
	if not find_building(state, building_id).is_empty():
		settle(state, data, now)  # its batch may have just been collected or finished
	var check := can_switch_product(state, data, building_id, recipe_id)
	if not check.ok:
		return check
	var fee := int(check.fee)
	state.profile.currency -= fee
	var spending: Dictionary = stats(state).spending
	spending["switch_fees"] = int(spending.get("switch_fees", 0)) + fee
	find_building(state, building_id)["product"] = recipe_id
	return check


## What demolishing a building would give back (changes nothing): no money, but every unit of
## material it and its upgrades were built with ("materials", b.materials) and the goods inside it
## ("goods"), all into the warehouse, so there must be room for them. Only buildings the player
## can build can be demolished, so starters stay.
static func can_demolish(state: Dictionary, data: Dictionary, building_id: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	var def: Dictionary = data.buildings.get(b.type, {})
	if is_hut(data, b):
		return _fail("A homeless household lives here. The hut goes by itself once they have a real home: build homes they can afford.")
	if not def.get("buildable", false):
		return _fail("This building can't be demolished.")
	if def.get("category", "") == "storage" and _count_category(state, data, "storage") <= 1:
		return _fail("You need at least one warehouse.")
	if is_crew_office(data, b) and _count_category(state, data, def.get("category", "")) <= 1:
		return _fail("You need at least one Construction Office: its workers build everything.")
	if has_batch(b):
		return _fail(BATCH_BUSY)
	var goods := _goods_inside(data, b)
	var materials: Dictionary = b.get("materials", {}).duplicate()
	var room := warehouse_cap(state, data) - storage_capacity(state, data, b)  # a warehouse takes its room with it
	if warehouse_total(state) + _total(goods) + _total(materials) > room:
		if def.get("category", "") == "storage":
			return _fail("The other warehouses don't have room for your goods and this one's materials. Make room first.")
		return _fail("Not enough room in the warehouse for its materials (%d) and what's inside. Make room first." % (_total(materials) + _total(goods)))
	return _ok({"materials": materials, "goods": goods})


## Why a building with a batch can't be demolished, suspended or upgraded.
const BATCH_BUSY := "It has a batch. Let it finish (or cancel it) and collect everything first."
## Why an upgrade can't start: it takes its materials only from the warehouse, never buys them.
const MISSING_MATERIALS := "Not enough materials in the warehouse (missing %s). Buy them at the Trading Post or produce them first."


## What a building hands back when its work is stopped for good (demolish, suspend): goods left
## in its storage and, for a Supermarket, what's still unsold on its shelves. (A building with a
## batch can't be stopped: see BATCH_BUSY.)
static func _goods_inside(_data: Dictionary, b: Dictionary) -> Dictionary:
	var goods: Dictionary = b.get("storage", {}).duplicate()
	for shelf in b.get("shelves", []):  # a Supermarket: what's still unsold on its shelves
		if not shelf.is_empty() and _unsold(shelf) > 0:
			_add_to(goods, {shelf.res: _unsold(shelf)})
	return goods


## The cost tags (cents) of _goods_inside: storage's tags and the shelves' share of what they cost.
static func _goods_inside_cost(_state: Dictionary, _data: Dictionary, b: Dictionary) -> Dictionary:
	var costs: Dictionary = _costs(b, "storage_cost").duplicate()
	for shelf in b.get("shelves", []):
		if not shelf.is_empty() and _unsold(shelf) > 0:
			_put_cost(costs, {shelf.res: float(shelf.get("cost", 0.0)) * _unsold(shelf) / int(shelf.qty)})
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
## Whether this kind of building has a Suspend button at all: it needs workers, and
## buildings.json can say "suspendable": false (the Warehouse and the Construction Office).
static func can_be_suspended(data: Dictionary, type_id: String) -> bool:
	var def: Dictionary = data.buildings.get(type_id, {})
	return int(def.get("max_workers", 0)) > 0 and def.get("suspendable", true)


static func can_suspend(state: Dictionary, data: Dictionary, building_id: String) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if max_workers(data, b) <= 0 or not can_be_suspended(data, b.type):
		return _fail("This building can't be switched off.")
	if is_suspended(b):
		return _fail("It's already suspended.")
	if not is_built(b, float(state.get("settled_at", 0.0))):
		return _fail(_unfinished(b, float(state.get("settled_at", 0.0))))
	if has_batch(b):
		return _fail(BATCH_BUSY)
	if warehouse_total(state) > warehouse_cap(state, data) - storage_capacity(state, data, b):
		return _fail("The other warehouses don't have room for your goods. Make room first.")
	return _ok({"goods": _goods_inside(data, b)})


## Suspend: what's inside is emptied into the warehouse (what doesn't fit stays inside to be
## collected later) and the workers go home. Returns "moved" (into the warehouse) and "kept"
## (left in the building).
static func suspend(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)
	var check := can_suspend(state, data, building_id)
	if not check.ok:
		return check
	var costs := _goods_inside_cost(state, data, b)  # the goods keep their cost tags
	_take_down_all_shelves(state, data, b, now)  # a Supermarket is paid for what it sold so far
	b["storage"] = {}
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
	_take_down_all_shelves(state, data, b, now)  # a Supermarket is paid for what it sold so far
	state.buildings.erase(b)
	_add_to(state.inventory, check.goods)
	_put_cost(_costs(state, "inventory_cost"), costs)  # the goods keep their cost tags
	# Its materials go back into the warehouse at what they really cost (b.materials_cost).
	_add_to(state.inventory, check.materials)
	_put_cost(_costs(state, "inventory_cost"), b.get("materials_cost", {}))
	# Its workers are freed for other posts. Nobody leaves: households that lost their home move
	# into other homes, or become homeless and put up Makeshift Huts (_hire updates them).
	_hire(state, data, now)
	return check


# --- Construction (plan.md §5.15) ------------------------------------------------
# Building and upgrading need materials (Bricks, Cement, Steel, Construction materials: items in
# resources.json of category "building_material") and a construction crew. A building's
# "materials" in buildings.json are its Level 1 amounts; each level needs
# construction.level_growth times the level below (2 = doubles). The warehouse's own materials
# are used first (construction_plan); the rest is bought from an in-game supplier when the work
# starts, at that hour's market price (material_price). The crew is paid once,
# construction.labor_share of the materials' value at that hour's prices (warehouse materials
# count too: they still need building with). All of it is paid at the start, so work never
# stalls halfway. Each building remembers every unit of material it was built with and what it
# really cost (b.materials, b.materials_cost): demolishing puts them back in the warehouse. Data
# without materials (the test data) can still set a fixed cash "build_cost" / upgrade "cost" and
# its own "build_time" / upgrade "time".

static func _construction(data: Dictionary) -> Dictionary:
	return data.config.get("construction", {})


## A construction material's price today, in cents: its base price plus or minus up to
## price_swing, a new price every price_change_seconds. Worked out from the time alone (nothing
## is saved), so the same hour always has the same price, away or playing.
static func material_price(data: Dictionary, material_id: String, now: float) -> int:
	return _material_price(data, material_id, now, false)


static func _material_price(data: Dictionary, material_id: String, now: float, at_base: bool) -> int:
	var c := _construction(data)
	var base := float(data.resources.get(material_id, {}).get("price", 0.0))
	if at_base or base <= 0.0:
		return cents(base)
	var slot := floori(now / maxf(float(c.get("price_change_seconds", 3600.0)), 1.0))
	# A fixed "random" number from -1 to 1 for this material and hour: the same every time it's
	# worked out (scrambled so one hour's price says nothing about the next).
	var h := _scramble(hash("%s:%d" % [material_id, slot]))
	var r := float(h & 0xFFFF) / 65535.0 * 2.0 - 1.0
	var swing := clampf(float(c.get("price_swing", 0.0)), 0.0, 0.9)
	return maxi(cents(base * (1.0 + swing * r)), 1)


## Mixes a whole number's bits thoroughly (a standard 32-bit integer hash), so numbers that are
## close together come out far apart.
static func _scramble(n: int) -> int:
	n &= 0xFFFFFFFF
	n = ((n ^ (n >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	n = ((n ^ (n >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return n ^ (n >> 16)


## When today's material prices change next (the start of the next price slot).
static func next_price_change_at(data: Dictionary, now: float) -> float:
	var step := maxf(float(_construction(data).get("price_change_seconds", 3600.0)), 1.0)
	return (floori(now / step) + 1) * step


## What building (level 1) or upgrading to `level` needs: {material id: amount, ..., "crew":
## construction workers}. Each level needs level_growth times the level below. The crew grows by
## construction.crew_per_level each level when the config has it (1 worker to build, 2 to reach
## Level 2, 3 for Level 3...), else like the materials. A building with no materials and no crew
## of its own (City Hall, huts) needs no crew either.
static func construction_needs(data: Dictionary, type_id: String, level: int) -> Dictionary:
	var def: Dictionary = data.buildings.get(type_id, {})
	var factor := pow(maxf(float(_construction(data).get("level_growth", 1.0)), 1.0), maxi(level, 1) - 1)
	var needs := {}
	var materials: Dictionary = def.get("materials", {})
	for m in materials:
		needs[m] = roundi(float(materials[m]) * factor)
	var crew := 0.0
	if def.has("crew") or not materials.is_empty():
		crew = float(def.get("crew", _construction(data).get("crew", 0)))
	if _construction(data).has("crew_per_level"):
		needs["crew"] = roundi(crew + float(_construction(data).crew_per_level) * (maxi(level, 1) - 1))
	else:
		needs["crew"] = roundi(crew * factor)
	return needs


## How long building (level 1) or upgrading to `level` takes, in seconds: the building's own
## "build_time" / the upgrade's own "time" if it has one, else construction.level_seconds (levels
## past the list take its last time; no list = at once).
static func construction_seconds(data: Dictionary, type_id: String, level: int) -> float:
	var def: Dictionary = data.buildings.get(type_id, {})
	if level <= 1 and def.has("build_time"):
		return float(def.build_time)
	var upgrades: Array = def.get("upgrades", [])
	if level >= 2 and level - 2 < upgrades.size() and upgrades[level - 2].has("time"):
		return float(upgrades[level - 2].time)
	var times: Array = _construction(data).get("level_seconds", [])
	if times.is_empty():
		return 0.0
	return float(times[clampi(level, 1, times.size()) - 1])


## True when `resource_id` is a building material (resources.json category "building_material"):
## what buildings and upgrades are made of.
static func is_building_material(data: Dictionary, resource_id: String) -> bool:
	return str(data.resources.get(resource_id, {}).get("category", "")) == "building_material"


## What building (level 1) or upgrading to `level` costs at `now`'s prices when every material is
## bought: {"cost" (cents, all of it), "seconds", "lines": [{"id", "name", "unit", "amount",
## "price" (cents each), "cost"}]}. The crew's line has id "labor", amount = workers, "share"
## (construction.labor_share) and cost = that share of the materials' value. A fixed cash part
## (older data's build_cost / upgrade cost) is in "cost" but has no line. See construction_plan
## for what it costs with the warehouse's own materials.
static func construction_quote(data: Dictionary, type_id: String, level: int, now: float) -> Dictionary:
	return _quote(data, type_id, level, now, false)


## construction_quote with the warehouse's own materials used first: each material line also has
## "from_stock" (units taken from the warehouse) and "buy" (units bought), and its "cost" is
## only what's bought. "cost" = the money it takes (bought materials + labor + any fixed part),
## "stock_value" = the cost tags (cents) of the warehouse materials it would use.
static func construction_plan(state: Dictionary, data: Dictionary, type_id: String, level: int, now: float) -> Dictionary:
	var quote := construction_quote(data, type_id, level, now)
	var stock_value := 0.0
	for line in quote.lines:
		if line.id == "labor":
			continue
		var from_stock := mini(int(line.amount), int(state.inventory.get(line.id, 0)))
		line["from_stock"] = from_stock
		line["buy"] = int(line.amount) - from_stock
		line.cost = int(line.buy) * int(line.price)
		quote.cost = int(quote.cost) - from_stock * int(line.price)
		stock_value += average_cost(state, line.id) * from_stock
	quote["stock_value"] = stock_value
	return quote


## Building or upgrading `b` with `plan` (construction_plan): its warehouse materials leave the
## warehouse with their cost tags, and every unit used (taken or bought) is recorded on `b` at what
## it really cost. Returns the cents of warehouse materials used (rounded), for its value.
static func _use_materials(state: Dictionary, b: Dictionary, plan: Dictionary) -> int:
	var units := {}
	var costs := {}
	var stock := {}
	for line in plan.get("lines", []):
		if line.id == "labor" or int(line.amount) <= 0:
			continue
		units[line.id] = int(line.amount)
		costs[line.id] = float(int(line.get("buy", line.amount)) * int(line.price))
		if int(line.get("from_stock", 0)) > 0:
			stock[line.id] = int(line.from_stock)
	var taken := _take_cost(state.inventory, _costs(state, "inventory_cost"), stock)
	_remove_from(state.inventory, stock)
	_put_cost(costs, taken)
	_record_materials(b, units, costs)
	var value := 0.0
	for res in taken:
		value += float(taken[res])
	return roundi(value)


## Adds materials to what `b` was built with: `units` {material: units}, `costs` {material: cents}.
static func _record_materials(b: Dictionary, units: Dictionary, costs: Dictionary) -> void:
	if units.is_empty():
		return
	if not b.has("materials"):
		b["materials"] = {}
	_add_to(b.materials, units)
	_put_cost(_costs(b, "materials_cost"), costs)


## Records on `b` the materials of building it and its upgrades up to `level`, at base prices: for
## buildings nobody bought (the starting buildings, free ones, and those in older saves).
static func record_base_materials(data: Dictionary, b: Dictionary, level: int) -> void:
	for l in range(1, mini(level, max_level(data, b.type)) + 1):
		var needs := construction_needs(data, b.type, l)
		var units := {}
		var costs := {}
		for m in needs:
			if m == "crew" or int(needs[m]) <= 0:
				continue
			units[m] = int(needs[m])
			costs[m] = float(int(needs[m]) * _material_price(data, m, 0.0, true))
		_record_materials(b, units, costs)


static func _quote(data: Dictionary, type_id: String, level: int, now: float, at_base: bool) -> Dictionary:
	var def: Dictionary = data.buildings.get(type_id, {})
	var seconds := construction_seconds(data, type_id, level)
	var total := 0
	if level <= 1:
		total += cents(float(def.get("build_cost", 0)))
	elif level - 2 < def.get("upgrades", []).size():
		total += cents(float(def.upgrades[level - 2].get("cost", 0)))
	var lines: Array = []
	var needs := construction_needs(data, type_id, level)
	var materials_value := 0
	for m in needs:
		if m == "crew" or int(needs[m]) <= 0:
			continue
		var price := _material_price(data, m, now, at_base)
		var info: Dictionary = data.resources.get(m, {})
		lines.append({"id": m, "name": str(info.get("name", m)), "unit": str(info.get("unit", "")),
			"amount": int(needs[m]), "price": price, "cost": int(needs[m]) * price})
		materials_value += int(needs[m]) * price
	total += materials_value
	if int(needs.crew) > 0:
		# The crew is paid a share of the materials' value, however long the work takes.
		var share := clampf(float(_construction(data).get("labor_share", 0.0)), 0.0, 1.0)
		var labor := roundi(materials_value * share)
		lines.append({"id": "labor", "name": "Labor", "unit": "worker", "amount": int(needs.crew),
			"share": share, "cost": labor})
		total += labor
	return {"cost": total, "seconds": seconds, "lines": lines}


## What one step (building = level 1, or the upgrade to `level`) is worth: its cost at base
## prices, with no market swing. In cents.
static func level_value(data: Dictionary, type_id: String, level: int) -> int:
	return int(_quote(data, type_id, level, 0.0, true).cost)


## What a building is worth at base prices: building it plus its upgrades up to `level`, in
## cents. Used for its share in selling prices (§5.12), demolish refunds and starting buildings.
static func construction_value(data: Dictionary, type_id: String, level := 1) -> int:
	var value := 0
	for l in range(1, mini(level, max_level(data, type_id)) + 1):
		value += level_value(data, type_id, l)
	return value


# --- Construction workers (plan.md §5.15) -------------------------------------------
# The Construction Office ("construction_crew" in buildings.json) employs villagers as
# construction workers. Building something needs construction_needs' "crew" of them (1 for a new
# building, one more per upgrade level) and they're busy until the work is done, so the offices'
# workers limit how much can be built at once. They're paid per project (the labor line of
# construction_quote), never by the hour. Roads need no crew. Data with no Construction Office
# type (the test data) builds without workers.

## True when building and upgrading need free construction workers.
static func crew_on(data: Dictionary) -> bool:
	return crew_office_type(data) != ""


## The building type whose workers are the construction crew ("" if there's none).
static func crew_office_type(data: Dictionary) -> String:
	for type_id in data.buildings:
		var def: Variant = data.buildings[type_id]
		if typeof(def) == TYPE_DICTIONARY and def.get("construction_crew", false):
			return type_id
	return ""


static func is_crew_office(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("construction_crew", false))


## All construction workers: the workers at finished, working Construction Offices (an office
## being upgraded stays open).
static func crew_total(state: Dictionary, data: Dictionary, now: float) -> int:
	var total := 0
	for b in state.buildings:
		if is_crew_office(data, b) and is_built(b, now) and not is_suspended(b):
			total += hired(b)
	return total


## The work keeping construction workers busy at `now`, soonest done first: [{"building_id",
## "crew", "until"}]. A building going up needs its Level 1 crew, an upgrade the next level's.
static func crew_jobs(state: Dictionary, data: Dictionary, now: float) -> Array:
	var jobs: Array = []
	for b in state.buildings:
		var crew := 0
		var until := 0.0
		if is_upgrading(b, now):
			crew = int(construction_needs(data, b.type, building_level(b) + 1).crew)
			until = float(b.upgrade_done_at)
		elif not is_built(b, now):
			crew = int(construction_needs(data, b.type, 1).crew)
			until = built_at(b)
		if crew > 0:
			jobs.append({"building_id": b.id, "crew": crew, "until": until})
	jobs.sort_custom(func(a, c): return float(a.until) < float(c.until))
	return jobs


## Construction workers busy right now.
static func crew_busy(state: Dictionary, data: Dictionary, now: float) -> int:
	var busy := 0
	for job in crew_jobs(state, data, now):
		busy += int(job.crew)
	return busy


## Construction workers free for new work right now.
static func crew_free(state: Dictionary, data: Dictionary, now: float) -> int:
	return maxi(crew_total(state, data, now) - crew_busy(state, data, now), 0)


## Whether `crew` construction workers are free for new work: {} when they are (or the game has
## no Construction Office), else a failure that says why and, when it's only a matter of waiting,
## "crew_free_at": when enough will be free.
static func _check_crew(state: Dictionary, data: Dictionary, crew: int, now: float) -> Dictionary:
	if crew <= 0 or not crew_on(data):
		return {}
	var total := crew_total(state, data, now)
	var free := crew_free(state, data, now)
	if free >= crew:
		return {}
	var more := " Upgrade your Construction Office or build another for more."
	if total == 0:
		return _fail("No construction workers: your Construction Office needs workers (and a road) to build anything.")
	if total < crew:
		return _fail("This needs %s, but your Construction Offices have only %d.%s" % [_crew_text(crew), total, more])
	var at := now
	for job in crew_jobs(state, data, now):
		free += int(job.crew)
		at = float(job.until)
		if free >= crew:
			break
	var fail := _fail("This needs %s, and only %d %s free. Enough are free in %s.%s" % [_crew_text(crew),
		crew_free(state, data, now), "is" if crew_free(state, data, now) == 1 else "are", _wait_text(at - now), more])
	fail["crew_free_at"] = at
	return fail


static func _crew_text(crew: int) -> String:
	return "1 construction worker" if crew == 1 else "%d construction workers" % crew


## A wait in words: "35 min", "2 h", "2 h 10 min".
static func _wait_text(seconds: float) -> String:
	var minutes := maxi(ceili(seconds / 60.0), 1)
	if minutes < 60:
		return "%d min" % minutes
	if minutes % 60 == 0:
		return "%d h" % (minutes / 60)
	return "%d h %d min" % [minutes / 60, minutes % 60]


## For saves from before the Construction Office: a free one, already standing, on the free tile
## nearest City Hall with a linked road beside it (else the nearest free tile). It counts in the
## starting capital like the starting buildings. Nothing happens if the plot is full.
static func add_free_crew_office(state: Dictionary, data: Dictionary) -> void:
	var type_id := crew_office_type(data)
	if type_id == "" or _count_category(state, data, data.buildings[type_id].get("category", "")) > 0:
		return
	var cell := _free_spot_by_road(state, data, type_id)
	if cell == Vector2i(-1, -1):
		return
	_add_free_building(state, data, type_id, cell)


## The free spot for a building of `type_id` nearest City Hall (ring by ring) with a linked road
## beside it, else the spot _free_spot_near_centre would give.
static func _free_spot_by_road(state: Dictionary, data: Dictionary, type_id: String) -> Vector2i:
	var linked := linked_roads(state, data)
	var hubs := _hub_cells(state, data)
	var grid: Array = state.plot.grid_size
	var map := _plot_map(state, data)
	for hub in hubs:
		for ring in range(1, maxi(int(grid[0]), int(grid[1])) + 1):
			for dy in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					var cell: Vector2i = hub + Vector2i(dx, dy)
					if maxi(absi(dx), absi(dy)) == ring and _footprint_problem(state, data, type_id, cell, "", map) == "" and _beside(linked, footprint(data, type_id, cell)):
						return cell
	return _free_spot_near_centre(state, data, type_id)


# --- Upgrades (plan.md §5.15) ----------------------------------------------------
# A building's "upgrades" in buildings.json list Level 2, Level 3, ...: the numbers that change
# at that level (max_workers, capacity, shelves, households); numbers a
# level leaves out stay as the level below had them. An upgrade costs materials + a crew like
# building does (see Construction above), doubling each level.
# Farms, mills, bakeries and shops close while being upgraded: no workers, no wages, and work
# in progress waits (a batch half done is still half done afterwards). Homes and warehouses
# stay in use. Either way the new level's numbers count from the moment it's finished.

## The building's level (1 = as built).
static func building_level(b: Dictionary) -> int:
	return maxi(int(b.get("level", 1)), 1)


## The highest level this kind of building can reach (1 = no upgrades).
static func max_level(data: Dictionary, type_id: String) -> int:
	return 1 + data.buildings.get(type_id, {}).get("upgrades", []).size()


## A number from buildings.json at the building's level: the latest level up to its own that
## sets `key`, else the building's own value, else `default`.
static func level_stat(data: Dictionary, b: Dictionary, key: String, default: Variant) -> Variant:
	var def: Dictionary = data.buildings.get(b.type, {})
	var value: Variant = def.get(key, default)
	var upgrades: Array = def.get("upgrades", [])
	for i in mini(building_level(b) - 1, upgrades.size()):
		value = upgrades[i].get(key, value)
	return value


## True while the building is being upgraded (it reaches the next level at "upgrade_done_at").
static func is_upgrading(b: Dictionary, now: float) -> bool:
	return b.has("upgrade_done_at") and now < float(b.upgrade_done_at)


## Homes, warehouses, Construction Offices, service buildings (Clinic, Police Station...) and
## Electric Substations (power carried, none made) stay in use while being upgraded; everything
## else closes.
static func stays_open_while_upgrading(data: Dictionary, b: Dictionary) -> bool:
	var def: Dictionary = data.buildings.get(b.type, {})
	if float(def.get("power_radius", 0.0)) > 0.0 and float(def.get("power_supply", 0.0)) <= 0.0:
		return true
	return def.get("category", "") in ["residential", "storage", "construction", "service"]


## The next level's entry in buildings.json (what changes), or {} at the top.
static func next_upgrade(data: Dictionary, b: Dictionary) -> Dictionary:
	var upgrades: Array = data.buildings.get(b.type, {}).get("upgrades", [])
	var index := building_level(b) - 1
	return upgrades[index] if index < upgrades.size() else {}


## Whether the building could start its next upgrade now (changes nothing):
## {"ok", "error", "level" (the one it would reach), "cost" (cents, at `now`'s prices), "seconds",
## "lines" (see construction_quote)}.
static func can_upgrade(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if is_upgrading(b, now):
		return _fail("It's already being upgraded.")
	if not is_built(b, now):
		return _fail(_unfinished(b, now))
	var next := next_upgrade(data, b)
	if next.is_empty():
		if max_level(data, b.type) <= 1:
			return _fail("This building can't be upgraded.")
		return _fail("It's at the highest level (%d)." % building_level(b))
	if is_suspended(b):
		return _fail("It's suspended. Resume it first.")
	if has_batch(b) and not stays_open_while_upgrading(data, b):
		return _fail(BATCH_BUSY)
	var crew := _check_crew(state, data, int(construction_needs(data, b.type, building_level(b) + 1).crew), now)
	if not crew.is_empty():
		return crew
	var quote := construction_plan(state, data, b.type, building_level(b) + 1, now)
	# Upgrades never buy materials: every unit must already be in the warehouse.
	var missing: Array[String] = []
	for line in quote.lines:
		if line.id != "labor" and int(line.get("buy", 0)) > 0:
			missing.append("%d %s" % [int(line.buy), line.name])
	if not missing.is_empty():
		return _fail(MISSING_MATERIALS % ", ".join(missing))
	if state.profile.currency < int(quote.cost):
		return _fail("Not enough money.")
	quote["level"] = building_level(b) + 1
	return _ok(quote)


## Start the next upgrade: take its materials from the warehouse (all of them must be there) and
## pay its crew now; the building reaches the next level after its time.
## A building that closes for it (see stays_open_while_upgrading) sends its workers home and
## pauses its work until then.
static func upgrade(state: Dictionary, data: Dictionary, building_id: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # time so far was worked at the old level
	var check := can_upgrade(state, data, building_id, now)
	if not check.ok:
		return check
	state.profile.currency -= int(check.cost)
	stats(state).spending.construction += int(check.cost)
	var value := int(check.cost) + _use_materials(state, b, check)  # money + warehouse materials used
	b["paid"] = int(b.get("paid", 0)) + value  # its value on the balance sheet...
	b["upgrade_paid"] = value  # ...this part counted as "being built" until it's done
	# A clock set backwards never moves the start before the time already worked out.
	var start := maxf(now, float(state.get("settled_at", now)))
	var done := start + float(check.seconds)
	b["upgrade_started_at"] = start
	b["upgrade_done_at"] = done
	if not stays_open_while_upgrading(data, b):
		b.built_at = done  # closed like a building under construction: no posts, no work
	_hire(state, data, start)  # its workers are freed for other posts (or it finishes at once)
	return _ok(check)


## Upgrades finished by `now` reach their new level (settling splits time at that moment, see
## _next_staffing_change, so the new numbers count from exactly then, away or playing).
static func _finish_upgrades(state: Dictionary, now: float) -> void:
	for b in state.buildings:
		if b.has("upgrade_done_at") and now >= float(b.upgrade_done_at):
			b["level"] = building_level(b) + 1
			b.erase("upgrade_done_at")
			b.erase("upgrade_started_at")
			b.erase("upgrade_paid")


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
	# What the sold goods cost to make (their cost tags), so the sale can show the profit.
	var made_for := float(_take_cost(state.inventory, _costs(state, "inventory_cost"), {resource_id: qty}).get(resource_id, 0.0))
	_remove_from(state.inventory, {resource_id: qty})
	return _ok(_record_sale(state, data, resource_id, qty, gross, made_for, now))


## Books a sale of `qty` × `resource_id` worth `gross` cents at time `now`, wherever it was sold
## (the Retailer, a Supermarket shelf): sales tax (§5.9) comes off, the rest goes to cash, and the
## tax window and statistics remember it. `made_for` = what the goods cost to make (cents, their
## cost tags). Returns, in cents: {"earned", "gross", "tax", "rate", "cost", "profit"}.
static func _record_sale(state: Dictionary, data: Dictionary, resource_id: String, qty: int, gross: int, made_for: float, now: float) -> Dictionary:
	var tax := sales_tax(state, data, gross, now)
	var earned := gross - tax
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
	return {"earned": earned, "gross": gross, "tax": tax, "rate": float(tax) / gross if gross > 0 else 0.0,
		"cost": roundi(made_for), "profit": earned - roundi(made_for)}


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


# --- Trading Post (plan.md §5.22) -------------------------------------------------
# A trader from off the island, at the Trading Post (one per village). It buys ANY item (raw,
# half-made or finished) at trade.sell_share of its normal price (§5.12) and sells any item at
# trade.buy_share (game_config.json). Instant, with no demand limit: just a worse price than the
# village pays. Selling pays sales tax like any sale (§5.9); bought goods go into the Warehouse
# with what was paid as their cost tag (§5.14). It gives raw and half-made goods a value, so a
# player can specialise (buy flour instead of farming wheat). The start of the Dock (§5.11).

## True when the village has a Trading Post that's built and not suspended.
static func has_trading_post(state: Dictionary, data: Dictionary, now: float) -> bool:
	for b in state.buildings:
		if data.buildings.get(b.type, {}).get("category", "") == "trade" and is_built(b, now) and not is_suspended(b):
			return true
	return false


## The trader's price for one unit, in cents: side "sell" = what it pays you, "buy" = what you
## pay it (at least 1 cent).
static func trade_price(data: Dictionary, resource_id: String, side: String) -> int:
	var shares: Dictionary = data.config.get("trade", {})
	if side == "sell":
		return maxi(roundi(unit_price(data, resource_id) * float(shares.get("sell_share", 1.0))), 0)
	return maxi(roundi(unit_price(data, resource_id) * float(shares.get("buy_share", 1.0))), 1)


## Whether `qty` × `resource_id` could be sold to the trader now (changes nothing): {"ok",
## "error", "price" (cents each), "gross", "tax", "earned", "cost" (their cost tags), "profit"}.
static func can_trade_sell(state: Dictionary, data: Dictionary, resource_id: String, qty: int, now: float) -> Dictionary:
	if not has_trading_post(state, data, now):
		return _fail("You need a Trading Post to trade (Build → Shops).")
	if not data.resources.has(resource_id):
		return _fail("Unknown item.")
	if qty <= 0:
		return _fail("Choose how many to sell.")
	if int(state.inventory.get(resource_id, 0)) < qty:
		return _fail("You don't have that many.")
	var price := trade_price(data, resource_id, "sell")
	var gross := qty * price
	var tax := sales_tax(state, data, gross, now)
	var cost := roundi(average_cost(state, resource_id) * qty)
	return _ok({"price": price, "gross": gross, "tax": tax, "earned": gross - tax, "cost": cost, "profit": gross - tax - cost})


## Sell to the trader (see can_trade_sell): the goods leave the Warehouse, the money (after
## sales tax) reaches cash at once.
static func trade_sell(state: Dictionary, data: Dictionary, resource_id: String, qty: int, now: float) -> Dictionary:
	settle(state, data, now)
	var check := can_trade_sell(state, data, resource_id, qty, now)
	if not check.ok:
		return check
	var made_for := float(_take_cost(state.inventory, _costs(state, "inventory_cost"), {resource_id: qty}).get(resource_id, 0.0))
	_remove_from(state.inventory, {resource_id: qty})
	var sale := _record_sale(state, data, resource_id, qty, int(check.gross), made_for, now)
	sale["price"] = int(check.price)
	return _ok(sale)


## Whether `qty` × `resource_id` could be bought from the trader now (changes nothing): {"ok",
## "error", "price" (cents each), "cost" (all of it)}. It needs the cash (no buying into debt)
## and room in the Warehouse.
static func can_trade_buy(state: Dictionary, data: Dictionary, resource_id: String, qty: int, now: float) -> Dictionary:
	if not has_trading_post(state, data, now):
		return _fail("You need a Trading Post to trade (Build → Shops).")
	if not data.resources.has(resource_id):
		return _fail("Unknown item.")
	if qty <= 0:
		return _fail("Choose how many to buy.")
	var price := trade_price(data, resource_id, "buy")
	var cost := qty * price
	if int(state.profile.currency) < cost:
		return _fail("Not enough money: that costs %s." % _money_text(cost))
	if warehouse_total(state) + qty > warehouse_cap(state, data):
		return _fail("Not enough room in the warehouse.")
	return _ok({"price": price, "cost": cost})


## Buy from the trader (see can_trade_buy): paid now, counted as "Trading Post purchases"; the
## goods go into the Warehouse with what was paid as their cost tag.
static func trade_buy(state: Dictionary, data: Dictionary, resource_id: String, qty: int, now: float) -> Dictionary:
	settle(state, data, now)
	var check := can_trade_buy(state, data, resource_id, qty, now)
	if not check.ok:
		return check
	var cost := int(check.cost)
	state.profile.currency -= cost
	var spending: Dictionary = stats(state).spending
	spending["purchases"] = int(spending.get("purchases", 0)) + cost
	_add_to(state.inventory, {resource_id: qty})
	_put_cost(_costs(state, "inventory_cost"), {resource_id: float(cost)})
	return check


# --- Supermarket (plan.md §5.16) -------------------------------------------------
# A retail building sells finished food to the village from its shelves: one product per shelf,
# several shelves at once, each product on only one shelf per store. Every store sells on its own,
# but the village has one appetite for a product, so stores selling the same product share it.
# When goods go on a shelf, their price and "rate" are fixed:
#   price = the normal price (§5.12) × the price tag's price (Sale 0.9, Premium 1.1, ...)
#   rate  = people × the item's appetite × the price tag's speed   (units per hour)
# While selling, a shelf sells rate × shoppers × speed ÷ stores selling it per hour: shoppers =
# +10% for each other product on the store's shelves ("one-stop shop"), speed = its workers (3 of
# 4 = 75%), and 2 stores selling flour each sell it half as fast (selling_counts). Those only
# change at a few moments (a shelf sells out or is stocked, workers come or go) and settling splits
# time there, so each stretch is one calculation. A shelf is paid for when it sells out, minus
# sales tax.

## How many of this item one villager buys per hour at the Normal price (0 = shops don't sell it).
static func appetite(data: Dictionary, resource_id: String) -> float:
	return float(data.resources.get(resource_id, {}).get("appetite", 0.0))


## The items shops can sell (finished goods: they have an appetite), in resources.json order.
static func shop_products(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for res in data.resources:
		if appetite(data, res) > 0.0:
			out.append(res)
	return out


## An item's category ("category" in resources.json: food, crop, ingredient, ...; their names are
## in game_config.json item_categories). An item people buy with no category counts as food, so
## older data keeps working; anything else without one has "".
static func item_category(data: Dictionary, resource_id: String) -> String:
	var def: Dictionary = data.resources.get(resource_id, {})
	if def.has("category"):
		return str(def.category)
	return "food" if appetite(data, resource_id) > 0.0 else ""


## True for food people buy: what the Food need counts (plan.md §5.6).
static func is_food(data: Dictionary, resource_id: String) -> bool:
	return appetite(data, resource_id) > 0.0 and item_category(data, resource_id) == "food"


## Whether a store of `type_id` can sell `resource_id`: people must buy it (an appetite), and the
## store must sell its category ("sells" in buildings.json; a store without that list sells
## anything people buy).
static func store_sells(data: Dictionary, type_id: String, resource_id: String) -> bool:
	if appetite(data, resource_id) <= 0.0:
		return false
	var sells: Array = data.buildings.get(type_id, {}).get("sells", [])
	return sells.is_empty() or sells.has(item_category(data, resource_id))


## The items a store of `type_id` can sell, in resources.json order.
static func store_products(data: Dictionary, type_id: String) -> Array[String]:
	var out: Array[String] = []
	for res in data.resources:
		if store_sells(data, type_id, res):
			out.append(res)
	return out


## The price tags, cheapest first: {tag: {"name", "price" (share of the normal price), "speed"}}.
static func price_tags(data: Dictionary) -> Dictionary:
	return data.config.get("retail", {}).get("price_tags", {"normal": {"name": "Normal", "price": 1.0, "speed": 1.0}})


## The store's shelves, one entry per shelf ({} = empty). A copy of the list: read it, don't change it.
static func shelves(data: Dictionary, b: Dictionary) -> Array:
	var out: Array = b.get("shelves", []).duplicate()
	while out.size() < int(level_stat(data, b, "shelves", 0)):
		out.append({})
	return out


## How many different products are on the store's shelves.
static func products_on_shelves(b: Dictionary) -> int:
	var seen := {}
	for shelf in b.get("shelves", []):
		if not shelf.is_empty():
			seen[shelf.res] = true
	return seen.size()


## Shoppers: 1.0, plus retail.variety_bonus (+10%) for each different product beyond the first.
## `extra_products` counts products about to go on a shelf (for previews).
static func shoppers(data: Dictionary, b: Dictionary, extra_products: int = 0) -> float:
	var products := products_on_shelves(b) + extra_products
	return 1.0 + float(data.config.get("retail", {}).get("variety_bonus", 0.0)) * maxi(products - 1, 0)


## True when this store already has `resource_id` on one of its shelves.
static func store_has_product(b: Dictionary, resource_id: String) -> bool:
	for shelf in b.get("shelves", []):
		if not shelf.is_empty() and shelf.res == resource_id:
			return true
	return false


## Where `resource_id` is on sale right now (the first store found): {"building_id", "index"},
## or {} if on no shelf.
static func shelf_selling(state: Dictionary, resource_id: String) -> Dictionary:
	for b in state.buildings:
		var list: Array = b.get("shelves", [])
		for i in list.size():
			if not list[i].is_empty() and list[i].res == resource_id:
				return {"building_id": b.id, "index": i}
	return {}


## What a shelf of this item at price tag `tag` would get right now: {"price" (cents each), "rate"
## (units per hour at full staff, before the shoppers bonus)}.
static func shelf_offer(state: Dictionary, data: Dictionary, resource_id: String, tag: String) -> Dictionary:
	var t: Dictionary = price_tags(data).get(tag, {})
	return {
		"price": roundi(unit_price(data, resource_id) * float(t.get("price", 1.0))),
		"rate": int(state.population.current) * appetite(data, resource_id) * float(t.get("speed", 1.0)),
	}


## Whether `qty` × `resource_id` could go on a free shelf at price tag `tag` (changes nothing).
## The UI uses this to grey out its button, and stock_shelf uses it too.
static func can_stock_shelf(state: Dictionary, data: Dictionary, building_id: String, resource_id: String, qty: int, tag: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	if data.buildings.get(b.type, {}).get("category", "") != "retail":
		return _fail("This building doesn't sell goods.")
	if not is_built(b, now):
		return _fail(_unfinished(b, now))
	if is_suspended(b):
		return _fail("It's suspended. Resume it first.")
	if appetite(data, resource_id) <= 0.0:
		return _fail("Shops don't sell %s: people only buy finished food." % _resource_name(data, resource_id))
	if not store_sells(data, b.type, resource_id):
		return _fail("A %s doesn't sell %s." % [data.buildings.get(b.type, {}).get("name", "store"), _resource_name(data, resource_id)])
	if not price_tags(data).has(tag):
		return _fail("Unknown price tag.")
	if qty <= 0:
		return _fail("Choose how many to put on the shelf.")
	if int(state.inventory.get(resource_id, 0)) < qty:
		return _fail("You don't have that many.")
	if store_has_product(b, resource_id):
		return _fail("%s is already on a shelf in this store. Wait for it to sell out, or sell it in another store." % _resource_name(data, resource_id))
	if _free_shelf(data, b) < 0:
		return _fail("Every shelf is full. Wait for one to sell out.")
	if int(state.population.current) <= 0:
		return _fail("Nobody lives in your village yet, so nobody would buy it.")
	return _ok()


## Put goods on a free shelf. They leave the warehouse now (with their cost tags), and their price
## and rate are fixed now (see shelf_offer). Returns "shelf" (its index) and "price" (cents each).
static func stock_shelf(state: Dictionary, data: Dictionary, building_id: String, resource_id: String, qty: int, tag: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # a shelf may have just sold out, freeing it
	var check := can_stock_shelf(state, data, building_id, resource_id, qty, tag, now)
	if not check.ok:
		return check
	var offer := shelf_offer(state, data, resource_id, tag)
	var cost := float(_take_cost(state.inventory, _costs(state, "inventory_cost"), {resource_id: qty}).get(resource_id, 0.0))
	_remove_from(state.inventory, {resource_id: qty})
	var list := shelves(data, b)
	var index := _free_shelf(data, b)
	list[index] = {"res": resource_id, "qty": qty, "sold": 0.0, "price": int(offer.price), "tag": tag,
		"rate": float(offer.rate), "cost": cost}
	b["shelves"] = list
	b.job_started_at = maxf(float(b.job_started_at), now)  # an empty store starts selling from now
	return _ok({"shelf": index, "price": int(offer.price)})


## What taking shelf `index` down would do (changes nothing): what's sold so far is paid for
## ("sold" units, "paid" cents before tax), the rest goes back to the warehouse ("back").
static func can_clear_shelf(state: Dictionary, data: Dictionary, building_id: String, index: int) -> Dictionary:
	var b := find_building(state, building_id)
	if b.is_empty():
		return _fail("Building not found.")
	var list := shelves(data, b)
	if index < 0 or index >= list.size() or list[index].is_empty():
		return _fail("That shelf is empty.")
	var shelf: Dictionary = list[index]
	var back := {}
	if _unsold(shelf) > 0:
		back[shelf.res] = _unsold(shelf)
	if warehouse_total(state) + _total(back) > warehouse_cap(state, data):
		return _fail("Not enough room in the warehouse to take them back.")
	var sold := int(shelf.qty) - _unsold(shelf)
	return _ok({"sold": sold, "paid": sold * int(shelf.price), "back": back})


## Take a shelf's goods down: what's sold so far is paid for, the rest goes back to the warehouse.
## Returns can_clear_shelf's answer plus "earned" (cents, after tax).
static func clear_shelf(state: Dictionary, data: Dictionary, building_id: String, index: int, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	if not b.is_empty():
		settle(state, data, now)  # it may have just sold out
	var check := can_clear_shelf(state, data, building_id, index)
	if not check.ok:
		return check
	var taken := _take_down_shelf(state, data, b, index, now)
	_add_to(state.inventory, taken.back)
	_put_cost(_costs(state, "inventory_cost"), taken.back_cost)
	check["earned"] = int(taken.earned)
	return check


## What putting `qty` × `resource_id` on a shelf at tag `tag` would bring (changes nothing):
## {"price" (cents each), "gross", "cost" (their cost tags), "tax" (at today's bracket), "profit"
## (cents), "per_hour" (how many the village would buy per hour, with this store's workers and
## shoppers, shared with the other stores selling it), "seconds" (to sell them all; INF when
## nobody would buy), "other_stores" (how many other stores sell it now)}.
static func stock_preview(state: Dictionary, data: Dictionary, building_id: String, resource_id: String, qty: int, tag: String, now: float) -> Dictionary:
	var b := find_building(state, building_id)
	var offer := shelf_offer(state, data, resource_id, tag)
	var gross := maxi(qty, 0) * int(offer.price)
	var cost := roundi(average_cost(state, resource_id) * maxi(qty, 0))
	var tax := sales_tax(state, data, gross, now)
	var per_hour := 0.0
	var others := 0
	if not b.is_empty():
		var has_it := store_has_product(b, resource_id)
		others = int(selling_counts(state, data, now).get(resource_id, 0))
		if has_it and building_speed(state, data, b, now) > 0.0:
			others -= 1  # this store is one of them
		per_hour = float(offer.rate) * shoppers(data, b, 0 if has_it else 1) * _staffed_share(data, b) / (others + 1)
	return {"price": int(offer.price), "gross": gross, "cost": cost, "tax": tax, "profit": gross - tax - cost,
		"per_hour": per_hour, "seconds": qty / per_hour * 3600.0 if per_hour > 0.0 else INF, "other_stores": others}


## Units of shelf `index` sold by `now` (time since the last settle counts at today's pace).
static func shelf_sold_now(state: Dictionary, data: Dictionary, b: Dictionary, index: int, now: float) -> float:
	var shelf: Dictionary = shelves(data, b)[index]
	if shelf.is_empty():
		return 0.0
	var since := maxf(now - float(state.get("settled_at", now)), 0.0)
	return minf(float(shelf.sold) + _shelf_pace(state, data, b, shelf, now) * since, float(shelf.qty))


## Seconds until shelf `index` sells out at today's pace (INF while it isn't selling).
static func shelf_time_left(state: Dictionary, data: Dictionary, b: Dictionary, index: int, now: float) -> float:
	var shelf: Dictionary = shelves(data, b)[index]
	var pace := 0.0 if shelf.is_empty() else _shelf_pace(state, data, b, shelf, now)
	if pace <= 0.0:
		return INF
	return (float(shelf.qty) - shelf_sold_now(state, data, b, index, now)) / pace


## Units per second this shelf sells right now: rate × shoppers × the store's speed ÷ the stores
## selling it.
static func _shelf_pace(state: Dictionary, data: Dictionary, b: Dictionary, shelf: Dictionary, now: float) -> float:
	var share := _demand_share(selling_counts(state, data, now), shelf.res)
	return float(shelf.rate) * shoppers(data, b) * building_speed(state, data, b, now) * share / 3600.0


## The next moment a shelf sells out at `speed`, from `t` (INF if none is selling).
static func _next_sell_out(state: Dictionary, data: Dictionary, b: Dictionary, t: float, speed: float) -> float:
	var per_second := shoppers(data, b) * speed / 3600.0
	var selling := selling_counts(state, data, t)
	var next := INF
	for shelf in b.get("shelves", []):
		if not shelf.is_empty() and float(shelf.rate) > 0.0:
			var pace := float(shelf.rate) * per_second * _demand_share(selling, shelf.res)
			next = minf(next, t + (float(shelf.qty) - float(shelf.sold)) / pace)
	return next + 0.000001


## Sells from the shelves over [t0, t1] at the store's `speed`, with the shoppers bonus and the
## stores sharing each product (`selling`, see selling_counts) as they were at t0 (settling splits
## time when a shelf sells out, so they can't change midway). A shelf that sells out is paid for
## at t1. Returns {"store_sales": cents earned, "sold:<item>": units}.
static func _settle_retail(state: Dictionary, data: Dictionary, b: Dictionary, t0: float, t1: float, speed: float, selling: Dictionary) -> Dictionary:
	var report := {}
	if is_suspended(b):
		return report
	var from := maxf(t0, float(b.job_started_at))
	if t1 <= from:
		return report  # still being built, or the clock moved backwards: never go back in time
	var per_hour := shoppers(data, b) * speed
	var list: Array = b.get("shelves", [])
	for i in list.size():
		var shelf: Dictionary = list[i]
		if shelf.is_empty():
			continue
		var share := _demand_share(selling, shelf.res)
		shelf.sold = minf(float(shelf.sold) + float(shelf.rate) * per_hour * share * (t1 - from) / 3600.0, float(shelf.qty))
		if float(shelf.sold) >= float(shelf.qty) - 0.0001:
			shelf.sold = float(shelf.qty)  # sold out (the tiny allowance covers rounding)
			var taken := _take_down_shelf(state, data, b, i, t1)
			_add_to(report, {"store_sales": int(taken.earned), "sold:%s" % shelf.res: int(shelf.qty)})
	b.job_started_at = t1
	return report


## Takes shelf `index` down at time `now`: what's sold is paid for (minus sales tax), the rest is
## handed back with its share of the cost tag. Returns {"earned" (cents), "back", "back_cost"}.
static func _take_down_shelf(state: Dictionary, data: Dictionary, b: Dictionary, index: int, now: float) -> Dictionary:
	var shelf: Dictionary = b.shelves[index]
	var qty := int(shelf.qty)
	var sold := qty - _unsold(shelf)
	var cost := float(shelf.get("cost", 0.0))
	var earned := 0
	if sold > 0:
		earned = int(_record_sale(state, data, shelf.res, sold, sold * int(shelf.price), cost * sold / qty, now).earned)
	var back := {}
	var back_cost := {}
	if qty > sold:
		back[shelf.res] = qty - sold
		back_cost[shelf.res] = cost * (qty - sold) / qty
	b.shelves[index] = {}
	return {"earned": earned, "back": back, "back_cost": back_cost}


## Demolish / suspend: every shelf is paid for what it sold so far and emptied (the unsold goods
## are already counted in _goods_inside, which hands them to the warehouse).
static func _take_down_all_shelves(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> void:
	var list: Array = b.get("shelves", [])
	for i in list.size():
		if not list[i].is_empty():
			_take_down_shelf(state, data, b, i, now)


## Units still unsold on a shelf (whole units: a part-sold unit isn't paid for yet).
static func _unsold(shelf: Dictionary) -> int:
	return int(shelf.qty) - mini(floori(float(shelf.sold) + 0.000001), int(shelf.qty))


## The first empty shelf, or -1 when every shelf is in use.
static func _free_shelf(data: Dictionary, b: Dictionary) -> int:
	var list := shelves(data, b)
	for i in list.size():
		if list[i].is_empty():
			return i
	return -1


## Share of its workers the store has (3 of 4 = 0.75), working or waiting: how fast it would sell.
static func _staffed_share(data: Dictionary, b: Dictionary) -> float:
	if _full_speed_workers(data, b) <= 0:
		return 1.0
	return float(hired(b)) / _full_speed_workers(data, b)


# --- Prices (plan.md §5.12) ------------------------------------------------------

## Retail price of one unit, in cents, worked out live from what it costs to make (plan.md
## §5.12): for the building that makes it, at full staff, one batch costs its ingredients (at
## their own prices) + wages (max_workers at the minimum wage) + water (at the base price) + a
## share of the build cost (so it pays for itself in pricing.payback_hours of production);
## divided by the units made, then by (1 - pricing.typical_tax_rate) so a typical company keeps
## that after sales tax. Rounded to the cent. A resource with a fixed "price" (dollars) in
## resources.json uses that instead.
static func unit_price(data: Dictionary, resource_id: String) -> int:
	return int(_cached(data, "price:" + resource_id, func(): return _unit_price(data, resource_id, {})))


## Prices and standard costs depend only on data/*.json. When `data` carries a "cache"
## dictionary (the game's does: its data never changes while playing), each one is worked out
## once and kept there; without one (tests change their data) it is worked out every time.
static func _cached(data: Dictionary, key: String, work: Callable) -> Variant:
	if not data.has("cache"):
		return work.call()
	var cache: Dictionary = data.cache
	if not cache.has(key):
		cache[key] = work.call()
	return cache[key]


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
			cost += float(def.get("power_mw", 0.0)) * hours * float(data.config.get("power", {}).get("price_per_mwh", 0.0))
			cost += construction_value(data, type_id) / 100.0 / payback * hours
			# By-products carry their cost_share of the batch (the same split as cost tags).
			price = cents(cost * float(output_shares(recipe)[resource_id]) / maxf(float(recipe.outputs[resource_id]), 1) / keep)
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
# They change cash directly (amounts in cents). That isn't income or spending (so the graphs
# stay clean), but it is counted in stats.adjustments, so the cash check still adds up.

static func dev_set_cash(state: Dictionary, amount: int) -> Dictionary:
	return dev_add_cash(state, amount - int(state.profile.currency))


static func dev_add_cash(state: Dictionary, amount: int) -> Dictionary:
	state.profile.currency += amount
	var s := stats(state)
	s["adjustments"] = int(s.get("adjustments", 0)) + amount
	return _ok()


## Sets the rent per household (dollars an hour) for a home type, overriding buildings.json; a
## negative `dollars` removes the override (back to the data file's rent). Kept in the save, so
## it lasts until reset. Households that can no longer afford their home move out at once.
static func dev_set_rent(state: Dictionary, data: Dictionary, type_id: String, dollars: float, now: float) -> Dictionary:
	if home_households(data, {"type": type_id}) <= 0 or bool(data.buildings[type_id].get("hut", false)):
		return _fail("That isn't a home with rent.")
	settle(state, data, now)  # rent so far is collected at the old price
	if not state.has("dev_rent"):
		state["dev_rent"] = {}
	if dollars < 0.0:
		state.dev_rent.erase(type_id)
	else:
		state.dev_rent[type_id] = dollars
	_update_huts(state, data, now)
	return _ok()


# Developer changes kept in the save until reset: state.dev = {"locks": {need: 0-1},
# "config": {path: value}}. Each tool settles first, so time so far counts with the old rules and
# the change only from now (time away still equals playing through).

## The happiness parts a developer can lock: the score itself, what people expect, and each need
## that counts (need_ids).
static func dev_lock_keys(data: Dictionary) -> Array:
	return ["score", "expected"] + need_ids(data)


## Developer locks on happiness: {key: 0-1} (dev_lock_keys). Read it; don't change it. A lock
## from an older game on something that no longer exists (the hut penalty) is left out.
static func dev_locks(state: Dictionary) -> Dictionary:
	var locks: Dictionary = state.get("dev", {}).get("locks", {})
	if not locks.has("penalty"):
		return locks
	var kept := locks.duplicate()
	kept.erase("penalty")
	return kept


## Developer changes to game_config.json numbers: {"happiness.weights.food": 2, ...}. Applied onto
## the config by the game (apply_config_overrides), never written to the file.
static func dev_config(state: Dictionary) -> Dictionary:
	return state.get("dev", {}).get("config", {})


## True while any developer change is on: a happiness lock, a tuning change or a rent change.
static func dev_active(state: Dictionary) -> bool:
	return not dev_locks(state).is_empty() or not dev_config(state).is_empty() or not state.get("dev_rent", {}).is_empty()


## state.dev[part] = what (an empty `what` removes it, and an empty state.dev too).
static func _set_dev(state: Dictionary, part: String, what: Dictionary) -> void:
	var dev: Dictionary = state.get("dev", {})
	if what.is_empty():
		dev.erase(part)
	else:
		dev[part] = what
	if dev.is_empty():
		state.erase("dev")
	else:
		state["dev"] = dev


## Locks a part of happiness (dev_lock_keys) at `value` (0-1); a negative value unlocks it. A
## locked need replaces what every class really has; a locked expectation replaces what people
## expect; a locked score replaces the whole score.
static func dev_lock_happiness(state: Dictionary, data: Dictionary, key: String, value: float, now: float) -> Dictionary:
	if not dev_lock_keys(data).has(key):
		return _fail("Nothing called %s to lock." % key)
	settle(state, data, now)
	var locks := dev_locks(state).duplicate()
	if value < 0.0:
		locks.erase(key)
	else:
		locks[key] = clampf(value, 0.0, 1.0)
	_set_dev(state, "locks", locks)
	return _ok()


## The value at `path` in the config ("happiness.growth_speeds.2.speed": dictionary keys and list
## places, separated by dots), or null when there's nothing there.
static func config_value(config: Dictionary, path: String) -> Variant:
	var node: Variant = config
	for part in path.split("."):
		if node is Dictionary and node.has(part):
			node = node[part]
		elif node is Array and part.is_valid_int() and int(part) >= 0 and int(part) < node.size():
			node = node[int(part)]
		else:
			return null
	return node


## Changes a game_config.json number (or true/false) from now on: `path` as in config_value. It
## must hold the same kind of value, or be missing from a block that exists (a happiness band
## without children_leave_per_hour gets one); null takes the change back. The game applies it onto
## its config (apply_config_overrides); `data` is the config as it stands before the change.
static func dev_set_config(state: Dictionary, data: Dictionary, path: String, value: Variant, now: float) -> Dictionary:
	var current: Variant = config_value(data.config, path)
	var parts := path.rsplit(".", true, 1)
	var parent: Variant = data.config if parts.size() == 1 else config_value(data.config, parts[0])
	if current == null and not parent is Dictionary:
		return _fail("No setting called %s." % path)
	if current != null and not (current is bool or current is int or current is float):
		return _fail("%s isn't a number." % path)
	if value != null and current != null and (value is bool) != (current is bool):
		return _fail("%s takes %s." % [path, "true or false" if current is bool else "a number"])
	if value != null and not (value is bool or value is int or value is float):
		return _fail("%s takes a number." % path)
	settle(state, data, now)  # time so far counts with the old numbers
	var changes := dev_config(state).duplicate()
	if value == null:
		changes.erase(path)
	else:
		changes[path] = value if (value is bool or value is int) else float(value)
	_set_dev(state, "config", changes)
	return _ok()


## Puts the config back to `original` (each top-level block copied afresh), then sets each change
## in `overrides` ({path: value}, see dev_set_config) in place (a key missing from a block that
## exists is added). Paths whose block no longer exists are skipped. The config dictionary itself
## stays the same object, so everything holding it sees the new numbers.
static func apply_config_overrides(config: Dictionary, original: Dictionary, overrides: Dictionary) -> void:
	for key in original:
		var block: Variant = original[key]
		config[key] = block.duplicate(true) if (block is Dictionary or block is Array) else block
	for path in overrides:
		var parts: PackedStringArray = String(path).rsplit(".", true, 1)
		var parent: Variant = config if parts.size() == 1 else config_value(config, parts[0])
		var last: String = parts[-1]
		if parent is Dictionary:
			parent[last] = overrides[path]
		elif parent is Array and last.is_valid_int() and int(last) >= 0 and int(last) < parent.size():
			parent[int(last)] = overrides[path]


## Adds `n` adults (a negative n takes them away, never below none). Workers are let go if need
## be, the jobless first (_hire). Not counted as moving in or away: it's a developer change.
static func dev_add_adults(state: Dictionary, data: Dictionary, n: int, now: float) -> Dictionary:
	settle(state, data, now)
	var change := maxi(n, -adults(state))
	if change == 0:
		return _fail("There are no adults to take away.")
	state.population.current = int(state.population.current) + change
	_hire(state, data, now)
	return _ok({"changed": change})


## Adds `n` children as a new age group, growing up after life.grow_up_hours.
static func dev_add_children(state: Dictionary, data: Dictionary, n: int, now: float) -> Dictionary:
	if n <= 0:
		return _fail("Add at least one child.")
	settle(state, data, now)
	var pop: Dictionary = state.population
	if not pop.has("children"):
		pop["children"] = []
	var hours := float(data.config.get("life", {}).get("grow_up_hours", 24.0))
	pop.children.append({"count": n, "grows_up_at": now + hours * 3600.0})  # the youngest: last
	pop.current = int(pop.current) + n
	_hire(state, data, now)
	return _ok()


## Every child grows up into an adult now (counted as growing up). Like growing up by itself,
## with life.grown_ups_leave_without_job the ones no job is waiting for leave the island.
## Returns {"grew_up", "left_for_work"}.
static func dev_children_grow_up(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	settle(state, data, now)
	var grown := children_count(state)
	if grown <= 0:
		return _fail("There are no children.")
	var waiting := _jobs_for_grown_ups(state, data, now, INF)
	var gone := maxi(grown - waiting, 0) if waiting >= 0 else 0
	state.population.children = []  # still counted in population.current: adults now
	state.population.current = int(state.population.current) - gone
	people_stats(state).grew_up = int(people_stats(state).grew_up) + grown
	people_stats(state).moved_away = int(people_stats(state).moved_away) + gone
	_hire(state, data, now)
	return _ok({"grew_up": grown, "left_for_work": gone})


## Every building going up and every upgrade under way is finished now. Their construction
## workers are free again.
static func dev_finish_construction(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	settle(state, data, now)
	var finished := 0
	for b in state.buildings:
		var done := false
		if b.has("upgrade_done_at") and float(b.upgrade_done_at) > now:
			b.upgrade_done_at = now
			done = true
		if built_at(b) > now:
			b.built_at = now
			b.job_started_at = minf(float(b.job_started_at), now)
			done = true
		if done:
			finished += 1
	if finished == 0:
		return _fail("Nothing is being built or upgraded.")
	_hire(state, data, now)  # upgrades reach their level; new posts and homes count from now
	return _ok({"finished": finished})


## Puts `qty` of `resource_id` in the warehouse, as much as fits. Returns {"added"}.
static func dev_add_item(state: Dictionary, data: Dictionary, resource_id: String, qty: int, now: float) -> Dictionary:
	if not data.resources.has(resource_id) or qty <= 0:
		return _fail("Pick an item and an amount.")
	settle(state, data, now)
	var added := mini(qty, maxi(warehouse_cap(state, data) - warehouse_total(state), 0))
	if added <= 0:
		return _fail("The warehouse is full.")
	state.inventory[resource_id] = int(state.inventory.get(resource_id, 0)) + added
	return _ok({"added": added})


## Takes back every developer change: happiness locks, tuning and rent.
static func dev_reset_all(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	settle(state, data, now)
	state.erase("dev")
	state.erase("dev_rent")
	_update_huts(state, data, now)
	return _ok()


# --- Questions the UI can ask -------------------------------------------------

static func find_building(state: Dictionary, building_id: String) -> Dictionary:
	for b in state.buildings:
		if b.id == building_id:
			return b
	return {}


## The building standing on this tile (any tile of its footprint), or {}.
static func building_at(state: Dictionary, data: Dictionary, cell: Vector2i) -> Dictionary:
	for b in state.buildings:
		var at := _cell_of(b)
		var size := size_of(data, b.type)
		if cell.x >= at.x and cell.y >= at.y and cell.x < at.x + size and cell.y < at.y + size:
			return b
	return {}


## Room for people (adults and children) in finished real homes: households x (2 + 2). Homes
## still under construction don't count yet, and neither do Makeshift Huts. With homeless
## households in huts, the village can hold more people than this.
static func population_capacity(state: Dictionary, data: Dictionary, now: float) -> int:
	return _real_households(state, data, now, true) * (adults_per_household(data) + children_per_household(data))


## How many people live in this home (adults and children; see housing()). 0 while it's being built.
static func home_residents(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> int:
	var home: Dictionary = housing(state, data, now).homes.get(b.id, {})
	return int(home.get("adults", 0)) + int(home.get("children", 0))


## When the next group moves in (see next_arrival_count): INF when there's no room for another adult (see _arrival_room),
## no open job for a migrant worker (see _job_cap), or nobody is moving in (immigration off, or too
## unhappy). Uses the move-in speed happiness gives right now (a new speed restarts the wait, see
## _update_growth_speed). `happy` (happiness) and `e` (employment) at `now` can be handed in.
static func next_arrival_at(state: Dictionary, data: Dictionary, now: float, happy := {}, e := {}) -> float:
	var pop: Dictionary = state.population
	if adults(state) >= mini(_arrival_room(state, data, now, true), _job_cap(state, data, now, e)):
		return INF
	var base := float(data.config.population_growth_seconds)
	if happy.is_empty():
		happy = happiness(state, data, now, {}, e)
	var speed := float(happy.move_in_speed)
	if base <= 0.0 or speed <= 0.0:
		return INF
	var step := base / speed
	var anchor := float(pop.growth_anchor)
	if not is_equal_approx(speed, _move_in_speed(pop)):
		anchor = maxf(anchor, float(state.get("settled_at", now)))
	return anchor + step * (floorf(maxf(now - anchor, 0.0) / step + 0.000001) + 1.0)


## How many adults the next group brings: up to move_in_group_size, fewer when fewer jobs are
## open (or less room). 0 when nobody is coming (see next_arrival_at, also for `happy` and `e`).
static func next_arrival_count(state: Dictionary, data: Dictionary, now: float, happy := {}, e := {}) -> int:
	if is_inf(next_arrival_at(state, data, now, happy, e)):
		return 0
	var room := mini(_arrival_room(state, data, now, true), _job_cap(state, data, now, e)) - adults(state)
	return clampi(room, 0, _move_in_group(data))


## When the building is (or was) finished. Saves from before construction time existed have no
## "built_at", so those buildings count as finished long ago.
static func built_at(b: Dictionary) -> float:
	return float(b.get("built_at", 0.0))


static func is_built(b: Dictionary, now: float) -> bool:
	return now >= built_at(b)


## Why a building that isn't finished can't do something yet.
static func _unfinished(b: Dictionary, now: float) -> String:
	return "It's being upgraded." if is_upgrading(b, now) else "Still under construction."


## 0.0 to 1.0 progress of construction or of an upgrade (1.0 = finished), for progress bars.
static func construction_progress(b: Dictionary, data: Dictionary, now: float) -> float:
	if is_upgrading(b, now):
		var started := float(b.get("upgrade_started_at", now))
		return clampf((now - started) / maxf(float(b.upgrade_done_at) - started, 0.001), 0.0, 1.0)
	var build_time := construction_seconds(data, b.type, 1)
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
	var full := int(level_stat(data, b, "capacity", 0))
	if max_workers(data, b) <= 0:
		return full
	return floori(full * workers_working(state, data, b, now) / float(max_workers(data, b)) + 0.000001)


static func warehouse_total(state: Dictionary) -> int:
	return _total(state.inventory)


## 0.0 to 1.0 progress of the whole batch, for progress bars (1.0 once every hour is made). Time
## since the last settle counts at the building's current speed, so a short-staffed building's
## bar moves slower.
static func job_progress(state: Dictionary, b: Dictionary, data: Dictionary, now: float) -> float:
	if not has_batch(b):
		return 0.0
	if not batch_running(b):
		return 1.0
	var recipe := _recipe(data.buildings.get(b.type, {}), b.batch.recipe_id)
	if recipe.is_empty():
		return 0.0
	var started := float(b.job_started_at)
	var settled := float(state.get("settled_at", now))
	var worked := now - started
	if now > settled and started <= settled:
		worked = (settled - started) + (now - settled) * building_speed(state, data, b, now)
	var made := float(b.batch.get("made_hours", 0)) / int(b.batch.hours)  # never shown going back
	return clampf(maxf(worked / (float(recipe.duration) * int(b.batch.hours)), made), 0.0, 1.0)


## When the running batch should be done at today's speed (unix time); INF while nobody works
## there; 0 without a running batch.
static func batch_finishes_at(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	if not batch_running(b):
		return 0.0
	var recipe := _recipe(data.buildings.get(b.type, {}), b.batch.recipe_id)
	var total := float(recipe.get("duration", 0.0)) * int(b.batch.hours)
	var left := total * (1.0 - job_progress(state, b, data, now))
	var speed := building_speed(state, data, b, now)
	if left <= 0.0:
		return now
	return now + left / speed if speed > 0.0 else INF


## How fast a building works: workers actually working ÷ Level 1's max_workers (6 of 8 = 0.75;
## an upgraded farm with 12 working = 1.5). Buildings without workers (homes, the office) always
## work at full speed.
static func building_speed(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	var most := _full_speed_workers(data, b)
	if most <= 0:
		return 1.0
	return workers_working(state, data, b, now) / float(most)


## The most workers this building can employ at its level.
static func max_workers(data: Dictionary, b: Dictionary) -> int:
	return int(level_stat(data, b, "max_workers", 0))


## The crew that works at full speed (1.0): Level 1's max_workers. An upgraded building with more
## workers works faster than that (12 of 8 = 1.5), so a bigger building makes more, while each
## batch still costs the same in wages.
static func _full_speed_workers(data: Dictionary, b: Dictionary) -> int:
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
## it's producing; 0 while it's still being built, isn't producing (halted, idle, suspended) or
## has no power (plan.md §5.5). They keep their workers (tied, unpaid) until they restart.
static func workers_working(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	if not is_built(b, now) or not is_producing(data, b) or power_problem(b) != "":
		return 0.0
	return float(hired(b))


## Workers tied to this building (hired, whether working right now or waiting unpaid).
static func hired(b: Dictionary) -> int:
	return int(b.get("hired", 0))


## Posts the building offers: what its staffing level asks for, once built and while not
## suspended. Halted or idle buildings keep offering them.
static func posts(data: Dictionary, b: Dictionary, now: float) -> int:
	if not is_built(b, now) or is_suspended(b) or not on_road(data, b):
		return 0
	return workers_wanted(data, b)


## Hands out free people (plan.md §5.6 "Hiring"). Workers are tied to their building, so only
## free people move: warehouses ("staffed_first") are filled before anything else; then they take
## turns, the emptiest building first (fewest hired for what it asked for), then the older one.
## (The wage bonus doesn't decide hiring: it makes more units per batch.) With more workers than
## people (a home was demolished) workers leave the newest building first, and warehouses last.
## Afterwards the Makeshift Huts are brought up to date, because who works where decides each
## household's wealth, and so where it can live; and then who gets power (plan.md §5.5).
## Returns what it worked out on the way, as things now stand, for settle to reuse: {"housing"
## (or {} when it changed afterwards), "power" (power_summary; {} without electricity)}.
static func _hire(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	_finish_upgrades(state, now)  # a finished upgrade's new posts and room count first
	_hire_workers(state, data, now)
	var homes := _update_huts(state, data, now)
	var power := _update_power(state, data, now, homes)  # who works and who lives where decide who needs power
	return {"housing": homes, "power": power}


static func _hire_workers(state: Dictionary, data: Dictionary, now: float) -> void:
	_update_road_links(state, data)  # a building with no road offers no posts
	var buildings: Array = state.buildings
	# Posts and who is staffed first don't change while people are handed out, so each
	# building's are worked out once (asking again for every worker is slow in a big village).
	var open: Array[int] = []
	var first: Array[bool] = []
	var free := adults(state)  # children don't work
	for b in buildings:
		open.append(posts(data, b, now))
		first.append(is_staffed_first(data, b))
		b["hired"] = mini(hired(b), open[-1])  # e.g. staffing was lowered: the rest are freed
		free -= hired(b)
	while free < 0:
		var leave := -1
		for i in buildings.size():
			if hired(buildings[i]) > 0 and (leave < 0 or _leaves_before(first[i], first[leave])):
				leave = i
		buildings[leave]["hired"] = hired(buildings[leave]) - 1
		free += 1
	while free > 0:
		var best := -1
		for i in buildings.size():
			var b: Dictionary = buildings[i]
			if hired(b) < open[i] and (best < 0 or _hires_before(first[i], hired(b), open[i], first[best], hired(buildings[best]), open[best])):
				best = i
		if best < 0:
			return  # every post is filled: the rest stay unemployed
		buildings[best]["hired"] = hired(buildings[best]) + 1
		free -= 1


## Whether building a gets the next free worker before b (both have an open post), given each
## one's staffed_first (is_staffed_first), hired and posts: buildings that are "staffed_first"
## (warehouses) before all others, then the emptier one (compared without decimals: a.hired /
## a.posts < b.hired / b.posts). Equal on both: the one found first, i.e. the older building.
static func _hires_before(a_first: bool, a_hired: int, a_posts: int, b_first: bool, b_hired: int, b_posts: int) -> bool:
	if a_first != b_first:
		return a_first
	return a_hired * b_posts < b_hired * a_posts


## With fewer people than workers: whether a worker at a leaves before one at b (b was found
## earlier, so it's the older one), given each one's staffed_first. "staffed_first" buildings lose
## workers last; otherwise the newer building (a) goes first.
static func _leaves_before(a_first: bool, b_first: bool) -> bool:
	if a_first != b_first:
		return not a_first
	return true


## Gets free workers before every other building and loses them last (warehouses: their room
## must not vanish when people are short). "staffed_first" in buildings.json.
static func is_staffed_first(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("staffed_first", false))


## Producing: has work to do and isn't suspended. Workers only work, and water and from Phase 2/3
## power are only used, while a building is producing (plan.md §5.5, §5.6). Warehouses count as
## always producing (storing) unless suspended: their workers make the room.
static func is_producing(data: Dictionary, b: Dictionary) -> bool:
	return not is_suspended(b) and not is_idle(data, b)


## Suspended by the player: switched off, no workers, no wages, no power (plan.md §5.10).
static func is_suspended(b: Dictionary) -> bool:
	return bool(b.get("suspended", false))


## Idle: a Farm, Mill or Bakery with no batch being made (none started, or every hour made), or
## a Supermarket with empty shelves. Its workers stay tied to it, waiting for the next batch.
static func is_idle(data: Dictionary, b: Dictionary) -> bool:
	if makes_batches(data, b):
		return not batch_running(b)
	if data.buildings.get(b.type, {}).get("category", "") == "retail":
		return products_on_shelves(b) == 0
	return false


## When a producing building will stop if nothing changes, at its current speed: its batch's last
## hour is done (idle); for a Supermarket, the next shelf to sell out (its shoppers bonus changes
## then, and it may go idle). INF if it won't. Settling splits time at this moment so water and
## workers stop exactly then, even while the player is away.
static func _stop_time(state: Dictionary, data: Dictionary, b: Dictionary, t: float) -> float:
	var def: Dictionary = data.buildings.get(b.type, {})
	if max_workers(data, b) <= 0 or not is_built(b, t) or not is_producing(data, b) or float(b.job_started_at) > t:
		return INF
	if def.get("category", "") not in ["extractor", "processor", "retail"]:
		return INF  # a warehouse never stops by itself
	var speed := building_speed(state, data, b, t)
	if speed <= 0.0:
		return INF
	if def.get("category", "") == "retail":
		return _next_sell_out(state, data, b, t, speed)
	var recipe := _recipe(def, b.batch.recipe_id)
	var work := float(recipe.get("duration", 0.0)) * int(b.batch.hours) - (t - float(b.job_started_at))
	return t + maxf(work, 0.0) / speed + 0.000001  # the last hour is done: idle from then on


## Wage per hour (dollars) for one worker here: the minimum wage for its worker type (game_config.json
## worker_types, set by the game) plus the building's bonus (None 0% / Small 20% / ...).
static func wage_per_worker(data: Dictionary, b: Dictionary) -> float:
	return minimum_wage(data, b) * (1.0 + bonus_rate(data, b))


## What one worker here earns per hour right now (dollars), which decides their wealth class:
## the minimum wage plus the bonus they are paid now (bonus_earned_now).
static func wage_earned_now(data: Dictionary, b: Dictionary) -> float:
	return minimum_wage(data, b) * (1.0 + float(data.config.get("wage_bonuses", {}).get(bonus_earned_now(data, b), 0.0)))


## The wage bonus the workers here are paid right now: bonus_level, except at a Farm, Mill or
## Bakery with no batch being made: "none", because nobody is paid a bonus while it's idle. The
## bonus chosen for the next batch only counts once that batch starts.
static func bonus_earned_now(data: Dictionary, b: Dictionary) -> String:
	if makes_batches(data, b) and not batch_running(b):
		return "none"
	return bonus_level(data, b)


## The minimum wage per hour (dollars) for this building's worker type, before any bonus.
static func minimum_wage(data: Dictionary, b: Dictionary) -> float:
	return _minimum_wage_of(data, data.buildings.get(b.type, {}))


## The building's wage bonus: "none", "small", "good" or "big" (wage_bonuses in config). While it
## has a batch, the one locked into that batch; otherwise the one chosen for the next batch.
## Always "none" for "fixed_wage" buildings (warehouses), whatever an older save says.
static func bonus_level(data: Dictionary, b: Dictionary) -> String:
	if has_fixed_wage(data, b):
		return "none"
	if has_batch(b):
		return str(b.batch.get("bonus", "none"))
	return str(b.get("bonus", data.config.get("default_bonus", "none")))


## Its bonus as a share of the minimum wage (0.4 = +40%).
static func bonus_rate(data: Dictionary, b: Dictionary) -> float:
	return float(data.config.get("wage_bonuses", {}).get(bonus_level(data, b), 0.0))


## True when the building always pays the minimum wage: no bonus choice ("fixed_wage" in
## buildings.json; warehouses, which are staffed first anyway).
static func has_fixed_wage(data: Dictionary, b: Dictionary) -> bool:
	return bool(data.buildings.get(b.type, {}).get("fixed_wage", false))


## What the building's workers cost per hour right now (dollars). 0 for a Farm, Mill or Bakery:
## a batch pays all its wages when it starts (start_batch). 0 for a Construction Office too: its
## workers are paid per project (the labor in construction_quote).
static func building_wages(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	if makes_batches(data, b) or is_crew_office(data, b):
		return 0.0
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


# Own water (plan.md §5.13.1): a Water Treatment Plant cleans "water_supply" m³ an hour (at its
# level) with all its workers working; fewer workers clean less (2 of 4 = half). Your buildings use
# that water first and only the rest is drawn from the public supply (and metered on the bill).
# Water nobody uses is simply not used. The plant's water costs only its workers' wages, which
# are paid by the hour like a warehouse's (always working unless suspended).

## m³ of water per hour this building cleans right now (0 for anything but a working plant).
static func water_supply(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	var full := float(level_stat(data, b, "water_supply", 0.0))
	if full <= 0.0 or not is_built(b, now) or not is_producing(data, b):
		return 0.0
	var most := max_workers(data, b)
	if most <= 0:
		return full
	return full * workers_working(state, data, b, now) / most


## All the water the company's own plants clean right now, m³ per hour.
static func own_water_total(state: Dictionary, data: Dictionary, now: float) -> float:
	var total := 0.0
	for b in state.buildings:
		total += water_supply(state, data, b, now)
	return total


## What the public supply has to cover right now (m³ per hour): use beyond the own plants' water.
static func public_water_use(state: Dictionary, data: Dictionary, now: float) -> float:
	return maxf(water_use_total(state, data, now) - own_water_total(state, data, now), 0.0)


## What a m³ of own water costs (dollars): the plants' wages per hour ÷ the m³ they clean, both at
## full staff (fewer workers clean less for less, so the price stays the same). 0 with no plant.
static func own_water_price(state: Dictionary, data: Dictionary, now: float) -> float:
	var wages := 0.0
	var m3 := 0.0
	for b in state.buildings:
		var supply := water_supply(state, data, b, now)
		if supply > 0.0:
			var full := float(level_stat(data, b, "water_supply", 0.0))
			wages += max_workers(data, b) * wage_per_worker(data, b) * supply / full
			m3 += supply
	return wages / m3 if m3 > 0.0 else 0.0


## The water picture right now: {"own" (m³/h the plants clean), "used" (m³/h the buildings draw),
## "from_own" (m³/h of it the plants cover), "public" (m³/h from the public supply), "spare"
## (m³/h cleaned that nobody uses), "own_price" (dollars per own m³)}.
static func water_summary(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var own := own_water_total(state, data, now)
	var used := water_use_total(state, data, now)
	return {"own": own, "used": used, "from_own": minf(own, used), "public": maxf(used - own, 0.0),
		"spare": maxf(own - used, 0.0), "own_price": own_water_price(state, data, now)}


## What `m3_per_hour` MORE water would cost per m³ right now (dollars): the plants' spare water
## first at the own price, the rest at the public price of the next m³ (with its tier).
static func extra_water_price(state: Dictionary, data: Dictionary, m3_per_hour: float, now: float) -> float:
	if m3_per_hour <= 0.0:
		return 0.0
	var summary := water_summary(state, data, now)
	var from_own := minf(m3_per_hour, float(summary.spare))
	return (from_own * float(summary.own_price) + (m3_per_hour - from_own) * water_unit_price(state, data)) / m3_per_hour


## What the water this building draws costs per hour right now (dollars): its share of the own
## water (the plants cover every building alike) at the own price, the rest at the public price.
static func water_cost_per_hour(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	var m3 := water_use(state, data, b, now)
	if m3 <= 0.0:
		return 0.0
	var summary := water_summary(state, data, now)
	var own_share := float(summary.from_own) / float(summary.used)
	return m3 * (own_share * float(summary.own_price) + (1.0 - own_share) * water_unit_price(state, data))


## The water meter: {"m3" (drawn this cycle), "base_cost" (dollars, each m³ at the price when it
## was drawn), "cycle_start" (when this billing cycle began)}. Older saves get one starting `now`.
static func water_meter(state: Dictionary, now: float) -> Dictionary:
	return utility_meter(state, "water", now)


## Seconds in one water billing cycle (water.billing_hours, 12 = one game day).
static func billing_seconds(data: Dictionary) -> float:
	return _billing_seconds(data, "water")


## When the current water bill falls due (a fixed moment: cycle start + one cycle).
static func water_bill_due_at(state: Dictionary, data: Dictionary, now: float) -> float:
	return bill_due_at(state, data, "water", now)


## The base price per m³ (dollars) right now. Later it can drift (market mood).
static func water_price(data: Dictionary) -> float:
	return utility_price(data, "water")


## A cycle's water bill (dollars) for `m3` that cost `base_cost` at the base price (see bill_cost).
static func water_bill_cost(data: Dictionary, m3: float, base_cost: float) -> float:
	return bill_cost(data, "water", m3, base_cost)


## The water bill so far this cycle: {"m3", "cost" (cents), "due_at"}. Changes nothing.
static func water_bill_so_far(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	return bill_so_far(state, data, "water", now)


# Utility bills, water and power alike: a meter records what the company draws (and what it cost
# at the price of the moment); every <kind>.billing_hours (12) the bill is charged at once, heavy
# users paying more for the part of the cycle's amount above each tier. Unpaid bills simply take
# cash below 0 (debt). The settings are in game_config.json under "water" and "power".

## What each utility is measured in: m³ of water, MWh of power.
const UTILITY_UNITS := {"water": "m3", "power": "mwh"}


## The meter of `kind` ("water" or "power"): {<unit> (drawn this cycle), "base_cost" (dollars),
## "cycle_start"}. A save without one gets one starting `now`.
static func utility_meter(state: Dictionary, kind: String, now: float) -> Dictionary:
	var key := kind + "_meter"
	if not state.has(key):
		state[key] = {UTILITY_UNITS[kind]: 0.0, "base_cost": 0.0, "cycle_start": now}
	return state[key]


static func _billing_seconds(data: Dictionary, kind: String) -> float:
	return maxf(float(data.config.get(kind, {}).get("billing_hours", 12.0)), 0.02) * 3600.0


## When the current bill of `kind` falls due (a fixed moment: cycle start + one cycle).
static func bill_due_at(state: Dictionary, data: Dictionary, kind: String, now: float) -> float:
	return float(utility_meter(state, kind, now).cycle_start) + _billing_seconds(data, kind)


## The base price (dollars) of one unit of `kind`: water.price_per_m3, power.price_per_mwh.
static func utility_price(data: Dictionary, kind: String) -> float:
	return float(data.config.get(kind, {}).get("price_per_" + UTILITY_UNITS[kind], 0.0))


## Records `amount` drawn, at the price of the moment.
static func _meter_use(state: Dictionary, data: Dictionary, kind: String, amount: float, now: float) -> void:
	if amount <= 0.0:
		return
	var meter := utility_meter(state, kind, now)
	var unit: String = UTILITY_UNITS[kind]
	meter[unit] = float(meter[unit]) + amount
	meter.base_cost = float(meter.base_cost) + amount * utility_price(data, kind)


## A cycle's bill (dollars) for `amount` that cost `base_cost` at the base price: plus each
## tier's extra on the part above where that tier starts (water: first 1,200 m³ normal, above +25%).
static func bill_cost(data: Dictionary, kind: String, amount: float, base_cost: float) -> float:
	if amount <= 0.0:
		return 0.0
	var average_price := base_cost / amount
	var cost := 0.0
	var tiers: Array = data.config.get(kind, {}).get("tiers", [{"from": 0, "extra": 0.0}])
	for i in tiers.size():
		var low := float(tiers[i].from)
		var high: float = float(tiers[i + 1].from) if i + 1 < tiers.size() else INF
		cost += maxf(minf(amount, high) - low, 0.0) * average_price * (1.0 + float(tiers[i].extra))
	return cost


## The bill of `kind` so far this cycle: {<unit> ("m3" or "mwh"), "cost" (cents), "due_at"}.
## Changes nothing.
static func bill_so_far(state: Dictionary, data: Dictionary, kind: String, now: float) -> Dictionary:
	var meter := utility_meter(state, kind, now)
	var unit: String = UTILITY_UNITS[kind]
	return {unit: float(meter[unit]), "cost": cents(bill_cost(data, kind, float(meter[unit]), float(meter.base_cost))),
		"due_at": bill_due_at(state, data, kind, now)}


## If the bill of `kind` is due at `now`, charges it all at once (into debt if need be), keeps it
## in the bill history (<kind>_bills) and starts the next cycle at the fixed moment it was due.
## Returns cents charged.
static func _bill_if_due(state: Dictionary, data: Dictionary, kind: String, now: float) -> int:
	var charged := 0
	var unit: String = UTILITY_UNITS[kind]
	while now >= bill_due_at(state, data, kind, now) - 0.000001:
		var meter := utility_meter(state, kind, now)
		var due := bill_due_at(state, data, kind, now)
		var amount := cents(bill_cost(data, kind, float(meter[unit]), float(meter.base_cost)))
		if amount > 0:
			state.profile.currency -= amount
			var spending: Dictionary = stats(state).spending
			spending[kind] = int(spending.get(kind, 0)) + amount
			var bills: Array = state.get(kind + "_bills", [])
			bills.append({"t": due, unit: float(meter[unit]), "cost": amount})
			while bills.size() > int(data.config.get(kind, {}).get("bill_history", 10)):
				bills.pop_front()
			state[kind + "_bills"] = bills
			charged += amount
		state[kind + "_meter"] = {unit: 0.0, "base_cost": 0.0, "cycle_start": due}
	return charged


## The price (dollars) of the next unit of `kind` from the public supply: the base price plus the
## extra of the tier this cycle has reached.
static func utility_unit_price(state: Dictionary, data: Dictionary, kind: String) -> float:
	var used := float(state.get(kind + "_meter", {}).get(UTILITY_UNITS[kind], 0.0))
	var extra := 0.0
	for tier in data.config.get(kind, {}).get("tiers", []):
		if used >= float(tier.from):
			extra = float(tier.extra)
	return utility_price(data, kind) * (1.0 + extra)


# --- Electricity (plan.md §5.5) ---------------------------------------------------
# Power is a flow in MW, Tropico-style. Your own power plants (power_supply) and any public grid
# link (grid_mw; since 2026-10-06 no building has one, City Hall included) feed one network. Each
# of them covers a circle of power_radius tiles around itself; circles that overlap join, starting
# from every plant, so Electric Substations carry power further. A building that uses power (power_mw) gets it only inside the network, and
# only while there's enough left: buildings are served oldest first, and one that doesn't fit
# gets none and stops (a home without power: nothing happens yet). Your own plants' power is
# used first; what the public grid adds is metered and billed like water. Who gets power is
# worked out again whenever workers are (_hire), which settling does at every moment that can
# change it, so time away stays one calculation.

## Whether this game has electricity at all (game_config.json has a "power" block).
static func power_on(data: Dictionary) -> bool:
	return not data.config.get("power", {}).is_empty()


## MW this building needs while it runs (power_mw at its level; 0 = it needs none).
static func power_need(data: Dictionary, b: Dictionary) -> float:
	if not power_on(data):
		return 0.0
	return float(level_stat(data, b, "power_mw", 0.0))


## How many tiles around it its power reaches (0 = it carries no power).
static func power_radius(data: Dictionary, b: Dictionary) -> float:
	return float(level_stat(data, b, "power_radius", 0.0))


## MW a public grid link can draw (grid_mw; 0 for every building since City Hall lost its link).
static func grid_link_mw(data: Dictionary, b: Dictionary) -> float:
	return float(level_stat(data, b, "grid_mw", 0.0))


## MW this power plant makes right now: its power_supply at its level once built and while not
## suspended; a plant with workers makes its share (2 of 4 workers = half).
static func power_supply(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	var full := float(level_stat(data, b, "power_supply", 0.0))
	if full <= 0.0 or not is_built(b, now) or not is_producing(data, b):
		return 0.0
	var most := max_workers(data, b)
	if most <= 0:
		return full
	return full * workers_working(state, data, b, now) / most


## Carries power: City Hall, a plant or a substation that is built and not suspended.
static func _carries_power(data: Dictionary, b: Dictionary, now: float) -> bool:
	return power_radius(data, b) > 0.0 and is_built(b, now) and not is_suspended(b)


## The power network as it stands: {"ids" {building id: true} (every plant, any grid link and
## every substation joined to them), "areas" [[cell, radius]] (their circles)}. It starts at the
## plants (and grid link) and takes in, again and again, everything whose circle overlaps one
## already in.
static func power_network(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var ids := {}
	var areas := []
	var waiting := []
	for b in state.buildings:
		if not _carries_power(data, b, now):
			continue
		if grid_link_mw(data, b) > 0.0 or is_power_source(data, b.type):
			ids[b.id] = true
			areas.append([centre_of(data, b), power_radius(data, b)])
		else:
			waiting.append(b)
	var grew := true
	while grew:
		grew = false
		for b in waiting.duplicate():
			if _in_reach(areas, centre_of(data, b), power_radius(data, b)):
				ids[b.id] = true
				areas.append([centre_of(data, b), power_radius(data, b)])
				waiting.erase(b)
				grew = true
	return {"ids": ids, "areas": areas}


## Whether a circle of `radius` around `point` (in tiles) overlaps (or, with radius 0, the point is
## inside) any of `areas` ([[centre, radius]]).
static func _in_reach(areas: Array, point: Vector2, radius: float) -> bool:
	for area in areas:
		var reach := float(area[1]) + radius
		if (point - (area[0] as Vector2)).length_squared() <= reach * reach + 0.000001:
			return true
	return false


## Whether this kind of building is where power starts: a plant (power_supply) or a grid link
## (grid_mw). Its circle is part of the network wherever it stands.
static func is_power_source(data: Dictionary, type_id: String) -> bool:
	var def: Dictionary = data.buildings.get(type_id, {})
	return float(def.get("power_supply", 0.0)) > 0.0 or float(def.get("grid_mw", 0.0)) > 0.0


## Whether the centre of `cell` is inside the network's reach (power_network).
static func is_powered_cell(network: Dictionary, cell: Vector2i) -> bool:
	return _in_reach(network.areas, Vector2(cell), 0.0)


## Whether a point (in tiles, e.g. a building's centre_at) is inside the network's reach.
static func is_powered_point(network: Dictionary, point: Vector2) -> bool:
	return _in_reach(network.areas, point, 0.0)


## Whether a plant or substation reaching `radius` tiles, with its centre at `point` (centre_at),
## would join the network (its circle overlaps the network's).
static func would_join_network(network: Dictionary, point: Vector2, radius: float) -> bool:
	return _in_reach(network.areas, point, radius)


## Whether the building asks for power right now: a home anyone lives in (`homes` = housing().homes);
## anything else while it's built, producing and has workers.
static func _wants_power(data: Dictionary, b: Dictionary, now: float, homes: Dictionary) -> bool:
	if not is_built(b, now):
		return false
	if home_households(data, b) > 0:
		return int(homes.get(b.id, {}).get("households", 0)) > 0
	return is_producing(data, b) and (max_workers(data, b) <= 0 or hired(b) > 0)


## The power picture right now (changes nothing; _update_power stores the "status"):
## {"status" {building id: "on" | "short" (not enough left for it) | "no_grid" (outside the
## network) | "" (needs none right now)} for every building that uses power, "own" (MW your
## joined plants make), "grid" (MW the grid link can add), "used" (MW the buildings get),
## "wanted" (MW the running buildings inside the network ask for), "from_own", "public" (MW
## drawn from the public grid), "spare" (own MW nobody uses), "left" (MW still free),
## "own_price" (dollars per own MWh)}. `housed` = housing at `now` if already worked out.
static func power_summary(state: Dictionary, data: Dictionary, now: float, housed := {}) -> Dictionary:
	var out := {"status": {}, "own": 0.0, "grid": 0.0, "used": 0.0, "wanted": 0.0, "from_own": 0.0,
		"public": 0.0, "spare": 0.0, "left": 0.0, "own_price": 0.0}
	if not power_on(data):
		return out
	var network := power_network(state, data, now)
	var plant_wages := 0.0
	for b in state.buildings:
		if network.ids.has(b.id):
			var made := power_supply(state, data, b, now)
			out.own = float(out.own) + made
			out.grid = float(out.grid) + grid_link_mw(data, b)
			if made > 0.0:
				plant_wages += building_wages(state, data, b, now)
	var left := float(out.own) + float(out.grid)
	var homes := {}
	for b in state.buildings:
		if home_households(data, b) > 0 and power_need(data, b) > 0.0:
			# Only worked out when a home uses power.
			homes = (housed if not housed.is_empty() else housing(state, data, now)).homes
			break
	for b in state.buildings:  # oldest first
		var need := power_need(data, b)
		if need <= 0.0:
			continue
		if not _in_reach(network.areas, centre_of(data, b), 0.0):
			out.status[b.id] = "no_grid"
		elif not _wants_power(data, b, now, homes):
			out.status[b.id] = ""
		else:
			out.wanted = float(out.wanted) + need
			if need <= left + 0.000001:
				out.status[b.id] = "on"
				left -= need
				out.used = float(out.used) + need
			else:
				out.status[b.id] = "short"
	out.from_own = minf(float(out.own), float(out.used))
	out.public = maxf(float(out.used) - float(out.own), 0.0)
	out.spare = maxf(float(out.own) - float(out.used), 0.0)
	out.left = maxf(left, 0.0)
	out.own_price = plant_wages / float(out.own) if float(out.own) > 0.0 else 0.0
	return out


## Stores who has power ("power" on each building that uses it; see power_summary). Run at the
## end of _hire, so the speeds settling reads always know. Returns the power_summary it used
## (writing the status changes none of its numbers); {} without electricity. `housed` = housing
## at `now` if already worked out.
static func _update_power(state: Dictionary, data: Dictionary, now: float, housed := {}) -> Dictionary:
	if not power_on(data):
		return {}
	var summary := power_summary(state, data, now, housed)
	var status: Dictionary = summary.status
	for b in state.buildings:
		if status.has(b.id):
			b["power"] = status[b.id]
		else:
			b.erase("power")
	return summary


## Why the building has no power: "short" (not enough left), "no_grid" (outside the network), or
## "" when it has power or needs none.
static func power_problem(b: Dictionary) -> String:
	var status := str(b.get("power", ""))
	return status if status in ["short", "no_grid"] else ""


## MW drawn from the public grid right now (billed).
static func public_power_draw(state: Dictionary, data: Dictionary, now: float) -> float:
	if not power_on(data):
		return 0.0
	return float(power_summary(state, data, now).public)


## What `mw` MORE power would cost per MWh right now (dollars): your plants' spare power first at
## its own price, the rest at the public grid's price of the next MWh.
static func extra_power_price(state: Dictionary, data: Dictionary, mw: float, now: float) -> float:
	if mw <= 0.0 or not power_on(data):
		return 0.0
	var summary := power_summary(state, data, now)
	var from_own := minf(mw, float(summary.spare))
	return (from_own * float(summary.own_price) + (mw - from_own) * utility_unit_price(state, data, "power")) / mw


## What this building's power costs per hour right now (dollars): its share of your plants' power
## (they cover every building alike) at the own price, the rest at the public price.
static func power_cost_per_hour(state: Dictionary, data: Dictionary, b: Dictionary, now: float) -> float:
	if str(b.get("power", "")) != "on":
		return 0.0
	var mw := power_need(data, b)
	var summary := power_summary(state, data, now)
	var own_share := float(summary.from_own) / float(summary.used) if float(summary.used) > 0.0 else 0.0
	return mw * (own_share * float(summary.own_price) + (1.0 - own_share) * utility_unit_price(state, data, "power"))


## The building type that carries power without making any (the Electric Substation): it has a
## power_radius, no power_supply and no grid link. "" if there's none.
static func substation_type(data: Dictionary) -> String:
	for type_id in data.buildings:
		var def: Dictionary = data.buildings[type_id]
		if float(def.get("power_radius", 0.0)) > 0.0 and float(def.get("power_supply", 0.0)) <= 0.0 and float(def.get("grid_mw", 0.0)) <= 0.0 and def.get("buildable", false):
			return type_id
	return ""


## Free Electric Substations until every building that uses power is inside the network, oldest
## building first (older saves, so their Mills and Bakeries keep working). For a building outside
## it, the substation goes on the free tile nearest that building whose circle joins the network,
## again until it's covered (or there's no tile left).
static func cover_all_with_power(state: Dictionary, data: Dictionary) -> void:
	var type_id := substation_type(data)
	if type_id == "" or not power_on(data):
		return
	var radius := float(data.buildings[type_id].power_radius)
	var now := float(state.get("settled_at", 0.0))
	var grid: Array = state.plot.grid_size
	for b in state.buildings.duplicate():
		if power_need(data, b) <= 0.0 or is_hut(data, b):
			continue
		for attempt in 10:
			var network := power_network(state, data, now)
			if network.ids.is_empty() or _in_reach(network.areas, centre_of(data, b), 0.0):
				break
			var best := Vector2i(-1, -1)
			var best_distance := INF
			var map := _plot_map(state, data)
			for y in int(grid[1]):
				for x in int(grid[0]):
					var cell := Vector2i(x, y)
					var at := centre_at(data, type_id, cell)
					var distance := (at - centre_of(data, b)).length_squared()
					if distance < best_distance and _footprint_problem(state, data, type_id, cell, "", map) == "" and _in_reach(network.areas, at, radius):
						best = cell
						best_distance = distance
			if best == Vector2i(-1, -1):
				break
			_add_free_building(state, data, type_id, best)


## A building that's already standing, free, counted at its value in the starting capital (for
## buildings an older save is given).
static func _add_free_building(state: Dictionary, data: Dictionary, type_id: String, cell: Vector2i) -> void:
	var b := _add_building(state, type_id, cell, 0.0, 0.0)
	b.paid = construction_value(data, type_id)
	record_base_materials(data, b, 1)
	var capital: Dictionary = stats(state).get("capital", {})
	capital["buildings"] = int(capital.get("buildings", 0)) + int(b.paid)


# --- Cost tags and cost per unit (plan.md §5.14) ----------------------------------
# Every stock carries its total cost in cents next to its amount: the warehouse in
# state.inventory_cost, a building's storage in b.storage_cost, a batch its whole cost
# (b.batch.cost: ingredients + wages + water, locked in when it starts; see batch_quote for the
# cost per unit shown before starting). Average cost = total cost ÷ amount, so mixing averages
# it. Moving goods moves their share of the cost with them. Missing tags count as 0 (older saves
# get standard tags when loaded, save_format.gd).

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


## The price of the next m³ (dollars): the base price, plus the extra of the tier this cycle's
## use has reached (+25% once past 1,200 m³).
static func water_unit_price(state: Dictionary, data: Dictionary) -> float:
	return utility_unit_price(state, data, "water")


## What making one unit costs with standard numbers (cents): ingredients at their standard cost,
## a full crew at the minimum wage, water at the base price; no building share, no tax. Used for
## cost tags of older saves, and as the estimate when an ingredient isn't in stock. A resource
## with a fixed "price" costs that price (it's bought).
static func standard_unit_cost(data: Dictionary, resource_id: String) -> float:
	return float(_cached(data, "cost:" + resource_id, func(): return _standard_unit_cost(data, resource_id, {})))


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
			cost += float(def.get("power_mw", 0.0)) * hours * utility_price(data, "power") * 100.0
			visiting.erase(resource_id)
			return cost * float(output_shares(recipe)[resource_id]) / maxf(float(recipe.outputs[resource_id]), 1)
	visiting.erase(resource_id)
	return 0.0


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
##  "buildings": {"working", "idle" (no batch), "done" (batch finished, waiting to be collected),
##   "building" (under construction), "suspended"}}
## "used" counts the ingredients at the pace the batch works through them (they all left the
## Warehouse when it started).
static func production_rates(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var made := {}
	var used := {}
	var counts := {"working": 0, "idle": 0, "done": 0, "building": 0, "suspended": 0}
	for b in state.buildings:
		if not makes_batches(data, b):
			continue
		if not is_built(b, now):
			counts.building += 1
			continue
		if is_suspended(b):
			counts.suspended += 1
			continue
		if not has_batch(b):
			counts.idle += 1
			continue
		if not batch_running(b):
			counts.done += 1
			continue
		var recipe := _recipe(data.buildings[b.type], b.batch.recipe_id)
		if recipe.is_empty():
			continue
		counts.working += 1
		var per_minute := 60.0 / float(recipe.duration) * building_speed(state, data, b, now)
		for res in b.batch.units:  # bonus included
			made[res] = float(made.get(res, 0.0)) + float(b.batch.units[res]) / int(b.batch.hours) * per_minute
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
## people, tied to their building). {"population" (everyone), "adults", "children", "jobs",
## "employed", "unemployed" (adults without a job), "open_jobs"}
static func employment(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	var jobs := 0
	var employed := 0
	for b in state.buildings:
		var open := posts(data, b, now)
		jobs += open
		employed += mini(hired(b), open)
	var people := int(state.population.current)
	var grown := adults(state)
	employed = mini(employed, grown)
	return {"population": people, "adults": grown, "children": people - grown, "jobs": jobs,
		"employed": employed, "unemployed": grown - employed, "open_jobs": jobs - employed}


## Who came and went over at least the last `window` seconds (or since the first history point),
## like cash_flow: {"moved_in", "born", "grew_up", "died", "moved_away", "seconds" (0 = no
## history yet)}.
static func people_flow(state: Dictionary, window: float, now: float) -> Dictionary:
	var counters := people_stats(state)
	var from := {}
	for point in stats(state).history:
		if float(point.t) <= now - window or from.is_empty():
			from = point
	var out := {"seconds": 0.0 if from.is_empty() else maxf(now - float(from.t), 0.0)}
	for key in PEOPLE_COUNTERS:
		out[key] = 0 if from.is_empty() else int(counters[key]) - int(from.get(key, counters[key]))
	return out


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
	var counters := people_stats(state)
	history.append({
		"t": now,
		"cash": int(state.profile.currency),
		"income": _total(s.income),
		"spending": _total(s.spending),
		"population": e.population,
		"adults": e.adults,
		"children": e.children,
		"employed": e.employed,
		"jobs": e.jobs,
		"made": s.made.duplicate(),
		# lifetime counters, so the last hour's comings and goings can be worked out (people_flow)
		"moved_in": int(counters.moved_in),
		"born": int(counters.born),
		"grew_up": int(counters.grew_up),
		"died": int(counters.died),
		"moved_away": int(counters.moved_away),
	})
	var keep := int(data.config.get("stats_history_size", 360))
	while history.size() > keep:
		history.pop_front()


# --- Balance sheet, cash check and money log (plan.md §5.19) -------------------------

## Proves every cent of cash is accounted for (changes nothing): starting cash + all money in −
## all money out + dev tool changes must equal the cash now, exactly. All in cents:
## {"start", "money_in", "money_out", "dev", "expected", "cash", "ok"}.
static func cash_check(state: Dictionary) -> Dictionary:
	var s := stats(state)
	var start := int(s.get("capital", {}).get("cash", 0))
	var money_in := _total(s.income)
	var money_out := _total(s.spending)
	var dev := int(s.get("adjustments", 0))
	var expected := start + money_in - money_out + dev
	var cash := int(state.profile.currency)
	return {"start": start, "money_in": money_in, "money_out": money_out, "dev": dev,
		"expected": expected, "cash": cash, "ok": expected == cash}


## What the company owns and owes right now (changes nothing). All in whole cents:
## owned: "cash" (0 when in debt), "receivable" (Supermarket sales not paid yet, after the tax
## they'll pay), "goods" ({res: {"qty", "value"}}: warehouse + building storage + unsold shelf
## goods + a batch's units ready to collect, at their cost tags), "in_production" (what the
## hours of running batches not finished yet cost: ingredients + prepaid wages), "buildings"
## (price paid), "being_built" (price paid for buildings and upgrades not finished yet), "roads"
## (price paid for the road tiles);
## owed: "debt" (cash below 0), "water_due" and "power_due" (this cycle's bills so far);
## "total_owned", "total_owed", "company_value" (owned − owed), "capital" (what the company
## started with) and "profit_kept" (company value − capital).
static func balance_sheet(state: Dictionary, data: Dictionary, now: float) -> Dictionary:
	# A clock set backwards never makes a finished building look unfinished again.
	now = maxf(now, float(state.get("settled_at", now)))
	var cash := int(state.profile.currency)
	var goods := {}  # res -> [qty, value (float cents)]
	var add_goods := func(stock: Dictionary, costs: Dictionary) -> void:
		for res in stock:
			if int(stock[res]) > 0:
				var entry: Array = goods.get(res, [0, 0.0])
				goods[res] = [int(entry[0]) + int(stock[res]), float(entry[1]) + float(costs.get(res, 0.0))]
	add_goods.call(state.inventory, state.get("inventory_cost", {}))
	var sold_gross := 0
	var in_production := 0.0
	var buildings := 0
	var being_built := 0
	for b in state.buildings:
		add_goods.call(b.get("storage", {}), b.get("storage_cost", {}))
		if has_batch(b):
			# Each unit of a batch is worth its share of the batch's cost: made ones are goods,
			# the rest is still being made.
			var ready := ready_units(b)
			var ready_cost := {}
			for res in ready:
				ready_cost[res] = batch_unit_cost(b.batch, res) * int(ready[res])
			add_goods.call(ready, ready_cost)
			var made := _units_after(b.batch, int(b.batch.get("made_hours", 0)))
			for res in b.batch.units:
				in_production += batch_unit_cost(b.batch, res) * (int(b.batch.units[res]) - int(made.get(res, 0)))
		for shelf in b.get("shelves", []):
			if shelf.is_empty():
				continue
			var unsold := _unsold(shelf)
			sold_gross += (int(shelf.qty) - unsold) * int(shelf.price)
			if unsold > 0:
				add_goods.call({shelf.res: unsold}, {shelf.res: float(shelf.get("cost", 0.0)) * unsold / int(shelf.qty)})
		var paid := int(b.get("paid", 0))
		var upgrade_paid := int(b.get("upgrade_paid", 0)) if b.has("upgrade_done_at") else 0
		if not is_built(b, now) and not b.has("upgrade_done_at"):
			being_built += paid  # its first construction
		else:
			buildings += paid - upgrade_paid
			being_built += upgrade_paid
	var roads := 0
	for road in state.get("roads", []):
		roads += int(road[2]) if road.size() > 2 else 0
	var sheet := {
		"cash": maxi(cash, 0),
		"receivable": sold_gross - sales_tax(state, data, sold_gross, now),
		"goods": {},
		"in_production": roundi(in_production),
		"buildings": buildings,
		"being_built": being_built,
		"roads": roads,
		"debt": maxi(-cash, 0),
		"water_due": int(water_bill_so_far(state, data, now).cost),
		"power_due": int(bill_so_far(state, data, "power", now).cost) if power_on(data) else 0,
	}
	var goods_total := 0
	for res in goods:
		var value := roundi(float(goods[res][1]))
		sheet.goods[res] = {"qty": int(goods[res][0]), "value": value}
		goods_total += value
	sheet.total_owned = int(sheet.cash) + int(sheet.receivable) + goods_total + int(sheet.in_production) + buildings + being_built + roads
	sheet.total_owed = int(sheet.debt) + int(sheet.water_due) + int(sheet.power_due)
	sheet.company_value = int(sheet.total_owned) - int(sheet.total_owed)
	var capital: Dictionary = stats(state).get("capital", {})
	sheet.capital = int(capital.get("cash", 0)) + int(capital.get("buildings", 0))
	sheet.profit_kept = int(sheet.company_value) - int(sheet.capital)
	return sheet


## Takes a snapshot of the money totals if config.money_log_minutes have passed since the last
## one (keeping money_log_size of them). Time spent away becomes a single entry, like the graphs.
static func _record_money_log(state: Dictionary, data: Dictionary, now: float) -> void:
	var s := stats(state)
	if not s.has("money_log"):
		s["money_log"] = []
	var log: Array = s.money_log
	var every := float(data.config.get("money_log_minutes", 30)) * 60.0
	if not log.is_empty() and now < float(log[-1].t) + every:
		return  # too soon (also covers a clock that moved backwards)
	log.append(_money_snapshot(s, now))
	while log.size() > maxi(int(data.config.get("money_log_size", 48)), 1):
		log.pop_front()


static func _money_snapshot(s: Dictionary, t: float) -> Dictionary:
	return {"t": t, "income": s.income.duplicate(), "spending": s.spending.duplicate(),
		"sales_by_item": s.sales_by_item.duplicate(), "adjustments": int(s.get("adjustments", 0))}


## The money log, newest first: what came in and went out between one snapshot and the next,
## plus the block still running up to now ("open": true). Each row, in cents: {"from", "to",
## "open", "income" {source: cents}, "spending" {what: cents}, "sales_by_item" {res: cents},
## "dev", "net" (how much cash changed)}. Sources with nothing in that block are left out.
static func money_log(state: Dictionary, now: float) -> Array:
	var s := stats(state)
	var points: Array = s.get("money_log", []).duplicate()
	if points.is_empty():
		return []
	var running := now > float(points[-1].t)  # a block is still running: show it up to now
	if running:
		points.append(_money_snapshot(s, now))
	var rows := []
	for i in range(points.size() - 1, 0, -1):
		var a: Dictionary = points[i - 1]
		var b: Dictionary = points[i]
		var row := {"from": float(a.t), "to": float(b.t), "open": running and i == points.size() - 1,
			"income": _difference(b.income, a.income), "spending": _difference(b.spending, a.spending),
			"sales_by_item": _difference(b.sales_by_item, a.sales_by_item),
			"dev": int(b.adjustments) - int(a.adjustments)}
		row.net = _total(row.income) - _total(row.spending) + int(row.dev)
		rows.append(row)
	return rows


## after − before for each key, leaving out keys that didn't change.
static func _difference(after: Dictionary, before: Dictionary) -> Dictionary:
	var out := {}
	for key in after:
		var change := int(after[key]) - int(before.get(key, 0))
		if change != 0:
			out[key] = change
	return out


static func _new_stats() -> Dictionary:
	return {
		"income": {"sales": 0, "demolish": 0},  # money in (cents), by where it came from
		"spending": {"construction": 0, "roads": 0, "wages": 0, "water": 0, "power": 0, "tax": 0},  # money out (cents), by what it went on
		"sales_by_item": {},  # resource -> cents earned selling it
		"made": {},  # resource -> amount ever produced
		"sold": {},  # resource -> amount ever sold
		"people": {"moved_in": 0, "born": 0, "grew_up": 0, "died": 0, "moved_away": 0},  # who ever came and went
		# graph points: {t, cash, income, spending, population, adults, children, employed, jobs,
		# made, moved_in, born, grew_up, died, moved_away}
		"history": [],
		# What the company started with (cents): starting cash + the starter buildings at their
		# build cost. new_game fills it in.
		"capital": {"cash": 0, "buildings": 0},
		"adjustments": 0,  # cash changed by the dev tools (cents), so the cash check still adds up
		# snapshots of the money totals every money_log_minutes: {t, income, spending,
		# sales_by_item, adjustments} (see money_log)
		"money_log": [],
	}


# --- Helpers ------------------------------------------------------------------

## The kind of building the homeless put up ("hut": true in buildings.json), or "" if none.
static func hut_type_of(data: Dictionary) -> String:
	var found := ""
	for type_id in data.buildings:
		if bool(data.buildings[type_id].get("hut", false)):
			found = type_id
	return found


## `finished_at` = when construction ends. Until then the building makes nothing and takes no orders.
static func _add_building(state: Dictionary, type_id: String, cell: Vector2i, now: float, finished_at: float) -> Dictionary:
	var b := {
		"id": "b%d" % int(state.next_building_id),
		"type": type_id,
		"level": 1,
		"position": [cell.x, cell.y],
		"built_at": finished_at,
		"storage": {},  # goods a suspended Supermarket couldn't fit in the Warehouse
		"batch": {},  # a Farm, Mill or Bakery's batch (see "Production batches"); {} = idle
		"job_started_at": maxf(now, finished_at),  # when the current batch started
		"hired": 0,  # workers tied to it (whole people, see _hire)
		"paid": 0,  # cents paid for it (build + upgrades): its value on the balance sheet
	}
	state.next_building_id = int(state.next_building_id) + 1
	state.buildings.append(b)
	return b




static func _in_plot(state: Dictionary, cell: Vector2i) -> bool:
	var grid: Array = state.plot.grid_size
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(grid[0]) and cell.y < int(grid[1])


static func _recipe(def: Dictionary, recipe_id: String) -> Dictionary:
	for r in def.get("recipes", []):
		if r.id == recipe_id:
			return r
	return {}


## Cents as whole dollars for a message: 123456 -> "$1,235".
static func _money_text(amount: int) -> String:
	var digits := str(absi(roundi(amount / 100.0)))
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return ("-$" if amount < 0 else "$") + grouped


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
