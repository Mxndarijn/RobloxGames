# habitat_prop_cosmo: a little brass telescope on a wooden tripod, tilted up to the sky.
import math
from mathutils import Vector
from models._habitat_prop5 import *

BRASS, BRASS_LO = rgb(250, 196, 70), rgb(226, 150, 44)
BAND = rgb(196, 112, 40)
WOOD_L, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
LENS = rgb(90, 200, 255)
parts = []
APEX = Vector((0, 0.05, 0.64))
for i, a in enumerate((-90, 30, 150)):
    r = math.radians(a)
    foot = Vector((math.cos(r) * 0.52, math.sin(r) * 0.5 + 0.05, 0))
    parts.append(tube(f"Leg{i}", [foot, APEX], [0.07, 0.05], WOOD_L, segs=5))
    parts.append(gcyl(f"Foot{i}", 0.08, 0.05, (foot.x, foot.y, 0), WOOD_D, segs=6))
parts.append(gcyl("Mount", 0.11, 0.14, (0, 0.05, 0.6), BAND, BRASS_LO, segs=8))
# tube: low eyepiece end at -x, wide lens end at +x, tilted up ~24 degrees
a0, a1 = Vector((-0.66, 0.3, 0.56)), Vector((0.66, -0.22, 1.1))
d = (a1 - a0).normalized()
P0 = lambda t: a0 + (a1 - a0) * t
parts.append(tube("Eyepiece", [a0 - d * 0.12, a0 + d * 0.05], [0.06, 0.07], BAND, segs=8))
parts.append(tube("Tube", [P0(0.03), P0(0.55), P0(0.56), P0(0.92)], [0.11, 0.13, 0.155, 0.17], BRASS, segs=10))
parts.append(tube("Hood", [P0(0.9), P0(1.0)], [0.21, 0.23], BRASS_LO, segs=10))
for i, t in enumerate((0.2, 0.555, 0.9)):
    parts.append(tube(f"Band{i}", [P0(t) - d * 0.03, P0(t) + d * 0.03], [0.13 + 0.06 * t] * 2, BAND, segs=10))
parts.append(tube("Lens", [P0(1.0) - d * 0.01, P0(1.0) + d * 0.015], [0.18, 0.18], LENS, segs=10))
# little star sparkle hanging over the lens? no: keep it one idea. Finder scope on top.
parts.append(tube("Finder", [P0(0.45) + Vector((0, 0, 0.2)), P0(0.7) + Vector((0, 0, 0.22))], [0.04, 0.05], BRASS_LO, segs=6))
ship("habitat_prop_cosmo", parts)
