"""WHEAT FARM (2x2 tiles): red barn with a cupola at the back, a silo, a fenced wheat field with a
scarecrow, and a dirt yard with hay bales, sacks and a cart. Plot is -5..5 on X and Y (see kit.py
for which sides the player sees)."""
import math

from mathutils import Vector

from kit import Parts, frame, mat, place, rng

TILES = 2
EDGE = 4.75  # fence line, just inside the plot

# Barn: centre, width (X), depth (Y). Its gable end with the big doors faces -Y (lower left on screen).
BX, BY, BW, BD = -2.45, 2.5, 3.6, 4.0
BASE = 0.35  # stone foundation height
# Barn cross-section (x across the barn, z up): walls, then the two-slope "gambrel" roof line.
EAVE, KNEE, RIDGE = 2.1, (1.2, 3.15), 3.75
OUTLINE = [(-BW / 2, BASE), (BW / 2, BASE), (BW / 2, EAVE), KNEE, (0, RIDGE), (-KNEE[0], KNEE[1]), (-BW / 2, EAVE)]

FIELD = (0.25, 4.55, -4.55, 2.6)  # x from, x to, y from, y to
SCARECROW = (2.45, -1.0)
SILO = (1.5, 3.9)


def build():
	r = rng(7)
	_ground()
	_barn(r)
	_roof(r)
	_silo()
	_field(r)
	_fence(r)
	_props(r)


def _ground():
	g = Parts("ground")
	x0, x1, y0, y1 = FIELD
	g.box((x1 - x0, y1 - y0, 0.14), place(((x0 + x1) / 2, (y0 + y1) / 2, 0.07)), mat("soil_dark"))
	# Dirt yard and path from the barn doors to the gate.
	yard = [(-3.6, 0.45), (-1.3, 0.45), (-0.7, -0.6), (-0.9, -2.2), (-1.3, -3.4), (-1.05, -4.7),
		(-3.7, -4.7), (-3.6, -3.3), (-4.2, -2.0), (-4.1, -0.6)]
	g.prism(yard, 0.05, frame((0, 0, 0.025), (1, 0, 0), z_axis=(0, 1, 0)), mat("dirt"))
	g.done(bevel=0.04)


def _barn(r):
	b = Parts("barn")
	front, side = BY - BD / 2, BX + BW / 2  # the two faces the player sees
	b.box((BW + 0.14, BD + 0.14, BASE), place((BX, BY, BASE / 2)), mat("stone"))
	b.prism(OUTLINE, BD, place((BX, BY, 0)), mat("barn_red"))

	# Board-and-batten walls: thin upright strips on the visible faces.
	x = -BW / 2 + 0.2
	while x < BW / 2 - 0.1:
		top = _roofline(x) - 0.12
		b.box((0.07, 0.05, top - BASE), place((BX + x, front - 0.025, (top + BASE) / 2)), mat("barn_red", -0.12))
		x += 0.3
	y = -BD / 2 + 0.25
	while y < BD / 2 - 0.1:
		b.box((0.05, 0.07, EAVE - BASE - 0.1), place((side + 0.025, BY + y, (EAVE + BASE) / 2)), mat("barn_red", -0.12))
		y += 0.3
	# White corner boards.
	for cx, cy in ((-1, -1), (1, -1), (1, 1)):
		b.box((0.18, 0.18, EAVE - BASE), place((BX + cx * BW / 2, BY + cy * BD / 2, (EAVE + BASE) / 2)), mat("trim"))

	# Big double doors with white frames and X braces.
	door_w, door_h = 0.8, 1.7
	for side_sign in (-1, 1):
		cx = BX + side_sign * (door_w / 2 + 0.02)
		cz = BASE + door_h / 2
		b.box((door_w, 0.08, door_h), place((cx, front - 0.08, cz)), mat("barn_red", 0.06))
		angle = math.degrees(math.atan2(door_h - 0.2, door_w - 0.2))
		for a in (angle, -angle):
			b.box((math.hypot(door_w - 0.2, door_h - 0.2), 0.05, 0.09), place((cx, front - 0.13, cz), (0, a, 0)), mat("trim"))
		for z in (BASE + 0.08, BASE + door_h - 0.08):
			b.box((door_w, 0.06, 0.12), place((cx, front - 0.13, z)), mat("trim"))
		b.box((0.09, 0.06, door_h), place((cx + side_sign * (door_w / 2 - 0.05), front - 0.13, cz)), mat("trim"))
	b.box((door_w * 2 + 0.4, 0.12, 0.16), place((BX, front - 0.1, BASE + door_h + 0.1)), mat("trim"))
	b.ball(0.05, place((BX + 0.12, front - 0.18, BASE + 0.9)), mat("metal_dark"), detail=1)  # handles
	b.ball(0.05, place((BX - 0.12, front - 0.18, BASE + 0.9)), mat("metal_dark"), detail=1)

	# Hayloft: dark opening with hay spilling out, white frame, and a hoist beam above it.
	lz = 2.75
	b.box((0.8, 0.06, 0.7), place((BX, front - 0.07, lz)), mat("window", -0.3))
	for dx in (-0.45, 0.45):
		b.box((0.1, 0.08, 0.86), place((BX + dx, front - 0.08, lz)), mat("trim"))
	for dz in (-0.4, 0.4):
		b.box((1.0, 0.08, 0.1), place((BX, front - 0.08, lz + dz)), mat("trim"))
	for i in range(5):
		b.ball(0.16, place((BX - 0.3 + i * 0.15, front - 0.1, lz - 0.22 + r.uniform(-0.03, 0.05))), mat("hay", r.uniform(-0.08, 0.06)), squash=(1.2, 0.8, 0.8), detail=1)
	b.box((0.14, 0.7, 0.14), place((BX, front - 0.25, 3.45)), mat("wood_dark"))
	b.cylinder(0.015, 0.5, place((BX, front - 0.52, 3.15)), mat("wood_dark"), sides=6)
	b.cylinder(0.06, 0.06, place((BX, front - 0.52, 2.9), (90, 0, 0)), mat("metal_dark"), sides=10)

	# Windows on the long side.
	for wy in (BY - 1.0, BY + 1.0):
		b.box((0.04, 0.6, 0.7), place((side + 0.04, wy, 1.35)), mat("window"))
		b.box((0.06, 0.06, 0.7), place((side + 0.07, wy, 1.35)), mat("trim"))
		b.box((0.06, 0.6, 0.06), place((side + 0.07, wy, 1.35)), mat("trim"))
		for dy in (-0.34, 0.34):
			b.box((0.08, 0.1, 0.86), place((side + 0.07, wy + dy, 1.35)), mat("trim"))
		for dz in (-0.39, 0.39):
			b.box((0.08, 0.78, 0.1), place((side + 0.07, wy, 1.35 + dz)), mat("trim"))
		b.box((0.14, 0.86, 0.06), place((side + 0.1, wy, 0.92)), mat("trim"))  # sill
	b.done(bevel=0.04)

	# Cupola on the ridge, with a weathervane.
	c = Parts("cupola")
	cz = RIDGE + 0.3
	c.box((0.62, 0.62, 0.7), place((BX, BY, cz + 0.05)), mat("barn_red"))
	for i in range(4):
		z = cz + 0.15 + i * 0.1
		c.box((0.64, 0.5, 0.04), place((BX, BY, z)), mat("trim"))
		c.box((0.5, 0.64, 0.04), place((BX, BY, z)), mat("trim"))
	c.cylinder(0.56, 0.45, place((BX, BY, cz + 0.62), (0, 0, 45)), mat("roof_dark"), sides=4, top_radius=0.02)
	c.cylinder(0.02, 0.55, place((BX, BY, cz + 1.0)), mat("metal_dark"), sides=6)
	c.box((0.42, 0.02, 0.06), place((BX, BY, cz + 1.12), (0, 0, 45)), mat("metal_dark"))
	c.cylinder(0.07, 0.14, place((BX + 0.15, BY + 0.15, cz + 1.12), (0, 90, 45)), mat("metal_dark"), sides=3, top_radius=0)
	c.done(bevel=0.02)


def _roofline(x: float) -> float:
	"""Height of the barn's roof line at x (across the barn), for the wall strips."""
	x = abs(x)
	kx, kz = KNEE
	if x <= kx:
		return RIDGE - (RIDGE - kz) * x / kx
	return EAVE + (kz - EAVE) * (BW / 2 - x) / (BW / 2 - kx)


def _roof(r):
	"""Four roof slopes (two each side), covered in rows of slightly lifted shingles."""
	slab = Parts("roof")
	tiles = Parts("roof tiles")
	trim = Parts("roof trim")
	length = BD + 0.5  # overhangs front and back
	front = BY - length / 2
	for sign in (-1, 1):
		lower = (Vector((sign * BW / 2, 0, EAVE)), Vector((sign * KNEE[0], 0, KNEE[1])))
		upper = (lower[1], Vector((0, 0, RIDGE)))
		for (p, q), overhang in ((lower, 0.35), (upper, 0.0)):
			p = p + Vector((BX, 0, 0))
			q = q + Vector((BX, 0, 0))
			u = (q - p).normalized()
			w = Vector((-u.z, 0, u.x)) * sign  # points out of the roof
			if w.z < 0:
				w = -w
			start = p - u * overhang
			run = (q - start).length + 0.06
			slab.box((run, length, 0.12), frame(start + u * run / 2 + w * 0.08 + Vector((0, BY, 0)), u, z_axis=w), mat("roof_dark"))
			# White trim board along the front edge of the slope.
			trim.box((run + 0.05, 0.1, 0.24), frame(start + u * run / 2 + w * 0.1 + Vector((0, front - 0.02, 0)), u, z_axis=w), mat("trim"))
			# Shingle rows from the eave up.
			lift = 0.12
			tu = (u - w * lift).normalized()
			tw = (w + u * lift).normalized()
			s, row = 0.0, 0
			while s < run - 0.15:
				y = -length / 2 + (0.25 if row % 2 else 0.0)
				while y < length / 2 - 0.05:
					seg = min(0.5, length / 2 - y)
					at = start + u * (s + 0.21) + w * 0.18 + Vector((0, BY + y + seg / 2, 0))
					tiles.box((0.42, seg - 0.04, 0.05), frame(at, tu, z_axis=tw), mat("roof", r.choice((-0.08, -0.03, 0.0, 0.05))))
					y += seg
				s += 0.3
				row += 1
	# Rounded cap along the ridge.
	slab.cylinder(0.13, length + 0.04, place((BX, BY, RIDGE + 0.2), (90, 0, 0)), mat("roof_dark"), sides=10)
	slab.done(bevel=0.03)
	tiles.done(bevel=0.012)
	trim.done(bevel=0.03)


def _silo():
	s = Parts("silo")
	sx, sy = SILO
	radius, top = 0.72, 3.95
	s.cylinder(radius + 0.1, 0.35, place((sx, sy, 0.175)), mat("stone"), sides=24)
	s.cylinder(radius, top - 0.35, place((sx, sy, (top + 0.35) / 2)), mat("metal"), sides=24)
	z = 0.6
	while z < top - 0.1:
		s.cylinder(radius + 0.03, 0.06, place((sx, sy, z)), mat("metal_dark"), sides=24)
		z += 0.45
	s.ball(radius + 0.03, place((sx, sy, top)), mat("barn_red"), squash=(1, 1, 0.65), detail=3)
	s.cylinder(0.14, 0.25, place((sx, sy, top + 0.55)), mat("metal_dark"), sides=10)
	s.cylinder(0.2, 0.08, place((sx, sy, top + 0.7)), mat("barn_red"), sides=10, top_radius=0.06)
	# Ladder on the side facing the camera.
	out = Vector((1, -1, 0)).normalized()
	across = Vector((1, 1, 0)).normalized()
	centre = Vector((sx, sy, 0)) + out * (radius + 0.08)
	for k in (-0.14, 0.14):
		s.cylinder(0.025, top - 0.2, place(centre + across * k + Vector((0, 0, (top + 0.2) / 2))), mat("metal_dark"), sides=6)
	z = 0.55
	while z < top - 0.1:
		s.box((0.03, 0.28, 0.03), frame(centre + Vector((0, 0, z)), out, z_axis=(0, 0, 1)), mat("metal_dark"))
		z += 0.28
	s.done(bevel=0.02)


def _field(r):
	"""Soil ridges with rows of wheat tufts, each tuft a handful of stalks with golden ears."""
	soil = Parts("field ridges")
	wheat = Parts("wheat")
	x0, x1, y0, y1 = FIELD
	x = x0 + 0.3
	while x < x1 - 0.2:
		soil.box((0.32, y1 - y0 - 0.3, 0.12), place((x, (y0 + y1) / 2, 0.18)), mat("soil"))
		y = y0 + 0.25
		while y < y1 - 0.15:
			if (Vector((x, y)) - Vector(SCARECROW)).length > 0.45:
				_tuft(wheat, r, Vector((x + r.uniform(-0.04, 0.04), y + r.uniform(-0.05, 0.05), 0.22)))
			y += 0.26
		x += 0.42
	soil.done(bevel=0.04)
	wheat.done(bevel=0)


def _tuft(parts: Parts, r, base: Vector):
	for _ in range(6):
		root = base + Vector((r.uniform(-0.1, 0.1), r.uniform(-0.1, 0.1), 0))
		up = Vector((r.uniform(-0.18, 0.18), r.uniform(-0.18, 0.18), 1)).normalized()
		h = r.uniform(0.5, 0.72)
		parts.box((0.03, 0.03, h), frame(root + up * h / 2, (1, 0, 0), z_axis=up), mat("stalk"))
		parts.ball(0.05, frame(root + up * (h + 0.07), (1, 0, 0), z_axis=up), mat(r.choice(("wheat", "wheat", "wheat_light"))), squash=(1, 1, 2.6), detail=1)


def _fence(r):
	"""Wooden fence around the plot, open where the yard path leaves."""
	f = Parts("fence")
	posts = 10  # sections per side
	gate = (1, 2, 3)  # open sections of the front side (y = -EDGE)
	corners = [Vector((-EDGE, -EDGE)), Vector((EDGE, -EDGE)), Vector((EDGE, EDGE)), Vector((-EDGE, EDGE))]
	for i in range(4):
		a, b = corners[i], corners[(i + 1) % 4]
		front = i == 0
		for k in range(posts):
			p, q = a.lerp(b, k / posts), a.lerp(b, (k + 1) / posts)
			if not (front and k in gate[1:]):  # no posts standing in the opening
				h = 0.95 if front and k == gate[0] else 0.75  # taller gate post
				f.box((0.15, 0.15, h), place((p.x, p.y, h / 2), (0, 0, r.uniform(-6, 6))), mat("wood", r.uniform(-0.1, 0.05)))
			if front and k in gate:
				continue
			if front and k == gate[-1] + 1:  # the other gate post
				f.box((0.16, 0.16, 0.95), place((p.x, p.y, 0.475)), mat("wood"))
			mid = (p + q) / 2
			d = q - p
			for z in (0.32, 0.6):
				f.box((d.length + 0.1, 0.07, 0.11), place((mid.x, mid.y, z + r.uniform(-0.02, 0.02)), (0, 0, math.degrees(math.atan2(d.y, d.x)))), mat("wood_light", r.uniform(-0.1, 0.04)))
	f.done(bevel=0.025)


def _props(r):
	p = Parts("props")
	# Round hay bales lying in the yard.
	for at, turn in (((-3.85, -1.35), 20), ((-3.55, -2.45), -15)):
		m = place((*at, 0.42), (90, 0, turn))
		p.cylinder(0.42, 0.62, m, mat("hay"), sides=20)
		for side in (-1, 1):
			p.cylinder(0.3, 0.02, m @ place((0, 0, side * 0.31)), mat("hay", -0.12), sides=20)  # rolled-up ends
		p.cylinder(0.43, 0.06, m @ place((0, 0, 0.12)), mat("wood_dark", 0.2), sides=20)
	# Stack of square bales by the silo.
	for at, z, turn in (((3.45, 3.55), 0.22, 0), ((3.45, 4.1), 0.22, 0), ((3.5, 3.8), 0.66, 85)):
		m = place((*at, z), (0, 0, turn))
		p.box((0.9, 0.5, 0.44), m, mat("hay", r.uniform(-0.06, 0.04)))
		for dx in (-0.22, 0.22):
			p.box((0.04, 0.52, 0.46), m @ place((dx, 0, 0)), mat("wood_dark", 0.2))
	# Wheat sacks by the barn door.
	for at, z, squash in (((-1.05, -0.05), 0.27, (1, 0.85, 1.25)), ((-0.7, 0.15), 0.27, (1, 0.85, 1.25)), ((-0.95, -0.45), 0.2, (1.3, 0.85, 0.9))):
		p.ball(0.22, place((*at, z)), mat("sack", r.uniform(-0.05, 0.03)), squash=squash, detail=2)
		if squash[2] > 1:
			p.cylinder(0.06, 0.1, place((*at, z + 0.3)), mat("sack", -0.1), sides=8)
	# Cart full of wheat.
	cart = place((-0.95, -2.3, 0), (0, 0, 30))
	p.box((0.9, 0.6, 0.08), cart @ place((0, 0, 0.42)), mat("wood"))
	for dy in (-0.3, 0.3):
		p.box((0.9, 0.06, 0.25), cart @ place((0, dy, 0.55)), mat("wood_light"))
	for dx in (-0.45, 0.45):
		p.box((0.06, 0.66, 0.25), cart @ place((dx, 0, 0.55)), mat("wood_light"))
	for i in range(6):
		p.ball(0.2, cart @ place((-0.28 + (i % 3) * 0.28, -0.13 + (i // 3) * 0.26, 0.66)), mat("wheat", r.uniform(-0.05, 0.08)), squash=(1, 1, 0.6), detail=1)
	for dy in (-0.36, 0.36):
		p.cylinder(0.24, 0.07, cart @ place((0.05, dy, 0.25), (90, 0, 0)), mat("wood_dark"), sides=14)
		p.box((0.8, 0.05, 0.05), cart @ place((-0.75, dy * 0.6, 0.48), (0, -8, 0)), mat("wood"))
	# Crates by the barn.
	for at, z, turn in (((-4.05, 0.05), 0.25, 10), ((-3.6, -0.05), 0.25, -8), ((-3.85, 0.0), 0.75, 30)):
		m = place((*at, z), (0, 0, turn))
		p.box((0.5, 0.5, 0.5), m, mat("wood_light", r.uniform(-0.06, 0.04)))
		for e in (-1, 1):
			p.box((0.54, 0.06, 0.06), m @ place((0, e * 0.24, 0.22)), mat("wood_dark", 0.1))
			p.box((0.54, 0.06, 0.06), m @ place((0, e * 0.24, -0.22)), mat("wood_dark", 0.1))
			p.box((0.06, 0.54, 0.06), m @ place((e * 0.24, 0, 0.22)), mat("wood_dark", 0.1))
			p.box((0.06, 0.54, 0.06), m @ place((e * 0.24, 0, -0.22)), mat("wood_dark", 0.1))
	# Scarecrow in the field.
	sx, sy = SCARECROW
	turn = place((sx, sy, 0), (0, 0, 45))
	p.cylinder(0.05, 1.5, turn @ place((0, 0, 0.75)), mat("wood"), sides=8)
	p.box((0.42, 0.26, 0.5), turn @ place((0, 0, 1.0)), mat("cloth_blue"))
	p.box((0.44, 0.28, 0.08), turn @ place((0, 0, 0.78)), mat("wood_dark", 0.15))
	p.box((1.0, 0.15, 0.15), turn @ place((0, 0, 1.17)), mat("cloth_blue", -0.1))
	for e in (-1, 1):
		p.cylinder(0.09, 0.18, turn @ place((e * 0.56, 0, 1.17), (0, e * 90, 0)), mat("hay"), sides=8, top_radius=0.02)
	p.ball(0.17, turn @ place((0, 0, 1.43)), mat("sack"), detail=2)
	p.cylinder(0.3, 0.04, turn @ place((0, 0, 1.56)), mat("hay", 0.05), sides=16)
	p.cylinder(0.15, 0.2, turn @ place((0, 0, 1.67)), mat("hay", 0.05), sides=16, top_radius=0.11)
	p.box((0.32, 0.05, 0.05), turn @ place((0, 0, 1.6)), mat("cloth_red"))
	# A bush in the front corner of the yard.
	for at, rad in (((-4.15, -4.15), 0.38), ((-3.8, -4.25), 0.3), ((-4.2, -3.75), 0.28)):
		p.ball(rad, place((*at, rad * 0.8)), mat("leaf", r.uniform(-0.08, 0.06)), squash=(1, 1, 0.9), detail=2)
	p.done(bevel=0.03)
