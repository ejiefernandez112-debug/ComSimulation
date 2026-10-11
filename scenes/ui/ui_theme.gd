class_name UITheme
## The game's look: "Harbor Glass", a calm, realistic city-builder style (the user asked for
## something like Cities: Skylines II, 2026-10-06). Dark slate glass panels with a thin light rim
## and small rounded corners, one blue highlight colour, white line icons and the Overpass font
## (assets/fonts/, SIL Open Font License).
##
## The look lives in one Godot theme file, assets/ui/game_theme.tres (since 2026-10-11; before, this
## script drew it from data/ui_look.json). Open it in the Godot editor and the Theme panel at the
## bottom shows every type: pick one (Button, GoButton, PanelContainer, SmallLabel...) and change its
## colours, borders, corners, padding and text sizes; every window follows. main.gd puts the theme on
## all of the UI, and scenes laid out in the editor carry it too, so they look right while you work.
## Two extra types in the file hold what the code needs:
##   "Palette" colours the code paints with: good / warn / bad numbers, rims and dividers, the shade
##     behind windows, the glass when the blur is off (glass_solid, glass_high_solid)...
##   "Sizes"   button sizes (small / normal / big: width, height, text), tiles, window widths
## Text colours come from the label types themselves (Label = body text, SmallLabel = notes) and
## text sizes from each label type's font size.
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
## then more solid (the Palette's glass_solid colours). A theme file can't blur, so that stays here.

const ICONS := "res://assets/ui/icons/"
const THEME_FILE := "res://assets/ui/game_theme.tres"
## What the theme file's "Palette" and "Sizes" types must have (tests/check_project.gd checks it).
const PALETTE_KEYS := ["text_faint", "accent_high", "good", "warn", "bad", "outline", "edge", "edge_strong",
	"dim", "dim_light", "glass_solid", "glass_high_solid"]
const SIZE_KEYS := ["small_width", "small_height", "small_font", "normal_width", "normal_height", "normal_font",
	"big_width", "big_height", "big_font", "round_icon", "round_action", "tag_text", "window_width",
	"build_panel_width", "build_panel_height", "build_details_width", "build_card_width", "build_card_height",
	"building_card_width", "toolbar_button", "screen_button"]
## Glass panels that turn solid when the blur is off: theme type -> the Palette colour they take.
const SOLID_GLASS := {"PanelContainer": "glass_solid", "Panel": "glass_solid", "HudPill": "glass_solid",
	"HudBar": "glass_solid", "TooltipPanel": "glass_high_solid"}

# Colours (the Palette, and the label types' text colours), read from the theme file.
static var TEXT: Color  # body text, titles and numbers (Label)
static var TEXT_DIM: Color  # small notes and captions (SmallLabel)
static var TEXT_FAINT: Color  # hints and empty text boxes
static var ACCENT_HIGH: Color  # the highlight colour, light
static var GOOD: Color  # good news (in windows and over the map)
static var WARN: Color  # "not quite right"
static var BAD: Color  # bad news / warnings
static var OUTLINE: Color  # dark outline for text and signs straight over the map
static var EDGE: Color  # the thin light rim around glass, and dividers
static var EDGE_STRONG: Color  # stronger lines (dividers between parts of a bar)
static var DIM: Color  # dims the map behind a window in the middle of the screen (and phone sheets)
static var DIM_LIGHT: Color  # a lighter dim (no window uses it since 2026-10-11: they all sit in the middle)

# Shapes and text sizes, read from the theme's own types.
static var RADIUS: int  # button corners (Button)
static var WINDOW_PADDING: int  # space inside a window's edge (PanelContainer)
static var SIZE_SMALL: int  # SmallLabel
static var SIZE_BODY: int  # Label
static var SIZE_HEADING: int  # HeadingLabel
static var SIZE_BIG: int  # BigLabel
static var SIZE_TITLE: int  # TitleLabel
static var SIZE_MAP: int  # OutlineLabel: words straight over the map
static var SIZE_TOOLTIP: int  # TooltipLabel
static var SIZE_TAG: int  # status tags ("● WORKING"; Sizes tag_text)

# Buttons and windows (the "Sizes" type).
## Button sizes: minimum width and height, and font size, for "small", "normal" and "big".
static var SIZES := {}
## Tile buttons (RoundButton): icon-only ones (close ✕, ✓) and the building card's, with a caption.
static var ROUND_ICON_SIZE: float
static var ROUND_ACTION_SIZE: float
static var BUTTON_ICON: int  # icons on buttons stay this small next to the words (Button icon_max_width)
static var WINDOW_WIDTH: float  # windows (ModalWindow) on wide screens
static var BUILD_PANEL_WIDTH: float  # the Build panel on wide screens (smaller if the screen is)
static var BUILD_PANEL_HEIGHT: float
static var BUILD_DETAILS_WIDTH: float  # the Build panel's details column
static var BUILD_CARD_SIZE: Vector2  # one building card in the Build panel
static var BUILDING_CARD_WIDTH: float  # the card at the bottom when a building is picked
static var TOOLBAR_BUTTON: float  # the bottom toolbar's category buttons
static var SCREEN_BUTTON: float  # the screen buttons in the top-left corner

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

static var _theme: Theme  # the theme file, as loaded
static var _icons := {}  # icon name -> texture: looked up once (checking the files is slow on phones)
static var _frosted := true  # the blur is on (Settings "glass_blur"); build() and frost() follow it
static var _frost: ShaderMaterial


static func _static_init() -> void:
	_read(theme_file())


## The theme file, loaded once. Godot's own font is added behind ours, for symbols Overpass doesn't
## have (✓); it's built in, so the file can't hold it.
static func theme_file() -> Theme:
	if _theme == null:
		_theme = load(THEME_FILE)
		var fonts: Array[Font] = [_theme.default_font]
		for type in _theme.get_type_list():
			for name in _theme.get_font_list(type):
				fonts.append(_theme.get_font(name, type))
		for font in fonts:
			if font != null and font.fallbacks.is_empty() and font != ThemeDB.fallback_font:
				font.fallbacks = [ThemeDB.fallback_font]
	return _theme


## Reads the colours and sizes the code needs from the theme.
static func _read(t: Theme) -> void:
	TEXT = t.get_color("font_color", "Label")
	TEXT_DIM = t.get_color("font_color", "SmallLabel")
	TEXT_FAINT = _palette(t, "text_faint")
	ACCENT_HIGH = _palette(t, "accent_high")
	GOOD = _palette(t, "good")
	WARN = _palette(t, "warn")
	BAD = _palette(t, "bad")
	OUTLINE = _palette(t, "outline")
	EDGE = _palette(t, "edge")
	EDGE_STRONG = _palette(t, "edge_strong")
	DIM = _palette(t, "dim")
	DIM_LIGHT = _palette(t, "dim_light")
	var button_box := t.get_stylebox("normal", "Button")
	RADIUS = (button_box as StyleBoxFlat).corner_radius_top_left if button_box is StyleBoxFlat else 4
	WINDOW_PADDING = roundi(t.get_stylebox("panel", "PanelContainer").content_margin_left)
	SIZE_BODY = t.get_font_size("font_size", "Label")
	SIZE_SMALL = t.get_font_size("font_size", "SmallLabel")
	SIZE_HEADING = t.get_font_size("font_size", "HeadingLabel")
	SIZE_BIG = t.get_font_size("font_size", "BigLabel")
	SIZE_TITLE = t.get_font_size("font_size", "TitleLabel")
	SIZE_MAP = t.get_font_size("font_size", "OutlineLabel")
	SIZE_TOOLTIP = t.get_font_size("font_size", "TooltipLabel")
	SIZE_TAG = _size(t, "tag_text")
	SIZES = {}
	for size in ["small", "normal", "big"]:
		SIZES[size] = {"min": Vector2(_size(t, size + "_width"), _size(t, size + "_height")), "font": _size(t, size + "_font")}
	ROUND_ICON_SIZE = _size(t, "round_icon")
	ROUND_ACTION_SIZE = _size(t, "round_action")
	BUTTON_ICON = t.get_constant("icon_max_width", "Button")
	WINDOW_WIDTH = _size(t, "window_width")
	BUILD_PANEL_WIDTH = _size(t, "build_panel_width")
	BUILD_PANEL_HEIGHT = _size(t, "build_panel_height")
	BUILD_DETAILS_WIDTH = _size(t, "build_details_width")
	BUILD_CARD_SIZE = Vector2(_size(t, "build_card_width"), _size(t, "build_card_height"))
	BUILDING_CARD_WIDTH = _size(t, "building_card_width")
	TOOLBAR_BUTTON = _size(t, "toolbar_button")
	SCREEN_BUTTON = _size(t, "screen_button")


static func _palette(t: Theme, key: String) -> Color:
	if not t.has_color(key, "Palette"):
		push_error("%s: the Palette type has no colour '%s'" % [THEME_FILE, key])
		return Color.MAGENTA
	return t.get_color(key, "Palette")


static func _size(t: Theme, key: String) -> int:
	if not t.has_constant(key, "Sizes"):
		push_error("%s: the Sizes type has no constant '%s'" % [THEME_FILE, key])
		return 10
	return t.get_constant(key, "Sizes")


## The theme for the UI. main.gd calls it once, and again when the "glass_blur" setting changes:
## frosted glass is the file's see-through glass; without the blur, a copy whose glass panels take
## the Palette's more solid colours, so words stay easy to read over the busy map.
static func build(frosted := true) -> Theme:
	_frosted = frosted
	var t := theme_file()
	if frosted:
		return t
	var solid: Theme = t.duplicate()
	for type in SOLID_GLASS:
		if t.has_stylebox("panel", type) and t.get_stylebox("panel", type) is StyleBoxFlat:
			var box: StyleBoxFlat = t.get_stylebox("panel", type).duplicate()
			box.bg_color = _palette(t, SOLID_GLASS[type])
			solid.set_stylebox("panel", type, box)
	return solid


## The game font (Overpass Medium): the theme's default font.
static func font() -> Font:
	return theme_file().default_font


## Overpass Bold, for titles, headings, numbers and buttons: the theme's heading font.
static func bold_font() -> Font:
	return theme_file().get_font("font", "HeadingLabel")


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
