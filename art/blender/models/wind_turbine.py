"""WIND TURBINE (1 tile): a tall white tower on a concrete footing, with the nacelle and three
blades at the top facing the camera (toward +X / -Y). Plot is -2.5..2.5 on X and Y (see kit.py)."""
import math

from mathutils import Vector

from kit import Parts, frame, mat, place

TILES = 1
HEIGHT = 9.0  # top of the tower (hub height)
FACING = Vector((1, -1, 0)).normalized()  # the rotor looks at the camera
BLADE = 3.6


def build():
	_footing()
	_tower()
	_rotor()


def _footing():
	g = Parts("footing")
	g.cylinder(1.5, 0.3, place((0, 0, 0.15)), mat("concrete"), sides=24)
	g.cylinder(1.1, 0.12, place((0, 0, 0.36)), mat("concrete_dark"), sides=24)
	# A small door box at the foot, on the side the player sees.
	g.box((0.7, 0.5, 0.9), place((0.55, -0.55, 0.75), (0, 0, 45)), mat("white", -0.06))
	g.box((0.36, 0.06, 0.62), place((0.73, -0.73, 0.68), (0, 0, 45)), mat("metal_dark"))
	g.done(bevel=0.04)


def _tower():
	t = Parts("tower")
	t.cylinder(0.55, HEIGHT, place((0, 0, 0.4 + HEIGHT / 2)), mat("white"), sides=20, top_radius=0.28)
	# Thin coloured band near the bottom, like real turbines.
	t.cylinder(0.56, 0.25, place((0, 0, 1.4)), mat("hazard"), sides=20, top_radius=0.55)
	t.done(bevel=0.02)


def _rotor():
	r = Parts("rotor")
	top = Vector((0, 0, 0.4 + HEIGHT + 0.25))
	# Nacelle: a rounded box along the facing direction, a little behind the hub.
	r.box((1.5, 0.62, 0.62), frame(top - FACING * 0.35, FACING, z_axis=(0, 0, 1)), mat("white", -0.04))
	hub = top + FACING * 0.55
	r.ball(0.36, frame(hub, FACING, z_axis=(0, 0, 1)), mat("white"), squash=(1.3, 1, 1))
	# Three blades in the plane facing the camera, one pointing up a little off vertical.
	side = Vector((0, 0, 1)).cross(FACING).normalized()  # across the rotor, sideways
	up = Vector((0, 0, 1))
	for i in range(3):
		a = math.radians(100 + i * 120)
		out = (up * math.sin(a) + side * math.cos(a)).normalized()
		centre = hub + out * (BLADE / 2 + 0.25) + FACING * 0.08
		r.box((0.1, 0.36, BLADE), frame(centre, FACING, z_axis=out), mat("white"))
		r.box((0.11, 0.37, 0.4), frame(hub + out * (BLADE + 0.05) + FACING * 0.08, FACING, z_axis=out), mat("barn_red"))
	r.done(bevel=0.03)
