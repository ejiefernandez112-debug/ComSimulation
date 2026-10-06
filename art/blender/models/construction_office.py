"""CONSTRUCTION OFFICE (2x2 tiles): two stacked blue site cabins with an outside staircase and a
giant hard-hat sign, a yellow tower crane lifting a bundle of steel beams, and building materials
around a gravel yard: beams, bricks, sand, a cement mixer, concrete pipes and traffic cones.
Plot is -5..5 on X and Y (see kit.py for which sides the player sees)."""
import math

from mathutils import Vector

from kit import Parts, frame, mat, place, rng

TILES = 2

LOW = (-2.1, 2.4)  # lower cabin centre
UP = (-1.7, 2.6)  # upper cabin centre
CW, CD, CH = 4.2, 2.0, 1.5  # cabin size
LIFT = 0.25  # cabins stand on blocks
MAST = (3.2, 3.2)
MAST_TOP, JIB_Z = 7.0, 7.25
JIB_END, COUNTER_END = -3.8, 4.9
TROLLEY_X, LOAD_Z = -0.9, 5.4


def build():
	r = rng(9)
	_yard(r)
	_cabins()
	_stairs()
	_crane()
	_props(r)


def _yard(r):
	g = Parts("yard")
	g.box((9.6, 9.6, 0.08), place((0, 0, 0.04)), mat("gravel"))
	g.box((5.4, 3.0, 0.1), place((-1.9, 2.5, 0.09)), mat("concrete"))
	g.box((1.6, 1.6, 0.1), place((MAST[0], MAST[1], 0.09)), mat("concrete"))
	# Tyre tracks across the gravel.
	for dx in (-0.35, 0.35):
		g.box((0.45, 5.0, 0.03), place((0.9 + dx, -2.3, 0.09)), mat("gravel", -0.12))
	g.done(bevel=0.02)


def _cabin(c: Parts, cx, cy, z0, door: bool):
	"""One site cabin: blue walls, white corner frame, windows (and a door) on the front."""
	c.box((CW, CD, CH), place((cx, cy, z0 + CH / 2)), mat("cloth_blue", 0.18))
	for ex in (-1, 1):
		for ey in (-1, 1):
			c.box((0.14, 0.14, CH + 0.04), place((cx + ex * CW / 2, cy + ey * CD / 2, z0 + CH / 2)), mat("white"))
	for z in (z0 + 0.04, z0 + CH - 0.04):
		c.box((CW + 0.06, CD + 0.06, 0.1), place((cx, cy, z)), mat("white"))
	# Ribbed walls on the visible faces.
	x = cx - CW / 2 + 0.25
	while x < cx + CW / 2 - 0.1:
		c.box((0.05, 0.04, CH - 0.2), place((x, cy - CD / 2 - 0.02, z0 + CH / 2)), mat("cloth_blue", 0.05))
		x += 0.28
	front = cy - CD / 2
	spots = (-1.2, 0.2, 1.3) if not door else (-1.3, 0.0)
	for wx in spots:
		c.box((0.8, 0.06, 0.6), place((cx + wx, front - 0.03, z0 + 0.95)), mat("window"))
		c.box((0.92, 0.08, 0.08), place((cx + wx, front - 0.05, z0 + 1.28)), mat("white"))
		c.box((0.92, 0.08, 0.08), place((cx + wx, front - 0.05, z0 + 0.62)), mat("white"))
	if door:
		c.box((0.7, 0.08, 1.2), place((cx + 1.35, front - 0.04, z0 + 0.62)), mat("white"))
		c.box((0.3, 0.06, 0.3), place((cx + 1.35, front - 0.09, z0 + 0.95)), mat("window"))
		c.box((0.9, 0.5, 0.22), place((cx + 1.35, front - 0.3, 0.11)), mat("concrete_dark"))


def _cabins():
	c = Parts("cabins")
	for ex in (-1, 1):  # concrete blocks under the lower cabin
		for ey in (-1, 1):
			c.box((0.4, 0.4, LIFT), place((LOW[0] + ex * (CW / 2 - 0.3), LOW[1] + ey * (CD / 2 - 0.3), LIFT / 2)), mat("concrete_dark"))
	_cabin(c, LOW[0], LOW[1], LIFT, door=True)
	_cabin(c, UP[0], UP[1], LIFT + CH + 0.05, door=False)
	# Door on the upper cabin's side, opening onto the landing.
	z_up = LIFT + CH + 0.05
	side = UP[0] + CW / 2
	c.box((0.08, 0.7, 1.2), place((side + 0.04, UP[1] - 0.4, z_up + 0.62)), mat("white"))
	# Sign on the roof: a yellow board with a giant hard hat in front of it.
	roof = z_up + CH
	for dx in (-1.0, 1.0):
		c.box((0.1, 0.1, 0.6), place((UP[0] + dx, UP[1] + 0.3, roof + 0.3)), mat("metal_dark"))
	c.box((2.6, 0.12, 0.9), place((UP[0], UP[1] + 0.3, roof + 0.95)), mat("hazard"))
	c.box((2.7, 0.14, 0.08), place((UP[0], UP[1] + 0.28, roof + 1.4)), mat("wood_dark"))
	c.box((2.7, 0.14, 0.08), place((UP[0], UP[1] + 0.28, roof + 0.5)), mat("wood_dark"))
	# A dark hammer on the board.
	board = place((UP[0] + 0.75, UP[1] + 0.22, roof + 0.95))
	c.box((0.09, 0.04, 0.62), board @ place((0, 0, -0.05), (0, 35, 0)), mat("wood_dark"))
	c.box((0.36, 0.05, 0.14), board @ place((0.16, 0, 0.21), (0, 35, 0)), mat("window"))
	hat = place((UP[0], UP[1] - 0.1, roof + 0.08))  # sits on the roof, its lower half hidden
	c.ball(0.55, hat, mat("hazard", 0.08), squash=(1.1, 0.9, 0.85), detail=3)
	c.box((0.18, 1.0, 0.12), hat @ place((0, 0, 0.42)), mat("hazard", -0.12))
	c.cylinder(0.7, 0.07, hat @ place((0, -0.05, -0.02)), mat("hazard", -0.05), sides=24)
	c.done(bevel=0.025)


def _stairs():
	"""Steel staircase from the ground up to a landing by the upper cabin's door."""
	s = Parts("stairs")
	z_up = LIFT + CH + 0.05
	lx = UP[0] + CW / 2 + 0.45
	land_y = UP[1] - 0.4
	s.box((0.9, 1.0, 0.1), place((lx, land_y, z_up - 0.05)), mat("metal_dark"))
	for ex in (-0.4, 0.4):
		s.box((0.08, 0.08, z_up), place((lx + ex, land_y + 0.45, z_up / 2)), mat("metal_dark"))
	steps = 8
	run = 2.2
	for i in range(steps):
		y = land_y - 0.5 - (i + 0.5) * run / steps
		z = z_up - (i + 1) * z_up / (steps + 1)
		s.box((0.8, run / steps + 0.02, 0.06), place((lx, y, z)), mat("metal", -0.05))
	length = math.hypot(run, z_up)
	angle = math.degrees(math.atan2(z_up, run))
	for ex in (-0.42, 0.42):
		mid = Vector((lx + ex, land_y - 0.5 - run / 2, z_up / 2))
		s.box((0.06, length, 0.16), place(mid, (angle, 0, 0)), mat("hazard"))
		s.box((0.05, length, 0.05), place(mid + Vector((0, 0, 0.85)), (angle, 0, 0)), mat("hazard"))
		s.box((0.05, 0.05, 0.85), place((lx + ex, land_y - 0.5 - run * 0.25, z_up * 0.75 + 0.42)), mat("hazard"))
		s.box((0.05, 0.05, 0.85), place((lx + ex, land_y - 0.5 - run * 0.75, z_up * 0.25 + 0.42)), mat("hazard"))
	s.box((0.05, 1.0, 0.05), place((lx + 0.42, land_y, z_up + 0.85)), mat("hazard"))
	s.done(bevel=0.015)


def _lattice(p: Parts, a: Vector, b: Vector, width: float, height: float, up: Vector, material, bay=0.7):
	"""A lattice girder from a to b: three chords (two low, one high) with zigzag bracing."""
	run = b - a
	length = run.length
	u = run.normalized()
	side = up.cross(u).normalized()
	chords = [side * width / 2, -side * width / 2, up * height]
	for c in chords:
		p.box((0.08, 0.08, length), frame(a + c + run / 2, side, z_axis=u), material)
	n = max(1, round(length / bay))
	for i in range(n):
		p0 = a + u * (i * length / n)
		p1 = a + u * ((i + 1) * length / n)
		for c in chords[:2]:
			top = (p0 if i % 2 == 0 else p1) + up * height
			bottom = (p1 if i % 2 == 0 else p0) + c
			d = top - bottom
			p.box((0.05, 0.05, d.length), frame(bottom + d / 2, side, z_axis=d), material)


def _crane():
	c = Parts("crane")
	yellow = mat("hazard")
	mx, my = MAST
	w = 0.7
	# Concrete foot and the square lattice mast.
	c.box((1.3, 1.3, 0.4), place((mx, my, 0.3)), mat("concrete_dark"))
	for ex in (-1, 1):
		for ey in (-1, 1):
			c.box((0.1, 0.1, MAST_TOP), place((mx + ex * w / 2, my + ey * w / 2, MAST_TOP / 2 + 0.2)), yellow)
	z, i = 0.5, 0
	while z < MAST_TOP - 0.3:
		for face in range(4):
			a = math.radians(face * 90)
			n = Vector((math.cos(a), math.sin(a), 0))
			t = Vector((-n.y, n.x, 0))
			centre = Vector((mx, my, 0)) + n * w / 2
			lo = centre + t * (w / 2) * (1 if i % 2 else -1) + Vector((0, 0, z))
			hi = centre - t * (w / 2) * (1 if i % 2 else -1) + Vector((0, 0, z + w))
			d = hi - lo
			c.box((0.05, 0.05, d.length), frame(lo + d / 2, n, z_axis=d), yellow)
		c.box((w, w, 0.05), place((mx, my, z)), yellow)
		z += w
		i += 1
	# Turntable, cab, and the A-frame peak.
	c.box((1.1, 1.1, 0.3), place((mx, my, MAST_TOP + 0.15)), mat("metal_dark"))
	c.box((0.8, 0.8, 0.8), place((mx - 0.2, my - 0.75, MAST_TOP - 0.2)), mat("white"))
	c.box((0.82, 0.05, 0.4), place((mx - 0.2, my - 1.16, MAST_TOP - 0.05)), mat("window"))
	c.box((0.05, 0.6, 0.4), place((mx + 0.21, my - 0.75, MAST_TOP - 0.05)), mat("window"))
	peak = MAST_TOP + 2.0
	for ey in (-0.3, 0.3):
		c.box((0.1, 0.1, peak - JIB_Z), place((mx, my + ey, (peak + JIB_Z) / 2)), yellow)
	# Jib reaching out over the yard, and the shorter counter-jib with its weights.
	_lattice(c, Vector((mx, my, JIB_Z)), Vector((JIB_END, my, JIB_Z)), 0.55, 0.6, Vector((0, 0, 1)), yellow)
	_lattice(c, Vector((mx, my, JIB_Z)), Vector((COUNTER_END, my, JIB_Z)), 0.6, 0.35, Vector((0, 0, 1)), yellow)
	for i in range(3):
		c.box((0.3, 0.9, 0.9), place((COUNTER_END - 0.25 - i * 0.32, my, JIB_Z - 0.2)), mat("concrete_dark", -i * 0.05))
	# Tie cables from the peak to both ends.
	top = Vector((mx, my, peak))
	for end in (Vector((JIB_END + 1.8, my, JIB_Z + 0.6)), Vector((COUNTER_END - 0.4, my, JIB_Z + 0.35))):
		d = end - top
		c.box((0.035, 0.035, d.length), frame(top + d / 2, (0, 1, 0), z_axis=d), mat("metal_dark"))
	# Trolley, hook cable, hook block and a bundle of steel beams.
	ty = my
	c.box((0.5, 0.6, 0.18), place((TROLLEY_X, ty, JIB_Z - 0.1)), mat("metal_dark"))
	for dy in (-0.08, 0.08):
		c.cylinder(0.018, JIB_Z - LOAD_Z - 0.6, place((TROLLEY_X, ty + dy, (JIB_Z + LOAD_Z + 0.6) / 2)), mat("metal_dark"), sides=6)
	c.box((0.3, 0.32, 0.3), place((TROLLEY_X, ty, LOAD_Z + 0.55)), mat("hazard", -0.1))
	c.cylinder(0.06, 0.2, place((TROLLEY_X, ty, LOAD_Z + 0.32)), mat("metal_dark"), sides=8)
	for dx in (-0.8, 0.8):
		d = Vector((dx, 0, -0.35))
		c.box((0.03, 0.03, d.length), frame(Vector((TROLLEY_X, ty, LOAD_Z + 0.25)) + d / 2, (0, 1, 0), z_axis=d), mat("metal_dark"))
	for k, (dy, dz) in enumerate(((-0.17, 0), (0.17, 0), (0, 0.2))):
		_beam(c, place((TROLLEY_X, ty + dy, LOAD_Z - 0.2 + dz)), 2.2)
	c.done(bevel=0.012)


def _beam(p: Parts, m, length):
	"""A steel I-beam lying along X."""
	p.box((length, 0.24, 0.04), m @ place((0, 0, 0.08)), mat("metal_dark", 0.15))
	p.box((length, 0.24, 0.04), m @ place((0, 0, -0.08)), mat("metal_dark", 0.15))
	p.box((length, 0.04, 0.16), m, mat("metal_dark", 0.1))


def _props(r):
	p = Parts("props")
	# Stack of steel beams on wooden bearers.
	for dx in (-0.9, 0.9):
		p.box((0.2, 1.4, 0.15), place((-2.6 + dx, -1.1, 0.15)), mat("wood"))
	for row in range(3):
		for k in range(4 - row):
			_beam(p, place((-2.6, -1.55 + k * 0.28 + row * 0.14, 0.33 + row * 0.2)), 2.6)

	# Pallets of bricks.
	for (bx, by) in ((-3.9, -3.4), (-3.0, -3.6), (-3.6, -4.3)):
		p.box((0.8, 0.8, 0.14), place((bx, by, 0.11)), mat("wood"))
		for layer in range(3):
			for i in range(3):
				p.box((0.72, 0.22, 0.17), place((bx, by - 0.25 + i * 0.25, 0.27 + layer * 0.18), (0, 0, 90 * (layer % 2))), mat("brick", r.uniform(-0.08, 0.05)))

	# Sand pile with a shovel stuck in it.
	p.cylinder(1.0, 0.9, place((-0.8, -3.5, 0.45)), mat("dirt", 0.12), sides=14, top_radius=0.15)
	p.ball(0.25, place((-0.8, -3.5, 0.9)), mat("dirt", 0.12), squash=(1, 1, 0.5), detail=1)
	p.box((0.05, 0.05, 1.1), place((-0.55, -3.6, 1.1), (0, 25, 0)), mat("wood"))
	p.box((0.25, 0.04, 0.3), place((-0.78, -3.6, 0.65), (0, 25, 0)), mat("metal_dark"))

	# Cement mixer.
	mx, my = 1.9, -0.5
	p.box((1.1, 0.6, 0.12), place((mx, my, 0.45)), mat("metal_dark"))
	for dy in (-0.35, 0.35):
		p.cylinder(0.22, 0.1, place((mx - 0.35, my + dy, 0.22), (90, 0, 0)), mat("window", -0.3), sides=12)
	p.box((0.1, 0.1, 0.5), place((mx + 0.4, my, 0.25)), mat("metal_dark"))
	drum = place((mx, my, 0.95), (0, 55, 0))
	p.cylinder(0.45, 0.6, drum, mat("cloth_red"), sides=16, top_radius=0.3)
	p.cylinder(0.45, 0.35, drum @ place((0, 0, -0.45)), mat("cloth_red", -0.1), sides=16, top_radius=0.28)
	p.cylinder(0.24, 0.05, drum @ place((0, 0, 0.32)), mat("window", -0.3), sides=12)

	# Concrete pipes lying by the front right.
	for k, (px, py) in enumerate(((3.7, -3.4), (3.7, -2.5))):
		m = place((px, py, 0.5), (0, 90, 0))
		p.cylinder(0.5, 1.6, m, mat("concrete"), sides=18)
		p.cylinder(0.36, 1.62, m, mat("concrete_dark", -0.25), sides=18)
	p.cylinder(0.5, 1.6, place((3.7, -2.95, 1.35), (0, 90, 0)), mat("concrete", 0.04), sides=18)
	p.cylinder(0.36, 1.62, place((3.7, -2.95, 1.35), (0, 90, 0)), mat("concrete_dark", -0.25), sides=18)

	# Wheelbarrow.
	wb = place((1.4, -2.3, 0), (0, 0, -30))
	p.box((0.7, 0.5, 0.3), wb @ place((0, 0, 0.45), (0, 10, 0)), mat("cloth_blue", 0.1))
	p.cylinder(0.16, 0.08, wb @ place((0.45, 0, 0.18), (90, 0, 0)), mat("window", -0.3), sides=12)
	for dy in (-0.18, 0.18):
		p.box((0.9, 0.04, 0.04), wb @ place((-0.2, dy, 0.38), (0, -12, 0)), mat("metal_dark"))

	# Traffic cones and striped barriers along the front edge, open where the trucks drive in.
	for (cx, cy) in ((-0.2, -4.6), (2.0, -4.6), (4.6, -0.2), (-4.6, -1.9)):
		p.box((0.42, 0.42, 0.06), place((cx, cy, 0.03)), mat("cloth_red", -0.1))
		p.cylinder(0.17, 0.6, place((cx, cy, 0.33)), mat("cloth_red"), sides=12, top_radius=0.03)
		p.cylinder(0.12, 0.1, place((cx, cy, 0.38)), mat("white"), sides=12, top_radius=0.1)
	for x0, x1 in ((-4.6, -1.0), (2.8, 4.6)):
		y = -4.6
		for leg in (x0 + 0.15, x1 - 0.15):
			p.box((0.06, 0.4, 0.06), place((leg, y, 0.03)), mat("metal_dark"))
			p.box((0.06, 0.06, 0.75), place((leg, y, 0.4)), mat("metal_dark"))
		stripes = round((x1 - x0) / 0.35)
		for i in range(stripes):
			x = x0 + (i + 0.5) * (x1 - x0) / stripes
			p.box((((x1 - x0) / stripes) + 0.005, 0.06, 0.22), place((x, y - 0.04, 0.65)), mat("cloth_red" if i % 2 == 0 else "white"))
	p.done(bevel=0.02)
