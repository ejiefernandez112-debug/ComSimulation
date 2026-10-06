extends Control
## The card that pops up at the bottom of the screen when a building is tapped: the building's
## picture, its name and what it's doing, a progress bar, and a row of action tiles. Info opens the
## building window; Collect acts straight away; Produce (an idle Farm, Mill or Bakery) opens the
## window to set up a batch; City Hall offers Build; Move starts moving the building.
## The buttons only ask (signals); main.gd does the action through Economy.

signal info_requested(building_id: String)
signal collect_requested(building_id: String)
signal build_requested
signal move_requested(building_id: String)

const BuildingView = preload("res://scenes/village/building_view.gd")
const MIN_WIDTH := 380.0

var building_id := ""

var _card: PanelContainer
var _picture: TextureRect
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
	_card = PanelContainer.new()
	_card.custom_minimum_size.x = MIN_WIDTH
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_card.add_child(column)
	# Top: the building's picture in a sunken square, then its name and what it's doing.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	var frame := PanelContainer.new()
	frame.theme_type_variation = "Inset"
	top.add_child(frame)
	_picture = UITheme.icon_rect("build", 40)
	frame.add_child(_picture)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(words)
	_title = UITheme.label("", "HeadingLabel")
	words.add_child(_title)
	_status = UITheme.label("", "SmallLabel")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = MIN_WIDTH - 100.0
	words.add_child(_status)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 6)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_progress)
	# The action tiles.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_info = RoundButton.make("Button", "info", "Info")
	_collect = RoundButton.make("GoButton", "item", "Collect")
	_produce = RoundButton.make("GoButton", "item", "Produce")
	_build = RoundButton.make("Button", "build", "Build")
	_move = RoundButton.make("Button", "move", "Move")
	for b in [_info, _collect, _produce, _build, _move]:
		row.add_child(b)
	_info.pressed.connect(func(): info_requested.emit(building_id))
	_collect.pressed.connect(func(): collect_requested.emit(building_id))
	_produce.pressed.connect(func(): info_requested.emit(building_id))  # the batch is set up there
	_build.pressed.connect(build_requested.emit)
	_move.pressed.connect(func(): move_requested.emit(building_id))
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 12)
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hide()
	Economy.changed.connect(_refresh)


## Shows the card for a building, rising in from below.
func show_for(id: String) -> void:
	building_id = id
	var art := BuildingView.picture(Economy.building(id).get("type", ""))
	_picture.texture = art.texture if not art.is_empty() else UITheme.icon("build")
	_refresh()
	show()
	UITheme.pop_in(_card)
	_card.pivot_offset = Vector2(_card.size.x / 2.0, _card.size.y)  # grows up from the bottom edge


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
	UITheme.set_font_color(_status, UITheme.TEXT_DIM if status.good else UITheme.WARN)
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
		var r := BuildingInfo.recipe_of(b)
		_produce.set_icon(BuildingInfo.output_of(r))
		_produce.set_caption("New batch")
		_produce.set_style("GoButton" if Economy.batch_max_hours(building_id, r.id, Economy.workers(b).bonus) > 0 else "BackButton")

	_build.visible = def.category == "civic"
