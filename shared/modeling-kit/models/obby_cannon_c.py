# obby_cannon_c (option C): a banded barrel on a swivel turret (steal-a-slime obby, Aim the Cannon).
# A slate cog ring on the deck carries an orange turntable with a pivot cap; an orange U-fork rises from it and holds
# the barrel on two big hub bolts. The barrel is a straight slate tube ringed by three orange bands, ending in a wide
# bell mouth with an orange lip (the dark bore is where you climb in) and a little orange sight bead on top.
# Mechanical and clean: the cog ring and turntable make the left-right sweep read as a turret turning.
# Fits the old 4 x 3 x 4 cannon box; the swivel axis is x = y = 0, the mouth aims at -Y.
import math
from mathutils import Vector
from lib import *
from models._obby_cannon_parts import *

ZC = 1.62
TILT = AIM_TILT
D = axis_dir(TILT)
UP = Vector((0.0, math.sin(math.radians(TILT)), math.cos(math.radians(TILT))))
C = Vector((0.0, 0.0, ZC))
ROT = barrel_rot(TILT)
parts = []

# -- the cog ring and the turntable
parts.append(disc("CogRing", 1.72, 0.0, 0.3, METAL_LO, METAL, segs=28))
for k in range(16):
    a = k * 360 / 16
    r = math.radians(a)
    parts.append(bb(f"Tooth{k}", (0.34, 0.3, 0.26), (1.8 * math.cos(r), 1.8 * math.sin(r), 0.14), METAL_LO, METAL,
                    bev=0, rot=(0, 0, a)))
parts.append(disc("Turntable", 1.46, 0.26, 0.28, ORANGE_LO, ORANGE, segs=28))
parts += bolts("Bolt", 8, 1.22, 0.54, METAL_HI, r=0.11, a0=math.pi / 8)
parts.append(disc("PivotCap", 0.55, 0.5, 0.16, METAL_LO, METAL_HI, segs=16))

# -- the U-fork: two rounded orange arms rising to the barrel's axis, slate hub bolts
for s in (-1, 1):
    x = s * 1.12
    parts.append(bb(f"Arm{s}", (0.34, 0.95, 1.18), (x, 0.0, 0.5 + 0.59), ORANGE_LO, ORANGE, bev=0.12))
    parts.append(cylinder(f"ArmTop{s}", 0.48, 0.34, (x - s * 0.17, 0, ZC), ORANGE, segs=14, rot=(0, s * 90, 0)))
    parts.append(cylinder(f"Hub{s}", 0.3, 0.16, (x + s * 0.15, 0, ZC), METAL, segs=10, rot=(0, s * 90, 0)))
    parts.append(cylinder(f"HubNut{s}", 0.14, 0.1, (x + s * 0.3, 0, ZC), METAL_HI, segs=6, rot=(0, s * 90, 0)))
# the yoke's crossbar under the barrel, on the turntable
parts.append(bb("Yoke", (2.4, 0.8, 0.3), (0, 0.0, 0.62), ORANGE_LO, ORANGE, bev=0.1))

# -- the barrel: round breech, straight tube, wide bell mouth with an orange lip, dark bore back inside
prof = [
    (0.0, -1.7), (0.6, -1.66), (0.84, -1.48), (0.9, -1.2),      # breech
    (0.84, 0.9), (0.98, 1.4),                                  # tube, bell starts
    (1.2, 1.7), (1.22, 1.86), (1.06, 1.98), (0.86, 1.92),      # bell lip
    (0.74, 1.6), (0.7, -0.6), (0.0, -0.7),                     # bore
]
cols = [METAL_LO, METAL_LO, METAL, METAL, METAL, METAL, ORANGE, ORANGE_HI, ORANGE_LO, BORE_HI, BORE, BORE]
parts.append(lathe("Barrel", prof, cols, segs=18, pos=C, rot=ROT))
for i, z in enumerate((-1.05, -0.2, 0.65)):
    parts.append(band(f"Band{i}", 0.8, 0.97, z, z + 0.3, ORANGE, ORANGE_LO, segs=18, pos=C, rot=ROT))
# breech knob and the sight bead on top near the mouth
parts.append(blob("Knob", 0.28, C - D * 1.8, ORANGE, subdiv=2, jitter=0))
parts.append(blob("Sight", 0.16, C + D * 1.15 + UP * 0.96, ORANGE_HI, subdiv=2, squash=(0.8, 1.3, 1.0), jitter=0))

finish("obby_cannon_c", parts)
