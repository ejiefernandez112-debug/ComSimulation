extends Node
## Sounds for things that happen by themselves while playing (plan.md §5.24): a building finishing
## construction or an upgrade, buildings losing power for lack of electricity, cash dropping below
## zero, the sales tax rate changing. Sounds for the player's own actions are played in main.gd.
## Watches Economy.changed and plays a sound when one of these turns from "no" to "yes". What
## happened while the game was closed stays quiet: the first look only takes notes.

## The tax rate walks a whole day of sales, so it's looked at only every this many updates.
const TAX_EVERY := 15

var _working := {}  # building id -> "build" or "upgrade" while construction work is going on
var _short := false  # some building has no power because there isn't enough electricity
var _broke := false  # cash is below zero
var _tax_rate := -1.0  # -1 = not looked at yet
var _updates := 0
var _started := false


func _ready() -> void:
	Economy.changed.connect(_on_changed)


## A new game: what was being built before is no longer news (call before starting it).
func forget() -> void:
	_working.clear()
	_started = false
	_tax_rate = -1.0


func _on_changed() -> void:
	var working := {}
	var present := {}
	var short := false
	for b in Economy.state.get("buildings", []):
		present[b.id] = true
		if not Economy.is_built(b):
			working[b.id] = "build"
		elif Economy.is_upgrading(b):
			working[b.id] = "upgrade"
		if Economy.power_problem(b) == "short":
			short = true
	var broke := Economy.currency() < 0
	if _started:
		var built := false
		var upgraded := false
		for id in _working:
			if present.has(id) and not working.has(id):  # finished (not demolished)
				built = built or _working[id] == "build"
				upgraded = upgraded or _working[id] == "upgrade"
		if built:
			Sfx.play("complete")
		if upgraded:
			Sfx.play("upgrade_done")
		if (short and not _short) or (broke and not _broke):
			Sfx.play("critical")
	_working = working
	_short = short
	_broke = broke
	if _updates % TAX_EVERY == 0:
		var rate := float(Economy.tax_bracket().rate)
		if _tax_rate >= 0.0 and not is_equal_approx(rate, _tax_rate):
			Sfx.play("tax_change")
		_tax_rate = rate
	_updates += 1
	_started = true
