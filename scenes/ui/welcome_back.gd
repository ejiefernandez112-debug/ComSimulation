extends ModalWindow
## "Welcome back!" (plan.md §6, Offline Summary): shown once at start-up after the game was closed
## for a while. Lists what the buildings made, who moved in, the wages paid and what needs
## attention. It only shows Economy's numbers; the catch-up itself happened in the game rules.


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
	if int(report.get("population", 0)) > 0:
		_row("Moved in").add_child(_amount("population", "+%d people" % int(report.population)))
	if roundi(int(report.get("wages", 0)) / 100.0) > 0:  # at least $1 (money is in cents)
		_row("Wages paid").add_child(_amount("cash", "-" + UITheme.money(int(report.wages))))
	if roundi(int(report.get("water", 0)) / 100.0) > 0:
		_row("Water paid").add_child(_amount("water", "-" + UITheme.money(int(report.water))))
	_row("Cash now").add_child(_amount("cash", UITheme.money(Economy.currency())))

	var counts: Dictionary = Economy.production_rates().buildings
	var full := int(counts.get("full", 0))
	if full > 0:
		_text("%d building%s full and stopped. Collect to restart." % [full, " is" if full == 1 else "s are"], true)
	var idle := int(counts.get("idle", 0))
	if idle > 0:
		_text("%d building%s out of jobs. Queue more to put the workers back to work." % [idle, " is" if idle == 1 else "s are"], true)
	if Economy.currency() < 0:
		_text("You are in debt: sell goods to pay it back before building again.", true)

	var go := Button.new()
	go.theme_type_variation = "GreenButton"
	go.text = "Continue"
	go.custom_minimum_size = Vector2(220, 58)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(close)
	content.add_child(go)
	open("Welcome back!")
	return true


func _text(message: String, warning := false) -> void:
	var label := Label.new()
	label.theme_type_variation = "BodyLabel"
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 70  # wrapped text needs a width
	if warning:
		label.add_theme_color_override("font_color", UITheme.BAD.darkened(0.25))
	content.add_child(label)


## A boxed row "Heading:  [icon] amount  [icon] amount"; returns the row to add amounts to.
func _row(heading_text: String) -> HBoxContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	content.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var heading := Label.new()
	heading.text = heading_text
	heading.custom_minimum_size.x = 130
	heading.add_theme_font_size_override("font_size", 19)
	row.add_child(heading)
	return row


## [icon] text
func _amount(icon_name: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = UITheme.icon(icon_name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	return row
