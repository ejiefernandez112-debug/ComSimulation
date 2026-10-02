extends Node
## Holds the live game state and is the only door scenes use to read or change it.
## The rules themselves live in scripts/sim/simulation.gd; this just supplies "now" and the content data.

## Emitted whenever the state may have changed, so UI can refresh.
signal changed

const Simulation = preload("res://scripts/sim/simulation.gd")
const SaveFormat = preload("res://scripts/sim/save_format.gd")

## The save, plus the one before it in case the newest gets damaged (plan.md §8).
const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.backup.json"
const TEMP_PATH := "user://save.tmp"

var state: Dictionary = {}
## What happened while the game was closed, worked out once at start-up (for the welcome-back
## screen): the settle report ({"wheat": 30, "wages": 120, ...}) and how long the player was away.
var offline_report: Dictionary = {}
var offline_seconds: float = 0.0
## Messages for the player about the save (couldn't be read, something was dropped). Empty = fine.
var save_notes: Array[String] = []

var _dirty := false  # a player action changed the state since the last save


func _ready() -> void:
	if Engine.has_meta("running_tests"):  # tests/test_simulation.gd: never touch the real save
		state = Simulation.new_game(data(), TimeService.now())
		return
	_load_game()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(tick)
	add_child(timer)
	timer.start()
	# Saving often is cheap and means a crash or a dead battery loses almost nothing.
	var autosave := Timer.new()
	autosave.wait_time = maxf(float(GameData.config.get("autosave_seconds", 30)), 5.0)
	autosave.timeout.connect(save_game)
	add_child(autosave)
	autosave.start()


## Save whenever the game might be about to stop: window closed, phone app sent to the
## background (phones may kill it there without warning), Android back button, or quitting.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_game()


func _exit_tree() -> void:
	save_game()  # covers get_tree().quit() (the Quit button), which sends no close request


## Content data bundled the way Simulation expects it.
func data() -> Dictionary:
	return {"resources": GameData.resources, "buildings": GameData.buildings, "config": GameData.config}


## Brings everything up to date. Returns what was produced (the offline summary uses this).
func tick() -> Dictionary:
	var report: Dictionary = Simulation.settle(state, data(), TimeService.now())
	if _dirty:
		save_game()  # once per second at most, so a burst of taps is one write
	changed.emit()
	return report


# --- Saving and loading ---

## Writes the save file. Writes a temporary file first and only then swaps it in, so a crash
## halfway through never leaves a half-written save; the previous save is kept as the backup.
func save_game() -> bool:
	if state.is_empty() or Engine.has_meta("running_tests"):
		return false
	var text := SaveFormat.to_text(state, TimeService.now())
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Couldn't write the save: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(text)
	var failed := file.get_error() != OK
	file.close()
	if failed:
		push_warning("Couldn't write the save (disk full?)")
		return false
	var dir := DirAccess.open("user://")
	if dir.file_exists(SAVE_PATH.get_file()):
		if dir.file_exists(BACKUP_PATH.get_file()):
			dir.remove(BACKUP_PATH.get_file())
		dir.rename(SAVE_PATH.get_file(), BACKUP_PATH.get_file())
	if dir.rename(TEMP_PATH.get_file(), SAVE_PATH.get_file()) != OK:
		push_warning("Couldn't swap in the new save")
		return false
	_dirty = false
	return true


## Throws the current game away and starts over (Settings → Start over). The old save stays
## as the backup until the next save replaces it.
func start_new_game() -> void:
	state = Simulation.new_game(data(), TimeService.now())
	offline_report = {}
	offline_seconds = 0.0
	save_game()
	changed.emit()


## Start-up: open the save (or its backup), work out everything that happened while the game was
## closed in one calculation, or start a new game if there's no save yet.
func _load_game() -> void:
	var now := TimeService.now()
	var main := _read_save(SAVE_PATH)
	var result := main
	if not main.ok and main.error != "":
		# Keep the unreadable save under another name, so later saves never overwrite it.
		var keep := "save.unreadable-%d.json" % int(now)
		DirAccess.open("user://").rename(SAVE_PATH.get_file(), keep)
		result = _read_save(BACKUP_PATH)
		if result.ok:
			save_notes.append("%s The save before it was loaded instead (the damaged file was kept as %s)." % [main.error, keep])
		else:
			save_notes.append("%s A new game was started (the old file was kept as %s)." % [main.error, keep])
	elif not main.ok:
		result = _read_save(BACKUP_PATH)  # no save, but maybe a crash right after the backup step
	if not result.ok:
		state = Simulation.new_game(data(), now)
		return
	state = result.state
	save_notes.append_array(result.warnings)
	var settled := float(state.get("settled_at", now))
	if settled > now and OS.is_debug_build():
		# The save was made after the dev panel skipped time ahead: skip ahead again, or nothing
		# would happen until the real clock caught up. (Real players never warp the clock.)
		TimeService.warp(settled - now)
		now = settled
	offline_seconds = maxf(now - settled, 0.0)
	offline_report = Simulation.settle(state, data(), now)


## {"ok", "error" ("" when there simply is no file), "state", "warnings"}
func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "", "state": {}, "warnings": []}
	return SaveFormat.from_text(FileAccess.get_file_as_string(path), data())


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


## Switch a building off: progress lost, goods to the warehouse ({"moved", "kept"}), no wages.
func suspend(building_id: String) -> Dictionary:
	return _after(Simulation.suspend(state, data(), building_id, TimeService.now()))


## Switch it back on: workers return, work starts from the beginning. Free.
func resume(building_id: String) -> Dictionary:
	return _after(Simulation.resume(state, data(), building_id, TimeService.now()))


## Whether it could be suspended ({"ok", "error", "goods" going to the warehouse}); changes nothing.
func can_suspend(building_id: String) -> Dictionary:
	return Simulation.can_suspend(state, data(), building_id)


func is_suspended(building: Dictionary) -> bool:
	return Simulation.is_suspended(building)


## The room this warehouse adds right now (fewer workers = less room); 0 for other buildings.
func storage_capacity(building: Dictionary) -> int:
	return Simulation.storage_capacity(state, data(), building)


## Halted: storage full, so it makes nothing and pays no wages until collected.
func is_halted(building: Dictionary) -> bool:
	return Simulation.is_halted(data(), building)


## Producing: has work and room for it (not halted, not an idle Mill/Bakery). Only then are
## its workers working and paid.
func is_producing(building: Dictionary) -> bool:
	return Simulation.is_producing(data(), building)


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


## level: "none", "small", "good" or "big" (see wage_bonuses in game_config.json).
func set_bonus(building_id: String, level: String) -> Dictionary:
	return _after(Simulation.set_bonus(state, data(), building_id, level, TimeService.now()))


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
	return Simulation.warehouse_cap(state, data())


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


## Share of the town's posts that are filled (0.0 to 1.0). Below 1 the town is short of people:
## some buildings have open posts (the ones with the smallest bonuses fill last).
func staffing() -> float:
	return Simulation.staffing(state, data(), TimeService.now())


## A building's workers: {"level" (low/medium/high), "wanted" (asked for at that level),
## "working" (actually working, can be a fraction when short), "max", "wage_each" (per hour),
## "wages" (per hour now), "type" (worker type name), "fixed" (true = no staffing choice),
## "hired" (tied to it), "bonus" (wage bonus level), "minimum" (minimum wage per hour)}.
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
		"fixed": Simulation.has_fixed_workers(d, building),  # no Low/Medium/High choice (warehouses)
		"hired": Simulation.hired(building),  # tied to it, working or waiting unpaid
		"bonus": Simulation.bonus_level(d, building),  # none / small / good / big
		"minimum": Simulation.minimum_wage(d, building),  # per hour, before the bonus
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
		_dirty = true
		changed.emit()
	return result
