"""ELECTRIC SUBSTATION (1 tile): a gravel yard behind a low fence, two transformers with cooling
fins, a steel gantry with insulators, and a hazard sign on the side the player sees. Plot is
-2.5..2.5 on X and Y (see kit.py)."""
from kit import Parts, mat, place

TILES = 1
EDGE = 2.25  # fence line


def build():
	_yard()
	_transformers()
	_gantry()
	_fence()


def _yard():
	g = Parts("yard")
	g.box((EDGE * 2, EDGE * 2, 0.16), place((0, 0, 0.08)), mat("gravel"))
	g.box((1.9, 1.5, 0.12), place((-0.7, 0.6, 0.22)), mat("concrete"))
	g.box((1.5, 1.3, 0.12), place((1.0, -0.9, 0.22)), mat("concrete"))
	g.done(bevel=0.03)


def _transformer(t, x, y, w, d, h):
	t.box((w, d, h), place((x, y, 0.28 + h / 2)), mat("metal_dark"))
	t.box((w + 0.08, d + 0.08, 0.1), place((x, y, 0.28 + h + 0.05)), mat("metal_dark", -0.15))
	# Cooling fins on the two faces the player sees.
	n = 6
	for i in range(n):
		fx = x - w / 2 + (i + 0.5) * w / n
		t.box((0.06, 0.22, h * 0.8), place((fx, y - d / 2 - 0.1, 0.28 + h * 0.45)), mat("metal", -0.1))
	for i in range(n):
		fy = y - d / 2 + (i + 0.5) * d / n
		t.box((0.22, 0.06, h * 0.8), place((x + w / 2 + 0.1, fy, 0.28 + h * 0.45)), mat("metal", -0.1))
	# Bushings (insulators) on top.
	for i in range(3):
		bx = x - w / 3 + i * w / 3
		for k in range(3):
			t.cylinder(0.11 - k * 0.015, 0.14, place((bx, y, 0.28 + h + 0.17 + k * 0.15)), mat("trim"), sides=10)


def _transformers():
	t = Parts("transformers")
	_transformer(t, -0.7, 0.6, 1.4, 1.0, 1.3)
	_transformer(t, 1.0, -0.9, 1.0, 0.8, 1.0)
	t.done(bevel=0.03)


def _gantry():
	g = Parts("gantry")
	height = 3.4
	for x, y in ((-1.7, -1.5), (-1.7, 1.6), (0.6, 1.6)):
		g.box((0.16, 0.16, height), place((x, y, 0.16 + height / 2)), mat("metal"))
	g.box((0.14, 3.1, 0.14), place((-1.7, 0.05, 0.16 + height)), mat("metal"))
	g.box((2.3, 0.14, 0.14), place((-0.55, 1.6, 0.16 + height)), mat("metal"))
	# Hanging insulator strings with a cap each.
	for x, y in ((-1.7, -0.7), (-1.7, 0.3), (-1.7, 1.1), (-1.0, 1.6), (-0.2, 1.6)):
		for k in range(4):
			g.cylinder(0.09, 0.08, place((x, y, 0.16 + height - 0.18 - k * 0.12)), mat("trim"), sides=10)
	g.done(bevel=0.02)


def _fence():
	f = Parts("fence")
	posts = 7
	for i in range(posts):
		v = -EDGE + i * EDGE * 2 / (posts - 1)
		for x, y in ((v, -EDGE), (EDGE, v), (v, EDGE), (-EDGE, v)):
			f.box((0.08, 0.08, 0.75), place((x, y, 0.16 + 0.375)), mat("metal_dark"))
	for z in (0.35, 0.8):
		f.box((EDGE * 2, 0.04, 0.05), place((0, -EDGE, z)), mat("metal"))
		f.box((0.04, EDGE * 2, 0.05), place((EDGE, 0, z)), mat("metal"))
		f.box((EDGE * 2, 0.04, 0.05), place((0, EDGE, z)), mat("metal"))
		f.box((0.04, EDGE * 2, 0.05), place((-EDGE, 0, z)), mat("metal"))
	# Yellow hazard sign on the front fence.
	f.box((0.5, 0.05, 0.4), place((-0.6, -EDGE - 0.05, 0.6)), mat("hazard"))
	f.box((0.08, 0.06, 0.24), place((-0.6, -EDGE - 0.08, 0.62), (0, 25, 0)), mat("window"))
	f.done(bevel=0.015)
