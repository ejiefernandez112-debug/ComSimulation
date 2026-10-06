"""MODEL BUILDER: runs one model script in Blender, saves it as a .glb for the sprite studio, and
renders a quick preview picture from the game's camera angle.

	"C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" -b --factory-startup --python art/blender/build.py -- wheat_farm

Writes art/models/wheat_farm.glb (what tools/sprite_studio.gd photographs into the game sprite) and
art/previews/wheat_farm.png (only for looking at; the studio's photo is the real game art).
Add  --blend  at the end to also save art/models/wheat_farm.blend, to open and tweak in Blender.

VARIANTS: a model script may offer 2-3 versions to choose from, as a dict of settings
(VARIANTS = {"a": {...}, "b": {...}}) that its build(settings) reads. Then every variant is built
in one run, as art/models/<id>-<letter>.glb with art/previews/<id>-<letter>.png; name letters
after the id (... -- dairy b) to build only those. The one used in the game is chosen in
tools/sprite_studio.json (tools/apply_picks.py; the building-sprites skill).
"""
import importlib
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ART = HERE.parent
sys.path.insert(0, str(HERE))
import kit  # noqa: E402  (needs the line above first)

# The game's sun (scenes/village/iso.gd Iso.SHADOW and tools/sprite_studio.gd): shadows fall toward
# the lower right of the screen, the sun stands 51 degrees above the horizon.
SHADOW = (0.9, 0.11)
SUN_HEIGHT = 51.0


def main():
	args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	if not args:
		raise SystemExit("Which model? e.g.  ... build.py -- wheat_farm")
	name = args[0]
	model = importlib.import_module("models." + name)
	variants = getattr(model, "VARIANTS", None)
	if not variants:
		_make(model, None, name, "--blend" in args)
		return
	chosen = [a for a in args[1:] if a in variants]
	for letter in chosen or list(variants):
		_make(model, variants[letter], f"{name}-{letter}", "--blend" in args)


## Builds one model (or one variant: `settings`), saves it as `out_name`.glb and renders its preview.
def _make(model, settings, out_name: str, blend: bool):
	for obj in list(bpy.data.objects):  # empty the scene (the default one, or the last variant)
		bpy.data.objects.remove(obj)
	if settings is None:
		model.build()
	else:
		model.build(settings)

	(ART / "models").mkdir(exist_ok=True)
	glb = ART / "models" / f"{out_name}.glb"
	bpy.ops.export_scene.gltf(filepath=str(glb), export_format="GLB", export_apply=True)
	if blend:
		bpy.ops.wm.save_as_mainfile(filepath=str(ART / "models" / f"{out_name}.blend"))
	print(f"Model builder: {out_name} -> {glb}")

	_preview(out_name, model.TILES)


def _preview(name: str, tiles: int):
	scene = bpy.context.scene
	size = tiles * kit.TILE

	# Camera: the game's 2:1 isometric view (looking down 30 degrees, turned 45), framed so the
	# whole model fits, however tall it is.
	cam_data = bpy.data.cameras.new("camera")
	cam_data.type = "ORTHO"
	cam = bpy.data.objects.new("camera", cam_data)
	scene.collection.objects.link(cam)
	cam.rotation_euler = (math.radians(60), 0, math.radians(45))
	turn = cam.rotation_euler.to_matrix()
	right, up, forward = turn.col[0], turn.col[1], -turn.col[2]
	corners = [obj.matrix_world @ Vector(c) for obj in scene.objects if obj.type == "MESH" for c in obj.bound_box]
	corners += [Vector((x, y, 0)) for x in (-size / 2, size / 2) for y in (-size / 2, size / 2)]
	xs = [right.dot(c) for c in corners]
	ys = [up.dot(c) for c in corners]
	cam_data.ortho_scale = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.15
	cam.location = right * (max(xs) + min(xs)) / 2 + up * (max(ys) + min(ys)) / 2 - forward * 40
	cam_data.clip_end = 100
	scene.camera = cam

	# Grass with the building's tiles outlined, so we can see it fits its footprint.
	ground = kit.Parts("preview ground")
	ground.box((size * 10, size * 10, 0.1), kit.place((0, 0, -0.05)), kit.mat("grass"))
	for i in range(tiles + 1):
		edge = -size / 2 + i * kit.TILE
		ground.box((0.06, size, 0.02), kit.place((edge, 0, 0.0)), kit.mat("grass", -0.25))
		ground.box((size, 0.06, 0.02), kit.place((0, edge, 0.0)), kit.mat("grass", -0.25))
	ground.done(bevel=0)

	# Sun from the same direction as in the game.
	sx, sy = SHADOW
	toward = -Vector((sx / 64 + sy / 32, sy / 32 - sx / 64)).normalized()  # Iso.to_cell_f, reversed
	h = math.radians(SUN_HEIGHT)
	to_sun = Vector((toward.x * math.cos(h), -toward.y * math.cos(h), math.sin(h)))
	sun_data = bpy.data.lights.new("sun", "SUN")
	sun_data.energy = 3.2
	sun_data.color = (1.0, 0.97, 0.9)
	sun_data.angle = math.radians(1.5)
	sun = bpy.data.objects.new("sun", sun_data)
	scene.collection.objects.link(sun)
	sun.rotation_euler = to_sun.to_track_quat("Z", "Y").to_euler()

	# Bluish sky light fills in the shaded walls, like the studio's.
	world = bpy.data.worlds.new("sky")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.75, 0.85, 1.0, 1.0)
	world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
	scene.world = world

	scene.render.engine = "BLENDER_EEVEE"
	scene.eevee.taa_render_samples = 32
	scene.view_settings.view_transform = "Standard"
	scene.render.resolution_x = 1000
	scene.render.resolution_y = 1000
	scene.render.filepath = str(ART / "previews" / f"{name}.png")
	(ART / "previews").mkdir(exist_ok=True)
	bpy.ops.render.render(write_still=True)
	print(f"Model builder: preview -> {scene.render.filepath}")


main()
