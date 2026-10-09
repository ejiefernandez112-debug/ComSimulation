extends ModalWindow
## The Statistics window (Stats card in the bottom menu), in six tabs:
## - Goods: what's being made and used per minute right now, and all-time totals
## - People: population (adults / children), work, homes and wealth, comings and goings
## - Happiness: the % and mood, what it does, what would raise it, and each need
## - Cash: money in and out over the last hour and all time, by source; the cash check
##   and the money log (money_pages.gd)
## - Balance: what the company owns and owes, and its value (money_pages.gd)
## - Graphs: cash, cash flow, people and production over time (15 min / 1 h / 6 h)
## Every number comes from Economy (the rules in scripts/sim/); this window only shows them.

const TABS := [["production", "Goods"], ["people", "People"], ["happiness", "Happiness"], ["cash", "Cash"], ["balance", "Balance"], ["graphs", "Graphs"]]
const GRAPHS := [["cash", "Cash"], ["flow", "Cash flow"], ["people", "People"], ["life", "Births"], ["production", "Production"]]
const CHILD_ROWS := 6  # age groups listed in "Children by age"; the rest are summed up
const PEOPLE_FLOW := [["moved_in", "Moved in"], ["born", "Born"], ["grew_up", "Grew up"], ["died", "Died"], ["moved_away", "Left the island"]]
const RANGES := [[900.0, "15 min"], [3600.0, "1 hour"], [21600.0, "6 hours"]]
const AVERAGE_OVER := 600.0  # rate graphs (cash flow, production) show 10-minute averages

var _tab := "production"
var _graph := "cash"
var _range := 3600.0
var _pages := {}  # tab id -> its page
var _tab_buttons := {}
var _graph_buttons := {}
var _range_buttons := {}
var _values := {}  # name -> Label whose text _refresh updates
var _item_cells := {}  # "rate_wheat" / "life_wheat" -> an item's name cell in the Production grids
var _population_bar: ProgressBar
var _happiness_bar: ProgressBar
var _employed_bar: ProgressBar
var _chart: LineChart
var _money := preload("res://scenes/ui/money_pages.gd").new(self)  # Balance tab, cash check, money log


func _ready() -> void:
	super()
	var tabs := _button_row(content, TABS, _tab_buttons, _select_tab)
	tabs.add_theme_constant_override("separation", 4)
	_pages.production = _production_page()
	_pages.people = _people_page()
	_pages.happiness = _happiness_page()
	_pages.cash = _cash_page()
	_pages.balance = _page()
	_money.build_balance(_pages.balance)
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
		_item_cell(grid, res, "rate_")
		for column in ["made", "used", "net"]:
			grid.add_child(_value("rate_%s_%s" % [column, res], true))
	now_box.add_child(_value("buildings"))
	var all_box := _section(page, "All time")
	grid = _grid(all_box, ["", "Made", "Sold", "Earned"])
	for res in GameData.resources:
		_item_cell(grid, res, "life_")
		for column in ["made", "sold", "earned"]:
			grid.add_child(_value("life_%s_%s" % [column, res], true))
	return page


func _people_page() -> VBoxContainer:
	var page := _page()
	var town := _section(page, "Population")
	town.add_child(_value("population"))
	_population_bar = _bar(town, "BlueBar")
	_value_row(town, "Adults", "group_adults")
	_value_row(town, "Children", "group_children")
	town.add_child(_value("children_by_age"))
	var work := _section(page, "Work")
	for row in [["employed", "Employed"], ["unemployed", "Unemployed"], ["open_jobs", "Open jobs"], ["jobs", "Jobs in total"]]:
		_value_row(work, row[1], row[0])
	_employed_bar = _bar(work, "GoldBar")
	work.add_child(_value("work_speed"))
	var homes := _section(page, "Homes and wealth")
	for type_id in GameData.buildings:
		var def: Dictionary = GameData.buildings[type_id]
		if int(def.get("households", 0)) > 0:
			_value_row(homes, def.name, "home_" + type_id)
	_value_row(homes, "Rent coming in", "rent_rate")
	for c in Economy.wealth_classes():
		_value_row(homes, str(c.name), "wealth_" + str(c.id))
	var flow := _section(page, "Comings and goings")
	var grid := _grid(flow, ["", "Last hour", "All time"])
	for row in PEOPLE_FLOW + [["net", "Net change"]]:
		grid.add_child(_body(row[1]))
		grid.add_child(_value("pf_hour_" + row[0], true))
		grid.add_child(_value("pf_all_" + row[0], true))
	flow.add_child(_value("next_birth"))
	flow.add_child(_value("next_arrival"))
	return page


## Happiness: the % and mood, what it's made of, what it does and what would raise it; then each
## need (its % and, under it, why).
func _happiness_page() -> VBoxContainer:
	var page := _page()
	var mood := _section(page, "Happiness")
	mood.add_child(_value("happiness"))
	_values.happiness.theme_type_variation = "HeadingLabel"
	_happiness_bar = _bar(mood, "GreenBar")
	mood.add_child(_note("summary"))
	_value_row(mood, "Births & newcomers", "move_in")
	mood.add_child(_value("leaving"))
	mood.add_child(_value("raise"))
	var needs := _section(page, "Needs")
	for need in Economy.need_ids():
		_value_row(needs, Economy.need_name(need), "need_" + need)
		needs.add_child(_note("why_" + need))
	return page


func _cash_page() -> VBoxContainer:
	var page := _page()
	var now_box := _section(page, "Cash")
	now_box.add_child(_value("cash"))
	_values.cash.theme_type_variation = "BigLabel"
	var recent := _section(page, "Last hour")
	_values["flow_title"] = recent.get_child(0).get_child(0)  # the section heading names the real time span
	_value_row(recent, "Money in", "flow_in")
	_value_row(recent, "Money out", "flow_out")
	_value_row(recent, "Net", "flow_net")
	var money_in := _section(page, "All time: money in")
	for res in GameData.resources:
		_value_row(money_in, "Sales of %s" % GameData.resources[res].name, "in_sales_" + res)
	_value_row(money_in, "Rent", "in_rent")
	_value_row(money_in, "Refunds", "in_demolish")  # older demolishes and roads paid back; demolishing now gives materials, not money
	_value_row(money_in, "Cancelled batches", "in_batch_refunds")
	_value_row(money_in, "Total", "in_total")
	var money_out := _section(page, "All time: money out")
	_value_row(money_out, "Construction", "out_construction")
	_value_row(money_out, "Roads", "out_roads")
	_value_row(money_out, "Wages", "out_wages")
	_value_row(money_out, "Water", "out_water")
	_value_row(money_out, "Power", "out_power")
	_value_row(money_out, "Sales tax", "out_tax")
	_value_row(money_out, "Switching products", "out_switch_fees")
	_value_row(money_out, "Trading Post purchases", "out_purchases")
	_value_row(money_out, "Total", "out_total")
	_money.build_cash_check(page)
	_money.build_money_log(page)
	var tax := _section(page, "Sales tax")
	_value_row(tax, "Sold to the Retailer, last 24 h", "tax_sold")
	_value_row(tax, "Your next sale is taxed at", "tax_rate")
	var water := _section(page, "Water bill")
	_value_row(water, "Using now", "water_now")
	_value_row(water, "This cycle so far", "water_so_far")
	_value_row(water, "Charged in", "water_due")
	_value_row(water, "Last bill", "water_last")
	if Economy.power_on():
		var power := _section(page, "Power bill")
		_value_row(power, "Using now", "power_now")
		_value_row(power, "This cycle so far", "power_so_far")
		_value_row(power, "Charged in", "power_due")
		_value_row(power, "Last bill", "power_last")
	return page


## A growth speed (babies or migrant workers) in words: "none", "half", "normal", "×1.5".
func _speed_text(speed: float) -> String:
	if speed <= 0.0:
		return "none"
	if is_equal_approx(speed, 1.0):
		return "normal"
	if is_equal_approx(speed, 0.5):
		return "half"
	return "×%s" % str(speed)


## Who is leaving the island right now, e.g. "Leaving the island, 5% an hour: jobless adults";
## "" when nobody is. Only the jobless adults leave (Simulation._leave_pool).
func _leaving_text(happy: Dictionary) -> String:
	var rate := float(happy.leave_per_hour)
	if rate <= 0.0 or int(happy.jobless) <= 0:
		return ""
	return "Leaving the island, %s%% an hour: jobless adults" % str(snappedf(rate * 100.0, 0.1))


## "To raise it: Clinic for 120 more people +9% ⋅ 1 more food +6% ⋅ homes for 10 households in
## huts +4%": the 3 biggest gains (Simulation.happiness_gains); "" when there's nothing to gain.
func _raise_text(happy: Dictionary) -> String:
	var gains := Economy.happiness_gains()
	var fixes := []
	for key in gains:
		var text := _fix_text(happy, key)
		if text != "":
			fixes.append([float(gains[key]), text])
	fixes.sort_custom(func(a, b): return a[0] > b[0])
	var parts: Array[String] = []
	for fix in fixes:
		if roundi(100.0 * fix[0]) >= 1 and parts.size() < 3:  # less than a point isn't worth saying
			parts.append("%s +%d%%" % [fix[1], roundi(100.0 * fix[0])])
	return "" if parts.is_empty() else "To raise it: " + " ⋅ ".join(parts)


## What a fix in happiness_gains means, in words ("homes for 3 households in huts").
func _fix_text(happy: Dictionary, key: String) -> String:
	match key:
		"food":
			return "1 more food"
		"jobs":
			var jobless := int(happy.jobless)
			return "jobs for %d adult%s" % [jobless, "" if jobless == 1 else "s"]
		"housing":
			var homeless := int(happy.homeless)
			return "homes for %d household%s in huts" % [homeless, "" if homeless == 1 else "s"]
		"power":
			var dark := int(happy.unpowered)
			return "power for %d household%s" % [dark, "" if dark == 1 else "s"]
	var type_id := Economy.service_building_for(key)  # needs met by service buildings
	if type_id == "":
		return ""
	var c: Dictionary = happy.coverage.get(key, {})
	var short := ceili(float(Economy.employment().population) - float(c.get("places", 0.0)))  # people not served yet
	var name := str(GameData.buildings[type_id].name)
	return "%s for %d more people" % [name, short] if short > 0 else "a better %s" % name


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
	_chart.custom_minimum_size = Vector2(UITheme.WINDOW_WIDTH - 50, 220)
	_chart.empty_text = "Not enough data yet."
	page.add_child(_chart)
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
		"happiness":
			_refresh_happiness()
		"cash":
			_refresh_cash()
			_money.refresh_cash_check()
			_money.refresh_money_log()
		"balance":
			_money.refresh_balance()
		"graphs":
			_refresh_graph()


func _refresh_production() -> void:
	var rates := Economy.production_rates()
	var st := Economy.stats()
	for res in GameData.resources:
		var made := float(rates.made.get(res, 0.0))
		var used := float(rates.used.get(res, 0.0))
		# With many kinds of goods, show only those in play: made, used, sold or in stock.
		var in_play := made > 0.0 or used > 0.0 or int(st.made.get(res, 0)) > 0 or int(st.sold.get(res, 0)) > 0 or int(Economy.state.inventory.get(res, 0)) > 0
		for group in ["rate_", "life_"]:
			_item_cells[group + res].visible = in_play
		for key in ["rate_made_", "rate_used_", "rate_net_", "life_made_", "life_sold_", "life_earned_"]:
			_values[key + res].visible = in_play
		_show("rate_made_" + res, _rate(made))
		_show("rate_used_" + res, _rate(used))
		_show("rate_net_" + res, ("+" if made - used > 0.05 else "") + _rate(made - used), _signed_color(made - used))
		_show("life_made_" + res, UITheme.number(int(st.made.get(res, 0))))
		_show("life_sold_" + res, UITheme.number(int(st.sold.get(res, 0))))
		_show("life_earned_" + res, UITheme.money(int(st.sales_by_item.get(res, 0))))
	var b: Dictionary = rates.buildings
	_show("buildings", "Buildings: %d working ⋅ %d idle ⋅ %d done, waiting to be collected ⋅ %d being built" % [b.working, b.idle, b.done, b.building])


func _refresh_people() -> void:
	var e := Economy.employment()
	var cap := Economy.population_capacity()
	_show("population", "%d people ⋅ room for %d" % [e.population, cap])
	_population_bar.value = 100.0 * e.population / maxf(cap, 1)
	_refresh_groups(e)
	_show("employed", str(e.employed))
	_show("unemployed", str(e.unemployed), UITheme.BAD if e.unemployed > 0 else UITheme.TEXT)
	_show("open_jobs", str(e.open_jobs))
	_show("jobs", str(e.jobs))
	_employed_bar.value = 100.0 * e.employed / maxf(e.adults, 1)
	if e.open_jobs <= 0:
		_show("work_speed", "Every post is filled")
	else:
		_show("work_speed", "%d post%s open" % [e.open_jobs, "" if e.open_jobs == 1 else "s"], UITheme.BAD)


func _refresh_happiness() -> void:
	var e := Economy.employment()
	var happy := Economy.happiness()
	# Rounded down, like the moods; a Developer-window lock says so.
	var mood := str(happy.get("mood", ""))
	_show("happiness", "%d%% %s%s" % [int(happy.percent), mood.to_lower() if mood != "" else "happy", " ⋅ dev lock" if not happy.get("dev_locks", {}).is_empty() else ""])
	_happiness_bar.value = 100.0 * float(happy.score)
	_show("summary", _summary_text(happy), UITheme.TEXT_DIM)
	var leaving := _leaving_text(happy)
	_show("leaving", leaving, UITheme.BAD)
	_values.leaving.visible = leaving != ""  # nothing to say while nobody leaves
	var raise := _raise_text(happy)
	_show("raise", raise)
	_values.raise.visible = raise != ""
	var speed := float(happy.growth_speed)
	var move_in := "babies %s ⋅ migrants %s" % [_speed_text(speed), _speed_text(float(happy.move_in_speed))]
	_show("move_in", move_in, UITheme.BAD if speed < 1.0 else UITheme.TEXT)
	_refresh_needs(happy, e)


## The Needs section: each need and why it stands where it does; a need that only counts in a
## bigger village says from how many people.
func _refresh_needs(happy: Dictionary, e: Dictionary) -> void:
	var needs: Dictionary = happy.needs
	var later: Dictionary = happy.get("later", {})
	for need in Economy.need_ids():
		if needs.has(need):
			var value := float(needs[need])
			_show("need_" + need, "%d%%" % roundi(100.0 * value), UITheme.BAD if value < 0.5 else UITheme.TEXT)
			_show("why_" + need, _need_reason(happy, e, need), UITheme.TEXT_DIM)
		else:
			_show("need_" + need, "—", UITheme.TEXT_DIM)
			_show("why_" + need, "counts from %d people" % int(later.get(need, 0)), UITheme.TEXT_DIM)


## Why a need stands where it does, e.g. "2 foods selling ⋅ 1 more food: 60%", "Clinics serve 100
## of 230 people".
func _need_reason(happy: Dictionary, e: Dictionary, need: String) -> String:
	var people := int(e.population)
	match need:
		"food":
			var foods := int(happy.foods)
			var text := "%d food%s selling" % [foods, "" if foods == 1 else "s"]
			# More different foods count for more (happiness.needs.food.scores): say what the next one brings.
			var scores: Array = GameData.config.get("happiness", {}).get("needs", {}).get("food", {}).get("scores", [])
			if foods + 1 < scores.size():
				text += " ⋅ 1 more food: %d%%" % roundi(100.0 * float(scores[foods + 1]))
			return text
		"jobs":
			return "%d of %d adults work" % [e.employed, e.adults]
		"housing":
			var parts: Array[String] = []
			if int(happy.homeless) > 0:
				parts.append("%d household%s in huts" % [int(happy.homeless), "" if int(happy.homeless) == 1 else "s"])
			if int(happy.unpowered) > 0:
				parts.append("%d without power" % int(happy.unpowered))
			return " ⋅ ".join(parts) if not parts.is_empty() else "everyone has a real home"
	var c: Dictionary = happy.coverage.get(need, {})
	var places := roundi(float(c.get("places", 0.0)))
	var type_id := Economy.service_building_for(need)
	var building := str(GameData.buildings[type_id].name) if type_id != "" else "nothing"
	return ("no %s yet" % building) if places <= 0 else "%ss serve %d of %d" % [building, mini(places, people), people]


## "Average of 4 needs ⋅ Fun counts from 100 people": happiness is the plain average of the needs
## that count, and the next need joins as the village grows. While an unmet need limits it: "⋅ no
## food selling: at most 35%".
func _summary_text(happy: Dictionary) -> String:
	var needs: Dictionary = happy.needs
	var text := "Average of %d need%s" % [needs.size(), "" if needs.size() == 1 else "s"]
	var later: Dictionary = happy.get("later", {})
	var next := ""
	for need in later:
		if next == "" or int(later[need]) < int(later[next]):
			next = need
	if next != "":
		text += " ⋅ %s counts from %d people" % [Economy.need_name(next), int(later[next])]
	var cap: Dictionary = happy.get("cap", {})
	if not cap.is_empty():
		var lacking := "no food selling" if str(cap.need) == "food" else "no " + Economy.need_name(str(cap.need)).to_lower()
		text += " ⋅ %s: at most %d%%" % [lacking, roundi(100.0 * float(cap.max))]
	return text


## Population by group, children by age, and who came and went.
func _refresh_groups(e: Dictionary) -> void:
	var people := maxf(e.population, 1)
	_show("group_adults", "%d ⋅ %d%%" % [e.adults, roundi(100.0 * e.adults / people)])
	_show("group_children", "%d ⋅ %d%%" % [e.children, roundi(100.0 * e.children / people)])
	_refresh_housing()
	var lines: Array[String] = []
	var groups := Economy.children_groups()
	var now := TimeService.now()
	for i in mini(groups.size(), CHILD_ROWS):
		var n := int(groups[i].count)
		lines.append("%d %s ⋅ grow%s up in %s" % [n, "child" if n == 1 else "children", "s" if n == 1 else "", UITheme.duration(maxf(float(groups[i].grows_up_at) - now, 0.0))])
	if groups.size() > CHILD_ROWS:
		var rest := 0
		for i in range(CHILD_ROWS, groups.size()):
			rest += int(groups[i].count)
		lines.append("…and %d younger" % rest)
	if not groups.is_empty() and bool(GameData.config.get("life", {}).get("grown_ups_leave_without_job", false)):
		lines.append("Jobs waiting for them now: %d. The rest leave to find work." % Economy.jobs_waiting())
	_show("children_by_age", "No children yet." if lines.is_empty() else "Children by age:\n" + "\n".join(lines), UITheme.TEXT_DIM)
	var hour := Economy.people_flow(3600.0)
	var ever := Economy.people_stats()
	var net_hour := 0
	var net_all := 0
	for row in PEOPLE_FLOW:
		var key: String = row[0]
		var sign := -1 if key in ["died", "moved_away"] else 1
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
	elif e.adults <= 0:
		_show("next_birth", "No babies: there are no adults.", UITheme.BAD)
	elif e.children >= int(Economy.housing().child_places):
		_show("next_birth", "No babies: every family already has 2 children.", UITheme.BAD)
	else:
		_show("next_birth", "No babies right now: the village is too unhappy.", UITheme.BAD)
	_show_next_arrival(e)


## The next migrant worker, or why none is coming, and how many households live in huts.
func _show_next_arrival(e: Dictionary) -> void:
	var arrival := Economy.next_arrival_in()
	var needs_home := bool(GameData.config.get("move_in_needs_home", true))
	var text := ""
	var color := UITheme.TEXT
	if not is_inf(arrival):
		var count := Economy.next_arrival_count()
		if count == 1:
			text = "Next migrant worker arrives in %s" % UITheme.duration(maxf(arrival, 0.0))
		else:
			text = "Next %d migrant workers arrive in %s" % [count, UITheme.duration(maxf(arrival, 0.0))]
	elif float(GameData.config.get("population_growth_seconds", 0)) <= 0.0:
		text = "Nobody moves in from outside."
	elif int(e.open_jobs) - int(e.unemployed) <= 0:
		text = "No migrant workers: no open jobs. Build a workplace to attract them."
	elif needs_home and Economy.adults() >= Economy.adult_room():
		text = "No migrant workers: no free homes. Build homes so they can move in."
		color = UITheme.BAD
	else:
		text = "No migrant workers: the village is too unhappy."
		color = UITheme.BAD
	var homeless := int(Economy.housing().homeless)
	if homeless > 0:
		text += "\n%d household%s live%s in huts: build homes to raise happiness." % [homeless, "" if homeless == 1 else "s", "s" if homeless == 1 else ""]
		color = UITheme.BAD
	_show("next_arrival", text, color)


## Housing: households per home type, the homeless, rent and power; households by wealth class.
func _refresh_housing() -> void:
	var h := Economy.housing()
	var used := {}  # home type -> households living there
	var room := {}  # home type -> households it has room for (huts: how many stand)
	for b in Economy.state.buildings:
		var def: Dictionary = GameData.buildings.get(b.type, {})
		if int(def.get("households", 0)) <= 0 or not Economy.is_built(b):
			continue
		room[b.type] = int(room.get(b.type, 0)) + int(Economy.level_stat(b, "households"))
		used[b.type] = int(used.get(b.type, 0)) + int(h.homes.get(b.id, {}).get("households", 0))
	for type_id in GameData.buildings:
		if not _values.has("home_" + type_id):
			continue
		if GameData.buildings[type_id].get("hut", false):
			var homeless := int(h.homeless)
			_show("home_" + type_id, "%d homeless household%s" % [homeless, "" if homeless == 1 else "s"], UITheme.BAD if homeless > 0 else UITheme.TEXT)
			_values["home_" + type_id].get_parent().visible = homeless > 0 or int(room.get(type_id, 0)) > 0
		else:
			_show("home_" + type_id, "%d of %d households" % [int(used.get(type_id, 0)), int(room.get(type_id, 0))])
			_values["home_" + type_id].get_parent().visible = int(room.get(type_id, 0)) > 0  # only home types you have
	_show("rent_rate", "%s an hour" % UITheme.money(roundi(float(h.rent_per_hour) * 100.0)), UITheme.GOOD if float(h.rent_per_hour) > 0.0 else UITheme.TEXT)
	for id in h.classes:
		if not _values.has("wealth_" + str(id)):
			continue
		var c: Dictionary = h.classes[id]
		var text := "%d households ⋅ %d adults" % [int(c.households), int(c.adults)]
		if int(c.homeless) > 0:
			text += " ⋅ %d homeless" % int(c.homeless)
		_show("wealth_" + str(id), text, UITheme.BAD if int(c.homeless) > 0 else UITheme.TEXT)


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
	_show("flow_in", ("+" if income > 0 else "") + UITheme.money(flow.income), UITheme.GOOD if income > 0 else UITheme.TEXT)
	_show("flow_out", ("-" if spent > 0 else "") + UITheme.money(flow.spending), UITheme.BAD if spent > 0 else UITheme.TEXT)
	var net: int = flow.income - flow.spending
	_show("flow_net", ("+" if roundi(net / 100.0) > 0 else "") + UITheme.money(net), _signed_color(roundi(net / 100.0)))
	for res in GameData.resources:
		var earned := int(st.sales_by_item.get(res, 0))
		_show("in_sales_" + res, UITheme.money(earned))
		_values["in_sales_" + res].get_parent().visible = earned > 0  # only goods that have sold
	_show("in_rent", UITheme.money(int(st.income.get("rent", 0))))
	_show("in_demolish", UITheme.money(int(st.income.demolish)))
	var refunds := int(st.income.get("batch_refunds", 0))
	_show("in_batch_refunds", UITheme.money(refunds))
	_values.in_batch_refunds.get_parent().visible = refunds > 0  # only once a batch was cancelled
	# Every kind of money in (like the Total out below), so the two totals match the cash.
	_show("in_total", UITheme.money(_sum(st.income)), UITheme.GOOD)
	_show("out_construction", UITheme.money(int(st.spending.construction)))
	_show("out_roads", UITheme.money(int(st.spending.get("roads", 0))))
	_show("out_wages", UITheme.money(int(st.spending.get("wages", 0))))
	_show("out_water", UITheme.money(int(st.spending.get("water", 0))))
	_show("out_power", UITheme.money(int(st.spending.get("power", 0))))
	_show("out_tax", UITheme.money(int(st.spending.get("tax", 0))))
	_show("out_switch_fees", UITheme.money(int(st.spending.get("switch_fees", 0))))
	_show("out_purchases", UITheme.money(int(st.spending.get("purchases", 0))))
	var total_out := 0
	for key in st.spending:
		total_out += int(st.spending[key])
	_show("out_total", UITheme.money(total_out), UITheme.BAD)
	var bracket := Economy.tax_bracket()
	_show("tax_sold", UITheme.money(int(bracket.sold)))
	var rate := "%d%%" % roundi(float(bracket.rate) * 100.0)
	if int(bracket.next_at) > 0:
		rate += " (next bracket at %s)" % UITheme.money(int(bracket.next_at))
	_show("tax_rate", rate)
	var water_flow := Economy.water_summary()  # own plants' water first, then the public supply
	_show("water_now", "%s m³/h ⋅ %s from your plants, %s public" % [UITheme.number(roundi(float(water_flow.used))), UITheme.number(roundi(float(water_flow.from_own))), UITheme.number(roundi(float(water_flow.public)))])
	var bill := Economy.water_bill()
	_show("water_so_far", "%s m³ ⋅ %s" % [UITheme.number(roundi(float(bill.m3))), UITheme.money(int(bill.cost))])
	_show("water_due", UITheme.duration(float(bill.due_at) - TimeService.now()))
	var bills := Economy.water_bills()
	if bills.is_empty():
		_show("water_last", "none yet")
	else:
		var last: Dictionary = bills[-1]
		_show("water_last", "%s for %s m³ (%s ago)" % [UITheme.money(int(last.cost)), UITheme.number(roundi(float(last.m3))), LineChart._ago(TimeService.now() - float(last.t))])
	if Economy.power_on():
		var power_flow := Economy.power_summary()  # own plants first, then the public grid
		_show("power_now", "%s ⋅ %s from your plants, %s from the grid" % [BuildingInfo.mw(float(power_flow.used)), BuildingInfo.mw(float(power_flow.from_own)), BuildingInfo.mw(float(power_flow.public))])
		var power_bill := Economy.power_bill()
		_show("power_so_far", "%s MWh ⋅ %s" % [str(snappedf(float(power_bill.mwh), 0.1)), UITheme.money(int(power_bill.cost))])
		_show("power_due", UITheme.duration(float(power_bill.due_at) - TimeService.now()))
		var power_bills := Economy.power_bills()
		if power_bills.is_empty():
			_show("power_last", "none yet")
		else:
			var last_power: Dictionary = power_bills[-1]
			_show("power_last", "%s for %s MWh (%s ago)" % [UITheme.money(int(last_power.cost)), str(snappedf(float(last_power.mwh), 0.1)), LineChart._ago(TimeService.now() - float(last_power.t))])


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
			"jobs": e.jobs, "made": st.made, "born": ever.born, "died": ever.died, "grew_up": ever.grew_up,
			"moved_away": ever.moved_away})
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
			var specs := [["Born", "born"], ["Died", "died"], ["Grew up", "grew_up"], ["Left", "moved_away"]]
			for i in specs.size():
				var key: String = specs[i][1]
				var known := history.filter(func(p): return p.has(key))
				var per_minute := _per_minute(known, now, func(p): return float(p[key]), 3600.0)
				lines.append({"name": specs[i][0], "color": i, "points": per_minute.map(func(v): return Vector2(v.x, v.y * 60.0))})
			_chart.set_data(lines, -_range, 0.0, "/h", 1)
		"production":
			var i := 0
			for res in GameData.resources:
				if int(Economy.stats().made.get(res, 0)) <= 0:
					continue  # never made: no line (there are many kinds of goods)
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
	page.add_theme_constant_override("separation", 8)
	flow_page(page)  # a long page carries on in a panel beside the window
	content.add_child(page)
	return page


## A titled, sunken box. Returns the column to add rows to (child 0 is the heading row).
func _section(parent: Control, title: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.theme_type_variation = "Inset"
	parent.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = "HeadingLabel"
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
		label.theme_type_variation = "SmallLabel"
		label.modulate.a = 0.75
		if i > 0:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.custom_minimum_size.x = 84
		grid.add_child(label)
	return grid


## First cell of a table row: the item's icon and name.
func _item_cell(grid: GridContainer, resource_id: String, group := "") -> void:
	var row := HBoxContainer.new()
	_item_cells[group + resource_id] = row  # so the row can be hidden for items not in play
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


## "Title ........ value" on one line; the value label is remembered under `key`. A long value
## wraps onto more lines (right-aligned) instead of making the window wider.
func _value_row(parent: Control, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _body(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := _value(key, true)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.size_flags_stretch_ratio = 1.5
	row.add_child(value)


## A label remembered under `key`: a whole line that wraps (right = false), or a table cell /
## row value (right = true).
func _value(key: String, right := false) -> Label:
	var label := _body("")
	if right:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = UITheme.WINDOW_WIDTH - 80  # wrapped text needs a width
	_values[key] = label
	return label


## A small, dim line that wraps (explanations under a row), remembered under `key`.
func _note(key: String) -> Label:
	var label := _value(key)
	label.theme_type_variation = "SmallLabel"
	return label


func _show(key: String, text: String, color := UITheme.TEXT) -> void:
	if not _values.has(key):  # a row this window doesn't show
		return
	var label: Label = _values[key]
	label.text = text
	UITheme.set_font_color(label, color)


func _bar(parent: Control, style: String) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = style
	bar.show_percentage = false
	bar.custom_minimum_size.y = 12
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
		UITheme.size_button(button, "small")
		button.custom_minimum_size.x = 0
		button.pressed.connect(on_pick.bind(item[0]))
		row.add_child(button)
		store[item[0]] = button
	return row


func _highlight(store: Dictionary, chosen: String) -> void:
	for id in store:
		store[id].theme_type_variation = "ChipOnButton" if id == chosen else "ChipButton"


func _body(text: String) -> Label:
	return UITheme.label(text)


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
		return UITheme.GOOD
	if value < -0.05:
		return UITheme.BAD
	return UITheme.TEXT
