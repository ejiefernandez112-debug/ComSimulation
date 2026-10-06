"""GRAIN MILL (2x2 tiles, building id flour_mill): a white eight-sided tower windmill with a dark cap
and four big sails turned toward the player, a wooden gallery around its middle, a little
storehouse, a pile of flour sacks and a cart, on a dirt yard. Plot is -5..5 on X and Y (see kit.py
for which sides the player sees)."""
import math

from mathutils import Vector

from kit import Parts, frame, mat, place, rng

TILES = 2

TX, TY = -1.3, 1.3  # tower centre
R_BASE, R_TOP, TOP = 1.95, 1.35, 6.4  # radius at the ground and at the top, and its height
GALLERY = 2.9  # height of the wooden gallery
FACING = Vector((1, -1, 0)).normalized()  # the sails face the player (the camera's corner)
ACROSS = Vector((1, 1, 0)).normalized()
SHED = (2.9, 2.6)


def build():
	r = rng(5)
	_ground(r)
	_tower(r)
	_cap_and_sails()
	_gallery()
	_shed(r)
	_props(r)


def _radius(z: float) -> float:
	return R_BASE + (R_TOP - R_BASE) * z / TOP


def _on_tower(angle_deg: float, z: float, out: float = 0.0):
	"""Placement on the tower wall facing `angle_deg` (0 = +X, -90 = -Y): x along the wall, -y out."""
	a = math.radians(angle_deg)
	d = Vector((math.cos(a), math.sin(a), 0))
	at = Vector((TX, TY, z)) + d * (_radius(z) * math.cos(math.radians(22.5)) + out)
	return frame(at, (-d.y, d.x, 0), z_axis=(0, 0, 1))


def _ground(r):
	g = Parts("ground")
	yard = [(-4.4, -1.2), (-3.4, -2.6), (-1.6, -2.9), (-0.6, -4.85), (1.4, -4.85), (1.6, -3.2),
		(3.6, -2.4), (4.5, -0.6), (4.4, 1.2), (4.6, 4.2), (1.0, 4.5), (-2.0, 4.6), (-4.5, 3.4)]
	g.prism(yard, 0.06, frame((0, 0, 0.03), (1, 0, 0), z_axis=(0, 1, 0)), mat("dirt"))
	g.done(bevel=0.03)


def _tower(r):
	t = Parts("tower")
	# Stone foot, then the white tapering tower (turned so flat faces point at the player).
	t.cylinder(R_BASE + 0.15, 0.8, place((TX, TY, 0.4), (0, 0, 22.5)), mat("stone"), sides=8)
	t.cylinder(R_BASE, TOP - 0.8, place((TX, TY, (TOP + 0.8) / 2), (0, 0, 22.5)), mat("plaster"), sides=8, top_radius=R_TOP)
	# Dark band under the cap.
	t.cylinder(R_TOP + 0.12, 0.25, place((TX, TY, TOP - 0.05), (0, 0, 22.5)), mat("wood_dark"), sides=8)

	# Door on the front face, with a little stone step.
	door = _on_tower(-90, 1.75)
	t.box((1.0, 0.1, 1.9), door @ place((0, -0.02, 0)), mat("wood"))
	for dx in (-0.3, 0.0, 0.3):
		t.box((0.04, 0.12, 1.85), door @ place((dx, -0.05, 0)), mat("wood_dark"))
	t.box((1.25, 0.14, 0.14), door @ place((0, -0.06, 1.0)), mat("trim"))
	for e in (-1, 1):
		t.box((0.14, 0.14, 2.0), door @ place((e * 0.56, -0.06, 0)), mat("trim"))
	t.ball(0.05, door @ place((0.3, -0.14, -0.05)), mat("metal_dark"), detail=1)
	step = _on_tower(-90, 0.1, 0.35)
	t.box((1.5, 0.7, 0.2), step, mat("stone", -0.05))

	# Small windows up the visible faces.
	for angle, z in ((-90, 4.4), (0, 1.9), (0, 4.6), (-45, 3.6)):
		m = _on_tower(angle, z)
		t.box((0.5, 0.08, 0.7), m @ place((0, -0.02, 0)), mat("window"))
		for e in (-1, 1):
			t.box((0.1, 0.1, 0.86), m @ place((e * 0.3, -0.05, 0)), mat("wood_dark"))
			t.box((0.7, 0.1, 0.1), m @ place((0, -0.05, e * 0.4)), mat("wood_dark"))
		t.box((0.75, 0.2, 0.08), m @ place((0, -0.1, -0.46)), mat("wood_dark"))
	t.done(bevel=0.03)


def _cap_and_sails():
	c = Parts("cap")
	# Boat-shaped cap: a squashed dome with a ridge, stretched along the windshaft.
	c.ball(R_TOP + 0.25, frame((TX, TY, TOP + 0.15), FACING, z_axis=(0, 0, 1)), mat("roof_dark"), squash=(1.15, 0.95, 0.8), detail=3)
	c.box((R_TOP * 2.4, 0.18, 0.18), frame((TX, TY, TOP + 1.25), FACING, z_axis=(0, 0, 1)), mat("roof_dark", -0.15))
	c.ball(0.2, place((TX, TY, TOP + 1.38)), mat("wood_dark"), detail=1)
	# Windshaft sticking out toward the player, and the hub.
	hub = Vector((TX, TY, TOP + 0.45)) + FACING * (R_TOP + 0.9)
	c.cylinder(0.22, 1.2, frame(hub - FACING * 0.5, ACROSS, z_axis=FACING), mat("wood_dark"), sides=12)
	c.cylinder(0.36, 0.3, frame(hub, ACROSS, z_axis=FACING), mat("wood_dark", -0.1), sides=12)
	c.ball(0.2, frame(hub + FACING * 0.18, ACROSS, z_axis=FACING), mat("metal_dark"), detail=1)
	c.done(bevel=0.03)

	# Four sails in an X: a stock, a lattice frame and a cream cloth on one side of it.
	s = Parts("sails")
	length, start, width = 4.4, 0.55, 1.0
	for k in range(4):
		a = math.radians(45 + k * 90)
		along = ACROSS * math.cos(a) + Vector((0, 0, 1)) * math.sin(a)  # out from the hub
		side = FACING.cross(along).normalized()  # across the sail
		base = hub + FACING * 0.25
		s.box((0.16, length + 0.3, 0.16), frame(base + along * (length + 0.3) / 2, side, z_axis=FACING), mat("wood"))
		cloth_mid = base + along * (start + (length - start) / 2) + side * (width / 2 + 0.08)
		s.box((width, length - start, 0.05), frame(cloth_mid + FACING * 0.04, side, z_axis=FACING), mat("white"))
		for i in range(6):  # cross bars
			at = base + along * (start + i * (length - start) / 5) + side * (width / 2 + 0.08)
			s.box((width + 0.12, 0.07, 0.08), frame(at + FACING * 0.09, side, z_axis=FACING), mat("wood"))
		s.box((0.07, length - start, 0.08), frame(cloth_mid + side * (width / 2) + FACING * 0.09, side, z_axis=FACING), mat("wood"))
	s.done(bevel=0.02)


def _gallery():
	"""Wooden gallery (walkway) around the tower, on brackets, with a railing."""
	g = Parts("gallery")
	rad = _radius(GALLERY) + 0.75
	g.cylinder(rad, 0.14, place((TX, TY, GALLERY), (0, 0, 22.5)), mat("wood"), sides=8)
	for k in range(8):
		a = math.radians(22.5 + k * 45)
		d = Vector((math.cos(a), math.sin(a), 0))
		corner = Vector((TX, TY, 0)) + d * rad * 0.98
		g.box((0.1, 0.1, 0.75), place(corner + Vector((0, 0, GALLERY + 0.42))), mat("wood_dark"))
		nxt = math.radians(22.5 + (k + 1) * 45)
		corner2 = Vector((TX, TY, 0)) + Vector((math.cos(nxt), math.sin(nxt), 0)) * rad * 0.98
		mid = (corner + corner2) / 2
		edge = corner2 - corner
		for z in (0.4, 0.75):
			g.box((edge.length, 0.06, 0.07), frame(mid + Vector((0, 0, GALLERY + z)), edge, z_axis=(0, 0, 1)), mat("wood_light"))
		# Slanted bracket under the walkway.
		inner = Vector((TX, TY, 0)) + d * (_radius(GALLERY - 0.8) * 0.93)
		strut = (corner * 0.85 + inner * 0.15) - inner + Vector((0, 0, 0.75))
		g.box((0.09, 0.09, strut.length), frame(inner + Vector((0, 0, GALLERY - 0.8)) + strut / 2, d, z_axis=strut), mat("wood_dark"))
	g.done(bevel=0.02)


def _shed(r):
	"""Small wooden storehouse with a lean-to roof at the back right."""
	s = Parts("shed")
	sx, sy = SHED
	w, d, h = 2.4, 2.2, 1.9
	s.box((w + 0.1, d + 0.1, 0.2), place((sx, sy, 0.1)), mat("stone"))
	s.box((w, d, h), place((sx, sy, 0.2 + h / 2)), mat("wood", 0.05))
	y = sy - d / 2
	x = sx - w / 2 + 0.15
	while x < sx + w / 2:
		s.box((0.05, 0.05, h), place((x, y - 0.02, 0.2 + h / 2)), mat("wood", -0.12))
		x += 0.3
	s.box((0.9, 0.08, 1.4), place((sx - 0.3, y - 0.04, 0.9)), mat("wood_dark"))
	s.box((0.1, 0.1, 1.5), place((sx - 0.3, y - 0.08, 0.9), (0, 30, 0)), mat("wood_light"))
	s.box((0.08, 0.5, 0.5), place((sx + w / 2 + 0.03, sy, 1.4)), mat("window"))
	roof = frame((sx, sy, 0.2 + h + 0.25), (1, 0, 0), z_axis=(0, -0.35, 1))
	s.box((w + 0.5, d + 0.6, 0.14), roof, mat("roof"))
	for i in range(7):
		s.box((0.06, d + 0.6, 0.05), roof @ place((-w / 2 + i * (w + 0.4) / 6, 0, 0.09)), mat("roof", -0.12))
	s.done(bevel=0.03)


def _sack(p: Parts, at, r, lying=False):
	if lying:
		p.ball(0.24, place(at), mat("sack", r.uniform(-0.05, 0.03)), squash=(1.35, 0.9, 0.85), detail=2)
	else:
		p.ball(0.25, place(at), mat("sack", r.uniform(-0.05, 0.03)), squash=(1, 0.9, 1.25), detail=2)
		p.cylinder(0.07, 0.12, place((at[0], at[1], at[2] + 0.34)), mat("sack", -0.1), sides=8)


def _props(r):
	p = Parts("props")
	# Pyramid of flour sacks beside the door.
	for row, (count, z) in enumerate(((4, 0.2), (3, 0.5), (2, 0.8))):
		for i in range(count):
			x = 1.0 - (count - 1) * 0.25 + i * 0.5
			_sack(p, (x, -1.1 + row * 0.08, z), r, lying=True)
	_sack(p, (2.1, -1.5, 0.3), r)
	_sack(p, (2.4, -1.15, 0.3), r)

	# Cart with sacks, near the path.
	cart = place((2.6, -3.2, 0), (0, 0, 35))
	p.box((1.3, 0.8, 0.08), cart @ place((0, 0, 0.5)), mat("wood"))
	for dy in (-0.43, 0.43):
		p.box((1.3, 0.06, 0.26), cart @ place((0, dy, 0.64)), mat("wood_light"))
		p.cylinder(0.32, 0.08, cart @ place((0.1, dy * 1.05, 0.32), (90, 0, 0)), mat("wood_dark"), sides=14)
		p.box((1.0, 0.06, 0.06), cart @ place((-1.05, dy * 0.6, 0.55), (0, -6, 0)), mat("wood"))
	for dx in (-0.35, 0.35):
		p.ball(0.24, cart @ place((dx, 0, 0.75)), mat("sack", r.uniform(-0.05, 0.03)), squash=(0.9, 1.35, 0.85), detail=2)

	# Wheat sheaves standing in the yard, waiting to be milled.
	for at in ((-3.6, -1.6), (-3.1, -2.2), (-4.0, -0.5)):
		base = Vector((*at, 0))
		p.cylinder(0.26, 0.9, place(base + Vector((0, 0, 0.45))), mat("stalk"), sides=10, top_radius=0.12)
		p.cylinder(0.14, 0.08, place(base + Vector((0, 0, 0.55))), mat("wood_dark", 0.2), sides=10)
		for k in range(7):
			a = k * 2 * math.pi / 7
			p.ball(0.1, place(base + Vector((math.cos(a) * 0.14, math.sin(a) * 0.14, 1.0))), mat(r.choice(("wheat", "wheat_light"))), squash=(1, 1, 1.8), detail=1)

	# Millstone leaning by the shed, and a couple of crates.
	p.cylinder(0.6, 0.22, place((1.3, 3.9, 0.62), (75, 0, 30)), mat("stone", 0.05), sides=20)
	p.cylinder(0.12, 0.24, place((1.3, 3.9, 0.62), (75, 0, 30)), mat("stone", -0.2), sides=10)
	for at, z, turn in (((4.2, 0.6), 0.25, 10), ((4.05, 1.15), 0.25, -12), ((4.15, 0.85), 0.75, 30)):
		m = place((*at, z), (0, 0, turn))
		p.box((0.5, 0.5, 0.5), m, mat("wood_light", r.uniform(-0.06, 0.04)))
		for e in (-1, 1):
			p.box((0.54, 0.06, 0.06), m @ place((0, e * 0.24, 0.22)), mat("wood_dark", 0.1))
			p.box((0.06, 0.54, 0.06), m @ place((e * 0.24, 0, 0.22)), mat("wood_dark", 0.1))

	# Bushes and a low fence at the front left.
	for at, rad in (((-4.3, -4.2), 0.42), ((-3.9, -4.45), 0.3), ((4.3, -4.3), 0.38), ((-4.4, 4.2), 0.45), ((4.4, 4.3), 0.36)):
		p.ball(rad, place((*at, rad * 0.8)), mat("leaf", r.uniform(-0.08, 0.06)), squash=(1, 1, 0.9), detail=2)
	p.done(bevel=0.025)
