"""NUCLEAR POWER PLANT (1 tile): a big concrete cooling tower at the back with a wisp of steam, a
domed reactor building in front, and a low turbine hall on the side the player sees. Plot is
-2.5..2.5 on X and Y (see kit.py)."""
from kit import Parts, mat, place

TILES = 1


def build():
	g = Parts("ground")
	g.box((4.8, 4.8, 0.14), place((0, 0, 0.07)), mat("concrete_dark"))
	g.done(bevel=0.03)

	# Cooling tower: a waisted shape made of stacked cone slices, wide at the bottom.
	t = Parts("cooling tower")
	cx, cy = -0.95, 1.0
	height, steps = 5.2, 10
	for i in range(steps):
		z0 = i / steps
		z1 = (i + 1) / steps
		t.cylinder(_tower_radius(z0), height / steps, place((cx, cy, 0.14 + height * (z0 + z1) / 2)), mat("concrete", -0.03 * (i % 2)), sides=28, top_radius=_tower_radius(z1))
	t.cylinder(_tower_radius(1.0) + 0.05, 0.12, place((cx, cy, 0.14 + height)), mat("concrete_dark"), sides=28)
	t.cylinder(_tower_radius(0.0) + 0.05, 0.2, place((cx, cy, 0.24)), mat("hazard", -0.2), sides=28)
	t.done(bevel=0.02)

	steam = Parts("steam")
	for i, (dx, dz, r) in enumerate(((0.0, 0.5, 0.9), (0.4, 1.2, 0.75), (0.9, 1.8, 0.6))):
		steam.ball(r, place((cx + dx, cy - dx * 0.4, 0.14 + height + dz)), mat("white"), squash=(1.2, 1.0, 0.75))
	steam.done(bevel=0)

	r = Parts("reactor")
	rx, ry = 1.0, -0.4
	r.cylinder(1.05, 1.5, place((rx, ry, 0.89)), mat("concrete"), sides=28)
	r.ball(1.05, place((rx, ry, 1.64)), mat("concrete", 0.05), squash=(1, 1, 0.8), detail=3)
	r.box((0.5, 0.1, 0.7), place((rx, ry - 1.05, 0.5)), mat("metal_dark"))
	r.box((0.6, 0.08, 0.12), place((rx, ry - 1.08, 0.92)), mat("hazard"))
	# Turbine hall at the front left, with a row of windows.
	r.box((1.6, 1.0, 0.9), place((-0.9, -1.55, 0.59)), mat("trim"))
	r.box((1.7, 1.1, 0.1), place((-0.9, -1.55, 1.08)), mat("roof"))
	for i in range(4):
		r.box((0.24, 0.05, 0.3), place((-1.45 + i * 0.37, -2.07, 0.7)), mat("window"))
	r.done(bevel=0.03)


def _tower_radius(t: float) -> float:
	"""Radius of the cooling tower at height share t (0 = bottom, 1 = top): narrowest at 70%."""
	return 0.75 + 0.75 * abs(t - 0.7) ** 1.4 / 0.7 ** 1.4 * (1.0 if t < 0.7 else 0.35)
