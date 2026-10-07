extends Node
## Plays the game's sound effects (plan.md §5.23). Which file each sound uses, its bus, loudness and
## variation are in data/sounds.json; the files are in assets/audio/sfx/ (made by
## tools/sfx/sound_studio.html). Presentation only: it never reads or changes the game state.
## Call Sfx.play("collect") from a screen. Every button also clicks by itself (_on_node_added).

const FOLDER := "res://assets/audio/sfx/"
## How many sounds can play at once; when all are busy, the one that started first is cut short.
const VOICES := 8

var _defs := {}  # sound id -> its entry in data/sounds.json
var _streams := {}  # sound id -> AudioStream
var _last_played := {}  # sound id -> milliseconds since the game started
var _players: Array[AudioStreamPlayer] = []
var _next := 0  # the player to use when all are busy


func _ready() -> void:
	_defs = GameData.sounds.get("sounds", {})
	var missing := 0
	for id in _defs:
		var path: String = FOLDER + str(_defs[id].get("file", ""))
		# A sound Godot hasn't imported yet (new file, editor not opened since) is just skipped.
		if ResourceLoader.exists(path):
			_streams[id] = load(path)
		else:
			missing += 1
	if missing > 0:
		push_warning("Sfx: %d sounds aren't imported yet (open the project in the Godot editor once)" % missing)
	for _i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	get_tree().node_added.connect(_on_node_added)


## Plays a sound from data/sounds.json. Unknown ids and too-quick repeats are ignored.
func play(id: String) -> void:
	if not _streams.has(id):
		return
	var def: Dictionary = _defs[id]
	var now := Time.get_ticks_msec()
	if _last_played.has(id) and now - int(_last_played[id]) < float(def.get("min_gap", 0.0)) * 1000.0:
		return
	_last_played[id] = now
	var player := _free_player()
	var jitter := float(def.get("pitch_jitter", 0.0))
	player.stream = _streams[id]
	player.bus = str(def.get("bus", "UI"))
	player.volume_db = float(def.get("volume_db", 0.0))
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	player.play()


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	var oldest := _players[_next]  # all busy: take turns cutting one short
	_next = (_next + 1) % _players.size()
	return oldest


## Every button in the game clicks when pressed: choice buttons (chips), check boxes and switches
## with "toggle", the rest with "tap". Runs once per new node, never every frame.
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("sfx_click"):  # a button moved elsewhere comes back here
		node.set_meta("sfx_click", true)
		var button := node as BaseButton
		button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: BaseButton) -> void:
	var choice := button.toggle_mode or button is CheckBox or button is CheckButton \
			or String(button.theme_type_variation) in ["ChipButton", "ChipOnButton"]
	play("toggle" if choice else "tap")
