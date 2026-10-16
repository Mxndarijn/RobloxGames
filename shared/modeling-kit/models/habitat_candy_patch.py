# habitat_candy_patch: pink sugar-soil mound (7.8 x 4.5 x 7.8) with a flat biscuit seat at z=2.4 for the slime,
# gumdrops round the rim and two swirl lollipops at the back rim (tops at 4.5).
import math, random
from mathutils import Matrix, Vector
from lib import *
from models._habitat import *

W, H = 7.8, 4.5
PLAZA, PATH, LILAC = P["ranch_plaza"], P["ranch_path"], P["ranch_lilac"]
SOIL_LO, SOIL_HI = mix(WOOD, PINK, 0.3), mix(PLAZA, PINK, 0.35)  # sugar soil: warm pink-brown
BISCUIT_LO, BISCUIT_HI = mix(WOOD, BUTTER, 0.35), mix(BUTTER, PLAZA, 0.45)
R = random.Random(11)
parts = []

# mound: flank -> rounded rim (~2.45) -> shallow dip at 2.15 round the biscuit
MOUND = [(0, 0), (3.75, 0), (3.9, 0.25), (3.75, 0.9), (3.45, 1.55), (3.05, 2.1), (2.65, 2.4), (2.35, 2.3), (2.1, 2.15), (0, 2.15)]
def mound_col(i, k, z):
    if i >= 7:
        return mix(SOIL_LO, SOIL_HI, 0.4)
    return shade(mix(SOIL_LO, SOIL_HI, min(1.0, z / 2.4)), R.uniform(0.95, 1.03))
m = lathe("Mound", MOUND, segs=16,  # r04: 18 -> 16 (tri budget)
          color_fn=mound_col)
for v in m.data.vertices:  # soft crumbly wobble on the flank only
    if 0.2 < v.co.z < 2.35 and v.co.xy.length > 2.5:
        s = 1 + R.uniform(-0.04, 0.02)
        v.co.x *= s
        v.co.y *= s
parts.append(m)

# biscuit seat: scalloped round biscuit, top exactly at SEAT; docking holes as flush darker dots
SC, BR = 10, 2.1  # r02: fewer columns (tri budget); r03: 2*SC columns so the scallop alternates evenly
bis = lathe("Biscuit", [(0, 1.95), (BR, 1.95), (BR + 0.06, 2.2), (BR - 0.08, SEAT), (0, SEAT)], segs=SC * 2,
            color_fn=lambda i, k, z: BISCUIT_HI if i >= 3 else (BISCUIT_LO if i == 0 else mix(BISCUIT_LO, BISCUIT_HI, 0.5)))
for v in bis.data.vertices:  # scallop: every other column pulled in
    a = math.atan2(v.co.y, v.co.x)
    k = round(a / math.tau * SC * 2) % (SC * 2)
    if k % 2 and v.co.xy.length > 1.0:
        v.co.x *= 0.92
        v.co.y *= 0.92
parts.append(bis)
for i, (x, y) in enumerate(((-0.9, 0.55), (0.9, 0.55), (0, -0.25), (-0.9, -1.0), (0.9, -1.0))):
    parts.append(cylinder(f"Dock{i}", 0.13, 0.04, (x, y, SEAT - 0.04), mix(BISCUIT_LO, WOOD, 0.4), segs=6))

# gumdrops on the rim and flank: sugared domes (lathe), flat bottoms sunk into the soil
def gumdrop(name, r, h, col, pos):
    # r02: squat dome (r01's straight sides read as jars/bottles)
    prof = [(0, -0.3), (r * 1.04, 0.05),  # r04: sunk cone base, one row less (tri budget)
            (r * 0.9, h * 0.42), (r * 0.62, h * 0.8), (r * 0.28, h * 0.98), (0, h)]
    lo, hi = shade(col, 0.82), mix(col, P["ranch_cream"], 0.2)
    g = lathe(name, prof, segs=8, color_fn=lambda i, k, z: shade(mix(lo, hi, min(1.0, max(0.0, z / h))), 1.05 if k % 3 == 0 else 1.0))
    return frame_obj(g, Matrix.Translation(Vector(pos)))
GUMS = [(-95, 3.05, 0.6, 0.68, ROOF), (-60, 3.15, 0.55, 0.6, BUTTER), (-128, 3.1, 0.55, 0.62, LILAC), (-25, 3.0, 0.52, 0.58, GOO),
        (20, 3.15, 0.55, 0.62, PINK), (160, 3.15, 0.55, 0.62, GOO), (200, 3.0, 0.52, 0.58, BUTTER), (90, 3.1, 0.6, 0.66, LILAC),
        (-160, 3.4, 0.46, 0.5, PINK), (-10, 3.45, 0.44, 0.48, ROOF)]
for i, (a, r, gr, gh, col) in enumerate(GUMS):
    aa = math.radians(a)
    x, y = r * math.cos(aa), r * math.sin(aa)
    z = max(0.0, 2.4 - (r - 2.65) * 1.3) + 0.15  # follow the flank; r05: +0.15, r04 gumdrops sank to half-domes
    parts.append(gumdrop(f"Gum{i}", gr, gh, col, (x, y, z)))

# two swirl lollipops at the back rim, candy discs facing the front (-Y), tops at H
def lollipop(name, x, y, col, lean):
    rr, th, top = 1.15, 0.34, H  # r02: bigger discs, shorter sticks
    stick = cylinder(name + "Stick", 0.13, top - rr - 1.6, (x, y, 1.6), P["ranch_cream"], segs=6)
    # r03: 6 face rings so the stripe offset per ring twists into a spiral (r02's 4 rings read as a pinwheel)
    face = [rr * f for f in (0.18, 0.36, 0.54, 0.72, 0.88)]
    rows = [(0, -th / 2)] + [(r, -th / 2) for r in face] + [(rr, 0)] + [(r, th / 2) for r in reversed(face)] + [(0, th / 2)]
    def sw(i, k, z):
        ring = min(i, len(rows) - 2 - i)  # 0 centre .. 5 edge
        return col if (k + ring * 2) % 8 < 4 else mix(P["ranch_cream"], col, 0.15)
    disc = lathe(name + "Disc", rows, segs=16, color_fn=sw)
    frame_obj(disc, Matrix.Translation(Vector((x, y, top - rr))) @ Matrix.Rotation(math.radians(lean), 4, "Y") @ Matrix.Rotation(math.radians(90), 4, "X"))
    return [stick, disc]
parts += lollipop("LolL", -2.55, 1.85, PINK, 8)
parts += lollipop("LolR", 2.55, 1.85, LILAC, -8)

o = finish("habitat_candy_patch", parts)
fit(o, W, H, W)
