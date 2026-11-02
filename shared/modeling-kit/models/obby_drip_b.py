# obby_drip_b (option B, "Goo Pipe"): Climb's drip as a slate goo pipe coming out of the wall behind the ladder,
# bending down over the climb into a flared spout. Lime bands with rivets, a lime valve wheel on top of the bend,
# a bolted wall flange at the back end; red goo rolls round the spout's lip with three drips, and the drop waits
# under the mouth. The spout keeps the old nozzle's 2.6 footprint and bottom; the pipe adds height (2.6) and runs
# 3 studs back (+Y, toward the ladder), so it needs room behind the drip point (decor, no collision).
# The drop: a rounder, squatter teardrop (2.0 x 2.05 x 2.0). The drain: the shared slate tub.
# DRIP_PART=set|nozzle|drop|drain (see models/_obby_drip_parts.py).
import math
from mathutils import Matrix
from lib import *
from models._obby_drip_parts import *
import models._obby_drip_parts as P

P.DROP_KW.update(height=2.05, pinch=1.15)

PR = 0.5  # pipe radius
BEND = 0.75  # bend radius of the elbow
BACK = 3.0  # how far the pipe runs back


def nozzle(z0):
    parts = []
    zt = z0 + 1.0  # where the straight spout meets the elbow
    zp = zt + BEND  # the horizontal pipe's axis height
    # the spout: flared mouth with a rolled lip, a dark bore, red goo up inside
    prof = [
        (0.0, 0.42), (0.6, 0.4), (0.66, 0.18), (0.76, 0.02),   # goo inside -> bore wall
        (0.96, 0.0), (1.06, 0.12), (0.98, 0.28),               # rolled lip
        (0.62, 0.62), (PR, 0.86), (PR, 1.06),                   # flare -> pipe
        (0.0, 1.06),
    ]
    cols = [HAZ_LO, BORE, BORE, BORE_HI, SLATE_LO, SLATE, SLATE_HI, SLATE, SLATE, SLATE]
    parts.append(rev("Spout", prof, flat(cols), segs=20, pos=(0, 0, z0), smooth=False))
    # the elbow and the run back to the wall
    pts = []
    for k in range(7):
        a = math.radians(90 * k / 6)
        pts.append((0, BEND - BEND * math.cos(a), zt + BEND * math.sin(a)))
    pts += [(0, BEND + 0.6, zp), (0, BACK - 0.3, zp)]
    pipe = tube("Pipe", [(0, 0, zt - 0.15)] + pts, [PR] * (len(pts) + 1), SLATE, segs=14, twist_free=True)
    gradient(pipe, SLATE_LO, SLATE_HI, zt - 0.2, zp + PR)
    parts.append(keep_smooth(pipe))
    # lime bands: one on the spout, one past the bend, rivets on them
    band = [(PR - 0.02, -0.12), (PR + 0.1, -0.08), (PR + 0.1, 0.08), (PR - 0.02, 0.12), (PR - 0.08, 0.0)]
    lime = flat([LIME_LO, LIME, LIME_HI, LIME, LIME_LO])
    parts.append(rev("BandSpout", band, lime, segs=16, smooth=False, loop=True, pos=(0, 0, z0 + 0.98)))
    parts.append(rev("BandPipe", band, lime, segs=16, smooth=False, loop=True, rot=(90, 0, 0),
                     pos=(0, BEND + 0.9, zp)))
    # the wall flange at the back end, bolted
    fl = [(0.0, 0.0), (0.92, 0.0), (1.0, 0.08), (1.0, 0.22), (0.92, 0.3), (0.0, 0.3)]
    parts.append(rev("Flange", fl, flat([SLATE_LO, SLATE_LO, SLATE, SLATE_HI, SLATE_HI]), segs=20, smooth=False,
                     rot=(-90, 0, 0), pos=(0, BACK - 0.3, zp)))
    for k in range(6):
        a = math.radians(30 + 60 * k)
        parts.append(keep_smooth(blob(f"Bolt{k}", 0.11, (0.78 * math.cos(a), BACK - 0.36, zp + 0.78 * math.sin(a)),
                                      SLATE_HI, subdiv=1, jitter=0, squash=(1, 0.6, 1)), False))
    # the valve wheel on top of the bend: a short stem and a lime ring with a cross
    parts.append(cylinder("ValveStem", 0.12, 0.42, (0, BEND + 0.15, zp + PR - 0.05), SLATE_LO, segs=8))
    ring = [(0.36, 0.0), (0.5, 0.0), (0.54, 0.07), (0.5, 0.14), (0.36, 0.14), (0.32, 0.07)]
    parts.append(rev("Wheel", ring, flat([LIME_LO, LIME, LIME_HI, LIME_HI, LIME, LIME_LO]), segs=18, smooth=False,
                     loop=True, pos=(0, BEND + 0.15, zp + PR + 0.32)))
    for k in range(2):
        sp = box(f"Spoke{k}", (0.86, 0.1, 0.08), (0, 0, 0), LIME)
        sp.data.transform(Matrix.Translation((0, BEND + 0.15, zp + PR + 0.39)) @ Matrix.Rotation(math.radians(90 * k), 4, "Z"))
        parts.append(sp)
    parts.append(keep_smooth(blob("WheelHub", 0.13, (0, BEND + 0.15, zp + PR + 0.4), LIME_HI, subdiv=1, jitter=0,
                                  squash=(1, 1, 0.7)), False))
    # red goo round the lip with three drips
    parts.append(lip_goo("LipGoo", z0 + 0.12, 0.98, [(-110, 0.4), (-20, 0.22), (150, 0.32)], seed=5, thick=0.12, n=28))
    return parts


ship("b", nozzle)
