# obby_finish_b (option B): a winner's PODIUM with a TROPHY SLIME at the back of the finish slab, and flag poles at
# the four corners (steal-a-slime obby). A two-step violet podium with a checkered band and a gold "1" carries a big
# gold cup with a happy green slime sitting in it, goo running over the rim. Candy-striped poles stand on the slab's
# corners: checkered flags on the front two, gold pennants on the back two, and bunting strung between them along
# both lane edges and across the back. Slab coordinates (models/_obby_finish_parts).
import math
from mathutils import Matrix, Vector
from lib import *
from models._obby_finish_parts import *

PY = 2.6  # podium centre y (back half of the slab)
parts = []

# -- the podium: two tiers, violet with light tops, a checkered band on the front of the base, a gold "1"
parts.append(bb("PodBase", (9.4, 4.6, 1.3), (0, PY, 0.65), VIOLET_LO, VIOLET, bev=0.18))
parts.append(bb("PodTop", (6.2, 3.6, 1.3), (0, PY + 0.2, 1.95), VIOLET, VIOLET_HI, bev=0.18))
parts.append(checker("PodBand", 9.0, 0.7, 12, 1, thick=0.1, pos=(0, PY - 2.33, 0.65)))
one = [(-0.25, 0), (0.45, 0), (0.45, 1.1), (0.05, 1.1), (-0.5, 0.75), (-0.5, 0.45), (-0.25, 0.55)]
parts.append(slab("One", one, 0.16, GOLD, pos=(0, PY + 0.2 - 1.82, 1.38), back=GOLD_LO))

# -- the trophy, built at unit scale on the podium top, then scaled up
T0 = len(parts)
B = Vector((0, PY + 0.2, 2.6))


def at(x, y, z):
    return (B.x + x, B.y + y, B.z + z)


foot = [(0, 0), (1.55, 0), (1.6, 0.22), (1.3, 0.5), (0.95, 0.62), (0, 0.62)]
parts.append(lathe("Foot", foot, [GOLD_LO, GOLD_LO, GOLD, GOLD, GOLD_HI], segs=20, pos=at(0, 0, 0)))
stem = [(0, 0.6), (0.48, 0.6), (0.4, 1.0), (0.78, 1.3), (0.78, 1.55), (0.38, 1.85), (0.5, 2.3), (0, 2.3)]
parts.append(lathe("Stem", stem, [GOLD_LO, GOLD, GOLD_HI, GOLD, GOLD_LO, GOLD, GOLD], segs=16, pos=at(0, 0, 0)))
# bowl: outer wall up to a rolled lip, then the inside wall back down (a darker gold so the opening reads)
bowl = [(0.0, 2.2), (0.9, 2.25), (1.7, 2.7), (2.25, 3.5), (2.5, 4.4), (2.68, 5.05), (2.62, 5.28), (2.36, 5.22),
        (2.15, 4.5), (1.5, 3.6), (0.0, 3.4)]
bcol = [GOLD_LO, GOLD_LO, GOLD, GOLD_HI, GOLD, GOLD_LO, GOLD_LO, GOLD_LO, GOLD_LO, GOLD_LO]  # shine on the belly, a darker lip so the slime reads apart
parts.append(smooth(lathe("Bowl", bowl, bcol, segs=22, pos=at(0, 0, 0))))
for s in (-1, 1):
    pts = [(s * 2.3, 0, 4.7), (s * 3.25, 0, 4.85), (s * 3.75, 0, 4.2), (s * 3.45, 0, 3.35), (s * 2.6, 0, 2.95),
           (s * 1.95, 0, 2.9)]
    parts.append(smooth(tube(f"Handle{s}", [at(*p) for p in pts], [0.34, 0.38, 0.4, 0.38, 0.34, 0.3], GOLD, segs=8,
                             twist_free=True)))
    gradient(parts[-1], GOLD_LO, GOLD_HI)
# the slime sitting in the cup, goo running over the rim
balls = [Ball(at(0, 0, 5.3), (2.62, 2.62, 0.62)), Ball(at(0, 0, 6.15), (2.15, 2.05, 1.55))]  # fills the cup, bulges over the rim
for a, ln in ((-0.25, 1.2), (0.55, 0.6), (3.45, 0.95), (2.55, 0.55)):  # on the sides, never under the face
    rim = Vector((math.cos(a) * 2.55, math.sin(a) * 2.55, 5.0))
    balls.append(Ball(at(rim.x, rim.y, 5.05), 0.42))
    balls += drip_balls(at(rim.x * 1.04, rim.y * 1.04, 4.85), ln, 0.36)
goo = metaball_mesh("CupSlime", balls, resolution=0.16, tris=900)
parts.append(paint_goo(goo, goo_color(GOO_DEEP, GOO, GOO_HI, z0=B.z + 4.0, z1=B.z + 7.6)))
parts += eyes("Eye", at(0, -1.72, 6.6), (0, -1, 0), 0.74, r=0.5, pupil=0.3)
parts.append(tube("Smile", [at(-0.5, -1.98, 6.0), at(-0.25, -2.1, 5.82), at(0, -2.13, 5.77), at(0.25, -2.1, 5.82),
                            at(0.5, -1.98, 6.0)], [0.12, 0.15, 0.16, 0.15, 0.12], INK, segs=6))
S = 1.8
M = Matrix.Translation(B) @ Matrix.Scale(S, 4) @ Matrix.Translation(-B)
for o in parts[T0:]:
    o.data.transform(M)

# -- corner poles: candy stripes, gold ball tops; checkered flags in front, gold pennants at the back
PX, PYC, PH = 11.3, 5.3, 12.5
tops = {}
for sx in (-1, 1):
    for sy in (-1, 1):
        base = (sx * PX, sy * PYC, 0)
        k = f"{'L' if sx < 0 else 'R'}{'F' if sy < 0 else 'B'}"
        parts.append(disc_ := bb(f"PoleFoot{k}", (1.1, 1.1, 0.4), (base[0], base[1], 0.2), VIOLET_LO, VIOLET, bev=0.1))
        parts.append(pole(f"Pole{k}", base, PH, 0.26, WHITE, WHITE, stripes=6, c2=VIOLET, segs=8))
        parts.append(ball(f"Knob{k}", 0.5, (base[0], base[1], PH + 0.35), GOLD_LO, GOLD_HI))
        tops[k] = Vector((base[0], base[1], PH - 0.6))
        if sy < 0:  # checkered flag, waving outward along x
            fw, fh = 4.4, 3.0
            parts.append(checker(f"Flag{k}", fw, fh, 4, 3, thick=0.14, sub=3,
                                 wave=lambda u, v: 0.35 * math.sin(u * math.pi * 2.0) * u,
                                 pos=(base[0] + sx * (fw / 2 + 0.2), base[1], PH - 0.4 - fh / 2),
                                 rot=(0, 0, 0 if sx > 0 else 180)))
        else:
            parts.append(pennant(f"Pen{k}", (base[0], base[1], PH - 0.3), 4.2, 2.8, GOLD, down=False,
                                 rot=(0, 0, 0 if sx > 0 else 180)))

# -- bunting along both lane edges (front pole to back pole) and across the back
COLS = [CYAN, GOLD, VIOLET, LIME, WHITE]


def bunting(name, a, b, sag, n):
    out = [rope(name + "Rope", catenary(a, b, sag, 14), 0.07, WHITE)]
    pts = catenary(a, b, sag, n + 1)[1:-1]
    d = (Vector(b) - Vector(a)).normalized()
    yaw = math.degrees(math.atan2(d.y, d.x))
    for i, p in enumerate(pts):
        out.append(pennant(f"{name}{i}", tuple(p), 1.3, 1.5, COLS[i % len(COLS)], rot=(0, 0, yaw), depth=0.12))
    return out


for sx in (-1, 1):
    k = "L" if sx < 0 else "R"
    parts += bunting(f"Side{k}", tops[k + "F"], tops[k + "B"], 1.4, 6)
parts += bunting("Back", tops["LB"], tops["RB"], 1.8, 12)

report("obby_finish_b", parts)
finish_smooth("obby_finish_b", parts)
