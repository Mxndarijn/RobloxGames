# obby_cannon_a (option A): a chunky cartoon cannon on a goo puddle (steal-a-slime obby, Aim the Cannon).
# A fat, short slate barrel with orange bands and a big flared orange mouth (a deep dark bore you climb into),
# goo dripping off the lower lip, held between two cheek plates with orange trunnion hubs. It all stands on an
# orange swivel turntable (bolted rim, dark seam) sitting in a green goo puddle: the turntable is the pivot the
# barrel sweeps round. Fits the old 4 x 3 x 4 cannon box; the swivel axis is x = y = 0, the mouth aims at -Y.
import math
from mathutils import Vector
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo
from models._obby_cannon_parts import *

ZC = 1.58  # barrel axis height at the pivot
TILT = AIM_TILT
D = axis_dir(TILT)
UP = Vector((0.0, math.sin(math.radians(TILT)), math.cos(math.radians(TILT))))  # barrel's local "up" (perp to D)
C = Vector((0.0, 0.0, ZC))
parts = []

# -- the goo puddle (the cannon's foot) and the swivel turntable on it
pb = [Ball((0, 0, 0.12), (1.8, 1.75, 0.34))]
for k, (a, d, s) in enumerate(((0.3, 1.4, 0.55), (1.5, 1.45, 0.45), (2.6, 1.35, 0.6), (3.7, 1.5, 0.45),
                               (4.8, 1.35, 0.55), (5.7, 1.4, 0.4))):
    pb.append(Ball((d * math.cos(a), d * math.sin(a), 0.1), (s, s * 0.9, 0.26)))
puddle = metaball_mesh("CannonPuddle", pb, resolution=0.16, tris=240, clamp_z=0.0)


def goo_col(co, n):
    c = mix(GOO_DEEP, GOO, min(1.0, 0.35 + co.z / 0.45))
    if n.z > 0.6:
        c = mix(c, GOO_HI, (n.z - 0.6) / 0.4 * 0.5)
    return c


parts.append(paint_goo(puddle, goo_col))
parts.append(disc("TurnSeat", 1.72, 0.2, 0.2, METAL_LO, METAL, segs=24))       # dark seam under the turntable
parts.append(disc("Turntable", 1.6, 0.36, 0.26, ORANGE_LO, ORANGE, segs=24))   # the swivel plate
parts += bolts("Bolt", 10, 1.38, 0.62, METAL_HI, r=0.12)
parts.append(disc("Hub", 0.62, 0.6, 0.12, METAL_LO, METAL, segs=16))            # the pivot hub in the middle

# -- the cradle: two cheek plates on the turntable, orange trunnion hubs on the barrel's axis
for s in (-1, 1):
    parts.append(bb(f"Cheek{s}", (0.3, 1.5, 1.05), (s * 1.0, 0.1, 1.0), METAL_LO, METAL, bev=0.13))
    parts.append(cylinder(f"Trun{s}", 0.42, 0.34, (s * 1.12, 0, ZC), ORANGE, segs=12, rot=(0, s * 90, 0)))
    parts.append(cylinder(f"TrunCap{s}", 0.22, 0.14, (s * 1.44, 0, ZC), METAL_HI, segs=10, rot=(0, s * 90, 0)))

# -- the barrel: breech -> body -> neck -> flared mouth with a rolled orange lip -> dark bore back inside
prof = [
    (0.0, -1.62), (0.62, -1.62), (0.88, -1.45), (0.94, -1.1),   # breech
    (0.86, 0.35), (0.9, 0.95), (1.1, 1.45),                      # body, neck, flare
    (1.2, 1.72), (1.12, 1.9), (0.92, 1.88),                      # rolled lip
    (0.78, 1.62), (0.72, -0.5), (0.0, -0.62),                    # bore
]
cols = [METAL_LO, METAL_LO, METAL, METAL, METAL, ORANGE, ORANGE, ORANGE_HI, ORANGE_LO, BORE_HI, BORE, BORE]
parts.append(lathe("Barrel", prof, cols, segs=18, pos=C, rot=barrel_rot(TILT)))
parts.append(band("BandBack", 0.86, 1.04, -1.25, -0.9, ORANGE, ORANGE_LO, segs=18, pos=C, rot=barrel_rot(TILT)))
parts.append(band("BandMid", 0.8, 0.96, 0.55, 0.85, ORANGE, ORANGE_LO, segs=18, pos=C, rot=barrel_rot(TILT)))
knob = C - D * 1.72
parts.append(blob("Knob", 0.3, knob, METAL, subdiv=2, jitter=0))

# -- goo oozing over the lower lip and two drips hanging off it
lip = C + D * 1.8
balls = []
for k in range(9):
    a = math.radians(-70 + k * 17.5)
    side = Vector((1, 0, 0))
    p = lip + (side * math.sin(a) - UP * math.cos(a)) * 1.17
    balls.append(Ball(p, (0.26, 0.24, 0.2)))
for x, ln in ((-0.45, 0.22), (0.4, 0.36)):
    base = lip + Vector((x, 0, 0)) - UP * 1.08
    for k in range(5):
        t = k / 4
        balls.append(Ball(base + Vector((0, -0.05, -ln * t)), 0.16 * (1 - 0.35 * t) + 0.05))
    balls.append(Ball(base + Vector((0, -0.05, -ln - 0.12)), 0.19))
drips = metaball_mesh("CannonDrips", balls, resolution=0.08, tris=240)
parts.append(paint_goo(drips, lambda co, n: mix(GOO, GOO_HI, 0.5 * max(0.0, n.z) ** 2)))

finish_smooth("obby_cannon_a", parts)
