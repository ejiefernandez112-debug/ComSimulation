extends ModalWindow
## The Statistics window (Stats card in the bottom menu), in four tabs:
## - Production: what's being made and used per minute right now, and all-time totals
## - People: population, groups (adults / children), children by age, births and deaths,
##   happiness, employed / unemployed, open jobs, jobs per building type
## - Cash flow: money in and out over the last hour and all time, by source
## - Graphs: cash, cash flow, people and production over time (15 min / 1 h / 6 h)
## Every number comes from Economy (the rules in scripts/sim/); this window only shows them.

const TABS := [["production", "Production"], ["people", "People"], ["cash", "Cash flow"], ["graphs", "Graphs"]]
const GRAPHS := [["cash", "Cash"], ["flow", "Cash flow"], ["people", "People"], ["life", "Births"], ["production", "Production"]]
const CHILD_ROWS := 6  # age groups listed in "Children by age"; the rest are summed up
const PEOPLE_FLOW := [["moved_in", "Moved in"], ["born", "Born"], ["grew_up", "Grew up"], ["died", "Died"]]
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
var _happiness_bar: ProgressBar
var _adults_bar: ProgressBar
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


## Opens the window on `tab` ("people", ...), or on the tab shown last time.
func show_stats(tab := "") -> void:
	_select_tab(tab if _pages.has(tab) else _tab)
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
	var groups := _section(page, "Population by group")
	_value_row(groups, "Adults", "group_adults")
	_value_row(groups, "    with a job", "group_employed")
	_value_row(groups, "    without a job", "group_unemployed")
	_value_row(groups, "Children", "group_children")
	_adults_bar = _bar(groups, "GoldBar")  # gold = adults' share, the dark rest = children
	groups.add_child(_value("group_note"))
	var homes := _section(page, "Housing")
	for type_id in GameData.buildings:
		var def: Dictionary = GameData.buildings[type_id]
		if int(def.get("households", 0)) > 0:
			_value_row(homes, def.name, "home_" + type_id)
	_value_row(homes, "Rent coming in", "rent_rate")
	_value_row(homes, "Homes' power use", "homes_power")
	var wealth := _section(page, "Households by wealth")
	for c in Economy.wealth_classes():
		_value_row(wealth, str(c.name), "wealth_" + str(c.id))
	var wealth_note := _body("Wealth comes from the wage: no job = Broke, the minimum wage = Poor, a wage bonus = Well off. Rich classes need skilled jobs (schools, later).")
	wealth_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wealth_note.custom_minimum_size.x = WIDTH - 90
	wealth_note.add_theme_font_size_override("font_size", 15)
	wealth_note.modulate.a = 0.8
	wealth.add_child(wealth_note)
	var kids := _section(page, "Children by age")
	kids.add_child(_value("children_by_age"))
	var flow := _section(page, "Comings and goings")
	var grid := _grid(flow, ["", "Last hour", "All time"])
	for row in PEOPLE_FLOW + [["net", "Net change"]]:
		grid.add_child(_body(row[1]))
		grid.add_child(_value("pf_hour_" + row[0], true))
		grid.add_child(_value("pf_all_" + row[0], true))
	flow.add_child(_value("next_birth"))
	var mood := _section(page, "Happiness")
	mood.add_child(_value("happiness"))
	_happiness_bar = _bar(mood, "GreenBar")
	_value_row(mood, "Food", "need_food")
	_value_row(mood, "Jobs", "need_jobs")
	_value_row(mood, "Births & newcomers", "move_in")
	var why := _body(_happiness_explanation())
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	why.custom_minimum_size.x = WIDTH - 90
	why.add_theme_font_size_override("font_size", 15)
	why.modulate.a = 0.8
	mood.add_child(why)
	var work := _section(page, "Work")
	for row in [["employed", "Employed"], ["unemployed", "Unemployed"], ["open_jobs", "Open jobs"], ["jobs", "Jobs in total"]]:
		_value_row(work, row[1], row[0])
	_employed_bar = _bar(work, "GoldBar")
	work.add_child(_value("employed_share"))
	work.add_child(_value("work_speed"))
	var by_type := _section(page, "Jobs by building")
	for type_id in GameData.buildings:
		if int(GameData.buildings[type_id].get("max_workers", 0)) > 0:
			_value_row(by_type, GameData.buildings[type_id].name, "jobs_" + type_id)
	var note := _body("When there are more jobs than adults, every building that needs workers runs slower. Children don't work: they grow up into workers. Build houses so babies have room to be born.")
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
	_value_row(money_in, "Rent", "in_rent")
	_value_row(money_in, "Demolish refunds", "in_demolish")
	_value_row(money_in, "Total", "in_total")
	var money_out := _section(page, "All time: money out")
	_value_row(money_out, "Construction", "out_construction")
	_value_row(money_out, "Wages", "out_wages")
	_value_row(money_out, "Water", "out_water")
	_value_row(money_out, "Sales tax", "out_tax")
	_value_row(money_out, "Total", "out_total")
	var tax := _section(page, "Sales tax")
	_value_row(tax, "Sold to the Retailer, last 24 h", "tax_sold")
	_value_row(tax, "Your next sale is taxed at", "tax_rate")
	var how := _body("Progressive: the first $5,000 sold in 24 hours is tax-free, then each part of a sale pays its bracket's rate (8%, 15%, 22%). Selling more never leaves you with less.")
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size.x = WIDTH - 90
	how.add_theme_font_size_override("font_size", 15)
	how.modulate.a = 0.8
	tax.add_child(how)
	var water := _section(page, "Water bill")
	_value_row(water, "This cycle so far", "water_so_far")
	_value_row(water, "Charged in", "water_due")
	_value_row(water, "Last bill", "water_last")
	var water_how := _body(_water_explanation())
	water_how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	water_how.custom_minimum_size.x = WIDTH - 90
	water_how.add_theme_font_size_override("font_size", 15)
	water_how.modulate.a = 0.8
	water.add_child(water_how)
	return page


## "Water comes from the public supply… billed every 12 hours. The part above 1,200 m³ in a
## cycle costs 25% more." Numbers from game_config.json, so the text follows any retuning.
func _water_explanation() -> String:
	var water: Dictionary = GameData.config.get("water", {})
	var text := "Water comes from the public supply at %s per m³. A meter records what your buildings use, and the bill is charged every %d hours." % [UITheme.price(roundi(float(water.get("price_per_m3", 0.0)) * 100.0)), int(water.get("billing_hours", 12))]
	var tiers: Array = water.get("tiers", [])
	for i in range(1, tiers.size()):
		text += " The part above %s m³ in a cycle costs %d%% more." % [UITheme.number(int(tiers[i].from)), roundi(float(tiers[i].extra) * 100.0)]
	return text


## "Happiness is Food and Jobs mixed half and half…" Numbers from game_config.json, so the text
## follows any retuning.
func _happiness_explanation() -> String:
	var h: Dictionary = GameData.config.get("happiness", {})
	var weights: Dictionary = h.get("weights", {})
	var text := "Happiness mixes Food (%d%%) and Jobs (%d%%). Food comes from different foods selling at a Supermarket with workers; Jobs is the share of adults with a job." % [roundi(100.0 * float(weights.get("food", 0.0))), roundi(100.0 * float(weights.get("jobs", 0.0)))]
	text += " Happier villages have more babies:"
	var bands: Array = h.get("growth_speeds", [])
	for i in range(bands.size() - 1, -1, -1):
		var speed := float(bands[i].speed)
		text += " from %d%% %s;" % [roundi(100.0 * float(bands[i].from)), _speed_text(speed)]
	text = text.trim_suffix(";") + "."
	text += " Needs only count from %d people, and not in a new village's first %s hours." % [int(h.get("needs_from_population", 0)), str(h.get("grace_hours", 0))]
	return text


## A growth speed (babies, and newcomers when they come back) in words: "none", "half speed",
## "normal speed", "1.5x as fast".
func _speed_text(speed: float) -> String:
	if speed <= 0.0:
		return "none"
	if is_equal_approx(speed, 1.0):
		return "normal speed"
	if is_equal_approx(speed, 0.5):
		return "half speed"
	return "%sx as fast" % str(speed)


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
		_show("life_earned_" + res, UITheme.money(int(st.sales_by_item.get(res, 0))))
	var b: Dictionary = rates.buildings
	_show("buildings", "Buildings: %d working · %d idle · %d storage full · %d being built" % [b.working, b.idle, b.full, b.building])


func _refresh_people() -> void:
	var e := Economy.employment()
	var cap := Economy.population_capacity()
	_show("population", "%d people · room for %d" % [e.population, cap])
	_population_bar.value = 100.0 * e.population / maxf(cap, 1)
	_refresh_groups(e)
	var happy := Economy.happiness()
	_show("happiness", "%d%% happy" % roundi(100.0 * float(happy.score)))
	_happiness_bar.value = 100.0 * float(happy.score)
	var foods := int(happy.foods)
	var food_text := "%d%% · %d food%s selling" % [roundi(100.0 * float(happy.food)), foods, "" if foods == 1 else "s"]
	_show("need_food", food_text, DOWN if float(happy.food) < 1.0 else LineChart.INK)
	_show("need_jobs", "%d%% · %d of %d adults have a job" % [roundi(100.0 * float(happy.jobs)), e.employed, e.adults], DOWN if float(happy.jobs) < 1.0 else LineChart.INK)
	var speed := float(happy.growth_speed)
	var move_in := _speed_text(speed)
	var child_room: bool = int(e.children) < int(Economy.housing().child_places)
	if not child_room:
		move_in += " · no free child places"
	elif float(happy.grace_left) > 0.0:
		move_in += " · new village: needs count in %s" % UITheme.duration(float(happy.grace_left))
	elif not happy.needs_count:
		move_in += " · small village, needs don't count yet"
	_show("move_in", move_in, DOWN if speed < 1.0 or not child_room else LineChart.INK)
	_show("employed", str(e.employed))
	_show("unemployed", str(e.unemployed), DOWN if e.unemployed > 0 else LineChart.INK)
	_show("open_jobs", str(e.open_jobs))
	_show("jobs", str(e.jobs))
	_employed_bar.value = 100.0 * e.employed / maxf(e.adults, 1)
	_show("employed_share", "%d%% of adults have a job" % roundi(100.0 * e.employed / maxf(e.adults, 1)))
	if e.open_jobs <= 0:
		_show("work_speed", "Every post is filled")
	else:
		_show("work_speed", "%d post%s open: free people go to the biggest wage bonus first" % [e.open_jobs, "" if e.open_jobs == 1 else "s"], DOWN)
	var counts := {}
	var jobs := {}  # type -> jobs asked for at the chosen staffing levels
	for building in Economy.state.buildings:
		if Economy.is_built(building):
			counts[building.type] = int(counts.get(building.type, 0)) + 1
			jobs[building.type] = int(jobs.get(building.type, 0)) + int(Economy.workers(building).wanted)
	for type_id in GameData.buildings:
		if _values.has("jobs_" + type_id):
			var n := int(counts.get(type_id, 0))
			_show("jobs_" + type_id, "%d built · %d jobs" % [n, int(jobs.get(type_id, 0))])


## Population by group, children by age, and who came and went.
func _refresh_groups(e: Dictionary) -> void:
	var people := maxf(e.population, 1)
	_show("group_adults", "%d · %d%%" % [e.adults, roundi(100.0 * e.adults / people)])
	_show("group_employed", str(e.employed))
	_show("group_unemployed", str(e.unemployed), DOWN if e.unemployed > 0 else LineChart.INK)
	_show("group_children", "%d · %d%%" % [e.children, roundi(100.0 * e.children / people)])
	_adults_bar.value = 100.0 * e.adults / people
	_show("group_note", "Adults work and have babies. Children don't work yet.")
	_refresh_housing()
	var lines: Array[String] = []
	var groups := Economy.children_groups()
	var now := TimeService.now()
	for i in mini(groups.size(), CHILD_ROWS):
		var n := int(groups[i].count)
		lines.append("%d %s · grow%s up in %s" % [n, "child" if n == 1 else "children", "s" if n == 1 else "", UITheme.duration(maxf(float(groups[i].grows_up_at) - now, 0.0))])
	if groups.size() > CHILD_ROWS:
		var rest := 0
		for i in range(CHILD_ROWS, groups.size()):
			rest += int(groups[i].count)
		lines.append("…and %d younger" % rest)
	_show("children_by_age", "No children yet." if lines.is_empty() else "\n".join(lines))
	var hour := Economy.people_flow(3600.0)
	var ever := Economy.people_stats()
	var net_hour := 0
	var net_all := 0
	for row in PEOPLE_FLOW:
		var key: String = row[0]
		var sign := -1 if key == "died" else 1
		if key != "grew_up":  # growing up changes who's an adult, not how many people there are
			net_hour += sign * int(hour[key])
			net_all += sign * int(ever[key])
		_show("pf_hour_" + key, str(int(hour[key])) if float(hour.seconds) > 0.0 else "–")
		_show("pf_all_" + key, str(int(ever[key])))
	_show("pf_hour_net", ("%+d" % net_hour) if float(hour.seconds) > 0.0 else "–", _signed_color(net_hour))
	_show("pf_all_net", "%+d" % net_all, _signed_color(net_all))
	var birth := Economy.next_birth_in()
	if not is_inf(birth):
		_show("next_birth", "Next baby in %s" % UITheme.duration(maxf(birth, 0.0)))
	elif int(Economy.housing().housed_adults) <= 0:
		_show("next_birth", "No babies: no adults have a home.", DOWN)
	elif e.children >= int(Economy.housing().child_places):
		_show("next_birth", "No babies: every household with a home already has 2 children.", DOWN)
	else:
		_show("next_birth", "No babies right now: the village is too unhappy.", DOWN)


## Housing: households per home type, the homeless, rent and power; households by wealth class.
func _refresh_housing() -> void:
	var h := Economy.housing()
	var used := {}  # home type -> households living there
	var room := {}  # home type -> households it has room for (huts: how many stand)
	for b in Economy.state.buildings:
		var def: Dictionary = GameData.buildings.get(b.type, {})
		if int(def.get("households", 0)) <= 0 or not Economy.is_built(b):
			continue
		room[b.type] = int(room.get(b.type, 0)) + int(def.households)
		used[b.type] = int(used.get(b.type, 0)) + int(h.homes.get(b.id, {}).get("households", 0))
	for type_id in GameData.buildings:
		if not _values.has("home_" + type_id):
			continue
		if GameData.buildings[type_id].get("hut", false):
			var homeless := int(h.homeless)
			_show("home_" + type_id, "%d homeless household%s" % [homeless, "" if homeless == 1 else "s"], DOWN if homeless > 0 else LineChart.INK)
		else:
			_show("home_" + type_id, "%d of %d households" % [int(used.get(type_id, 0)), int(room.get(type_id, 0))])
	_show("rent_rate", "%s an hour" % UITheme.money(roundi(float(h.rent_per_hour) * 100.0)), UP if float(h.rent_per_hour) > 0.0 else LineChart.INK)
	_show("homes_power", "%s MW (once electricity exists)" % str(snappedf(float(h.power_mw), 0.1)))
	for id in h.classes:
		if not _values.has("wealth_" + str(id)):
			continue
		var c: Dictionary = h.classes[id]
		var text := "%d households · %d adults" % [int(c.households), int(c.adults)]
		if int(c.homeless) > 0:
			text += " · %d homeless" % int(c.homeless)
		_show("wealth_" + str(id), text, DOWN if int(c.homeless) > 0 else LineChart.INK)


func _refresh_cash() -> void:
	var st := Economy.stats()
	_show("cash", UITheme.money(Economy.currency()))
	var flow := Economy.cash_flow(3600.0)
	var span := float(flow.seconds)
	if span < 60.0:
		_values.flow_title.text = "Last hour (collecting data…)"
	elif absf(span - 3600.0) <= 120.0:
		_values.flow_title.text = "Last hour"
	else:
		_values.flow_title.text = "Last %s" % LineChart._ago(span)  # shorter at first; longer right after time away
	# Signs and colours follow the whole dollars shown, so a few cents never show as "-$0".
	var income := roundi(flow.income / 100.0)
	var spent := roundi(flow.spending / 100.0)
	_show("flow_in", ("+" if income > 0 else "") + UITheme.money(flow.income), UP if income > 0 else LineChart.INK)
	_show("flow_out", ("-" if spent > 0 else "") + UITheme.money(flow.spending), DOWN if spent > 0 else LineChart.INK)
	var net: int = flow.income - flow.spending
	_show("flow_net", ("+" if roundi(net / 100.0) > 0 else "") + UITheme.money(net), _signed_color(roundi(net / 100.0)))
	var total_in := 0
	for res in GameData.resources:
		var earned := int(st.sales_by_item.get(res, 0))
		total_in += earned
		_show("in_sales_" + res, UITheme.money(earned))
	_show("in_rent", UITheme.money(int(st.income.get("rent", 0))))
	_show("in_demolish", UITheme.money(int(st.income.demolish)))
	_show("in_total", UITheme.money(total_in + int(st.income.get("rent", 0)) + int(st.income.demolish)), UP)
	_show("out_construction", UITheme.money(int(st.spending.construction)))
	_show("out_wages", UITheme.money(int(st.spending.get("wages", 0))))
	_show("out_water", UITheme.money(int(st.spending.get("water", 0))))
	_show("out_tax", UITheme.money(int(st.spending.get("tax", 0))))
	var total_out := 0
	for key in st.spending:
		total_out += int(st.spending[key])
	_show("out_total", UITheme.money(total_out), DOWN)
	var bracket := Economy.tax_bracket()
	_show("tax_sold", UITheme.money(int(bracket.sold)))
	var rate := "%d%%" % roundi(float(bracket.rate) * 100.0)
	if int(bracket.next_at) > 0:
		rate += " (next bracket at %s)" % UITheme.money(int(bracket.next_at))
	_show("tax_rate", rate)
	var bill := Economy.water_bill()
	_show("water_so_far", "%s m³ · %s" % [UITheme.number(roundi(float(bill.m3))), UITheme.money(int(bill.cost))])
	_show("water_due", UITheme.duration(float(bill.due_at) - TimeService.now()))
	var bills := Economy.water_bills()
	if bills.is_empty():
		_show("water_last", "none yet")
	else:
		var last: Dictionary = bills[-1]
		_show("water_last", "%s for %s m³ (%s ago)" % [UITheme.money(int(last.cost)), UITheme.number(roundi(float(last.m3))), LineChart._ago(TimeService.now() - float(last.t))])


## Builds the chosen graph's lines from the history points (one every minute), plus a point for
## right now so the lines always reach "now" and include what just happened.
func _refresh_graph() -> void:
	var st := Economy.stats()
	var now := TimeService.now()
	var history: Array = st.history.duplicate()
	if history.is_empty() or now - float(history[-1].t) > 1.0:
		var e := Economy.employment()
		var ever := Economy.people_stats()
		history.append({"t": now, "cash": Economy.currency(), "income": _sum(st.income), "spending": _sum(st.spending),
			"population": e.population, "adults": e.adults, "children": e.children, "employed": e.employed,
			"jobs": e.jobs, "made": st.made, "born": ever.born, "died": ever.died, "grew_up": ever.grew_up})
	var lines: Array = []
	# Money is kept in cents; the graphs show dollars (/ 100).
	match _graph:
		"cash":
			lines.append({"name": "Cash", "color": 0, "points": _points(history, now, func(p): return float(p.cash) / 100.0)})
			_chart.set_data(lines, -_range, 0.0, "", 0, "$")
		"flow":
			lines.append({"name": "In", "color": 0, "points": _per_minute(history, now, func(p): return float(p.income) / 100.0)})
			lines.append({"name": "Out", "color": 1, "points": _per_minute(history, now, func(p): return float(p.spending) / 100.0)})
			_chart.set_data(lines, -_range, 0.0, "/min", 1, "$")
		"people":
			# Older history points have no adults / children: those lines start where the data does.
			var specs := [["People", "population"], ["Adults", "adults"], ["Children", "children"], ["Employed", "employed"], ["Jobs", "jobs"]]
			for i in specs.size():
				var key: String = specs[i][1]
				var known := history.filter(func(p): return p.has(key))
				lines.append({"name": specs[i][0], "color": i, "points": _points(known, now, func(p): return float(p[key]))})
			_chart.set_data(lines, -_range, 0.0)
		"life":
			# Births and deaths per hour, averaged over the hour before each point (they're rare
			# events, so a shorter average would jump between 0 and a spike).
			var specs := [["Born", "born"], ["Died", "died"], ["Grew up", "grew_up"]]
			for i in specs.size():
				var key: String = specs[i][1]
				var known := history.filter(func(p): return p.has(key))
				var per_minute := _per_minute(known, now, func(p): return float(p[key]), 3600.0)
				lines.append({"name": specs[i][0], "color": i, "points": per_minute.map(func(v): return Vector2(v.x, v.y * 60.0))})
			_chart.set_data(lines, -_range, 0.0, "/h", 1)
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
## `over` seconds before each point (AVERAGE_OVER unless given). Work arrives in batches (32 flour
## every 6 minutes), so a minute-by-minute rate would jump between 0 and a spike.
func _per_minute(history: Array, now: float, total: Callable, over := AVERAGE_OVER) -> Array:
	var out: Array = []
	var start := 0  # oldest point inside the averaging window
	for i in range(1, history.size()):
		var t := float(history[i].t)
		while start < i - 1 and float(history[start].t) < t - over:
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
