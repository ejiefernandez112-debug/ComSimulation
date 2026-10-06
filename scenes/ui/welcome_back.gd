extends ModalWindow
## "Welcome back!" (plan.md §6, Offline Summary): shown once at start-up after the game was closed
## for a while. Lists what the buildings made, who was born, grew up or died, the wages paid and what needs
## attention. It only shows Economy's numbers; the catch-up itself happened in the game rules.


func _init() -> void:
	docked = false  # a greeting: in the middle of the screen, not docked at the side


## Opens the window if the player was away long enough (welcome_back_after_seconds in
## game_config.json). Returns whether it opened.
func show_if_away() -> bool:
	var away := Economy.offline_seconds
	if away < float(GameData.config.get("welcome_back_after_seconds", 120)):
		return false
	var report := Economy.offline_report
	clear_content()
	_text("You were away for %s. Your company kept working:" % UITheme.duration(away))

	var made := {}
	for res in report:
		if GameData.resources.has(res) and int(report[res]) > 0:
			made[res] = int(report[res])
	if made.is_empty():
		_text("Nothing was made: no building was working.")
	else:
		var row := _row("Made")
		for res in made:
			row.add_child(_amount(res, "+" + UITheme.number(made[res])))
	var sold := Economy.sold_in(report)  # Supermarket shelves that sold out
	if not sold.is_empty():
		var row := _row("Sold")
		for res in sold:
			row.add_child(_amount(res, UITheme.number(int(sold[res]))))
		row.add_child(_amount("cash", "+" + UITheme.money(int(report.get("store_sales", 0)))))
	if int(report.get("population", 0)) > 0:
		_row("Moved in").add_child(_amount("population", "+%d people" % int(report.population)))
	if int(report.get("born", 0)) > 0:
		_row("Born").add_child(_amount("population", "+%d babies" % int(report.born)))
	if int(report.get("grew_up", 0)) > 0:
		_row("Grew up").add_child(_amount("population", "%d children became adults" % int(report.grew_up)))
	if int(report.get("died", 0)) > 0:
		_row("Died").add_child(_amount("population", "-%d people" % int(report.died)))
	if int(report.get("moved_away", 0)) > 0:
		_row("Left the island").add_child(_amount("population", "-%d people" % int(report.moved_away)))
	if roundi(int(report.get("wages", 0)) / 100.0) > 0:  # at least $1 (money is in cents)
		_row("Wages paid").add_child(_amount("cash", "-" + UITheme.money(int(report.wages))))
	if roundi(int(report.get("rent", 0)) / 100.0) > 0:
		_row("Rent collected").add_child(_amount("cash", "+" + UITheme.money(int(report.rent))))
	if roundi(int(report.get("water", 0)) / 100.0) > 0:
		_row("Water bills").add_child(_amount("water", "-" + UITheme.money(int(report.water))))
	if roundi(int(report.get("power", 0)) / 100.0) > 0:
		_row("Power bills").add_child(_amount("power", "-" + UITheme.money(int(report.power))))
	_row("Cash now").add_child(_amount("cash", UITheme.money(Economy.currency())))

	var counts: Dictionary = Economy.production_rates().buildings
	var done := int(counts.get("done", 0))
	if done > 0:
		_text("%d batch%s finished. Collect the goods and start a new one." % [done, "" if done == 1 else "es"], true)
	var idle := int(counts.get("idle", 0))
	if idle > 0:
		_text("%d building%s idle. Start a batch to put the workers back to work." % [idle, " is" if idle == 1 else "s are"], true)
	if Economy.currency() < 0:
		_text("You are in debt: sell goods to pay it back before building again.", true)

	var go := UITheme.button("Continue", "GoButton", "big")
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(close)
	content.add_child(go)
	open("Welcome back!")
	return true


func _text(message: String, warning := false) -> void:
	var label := UITheme.wrapped(message, WIDTH - 70)
	if warning:
		label.add_theme_color_override("font_color", UITheme.BAD)
	content.add_child(label)


## A boxed row "Heading:  [icon] amount  [icon] amount"; returns the row to add amounts to.
func _row(heading_text: String) -> HBoxContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	content.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var heading := UITheme.label(heading_text, "HeadingLabel")
	heading.custom_minimum_size.x = 130
	row.add_child(heading)
	return row


## [icon] text
func _amount(icon_name: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(UITheme.icon_rect(icon_name, 32))
	row.add_child(UITheme.label(text, "HeadingLabel"))
	return row
