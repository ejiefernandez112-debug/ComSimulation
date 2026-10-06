"""BAKERY (2x2 tiles): a cosy plaster shop with a terracotta roof, a striped awning over the shop
window full of bread, a hanging bread sign, a smoking brick chimney, and a wood-fired oven with a
log pile in the side yard. A paved terrace in front holds a bread table, a cafe table and a delivery
cart. Plot is -5..5 on X and Y (see kit.py for which sides the player sees)."""
import math

from mathutils import Vector

from kit import Parts, frame, mat, place, rng

TILES = 2

# The shop: centre, width (X), depth (Y). The ridge runs along X, so the long roof slope faces the
# player and the gable end (with a round window) is the +X side.
HX, HY, HW, HD = -0.7, 1.3, 6.0, 4.2
FRONT, SIDE = HY - HD / 2, HX + HW / 2  # the two wall faces the player sees
BASE, EAVE, RIDGE = 0.3, 3.0, 5.0

DOOR_X = 0.35
DORMER_X, DORMER_W = -1.9, 1.3
OVEN = (3.55, 2.3)


def build():
	r = rng(11)
	_paving(r)
	_walls(r)
	_shop_front(r)
	_roof(r)
	_chimney()
	_oven(r)
	_props(r)


def _wall(side: str, along: float, z: float):
	"""Placement on one of the visible walls: x runs along the wall, -y points out of it."""
	if side == "front":
		return place((along, FRONT, z))
	return frame((SIDE, along, z), (0, 1, 0), z_axis=(0, 0, 1))


def _paving(r):
	"""Warm sandstone flagstones: a terrace in front, a yard by the oven, and a path to the plot edge."""
	g = Parts("paving")
	step = 0.62
	areas = ((-4.75, 4.75, -3.5, FRONT), (SIDE, 4.75, FRONT, 3.6), (-0.3, 1.0, -4.85, -3.5))
	x = -4.75 + step / 2
	while x < 4.75:
		y = -4.85 + step / 2
		while y < 3.6:
			if any(x0 <= x <= x1 and y0 <= y <= y1 for x0, x1, y0, y1 in areas):
				g.box((step - 0.06, step - 0.06, 0.08), place((x, y, 0.04)), mat("paving", r.choice((-0.1, -0.05, 0.0, 0.04))))
			y += step
		x += step
	g.done(bevel=0.02)


def _walls(r):
	w = Parts("walls")
	w.box((HW + 0.12, HD + 0.12, BASE), place((HX, HY, BASE / 2)), mat("brick_dark"))
	# Plaster walls with the gable triangles at both X ends.
	outline = [(-HD / 2, BASE), (HD / 2, BASE), (HD / 2, EAVE), (0, RIDGE), (-HD / 2, EAVE)]
	w.prism(outline, HW, frame((HX, HY, 0), (0, 1, 0), z_axis=(0, 0, 1)), mat("plaster"))

	# Stone corner blocks (quoins), alternating long and short.
	for cx, cy, sx, sy in ((SIDE, FRONT, -1, 1), (HX - HW / 2, FRONT, 1, 1), (SIDE, HY + HD / 2, -1, -1)):
		z, i = BASE + 0.15, 0
		while z < EAVE - 0.1:
			a, b = (0.5, 0.28) if i % 2 == 0 else (0.28, 0.5)
			shade = r.choice((-0.06, 0.0, 0.05))
			w.box((a, 0.1, 0.26), place((cx + sx * a / 2, cy - sy * 0.03, z)), mat("stone", shade))
			w.box((0.1, b, 0.26), place((cx - sx * 0.03, cy + sy * b / 2, z)), mat("stone", shade))
			z += 0.3
			i += 1

	# Side windows with shutters and flower boxes, and a round window in the gable.
	_window(w, "side", 0.65, 1.55, 0.75, 0.95, r)
	_window(w, "front", 1.6, 1.5, 0.6, 0.8, r, shutters=False)
	m = place((SIDE + 0.02, HY, 3.85), (0, 90, 0))
	w.cylinder(0.46, 0.1, m, mat("wood_dark"), sides=20)
	w.cylinder(0.36, 0.14, m, mat("window"), sides=20)
	w.box((0.16, 0.06, 0.72), place((SIDE + 0.09, HY, 3.85)), mat("wood_dark"))
	w.box((0.16, 0.72, 0.06), place((SIDE + 0.09, HY, 3.85)), mat("wood_dark"))
	w.done(bevel=0.03)


def _window(p: Parts, side: str, along: float, z: float, width: float, height: float, r, shutters=True):
	m = _wall(side, along, z)
	p.box((width, 0.06, height), m @ place((0, -0.02, 0)), mat("window"))
	p.box((0.05, 0.08, height), m @ place((0, -0.05, 0)), mat("trim"))
	p.box((width, 0.08, 0.05), m @ place((0, -0.05, 0.08)), mat("trim"))
	for e in (-1, 1):
		p.box((0.1, 0.1, height + 0.2), m @ place((e * (width / 2 + 0.05), -0.06, 0)), mat("trim"))
		p.box((width + 0.3, 0.1, 0.1), m @ place((0, -0.06, e * (height / 2 + 0.05))), mat("trim"))
		if not shutters:
			continue
		# Green shutters with two cross bars.
		sx = e * (width * 0.75 + 0.14)
		p.box((width / 2, 0.06, height), m @ place((sx, -0.05, 0)), mat("shop_green"))
		for dz in (-height / 4, height / 4):
			p.box((width / 2 - 0.08, 0.04, 0.05), m @ place((sx, -0.1, dz)), mat("shop_green", -0.2))
	# Flower box under the window.
	p.box((width + 0.25, 0.26, 0.2), m @ place((0, -0.2, -height / 2 - 0.22)), mat("wood"))
	for i in range(6):
		fx = -width / 2 + (i + 0.5) * width / 6
		p.ball(0.11, m @ place((fx, -0.2, -height / 2 - 0.07)), mat("leaf", r.uniform(-0.08, 0.06)), detail=1)
		p.ball(0.06, m @ place((fx + r.uniform(-0.04, 0.04), -0.3, -height / 2 + 0.0)), mat(r.choice(("cloth_red", "hazard", "trim"))), detail=1)


def _loaf(p: Parts, m, kind: str, r):
	"""One bread: a round loaf with score marks, or a long baguette."""
	shade = r.uniform(-0.06, 0.06)
	if kind == "round":
		p.ball(0.15, m, mat("bread", shade), squash=(1.3, 1, 0.75), detail=2)
		for dx in (-0.06, 0.06):
			p.box((0.03, 0.16, 0.02), m @ place((dx, 0, 0.1), (0, 0, 20)), mat("bread_light"))
	else:
		p.ball(0.08, m, mat("bread_light", shade), squash=(4.0, 1, 0.9), detail=2)


def _shop_front(r):
	s = Parts("shop front")
	# Big shop window in a green frame, with two shelves of bread behind the glass.
	wx, wz, ww, wh = -1.9, 1.5, 2.6, 1.4
	s.box((ww, 0.06, wh), place((wx, FRONT - 0.02, wz)), mat("window"))
	for e in (-1, 1):
		s.box((0.14, 0.14, wh + 0.28), place((wx + e * (ww / 2 + 0.07), FRONT - 0.06, wz)), mat("shop_green"))
		s.box((ww + 0.28, 0.14, 0.14), place((wx, FRONT - 0.06, wz + e * (wh / 2 + 0.07))), mat("shop_green"))
	s.box((0.08, 0.1, wh), place((wx, FRONT - 0.06, wz)), mat("shop_green"))
	s.box((ww + 0.45, 0.3, 0.1), place((wx, FRONT - 0.14, wz - wh / 2 - 0.16)), mat("shop_green", -0.1))
	for shelf_z in (1.05, 1.6):
		s.box((ww - 0.2, 0.16, 0.04), place((wx, FRONT - 0.1, shelf_z)), mat("wood_light"))
		for i in range(6):
			bx = wx - ww / 2 + 0.3 + i * (ww - 0.6) / 5
			kind = "round" if (i + int(shelf_z * 10)) % 2 else "long"
			_loaf(s, place((bx, FRONT - 0.13, shelf_z + 0.1), (0, 0, 0 if kind == "round" else 15)), kind, r)

	# Front door with a glass pane, frame, step and knob.
	dw, dh = 0.9, 1.85
	s.box((dw, 0.1, dh), place((DOOR_X, FRONT - 0.03, BASE + dh / 2)), mat("shop_green", 0.05))
	s.box((0.5, 0.06, 0.6), place((DOOR_X, FRONT - 0.09, BASE + dh - 0.45)), mat("window"))
	for e in (-1, 1):
		s.box((0.12, 0.14, dh + 0.12), place((DOOR_X + e * (dw / 2 + 0.06), FRONT - 0.05, BASE + dh / 2)), mat("trim"))
	s.box((dw + 0.36, 0.14, 0.12), place((DOOR_X, FRONT - 0.05, BASE + dh + 0.06)), mat("trim"))
	s.ball(0.05, place((DOOR_X + 0.3, FRONT - 0.13, BASE + 0.95)), mat("hazard"), detail=1)
	s.box((dw + 0.5, 0.5, 0.16), place((DOOR_X, FRONT - 0.25, 0.08)), mat("stone"))

	# Green sign board above the awning, with a golden stripe.
	s.box((4.6, 0.12, 0.38), place((-1.25, FRONT - 0.06, 2.78)), mat("shop_green"))
	s.box((4.4, 0.06, 0.05), place((-1.25, FRONT - 0.13, 2.68)), mat("wheat"))
	s.box((4.4, 0.06, 0.05), place((-1.25, FRONT - 0.13, 2.88)), mat("wheat"))
	s.done(bevel=0.025)

	_awning()
	_hanging_sign(r)


def _awning():
	"""Red-and-cream striped awning over the shop window and door, with a scalloped edge."""
	a = Parts("awning")
	x0, x1 = -3.45, 0.95
	top = Vector((0, FRONT, 2.55))
	bottom = Vector((0, FRONT - 1.05, 2.1))
	u = (bottom - top).normalized()
	w = Vector((0, -u.z, u.y))
	if w.z < 0:
		w = -w
	length = (bottom - top).length
	stripes = 11
	sw = (x1 - x0) / stripes
	for i in range(stripes):
		x = x0 + (i + 0.5) * sw
		colour = "cloth_red" if i % 2 == 0 else "trim"
		a.box((sw + 0.005, length, 0.06), frame(Vector((x, 0, 0)) + (top + bottom) / 2, (1, 0, 0), z_axis=w), mat(colour))
		a.box((sw + 0.005, 0.05, 0.22), place((x, bottom.y, bottom.z - 0.1)), mat(colour))
		a.ball(sw / 2, place((x, bottom.y, bottom.z - 0.21)), mat(colour), squash=(1, 0.2, 0.6), detail=1)
	for x in (x0 + 0.05, x1 - 0.05):
		mid = (top + bottom) / 2
		a.box((0.04, length, 0.04), frame(Vector((x, mid.y, mid.z - 0.08)), (1, 0, 0), z_axis=w), mat("metal_dark"))
	a.done(bevel=0.015)


def _hanging_sign(r):
	"""Round wooden sign with a big loaf on it, hanging from an iron arm beside the small window."""
	h = Parts("hanging sign")
	sx, arm_z = 1.6, 2.75
	h.box((0.07, 1.05, 0.07), place((sx, FRONT - 0.52, arm_z)), mat("metal_dark"))
	h.box((0.05, 0.6, 0.05), place((sx, FRONT - 0.25, arm_z - 0.25), (45, 0, 0)), mat("metal_dark"))
	for dy in (-0.32, 0.32):
		h.cylinder(0.012, 0.18, place((sx, FRONT - 0.65 + dy * 0.6, arm_z - 0.1)), mat("metal_dark"), sides=6)
	m = place((sx, FRONT - 0.65, arm_z - 0.55), (0, 90, 0))
	h.cylinder(0.42, 0.1, m, mat("wood_dark"), sides=24)
	h.cylinder(0.35, 0.14, m, mat("trim"), sides=24)
	h.ball(0.15, place((sx + 0.1, FRONT - 0.65, arm_z - 0.55)), mat("bread"), squash=(0.7, 1.7, 1.0), detail=2)
	for dy in (-0.1, 0.0, 0.1):
		h.box((0.03, 0.03, 0.16), place((sx + 0.2, FRONT - 0.65 + dy, arm_z - 0.5), (20, 0, 0)), mat("bread_light"))
	h.done(bevel=0.015)


def _roof(r):
	"""Two slopes of round terracotta tiles, a dormer window on the front slope, and dark barge boards."""
	slab = Parts("roof")
	tiles = Parts("roof tiles")
	length = HW + 0.6
	dormer_y = FRONT + 0.7  # the dormer's front face
	for sign in (-1, 1):
		eave = Vector((HX, HY + sign * HD / 2, EAVE))
		ridge = Vector((HX, HY, RIDGE))
		u = (ridge - eave).normalized()
		w = Vector((0, -u.z, u.y))
		if w.z < 0:
			w = -w
		start = eave - u * 0.45
		run = (ridge - start).length + 0.08
		slab.box((length, run, 0.14), frame(start + u * run / 2 + w * 0.07, (1, 0, 0), z_axis=w), mat("terracotta_dark"))
		x = HX - length / 2 + 0.13
		while x < HX + length / 2:
			rib = run - 0.1
			if sign < 0 and abs(x - DORMER_X) < DORMER_W / 2 + 0.15:
				rib = (dormer_y - start.y) / u.y  # stop at the dormer
			at = Vector((x, 0, 0)) + start + u * rib / 2 + w * 0.17
			tiles.cylinder(0.125, rib, frame(at, (1, 0, 0), z_axis=u), mat("terracotta", r.choice((-0.08, -0.03, 0.0, 0.05))), sides=10)
			x += 0.25
		# Dark barge board along the visible gable edge (+X end).
		slab.box((0.16, run, 0.42), frame(start + u * run / 2 + w * 0.17 + Vector((length / 2 + 0.08, 0, 0)), (1, 0, 0), z_axis=w), mat("wood_dark"))
	slab.cylinder(0.18, length + 0.06, place((HX, HY, RIDGE + 0.28), (0, 90, 0)), mat("terracotta_dark"), sides=12)

	# Dormer: a little plaster box with its own gable roof and a window.
	d_top = 4.55
	d_depth = HY - dormer_y
	slab.box((DORMER_W, d_depth, d_top - EAVE), place((DORMER_X, dormer_y + d_depth / 2, (d_top + EAVE) / 2)), mat("plaster"))
	slab.box((0.5, 0.06, 0.5), place((DORMER_X, dormer_y - 0.02, 4.15)), mat("window"))
	for e in (-1, 1):
		slab.box((0.09, 0.1, 0.68), place((DORMER_X + e * 0.3, dormer_y - 0.05, 4.15)), mat("trim"))
		slab.box((0.68, 0.1, 0.09), place((DORMER_X, dormer_y - 0.05, 4.15 + e * 0.3)), mat("trim"))
	slab.prism([(-DORMER_W / 2 - 0.2, d_top - 0.05), (DORMER_W / 2 + 0.2, d_top - 0.05), (0, d_top + 0.5)], d_depth + 0.3,
		place((DORMER_X, dormer_y + d_depth / 2 - 0.15, 0)), mat("terracotta"))
	slab.done(bevel=0.03)
	tiles.done(bevel=0.0)


def _chimney():
	c = Parts("chimney")
	cx, cy, bottom, top = 1.0, 2.45, 3.8, 6.0
	c.box((0.75, 0.75, top - bottom), place((cx, cy, (top + bottom) / 2)), mat("brick"))
	z = bottom + 0.35
	while z < top - 0.1:
		c.box((0.77, 0.77, 0.04), place((cx, cy, z)), mat("brick_dark"))
		z += 0.32
	c.box((0.95, 0.95, 0.16), place((cx, cy, top + 0.08)), mat("brick_dark"))
	c.cylinder(0.18, 0.3, place((cx, cy, top + 0.3)), mat("brick_dark"), sides=10)
	# A few puffs of smoke drifting away.
	for (dx, dy, dz), rad in (((0.05, 0.0, 0.85), 0.3), ((0.35, -0.12, 1.35), 0.4), ((0.8, -0.25, 1.9), 0.48)):
		c.ball(rad, place((cx + dx, cy + dy, top + dz)), mat("white"), squash=(1.15, 1, 0.9), detail=2)
	c.done(bevel=0.02)


def _oven(r):
	"""Wood-fired brick oven in the side yard, with a glowing fire inside and a log pile."""
	o = Parts("oven")
	ox, oy = OVEN
	o.box((2.1, 2.0, 0.5), place((ox, oy, 0.25)), mat("stone"))
	o.box((2.2, 2.1, 0.08), place((ox, oy, 0.52)), mat("stone", -0.12))
	o.ball(0.95, place((ox, oy, 0.56)), mat("brick"), squash=(1, 1, 0.85), detail=3)
	# Arched mouth facing the player, with the fire glowing inside.
	mouth = oy - 0.86
	o.cylinder(0.42, 0.3, place((ox, mouth, 0.9), (90, 0, 0)), mat("brick_dark"), sides=16)
	o.box((0.84, 0.3, 0.34), place((ox, mouth, 0.73)), mat("brick_dark"))
	o.cylinder(0.3, 0.32, place((ox, mouth - 0.01, 0.92), (90, 0, 0)), mat("window", -0.4), sides=16)
	o.box((0.6, 0.32, 0.3), place((ox, mouth - 0.01, 0.75)), mat("window", -0.4))
	for dx in (-0.12, 0.0, 0.13):
		o.ball(0.12, place((ox + dx, mouth - 0.12, 0.72)), mat("fire", r.uniform(-0.05, 0.1)), squash=(1, 1, 1.3), detail=1)
	o.cylinder(0.11, 0.5, place((ox + 0.3, oy + 0.3, 1.55)), mat("metal_dark"), sides=10)
	o.cylinder(0.16, 0.08, place((ox + 0.3, oy + 0.3, 1.82)), mat("metal_dark"), sides=10)
	o.done(bevel=0.03)

	logs = Parts("logs")
	lx, ly = 3.95, 0.25
	for row, (count, z) in enumerate(((4, 0.21), (3, 0.43), (2, 0.65))):
		for i in range(count):
			x = lx - (count - 1) * 0.135 + i * 0.27
			m = place((x, ly, z), (90, 0, r.uniform(-4, 4)))
			logs.cylinder(0.13, 0.85, m, mat("wood", r.uniform(-0.1, 0.05)), sides=10)
			logs.cylinder(0.1, 0.87, m, mat("wood_light"), sides=10)
	logs.done(bevel=0.02)


def _props(r):
	p = Parts("props")
	# Bread table under the shop window, with baskets of loaves.
	tx, ty = -1.9, FRONT - 0.55
	p.box((2.4, 0.6, 0.08), place((tx, ty, 0.78)), mat("wood_light"))
	for ex in (-1.1, 1.1):
		for ey in (-0.22, 0.22):
			p.box((0.08, 0.08, 0.74), place((tx + ex, ty + ey, 0.4)), mat("wood"))
	for i, bx in enumerate((-0.75, 0.0, 0.75)):
		p.cylinder(0.27, 0.16, place((tx + bx, ty, 0.9)), mat("wood_light", -0.15), sides=14)
		for k in range(3):
			angle = k * 2.1 + i
			_loaf(p, place((tx + bx + math.cos(angle) * 0.1, ty + math.sin(angle) * 0.1, 1.02), (0, 0, k * 60)), "round" if i != 1 else "long", r)

	# Cafe table with a parasol and two chairs.
	cx, cy = -3.7, -2.95
	p.cylinder(0.42, 0.06, place((cx, cy, 0.78)), mat("trim"), sides=16)
	p.cylinder(0.04, 2.0, place((cx, cy, 1.0)), mat("wood_dark"), sides=8)
	p.cylinder(0.25, 0.06, place((cx, cy, 0.11)), mat("metal_dark"), sides=12)
	p.cylinder(0.95, 0.42, place((cx, cy, 2.05), (0, 0, 22.5)), mat("trim"), sides=8, top_radius=0.06)
	p.cylinder(0.96, 0.1, place((cx, cy, 1.82), (0, 0, 22.5)), mat("cloth_red"), sides=8)
	p.ball(0.08, place((cx, cy, 2.3)), mat("cloth_red"), detail=1)
	for dx, dy, turn in ((0.7, 0.1, 0), (-0.25, -0.7, 90)):
		m = place((cx + dx, cy + dy, 0), (0, 0, turn))
		p.box((0.42, 0.42, 0.07), m @ place((0, 0, 0.48)), mat("wood"))
		p.box((0.07, 0.42, 0.5), m @ place((0.2, 0, 0.75)), mat("wood"))
		for ex in (-0.17, 0.17):
			for ey in (-0.17, 0.17):
				p.box((0.06, 0.06, 0.46), m @ place((ex, ey, 0.23)), mat("wood_dark"))
	_loaf(p, place((cx + 0.1, cy, 0.86)), "round", r)

	# Flour sacks beside the door.
	for (sx, sy), z, squash in (((1.75, -1.15), 0.3, (1, 0.85, 1.25)), ((2.1, -1.1), 0.3, (1, 0.85, 1.25)), ((1.95, -1.5), 0.22, (1.3, 0.85, 0.9))):
		p.ball(0.23, place((sx, sy, z)), mat("sack", r.uniform(-0.05, 0.03)), squash=squash, detail=2)
		if squash[2] > 1:
			p.cylinder(0.06, 0.1, place((sx, sy, z + 0.32)), mat("sack", -0.1), sides=8)

	# Flower pots either side of the door.
	for px in (DOOR_X - 0.85, DOOR_X + 0.8):
		p.cylinder(0.2, 0.36, place((px, FRONT - 0.35, 0.18)), mat("terracotta"), sides=14, top_radius=0.24)
		p.ball(0.3, place((px, FRONT - 0.35, 0.58)), mat("leaf", r.uniform(-0.06, 0.06)), squash=(1, 1, 1.1), detail=2)

	# Delivery hand-cart with two crates of bread.
	cart = place((2.7, -2.75, 0), (0, 0, -25))
	p.box((1.1, 0.75, 0.08), cart @ place((0, 0, 0.45)), mat("wood"))
	for dy in (-0.42, 0.42):
		p.cylinder(0.27, 0.08, cart @ place((0.05, dy, 0.27), (90, 0, 0)), mat("wood_dark"), sides=14)
		p.box((0.9, 0.05, 0.05), cart @ place((-0.9, dy * 0.55, 0.52), (0, -8, 0)), mat("wood"))
	for dx in (-0.27, 0.27):
		p.box((0.5, 0.65, 0.3), cart @ place((dx, 0, 0.64)), mat("wood_light", 0.05))
		for k in range(3):
			_loaf(p, cart @ place((dx, -0.18 + k * 0.18, 0.84), (0, 0, 90)), "long", r)

	# Bushes in the corners of the plot.
	for at, rad in (((-4.35, -4.3), 0.42), ((-3.95, -4.45), 0.3), ((4.3, -4.25), 0.4), ((4.4, -3.85), 0.28), ((-4.35, 3.9), 0.45)):
		p.ball(rad, place((*at, rad * 0.8)), mat("leaf", r.uniform(-0.08, 0.06)), squash=(1, 1, 0.9), detail=2)
	p.done(bevel=0.025)
