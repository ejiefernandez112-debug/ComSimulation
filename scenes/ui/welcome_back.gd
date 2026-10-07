extends ModalWindow
## "Welcome back!" (plan.md §6, Offline Summary): shown once at start-up after the game was closed
## for a while. Lists what the buildings made and sold, people who left, the wages paid and a debt
## warning. It only shows Economy's numbers; the catch-up itself happened in the game rules.


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
	_text("You were away for %s." % UITheme.duration(away))

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
	if int(report.get("moved_away", 0)) > 0:
		_row("Left the island").add_child(_amount("population", "-%d people" % int(report.moved_away)))
	if roundi(int(report.get("wages", 0)) / 100.0) > 0:  # at least $1 (money is in cents)
		_row("Wages paid").add_child(_amount("cash", "-" + UITheme.money(int(report.wages))))
	if Economy.currency() < 0:
		_text("You are in debt: sell goods to pay it back before building again.", true)

	var go := UITheme.button("Continue", "GoButton", "big")
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(close)
	content.add_child(go)
	open("Welcome back!")
	return true


func _text(message: String, warning := false) -> void:
	var label := UITheme.wrapped(message, UITheme.WINDOW_WIDTH - 70)
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
