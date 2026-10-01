extends Node2D
## How one building looks on the map: its picture from assets/buildings/ (made by the sprite studio,
## tools/sprite_studio.gd) when there is one, otherwise a PLACEHOLDER shaded box. Sits at the centre
## of the building's tile; the Objects layer sorts it by how low on screen it is, so nearer things
## cover farther ones. Holds no game numbers.

const SPRITES := "res://assets/buildings/"
const HEIGHT := 30.0  # placeholder box height
const CATEGORY_COLORS := {
	"civic": Color("8a8fa8"),
	"residential": Color("c98b5e"),
	"extractor": Color("d6b84a"),
	"processor": Color("9c7bb5"),
}

static var _manifest := {}  # what the sprite studio wrote: which pictures exist, and their anchors

var type_id := ""


func _ready() -> void:
	var art := picture(type_id)
	if not art.is_empty():
		var sprite := Sprite2D.new()
		sprite.texture = art.texture
		sprite.centered = false
		sprite.offset = -art.anchor  # puts the footprint's centre (the anchor) on this node
		sprite.scale = Vector2.ONE * art.scale
		sprite.show_behind_parent = true  # keeps the name label drawn on top
		add_child(sprite)


func _draw() -> void:
	if picture(type_id).is_empty():
		draw_block(self, Vector2.ZERO, type_id, Color.WHITE)
	draw_name(self, Vector2.ZERO, type_id, 1.0)


## Shadow on the ground, falling away from the sun. Called by the village's Shadows layer.
## Pictures from the sprite studio already include their shadow.
func draw_shadow(layer: Node2D) -> void:
	if picture(type_id).is_empty():
		layer.cast(Iso.diamond_at(position), HEIGHT)


## The see-through preview in Placement Mode, centred on `at`.
static func draw_preview(canvas: CanvasItem, at: Vector2, type_id: String, tint: Color) -> void:
	var art := picture(type_id)
	if art.is_empty():
		draw_block(canvas, at, type_id, tint)
	else:
		var size: Vector2 = art.texture.get_size() * art.scale
		canvas.draw_texture_rect(art.texture, Rect2(at - art.anchor * art.scale, size), false, tint)
	draw_name(canvas, at, type_id, tint.a)


## The building's picture as {"texture", "anchor" (footprint centre, in picture pixels), "scale"},
## or {} if the sprite studio hasn't made one for this building type.
static func picture(type_id: String) -> Dictionary:
	if _manifest.is_empty() and FileAccess.file_exists(SPRITES + "sprites.json"):
		_manifest = GameData.load_json(SPRITES + "sprites.json")
	var entry: Dictionary = _manifest.get("sprites", {}).get(type_id, {})
	if entry.is_empty():
		return {}
	return {
		"texture": load(SPRITES + type_id + ".png"),
		"anchor": Vector2(entry.anchor[0], entry.anchor[1]),
		"scale": Iso.TILE_W / float(_manifest.pixels_per_tile),
	}


## The building's name, just above its top.
static func draw_name(canvas: CanvasItem, at: Vector2, type_id: String, alpha: float) -> void:
	var art := picture(type_id)
	var top: float = at.y - (art.anchor.y * art.scale if not art.is_empty() else HEIGHT + Iso.TILE_H / 2.0)
	var def: Dictionary = GameData.buildings[type_id]
	canvas.draw_string(ThemeDB.fallback_font, Vector2(at.x - 60, top - 4), def.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(1, 1, 1, alpha))


## PLACEHOLDER box, centred on `at`, for buildings that have no picture yet.
static func draw_block(canvas: CanvasItem, at: Vector2, type_id: String, tint: Color) -> void:
	var def: Dictionary = GameData.buildings[type_id]
	var color: Color = CATEGORY_COLORS.get(def.category, Color.GRAY) * tint
	var base := Iso.diamond_at(at)
	var top := Iso.diamond_at(at, HEIGHT)
	# Sun from the upper left: the left wall is half-lit, the right wall faces away.
	var left := PackedVector2Array([top[3], top[2], base[2], base[3]])
	var right := PackedVector2Array([top[2], top[1], base[1], base[2]])
	canvas.draw_colored_polygon(left, color.darkened(0.2))
	canvas.draw_colored_polygon(right, color.darkened(0.42))
	canvas.draw_colored_polygon(top, color.lightened(0.08))
	# Thin smooth outlines hide jagged edges and give a crisp cartoon look.
	var edge := color.darkened(0.6)
	canvas.draw_polyline(PackedVector2Array([top[0], top[1], base[1], base[2], base[3], top[3], top[0]]), edge, 1.0, true)
	canvas.draw_polyline(PackedVector2Array([top[3], top[2], top[1]]), color.lightened(0.35), 1.0, true)
	canvas.draw_line(top[2], base[2], edge.lightened(0.15), 1.0, true)
