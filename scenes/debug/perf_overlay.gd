extends Control
## Performance overlay (plan.md §9.1): how fast the game runs right now, to check on a PC or on a
## test phone. Only in test builds (main.gd loads it inside OS.is_debug_build()). Opens with F11,
## or the Developer window's Performance button.
## Shows pictures drawn per second ("fps") and the limit frame_rate.gd sets (30 after 10 seconds
## without touching is the battery saver, not slowness), how long the last picture took to work
## out, draw calls (separate jobs for the graphics chip), nodes, and how long the last tick took:
## the rules (Economy settling time) and the screens refreshing, with the slowest since opening.
## The switches hide parts of the map: the fps won back by hiding something is what it costs to
## draw (on a phone, the island's water shader is the main suspect).

const Traffic = preload("res://scenes/village/traffic.gd")
const UPDATE_SECONDS := 0.5

## The Village View (set by main.gd), whose layers the switches hide.
var village: Node2D

var _text: Label
var _slowest := {"rules": 0, "screens": 0}  # slowest tick since the overlay opened (microseconds)
var _hidden := {}  # part name -> true while a switch hides it


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.theme_type_variation = "HudPill"
	panel.position = Vector2(14, 14)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_text = UITheme.label("", "SmallLabel")
	column.add_child(_text)
	var switches := HFlowContainer.new()
	switches.custom_minimum_size.x = 330
	column.add_child(switches)
	for part in ["Island", "Trees", "Shadows", "Roads", "Traffic"]:
		var button := UITheme.button(part, "ChipOnButton", "small")
		button.tooltip_text = "Hide or show it, to see what it costs to draw"
		button.pressed.connect(_toggle_part.bind(part, button))
		switches.add_child(button)
	var timer := Timer.new()
	timer.wait_time = UPDATE_SECONDS
	timer.timeout.connect(_update)
	add_child(timer)
	timer.start()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	_slowest = {"rules": 0, "screens": 0}
	_update()


func _update() -> void:
	if _hidden.has("Traffic"):
		_show_traffic(false)  # new people and cars keep appearing
	if not visible:
		return
	var tick: Dictionary = Economy.last_tick_usec
	for key in _slowest:
		_slowest[key] = maxi(int(_slowest[key]), int(tick.get(key, 0)))
	var cap := Engine.max_fps
	_text.text = "\n".join([
		"%d fps (limit %s) · frame %.1f ms" % [Engine.get_frames_per_second(), str(cap) if cap > 0 else "none",
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0],
		"Draw calls %d · nodes %s" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			UITheme.number(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))],
		"Tick: rules %.1f ms · screens %.1f ms" % [int(tick.get("rules", 0)) / 1000.0, int(tick.get("screens", 0)) / 1000.0],
		"Slowest tick: rules %.1f ms · screens %.1f ms" % [int(_slowest.rules) / 1000.0, int(_slowest.screens) / 1000.0],
		"Video memory %d MB" % roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"Limit 30 after 10 s untouched = battery saver",
	])


func _toggle_part(part: String, button: Button) -> void:
	var show_it := _hidden.has(part)
	if show_it:
		_hidden.erase(part)
	else:
		_hidden[part] = true
	button.theme_type_variation = "ChipOnButton" if show_it else "ChipButton"
	if village == null:
		return
	match part:
		"Island":
			village.get_node("IslandMap").visible = show_it
		"Trees":
			for tree in get_tree().get_nodes_in_group("placeholder_trees"):
				tree.visible = show_it
		"Shadows":
			village.get_node("Shadows").visible = show_it
		"Roads":
			village.get_node("Roads").visible = show_it
		"Traffic":
			_show_traffic(show_it)


func _show_traffic(show_it: bool) -> void:
	if village == null:
		return
	for child in village.get_node("Objects").get_children():
		if child is Traffic.Agent:
			child.visible = show_it
