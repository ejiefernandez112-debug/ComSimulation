extends Control
## The bar that pops up at the bottom of the screen when a building is tapped, Clash-of-Clans
## style: the building's name and what it's doing, plus round action buttons. Info opens the
## building panel; Collect acts straight away; Produce (an idle Farm, Mill or Bakery) opens the
## panel to set up a batch; City Hall offers Build; Move starts moving the building.
## The buttons only ask (signals); main.gd does the action through Economy.

signal info_requested(building_id: String)
signal collect_requested(building_id: String)
signal build_requested
signal move_requested(building_id: String)

var building_id := ""

var _box: VBoxContainer
var _title: Label
var _status: Label
var _progress: ProgressBar
var _info: RoundButton
var _collect: RoundButton
var _produce: RoundButton
var _build: RoundButton
var _move: RoundButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_END
	_box.add_theme_constant_override("separation", 4)
	_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_title = _label(28)
	_status = _label(18)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(260, 12)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_progress)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(row)
	_info = RoundButton.make("blue", "info", "Info")
	_collect = RoundButton.make("green", "item", "Collect")
	_produce = RoundButton.make("yellow", "item", "Produce")
	_build = RoundButton.make("yellow", "build", "Build")
	_move = RoundButton.make("blue", "move", "Move")
	for b in [_info, _collect, _produce, _build, _move]:
		row.add_child(b)
	_info.pressed.connect(func(): info_requested.emit(building_id))
	_collect.pressed.connect(func(): collect_requested.emit(building_id))
	_produce.pressed.connect(func(): info_requested.emit(building_id))  # the batch is set up there
	_build.pressed.connect(build_requested.emit)
	_move.pressed.connect(func(): move_requested.emit(building_id))
	hide()
	Economy.changed.connect(_refresh)


## Shows the bar for a building, popping in from below.
func show_for(id: String) -> void:
	building_id = id
	_refresh()
	show()
	_box.pivot_offset = Vector2(_box.size.x / 2.0, _box.size.y)
	_box.scale = Vector2(0.85, 0.85)
	_box.modulate.a = 0.0
	var pop := create_tween().set_parallel()
	pop.tween_property(_box, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_box, "modulate:a", 1.0, 0.12)


func close() -> void:
	building_id = ""
	hide()


func _refresh() -> void:
	if building_id == "":
		return
	var b := Economy.building(building_id)
	if b.is_empty():
		close()
		return
	var def: Dictionary = GameData.buildings[b.type]
	_title.text = "%s (Level %d)" % [def.name, Economy.building_level(b)]
	var status := BuildingInfo.status(b)
	_status.text = status.text
	_status.add_theme_color_override("font_color", UITheme.TEXT if status.good else Color("ffd166"))
	_progress.visible = status.progress >= 0.0
	_progress.value = status.progress * 100.0

	var waiting := Economy.waiting_goods(b)
	_collect.visible = not waiting.is_empty()
	if _collect.visible:
		_collect.set_icon(waiting.keys()[0])
		_collect.set_caption("Collect %s" % UITheme.number(BuildingInfo.stored(b)))

	# Produce opens the building window, where the batch's length and bonus are chosen.
	_produce.visible = Economy.makes_batches(b) and not Economy.has_batch(b)
	if _produce.visible:
		var r := BuildingInfo.recipe(b.type)
		_produce.set_icon(BuildingInfo.output_of(r))
		_produce.set_caption("New batch")
		_produce.set_color("yellow" if Economy.batch_max_hours(building_id, r.id, Economy.workers(b).bonus) > 0 else "grey")

	_build.visible = def.category == "civic"


func _label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	_box.add_child(label)
	return label
