class_name UITheme
## The game's Clash-of-Clans-style look, in one place: chunky glossy buttons with dark outlines,
## cream panels, and bold white text with a dark outline that stays readable over anything.
## The artwork is SVG files in assets/ui/ (plain text, easy to restyle); main.gd applies the
## theme to all of the UI, so every Button, Label and panel picks it up automatically.
##
## Colours other than green are "type variations": set a Button's theme_type_variation to
## "YellowButton", "BlueButton", "RedButton" or "GreyButton".

const SKINS := "res://assets/ui/"
const ICONS := "res://assets/ui/icons/"
const BUTTON_COLORS := ["green", "yellow", "blue", "red", "grey"]
const TEXT := Color("fffcf2")
const TEXT_DARK := Color("4b341d")  # body text on cream panels
const OUTLINE := Color("1b130b")
const GOOD := Color("8ff05a")
const BAD := Color("ff6b57")

static var _font: Font


## Builds the theme. Call once (main.gd does).
static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20

	# Labels: white with a thick dark outline and a soft drop shadow.
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", OUTLINE)
	t.set_constant("outline_size", "Label", 8)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.4))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 3)
	t.set_constant("shadow_outline_size", "Label", 8)
	# Plain dark text for reading on cream panels.
	t.set_type_variation("BodyLabel", "Label")
	t.set_color("font_color", "BodyLabel", TEXT_DARK)
	t.set_constant("outline_size", "BodyLabel", 0)
	t.set_constant("shadow_outline_size", "BodyLabel", 0)
	t.set_color("font_shadow_color", "BodyLabel", Color(0, 0, 0, 0))
	t.set_font_size("font_size", "BodyLabel", 17)

	# Buttons: green unless a colour variation is chosen. Grey whenever disabled.
	_button(t, "Button", "green")
	for color in BUTTON_COLORS:
		var variation: String = color.capitalize() + "Button"
		t.set_type_variation(variation, "Button")
		_button(t, variation, color)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.75))
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_constant("outline_size", "Button", 8)
	t.set_constant("h_separation", "Button", 10)
	t.set_font_size("font_size", "Button", 21)
	# Clickable cards (build menu entries).
	t.set_type_variation("CardButton", "Button")
	var card := skin("card", 16, 16, 16, 18)
	card.set_content_margin_all(10)
	card.content_margin_bottom = 14
	t.set_stylebox("normal", "CardButton", card)
	t.set_stylebox("hover", "CardButton", _tinted(card, Color(1.06, 1.06, 1.0)))
	t.set_stylebox("pressed", "CardButton", _pressed(card))
	t.set_stylebox("disabled", "CardButton", _tinted(card, Color(0.82, 0.8, 0.78)))
	t.set_stylebox("focus", "CardButton", StyleBoxEmpty.new())

	# Tabs down a window's right edge (Build Menu). A closed tab is tan; the open one is cream and
	# reaches left over the window's border, so it looks joined to the page.
	var tab := _flat(Color("c9a15e"), OUTLINE, 0, 4, 8)
	tab.border_width_left = 0
	tab.corner_radius_top_right = 18
	tab.corner_radius_bottom_right = 18
	tab.content_margin_left = 14
	var open_tab: StyleBoxFlat = tab.duplicate()
	open_tab.bg_color = Color("f9edcd")
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

	# Windows: cream panel with a dark outline.
	var window := skin("panel", 26, 26, 26, 30)
	window.set_content_margin_all(22)
	window.content_margin_bottom = 28
	t.set_stylebox("panel", "PanelContainer", window)
	t.set_stylebox("panel", "Panel", window)
	# Sunken boxes inside windows (rows of details, queue slots).
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", _flat(Color("e9d3a2"), Color("c7a46a"), 12, 2, 10))
	# Dark see-through pills for the HUD over the map.
	t.set_type_variation("HudPill", "PanelContainer")
	t.set_stylebox("panel", "HudPill", _flat(Color(0.05, 0.04, 0.03, 0.55), Color(0, 0, 0, 0.7), 16, 2, 6))

	# Scroll bars inside windows: a wooden handle on a faint track.
	var track := _flat(Color(0, 0, 0, 0.08), Color(0, 0, 0, 0), 6, 0, 0)
	track.content_margin_left = 5
	track.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", track)
	t.set_stylebox("grabber", "VScrollBar", _flat(Color("b98a4e"), Color("6e4a22"), 6, 2, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _flat(Color("cf9e5c"), Color("6e4a22"), 6, 2, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", _flat(Color("a8783f"), Color("6e4a22"), 6, 2, 0))

	# Progress bars: dark track with a glossy coloured fill. Other fills are variations.
	t.set_stylebox("background", "ProgressBar", _flat(Color("2b2219"), Color("150f09"), 9, 2, 0))
	t.set_stylebox("fill", "ProgressBar", _bar_fill(Color("7fd84a")))
	for pair in [["GoldBar", "f6c13a"], ["BlueBar", "4fb4f5"], ["BrownBar", "d38c45"]]:
		t.set_type_variation(pair[0], "ProgressBar")
		t.set_stylebox("fill", pair[0], _bar_fill(Color(pair[1])))
	return t


## The game font: the built-in font made bolder (a chunky display font could replace it later).
static func font() -> Font:
	if _font == null:
		var bold := FontVariation.new()
		bold.base_font = ThemeDB.fallback_font
		bold.variation_embolden = 0.7
		_font = bold
	return _font


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


## "1,250" style numbers.
static func number(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## Money in dollars: "$1,250", or "-$202" when in debt. Use this wherever cash is shown.
static func money(value: int) -> String:
	return ("-$" if value < 0 else "$") + number(absi(value))


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


static func _button(t: Theme, type: String, color: String) -> void:
	var normal := skin("button_" + color, 16, 20, 16, 16)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 8
	normal.content_margin_bottom = 15
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, _tinted(normal, Color(1.1, 1.1, 1.1)))
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
	var copy := _tinted(box, Color(0.86, 0.86, 0.86))
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
	var box := _flat(color, color.lightened(0.45), 9, 0, 0)
	box.border_width_top = 5  # light top edge fading into the colour: a glossy look
	box.border_blend = true
	return box
