extends Node
## Holds the live game state and is the only door scenes use to read or change it.
## The rules themselves live in scripts/sim/simulation.gd; this just supplies "now" and the content data.

## Emitted whenever the state may have changed, so UI can refresh.
signal changed
## A water bill was just charged while playing (cents, m³). Bills charged while the game was
## closed are in offline_report instead (the Welcome back window).
signal water_bill_paid(cost: int, m3: float)
## A power bill was just charged while playing (cents, MWh). While closed: offline_report instead.
signal power_bill_paid(cost: int, mwh: float)
## Supermarket shelves sold out while playing: `earned` = cents after tax, `sold` = {item: units}.
## Sales while the game was closed are in offline_report instead.
signal shelves_sold(earned: int, sold: Dictionary)
## People came or went while playing: `report` is the settle report, with "population" (moved
## in), "born", "grew_up", "moved_away" (counts; missing = 0). While closed: offline_report instead.
signal people_changed(report: Dictionary)

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
## How long the last tick took, in microseconds: "rules" (settling) and "screens" (everything
## that refreshed on `changed`). Shown by the performance overlay (scenes/debug/).
var last_tick_usec := {"rules": 0, "screens": 0}

var _dirty := false  # a player action changed the state since the last save
var _data := {}  # see data()
var _memo := {}  # answers to heavy questions, kept until the state changes (see _remember)
var _hiring := {}  # what the last tick's hiring worked out (settle's `moment`); {} once anything else changed the state


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


## Content data bundled the way Simulation expects it, made once. Its "cache" keeps prices
## Simulation has worked out (data/*.json never changes while playing).
func data() -> Dictionary:
	if _data.is_empty():
		_data = {"resources": GameData.resources, "buildings": GameData.buildings, "config": GameData.config, "cache": {}}
	return _data


## Brings everything up to date. Returns what was produced (the offline summary uses this).
func tick() -> Dictionary:
	var started := Time.get_ticks_usec()
	var moment := _hiring  # nothing changed since the last tick (actions forget it), so settle may reuse it
	var report: Dictionary = Simulation.settle(state, data(), TimeService.now(), moment)
	_hiring = moment
	last_tick_usec.rules = Time.get_ticks_usec() - started
	_memo.clear()
	# Who lives where and the power were just worked out for this very moment: keep them.
	if not moment.housing.is_empty():
		_memo["housing"] = moment.housing
	if not moment.power.is_empty():
		_memo["power_summary"] = moment.power
	if int(report.get("water", 0)) > 0 and not water_bills().is_empty():
		water_bill_paid.emit(int(report.water), float(water_bills()[-1].m3))
		_dirty = true  # save soon after a bill
	if int(report.get("power", 0)) > 0 and not power_bills().is_empty():
		power_bill_paid.emit(int(report.power), float(power_bills()[-1].mwh))
		_dirty = true
	var sold := sold_in(report)
	if not sold.is_empty():
		shelves_sold.emit(int(report.get("store_sales", 0)), sold)
		_dirty = true
	for key in ["population", "born", "grew_up", "moved_away"]:
		if int(report.get(key, 0)) > 0:
			people_changed.emit(report)
			break
	if _dirty:
		save_game()  # once per second at most, so a burst of taps is one write
	var refreshing := Time.get_ticks_usec()
	changed.emit()
	last_tick_usec.screens = Time.get_ticks_usec() - refreshing
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
	_memo.clear()
	_hiring = {}
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
	_memo.clear()
	_hiring = {}


## {"ok", "error" ("" when there simply is no file), "state", "warnings"}
func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "", "state": {}, "warnings": []}
	return SaveFormat.from_text(FileAccess.get_file_as_string(path), data())


# --- Player actions (each returns {"ok", "error", ...}) ---

func build(type_id: String, cell: Vector2i) -> Dictionary:
	return _after(Simulation.build(state, data(), type_id, cell, TimeService.now()))


## Start a production batch of `hours` with wage bonus `bonus` (plan.md §5.1): ingredients and
## wages are paid now. Returns the batch's quote (see batch_quote) on success.
func start_batch(building_id: String, recipe_id: String, hours: int, bonus: String) -> Dictionary:
	return _after(Simulation.start_batch(state, data(), building_id, recipe_id, hours, bonus, TimeService.now()))


## Cancel the running batch: hours already made are kept; part of the rest comes back
## ({"refund", "money", "hours_left"}).
func cancel_batch(building_id: String) -> Dictionary:
	return _after(Simulation.cancel_batch(state, data(), building_id, TimeService.now()))


func collect(building_id: String) -> Dictionary:
	return _after(Simulation.collect(state, data(), building_id, TimeService.now()))


## Collect from this building and every other one of its type ({"moved", "by_building", "left_over"}).
func collect_group(building_id: String) -> Dictionary:
	return _after(Simulation.collect_group(state, data(), building_id, TimeService.now()))


func move(building_id: String, cell: Vector2i) -> Dictionary:
	return _after(Simulation.move(state, data(), building_id, cell, TimeService.now()))


## Build road on these tiles (Vector2i), paid now (plan.md §5.20). {"cost", "new_cells"}.
func build_roads(cells: Array) -> Dictionary:
	return _after(Simulation.build_roads(state, data(), cells, TimeService.now()))


## Remove the road on these tiles (free, nothing paid back). {"cells"}.
func remove_roads(cells: Array) -> Dictionary:
	return _after(Simulation.remove_roads(state, data(), cells, TimeService.now()))


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


## Start the building's next upgrade (buys its materials and pays its crew now; plan.md §5.15).
func upgrade(building_id: String) -> Dictionary:
	return _after(Simulation.upgrade(state, data(), building_id, TimeService.now()))


## Whether it could be upgraded now ({"ok", "error", "level", "cost" (cents, today's prices),
## "seconds", "lines" (what it needs, see build_quote)}).
func can_upgrade(building_id: String) -> Dictionary:
	return Simulation.can_upgrade(state, data(), building_id, TimeService.now())


## What the building's next upgrade needs and costs at today's prices (see build_quote); {} at
## the top level.
func upgrade_quote(building: Dictionary) -> Dictionary:
	var level := Simulation.building_level(building)
	if level >= Simulation.max_level(data(), building.type):
		return {}
	return Simulation.construction_plan(state, data(), building.type, level + 1, TimeService.now())


## The next level's entry in buildings.json (what changes); {} at the top.
func next_upgrade(building: Dictionary) -> Dictionary:
	return Simulation.next_upgrade(data(), building)


## The building's level, and the highest its kind can reach.
func building_level(building: Dictionary) -> int:
	return Simulation.building_level(building)


func max_level(type_id: String) -> int:
	return Simulation.max_level(data(), type_id)


func is_upgrading(building: Dictionary) -> bool:
	return Simulation.is_upgrading(building, TimeService.now())


## Seconds until its upgrade is done (0 when it isn't being upgraded).
func upgrade_left(building: Dictionary) -> float:
	return maxf(float(building.get("upgrade_done_at", 0.0)) - TimeService.now(), 0.0)


## True when the building keeps working while it's upgraded (homes, warehouses).
func stays_open_while_upgrading(building: Dictionary) -> bool:
	return Simulation.stays_open_while_upgrading(data(), building)


## A number from buildings.json at the building's level (max_workers, capacity, shelves,
## households).
func level_stat(building: Dictionary, key: String, default: Variant = 0) -> Variant:
	return Simulation.level_stat(data(), building, key, default)


## The room this warehouse adds right now (fewer workers = less room); 0 for other buildings.
func storage_capacity(building: Dictionary) -> int:
	return Simulation.storage_capacity(state, data(), building)


## Producing: has work to do (a batch being made, shelves to sell). Only then are its workers
## working.
func is_producing(building: Dictionary) -> bool:
	return Simulation.is_producing(data(), building)


## Sales tax a sale worth `gross` would pay right now (changes nothing).
func sales_tax(gross: int) -> int:
	return Simulation.sales_tax(state, data(), gross, TimeService.now())


## {"sold" (Retailer sales, last 24 h), "rate" (bracket the next sale starts in), "next_at"}.
func tax_bracket() -> Dictionary:
	return Simulation.tax_bracket(state, data(), TimeService.now())


## Several screens ask the same heavy questions every second (who lives where, happiness, the
## power), and each answer walks every building. So the first answer is kept, under `key`, until
## the state changes: every tick and every player action forget them all (in between, an answer
## is at most a second old, like everything else on screen). Read them; don't change them.
func _remember(key: String, work: Callable) -> Variant:
	if not _memo.has(key):
		_memo[key] = work.call()
	return _memo[key]


## Developer tools only (the dev panel in scenes/debug/, test builds only). Amounts in dollars.
func dev_set_cash(dollars: float) -> Dictionary:
	return _after(Simulation.dev_set_cash(state, Simulation.cents(dollars)))


func dev_add_cash(dollars: float) -> Dictionary:
	return _after(Simulation.dev_add_cash(state, Simulation.cents(dollars)))


## Developer: rent per household (dollars an hour) for a home type; a negative amount resets it
## to the rent in buildings.json.
func dev_set_rent(type_id: String, dollars: float) -> Dictionary:
	return _after(Simulation.dev_set_rent(state, data(), type_id, dollars, TimeService.now()))


## Rent per household per hour (dollars) for a home type, with any developer change.
func rent_per_household(type_id: String) -> float:
	return Simulation.rent_per_household(state, data(), type_id)


## True when the developer changed this home type's rent.
func rent_changed(type_id: String) -> bool:
	return state.get("dev_rent", {}).has(type_id)


## level: "low", "medium" or "high" (see staffing_levels in game_config.json).
func set_staffing(building_id: String, level: String) -> Dictionary:
	return _after(Simulation.set_staffing(state, data(), building_id, level, TimeService.now()))


## The bonus offered for the next batch. level: "none", "small", "good" or "big" (see
## wage_bonuses / bonus_output in game_config.json). Refused while a batch is under way.
func set_bonus(building_id: String, level: String) -> Dictionary:
	return _after(Simulation.set_bonus(state, data(), building_id, level, TimeService.now()))


func sell(resource_id: String, qty: int) -> Dictionary:
	return _after(Simulation.sell(state, data(), resource_id, qty, TimeService.now()))


# --- Trading Post (plan.md §5.22) ---

## True when the village has a working Trading Post.
func has_trading_post() -> bool:
	return Simulation.has_trading_post(state, data(), TimeService.now())


## The trader's price for one unit (cents): side "sell" = what it pays you, "buy" = what you pay.
func trade_price(resource_id: String, side: String) -> int:
	return Simulation.trade_price(data(), resource_id, side)


## What selling that to the trader would bring ({"ok", "error", "price", "gross", "tax", "earned",
## "cost", "profit"}); changes nothing.
func can_trade_sell(resource_id: String, qty: int) -> Dictionary:
	return Simulation.can_trade_sell(state, data(), resource_id, qty, TimeService.now())


func trade_sell(resource_id: String, qty: int) -> Dictionary:
	return _after(Simulation.trade_sell(state, data(), resource_id, qty, TimeService.now()))


## What buying that from the trader would cost ({"ok", "error", "price", "cost"}); changes nothing.
func can_trade_buy(resource_id: String, qty: int) -> Dictionary:
	return Simulation.can_trade_buy(state, data(), resource_id, qty, TimeService.now())


func trade_buy(resource_id: String, qty: int) -> Dictionary:
	return _after(Simulation.trade_buy(state, data(), resource_id, qty, TimeService.now()))


## True when the village already has as many of this building as it may (the Trading Post: 1).
func at_build_limit(type_id: String) -> bool:
	return Simulation.at_build_limit(state, data(), type_id)


# --- Supermarket (plan.md §5.16) ---

## Put `qty` × `resource_id` on a free shelf at price tag `tag` ("normal", "sale", ...).
func stock_shelf(building_id: String, resource_id: String, qty: int, tag: String) -> Dictionary:
	return _after(Simulation.stock_shelf(state, data(), building_id, resource_id, qty, tag, TimeService.now()))


## Take shelf `index` down: what's sold is paid for, the rest goes back to the warehouse.
func clear_shelf(building_id: String, index: int) -> Dictionary:
	return _after(Simulation.clear_shelf(state, data(), building_id, index, TimeService.now()))


## Whether those goods could go on a shelf ({"ok", "error"}); changes nothing.
func can_stock_shelf(building_id: String, resource_id: String, qty: int, tag: String) -> Dictionary:
	return Simulation.can_stock_shelf(state, data(), building_id, resource_id, qty, tag, TimeService.now())


## What taking that shelf down would do ({"ok", "error", "sold", "paid", "back"}); changes nothing.
func can_clear_shelf(building_id: String, index: int) -> Dictionary:
	return Simulation.can_clear_shelf(state, data(), building_id, index)


## What putting those goods on a shelf would bring (see Simulation.stock_preview; cents).
func stock_preview(building_id: String, resource_id: String, qty: int, tag: String) -> Dictionary:
	return Simulation.stock_preview(state, data(), building_id, resource_id, qty, tag, TimeService.now())


## The store's shelves, one entry per shelf ({} = empty; else "res", "qty", "price", "tag", ...).
func shelves(building: Dictionary) -> Array:
	return Simulation.shelves(data(), building)


## Units of that shelf sold so far (counting up between ticks).
func shelf_sold_now(building: Dictionary, index: int) -> float:
	return Simulation.shelf_sold_now(state, data(), building, index, TimeService.now())


## Seconds until that shelf sells out at today's pace (INF while it isn't selling).
func shelf_time_left(building: Dictionary, index: int) -> float:
	return Simulation.shelf_time_left(state, data(), building, index, TimeService.now())


## The store's shoppers: 1.0, +10% for each different product on its shelves beyond the first.
func shoppers(building: Dictionary) -> float:
	return Simulation.shoppers(data(), building)


## The goods shops can sell (finished goods people buy), in resources.json order.
func shop_products() -> Array[String]:
	return Simulation.shop_products(data())


## The goods a store of this type sells (its "sells" categories), in resources.json order.
func store_products(type_id: String) -> Array[String]:
	return Simulation.store_products(data(), type_id)


## An item's category id ("food", "crop", ...; "" if it has none).
func item_category(resource_id: String) -> String:
	return Simulation.item_category(data(), resource_id)


## A category's name for the screen ("Food"), from game_config.json item_categories.
func category_name(category_id: String) -> String:
	return str(GameData.config.get("item_categories", {}).get(category_id, {}).get("name", category_id.capitalize()))


## Where that item is on sale ({"building_id", "index"} of the first store found), or {} if on no shelf.
func shelf_selling(resource_id: String) -> Dictionary:
	return Simulation.shelf_selling(state, resource_id)


## True when this store already has that item on one of its shelves.
func store_has_product(building_id: String, resource_id: String) -> bool:
	return Simulation.store_has_product(Simulation.find_building(state, building_id), resource_id)


## How many stores are selling each item right now: {item: stores} (they share its shoppers).
func selling_counts() -> Dictionary:
	return Simulation.selling_counts(state, data(), TimeService.now())


## {"item": units} sold out on shelves, from a settle report (its "sold:<item>" entries).
static func sold_in(report: Dictionary) -> Dictionary:
	var sold := {}
	for key in report:
		if str(key).begins_with("sold:"):
			sold[str(key).trim_prefix("sold:")] = int(report[key])
	return sold


# --- Read-only questions for the UI ---

## Cash, in cents (UITheme.money shows it as "$5,750.00").
func currency() -> int:
	return int(state.profile.currency)


## What one unit sells for at the Retailer right now, in cents, worked out from its costs
## (plan.md §5.12).
func unit_price(resource_id: String) -> int:
	return Simulation.unit_price(data(), resource_id)


## m³ of water per hour this building draws right now (own plants first, then the public
## supply; 0 when not producing).
func water_use(building: Dictionary) -> float:
	return Simulation.water_use(state, data(), building, TimeService.now())


## What the water this building draws costs per hour right now (dollars): own plants' water at
## its own price, the rest at the public price.
func water_cost_per_hour(building: Dictionary) -> float:
	return Simulation.water_cost_per_hour(state, data(), building, TimeService.now())


## m³ of water per hour this Water Treatment Plant cleans right now (0 for other buildings).
func water_supply(building: Dictionary) -> float:
	return Simulation.water_supply(state, data(), building, TimeService.now())


## The company's water right now (m³/h): {"own", "used", "from_own", "public", "spare",
## "own_price" (dollars per own m³)}.
func water_summary() -> Dictionary:
	return _remember("water_summary", func(): return Simulation.water_summary(state, data(), TimeService.now()))


## The water bill building up this cycle: {"m3", "cost" (cents, heavy-user extra included),
## "due_at" (unix time it's charged)}.
func water_bill() -> Dictionary:
	return Simulation.water_bill_so_far(state, data(), TimeService.now())


## Past water bills, oldest first: [{"t" (when charged), "m3", "cost" (cents)}].
func water_bills() -> Array:
	return state.get("water_bills", [])


# --- Electricity (plan.md §5.5) ---

## Whether this game has electricity (game_config.json has a "power" block).
func power_on() -> bool:
	return Simulation.power_on(data())


## MW this building needs while it runs (0 = none).
func power_need(building: Dictionary) -> float:
	return Simulation.power_need(data(), building)


## Why it has no power: "short" (not enough left), "no_grid" (outside the network), or "".
func power_problem(building: Dictionary) -> String:
	return Simulation.power_problem(building)


## MW this power plant makes right now (0 for other buildings).
func power_supply(building: Dictionary) -> float:
	return Simulation.power_supply(state, data(), building, TimeService.now())


## How many tiles around it its power reaches (0 = it carries none).
func power_radius(building: Dictionary) -> float:
	return Simulation.power_radius(data(), building)


## The power right now: {"own", "grid", "used", "wanted", "from_own", "public", "spare", "left",
## "own_price", "status"} (see Simulation.power_summary).
func power_summary() -> Dictionary:
	return _remember("power_summary", func(): return Simulation.power_summary(state, data(), TimeService.now(), housing()))


## The power network: {"ids" (buildings joined), "areas" [[centre (Vector2, in tiles), radius]]}.
func power_network() -> Dictionary:
	return _remember("power_network", func(): return Simulation.power_network(state, data(), TimeService.now()))


## Whether `cell` is inside the power network's reach.
func is_powered_cell(cell: Vector2i) -> bool:
	return Simulation.is_powered_cell(power_network(), cell)


## Whether a point in tiles (e.g. a building's middle, centre_at) is inside the network's reach.
func is_powered_point(point: Vector2) -> bool:
	return Simulation.is_powered_point(power_network(), point)


## Every tile of the plot inside the power network's reach: Vector2i -> true (for the map).
func powered_cells() -> Dictionary:
	return _remember("powered_cells", func():
		var network := power_network()
		var cells := {}
		var size: Array = state.plot.grid_size
		for y in int(size[1]):
			for x in int(size[0]):
				if Simulation.is_powered_cell(network, Vector2i(x, y)):
					cells[Vector2i(x, y)] = true
		return cells)


## Whether a plant or substation of this kind, reaching `radius` tiles, would join the network
## standing at `cell` (its position).
func would_join_network(type_id: String, cell: Vector2i, radius: float) -> bool:
	return Simulation.would_join_network(power_network(), Simulation.centre_at(data(), type_id, cell), radius)


## What this building's power costs per hour right now (dollars).
func power_cost_per_hour(building: Dictionary) -> float:
	return Simulation.power_cost_per_hour(state, data(), building, TimeService.now())


## The power bill building up this cycle: {"mwh", "cost" (cents), "due_at"}.
func power_bill() -> Dictionary:
	return Simulation.bill_so_far(state, data(), "power", TimeService.now())


## Past power bills, oldest first: [{"t", "mwh", "cost" (cents)}].
func power_bills() -> Array:
	return state.get("power_bills", [])


## What a batch of `hours` with bonus `bonus` would make and cost, in cents: units, ingredients,
## wages, water, total, cost per unit, finish time (see Simulation.batch_quote). {} if it makes
## nothing.
func batch_quote(building: Dictionary, recipe_id: String, hours: int, bonus: String) -> Dictionary:
	return Simulation.batch_quote(state, data(), building, recipe_id, hours, bonus, TimeService.now())


## The recipe this building is set up for, or "" while it hasn't chosen (its first batch chooses).
func product_of(building: Dictionary) -> String:
	return Simulation.product_of(data(), building)


## True when this type of building can switch to another product later, for a fee.
func is_switchable(type_id: String) -> bool:
	return Simulation.is_switchable(data(), type_id)


## What switching this building to another product costs (cents).
func switch_fee(building: Dictionary) -> int:
	return Simulation.switch_fee(data(), building)


## Whether it could switch to that product now ({"ok", "error", "fee"}); changes nothing.
func can_switch_product(building_id: String, recipe_id: String) -> Dictionary:
	return Simulation.can_switch_product(state, data(), building_id, recipe_id)


## Switch it to another product: the fee is paid now (plan.md §5.21).
func switch_product(building_id: String, recipe_id: String) -> Dictionary:
	return _after(Simulation.switch_product(state, data(), building_id, recipe_id, TimeService.now()))


## What one unit of that item from this batch cost to make (cents; by-products carry their share).
func batch_unit_cost(batch: Dictionary, resource_id: String) -> float:
	return Simulation.batch_unit_cost(batch, resource_id)


## Whether that batch could start now ({"ok", "error"} + the quote); changes nothing.
func can_start_batch(building_id: String, recipe_id: String, hours: int, bonus: String) -> Dictionary:
	return Simulation.can_start_batch(state, data(), building_id, recipe_id, hours, bonus, TimeService.now())


## The longest batch that could start now, in hours (0 = none): limited by batch.max_hours, the
## ingredients in the Warehouse and the cash for the wages.
func batch_max_hours(building_id: String, recipe_id: String, bonus: String) -> int:
	return Simulation.batch_max_hours(state, data(), building_id, recipe_id, bonus)


## The longest batch allowed at all, and the length the panel offers first.
func batch_hours_limit() -> int:
	return Simulation.batch_hours_limit(data())


func batch_default_hours() -> int:
	return Simulation.batch_default_hours(data())


## Extra share of units a bonus makes (0.1 = +10%).
func bonus_output(bonus: String) -> float:
	return Simulation.bonus_output(data(), bonus)


## What cancelling the running batch would give back ({"ok", "error", "refund", "money",
## "hours_left"}); changes nothing.
func can_cancel_batch(building_id: String) -> Dictionary:
	return Simulation.can_cancel_batch(state, data(), building_id)


## Units the batch has made that wait to be collected: {res: qty}. Goods waiting of any kind
## (a batch's units, or a suspended shop's leftovers): waiting_goods.
func ready_units(building: Dictionary) -> Dictionary:
	return Simulation.ready_units(building)


func waiting_goods(building: Dictionary) -> Dictionary:
	return Simulation.waiting_goods(building)


## True while the building has a batch (being made, or made and waiting to be collected), and
## while that batch still has hours to go.
func has_batch(building: Dictionary) -> bool:
	return Simulation.has_batch(building)


func batch_running(building: Dictionary) -> bool:
	return Simulation.batch_running(building)


## True for buildings that make things in batches (Farm, Mill, Bakery).
func makes_batches(building: Dictionary) -> bool:
	return Simulation.makes_batches(data(), building)


## When the running batch should be done at today's speed (unix time; INF with nobody working).
func batch_finishes_at(building: Dictionary) -> float:
	return Simulation.batch_finishes_at(state, data(), building, TimeService.now())


## Average cost tag (cents per unit) of this item in the warehouse: what it cost you to make or buy.
func average_cost(resource_id: String) -> float:
	return Simulation.average_cost(state, resource_id)


## The money building this type takes at today's material prices, in cents (plan.md §5.15; the
## warehouse's own materials are used first).
func build_cost(type_id: String) -> int:
	return int(build_quote(type_id).cost)


## What building this type needs and costs at today's prices, the warehouse's own materials used
## first: {"cost" (cents of money), "seconds", "lines": [{"id", "name", "unit", "amount",
## "from_stock", "buy", "price" (cents each), "cost" (of what's bought)}]}; the crew's line has id
## "labor", amount = workers and "share" (of the materials' value).
func build_quote(type_id: String) -> Dictionary:
	return Simulation.construction_plan(state, data(), type_id, 1, TimeService.now())


## Seconds until construction material prices change next.
func price_change_in() -> float:
	return maxf(Simulation.next_price_change_at(data(), TimeService.now()) - TimeService.now(), 0.0)


func population() -> int:
	return int(state.population.current)


func population_capacity() -> int:
	return _remember("population_capacity", func(): return Simulation.population_capacity(state, data(), TimeService.now()))


## People living in this home (adults and children; 0 while it's being built).
func home_residents(building: Dictionary) -> int:
	return Simulation.home_residents(state, data(), building, TimeService.now())


## Who lives where: {"homes": {building_id: {"households", "adults", "children", "rent"}},
## "classes": {class: {"households", "adults", "homeless"}}, "homeless", "rent_per_hour",
## "child_places", "power_mw", "households"} (see Simulation.housing).
func housing() -> Dictionary:
	return _remember("housing", func(): return Simulation.housing(state, data(), TimeService.now()))


## The wealth classes, poorest first: [{"id", "name", "from_wage"}].
func wealth_classes() -> Array:
	return Simulation.wealth_classes(data())


## Room for adults in finished real homes (huts left out).
func adult_room() -> int:
	return Simulation.adult_room(state, data(), TimeService.now())


## Seconds until the next job seeker moves in (INF when no job is open, the homes are full or the
## village is too unhappy).
func next_arrival_in() -> float:
	var now := TimeService.now()
	return Simulation.next_arrival_at(state, data(), now, happiness(), employment()) - now


## How many job seekers the next group brings (0 when nobody is coming).
func next_arrival_count() -> int:
	return Simulation.next_arrival_count(state, data(), TimeService.now(), happiness(), employment())


## Seconds until the next baby is born (INF when none is coming).
func next_birth_in() -> float:
	var now := TimeService.now()
	return Simulation.next_birth_at(state, data(), now) - now


## Adults (everyone who isn't a child: they work and have babies).
func adults() -> int:
	return Simulation.adults(state)


## The children's age groups, oldest first: [{"count", "grows_up_at"}]. Read it; don't change it.
func children_groups() -> Array:
	return Simulation.children_groups(state)


## Who came and went over (up to) the last `window` seconds:
## {"moved_in", "born", "grew_up", "died", "seconds"}.
func people_flow(window: float) -> Dictionary:
	return Simulation.people_flow(state, window, TimeService.now())


## Lifetime counters: {"moved_in", "born", "grew_up", "died"}. Read it; don't change it.
func people_stats() -> Dictionary:
	return Simulation.people_stats(state)


## Village happiness: {"score", "food", "jobs", "foods", "needs_count", "growth_speed" (births),
## "move_in_speed" (migrant workers), "homeless_penalty" (taken off for households in huts),
## "leave_per_hour", ...}
## (see Simulation.happiness).
func happiness() -> Dictionary:
	return _remember("happiness", func(): return Simulation.happiness(state, data(), TimeService.now(), housing(), employment()))


func warehouse_total() -> int:
	return Simulation.warehouse_total(state)


func warehouse_cap() -> int:
	return _remember("warehouse_cap", func(): return Simulation.warehouse_cap(state, data()))


## Whether type_id could be built on cell right now ({"ok", "error", and the quote's "cost",
## "seconds", "lines"}); changes nothing.
func can_build(type_id: String, cell: Vector2i) -> Dictionary:
	return Simulation.can_build(state, data(), type_id, cell, TimeService.now())


## The building standing on this tile (any tile of its footprint), or {}.
func building_at(cell: Vector2i) -> Dictionary:
	return Simulation.building_at(state, data(), cell)


## How many tiles wide and deep this kind of building stands (1 or 2).
func size_of(type_id: String) -> int:
	return Simulation.size_of(data(), type_id)


## The middle of a building of this kind standing at `cell`, in tiles (see Simulation.centre_at):
## Iso.to_world() of it is where its picture is centred.
func centre_at(type_id: String, cell: Vector2i) -> Vector2:
	return Simulation.centre_at(data(), type_id, cell)


## The tiles a building of this kind covers standing at `cell`.
func footprint(type_id: String, cell: Vector2i) -> Array[Vector2i]:
	return Simulation.footprint(data(), type_id, cell)


## The free spot for a building of this kind closest to `near` (the tile its whole footprint
## fits on, with no building or road), or `near` itself when there's none.
func free_spot_near(type_id: String, near: Vector2i) -> Vector2i:
	return Simulation.free_spot_near(state, data(), type_id, near)


## The building with this id, or {} if there is none. Read it; don't change it.
func building(building_id: String) -> Dictionary:
	return Simulation.find_building(state, building_id)


## Whether the building could be moved to cell ({"ok", "error"}); changes nothing.
func can_move(building_id: String, cell: Vector2i) -> Dictionary:
	return Simulation.can_move(state, data(), building_id, cell)


# --- Roads (plan.md §5.20) ---

## What road on these tiles would cost ({"ok", "error", "cost" (cents), "new_cells"}); changes nothing.
func road_quote(cells: Array) -> Dictionary:
	return Simulation.road_quote(state, data(), cells)


## Whether the road on these tiles could be removed ({"ok", "error", "cells"}); changes nothing.
func can_remove_roads(cells: Array) -> Dictionary:
	return Simulation.can_remove_roads(state, data(), cells)


## The price of one road tile, in cents.
func road_price() -> int:
	return Simulation.road_price(data())


## Every road tile: Vector2i -> cents paid for it.
func road_cells() -> Dictionary:
	return _remember("road_cells", func(): return Simulation.road_cells(state))


## The road tiles linked to City Hall: Vector2i -> true.
func linked_roads() -> Dictionary:
	return _remember("linked_roads", func(): return Simulation.linked_roads(state, data()))


func is_road(cell: Vector2i) -> bool:
	return Simulation.is_road(state, cell)


## True when this building has workers and so needs a road to City Hall.
func needs_road(building: Dictionary) -> bool:
	return Simulation.needs_road(data(), building)


## False when the building needs a road and has none (it gets no workers).
func on_road(building: Dictionary) -> bool:
	return Simulation.on_road(data(), building)


# --- Construction workers (plan.md §5.15) ---

## True for a Construction Office (its workers are the construction workers).
func is_crew_office(building: Dictionary) -> bool:
	return Simulation.is_crew_office(data(), building)


## Construction workers: {"total", "busy", "free", "jobs": [{"building_id", "crew", "until"}]
## soonest done first}.
func crew() -> Dictionary:
	var now := TimeService.now()
	return {"total": Simulation.crew_total(state, data(), now), "busy": Simulation.crew_busy(state, data(), now),
		"free": Simulation.crew_free(state, data(), now), "jobs": Simulation.crew_jobs(state, data(), now)}


## Construction workers needed to build (level 1) or upgrade to `level`.
func crew_needed(type_id: String, level := 1) -> int:
	return int(Simulation.construction_needs(data(), type_id, level).crew)



## What demolishing would give back ({"ok", "error", "materials", "goods"}: no money, all of it
## into the warehouse); changes nothing.
func can_demolish(building_id: String) -> Dictionary:
	return Simulation.can_demolish(state, data(), building_id)


## 0.0 to 1.0 progress of the building's whole batch.
func job_progress(building: Dictionary) -> float:
	return Simulation.job_progress(state, building, data(), TimeService.now())


## How fast the building works right now: 1.0 = full speed, less when short of workers.
func building_speed(building: Dictionary) -> float:
	return Simulation.building_speed(state, data(), building, TimeService.now())


## Share of the town's posts that are filled (0.0 to 1.0). Below 1 the town is short of people:
## some buildings have open posts.
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


## How many people are working there right now (0 while it's built, idle, suspended or without
## power), and how many it asks for at its staffing level. Cheaper than workers() for screens that
## count every building.
func workers_working(building: Dictionary) -> float:
	return Simulation.workers_working(state, data(), building, TimeService.now())


func workers_wanted(building: Dictionary) -> int:
	return Simulation.workers_wanted(data(), building)


## A number that changes whenever a road or building is added, removed or moved, so screens can
## redraw the map only then.
func layout_key() -> int:
	return _remember("layout_key", func():
		var parts: Array = [state.get("roads", [])]
		for b in state.buildings:
			parts.append([b.type, b.position])
		return hash(parts))


## False while the building is still under construction.
func is_built(building: Dictionary) -> bool:
	return Simulation.is_built(building, TimeService.now())


## 0.0 to 1.0 progress of construction or of an upgrade (1.0 = finished).
func construction_progress(building: Dictionary) -> float:
	return Simulation.construction_progress(building, data(), TimeService.now())


## Lifetime counters and graph history (see Simulation.stats). Read it; don't change it.
func stats() -> Dictionary:
	return Simulation.stats(state)


## Per-minute rates of what's being made and used right now (see Simulation.production_rates).
func production_rates() -> Dictionary:
	return Simulation.production_rates(state, data(), TimeService.now())


## {"population" (everyone), "adults", "children", "jobs", "employed", "unemployed" (adults
## without a job), "open_jobs"}
func employment() -> Dictionary:
	return _remember("employment", func(): return Simulation.employment(state, data(), TimeService.now()))


## Money in and out over (up to) the last `window` seconds: {"income", "spending", "seconds"}.
func cash_flow(window: float) -> Dictionary:
	return Simulation.cash_flow(state, window, TimeService.now())


## What the company owns and owes right now, in cents (see Simulation.balance_sheet).
func balance_sheet() -> Dictionary:
	return Simulation.balance_sheet(state, data(), TimeService.now())


## Starting cash + money in − money out (+ dev tools) vs the cash now (see Simulation.cash_check).
func cash_check() -> Dictionary:
	return Simulation.cash_check(state)


## Money in and out per 30-minute block, newest first (see Simulation.money_log).
func money_log() -> Array:
	return Simulation.money_log(state, TimeService.now())


## Seconds until construction ends (0 when finished).
func construction_left(building: Dictionary) -> float:
	return maxf(Simulation.built_at(building) - TimeService.now(), 0.0)


func _after(result: Dictionary) -> Dictionary:
	_memo.clear()  # a refused action may still have settled first
	_hiring = {}
	if result.ok:
		_dirty = true
		changed.emit()
	return result
