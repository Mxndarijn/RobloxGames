# habitat_candy_patch_overlay: candy dressing for the crate pad: a pink sugar-soil frame round the mat,
# sugared gumdrops on the rim band and two swirl lollipops at opposite corners (front-left, back-right).
import math, random
from mathutils import Matrix, Vector
from lib import *
from models._habitat import *
from models._habitat_overlay import *

PLAZA, LILAC = P["ranch_plaza"], P["ranch_lilac"]
SOIL_LO, SOIL_HI = mix(WOOD, PINK, 0.3), mix(PLAZA, PINK, 0.35)  # sugar soil: warm pink-brown (as the full habitat)
R = random.Random(11)
parts = [frame("SugarSoil", mix(SOIL_HI, CREAM, 0.3), SOIL_LO, seed=11, wobble=0.1)]  # r04: sugared top, contrast vs the red mat


def gumdrop(name, r, h, col, pos):
    """Squat sugared dome, flat bottom on pos (never below the deck)."""
    prof = [(0, 0), (r, 0), (r * 0.95, h * 0.35), (r * 0.66, h * 0.78), (r * 0.28, h * 0.97), (0, h)]
    lo, hi = shade(col, 0.92), mix(col, CREAM, 0.25)  # r05: lighter base, roblox look went muddy
    g = lathe(name, prof, segs=8, color_fn=lambda i, k, z: shade(mix(lo, hi, min(1.0, z / h)), 1.05 if k % 3 == 0 else 1.0))
    return frame_obj(g, Matrix.Translation(Vector(pos)))


def lollipop(name, x, y, col, out_deg, top=2.55, rr=0.86):
    """Swirl disc on a cream stick; the disc faces outward along out_deg (corner diagonal)."""
    th = 0.34
    cz = top - rr
    stick = cylinder(name + "Stick", 0.14, cz, (x, y, 0), CREAM, segs=6)
    face = [rr * f for f in (0.18, 0.36, 0.54, 0.72, 0.88)]
    rows = [(0, -th / 2)] + [(r, -th / 2) for r in face] + [(rr, 0)] + [(r, th / 2) for r in reversed(face)] + [(0, th / 2)]

    def sw(i, k, z):
        ring = min(i, len(rows) - 2 - i)
        return col if (k + ring * 2) % 8 < 4 else mix(CREAM, col, 0.15)
    disc = lathe(name + "Disc", rows, segs=16, color_fn=sw)
    frame_obj(disc, Matrix.Translation(Vector((x, y, cz))) @ Matrix.Rotation(math.radians(out_deg + 90), 4, "Z")
              @ Matrix.Rotation(math.radians(90), 4, "X"))
    return [stick, disc]


# lollipops on two opposite corners (point-symmetric -> bbox stays centred)
(x0, y0, a0), (x1, y1, a1), (x2, y2, a2), (x3, y3, a3) = CORNERS
parts += lollipop("LolFL", x0, y0, PINK, a0)
parts += lollipop("LolBR", x2, y2, LILAC, a2)

# gumdrops: a big + small pair on the two free corners, one per edge middle, small ones round the lollipop sticks
GUM = [  # (x, y, r, h, colour)
    (x1 - 0.1, y1 + 0.1, 0.55, 0.66, ROOF), (x1 - 0.7, y1 - 0.05, 0.36, 0.44, BUTTER),
    (x3 + 0.1, y3 - 0.1, 0.55, 0.66, GOO), (x3 + 0.7, y3 + 0.05, 0.36, 0.44, PINK),
    (0.0, -BAND, 0.5, 0.6, BUTTER), (BAND, 0.0, 0.5, 0.6, GOO), (0.0, BAND, 0.5, 0.6, ROOF), (-BAND, 0.0, 0.5, 0.6, LILAC),
    (x0 + 0.55, y0 + 0.05, 0.34, 0.42, GOO), (x2 - 0.55, y2 - 0.05, 0.34, 0.42, BUTTER),
]
for i, (x, y, r, h, col) in enumerate(GUM):
    parts.append(gumdrop(f"Gum{i}", r * 1.12, h * 1.35, col, (x, y, 0.08)))

# r02: sprinkles scattered on the frame top (tiny bright bars) so the frame reads as sugar, not soil
SPR = [PINK, BUTTER, GOO, LILAC, CREAM, ROOF]
for i in range(16):
    u = R.uniform(0, 4)
    s_, t = int(u), R.uniform(-HALF + 0.25, HALF - 0.25)
    off = R.uniform(INNER / 2 + 0.2, HALF - 0.2)
    x, y = [(t, -off), (off, t), (-t, off), (-off, -t)][s_]
    parts.append(box(f"Spr{i}", (0.38, 0.12, 0.1), (x, y, FRAME_H + 0.06), SPR[i % len(SPR)], rot=(0, 0, R.uniform(0, 180))))

overlay_finish("habitat_candy_patch_overlay", parts)
