"""CITY HALL (2x2 tiles): a cream classical building with a columned porch and pediment, a clock
tower with a green copper dome, wide front steps, a fountain on a paved square, lamp posts and a
flagpole. Plot is -5..5 on X and Y (see kit.py for which sides the player sees)."""
import math

from kit import Parts, frame, mat, place, rng

TILES = 2

# Main block: centre, width (X), depth (Y), and heights.
HX, HY, HW, HD = 0.0, 1.5, 7.6, 3.8
FRONT, SIDE = HY - HD / 2, HX + HW / 2
PLINTH, WALL = 0.5, 3.8
PORCH_W, PORCH_FRONT = 4.4, FRONT - 1.45  # the columned porch sticks out in front
TOWER = (0.0, 1.9)


def build():
	r = rng(3)
	_square(r)
	_block()
	_porch()
	_tower()
	_props(r)


def _wall(side: str, along: float, z: float):
	"""Placement on one of the visible walls: x runs along the wall, -y points out of it."""
	if side == "front":
		return place((along, FRONT, z))
	return frame((SIDE, along, z), (0, 1, 0), z_axis=(0, 0, 1))


def _square(r):
	g = Parts("square")
	step = 0.7
	x = -4.8 + step / 2
	while x < 4.8:
		y = -4.85 + step / 2
		while y < PORCH_FRONT:
			g.box((step - 0.05, step - 0.05, 0.08), place((x, y, 0.04)), mat("paving", r.choice((-0.08, -0.03, 0.0, 0.04))))
			y += step
		x += step
	g.done(bevel=0.02)


def _window(p: Parts, side: str, along: float, z: float):
	m = _wall(side, along, z)
	w, h = 0.62, 1.05
	p.box((w, 0.06, h), m @ place((0, -0.02, 0)), mat("window"))
	p.box((0.05, 0.08, h), m @ place((0, -0.05, 0)), mat("white"))
	for dz in (-0.18, 0.2):
		p.box((w, 0.08, 0.05), m @ place((0, -0.05, dz)), mat("white"))
	for e in (-1, 1):
		p.box((0.1, 0.1, h + 0.2), m @ place((e * (w / 2 + 0.05), -0.06, 0)), mat("white"))
	p.box((w + 0.3, 0.18, 0.08), m @ place((0, -0.1, -h / 2 - 0.08)), mat("white"))
	# Little pediment over each window.
	p.prism([(-w / 2 - 0.18, 0), (w / 2 + 0.18, 0), (0, 0.24)], 0.16, m @ place((0, -0.1, h / 2 + 0.1)), mat("white"))


def _block():
	b = Parts("main block")
	b.box((HW + 0.3, HD + 0.3, PLINTH), place((HX, HY, PLINTH / 2)), mat("stone"))
	b.box((HW, HD, WALL - PLINTH), place((HX, HY, (WALL + PLINTH) / 2)), mat("trim"))
	# Floor band, cornice and a balustrade around the flat roof.
	b.box((HW + 0.1, HD + 0.1, 0.14), place((HX, HY, 2.15)), mat("trim", -0.08))
	b.box((HW + 0.4, HD + 0.4, 0.28), place((HX, HY, WALL + 0.14)), mat("white"))
	b.box((HW - 0.2, HD - 0.2, 0.1), place((HX, HY, WALL + 0.32)), mat("roof"))
	for z in (WALL + 0.36, WALL + 0.8):
		b.box((HW + 0.3, 0.14, 0.1), place((HX, HY - HD / 2 - 0.05, z)), mat("white"))
		b.box((0.14, HD + 0.3, 0.1), place((SIDE + 0.05, HY, z)), mat("white"))
		b.box((HW + 0.3, 0.14, 0.1), place((HX, HY + HD / 2 + 0.05, z)), mat("white"))
		b.box((0.14, HD + 0.3, 0.1), place((HX - HW / 2 - 0.05, HY, z)), mat("white"))
	x = HX - HW / 2
	while x <= SIDE + 0.01:
		b.cylinder(0.06, 0.36, place((x, FRONT - 0.05, WALL + 0.58)), mat("white"), sides=8, top_radius=0.04)
		x += 0.3
	y = FRONT
	while y <= HY + HD / 2 + 0.01:
		b.cylinder(0.06, 0.36, place((SIDE + 0.05, y, WALL + 0.58)), mat("white"), sides=8, top_radius=0.04)
		y += 0.3
	# Corner pilasters.
	for cx, cy in ((SIDE, FRONT), (HX - HW / 2, FRONT), (SIDE, HY + HD / 2)):
		b.box((0.34, 0.34, WALL - PLINTH), place((cx, cy, (WALL + PLINTH) / 2)), mat("white"))
	# Two floors of windows on the wings and the side.
	for along in (-3.05, 3.05):  # one column of windows on each wing
		for z in (1.3, 2.95):
			_window(b, "front", along, z)
	for along in (FRONT + 0.75, HY, HY + HD / 2 - 0.75):
		for z in (1.3, 2.95):
			_window(b, "side", along, z)
	b.done(bevel=0.03)


def _porch():
	p = Parts("porch")
	cx, depth = HX, FRONT - PORCH_FRONT
	mid_y = FRONT - depth / 2
	p.box((PORCH_W + 0.3, depth + 0.1, PLINTH), place((cx, mid_y, PLINTH / 2)), mat("stone", 0.05))
	for i in range(3):  # three steps down to the square
		h = PLINTH - (i + 1) * PLINTH / 4
		run = (i + 1) * 0.32
		p.box((PORCH_W + 0.3 + (i + 1) * 0.3, run, h), place((cx, PORCH_FRONT - run / 2, h / 2)), mat("stone", 0.05 - i * 0.04))
	# Big front door with a half-round fanlight.
	p.box((1.3, 0.1, 2.2), place((cx, FRONT - 0.03, PLINTH + 1.1)), mat("wood_dark"))
	p.box((0.05, 0.12, 2.1), place((cx, FRONT - 0.07, PLINTH + 1.05)), mat("wood_dark", -0.2))
	p.cylinder(0.62, 0.08, place((cx, FRONT - 0.03, PLINTH + 2.25), (90, 0, 0)), mat("window"), sides=20)
	p.box((1.6, 0.14, 0.14), place((cx, FRONT - 0.06, PLINTH + 2.25)), mat("white"))
	for e in (-1, 1):
		p.box((0.16, 0.14, 2.4), place((cx + e * 0.75, FRONT - 0.06, PLINTH + 1.2)), mat("white"))
	# Six columns with bases and capitals.
	col_y = PORCH_FRONT + 0.3
	top = WALL - 0.35
	for i in range(6):
		x = cx - PORCH_W / 2 + 0.3 + i * (PORCH_W - 0.6) / 5
		p.box((0.46, 0.46, 0.14), place((x, col_y, PLINTH + 0.07)), mat("white"))
		p.cylinder(0.18, top - PLINTH - 0.2, place((x, col_y, (top + PLINTH) / 2)), mat("white"), sides=12, top_radius=0.16)
		p.box((0.44, 0.44, 0.14), place((x, col_y, top - 0.04)), mat("white"))
	# Beam across the columns and the triangular pediment, with a gold emblem.
	p.box((PORCH_W + 0.2, depth + 0.1, 0.42), place((cx, mid_y, top + 0.24)), mat("trim"))
	p.box((PORCH_W + 0.35, depth + 0.2, 0.12), place((cx, mid_y, top + 0.5)), mat("white"))
	peak = 1.05
	p.prism([(-PORCH_W / 2 - 0.15, 0), (PORCH_W / 2 + 0.15, 0), (0, peak)], depth + 0.2, place((cx, mid_y, top + 0.56)), mat("trim"))
	p.prism([(-PORCH_W / 2 + 0.25, 0.1), (PORCH_W / 2 - 0.25, 0.1), (0, peak - 0.25)], 0.06, place((cx, PORCH_FRONT - 0.07, top + 0.56)), mat("trim", -0.1))
	p.cylinder(0.24, 0.1, place((cx, PORCH_FRONT - 0.1, top + 0.86), (90, 0, 0)), mat("hazard"), sides=16)
	for sign in (-1, 1):  # the sloping roof edges of the pediment
		run = math.hypot(PORCH_W / 2 + 0.25, peak)
		angle = math.degrees(math.atan2(peak, PORCH_W / 2 + 0.25))
		p.box((run, depth + 0.3, 0.14), place((cx + sign * (PORCH_W / 4 + 0.06), mid_y, top + 0.62 + peak / 2), (0, sign * angle, 0)), mat("white"))
	p.done(bevel=0.03)


def _tower():
	t = Parts("clock tower")
	tx, ty = TOWER
	base, size, top = WALL + 0.3, 1.8, 6.5
	t.box((size, size, top - base), place((tx, ty, (top + base) / 2)), mat("trim"))
	for ex in (-1, 1):
		for ey in (-1, 1):
			t.box((0.26, 0.26, top - base), place((tx + ex * size / 2, ty + ey * size / 2, (top + base) / 2)), mat("white"))
	t.box((size + 0.35, size + 0.35, 0.22), place((tx, ty, top + 0.11)), mat("white"))
	# Clock faces on the two sides the player sees.
	for m in (place((tx, ty - size / 2, 5.7)), frame((tx + size / 2, ty, 5.7), (0, 1, 0), z_axis=(0, 0, 1))):
		t.cylinder(0.62, 0.1, m @ place((0, -0.03, 0), (90, 0, 0)), mat("wood_dark"), sides=24)
		t.cylinder(0.54, 0.12, m @ place((0, -0.05, 0), (90, 0, 0)), mat("white"), sides=24)
		for k in range(12):
			a = math.radians(k * 30)
			t.box((0.05, 0.04, 0.1), m @ place((math.sin(a) * 0.44, -0.12, math.cos(a) * 0.44), (0, -k * 30, 0)), mat("window"))
		t.box((0.05, 0.04, 0.36), m @ place((0.0, -0.14, 0.15)), mat("window"))
		t.box((0.26, 0.04, 0.05), m @ place((0.11, -0.14, 0.0)), mat("window"))
		# Arched window below the clock.
		t.box((0.42, 0.06, 0.5), m @ place((0, -0.02, -1.15)), mat("window"))
		t.cylinder(0.21, 0.06, m @ place((0, -0.02, -0.9), (90, 0, 0)), mat("window"), sides=12)
	# Round drum and the copper dome with a gold tip.
	t.cylinder(0.75, 0.6, place((tx, ty, top + 0.5)), mat("trim"), sides=20)
	for k in range(10):
		a = math.radians(k * 36)
		t.box((0.12, 0.12, 0.6), place((tx + math.cos(a) * 0.77, ty + math.sin(a) * 0.77, top + 0.5)), mat("white"))
	t.cylinder(0.85, 0.12, place((tx, ty, top + 0.86)), mat("white"), sides=20)
	t.ball(0.78, place((tx, ty, top + 0.9)), mat("copper"), squash=(1, 1, 1.05), detail=3)
	t.cylinder(0.1, 0.3, place((tx, ty, top + 1.8)), mat("hazard"), sides=10)
	t.ball(0.12, place((tx, ty, top + 2.02)), mat("hazard"), detail=1)
	t.cylinder(0.03, 0.6, place((tx, ty, top + 2.35)), mat("hazard"), sides=6)
	t.done(bevel=0.025)


def _props(r):
	p = Parts("props")
	# Round fountain in the middle of the square.
	fx, fy = 0.0, -3.85
	p.cylinder(1.0, 0.45, place((fx, fy, 0.225)), mat("stone", 0.05), sides=24)
	p.cylinder(0.85, 0.47, place((fx, fy, 0.24)), mat("water"), sides=24)
	p.cylinder(0.16, 1.1, place((fx, fy, 0.75)), mat("stone", 0.05), sides=12)
	p.cylinder(0.42, 0.14, place((fx, fy, 1.3)), mat("stone", 0.05), sides=16, top_radius=0.5)
	p.cylinder(0.38, 0.06, place((fx, fy, 1.36)), mat("water"), sides=16)
	for k, rad in enumerate((0.12, 0.1, 0.08)):
		p.ball(rad, place((fx, fy, 1.45 + k * 0.16)), mat("white"), detail=1)
	for k in range(6):
		a = math.radians(k * 60)
		p.ball(0.07, place((fx + math.cos(a) * 0.5, fy + math.sin(a) * 0.5, 0.52)), mat("white"), detail=1)

	# Lamp posts beside the steps.
	for lx in (-PORCH_W / 2 - 0.9, PORCH_W / 2 + 0.9):
		ly = PORCH_FRONT - 0.5
		p.cylinder(0.14, 0.2, place((lx, ly, 0.1)), mat("metal_dark"), sides=10)
		p.cylinder(0.05, 2.0, place((lx, ly, 1.1)), mat("metal_dark"), sides=8)
		p.ball(0.2, place((lx, ly, 2.25)), mat("wheat_light"), detail=2)
		p.cylinder(0.2, 0.12, place((lx, ly, 2.46)), mat("metal_dark"), sides=10, top_radius=0.05)

	# Flagpole at the front left with a blue-and-gold flag.
	gx, gy = -4.35, -1.0
	p.cylinder(0.25, 0.3, place((gx, gy, 0.15)), mat("stone"), sides=12)
	p.cylinder(0.05, 5.6, place((gx, gy, 3.0)), mat("white"), sides=8)
	p.ball(0.09, place((gx, gy, 5.85)), mat("hazard"), detail=1)
	flag = place((gx, gy, 5.25), (0, 0, 35))
	p.box((1.3, 0.04, 0.8), flag @ place((0.68, 0, 0)), mat("cloth_blue"))
	p.box((1.3, 0.05, 0.14), flag @ place((0.68, 0, 0)), mat("hazard"))

	# Hedges in front of the wings and round bushes in the corners.
	for hx in (-2.95, 3.0):
		p.box((1.5, 0.5, 0.55), place((hx, FRONT - 0.45, 0.3)), mat("leaf", -0.05))
		p.box((1.6, 0.6, 0.12), place((hx, FRONT - 0.45, 0.06)), mat("stone"))
	for at, rad in (((-4.35, -4.3), 0.42), ((-4.4, -3.75), 0.3), ((4.4, 4.3), 0.4), ((-4.4, 4.3), 0.42)):
		p.ball(rad, place((*at, rad * 0.8)), mat("leaf", r.uniform(-0.08, 0.06)), squash=(1, 1, 0.9), detail=2)
	# Benches facing the fountain.
	for bx, turn in ((-2.3, 0), (2.3, 0)):
		m = place((bx, -4.3, 0), (0, 0, turn))
		p.box((1.2, 0.4, 0.07), m @ place((0, 0, 0.45)), mat("wood"))
		p.box((1.2, 0.07, 0.35), m @ place((0, -0.2, 0.68)), mat("wood"))
		for e in (-0.5, 0.5):
			p.box((0.07, 0.4, 0.45), m @ place((e, 0, 0.22)), mat("metal_dark"))
	p.done(bevel=0.025)
