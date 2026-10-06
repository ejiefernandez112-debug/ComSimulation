class_name UITheme
## The game's look, in one place: "Harbor Glass", a calm, realistic city-builder style (the user
## asked for something like Cities: Skylines II, 2026-10-06). Dark slate glass panels with a thin
## light rim and small rounded corners, one blue highlight colour, white line icons and the Overpass
## font (assets/fonts/, SIL Open Font License). Everything is drawn by Godot (no picture files), so
## a colour change here restyles the whole game. main.gd applies the theme to all of the UI, so
## every Button, Label and panel picks it up automatically.
##
## Buttons all have the same shape; their colour says what they do (set theme_type_variation):
##   "" (glass)       a normal action
##   "GoButton"       go / start / collect (blue, the one strong colour)
##   "DangerButton"   demolish, can't be undone (red)
##   "BackButton"     back / no / can't do it yet (just an outline)
##   "IconButton"     no box at all until pointed at: close ✕, the bottom toolbar
##   "ChipButton" / "ChipOnButton"   one choice out of several; the picked one is "On" (blue)
## Make buttons with UITheme.button(), which also gives them one of three sizes.
##
## Text styles (Label theme_type_variation): "" or "BodyLabel" (body text), "SmallLabel" (grey
## notes), "HeadingLabel", "BigLabel", "TitleLabel" (window titles) and "OutlineLabel" (white with
## a dark outline, for text straight over the map).

const ICONS := "res://assets/ui/icons/"
const FONT_FILE := "res://assets/fonts/Overpass-Medium.ttf"
const BOLD_FONT_FILE := "res://assets/fonts/Overpass-Bold.ttf"

# Palette.
const GLASS := Color(0.075, 0.102, 0.141, 0.93)  # windows, bars and the HUD: dark slate glass
const GLASS_HIGH := Color(0.106, 0.141, 0.188, 0.97)  # tooltips and side tabs: a shade lighter
const EDGE := Color(1, 1, 1, 0.09)  # the thin light rim around glass
const EDGE_STRONG := Color(1, 1, 1, 0.17)  # outlines of empty buttons, chips and text boxes
const WELL := Color(0, 0, 0, 0.28)  # sunken boxes inside windows
const HOVER := Color(1, 1, 1, 0.08)  # under the pointer
const TEXT := Color("eef3f8")  # body text, titles and numbers
const TEXT_DIM := Color("a9b6c5")  # small notes and captions
const TEXT_FAINT := Color("74849a")  # hints and empty text boxes
const ACCENT := Color("2f9cf0")  # the one highlight colour: Go buttons, picked choices, selection
const ACCENT_HIGH := Color("5bb6ff")
const GOOD := Color("5fd07a")  # good news (in windows and over the map)
const WARN := Color("f2b23e")  # "not quite right"
const BAD := Color("f0605a")  # bad news / warnings
const OUTLINE := Color("0b1118")  # dark outline for text and signs straight over the map
## Dims the map behind a window in the middle of the screen (and phone sheets).
const DIM := Color(0.02, 0.04, 0.07, 0.42)
## Behind a window docked at the side: lighter, so the map stays in view.
const DIM_LIGHT := Color(0.02, 0.04, 0.07, 0.16)
const RADIUS := 4  # buttons
const WINDOW_RADIUS := 6  # windows, cards and the HUD

# Text sizes: every label uses one of these (through its variation).
const SIZE_SMALL := 14
const SIZE_BODY := 17
const SIZE_HEADING := 19
const SIZE_BIG := 23
const SIZE_TITLE := 21

## Button sizes: minimum width and height, and font size.
const SIZES := {
	"small": {"min": Vector2(64, 40), "font": 15},
	"normal": {"min": Vector2(140, 46), "font": 17},
	"big": {"min": Vector2(220, 54), "font": 19},
}
## Tile buttons (RoundButton): icon-only ones (close ✕, ✓) and the building card's, with a caption.
const ROUND_ICON_SIZE := 44.0
const ROUND_ACTION_SIZE := 64.0

## Button colours: variation -> [fill, rim, text colour]. Filled buttons (Go, Danger, the picked
## chip) light up a little towards the top, like the glass catching the light.
const BUTTONS := {
	"Button": [Color(1, 1, 1, 0.08), EDGE, TEXT],
	"GoButton": [Color("1f86d6"), Color("4fb0f8"), Color.WHITE],
	"DangerButton": [Color("cf433d"), Color("f47770"), Color.WHITE],
	"BackButton": [Color(0, 0, 0, 0), EDGE_STRONG, TEXT_DIM],
	"IconButton": [Color(0, 0, 0, 0), Color(0, 0, 0, 0), TEXT_DIM],
	"ChipOnButton": [Color("1f86d6"), Color("4fb0f8"), Color.WHITE],
	"ChipButton": [Color(0, 0, 0, 0), EDGE_STRONG, TEXT_DIM],
}
const FILLED := ["GoButton", "DangerButton", "ChipOnButton"]
const CHIPS := ["ChipButton", "ChipOnButton"]

static var _font: Font
static var _bold: Font
static var _icons := {}  # icon name -> texture: looked up once (checking the files is slow on phones)


## Builds the theme. Call once (main.gd does).
static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = SIZE_BODY
	_labels(t)
	_buttons(t)
	_panels(t)
	_bars(t)
	return t


static func _labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	t.set_type_variation("BodyLabel", "Label")
	_label_style(t, "SmallLabel", SIZE_SMALL, TEXT_DIM)
	_label_style(t, "HeadingLabel", SIZE_HEADING, TEXT, true)
	_label_style(t, "BigLabel", SIZE_BIG, TEXT, true)
	_label_style(t, "TitleLabel", SIZE_TITLE, TEXT, true)
	# White text with a dark outline and a soft shadow: readable over the map.
	_label_style(t, "OutlineLabel", 18, TEXT, true)
	t.set_color("font_outline_color", "OutlineLabel", OUTLINE)
	t.set_constant("outline_size", "OutlineLabel", 6)
	t.set_color("font_shadow_color", "OutlineLabel", Color(OUTLINE, 0.4))
	t.set_constant("shadow_offset_x", "OutlineLabel", 0)
	t.set_constant("shadow_offset_y", "OutlineLabel", 2)
	t.set_constant("shadow_outline_size", "OutlineLabel", 6)
	# Tooltips: a small glass note.
	t.set_stylebox("panel", "TooltipPanel", _flat(GLASS_HIGH, EDGE_STRONG, RADIUS, 1, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 15)


static func _label_style(t: Theme, variation: String, size: int, color: Color, bold := false) -> void:
	t.set_type_variation(variation, "Label")
	t.set_font_size("font_size", variation, size)
	t.set_color("font_color", variation, color)
	if bold:
		t.set_font("font", variation, bold_font())


static func _buttons(t: Theme) -> void:
	t.set_font("font", "Button", bold_font())
	t.set_font_size("font_size", "Button", SIZES.normal.font)
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 28)  # icons on buttons stay small next to the words
	for variation in BUTTONS:
		if variation != "Button":
			t.set_type_variation(variation, "Button")
		var spec: Array = BUTTONS[variation]
		_button(t, variation, spec[0], spec[1], variation in FILLED, 16 if variation in CHIPS else RADIUS)
		var text: Color = spec[2]
		for state in ["font_color", "font_focus_color"]:
			t.set_color(state, variation, text)
		# Grey text lights up under the pointer.
		for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(state, variation, TEXT if text == TEXT_DIM else text)
		t.set_color("font_disabled_color", variation, Color(TEXT, 0.38))
		t.set_constant("outline_size", variation, 0)

	# Clickable cards (build menu entries): a faint glass tile.
	t.set_type_variation("CardButton", "Button")
	var card := _flat(Color(1, 1, 1, 0.05), EDGE, WINDOW_RADIUS, 1, 8)
	t.set_stylebox("normal", "CardButton", card)
	t.set_stylebox("hover", "CardButton", _filled(card, Color(1, 1, 1, 0.1)))
	t.set_stylebox("pressed", "CardButton", _filled(card, Color(1, 1, 1, 0.03)))
	t.set_stylebox("hover_pressed", "CardButton", _filled(card, Color(1, 1, 1, 0.03)))
	t.set_stylebox("disabled", "CardButton", card)
	t.set_stylebox("focus", "CardButton", StyleBoxEmpty.new())
	# The blue outline around the chosen card (a Panel laid over it), with a faint blue wash.
	t.set_type_variation("CardRing", "Panel")
	var ring := _flat(Color(ACCENT, 0.12), ACCENT_HIGH, WINDOW_RADIUS, 2, 0)
	t.set_stylebox("panel", "CardRing", ring)

	# Tabs down a window's right edge (Build Menu): glass tiles; the open one is blue.
	var tab := _flat(GLASS_HIGH, EDGE, 0, 1, 8)
	tab.border_width_left = 0
	tab.corner_radius_top_right = WINDOW_RADIUS
	tab.corner_radius_bottom_right = WINDOW_RADIUS
	var open_tab := _lit(tab, Color("1f86d6"), Color("4fb0f8"))
	for pair in [["SideTab", tab], ["SideTabOpen", open_tab]]:
		t.set_type_variation(pair[0], "Button")
		t.set_stylebox("normal", pair[0], pair[1])
		t.set_stylebox("pressed", pair[0], pair[1])
		t.set_stylebox("hover_pressed", pair[0], pair[1])
		t.set_stylebox("focus", pair[0], StyleBoxEmpty.new())
		t.set_constant("icon_max_width", pair[0], 30)
	t.set_stylebox("hover", "SideTab", _filled(tab, Color("243041", 0.97)))
	t.set_stylebox("hover", "SideTabOpen", open_tab)


static func _panels(t: Theme) -> void:
	# Windows: dark glass with a thin light rim and a soft shadow underneath.
	var window := _flat(GLASS, EDGE, WINDOW_RADIUS, 1, 16)
	window.content_margin_top = 12
	window.shadow_color = Color(0, 0, 0, 0.35)
	window.shadow_size = 16
	window.shadow_offset = Vector2(0, 6)
	t.set_stylebox("panel", "PanelContainer", window)
	t.set_stylebox("panel", "Panel", window)
	# The strip across the top of every window (title + close button). It reaches out over the
	# window's own padding (expand margins), so its faint band and the line under it run edge to edge.
	t.set_type_variation("TitleBar", "PanelContainer")
	var strip := _flat(Color(1, 1, 1, 0.035), EDGE, 0, 0, 0)
	strip.border_width_bottom = 1
	strip.corner_radius_top_left = WINDOW_RADIUS
	strip.corner_radius_top_right = WINDOW_RADIUS
	strip.expand_margin_left = 16
	strip.expand_margin_right = 16
	strip.expand_margin_top = 12
	strip.content_margin_bottom = 8
	t.set_stylebox("panel", "TitleBar", strip)
	# Sunken boxes inside windows (sections, rows of details).
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", _flat(WELL, EDGE, 5, 1, 10))
	# Small glass boxes over the map: the warehouse chips under the HUD and the short messages.
	t.set_type_variation("HudPill", "PanelContainer")
	var pill := _flat(GLASS, EDGE, 5, 1, 4)
	pill.content_margin_left = 8
	pill.content_margin_right = 10
	pill.shadow_color = Color(0, 0, 0, 0.3)
	pill.shadow_size = 6
	pill.shadow_offset = Vector2(0, 2)
	t.set_stylebox("panel", "HudPill", pill)
	# Glass bars over the map: the HUD's numbers, the bottom toolbar.
	t.set_type_variation("HudBar", "PanelContainer")
	var bar := _flat(GLASS, EDGE, WINDOW_RADIUS, 1, 6)
	bar.content_margin_left = 10
	bar.content_margin_right = 10
	bar.shadow_color = Color(0, 0, 0, 0.32)
	bar.shadow_size = 12
	bar.shadow_offset = Vector2(0, 4)
	t.set_stylebox("panel", "HudBar", bar)
	# Text boxes (developer tools): a dark well that outlines in blue while typing.
	var field := _flat(Color(0, 0, 0, 0.3), EDGE_STRONG, RADIUS, 1, 8)
	field.content_margin_left = 10
	field.content_margin_right = 10
	var focused := _flat(Color(0, 0, 0, 0), ACCENT, RADIUS, 2, 8)
	focused.draw_center = false  # drawn over the normal box
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focused)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT_HIGH)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.35))


static func _bars(t: Theme) -> void:
	# Scroll bars inside windows: a thin light handle on a faint track.
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := _flat(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 4, 0, 4)
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, _flat(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 4, 0, 0))
		t.set_stylebox("grabber_highlight", bar, _flat(Color(1, 1, 1, 0.32), Color(0, 0, 0, 0), 4, 0, 0))
		t.set_stylebox("grabber_pressed", bar, _flat(Color(1, 1, 1, 0.4), Color(0, 0, 0, 0), 4, 0, 0))

	# Sliders (amount pickers): a thin track that fills with blue up to the handle.
	var groove := _flat(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 3, 0, 0)
	groove.content_margin_top = 2
	groove.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", _filled(groove, ACCENT))
	t.set_stylebox("grabber_area_highlight", "HSlider", _filled(groove, ACCENT_HIGH))

	# Progress bars: a faint track with a flat coloured fill (blue). Other fills are variations.
	t.set_stylebox("background", "ProgressBar", _flat(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 3, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _flat(ACCENT, Color(0, 0, 0, 0), 3, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	for pair in [["GoldBar", WARN], ["BlueBar", Color("7cc4f0")], ["BrownBar", Color("c9a26a")], ["GreenBar", GOOD], ["RedBar", BAD]]:
		t.set_type_variation(pair[0], "ProgressBar")
		t.set_stylebox("fill", pair[0], _flat(pair[1], Color(0, 0, 0, 0), 3, 0, 0))


## The game font: Overpass Medium. Symbols it doesn't have (✓) come from Godot's own font.
static func font() -> Font:
	if _font == null:
		_font = _overpass(FONT_FILE)
	return _font


## Overpass Bold, for titles, headings, numbers and buttons.
static func bold_font() -> Font:
	if _bold == null:
		_bold = _overpass(BOLD_FONT_FILE)
	return _bold


static func _overpass(path: String) -> Font:
	var tuned := FontVariation.new()
	tuned.base_font = load(path)
	# Digits all the same width ("tnum"), so numbers that change don't wobble and columns line up.
	tuned.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	# Overpass sits a little high in its line; this nudges it down a pixel so text looks centred
	# in buttons and bars (the line stays the same height).
	tuned.spacing_top = 1
	tuned.spacing_bottom = -1
	tuned.fallbacks = [ThemeDB.fallback_font]
	return tuned


# --- Builders: every screen makes its buttons, labels and boxes with these -----------

## A button in one of the standard sizes ("small", "normal", "big"). variation picks the colour
## (see the top of this file); icon_name is an icon from assets/ui/icons/.
static func button(text: String, variation := "", size := "normal", icon_name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	if icon_name != "":
		b.icon = icon(icon_name)
		b.expand_icon = true
	size_button(b, size)
	return b


## Gives an existing button one of the standard sizes.
static func size_button(b: Button, size: String) -> void:
	var s: Dictionary = SIZES[size]
	b.custom_minimum_size = s.min
	b.add_theme_font_size_override("font_size", s.font)


## Gives a label or button this text colour, but only when it's a different one: setting it counts
## as a theme change, which makes the control and its containers work out their size again (slow
## for screens that refresh many labels every second).
static func set_font_color(control: Control, color: Color) -> void:
	if not control.has_theme_color_override("font_color") or control.get_theme_color("font_color") != color:
		control.add_theme_color_override("font_color", color)


## A label in one of the text styles ("" = body text).
static func label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## The standard text style closest to a font size, so older code that asks for "16" or "20"
## still lands on one of the few sizes every screen shares.
static func style_for(font_size: int) -> String:
	if font_size <= 16:
		return "SmallLabel"
	if font_size <= 19:
		return ""
	if font_size <= 23:
		return "HeadingLabel"
	return "BigLabel"


## Text that wraps onto more lines instead of making its window wider (it needs a width).
static func wrapped(text: String, width: float, variation := "") -> Label:
	var l := label(text, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


## An icon picture of a fixed size.
static func icon_rect(icon_name: String, side: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon(icon_name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The strip across the top of a window: its title, and a close ✕ at the right end.
## Returns {"bar": PanelContainer, "label": Label, "close": RoundButton}.
static func title_bar(text := "") -> Dictionary:
	var bar := PanelContainer.new()
	bar.theme_type_variation = "TitleBar"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var title := label(text, "TitleLabel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	row.add_child(title)
	var close := RoundButton.make("IconButton", "close", "", ROUND_ICON_SIZE)
	close.button.tooltip_text = "Close"
	row.add_child(close)
	return {"bar": bar, "label": title, "close": close}


## A window (or bar) fades in, growing very slightly into place.
static func pop_in(control: Control, from := 0.97) -> void:
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2(from, from)
	control.modulate.a = 0.0
	var pop := control.create_tween().set_parallel()
	pop.tween_property(control, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(control, "modulate:a", 1.0, 0.12)


## An icon from assets/ui/icons/, or the plain item icon if that one doesn't exist yet.
static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := ICONS + icon_name + ".svg"
		_icons[icon_name] = load(path) if ResourceLoader.exists(path) else load(ICONS + "item.svg")
	return _icons[icon_name]


# --- Numbers and times as text -------------------------------------------------------

## "1,250" style numbers.
static func number(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## Money in whole dollars, from CENTS (how the game rules keep it), rounded: 125050 -> "$1,251",
## or "-$202" when in debt. Use this for cash, building costs, totals and wages.
static func money(cents: int) -> String:
	var whole := roundi(absi(cents) / 100.0)
	return ("-$" if cents < 0 and whole > 0 else "$") + number(whole)


## A price per unit, with cents (the only money shown with cents, plan.md §5.12): 53 -> "$0.53".
static func price(cents: int) -> String:
	var whole := absi(cents)
	return ("-$" if cents < 0 else "$") + number(whole / 100) + ".%02d" % (whole % 100)


## Money from an amount in dollars, like the data files and wages per hour use (15.0 -> "$15").
static func dollars(amount: float) -> String:
	return money(roundi(amount * 100.0))


## "2m 05s" / "45s" / "1h 20m" / "2d 03h" for time left (or time away).
static func duration(seconds: float) -> String:
	var s := maxi(ceili(seconds), 0)
	if s >= 86400:
		return "%dd %02dh" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s


## A moment (unix seconds) as the player's local time of day: "6:05 PM" when it's today
## (`now`'s day), else with the weekday, "Tue 6:05 PM". INF = "never".
static func clock(unix: float, now: float) -> String:
	if is_inf(unix):
		return "never"
	var offset := TimeService.utc_offset_seconds()
	var when := Time.get_datetime_dict_from_unix_time(int(unix + offset))
	var today := Time.get_datetime_dict_from_unix_time(int(now + offset))
	var hour := int(when.hour) % 12
	var text := "%d:%02d %s" % [12 if hour == 0 else hour, int(when.minute), "AM" if int(when.hour) < 12 else "PM"]
	if when.year == today.year and when.month == today.month and when.day == today.day:
		return text
	return "%s %s" % [["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(when.weekday)], text]


# --- Style helpers -------------------------------------------------------------------

## One button look: normal, a lighter hover, a darker pressed (its text sinks a pixel, as if
## pushed in) and a faint grey disabled one, which is the same for every colour.
static func _button(t: Theme, type: String, fill: Color, rim: Color, filled: bool, radius: int) -> void:
	var normal := _flat(fill, rim, radius, 1, 6)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	if filled:
		normal = _lit(normal, fill, rim)
		hover = _lit(normal, fill.lightened(0.1), rim.lightened(0.1))
		pressed = _filled(normal, fill.darkened(0.12))
		pressed.border_color = fill
	else:
		hover = _filled(normal, Color(1, 1, 1, fill.a + 0.07))
		pressed = _filled(normal, Color(1, 1, 1, 0.04))
	pressed.content_margin_top += 1
	pressed.content_margin_bottom -= 1
	var disabled := _flat(Color(1, 1, 1, 0.05), EDGE, radius, 1, 6)
	disabled.content_margin_left = 14
	disabled.content_margin_right = 14
	if type == "IconButton":
		disabled.draw_center = false
		disabled.border_color = Color(0, 0, 0, 0)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())


## A copy of a box with another fill colour.
static func _filled(box: StyleBoxFlat, fill: Color) -> StyleBoxFlat:
	var copy: StyleBoxFlat = box.duplicate()
	copy.bg_color = fill
	return copy


## A filled box whose top half catches the light: a lighter top edge that fades into the fill
## (Godot boxes can't hold a real gradient, so a thick top border that blends does it).
static func _lit(box: StyleBoxFlat, fill: Color, light: Color) -> StyleBoxFlat:
	var copy := _filled(box, fill)
	copy.border_color = light
	copy.border_width_top = 20
	copy.border_blend = true
	return copy


static func _flat(fill: Color, border: Color, radius: int, border_width: int, padding: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(padding)
	box.anti_aliasing = true
	return box
