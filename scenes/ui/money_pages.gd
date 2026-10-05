extends RefCounted
## The money parts of the Statistics window (plan.md §5.19):
## - the Balance tab: what the company owns and owes, its value, and where that value came from
## - on the Cash flow tab: the Cash check (start + money in − money out = cash now) and the
##   Money log (money in and out per 30-minute block)
## Built with the window's own helpers (_section, _value_row, _show, _body), so they look the
## same. Every number comes from Economy; this only shows them.

const NAMES := {"rent": "Rent", "demolish": "Demolish refunds", "batch_refunds": "Cancelled batches",
	"construction": "Construction", "roads": "Roads", "wages": "Wages", "water": "Water", "power": "Power", "tax": "Sales tax",
	"switch_fees": "Switching products", "purchases": "Trading Post purchases"}
const NOTE_SIZE := 15

var _panel  # the Statistics window (stats_panel.gd)
var _log_rows: VBoxContainer  # the finished blocks of the money log, rebuilt when a block ends
var _log_shown := ""  # which finished blocks are on screen, so they're only rebuilt when it changes


func _init(panel) -> void:
	_panel = panel


# --- Balance tab ---------------------------------------------------------------

func build_balance(page: VBoxContainer) -> void:
	var own: VBoxContainer = _panel._section(page, "What you own")
	_panel._value_row(own, "Cash", "bs_cash")
	_panel._value_row(own, "Shop sales not paid yet", "bs_receivable")
	for res in GameData.resources:
		_panel._value_row(own, GameData.resources[res].name, "bs_goods_" + res)
	_panel._value_row(own, "Batches being made (at cost)", "bs_in_production")
	_panel._value_row(own, "Buildings", "bs_buildings")
	_panel._value_row(own, "Being built / upgrading", "bs_being_built")
	_panel._value_row(own, "Roads", "bs_roads")
	_panel._value_row(own, "Total owned", "bs_owned")
	var owe: VBoxContainer = _panel._section(page, "What you owe")
	_panel._value_row(owe, "Debt (cash below $0)", "bs_debt")
	_panel._value_row(owe, "Water bill so far", "bs_water")
	_panel._value_row(owe, "Power bill so far", "bs_power")
	_panel._value_row(owe, "Total owed", "bs_owed")
	var value: VBoxContainer = _panel._section(page, "Company value")
	value.add_child(_panel._value("bs_value"))
	_panel._values.bs_value.add_theme_font_size_override("font_size", 26)
	_panel._value_row(value, "Starting capital", "bs_capital")
	_panel._value_row(value, "Profit kept since the start", "bs_profit")
	page.add_child(_note("Company value = what you own − what you owe. Goods count at what they cost to make, buildings and roads at the price paid (the starter buildings and roads at their build cost, as part of the starting capital). Shop sales not paid yet = goods sold from Supermarket shelves, paid (after sales tax) when the shelf sells out or is taken down. Profit kept = how much the company has grown since the start."))


func refresh_balance() -> void:
	var sheet := Economy.balance_sheet()
	_panel._show("bs_cash", UITheme.money(int(sheet.cash)))
	_panel._show("bs_receivable", UITheme.money(int(sheet.receivable)))
	for res in GameData.resources:
		var goods: Dictionary = sheet.goods.get(res, {"qty": 0, "value": 0})
		var text := UITheme.money(int(goods.value))
		if int(goods.qty) > 0:
			text = "%s × %s = %s" % [UITheme.number(int(goods.qty)), UITheme.price(roundi(float(goods.value) / int(goods.qty))), text]
		_panel._show("bs_goods_" + res, text)
	_panel._show("bs_in_production", UITheme.money(int(sheet.in_production)))
	_panel._show("bs_buildings", UITheme.money(int(sheet.buildings)))
	_panel._show("bs_being_built", UITheme.money(int(sheet.being_built)))
	_panel._show("bs_roads", UITheme.money(int(sheet.get("roads", 0))))
	_panel._show("bs_owned", UITheme.money(int(sheet.total_owned)), _panel.UP)
	_panel._show("bs_debt", UITheme.money(int(sheet.debt)), _panel.DOWN if int(sheet.debt) > 0 else LineChart.INK)
	_panel._show("bs_water", UITheme.money(int(sheet.water_due)))
	_panel._show("bs_power", UITheme.money(int(sheet.get("power_due", 0))))
	_panel._show("bs_owed", UITheme.money(int(sheet.total_owed)), _panel.DOWN if int(sheet.total_owed) > 0 else LineChart.INK)
	_panel._show("bs_value", UITheme.money(int(sheet.company_value)), _panel.DOWN if int(sheet.company_value) < 0 else LineChart.INK)
	_panel._show("bs_capital", UITheme.money(int(sheet.capital)))
	_panel._show("bs_profit", _signed(int(sheet.profit_kept)), _panel._signed_color(roundi(int(sheet.profit_kept) / 100.0)))


# --- Cash check (Cash flow tab) ------------------------------------------------------

func build_cash_check(page: VBoxContainer) -> void:
	var box: VBoxContainer = _panel._section(page, "Cash check")
	_panel._value_row(box, "Starting cash", "cc_start")
	_panel._value_row(box, "+ All money in", "cc_in")
	_panel._value_row(box, "− All money out", "cc_out")
	_panel._value_row(box, "± Dev tools", "cc_dev")
	_panel._value_row(box, "= Should have", "cc_expected")
	_panel._value_row(box, "Cash now", "cc_cash")
	box.add_child(_panel._value("cc_result"))


func refresh_cash_check() -> void:
	var check := Economy.cash_check()
	_panel._show("cc_start", UITheme.money(int(check.start)))
	_panel._show("cc_in", "+" + UITheme.money(int(check.money_in)), _panel.UP)
	_panel._show("cc_out", "-" + UITheme.money(int(check.money_out)), _panel.DOWN)
	_panel._values.cc_dev.get_parent().visible = int(check.dev) != 0  # only in test builds
	_panel._show("cc_dev", _signed(int(check.dev)))
	_panel._show("cc_expected", UITheme.money(int(check.expected)))
	_panel._show("cc_cash", UITheme.money(int(check.cash)))
	if check.ok:
		_panel._show("cc_result", "It adds up: every cent is accounted for.", _panel.UP)
	else:
		_panel._show("cc_result", "Doesn't add up: %s unaccounted for. Please report this bug." % UITheme.price(int(check.cash) - int(check.expected)), _panel.DOWN)


# --- Money log (Cash flow tab) -----------------------------------------------------

func build_money_log(page: VBoxContainer) -> void:
	var minutes := roundi(float(GameData.config.get("money_log_minutes", 30)))
	var box: VBoxContainer = _panel._section(page, "Money log (every %d min)" % minutes)
	# The block still running: its labels are updated in place, as money comes and goes.
	_panel._value_row(box, "Now", "log_now")
	box.add_child(_detail("log_now_in"))
	box.add_child(_detail("log_now_out"))
	_log_rows = VBoxContainer.new()
	_log_rows.add_theme_constant_override("separation", 6)
	box.add_child(_log_rows)


func refresh_money_log() -> void:
	var rows := Economy.money_log()
	var now := TimeService.now()
	var finished := rows
	if not rows.is_empty() and rows[0].open:
		var row: Dictionary = rows[0]
		finished = rows.slice(1)
		_panel._values.log_now.get_parent().get_child(0).text = "Last %s (still running)" % LineChart._ago(now - float(row.from))
		_panel._show("log_now", _signed(int(row.net)), _panel._signed_color(roundi(int(row.net) / 100.0)))
		_panel._show("log_now_in", "In: " + _list(_money_in(row)), _panel.UP)
		_panel._show("log_now_out", "Out: " + _list(_money_out(row)), _panel.DOWN)
	else:
		_panel._values.log_now.get_parent().get_child(0).text = "Now"
		_panel._show("log_now", "$0")
	for key in ["log_now_in", "log_now_out"]:
		_panel._values[key].visible = not rows.is_empty() and rows[0].open
	# Finished blocks don't change: rebuild them only when one is added (or old ones drop off).
	var shown := "%d %s" % [finished.size(), finished[0].to if not finished.is_empty() else 0.0]
	if shown == _log_shown:
		return
	_log_shown = shown
	for child in _log_rows.get_children():
		child.queue_free()
	if finished.is_empty():
		_log_rows.add_child(_note("Each block of %d minutes shows up here once it's over." % roundi(float(GameData.config.get("money_log_minutes", 30)))))
	var every := float(GameData.config.get("money_log_minutes", 30)) * 60.0
	for row in finished:
		var line := HBoxContainer.new()
		_log_rows.add_child(line)
		var when: Label = _panel._body(_when(row, now, every))
		when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(when)
		var net: Label = _panel._body(_signed(int(row.net)))
		net.add_theme_color_override("font_color", _panel._signed_color(roundi(int(row.net) / 100.0)))
		line.add_child(net)
		var money_in := _money_in(row)
		var money_out := _money_out(row)
		if not money_in.is_empty():
			_log_rows.add_child(_note("In: " + _list(money_in)))
		if not money_out.is_empty():
			_log_rows.add_child(_note("Out: " + _list(money_out)))


## "2h ago – 1h 30m ago", or "While you were away (6h)" for a block that covers time away.
func _when(row: Dictionary, now: float, every: float) -> String:
	var length := float(row.to) - float(row.from)
	if length > every * 1.5:
		return "While you were away (%s), until %s ago" % [LineChart._ago(length), LineChart._ago(now - float(row.to))]
	return "%s ago – %s ago" % [LineChart._ago(now - float(row.from)), LineChart._ago(now - float(row.to))]


## Money in, as [[name, cents]]: sales by item, then the other sources.
func _money_in(row: Dictionary) -> Array:
	var out := []
	for res in row.sales_by_item:
		out.append([GameData.resources.get(res, {}).get("name", res), int(row.sales_by_item[res])])
	for key in row.income:
		if key != "sales":
			out.append([NAMES.get(key, key.capitalize()), int(row.income[key])])
	if row.dev > 0:
		out.append(["Dev tools", int(row.dev)])
	return out


## Money out, as [[name, cents]].
func _money_out(row: Dictionary) -> Array:
	var out := []
	for key in row.spending:
		out.append([NAMES.get(key, key.capitalize()), int(row.spending[key])])
	if row.dev < 0:
		out.append(["Dev tools", -int(row.dev)])
	return out


## "Bread $900, Rent $300", or "nothing".
func _list(items: Array) -> String:
	var parts := []
	for item in items:
		parts.append("%s %s" % [item[0], UITheme.money(item[1])])
	return "nothing" if parts.is_empty() else ", ".join(parts)


# --- Helpers ------------------------------------------------------------------

## "+$1,200" / "-$300" / "$0", by the whole dollars shown (a few cents never show as "-$0").
func _signed(cents: int) -> String:
	var whole := roundi(cents / 100.0)
	return ("+" if whole > 0 else "") + UITheme.money(cents)


## A small explanation line, wrapped to the window's width.
func _note(text: String) -> Label:
	var label: Label = _panel._body(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _panel.WIDTH - 90
	label.add_theme_font_size_override("font_size", NOTE_SIZE)
	label.modulate.a = 0.8
	return label


## A note whose text refresh_money_log sets (remembered under `key`).
func _detail(key: String) -> Label:
	var label := _note("")
	_panel._values[key] = label
	return label
