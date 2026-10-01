extends Control
## TEMPORARY test screen (step 2): plain buttons to play the Phase 1a loop before the real
## Village View exists. It only calls Economy and displays results, like the real UI will.

var _status: Label
var _readout: Label


func _ready() -> void:
	var root := VBoxContainer.new()
	root.position = Vector2(24, 24)
	add_child(root)

	var buttons := HFlowContainer.new()
	buttons.custom_minimum_size.x = 1200
	root.add_child(buttons)
	for type_id in ["wheat_farm", "flour_mill", "bakery"]:
		_add_button(buttons, "Build %s" % GameData.buildings[type_id].name, _build.bind(type_id))
	_add_button(buttons, "Queue Flour job", _queue_all.bind("flour_mill", "mill_flour"))
	_add_button(buttons, "Queue Bread job", _queue_all.bind("bakery", "bake_bread"))
	_add_button(buttons, "Collect all", _collect_all)
	_add_button(buttons, "Sell all Bread", _sell_all.bind("bread"))
	_add_button(buttons, "Sell 50 Wheat", _sell.bind("wheat", 50))
	_add_button(buttons, "Skip 10 min (test)", _warp.bind(600))

	_status = Label.new()
	_status.modulate = Color(1, 0.85, 0.4)
	root.add_child(_status)
	_readout = Label.new()
	root.add_child(_readout)

	Economy.changed.connect(_refresh)
	_refresh()


func _add_button(parent: Node, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)


func _show(result: Dictionary, success_text: String) -> void:
	_status.text = success_text if result.ok else result.error


func _build(type_id: String) -> void:
	# Real placement comes in step 5; for now take the first free cell.
	var grid: Array = Economy.state.plot.grid_size
	for y in int(grid[1]):
		for x in int(grid[0]):
			if Economy.building_at(Vector2i(x, y)).is_empty():
				_show(Economy.build(type_id, Vector2i(x, y)), "Built %s." % GameData.buildings[type_id].name)
				return


func _queue_all(type_id: String, recipe_id: String) -> void:
	for b in Economy.state.buildings:
		if b.type == type_id:
			_show(Economy.enqueue(b.id, recipe_id), "Job queued.")
			return
	_status.text = "Build a %s first." % GameData.buildings[type_id].name


func _collect_all() -> void:
	var total := 0
	for b in Economy.state.buildings:
		var result := Economy.collect(b.id)
		if result.ok:
			for res in result.moved:
				total += int(result.moved[res])
	_status.text = "Collected %d items." % total


func _sell(resource_id: String, qty: int) -> void:
	var result := Economy.sell(resource_id, qty)
	_show(result, "Earned %d." % result.get("earned", 0))


func _sell_all(resource_id: String) -> void:
	_sell(resource_id, int(Economy.state.inventory.get(resource_id, 0)))


func _warp(seconds: float) -> void:
	TimeService.warp(seconds)
	var report := Economy.tick()
	_status.text = "Skipped ahead. Produced while away: %s" % str(report)


func _refresh() -> void:
	var lines: Array[String] = [
		"Cash: %d" % Economy.currency(),
		"Population: %d / %d" % [Economy.population(), Economy.population_capacity()],
		"Warehouse (%d / %d): %s" % [Economy.warehouse_total(), Economy.warehouse_cap(), str(Economy.state.inventory)],
		"",
	]
	for b in Economy.state.buildings:
		var def: Dictionary = GameData.buildings[b.type]
		var line := "%s  storage %s" % [def.name, str(b.storage)]
		if def.category == "extractor" or not b.queue.is_empty():
			line += "  progress %d%%" % int(Economy.job_progress(b) * 100)
		if def.category == "processor":
			line += "  queue %d/%d" % [b.queue.size(), int(def.queue_size)]
		if b.blocked:
			line += "  (storage full - collect!)"
		lines.append(line)
	_readout.text = "\n".join(lines)
