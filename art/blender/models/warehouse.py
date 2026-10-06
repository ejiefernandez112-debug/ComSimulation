"""WAREHOUSE (2x2 tiles): a big grey ribbed shed with a red corrugated roof, a raised loading dock
with two roll-up doors (one half open, crates inside), a yellow forklift carrying a pallet, and
pallets, crates and barrels on a concrete apron. Plot is -5..5 on X and Y (see kit.py for which
sides the player sees)."""
from mathutils import Vector

from kit import Parts, frame, mat, place, rng

TILES = 2

HX, HY, HW, HD = -0.45, 1.75, 7.6, 4.6
FRONT, SIDE = HY - HD / 2, HX + HW / 2
WALL, RIDGE = 3.6, 4.6
DOCK_H, DOCK_D = 0.8, 1.1  # loading dock height and depth
DOCK_X0, DOCK_X1 = -4.0, 2.2
DOORS = (-2.55, 0.45)  # door centres along the front
DOOR_W, DOOR_TOP = 2.0, 2.95


def build():
	r = rng(4)
	_apron()
	_shed(r)
	_roof(r)
	_dock(r)
	_forklift()
	_props(r)


def _apron():
	g = Parts("apron")
	g.box((9.6, FRONT + 4.8, 0.08), place((0, (FRONT - 4.8) / 2, 0.04)), mat("concrete_dark", 0.05))
	g.box((4.8 - SIDE, HD, 0.08), place(((SIDE + 4.8) / 2, HY, 0.04)), mat("concrete_dark", 0.05))
	# White lines marking the loading bays.
	for x in (-4.0, -1.05, 1.95):
		g.box((0.08, 2.4, 0.02), place((x, FRONT - DOCK_D - 1.4, 0.09)), mat("white"))
	g.done(bevel=0.02)


def _shed(r):
	s = Parts("shed")
	# Brick footing band, then ribbed metal walls with gable ends at both X ends.
	s.box((HW + 0.1, HD + 0.1, 0.9), place((HX, HY, 0.45)), mat("brick_dark"))
	outline = [(-HD / 2, 0.9), (HD / 2, 0.9), (HD / 2, WALL), (0, RIDGE), (-HD / 2, WALL)]
	s.prism(outline, HW, frame((HX, HY, 0), (0, 1, 0), z_axis=(0, 0, 1)), mat("metal", 0.05))
	x = HX - HW / 2 + 0.2
	while x < SIDE - 0.1:
		if all(abs(x - d) > DOOR_W / 2 + 0.1 for d in DOORS):
			s.box((0.07, 0.06, WALL - 0.95), place((x, FRONT - 0.02, (WALL + 0.95) / 2)), mat("metal", -0.12))
		x += 0.3
	y = FRONT + 0.2
	while y < HY + HD / 2 - 0.1:
		top = WALL + (RIDGE - WALL) * (1 - abs(y - HY) / (HD / 2)) - 0.1
		s.box((0.06, 0.07, top - 0.95), place((SIDE + 0.02, y, (top + 0.95) / 2)), mat("metal", -0.12))
		y += 0.3
	for cx, cy in ((SIDE, FRONT), (HX - HW / 2, FRONT), (SIDE, HY + HD / 2)):
		s.box((0.22, 0.22, WALL), place((cx, cy, WALL / 2)), mat("metal_dark"))
	s.box((HW + 0.1, 0.12, 0.16), place((HX, FRONT - 0.04, WALL - 0.05)), mat("metal_dark"))

	# Two roll-up doors: the left one shut, the right one half open showing crates inside.
	for i, dx in enumerate(DOORS):
		bottom = DOCK_H
		s.box((DOOR_W + 0.3, 0.12, 0.14), place((dx, FRONT - 0.05, DOOR_TOP + 0.07)), mat("hazard"))
		for e in (-1, 1):
			s.box((0.14, 0.12, DOOR_TOP - bottom), place((dx + e * (DOOR_W / 2 + 0.08), FRONT - 0.05, (DOOR_TOP + bottom) / 2)), mat("hazard"))
		shut_to = bottom if i == 0 else bottom + 1.25
		s.box((DOOR_W, 0.06, DOOR_TOP - shut_to), place((dx, FRONT - 0.02, (DOOR_TOP + shut_to) / 2)), mat("metal_dark", 0.12))
		z = shut_to + 0.12
		while z < DOOR_TOP - 0.05:
			s.box((DOOR_W, 0.08, 0.04), place((dx, FRONT - 0.04, z)), mat("metal_dark", -0.05))
			z += 0.2
		if i == 1:
			s.box((DOOR_W, 0.04, shut_to - bottom), place((dx, FRONT + 0.02, (shut_to + bottom) / 2)), mat("window", -0.45))
			for k, (cx, cz, size) in enumerate(((-0.45, 0.32, 0.6), (0.25, 0.3, 0.55), (0.25, 0.85, 0.5), (0.75, 0.25, 0.45))):
				s.box((size, 0.5, size), place((dx + cx, FRONT + 0.35, bottom + cz), (0, 0, r.uniform(-8, 8))), mat("wood_light", r.uniform(-0.1, 0.05)))

	# Big sign board above the doors: a white board with a red box picture.
	s.box((2.6, 0.1, 0.5), place((HX + 2.4, FRONT - 0.06, 3.25)), mat("white"))
	s.box((0.4, 0.06, 0.3), place((HX + 1.65, FRONT - 0.12, 3.25)), mat("barn_red"))
	for i in range(3):
		s.box((1.3 - i * 0.3, 0.06, 0.06), place((HX + 2.6 - i * 0.15, FRONT - 0.12, 3.37 - i * 0.12)), mat("window"))

	# Office door and window on the side the player sees.
	s.box((0.08, 0.95, 2.0), place((SIDE + 0.04, FRONT + 1.0, 1.0)), mat("barn_red"))
	s.box((0.1, 1.15, 0.12), place((SIDE + 0.05, FRONT + 1.0, 2.06)), mat("white"))
	s.box((0.8, 1.2, 0.15), place((SIDE + 0.4, FRONT + 1.0, 0.075)), mat("concrete"))
	for wy in (FRONT + 2.4, FRONT + 3.6):
		s.box((0.06, 0.9, 0.7), place((SIDE + 0.04, wy, 1.7)), mat("window"))
		s.box((0.1, 1.04, 0.08), place((SIDE + 0.06, wy, 2.07)), mat("white"))
		s.box((0.12, 1.04, 0.08), place((SIDE + 0.08, wy, 1.33)), mat("white"))
	s.done(bevel=0.03)


def _roof(r):
	slab = Parts("roof")
	ribs = Parts("roof ribs")
	length = HW + 0.5
	for sign in (-1, 1):
		eave = Vector((HX, HY + sign * HD / 2, WALL))
		ridge = Vector((HX, HY, RIDGE))
		u = (ridge - eave).normalized()
		w = Vector((0, -u.z, u.y))
		if w.z < 0:
			w = -w
		start = eave - u * 0.35
		run = (ridge - start).length + 0.05
		slab.box((length, run, 0.12), frame(start + u * run / 2 + w * 0.06, (1, 0, 0), z_axis=w), mat("barn_red"))
		x = HX - length / 2 + 0.12
		while x < HX + length / 2:
			ribs.box((0.07, run, 0.06), frame(Vector((x, 0, 0)) + start + u * run / 2 + w * 0.15, (1, 0, 0), z_axis=w), mat("barn_red", -0.12))
			x += 0.3
		# Two strips of skylights on the front slope.
		if sign < 0:
			for sx in (HX - 1.8, HX + 1.8):
				slab.box((1.3, run * 0.55, 0.06), frame(Vector((sx, 0, 0)) + start + u * run * 0.5 + w * 0.2, (1, 0, 0), z_axis=w), mat("white", -0.12))
	slab.box((length, 0.35, 0.12), place((HX, HY, RIDGE + 0.13)), mat("barn_red", -0.18))
	# Round vents on the ridge.
	for vx in (HX - 2.6, HX + 0.2, HX + 2.8):
		slab.cylinder(0.24, 0.5, place((vx, HY, RIDGE + 0.4)), mat("metal"), sides=14)
		slab.cylinder(0.34, 0.14, place((vx, HY, RIDGE + 0.72)), mat("metal_dark"), sides=14, top_radius=0.1)
	slab.done(bevel=0.03)
	ribs.done(bevel=0.0)


def _dock(r):
	d = Parts("dock")
	cx = (DOCK_X0 + DOCK_X1) / 2
	width = DOCK_X1 - DOCK_X0
	d.box((width, DOCK_D, DOCK_H), place((cx, FRONT - DOCK_D / 2, DOCK_H / 2)), mat("concrete"))
	# Yellow-and-black edge stripes and black rubber bumpers.
	stripes = round(width / 0.3)
	for i in range(stripes):
		x = DOCK_X0 + (i + 0.5) * width / stripes
		d.box((width / stripes + 0.004, 0.04, 0.14), place((x, FRONT - DOCK_D - 0.02, DOCK_H - 0.08)), mat("hazard" if i % 2 == 0 else "window", -0.2 if i % 2 else 0.0))
	for bx in DOORS:
		for e in (-1, 1):
			d.box((0.24, 0.16, 0.4), place((bx + e * 0.75, FRONT - DOCK_D - 0.08, DOCK_H - 0.4)), mat("window", -0.4))
	# Steps up to the dock at its right end, with a railing.
	for i in range(4):
		h = DOCK_H * (i + 1) / 5
		d.box((0.3, DOCK_D, h), place((DOCK_X1 + 1.05 - i * 0.28, FRONT - DOCK_D / 2, h / 2)), mat("concrete", -0.05))
	for x in (DOCK_X0, DOCK_X1):  # railing posts at the dock ends
		d.box((0.05, 0.05, 1.0), place((x, FRONT - DOCK_D + 0.05, DOCK_H + 0.5)), mat("hazard"))
	# Yellow bollards in front of the dock corners.
	for bx in (DOCK_X0 - 0.35, SIDE + 0.5):
		d.cylinder(0.14, 0.9, place((bx, FRONT - DOCK_D - 0.3, 0.45)), mat("hazard"), sides=12)
		d.ball(0.14, place((bx, FRONT - DOCK_D - 0.3, 0.9)), mat("hazard"), detail=1)
		d.cylinder(0.145, 0.1, place((bx, FRONT - DOCK_D - 0.3, 0.6)), mat("window", -0.3), sides=12)
	d.done(bevel=0.02)


def _pallet(p: Parts, m):
	p.box((1.0, 0.8, 0.05), m @ place((0, 0, 0.13)), mat("wood_light"))
	for dx in (-0.42, 0.0, 0.42):
		p.box((0.12, 0.8, 0.1), m @ place((dx, 0, 0.05)), mat("wood"))


def _forklift():
	f = Parts("forklift")
	m = place((2.7, -3.1, 0), (0, 0, 115))  # its forks point toward the dock
	f.box((1.3, 0.9, 0.55), m @ place((0, 0, 0.55)), mat("hazard"))
	f.box((0.5, 0.86, 0.5), m @ place((-0.45, 0, 1.0)), mat("hazard", -0.08))  # counterweight hump
	f.box((0.5, 0.6, 0.1), m @ place((0.1, 0, 0.88)), mat("window", -0.3))  # seat
	f.box((0.22, 0.5, 0.35), m @ place((-0.12, 0, 1.08)), mat("window", -0.3))
	for e in (-1, 1):  # roll cage
		f.box((0.07, 0.07, 1.3), m @ place((0.4, e * 0.4, 1.45)), mat("metal_dark"))
		f.box((0.07, 0.07, 1.3), m @ place((-0.35, e * 0.4, 1.45)), mat("metal_dark"))
	f.box((0.85, 0.9, 0.06), m @ place((0.02, 0, 2.1)), mat("metal_dark"))
	for wx in (0.42, -0.42):
		for e in (-1, 1):
			f.cylinder(0.24, 0.18, m @ place((wx, e * 0.46, 0.24), (90, 0, 0)), mat("window", -0.35), sides=14)
			f.cylinder(0.12, 0.2, m @ place((wx, e * 0.46, 0.24), (90, 0, 0)), mat("metal"), sides=10)
	# Mast with forks, carrying a pallet of boxes.
	for e in (-1, 1):
		f.box((0.1, 0.1, 2.2), m @ place((0.72, e * 0.3, 1.1)), mat("metal_dark"))
		f.box((0.9, 0.12, 0.05), m @ place((1.2, e * 0.22, 0.38)), mat("metal_dark"))
	f.box((0.08, 0.8, 0.5), m @ place((0.76, 0, 0.6)), mat("metal_dark"))
	_pallet(f, m @ place((1.25, 0, 0.3)))
	for k, (bx, by, bz) in enumerate(((1.05, -0.2, 0.0), (1.05, 0.2, 0.0), (1.45, -0.2, 0.0), (1.45, 0.2, 0.0), (1.25, 0.0, 0.38))):
		f.box((0.36, 0.36, 0.36), m @ place((bx, by, 0.66 + bz)), mat("sack" if k % 2 else "wood_light", -0.05 * k))
	f.done(bevel=0.025)


def _props(r):
	p = Parts("props")
	# Stacks of crates on pallets at the front left.
	for (px, py, turn, layers) in ((-3.9, -3.0, 5, 2), (-2.6, -3.7, -8, 1), (-4.0, -4.2, 15, 1)):
		m = place((px, py, 0), (0, 0, turn))
		_pallet(p, m)
		for layer in range(layers):
			for i, (bx, by) in enumerate(((-0.25, -0.2), (0.25, -0.2), (-0.25, 0.2), (0.25, 0.2))):
				if layer == 1 and i == 3:
					continue
				p.box((0.46, 0.38, 0.4), m @ place((bx, by, 0.36 + layer * 0.41)), mat("wood_light", r.uniform(-0.1, 0.05)))
	# Barrels by the side wall.
	for k, (bx, by) in enumerate(((SIDE + 0.55, HY + 0.6), (SIDE + 1.1, HY + 0.85), (SIDE + 0.6, HY + 1.2), (SIDE + 1.05, HY + 1.5))):
		colour = ("cloth_blue", "cloth_red")[k % 2]
		p.cylinder(0.27, 0.8, place((bx, by, 0.4)), mat(colour), sides=16)
		for z in (0.2, 0.6):
			p.cylinder(0.285, 0.05, place((bx, by, z)), mat(colour, -0.2), sides=16)
		p.cylinder(0.27, 0.02, place((bx, by, 0.81)), mat(colour, 0.12), sides=16)
	# Hand truck with a box.
	ht = place((-0.6, -2.7, 0), (0, 0, -20))
	p.box((0.05, 0.05, 1.2), ht @ place((-0.2, -0.15, 0.6), (0, -12, 0)), mat("cloth_red"))
	p.box((0.05, 0.05, 1.2), ht @ place((-0.2, 0.15, 0.6), (0, -12, 0)), mat("cloth_red"))
	p.box((0.3, 0.4, 0.04), ht @ place((0.02, 0, 0.04)), mat("metal_dark"))
	p.box((0.4, 0.4, 0.4), ht @ place((0.05, 0, 0.27)), mat("wood_light"))
	for e in (-0.2, 0.2):
		p.cylinder(0.12, 0.06, ht @ place((-0.22, e, 0.12), (90, 0, 0)), mat("window", -0.3), sides=12)
	# Bushes at the back corners.
	for at, rad in (((4.4, 4.3), 0.42), ((-4.5, 4.4), 0.38), ((4.45, -4.4), 0.32)):
		p.ball(rad, place((*at, rad * 0.8)), mat("leaf", r.uniform(-0.08, 0.06)), squash=(1, 1, 0.9), detail=2)
	p.done(bevel=0.025)
