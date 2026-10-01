class_name LineChart
extends Control
## A simple line chart over time for the Statistics window. Give it lines with set_data(); it
## draws a legend (with each line's latest value), three faint gridlines from 0, time labels,
## and, while the pointer is over it (or a finger drags across it), a crosshair with the values
## at that moment. Only draws numbers it is handed; it works nothing out about the game.

## Line colours in a fixed order, checked to stay tell-apart-able for colour-blind players.
## A line keeps its colour whatever else is shown (e.g. Wheat is always the first colour).
const COLORS := [Color("2a78d6"), Color("eb6834"), Color("1baf7a"), Color("eda100"),
	Color("e87ba4"), Color("008300"), Color("4a3aa7"), Color("e34948")]
const SURFACE := Color("fbf6ea")
const BORDER := Color("c7a46a")
const GRID := Color("e8dcc2")
const INK := Color("4b341d")
const MUTED := Color("8a7556")
const LEGEND_HEIGHT := 28.0
const PAD_LEFT := 50.0
const PAD_RIGHT := 16.0
const PAD_BOTTOM := 26.0

## [{"name": String, "color": int (index into COLORS), "points": Array of Vector2(time, value)}]
var lines: Array = []
var t_from := 0.0
var t_to := 1.0
var unit := ""  # added after values, e.g. "/min"
var decimals := 0
var empty_text := "Not enough data yet."

var _hover_x := -1.0
var _frame := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS  # wheel scrolling still reaches the window
	_frame.bg_color = SURFACE
	_frame.border_color = BORDER
	_frame.set_border_width_all(2)
	_frame.set_corner_radius_all(10)
	_frame.anti_aliasing = true
	mouse_exited.connect(func():
		_hover_x = -1.0
		queue_redraw())


func set_data(new_lines: Array, from: float, to: float, value_unit := "", value_decimals := 0) -> void:
	lines = new_lines
	t_from = from
	t_to = maxf(to, from + 1.0)
	unit = value_unit
	decimals = value_decimals
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed):
		_hover_x = event.position.x
		queue_redraw()


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	var font := UITheme.font()
	var plot := Rect2(PAD_LEFT, LEGEND_HEIGHT + 14.0, size.x - PAD_LEFT - PAD_RIGHT, size.y - LEGEND_HEIGHT - 14.0 - PAD_BOTTOM)
	_draw_legend(font)

	var visible_lines: Array = []
	var top := 0.0
	for line in lines:
		var pts: Array = line.points.filter(func(p: Vector2): return p.x >= t_from and p.x <= t_to)
		if pts.size() >= 2:
			visible_lines.append({"color": COLORS[int(line.color) % COLORS.size()], "points": pts, "name": line.name})
			for p in pts:
				top = maxf(top, p.y)
	if visible_lines.is_empty():
		draw_string(font, Vector2(0, plot.get_center().y), empty_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, MUTED)
		return

	# Gridlines at 0, half and the top, on a "nice" round scale.
	var y_max := _nice_max(top)
	for i in 3:
		var value := y_max * i / 2.0
		var y := plot.end.y - plot.size.y * i / 2.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID if i > 0 else BORDER, 1.0)
		draw_string(font, Vector2(4, y + 5), _compact(value), HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 10, 13, MUTED)
	# Time labels: start, middle, now.
	var span := t_to - t_from
	for i in 3:
		var x := plot.position.x + plot.size.x * i / 2.0
		var text := "now" if i == 2 else "-" + _ago(span * (2 - i) / 2.0)
		draw_string(font, Vector2(x - 40, size.y - 8), text, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, MUTED)

	var to_screen := func(p: Vector2) -> Vector2:
		return Vector2(plot.position.x + (p.x - t_from) / span * plot.size.x, plot.end.y - p.y / y_max * plot.size.y)
	for line in visible_lines:
		var screen := PackedVector2Array()
		for p in line.points:
			screen.append(to_screen.call(p))
		draw_polyline(screen, line.color, 2.0, true)
		_dot(screen[-1], line.color)

	if _hover_x >= plot.position.x and _hover_x <= plot.end.x:
		_draw_hover(font, plot, visible_lines, to_screen)


## Legend along the top: a colour swatch, the name and the latest value of each line.
func _draw_legend(font: Font) -> void:
	var x := 12.0
	for line in lines:
		var color: Color = COLORS[int(line.color) % COLORS.size()]
		draw_rect(Rect2(x, 10, 12, 12), color)
		x += 17.0
		var latest := "–"
		if not line.points.is_empty():
			latest = _format(line.points[-1].y)
		var text := "%s %s" % [line.name, latest]
		draw_string(font, Vector2(x, 21), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0


## Crosshair at the point nearest the pointer, with a box listing every line's value there.
func _draw_hover(font: Font, plot: Rect2, visible_lines: Array, to_screen: Callable) -> void:
	var t := t_from + (_hover_x - plot.position.x) / plot.size.x * (t_to - t_from)
	var rows: Array = []
	var x := -1.0
	for line in visible_lines:
		var nearest: Vector2 = line.points[0]
		for p in line.points:
			if absf(p.x - t) < absf(nearest.x - t):
				nearest = p
		var at: Vector2 = to_screen.call(nearest)
		if x < 0.0:
			x = at.x
			t = nearest.x
		rows.append({"color": line.color, "text": "%s: %s" % [line.name, _format(nearest.y)], "at": at})
	draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), MUTED, 1.0)
	for row in rows:
		_dot(row.at, row.color)
	var title := "now" if t_to - t < 30.0 else "%s ago" % _ago(t_to - t)
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	for row in rows:
		width = maxf(width, font.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0)
	var box := Rect2(0, plot.position.y + 4, width + 16, 24 + rows.size() * 20)
	box.position.x = x + 12 if x + 12 + box.size.x < size.x - 4 else x - 12 - box.size.x
	draw_rect(box, Color(SURFACE, 0.96))
	draw_rect(box, BORDER, false, 1.0)
	draw_string(font, box.position + Vector2(8, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	for i in rows.size():
		var y := box.position.y + 24 + i * 20
		draw_rect(Rect2(box.position.x + 8, y + 3, 10, 10), rows[i].color)
		draw_string(font, Vector2(box.position.x + 26, y + 13), rows[i].text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)


## An 8px marker with a ring of the background colour, so it stands clear of the line.
func _dot(at: Vector2, color: Color) -> void:
	draw_circle(at, 6.0, SURFACE, true, -1.0, true)
	draw_circle(at, 4.0, color, true, -1.0, true)


func _format(value: float) -> String:
	if decimals > 0:
		return ("%." + str(decimals) + "f%s") % [value, unit]
	return UITheme.number(roundi(value)) + unit


## Short axis numbers: 950, 1.2k, 15k.
func _compact(value: float) -> String:
	if value >= 10000.0:
		return "%dk" % roundi(value / 1000.0)
	if value >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	if decimals > 0 and value < 10.0 and value != roundf(value):
		return "%.1f" % value
	return str(roundi(value))


## "45m", "2h", "1h 30m": for time labels.
static func _ago(seconds: float) -> String:
	var m := roundi(seconds / 60.0)
	if m < 60:
		return "%dm" % maxi(m, 1)
	if m % 60 == 0:
		return "%dh" % (m / 60)
	return "%dh %dm" % [m / 60, m % 60]


## The next round number at or above `value` (1, 2, 2.5, 5 x 10^n), so gridlines land on tidy values.
static func _nice_max(value: float) -> float:
	if value <= 0.0:
		return 1.0
	var magnitude := pow(10.0, floorf(log(value) / log(10.0)))
	for step in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if step * magnitude >= value:
			return step * magnitude
	return 10.0 * magnitude
