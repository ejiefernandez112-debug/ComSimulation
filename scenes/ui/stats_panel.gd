extends ModalWindow
## The Statistics window (Stats card in the bottom menu), in four tabs:
## - Production: what's being made and used per minute right now, and all-time totals
## - People: population, employed / unemployed, open jobs, jobs per building type
## - Cash flow: money in and out over the last hour and all time, by source
## - Graphs: cash, cash flow, people and production over time (15 min / 1 h / 6 h)
## Every number comes from Economy (the rules in scripts/sim/); this window only shows them.

const TABS := [["production", "Production"], ["people", "People"], ["cash", "Cash flow"], ["graphs", "Graphs"]]
const GRAPHS := [["cash", "Cash"], ["flow", "Cash flow"], ["people", "People"], ["production", "Production"]]
const RANGES := [[900.0, "15 min"], [3600.0, "1 hour"], [21600.0, "6 hours"]]
const UP := Color("2f7a1f")  # money in / surplus, readable on the cream panel
const DOWN := Color("b63a2b")  # money out / shortfall
const AVERAGE_OVER := 600.0  # rate graphs (cash flow, production) show 10-minute averages

var _tab := "production"
var _graph := "cash"
var _range := 3600.0
var _pages := {}  # tab id -> its page
var _tab_buttons := {}
var _graph_buttons := {}
var _range_buttons := {}
var _values := {}  # name -> Label whose text _refresh updates
var _population_bar: ProgressBar
var _employed_bar: ProgressBar
var _chart: LineChart


func _ready() -> void:
	super()
	var tabs := _button_row(content, TABS, _tab_buttons, _select_tab)
	tabs.add_theme_constant_override("separation", 6)
	_pages.production = _production_page()
	_pages.people = _people_page()
	_pages.cash = _cash_page()
	_pages.graphs = _graphs_page()
	Economy.changed.connect(_refresh)


func show_stats() -> void:
	_select_tab(_tab)
	open("Statistics")
	_refresh()


func _select_tab(id: String) -> void:
	_tab = id
	for key in _pages:
		_pages[key].visible = key == id
	_highlight(_tab_buttons, id)
	_refresh()
	_layout.call_deferred()  # the window resizes to the new page


# --- Pages ---------------------------------------------------------------------

func _production_page() -> VBoxContainer:
	var page := _page()
	var now_box := _section(page, "Right now, per minute")
	var grid := _grid(now_box, ["", "Made", "Used", "Net"])
	for res in GameData.resources:
		_item_cell(grid, res)
		for column in ["made", "used", "net"]:
			grid.add_child(_value("rate_%s_%s" % [column, res], true))
	now_box.add_child(_value("buildings"))
	var all_box := _section(page, "All time")
	grid = _grid(all_box, ["", "Made", "Sold", "Earned"])
	for res in GameData.resources:
		_item_cell(grid, res)
		for column in ["made", "sold", "earned"]:
			grid.add_child(_value("life_%s_%s" % [column, res], true))
	return page


func _people_page() -> VBoxContainer:
	var page := _page()
	var town := _section(page, "Population")
	town.add_child(_value("population"))
	_population_bar = _bar(town, "BlueBar")
	var work := _section(page, "Work")
	for row in [["employed", "Employed"], ["unemployed", "Unemployed"], ["open_jobs", "Open jobs"], ["jobs", "Jobs in total"]]:
		_value_row(work, row[1], row[0])
	_employed_bar = _bar(work, "GoldBar")
	work.add_child(_value("employed_share"))
	work.add_child(_value("work_speed"))
	var by_type := _section(page, "Jobs by building")
	for type_id in GameData.buildings:
		if int(GameData.buildings[type_id].get("workers", 0)) > 0:
			_value_row(by_type, GameData.buildings[type_id].name, "jobs_" + type_id)
	var note := _body("When there are more jobs than people, every building that needs workers runs slower. Build houses so more people move in.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = WIDTH - 70
	note.modulate.a = 0.8
	page.add_child(note)
	return page


func _cash_page() -> VBoxContainer:
	var page := _page()
	var now_box := _section(page, "Cash")
	now_box.add_child(_value("cash"))
	_values.cash.add_theme_font_size_override("font_size", 26)
	var recent := _section(page, "Last hour")
	_values["flow_title"] = recent.get_child(0).get_child(0)  # the section heading names the real time span
	_value_row(recent, "Money in", "flow_in")
	_value_row(recent, "Money out", "flow_out")
	_value_row(recent, "Net", "flow_net")
	var money_in := _section(page, "All time: money in")
	for res in GameData.resources:
		_value_row(money_in, "Sales of %s" % GameData.resources[res].name, "in_sales_" + res)
	_value_row(money_in, "Demolish refunds", "in_demolish")
	_value_row(money_in, "Total", "in_total")
	var money_out := _section(page, "All time: money out")
	_value_row(money_out, "Construction", "out_construction")
	_value_row(money_out, "Total", "out_total")
	return page


func _graphs_page() -> VBoxContainer:
	var page := _page()
	_button_row(page, GRAPHS, _graph_buttons, func(id):
		_graph = id
		_highlight(_graph_buttons, id)
		_refresh())
	var ranges := []
	for r in RANGES:
		ranges.append([str(r[0]), r[1]])
	_button_row(page, ranges, _range_buttons, func(id):
		_range = float(id)
		_highlight(_range_buttons, id)
		_refresh())
	_highlight(_graph_buttons, _graph)
	_highlight(_range_buttons, str(_range))
	_chart = LineChart.new()
	_chart.custom_minimum_size = Vector2(WIDTH - 50, 270)
	_chart.empty_text = "Not enough data yet: a point is added every minute."
	page.add_child(_chart)
	var hint := _body("Point at (or drag across) the graph to see the values at that time. Per-minute rates are 10-minute averages.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = WIDTH - 70
	hint.add_theme_font_size_override("font_size", 15)
	hint.modulate.a = 0.8
	page.add_child(hint)
	return page


# --- Refreshing the numbers ----------------------------------------------------

func _refresh() -> void:
	if not visible:
		return
	match _tab:
		"production":
			_refresh_production()
		"people":
			_refresh_people()
		"cash":
			_refresh_cash()
		"graphs":
			_refresh_graph()


func _refresh_production() -> void:
	var rates := Economy.production_rates()
	var st := Economy.stats()
	for res in GameData.resources:
		var made := float(rates.made.get(res, 0.0))
		var used := float(rates.used.get(res, 0.0))
		_show("rate_made_" + res, _rate(made))
		_show("rate_used_" + res, _rate(used))
		_show("rate_net_" + res, ("+" if made - used > 0.05 else "") + _rate(made - used), _signed_color(made - used))
		_show("life_made_" + res, UITheme.number(int(st.made.get(res, 0))))
		_show("life_sold_" + res, UITheme.number(int(st.sold.get(res, 0))))
		_show("life_earned_" + res, UITheme.number(int(st.sales_by_item.get(res, 0))))
	var b: Dictionary = rates.buildings
	_show("buildings", "Buildings: %d working · %d idle · %d storage full · %d being built" % [b.working, b.idle, b.full, b.building])


func _refresh_people() -> void:
	var e := Economy.employment()
	var cap := Economy.population_capacity()
	_show("population", "%d people · room for %d" % [e.population, cap])
	_population_bar.value = 100.0 * e.population / maxf(cap, 1)
	_show("employed", str(e.employed))
	_show("unemployed", str(e.unemployed), DOWN if e.unemployed > 0 else LineChart.INK)
	_show("open_jobs", str(e.open_jobs))
	_show("jobs", str(e.jobs))
	_employed_bar.value = 100.0 * e.employed / maxf(e.population, 1)
	_show("employed_share", "%d%% of people have a job" % roundi(100.0 * e.employed / maxf(e.population, 1)))
	var speed := Economy.staffing()
	if speed >= 1.0:
		_show("work_speed", "Buildings work at full speed")
	else:
		_show("work_speed", "Buildings work at %d%% speed: %d more worker%s needed" % [floori(speed * 100.0), e.open_jobs, "" if e.open_jobs == 1 else "s"], DOWN)
	var counts := {}
	for building in Economy.state.buildings:
		if Economy.is_built(building):
			counts[building.type] = int(counts.get(building.type, 0)) + 1
	for type_id in GameData.buildings:
		if _values.has("jobs_" + type_id):
			var n := int(counts.get(type_id, 0))
			_show("jobs_" + type_id, "%d built · %d jobs" % [n, n * int(GameData.buildings[type_id].workers)])


func _refresh_cash() -> void:
	var st := Economy.stats()
	_show("cash", UITheme.number(Economy.currency()))
	var flow := Economy.cash_flow(3600.0)
	var span := float(flow.seconds)
	_values.flow_title.text = "Last hour" if span >= 3540.0 else ("Last %s" % LineChart._ago(span) if span >= 60.0 else "Last hour (collecting data…)")
	_show("flow_in", ("+" if flow.income > 0 else "") + UITheme.number(flow.income), UP if flow.income > 0 else LineChart.INK)
	_show("flow_out", ("-" if flow.spending > 0 else "") + UITheme.number(flow.spending), DOWN if flow.spending > 0 else LineChart.INK)
	var net: int = flow.income - flow.spending
	_show("flow_net", ("+" if net > 0 else "") + UITheme.number(net), _signed_color(net))
	var total_in := 0
	for res in GameData.resources:
		var earned := int(st.sales_by_item.get(res, 0))
		total_in += earned
		_show("in_sales_" + res, UITheme.number(earned))
	_show("in_demolish", UITheme.number(int(st.income.demolish)))
	_show("in_total", UITheme.number(total_in + int(st.income.demolish)), UP)
	_show("out_construction", UITheme.number(int(st.spending.construction)))
	_show("out_total", UITheme.number(int(st.spending.construction)), DOWN)


## Builds the chosen graph's lines from the history points (one every minute), plus a point for
## right now so the lines always reach "now" and include what just happened.
func _refresh_graph() -> void:
	var st := Economy.stats()
	var now := TimeService.now()
	var history: Array = st.history.duplicate()
	if history.is_empty() or now - float(history[-1].t) > 1.0:
		var e := Economy.employment()
		history.append({"t": now, "cash": Economy.currency(), "income": _sum(st.income), "spending": _sum(st.spending),
			"population": e.population, "employed": e.employed, "jobs": e.jobs, "made": st.made})
	var lines: Array = []
	match _graph:
		"cash":
			lines.append({"name": "Cash", "color": 0, "points": _points(history, now, func(p): return float(p.cash))})
			_chart.set_data(lines, -_range, 0.0)
		"flow":
			lines.append({"name": "In", "color": 0, "points": _per_minute(history, now, func(p): return float(p.income))})
			lines.append({"name": "Out", "color": 1, "points": _per_minute(history, now, func(p): return float(p.spending))})
			_chart.set_data(lines, -_range, 0.0, "/min", 1)
		"people":
			var specs := [["People", "population"], ["Employed", "employed"], ["Jobs", "jobs"]]
			for i in specs.size():
				var key: String = specs[i][1]
				lines.append({"name": specs[i][0], "color": i, "points": _points(history, now, func(p): return float(p.get(key, 0)))})
			_chart.set_data(lines, -_range, 0.0)
		"production":
			var i := 0
			for res in GameData.resources:
				lines.append({"name": GameData.resources[res].name, "color": i,
					"points": _per_minute(history, now, func(p): return float(p.made.get(res, 0)))})
				i += 1
			_chart.set_data(lines, -_range, 0.0, "/min", 1)


## One graph point per history point: (seconds before now, value). Times are made relative to now
## because chart points (Vector2) can't hold a full clock time precisely.
func _points(history: Array, now: float, value: Callable) -> Array:
	var out: Array = []
	for p in history:
		out.append(Vector2(float(p.t) - now, value.call(p)))
	return out


## For running totals (money in, items made): how fast they grew per minute, averaged over the
## AVERAGE_OVER seconds before each point. Work arrives in batches (32 flour every 6 minutes),
## so a minute-by-minute rate would jump between 0 and a spike.
func _per_minute(history: Array, now: float, total: Callable) -> Array:
	var out: Array = []
	var start := 0  # oldest point inside the averaging window
	for i in range(1, history.size()):
		var t := float(history[i].t)
		while start < i - 1 and float(history[start].t) < t - AVERAGE_OVER:
			start += 1
		var minutes := maxf((t - float(history[start].t)) / 60.0, 0.001)
		out.append(Vector2(t - now, (total.call(history[i]) - total.call(history[start])) / minutes))
	return out


# --- Small building blocks -----------------------------------------------------

func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	content.add_child(page)
	return page


## A titled, sunken box. Returns the column to add rows to (child 0 is the heading row).
func _section(parent: Control, title: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	parent.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	box.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 19)
	header.add_child(heading)
	return column


## A table with a header row; cells are added after it, left to right.
func _grid(parent: Control, headers: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for i in headers.size():
		var label := _body(headers[i])
		label.add_theme_font_size_override("font_size", 15)
		label.modulate.a = 0.75
		if i > 0:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.custom_minimum_size.x = 84
		grid.add_child(label)
	return grid


## First cell of a table row: the item's icon and name.
func _item_cell(grid: GridContainer, resource_id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var icon := TextureRect.new()
	icon.texture = UITheme.icon(resource_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28, 28)
	row.add_child(icon)
	row.add_child(_body(GameData.resources[resource_id].name))
	grid.add_child(row)


## "Title ........ value" on one line; the value label is remembered under `key`.
func _value_row(parent: Control, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _body(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(_value(key, true))


func _value(key: String, right := false) -> Label:
	var label := _body("")
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_values[key] = label
	return label


func _show(key: String, text: String, color := LineChart.INK) -> void:
	var label: Label = _values[key]
	label.text = text
	label.add_theme_color_override("font_color", color)


func _bar(parent: Control, style: String) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = style
	bar.show_percentage = false
	bar.custom_minimum_size.y = 16
	parent.add_child(bar)
	return bar


## A row of buttons that work like tabs; `on_pick` gets the chosen id.
func _button_row(parent: Control, items: Array, store: Dictionary, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	for item in items:
		var button := Button.new()
		button.text = item[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 44
		button.add_theme_font_size_override("font_size", 16)
		button.pressed.connect(on_pick.bind(item[0]))
		row.add_child(button)
		store[item[0]] = button
	return row


func _highlight(store: Dictionary, chosen: String) -> void:
	for id in store:
		store[id].theme_type_variation = "YellowButton" if id == chosen else "BlueButton"


func _body(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = "BodyLabel"
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _sum(amounts: Dictionary) -> int:
	var total := 0
	for key in amounts:
		total += int(amounts[key])
	return total


func _rate(per_minute: float) -> String:
	if absf(per_minute) < 0.05:
		return "0"
	return "%.1f" % per_minute


func _signed_color(value: float) -> Color:
	if value > 0.05:
		return UP
	if value < -0.05:
		return DOWN
	return LineChart.INK
