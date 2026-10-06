class_name UITheme
## The game's look, in one place: a warm, cosy cartoon style ("Honey & cream"). Cream paper
## windows with soft caramel outlines, a honey title ribbon on every window, chunky rounded
## buttons, and the rounded Fredoka font (assets/fonts/, SIL Open Font License).
## The artwork is SVG files in assets/ui/ (plain text, easy to restyle); main.gd applies the
## theme to all of the UI, so every Button, Label and panel picks it up automatically.
##
## Buttons all have the same shape; their colour says what they do (set theme_type_variation):
##   "" (honey)       a normal action
##   "GoButton"       go / start / collect (green)
##   "DangerButton"   demolish, cancel, can't be undone (coral red)
##   "BackButton"     back / no / can't do it yet (warm grey)
##   "ChipButton" / "ChipOnButton"   one choice out of several; the picked one is "On" (honey)
## Make buttons with UITheme.button(), which also gives them one of three sizes.
##
## Text styles (Label theme_type_variation): "" or "BodyLabel" (brown body text), "SmallLabel",
## "HeadingLabel", "BigLabel", "TitleLabel" (white, on the title ribbon) and "OutlineLabel"
## (white with an outline, for text straight over the map).

const SKINS := "res://assets/ui/"
const ICONS := "res://assets/ui/icons/"
const FONT_FILE := "res://assets/fonts/Fredoka.ttf"

# Palette.
const CREAM := Color("fff8e9")
const SAND := Color("f7e5c1")
const SAND_EDGE := Color("e0be83")
const CARAMEL := Color("d9a066")
const BROWN := Color("8a5a2b")  # window and pill outlines
const HONEY := Color("f6b13f")
const HONEY_DARK := Color("8e5312")
const TEXT := Color("fffcf2")  # white text (on buttons, the ribbon, over the map)
const TEXT_DARK := Color("5a3618")  # body text on cream
const TEXT_MUTED := Color("85623f")  # small notes
const HEADING := Color("8e4f14")
const OUTLINE := Color("4a2a12")  # outlines over the map: name tags, bubbles, floating numbers
const GOOD := Color("9cf06a")  # good news over the map
const BAD := Color("ff7a63")  # bad news over the map
const GOOD_TEXT := Color("3f8a2a")  # good news on cream
const BAD_TEXT := Color("c23b2c")  # bad news / warnings on cream
const WARN_TEXT := Color("ffd166")  # "not quite right" over the map
const SELECTED := Color("f6b13f")  # the ring around the chosen card
## Dims the map behind an open window.
const DIM := Color(0.22, 0.12, 0.04, 0.4)

# Text sizes: every label uses one of these (through its variation).
const SIZE_SMALL := 15
const SIZE_BODY := 18
const SIZE_HEADING := 21
const SIZE_BIG := 26
const SIZE_TITLE := 30

## Button sizes: minimum width and height, and font size.
const SIZES := {
	"small": {"min": Vector2(64, 44), "font": 17},
	"normal": {"min": Vector2(150, 52), "font": 20},
	"big": {"min": Vector2(240, 60), "font": 23},
}
## Round buttons: icon-only ones (close, ✓, ✗) and the building action bar's.
const ROUND_ICON_SIZE := 56.0
const ROUND_ACTION_SIZE := 84.0

## Button colours: variation -> [skin, text colour, text outline colour ("" = no outline)].
## Light buttons get dark brown text; the strong green and red ones white text with an outline.
const BUTTONS := {
	"Button": ["honey", "6b3a0e", ""],
	"GoButton": ["green", "fffcf2", "2f6b27"],
	"DangerButton": ["red", "fffcf2", "8c2c27"],
	"BackButton": ["grey", "5a4a38", ""],
	"ChipOnButton": ["honey", "6b3a0e", ""],
	"ChipButton": ["chip", "5a3618", ""],
}

static var _font: Font
static var _bold: Font


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
	# Almost every label sits on a cream window, so plain brown text is the default.
	t.set_color("font_color", "Label", TEXT_DARK)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	t.set_type_variation("BodyLabel", "Label")
	_label_style(t, "SmallLabel", SIZE_SMALL, TEXT_MUTED)
	_label_style(t, "HeadingLabel", SIZE_HEADING, HEADING, true)
	_label_style(t, "BigLabel", SIZE_BIG, TEXT_DARK, true)
	_label_style(t, "TitleLabel", SIZE_TITLE, TEXT, true)
	t.set_color("font_outline_color", "TitleLabel", HONEY_DARK)
	t.set_constant("outline_size", "TitleLabel", 9)
	# White text with a soft brown outline and shadow: readable over the map.
	_label_style(t, "OutlineLabel", 20, TEXT, true)
	t.set_color("font_outline_color", "OutlineLabel", OUTLINE)
	t.set_constant("outline_size", "OutlineLabel", 8)
	t.set_color("font_shadow_color", "OutlineLabel", Color(OUTLINE, 0.35))
	t.set_constant("shadow_offset_x", "OutlineLabel", 0)
	t.set_constant("shadow_offset_y", "OutlineLabel", 3)
	t.set_constant("shadow_outline_size", "OutlineLabel", 8)
	# Tooltips: a little cream note.
	t.set_stylebox("panel", "TooltipPanel", _flat(CREAM, BROWN, 10, 2, 8))
	t.set_color("font_color", "TooltipLabel", TEXT_DARK)
	t.set_font_size("font_size", "TooltipLabel", 16)


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
	for variation in BUTTONS:
		if variation != "Button":
			t.set_type_variation(variation, "Button")
		var spec: Array = BUTTONS[variation]
		_button(t, variation, spec[0])
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(state, variation, Color(spec[1]))
		t.set_constant("outline_size", variation, 5 if spec[2] != "" else 0)
		if spec[2] != "":
			t.set_color("font_outline_color", variation, Color(spec[2]))
		# Disabled buttons all turn grey: keep their text readable on it.
		t.set_color("font_disabled_color", variation, Color(1, 1, 1, 0.9) if spec[2] != "" else Color("5a4a38", 0.6))

	# Clickable cards (build menu entries).
	t.set_type_variation("CardButton", "Button")
	var card := skin("card", 16, 16, 16, 18)
	card.set_content_margin_all(10)
	card.content_margin_bottom = 14
	t.set_stylebox("normal", "CardButton", card)
	t.set_stylebox("hover", "CardButton", _tinted(card, Color(1.05, 1.03, 0.96)))
	t.set_stylebox("pressed", "CardButton", _pressed(card))
	t.set_stylebox("disabled", "CardButton", _tinted(card, Color(0.85, 0.82, 0.78)))
	t.set_stylebox("focus", "CardButton", StyleBoxEmpty.new())
	# The honey ring around the chosen card (a Panel laid over it).
	t.set_type_variation("CardRing", "Panel")
	var ring := _flat(Color(0, 0, 0, 0), SELECTED, 16, 4, 0)
	ring.draw_center = false
	ring.expand_margin_left = 3
	ring.expand_margin_right = 3
	ring.expand_margin_top = 3
	ring.expand_margin_bottom = 1
	t.set_stylebox("panel", "CardRing", ring)

	# Tabs down a window's right edge (Build Menu). A closed tab is sand; the open one is cream and
	# reaches left over the window's border, so it looks joined to the page.
	var tab := _flat(Color("f2d49b"), BROWN, 0, 3, 8)
	tab.border_width_left = 0
	tab.corner_radius_top_right = 18
	tab.corner_radius_bottom_right = 18
	tab.content_margin_left = 14
	var open_tab: StyleBoxFlat = tab.duplicate()
	open_tab.bg_color = Color("fdf1d9")
	open_tab.expand_margin_left = 12
	for pair in [["SideTab", tab], ["SideTabOpen", open_tab]]:
		t.set_type_variation(pair[0], "Button")
		t.set_stylebox("normal", pair[0], pair[1])
		t.set_stylebox("pressed", pair[0], pair[1])
		t.set_stylebox("focus", pair[0], StyleBoxEmpty.new())
		var hover: StyleBoxFlat = pair[1].duplicate()
		hover.bg_color = hover.bg_color.lightened(0.15)
		t.set_stylebox("hover", pair[0], hover)
	t.set_stylebox("hover", "SideTabOpen", open_tab)


static func _panels(t: Theme) -> void:
	# Windows: cream paper with a caramel rim.
	var window := skin("panel", 26, 26, 26, 30)
	window.set_content_margin_all(22)
	window.content_margin_bottom = 28
	t.set_stylebox("panel", "PanelContainer", window)
	t.set_stylebox("panel", "Panel", window)
	# The honey ribbon across the top of every window (title + close button).
	t.set_type_variation("TitleBar", "PanelContainer")
	var ribbon := skin("title_bar", 24, 30, 24, 26)
	ribbon.content_margin_left = 22
	ribbon.content_margin_right = 8
	ribbon.content_margin_top = 4
	ribbon.content_margin_bottom = 10
	t.set_stylebox("panel", "TitleBar", ribbon)
	# Sunken boxes inside windows (sections, rows of details).
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", _flat(SAND, SAND_EDGE, 14, 2, 12))
	# Cream bubbles over the map: the HUD numbers and the short messages.
	t.set_type_variation("HudPill", "PanelContainer")
	var pill := _flat(Color(CREAM, 0.97), BROWN, 18, 3, 6)
	pill.content_margin_left = 10
	pill.content_margin_right = 10
	pill.shadow_color = Color(0.48, 0.29, 0.12, 0.3)
	pill.shadow_size = 3
	pill.shadow_offset = Vector2(0, 3)
	t.set_stylebox("panel", "HudPill", pill)
	# Text boxes (developer tools).
	var field := _flat(Color("fffdf6"), Color("b98a52"), 12, 2, 10)
	var focused := field.duplicate()
	focused.border_color = HONEY
	focused.set_border_width_all(3)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", focused)
	t.set_color("font_color", "LineEdit", TEXT_DARK)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXT_MUTED, 0.7))
	t.set_color("caret_color", "LineEdit", TEXT_DARK)


static func _bars(t: Theme) -> void:
	# Scroll bars inside windows: a caramel handle on a faint track.
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := _flat(Color(BROWN, 0.1), Color(0, 0, 0, 0), 7, 0, 0)
		track.set_content_margin_all(5)
		t.set_stylebox("scroll", bar, track)
		t.set_stylebox("grabber", bar, _flat(CARAMEL, BROWN, 7, 2, 0))
		t.set_stylebox("grabber_highlight", bar, _flat(CARAMEL.lightened(0.15), BROWN, 7, 2, 0))
		t.set_stylebox("grabber_pressed", bar, _flat(CARAMEL.darkened(0.1), BROWN, 7, 2, 0))

	# Sliders (amount pickers): a sand track that fills with honey up to the handle.
	var groove := _flat(Color("ead6b0"), Color("b98a52"), 6, 2, 0)
	groove.content_margin_top = 4
	groove.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", groove)
	t.set_stylebox("grabber_area", "HSlider", _flat(HONEY, Color("b98a52"), 6, 2, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(HONEY.lightened(0.15), Color("b98a52"), 6, 2, 0))

	# Progress bars: a sand track with a soft coloured fill. Other fills are variations.
	t.set_stylebox("background", "ProgressBar", _flat(Color("ead6b0"), Color("b98a52"), 9, 2, 0))
	t.set_stylebox("fill", "ProgressBar", _bar_fill(Color("8cd267")))
	for pair in [["GoldBar", "f7c548"], ["BlueBar", "7cc4f0"], ["BrownBar", "d9a066"], ["GreenBar", "8cd267"], ["RedBar", "f07f6e"]]:
		t.set_type_variation(pair[0], "ProgressBar")
		t.set_stylebox("fill", pair[0], _bar_fill(Color(pair[1])))


## The game font: Fredoka, medium weight. Symbols it doesn't have (→ ✓) come from Godot's own font.
static func font() -> Font:
	if _font == null:
		_font = _fredoka(500)
	return _font


## Bold Fredoka, for titles, headings and buttons.
static func bold_font() -> Font:
	if _bold == null:
		_bold = _fredoka(700)
	return _bold


static func _fredoka(weight: int) -> Font:
	var weighted := FontVariation.new()
	weighted.base_font = load(FONT_FILE)
	weighted.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	weighted.fallbacks = [ThemeDB.fallback_font]
	return weighted


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


## The honey ribbon with a window's title, and a round red close button at its right end.
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
	var close := RoundButton.make("red", "close", "", ROUND_ICON_SIZE)
	close.button.tooltip_text = "Close"
	row.add_child(close)
	return {"bar": bar, "label": title, "close": close}


## A window (or bar) pops in with a little bounce.
static func pop_in(control: Control, from := 0.85) -> void:
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2(from, from)
	control.modulate.a = 0.0
	var pop := control.create_tween().set_parallel()
	pop.tween_property(control, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(control, "modulate:a", 1.0, 0.12)


## An icon from assets/ui/icons/, or the plain item icon if that one doesn't exist yet.
static func icon(icon_name: String) -> Texture2D:
	var path := ICONS + icon_name + ".svg"
	return load(path) if ResourceLoader.exists(path) else load(ICONS + "item.svg")


## A 9-patch style from an SVG skin: the corners keep their shape however big the box gets.
static func skin(skin_name: String, left: float, top: float, right: float, bottom: float) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(SKINS + skin_name + ".svg")
	box.texture_margin_left = left
	box.texture_margin_top = top
	box.texture_margin_right = right
	box.texture_margin_bottom = bottom
	return box


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

static func _button(t: Theme, type: String, color: String) -> void:
	var normal := skin("button_" + color, 18, 20, 18, 18)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 6
	normal.content_margin_bottom = 12
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, _tinted(normal, Color(1.07, 1.07, 1.07)))
	t.set_stylebox("pressed", type, _pressed(normal))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	var grey: StyleBoxTexture = normal.duplicate()
	grey.texture = load(SKINS + "button_grey.svg")
	t.set_stylebox("disabled", type, grey)


static func _tinted(box: StyleBoxTexture, tint: Color) -> StyleBoxTexture:
	var copy: StyleBoxTexture = box.duplicate()
	copy.modulate_color = tint
	return copy


## Pressed look: a little darker, and the label sinks 3 pixels as if pushed in.
static func _pressed(box: StyleBoxTexture) -> StyleBoxTexture:
	var copy := _tinted(box, Color(0.9, 0.88, 0.86))
	copy.content_margin_top += 3
	copy.content_margin_bottom -= 3
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


static func _bar_fill(color: Color) -> StyleBoxFlat:
	var box := _flat(color, color.lightened(0.5), 9, 0, 0)
	box.border_width_top = 4  # light top edge fading into the colour: a soft shine
	box.border_blend = true
	return box
