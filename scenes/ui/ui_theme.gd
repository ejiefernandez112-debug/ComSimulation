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
## Between parts of a line use "⋅" (the dot operator), not "·": Overpass draws its own middle dot
## pushed against the next word ("people ·room").
##
## Panels over the map are frosted glass (frost()): the map behind them is blurred, as in the
## mockup. Settings → Frosted glass turns the blur off (phones start with it off); the glass is
## then more solid.

const ICONS := "res://assets/ui/icons/"
const FONT_FILE := "res://assets/fonts/Overpass-Medium.ttf"
const BOLD_FONT_FILE := "res://assets/fonts/Overpass-Bold.ttf"
## The look's colours and sizes live in data/ui_look.json (change them live in the game:
## Developer window → Look). Every setting the file has, by section; tests/check_project.gd checks
## the file against this list. Its "icons" section is extra: {icon name: the icon drawn instead}.
const LOOK_FILE := "res://data/ui_look.json"
const LOOK_KEYS := {
	"colors": ["glass", "glass_solid", "glass_high", "glass_high_solid", "edge", "edge_strong", "well",
		"hover", "text", "text_dim", "text_faint", "accent", "accent_high", "good", "warn", "bad",
		"outline", "dim", "dim_light", "button", "go", "go_rim", "danger", "danger_rim", "chip_on", "chip_on_rim"],
	"shapes": ["button_radius", "chip_radius", "window_radius", "inset_radius", "rim_width",
		"window_padding", "button_padding", "window_shadow"],
	"text": ["small", "body", "heading", "big", "title", "map", "tooltip", "tag"],
	"buttons": ["small_width", "small_height", "small_font", "normal_width", "normal_height", "normal_font",
		"big_width", "big_height", "big_font", "round_icon", "round_action", "icon_on_button"],
	"windows": ["window_width", "build_panel_width", "build_panel_height", "build_details_width",
		"build_card_width", "build_card_height", "building_card_width", "toolbar_button", "screen_button"],
}

# Palette (from data/ui_look.json "colors", set by apply_look()).
## Windows, bars and the HUD: dark slate glass. Frosted (the map behind is blurred, see frost()),
## it is see-through; without the blur (Settings, or phones) it is more solid ("_SOLID") so words
## stay easy to read over the busy map.
static var GLASS: Color
static var GLASS_SOLID: Color
static var GLASS_HIGH: Color  # tooltips and side tabs: a shade lighter
static var GLASS_HIGH_SOLID: Color
static var EDGE: Color  # the thin light rim around glass
static var EDGE_STRONG: Color  # outlines of empty buttons, chips and text boxes
static var WELL: Color  # sunken boxes inside windows
static var HOVER: Color  # under the pointer
static var TEXT: Color  # body text, titles and numbers
static var TEXT_DIM: Color  # small notes and captions
static var TEXT_FAINT: Color  # hints and empty text boxes
static var ACCENT: Color  # the one highlight colour: Go buttons, picked choices, selection
static var ACCENT_HIGH: Color
static var GOOD: Color  # good news (in windows and over the map)
static var WARN: Color  # "not quite right"
static var BAD: Color  # bad news / warnings
static var OUTLINE: Color  # dark outline for text and signs straight over the map
static var DIM: Color  # dims the map behind a window in the middle of the screen (and phone sheets)
static var DIM_LIGHT: Color  # behind a window docked at the side: lighter, so the map stays in view

# Shapes ("shapes").
static var RADIUS: int  # buttons
static var CHIP_RADIUS: int  # choice chips: rounder
static var WINDOW_RADIUS: int  # windows, cards and the HUD
static var INSET_RADIUS: int  # sunken boxes and small glass pills
static var RIM: int  # how thick the light rims are
static var WINDOW_PADDING: int  # space inside a window's edge
static var BUTTON_PADDING: int  # space left and right of a button's words
static var WINDOW_SHADOW: int  # the soft shadow under windows and glass bars (0 = none: cheaper to draw)

# Text sizes ("text"): every label uses one of these (through its variation).
static var SIZE_SMALL: int
static var SIZE_BODY: int
static var SIZE_HEADING: int
static var SIZE_BIG: int
static var SIZE_TITLE: int
static var SIZE_MAP: int  # words straight over the map
static var SIZE_TOOLTIP: int
static var SIZE_TAG: int  # status tags ("● WORKING")

# Buttons ("buttons").
## Button sizes: minimum width and height, and font size, for "small", "normal" and "big".
static var SIZES := {}
## Tile buttons (RoundButton): icon-only ones (close ✕, ✓) and the building card's, with a caption.
static var ROUND_ICON_SIZE: float
static var ROUND_ACTION_SIZE: float
static var BUTTON_ICON: int  # icons on buttons stay this small next to the words

# Windows ("windows").
static var WINDOW_WIDTH: float  # windows (ModalWindow) on wide screens
static var BUILD_PANEL_WIDTH: float  # the Build panel on wide screens (smaller if the screen is)
static var BUILD_PANEL_HEIGHT: float
static var BUILD_DETAILS_WIDTH: float  # the Build panel's details column
static var BUILD_CARD_SIZE: Vector2  # one building card in the Build panel
static var BUILDING_CARD_WIDTH: float  # the card at the bottom when a building is picked
static var TOOLBAR_BUTTON: float  # the bottom toolbar's category buttons
static var SCREEN_BUTTON: float  # the screen buttons in the top-left corner

## Button colours: variation -> [fill, rim, text colour] (made by apply_look()). Filled buttons
## (Go, Danger, the picked chip) light up a little towards the top, like the glass catching the light.
static var BUTTONS := {}
const FILLED := ["GoButton", "DangerButton", "ChipOnButton"]
const CHIPS := ["ChipButton", "ChipOnButton"]

## Frosted glass: a panel with this material blurs the map behind it. Only the panel's body is
## frosted (it is the only part drawn at least half solid); its faint rim (and shadow, if any) are
## drawn as usual. The blur comes from Godot's small, already-blurred copies of the screen ("mipmaps").
const FROST_SHADER := "shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 3.0;
void fragment() {
	vec2 step = SCREEN_PIXEL_SIZE * 7.0;
	vec3 behind = textureLod(screen, SCREEN_UV, blur).rgb * 0.36;
	behind += textureLod(screen, SCREEN_UV + vec2(step.x, step.y), blur).rgb * 0.16;
	behind += textureLod(screen, SCREEN_UV + vec2(-step.x, step.y), blur).rgb * 0.16;
	behind += textureLod(screen, SCREEN_UV + vec2(step.x, -step.y), blur).rgb * 0.16;
	behind += textureLod(screen, SCREEN_UV + vec2(-step.x, -step.y), blur).rgb * 0.16;
	behind = mix(vec3(dot(behind, vec3(0.299, 0.587, 0.114))), behind, 1.35);
	float body = smoothstep(0.45, 0.75, COLOR.a);
	vec3 frosted = mix(behind, COLOR.rgb, COLOR.a);
	COLOR = vec4(mix(COLOR.rgb, frosted, body), mix(COLOR.a, 1.0, body));
}"

static var look := {}  # data/ui_look.json as now (with any changes made live in the Look page)
static var _icon_swaps := {}  # icon name -> the icon drawn instead ("icons")
static var _font: Font
static var _bold: Font
static var _icons := {}  # icon name -> texture: looked up once (checking the files is slow on phones)
static var _frosted := true  # the blur is on (Settings "glass_blur"); build() and frost() follow it
static var _frost: ShaderMaterial
static var _glass: Color
static var _glass_high: Color


static func _static_init() -> void:
	apply_look(load_look())


## data/ui_look.json as it is in the file.
static func load_look() -> Dictionary:
	return preload("res://scripts/autoload/game_data.gd").load_json(LOOK_FILE)


## Takes the look's colours and sizes from `new_look` (data/ui_look.json's shape). Windows made
## after this use them; build() a new theme to restyle the ones already on screen.
static func apply_look(new_look: Dictionary) -> void:
	look = new_look
	GLASS = _look_color("glass")
	GLASS_SOLID = _look_color("glass_solid")
	GLASS_HIGH = _look_color("glass_high")
	GLASS_HIGH_SOLID = _look_color("glass_high_solid")
	EDGE = _look_color("edge")
	EDGE_STRONG = _look_color("edge_strong")
	WELL = _look_color("well")
	HOVER = _look_color("hover")
	TEXT = _look_color("text")
	TEXT_DIM = _look_color("text_dim")
	TEXT_FAINT = _look_color("text_faint")
	ACCENT = _look_color("accent")
	ACCENT_HIGH = _look_color("accent_high")
	GOOD = _look_color("good")
	WARN = _look_color("warn")
	BAD = _look_color("bad")
	OUTLINE = _look_color("outline")
	DIM = _look_color("dim")
	DIM_LIGHT = _look_color("dim_light")
	RADIUS = _look_int("shapes", "button_radius")
	CHIP_RADIUS = _look_int("shapes", "chip_radius")
	WINDOW_RADIUS = _look_int("shapes", "window_radius")
	INSET_RADIUS = _look_int("shapes", "inset_radius")
	RIM = _look_int("shapes", "rim_width")
	WINDOW_PADDING = _look_int("shapes", "window_padding")
	BUTTON_PADDING = _look_int("shapes", "button_padding")
	WINDOW_SHADOW = _look_int("shapes", "window_shadow")
	SIZE_SMALL = _look_int("text", "small")
	SIZE_BODY = _look_int("text", "body")
	SIZE_HEADING = _look_int("text", "heading")
	SIZE_BIG = _look_int("text", "big")
	SIZE_TITLE = _look_int("text", "title")
	SIZE_MAP = _look_int("text", "map")
	SIZE_TOOLTIP = _look_int("text", "tooltip")
	SIZE_TAG = _look_int("text", "tag")
	SIZES = {}
	for size in ["small", "normal", "big"]:
		SIZES[size] = {"min": Vector2(_look_int("buttons", size + "_width"), _look_int("buttons", size + "_height")),
			"font": _look_int("buttons", size + "_font")}
	ROUND_ICON_SIZE = _look_int("buttons", "round_icon")
	ROUND_ACTION_SIZE = _look_int("buttons", "round_action")
	BUTTON_ICON = _look_int("buttons", "icon_on_button")
	WINDOW_WIDTH = _look_int("windows", "window_width")
	BUILD_PANEL_WIDTH = _look_int("windows", "build_panel_width")
	BUILD_PANEL_HEIGHT = _look_int("windows", "build_panel_height")
	BUILD_DETAILS_WIDTH = _look_int("windows", "build_details_width")
	BUILD_CARD_SIZE = Vector2(_look_int("windows", "build_card_width"), _look_int("windows", "build_card_height"))
	BUILDING_CARD_WIDTH = _look_int("windows", "building_card_width")
	TOOLBAR_BUTTON = _look_int("windows", "toolbar_button")
	SCREEN_BUTTON = _look_int("windows", "screen_button")
	BUTTONS = {
		"Button": [_look_color("button"), EDGE, TEXT],
		"GoButton": [_look_color("go"), _look_color("go_rim"), Color.WHITE],
		"DangerButton": [_look_color("danger"), _look_color("danger_rim"), Color.WHITE],
		"BackButton": [Color(0, 0, 0, 0), EDGE_STRONG, TEXT_DIM],
		"IconButton": [Color(0, 0, 0, 0), Color(0, 0, 0, 0), TEXT_DIM],
		"ChipOnButton": [_look_color("chip_on"), _look_color("chip_on_rim"), Color.WHITE],
		"ChipButton": [Color(0, 0, 0, 0), EDGE_STRONG, TEXT_DIM],
	}
	_icon_swaps = look.get("icons", {})
	_icons.clear()


static func _look_color(key: String) -> Color:
	var text := str(look.get("colors", {}).get(key, ""))
	if not Color.html_is_valid(text):
		push_error("data/ui_look.json: colors.%s isn't a colour like \"#2f9cf0\"" % key)
		return Color.MAGENTA
	return Color.html(text)


static func _look_int(section: String, key: String) -> int:
	var value: Variant = look.get(section, {}).get(key)
	if not (value is float or value is int):
		push_error("data/ui_look.json: %s.%s is missing" % [section, key])
		return 10
	return roundi(value)


## Builds the theme. Call once (main.gd does), and again when the "glass_blur" setting changes:
## frosted glass is see-through, plain glass more solid.
static func build(frosted := true) -> Theme:
	_frosted = frosted
	_glass = GLASS if frosted else GLASS_SOLID
	_glass_high = GLASS_HIGH if frosted else GLASS_HIGH_SOLID
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
	_label_style(t, "OutlineLabel", SIZE_MAP, TEXT, true)
	t.set_color("font_outline_color", "OutlineLabel", OUTLINE)
	t.set_constant("outline_size", "OutlineLabel", 6)
	t.set_color("font_shadow_color", "OutlineLabel", Color(OUTLINE, 0.4))
	t.set_constant("shadow_offset_x", "OutlineLabel", 0)
	t.set_constant("shadow_offset_y", "OutlineLabel", 2)
	t.set_constant("shadow_outline_size", "OutlineLabel", 6)
	# Tooltips: a small glass note.
	t.set_stylebox("panel", "TooltipPanel", _flat(_glass_high, EDGE_STRONG, RADIUS, RIM, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", SIZE_TOOLTIP)


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
	t.set_constant("icon_max_width", "Button", BUTTON_ICON)  # icons on buttons stay small next to the words
	for variation in BUTTONS:
		if variation != "Button":
			t.set_type_variation(variation, "Button")
		var spec: Array = BUTTONS[variation]
		_button(t, variation, spec[0], spec[1], variation in FILLED, CHIP_RADIUS if variation in CHIPS else RADIUS)
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
	var card := _flat(Color(1, 1, 1, 0.05), EDGE, WINDOW_RADIUS, RIM, 8)
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


## A soft shadow under a glass box (none when `size` is 0, which is also cheaper to draw).
static func _add_shadow(box: StyleBoxFlat, darkness: float, size: int, drop: float) -> void:
	if size <= 0:
		return
	box.shadow_color = Color(0, 0, 0, darkness)
	box.shadow_size = size
	box.shadow_offset = Vector2(0, drop)


static func _panels(t: Theme) -> void:
	# Windows: dark glass with a thin light rim (and a soft shadow underneath when window_shadow in
	# ui_look.json is above 0; it's 0 since 2026-10-07, to save drawing).
	var window := _flat(_glass, EDGE, WINDOW_RADIUS, RIM, WINDOW_PADDING)
	window.content_margin_top = 12
	_add_shadow(window, 0.35, WINDOW_SHADOW, 6)
	t.set_stylebox("panel", "PanelContainer", window)
	t.set_stylebox("panel", "Panel", window)
	# The strip across the top of every window (title + close button). It reaches out over the
	# window's own padding (expand margins), so its faint band and the line under it run edge to edge.
	t.set_type_variation("TitleBar", "PanelContainer")
	var strip := _flat(Color(1, 1, 1, 0.035), EDGE, 0, 0, 0)
	strip.border_width_bottom = 1
	strip.corner_radius_top_left = WINDOW_RADIUS
	strip.corner_radius_top_right = WINDOW_RADIUS
	strip.expand_margin_left = WINDOW_PADDING
	strip.expand_margin_right = WINDOW_PADDING
	strip.expand_margin_top = 12
	strip.content_margin_bottom = 8
	t.set_stylebox("panel", "TitleBar", strip)
	# Sunken boxes inside windows (sections, rows of details).
	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", _flat(WELL, EDGE, INSET_RADIUS, RIM, 10))
	# Small glass boxes over the map: the warehouse chips under the HUD and the short messages.
	t.set_type_variation("HudPill", "PanelContainer")
	var pill := _flat(_glass, EDGE, INSET_RADIUS, RIM, 4)
	pill.content_margin_left = 8
	pill.content_margin_right = 10
	_add_shadow(pill, 0.3, WINDOW_SHADOW / 2, 2)
	t.set_stylebox("panel", "HudPill", pill)
	# Glass bars over the map: the HUD's numbers, the bottom toolbar.
	t.set_type_variation("HudBar", "PanelContainer")
	var bar := _flat(_glass, EDGE, WINDOW_RADIUS, RIM, 6)
	bar.content_margin_left = 10
	bar.content_margin_right = 10
	_add_shadow(bar, 0.32, WINDOW_SHADOW, 4)
	t.set_stylebox("panel", "HudBar", bar)
	# Status tags ("BUY $750", "WORKING"): a small dark box with a faint rim, words in small capitals.
	t.set_type_variation("Tag", "PanelContainer")
	var tag := _flat(Color(0, 0, 0, 0.3), EDGE_STRONG, RADIUS, RIM, 3)
	tag.content_margin_left = 8
	tag.content_margin_right = 8
	t.set_stylebox("panel", "Tag", tag)
	# Text boxes (developer tools): a dark well that outlines in blue while typing.
	var field := _flat(Color(0, 0, 0, 0.3), EDGE_STRONG, RADIUS, RIM, 8)
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


## Makes a glass panel frosted: the map behind it is blurred (when the "glass_blur" setting is on).
## Use it on panels that sit over the map: windows, the HUD, the toolbars, the building card.
static func frost(panel: Control) -> void:
	panel.add_to_group("frosted_glass")
	panel.material = _frost_material() if _frosted else null


## The "glass_blur" setting changed: frost (or stop frosting) every frosted panel.
static func set_frosted(tree: SceneTree, on: bool) -> void:
	_frosted = on
	for panel: Control in tree.get_nodes_in_group("frosted_glass"):
		panel.material = _frost_material() if on else null


static func _frost_material() -> ShaderMaterial:
	if _frost == null:
		_frost = ShaderMaterial.new()
		_frost.shader = Shader.new()
		_frost.shader.code = FROST_SHADER
	return _frost


## A thin light line between parts of a bar or panel (vertical = a | line, else a — line).
static func divider(vertical: bool, length := 0.0) -> ColorRect:
	var line := ColorRect.new()
	line.color = EDGE_STRONG if vertical else EDGE
	line.custom_minimum_size = Vector2(1, length) if vertical else Vector2(length, 1)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER if vertical and length > 0.0 else Control.SIZE_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## A status tag: a coloured dot and words in small capitals ("● BUY $750").
## Returns {"tag": PanelContainer, "dot": ColorRect, "label": Label}.
static func tag(text := "", color := WARN) -> Dictionary:
	var box := PanelContainer.new()
	box.theme_type_variation = "Tag"
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(7, 7)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var words := label(text.to_upper(), "SmallLabel")
	words.add_theme_font_override("font", bold_font())
	words.add_theme_font_size_override("font_size", SIZE_TAG)
	words.add_theme_color_override("font_color", TEXT)
	row.add_child(words)
	return {"tag": box, "dot": dot, "label": words}


## A small coloured square with a white icon: a window's or category's sign (the colour says what
## kind of building it is about, like the map's colours).
static func category_square(icon_name: String, color: Color, side := 36.0) -> PanelContainer:
	var square := PanelContainer.new()
	square.custom_minimum_size = Vector2(side, side)
	square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	square.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := _lit(_flat(color, color, RADIUS + 1, 0, 0), color, color.lightened(0.25))
	box.border_width_top = int(side / 2.0)
	square.add_theme_stylebox_override("panel", box)
	var picture := icon_rect(icon_name, roundf(side * 0.58))
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	square.add_child(picture)
	return square


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


## An icon from assets/ui/icons/ (or the one ui_look.json "icons" draws in its place), or the
## plain item icon if that one doesn't exist yet.
static func icon(icon_name: String) -> Texture2D:
	if not _icons.has(icon_name):
		var path := ICONS + str(_icon_swaps.get(icon_name, icon_name)) + ".svg"
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
	var normal := _flat(fill, rim, radius, RIM, 6)
	normal.content_margin_left = BUTTON_PADDING
	normal.content_margin_right = BUTTON_PADDING
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
	var disabled := _flat(Color(1, 1, 1, 0.05), EDGE, radius, RIM, 6)
	disabled.content_margin_left = BUTTON_PADDING
	disabled.content_margin_right = BUTTON_PADDING
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
