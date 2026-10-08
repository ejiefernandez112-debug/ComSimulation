"""STYLE KIT shared by every model in the pack (plan.md section 4), so they all look like one set:
one colour palette, one scale, and helpers that build shapes with softly rounded (bevelled) edges.

Scale: 1 game tile = TILE Blender units (metres). A 2x2 building stands on a 10 x 10 square
centred on the origin. The sprite studio resizes every model to fit its tiles, so this only has to
be consistent between models, not exact.

Directions: the game camera stands off the +X / -Y corner, so the faces the player sees are the
-Y face (lower-left on screen) and the +X face (lower-right on screen). Put doors, windows and other
detail there. The +Y and -X faces are the hidden back; the -X/+Y corner is the top of the screen.
"""
import math
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

TILE = 5.0

# Colours (sRGB hex, like a paint program). Warm and fairly saturated, Clash-of-Clans style.
PALETTE = {
	"barn_red": "#b5402c",
	"barn_red_dark": "#8e2e20",
	"trim": "#f2e9d6",
	"roof": "#5d6672",
	"roof_dark": "#48505b",
	"wood_light": "#cf9f5f",
	"wood": "#a8733f",
	"wood_dark": "#6c4426",
	"stone": "#a39d95",
	"stone_dark": "#7c766f",
	"metal": "#b8c3ca",
	"metal_dark": "#7d8992",
	"soil": "#7a5134",
	"soil_dark": "#5c3b25",
	"dirt": "#a8835a",
	"wheat": "#e9b947",
	"wheat_light": "#f6d77c",
	"stalk": "#c9973a",
	"hay": "#e3c066",
	"sack": "#dccaa0",
	"cloth_blue": "#4677b3",
	"cloth_red": "#c4483b",
	"leaf": "#5f9a3a",
	"window": "#3b4a5c",
	"white": "#eef1f2",
	"concrete": "#cbc6bb",
	"concrete_dark": "#a29c91",
	"solar": "#28477a",
	"solar_light": "#5d8fd1",
	"hazard": "#e8b630",
	"gravel": "#9a958b",
	"plaster": "#f3dfb8",
	"brick": "#b35a3c",
	"brick_dark": "#8c4029",
	"terracotta": "#c8643a",
	"terracotta_dark": "#9f4a2a",
	"bread": "#d08a3e",
	"bread_light": "#ecc07a",
	"shop_green": "#3f6f52",
	"paving": "#d9c9a8",
	"fire": "#f39a2e",
	"copper": "#5fa391",
	"copper_dark": "#447e70",
	"water": "#6fb7e0",
	"grass": "#6ca444",  # preview ground only
}

_materials = {}


def mat(name: str, shade: float = 0.0) -> bpy.types.Material:
	"""A palette material. `shade` makes it a little lighter (+) or darker (-), e.g. 0.06, so rows
	of planks or tiles don't look copy-pasted. Shades are rounded so we don't make hundreds."""
	shade = round(shade, 2)
	key = (name, shade)
	if key not in _materials:
		m = bpy.data.materials.new(f"{name}{'' if shade == 0 else f'{shade:+.2f}'}")
		color = _srgb_to_linear(PALETTE[name])
		factor = 1.0 + shade
		m.diffuse_color = (*[min(c * factor, 1.0) for c in color], 1.0)
		m.use_nodes = True
		bsdf = m.node_tree.nodes["Principled BSDF"]
		bsdf.inputs["Base Color"].default_value = m.diffuse_color
		is_metal = name.startswith("metal")
		bsdf.inputs["Roughness"].default_value = 0.45 if is_metal else 0.85
		bsdf.inputs["Metallic"].default_value = 0.4 if is_metal else 0.0
		_materials[key] = m
	return _materials[key]


def _srgb_to_linear(hex_color: str):
	rgb = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
	return [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]


def frame(at, x_axis, y_axis=None, z_axis=None) -> Matrix:
	"""Placement matrix from a position and the directions the shape's own X/Y/Z should point.
	Give two axes; the third is worked out."""
	x = Vector(x_axis).normalized()
	if z_axis is None:
		z = x.cross(Vector(y_axis)).normalized()
	else:
		z = Vector(z_axis).normalized()
		x = (x - z * x.dot(z)).normalized()  # square it up against z
	y = z.cross(x)
	m = Matrix((x, y, z)).transposed().to_4x4()
	m.translation = Vector(at)
	return m


def place(at=(0, 0, 0), rot=(0, 0, 0)) -> Matrix:
	"""Placement matrix from a position and a rotation in degrees around X, Y, Z."""
	return Matrix.Translation(Vector(at)) @ Euler([math.radians(r) for r in rot]).to_matrix().to_4x4()


class Parts:
	"""Collects many simple shapes into ONE object (much tidier than hundreds of objects).
	Every shape takes a placement matrix (from place() or frame()) and a material."""

	def __init__(self, name: str):
		self.name = name
		self.bm = bmesh.new()
		self.materials = []

	def _paint(self, verts, material):
		if material not in self.materials:
			self.materials.append(material)
		index = self.materials.index(material)
		for f in {f for v in verts for f in v.link_faces}:
			f.material_index = index

	def box(self, size, m: Matrix, material):
		"""A box `size` = (x, y, z), centred on the placement point."""
		result = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m @ Matrix.Diagonal((*size, 1.0)))
		self._paint(result["verts"], material)

	def cylinder(self, radius, height, m: Matrix, material, sides=16, top_radius=None):
		"""Upright cylinder (or cone, with top_radius) centred on the placement point."""
		result = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=sides,
			radius1=radius, radius2=radius if top_radius is None else top_radius, depth=height, matrix=m)
		self._paint(result["verts"], material)

	def ball(self, radius, m: Matrix, material, squash=(1, 1, 1), detail=2):
		"""A ball, optionally squashed/stretched by `squash` = (x, y, z)."""
		result = bmesh.ops.create_icosphere(self.bm, subdivisions=detail, radius=radius,
			matrix=m @ Matrix.Diagonal((*squash, 1.0)))
		self._paint(result["verts"], material)

	def prism(self, outline, depth, m: Matrix, material):
		"""A flat 2D shape (list of (x, z) points, going around) pushed out `depth` along Y, centred."""
		front = [self.bm.verts.new(m @ Vector((x, -depth / 2, z))) for x, z in outline]
		back = [self.bm.verts.new(m @ Vector((x, depth / 2, z))) for x, z in outline]
		faces = [self.bm.faces.new(front), self.bm.faces.new(list(reversed(back)))]
		n = len(outline)
		for i in range(n):
			j = (i + 1) % n
			faces.append(self.bm.faces.new((front[i], front[j], back[j], back[i])))
		bmesh.ops.recalc_face_normals(self.bm, faces=faces)
		self._paint(front + back, material)

	def done(self, bevel=0.03, pivot: Matrix = None) -> bpy.types.Object:
		"""Turns the collected shapes into an object. `bevel` rounds every sharp edge by that much,
		which catches the sun and makes small things read as solid, chunky toys (0 = no rounding).
		`pivot` (a frame()) is for a part that turns in the game, like a turbine's rotor: the object
		then sits there, its own X axis being the axle it turns around (the sprite studio's "spin")."""
		mesh = bpy.data.meshes.new(self.name)
		if pivot is not None:
			self.bm.transform(pivot.inverted())  # the shapes were placed in world positions
		self.bm.to_mesh(mesh)
		self.bm.free()
		for material in self.materials:
			mesh.materials.append(material)
		for poly in mesh.polygons:
			poly.use_smooth = bevel > 0  # without rounding, keep crisp flat faces
		obj = bpy.data.objects.new(self.name, mesh)
		if pivot is not None:
			obj.matrix_world = pivot
		bpy.context.scene.collection.objects.link(obj)
		if bevel > 0:
			mod = obj.modifiers.new("rounded edges", "BEVEL")
			mod.width = bevel
			mod.segments = 2
			mod.limit_method = "ANGLE"
			mod.angle_limit = math.radians(35)
			mod.harden_normals = True  # flat faces stay flat-shaded, only the rounded edges are smooth
		return obj


def rng(seed: int) -> random.Random:
	"""Random numbers that come out the same every run, so re-building a model gives the same model."""
	return random.Random(seed)
