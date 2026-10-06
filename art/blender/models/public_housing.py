"""PUBLIC HOUSING (1 tile): a three-storey cream apartment block with balconies (laundry hanging on
them), an entrance canopy, and a flat roof with a water tank, AC units and a stair hut; a pavement,
bins, a bench and a small tree in front. Plot is -2.5..2.5 on X and Y (see kit.py)."""
from kit import Parts, frame, mat, place, rng

TILES = 1

HX, HY, HW, HD = -0.2, 0.45, 3.7, 2.9
FRONT, SIDE = HY - HD / 2, HX + HW / 2
BASE, FLOOR, FLOORS = 0.2, 1.2, 3
ROOF = BASE + FLOOR * FLOORS
BAYS = (-1.35, -0.2, 0.95)  # window columns along the front
DOOR_BAY = 1


def build():
	r = rng(21)
	_pavement(r)
	_block(r)
	_balconies(r)
	_roof()
	_props(r)


def _wall(side: str, along: float, z: float):
	"""Placement on one of the visible walls: x runs along the wall, -y points out of it."""
	if side == "front":
		return place((along, FRONT, z))
	return frame((SIDE, along, z), (0, 1, 0), z_axis=(0, 0, 1))


def _pavement(r):
	g = Parts("pavement")
	g.box((4.8, FRONT + 2.4, 0.06), place((0, (FRONT - 2.4) / 2, 0.03)), mat("paving", -0.05))
	g.box((2.4 - SIDE, HD, 0.06), place(((SIDE + 2.4) / 2, HY, 0.03)), mat("paving", -0.05))
	x = -2.4
	while x < 2.4:  # paving joints
		g.box((0.03, FRONT + 2.4, 0.01), place((x, (FRONT - 2.4) / 2, 0.065)), mat("paving", -0.18))
		x += 0.6
	g.done(bevel=0.015)


def _window(p: Parts, side: str, along: float, z: float, w=0.6, h=0.62):
	m = _wall(side, along, z)
	p.box((w, 0.05, h), m @ place((0, -0.02, 0)), mat("window"))
	p.box((0.04, 0.07, h), m @ place((0, -0.04, 0)), mat("white"))
	for e in (-1, 1):
		p.box((0.07, 0.07, h + 0.1), m @ place((e * (w / 2 + 0.03), -0.04, 0)), mat("white"))
	p.box((w + 0.16, 0.14, 0.06), m @ place((0, -0.07, -h / 2 - 0.05)), mat("white"))
	p.box((w + 0.1, 0.07, 0.06), m @ place((0, -0.04, h / 2 + 0.04)), mat("white"))


def _block(r):
	b = Parts("block")
	b.box((HW + 0.08, HD + 0.08, BASE + FLOOR - 0.05), place((HX, HY, (BASE + FLOOR - 0.05) / 2)), mat("brick"))
	b.box((HW, HD, ROOF - BASE - FLOOR + 0.05), place((HX, HY, (ROOF + BASE + FLOOR - 0.05) / 2)), mat("plaster"))
	# Floor bands and a parapet round the flat roof.
	for k in range(1, FLOORS):
		b.box((HW + 0.06, HD + 0.06, 0.07), place((HX, HY, BASE + k * FLOOR)), mat("white"))
	b.box((HW + 0.14, HD + 0.14, 0.25), place((HX, HY, ROOF + 0.1)), mat("white"))
	b.box((HW - 0.12, HD - 0.12, 0.06), place((HX, HY, ROOF + 0.2)), mat("concrete_dark"))
	# Windows: three columns on the front, two on the side, on every floor.
	for k in range(FLOORS):
		z = BASE + k * FLOOR + 0.62
		for i, along in enumerate(BAYS):
			if k == 0 and i == DOOR_BAY:
				continue
			if k > 0 and i != DOOR_BAY:  # balcony doors behind the balconies
				_window(b, "front", along, z - 0.1, w=0.55, h=0.85)
			else:
				_window(b, "front", along, z)
		for along in (HY - 0.65, HY + 0.65):
			_window(b, "side", along, z)
	# Entrance: double door with a glass top, a canopy and two steps.
	dx = BAYS[DOOR_BAY]
	b.box((0.8, 0.06, 0.95), place((dx, FRONT - 0.02, BASE + 0.48)), mat("wood_dark"))
	b.box((0.66, 0.06, 0.3), place((dx, FRONT - 0.05, BASE + 0.72)), mat("window"))
	b.box((0.03, 0.07, 0.9), place((dx, FRONT - 0.05, BASE + 0.46)), mat("wood_dark", -0.2))
	b.box((1.2, 0.6, 0.08), place((dx, FRONT - 0.3, BASE + 1.08)), mat("cloth_blue"))
	for e in (-1, 1):
		b.box((0.04, 0.5, 0.04), place((dx + e * 0.5, FRONT - 0.3, BASE + 1.0), (-20, 0, 0)), mat("metal_dark"))
	b.box((1.1, 0.45, 0.1), place((dx, FRONT - 0.22, 0.05)), mat("concrete"))
	b.box((1.0, 0.25, 0.2), place((dx, FRONT - 0.12, 0.1)), mat("concrete"))
	# House number plate and a drainpipe on the side.
	b.box((0.22, 0.04, 0.16), place((dx + 0.6, FRONT - 0.03, BASE + 0.85)), mat("cloth_blue"))
	b.cylinder(0.04, ROOF, place((SIDE + 0.05, FRONT + 0.12, ROOF / 2)), mat("metal_dark"), sides=8)
	b.done(bevel=0.02)


def _balconies(r):
	p = Parts("balconies")
	colours = ("cloth_red", "cloth_blue", "hazard", "trim", "leaf", "cloth_red")
	for k in range(1, FLOORS):
		z = BASE + k * FLOOR
		for i, along in enumerate(BAYS):
			if i == DOOR_BAY:
				continue
			# Slab, white railing with posts.
			p.box((1.0, 0.55, 0.08), place((along, FRONT - 0.27, z)), mat("white"))
			p.box((1.0, 0.04, 0.45), place((along, FRONT - 0.53, z + 0.27)), mat("concrete", 0.08))
			for e in (-1, 1):
				p.box((0.04, 0.55, 0.45), place((along + e * 0.48, FRONT - 0.27, z + 0.27)), mat("concrete", 0.08))
			p.box((1.04, 0.07, 0.05), place((along, FRONT - 0.54, z + 0.52)), mat("white"))
			# A line of washing on some balconies, a plant pot on the others.
			if (i + k) % 2 == 0:
				p.box((0.9, 0.015, 0.015), place((along, FRONT - 0.3, z + 0.85)), mat("metal_dark"))
				for n in range(4):
					colour = colours[(i + k + n) % len(colours)]
					p.box((0.16, 0.03, 0.22 + (n % 2) * 0.08), place((along - 0.33 + n * 0.22, FRONT - 0.3, z + 0.72 - (n % 2) * 0.04)), mat(colour))
			else:
				p.cylinder(0.1, 0.16, place((along + 0.3, FRONT - 0.3, z + 0.12)), mat("terracotta"), sides=10)
				p.ball(0.14, place((along + 0.3, FRONT - 0.3, z + 0.28)), mat("leaf"), detail=1)
	p.done(bevel=0.012)


def _roof():
	t = Parts("roof things")
	top = ROOF + 0.23
	# Water tank on legs.
	tx, ty = HX - 0.9, HY + 0.7
	for ex in (-0.3, 0.3):
		for ey in (-0.3, 0.3):
			t.box((0.06, 0.06, 0.6), place((tx + ex, ty + ey, top + 0.3)), mat("metal_dark"))
	t.cylinder(0.48, 0.7, place((tx, ty, top + 0.95)), mat("metal"), sides=16)
	t.ball(0.5, place((tx, ty, top + 1.3)), mat("metal_dark"), squash=(1, 1, 0.35), detail=2)
	# Stair hut with a door, and AC units.
	sx, sy = HX + 0.9, HY + 0.6
	t.box((1.0, 0.9, 0.85), place((sx, sy, top + 0.42)), mat("plaster", -0.05))
	t.box((1.1, 1.0, 0.07), place((sx, sy, top + 0.88)), mat("white"))
	t.box((0.42, 0.04, 0.65), place((sx - 0.1, sy - 0.46, top + 0.33)), mat("wood_dark"))
	for ax, ay in ((HX + 1.3, HY - 0.75), (HX + 0.4, HY - 0.85)):
		t.box((0.5, 0.36, 0.34), place((ax, ay, top + 0.17)), mat("white", -0.05))
		t.cylinder(0.12, 0.04, place((ax, ay - 0.19, top + 0.17), (90, 0, 0)), mat("metal_dark"), sides=12)
	# TV antenna.
	t.cylinder(0.02, 0.9, place((HX - 1.5, HY - 0.9, top + 0.45)), mat("metal_dark"), sides=6)
	for z, w in ((0.7, 0.5), (0.85, 0.35)):
		t.box((w, 0.03, 0.03), place((HX - 1.5, HY - 0.9, top + z)), mat("metal_dark"))
	t.done(bevel=0.015)


def _props(r):
	p = Parts("props")
	for k, by in enumerate((FRONT + 0.35, FRONT + 0.8)):  # bins along the side wall
		p.box((0.34, 0.34, 0.46), place((SIDE + 0.3, by, 0.29)), mat("leaf", -0.2 + k * 0.1))
		p.box((0.38, 0.38, 0.06), place((SIDE + 0.3, by, 0.55)), mat("leaf", -0.32))
	# Bench and a small tree on the pavement.
	m = place((HX - 1.3, -1.95, 0))
	p.box((0.9, 0.3, 0.05), m @ place((0, 0, 0.3)), mat("wood"))
	p.box((0.9, 0.05, 0.25), m @ place((0, 0.15, 0.48)), mat("wood"))
	for e in (-0.38, 0.38):
		p.box((0.05, 0.3, 0.3), m @ place((e, 0, 0.15)), mat("metal_dark"))
	p.cylinder(0.3, 0.05, place((1.75, -1.9, 0.08)), mat("soil_dark"), sides=14)
	p.cylinder(0.06, 1.2, place((1.75, -1.9, 0.6)), mat("wood_dark"), sides=8)
	for (dx, dy, dz), rad in (((0, 0, 1.45), 0.5), ((0.25, -0.15, 1.25), 0.35), ((-0.25, 0.1, 1.3), 0.35)):
		p.ball(rad, place((1.75 + dx, -1.9 + dy, dz)), mat("leaf", r.uniform(-0.06, 0.06)), detail=2)
	# Bicycle leaning by the wall.
	b = place((HX - 1.55, FRONT - 0.25, 0))
	for dx in (-0.3, 0.3):
		p.cylinder(0.22, 0.03, b @ place((dx, 0, 0.24), (90, 0, 0)), mat("window", -0.2), sides=14)
	p.box((0.6, 0.03, 0.03), b @ place((0, 0, 0.36)), mat("cloth_red"))
	p.box((0.03, 0.03, 0.3), b @ place((0.22, 0, 0.42)), mat("cloth_red"))
	p.box((0.03, 0.03, 0.3), b @ place((-0.12, 0, 0.42)), mat("cloth_red"))
	p.done(bevel=0.012)
