extends Node
## Holds the live game state and is the only door scenes use to read or change it.
## The rules themselves live in scripts/sim/simulation.gd; this just supplies "now" and the content data.

## Emitted whenever the state may have changed, so UI can refresh.
signal changed

const Simulation = preload("res://scripts/sim/simulation.gd")

var state: Dictionary = {}


func _ready() -> void:
	# Step 3 will load the save file here instead of always starting fresh.
	state = Simulation.new_game(data(), TimeService.now())
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(tick)
	add_child(timer)
	timer.start()


## Content data bundled the way Simulation expects it.
func data() -> Dictionary:
	return {"resources": GameData.resources, "buildings": GameData.buildings, "config": GameData.config}


## Brings everything up to date. Returns what was produced (the offline summary uses this).
func tick() -> Dictionary:
	var report: Dictionary = Simulation.settle(state, data(), TimeService.now())
	changed.emit()
	return report


# --- Player actions (each returns {"ok", "error", ...}) ---

func build(type_id: String, cell: Vector2i) -> Dictionary:
	return _after(Simulation.build(state, data(), type_id, cell, TimeService.now()))


func enqueue(building_id: String, recipe_id: String) -> Dictionary:
	return _after(Simulation.enqueue(state, data(), building_id, recipe_id, TimeService.now()))


func collect(building_id: String) -> Dictionary:
	return _after(Simulation.collect(state, data(), building_id, TimeService.now()))


func fill_queue(building_id: String, recipe_id: String) -> Dictionary:
	return _after(Simulation.fill_queue(state, data(), building_id, recipe_id, TimeService.now()))


func move(building_id: String, cell: Vector2i) -> Dictionary:
	return _after(Simulation.move(state, building_id, cell))


func cancel_job(building_id: String, index: int) -> Dictionary:
	return _after(Simulation.cancel_job(state, data(), building_id, index, TimeService.now()))


func demolish(building_id: String) -> Dictionary:
	return _after(Simulation.demolish(state, data(), building_id, TimeService.now()))


## Halted: storage full, so it makes nothing and pays no wages until collected.
func is_halted(building: Dictionary) -> bool:
	return Simulation.is_halted(data(), building)


## Sales tax a sale worth `gross` would pay right now (changes nothing).
func sales_tax(gross: int) -> int:
	return Simulation.sales_tax(state, data(), gross, TimeService.now())


## {"sold" (Retailer sales, last 24 h), "rate" (bracket the next sale starts in), "next_at"}.
func tax_bracket() -> Dictionary:
	return Simulation.tax_bracket(state, data(), TimeService.now())


## Developer tools only (the dev panel in scenes/debug/, test builds only).
func dev_set_cash(amount: int) -> Dictionary:
	return _after(Simulation.dev_set_cash(state, amount))


func dev_add_cash(amount: int) -> Dictionary:
	return _after(Simulation.dev_add_cash(state, amount))


## level: "low", "medium" or "high" (see staffing_levels in game_config.json).
func set_staffing(building_id: String, level: String) -> Dictionary:
	return _after(Simulation.set_staffing(state, data(), building_id, level, TimeService.now()))


func sell(resource_id: String, qty: int) -> Dictionary:
	return _after(Simulation.sell(state, data(), resource_id, qty, TimeService.now()))


# --- Read-only questions for the UI ---

func currency() -> int:
	return int(state.profile.currency)


func population() -> int:
	return int(state.population.current)


func population_capacity() -> int:
	return Simulation.population_capacity(state, data(), TimeService.now())


func warehouse_total() -> int:
	return Simulation.warehouse_total(state)


func warehouse_cap() -> int:
	return Simulation.warehouse_cap(data())


## Whether type_id could be built on cell right now ({"ok", "error"}); changes nothing.
func can_build(type_id: String, cell: Vector2i) -> Dictionary:
	return Simulation.can_build(state, data(), type_id, cell)


func building_at(cell: Vector2i) -> Dictionary:
	return Simulation.building_at(state, cell)


## The building with this id, or {} if there is none. Read it; don't change it.
func building(building_id: String) -> Dictionary:
	return Simulation.find_building(state, building_id)


## Whether a job could be queued right now ({"ok", "error"}); changes nothing.
func can_enqueue(building_id: String, recipe_id: String) -> Dictionary:
	return Simulation.can_enqueue(state, data(), building_id, recipe_id, TimeService.now())


## How many batches "Fill queue" would add right now (0 = none).
func batches_possible(building_id: String, recipe_id: String) -> int:
	return Simulation.batches_possible(state, data(), building_id, recipe_id, TimeService.now())


## Whether the building could be moved to cell ({"ok", "error"}); changes nothing.
func can_move(building_id: String, cell: Vector2i) -> Dictionary:
	return Simulation.can_move(state, building_id, cell)


## What cancelling that queued job would refund ({"ok", "error", "refund", "in_progress"}); changes nothing.
func can_cancel_job(building_id: String, index: int) -> Dictionary:
	return Simulation.can_cancel_job(state, data(), building_id, index)


## What demolishing would give back ({"ok", "error", "money", "goods"}); changes nothing.
func can_demolish(building_id: String) -> Dictionary:
	return Simulation.can_demolish(state, data(), building_id)


func job_progress(building: Dictionary) -> float:
	return Simulation.job_progress(state, building, data(), TimeService.now())


## How fast the building works right now: 1.0 = full speed, less when short of workers.
func building_speed(building: Dictionary) -> float:
	return Simulation.building_speed(state, data(), building, TimeService.now())


## Share of jobs filled in town (0.0 to 1.0). Below 1, every building gets that share of the
## workers it asks for.
func staffing() -> float:
	return Simulation.staffing(state, data(), TimeService.now())


## A building's workers: {"level" (low/medium/high), "wanted" (asked for at that level),
## "working" (actually working, can be a fraction when short), "max", "wage_each" (per hour),
## "wages" (per hour now), "type" (worker type name)}.
func workers(building: Dictionary) -> Dictionary:
	var now := TimeService.now()
	var d := data()
	var type_id: String = d.buildings.get(building.type, {}).get("worker_type", "low_skilled")
	return {
		"level": Simulation.staffing_level(d, building),
		"wanted": Simulation.workers_wanted(d, building),
		"working": Simulation.workers_working(state, d, building, now),
		"max": Simulation.max_workers(d, building),
		"wage_each": Simulation.wage_per_worker(d, building),
		"wages": Simulation.building_wages(state, d, building, now),
		"type": str(d.config.get("worker_types", {}).get(type_id, {}).get("name", type_id)),
	}


## False while the building is still under construction.
func is_built(building: Dictionary) -> bool:
	return Simulation.is_built(building, TimeService.now())


## 0.0 to 1.0 progress of construction (1.0 = finished).
func construction_progress(building: Dictionary) -> float:
	return Simulation.construction_progress(building, data(), TimeService.now())


## Lifetime counters and graph history (see Simulation.stats). Read it; don't change it.
func stats() -> Dictionary:
	return Simulation.stats(state)


## Per-minute rates of what's being made and used right now (see Simulation.production_rates).
func production_rates() -> Dictionary:
	return Simulation.production_rates(state, data(), TimeService.now())


## {"population", "jobs", "employed", "unemployed", "open_jobs"}
func employment() -> Dictionary:
	return Simulation.employment(state, data(), TimeService.now())


## Money in and out over (up to) the last `window` seconds: {"income", "spending", "seconds"}.
func cash_flow(window: float) -> Dictionary:
	return Simulation.cash_flow(state, window, TimeService.now())


## Seconds until construction ends (0 when finished).
func construction_left(building: Dictionary) -> float:
	return maxf(Simulation.built_at(building) - TimeService.now(), 0.0)


func _after(result: Dictionary) -> Dictionary:
	if result.ok:
		changed.emit()
	return result
