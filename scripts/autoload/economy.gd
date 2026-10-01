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


func sell(resource_id: String, qty: int) -> Dictionary:
	return _after(Simulation.sell(state, data(), resource_id, qty))


# --- Read-only questions for the UI ---

func currency() -> int:
	return int(state.profile.currency)


func population() -> int:
	return int(state.population.current)


func population_capacity() -> int:
	return Simulation.population_capacity(state, data())


func warehouse_total() -> int:
	return Simulation.warehouse_total(state)


func warehouse_cap() -> int:
	return Simulation.warehouse_cap(data())


func building_at(cell: Vector2i) -> Dictionary:
	return Simulation.building_at(state, cell)


func job_progress(building: Dictionary) -> float:
	return Simulation.job_progress(building, data(), TimeService.now())


func _after(result: Dictionary) -> Dictionary:
	if result.ok:
		changed.emit()
	return result
