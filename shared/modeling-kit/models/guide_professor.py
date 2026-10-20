# guide_professor (concept C): slime scientist. Long cream lab coat over a lilac shirt and red bow tie,
# wild white hair with goggles pushed up, a glass goo tank on the back with a hose, clipboard in the
# left hand, right hand raised with a pointing finger. ~7 studs tall. Front faces -Y.
from lib import *
from models._guide_parts import *

parts = []
COAT, COAT_LO = CREAM, mix(CREAM, PLAZA, 0.6)
PANTS, PANTS_LO = rgb(92, 90, 120), rgb(64, 62, 90)
SHIRT = LILAC
HAIR, HAIR_LO = rgb(250, 250, 250), rgb(206, 212, 226)

for s in (-1, 1):
    parts.append(bb(f"Shoe{s}", (0.9, 1.25, 0.5), (s * 0.48, -0.12, 0.25), INK, mix(INK, WOOD_D, 0.5), bev=0.15))
    parts.append(bb(f"Leg{s}", (0.82, 0.9, 1.7), (s * 0.48, 0, 1.35), PANTS_LO, PANTS, bev=0.12))

TZ0, TZ1 = 2.2, 4.3
# shirt core + coat (long tails below the waist, open at the front)
parts.append(bb("Shirt", (1.7, 1.0, TZ1 - TZ0), (0, 0, (TZ0 + TZ1) / 2), mix(SHIRT, INK, 0.2), SHIRT, bev=0.15))
for s in (-1, 1):
    parts.append(bb(f"CoatSide{s}", (0.75, 1.2, TZ1 - TZ0 + 0.1), (s * 0.7, 0, (TZ0 + TZ1) / 2), COAT_LO, COAT, bev=0.15))
    parts.append(bb(f"Tail{s}", (0.85, 1.25, 1.35), (s * 0.62, 0.02, TZ0 - 0.55), COAT_LO, COAT, bev=0.12,
                    rot=(0, s * 6, 0)))
    parts.append(bb(f"Lapel{s}", (0.32, 0.12, 0.95), (s * 0.4, -0.6, TZ1 - 0.5), COAT_LO, COAT, bev=0.04,
                    rot=(0, s * -14, 0)))
parts.append(bb("CoatBack", (1.9, 0.35, TZ1 - TZ0 + 1.4), (0, 0.45, (TZ0 + TZ1) / 2 - 0.65), COAT_LO, COAT, bev=0.12))
parts.append(bb("Pocket", (0.55, 0.1, 0.45), (-0.72, -0.62, TZ1 - 0.75), COAT_LO, COAT, bev=0.03))
for k, c in enumerate((ROOF, GOO, BUTTER)):
    parts.append(box(f"Pen{k}", (0.09, 0.09, 0.45), (-0.88 + k * 0.15, -0.64, TZ1 - 0.45), c))
# bow tie
for s in (-1, 1):
    parts.append(cone(f"Bow{s}", 0.26, 0.38, (s * 0.02, -0.55, TZ1 - 0.15), ROOF, segs=4, rot=(0, s * -90, 0)))
parts.append(blob("BowK", 0.12, (0, -0.58, TZ1 - 0.15), ROOF_D, subdiv=1, jitter=0))

# arms: left holding a clipboard in front, right raised pointing up
la, lh = limb("ArmL", (-1.3, 0, TZ1 - 0.3), -25, 1.7, 0.75, 0.8, COAT_LO, COAT)
parts.append(la)
parts.append(blob("HandL", 0.38, (lh[0], lh[1] - 0.2, lh[2]), SKIN, subdiv=2, jitter=0))
parts.append(bb("Board", (1.1, 0.12, 1.4), (lh[0] + 0.15, lh[1] - 0.55, lh[2] + 0.35), WOOD_D, WOOD, bev=0.04,
                rot=(12, 0, -8)))
parts.append(bb("Paper", (0.9, 0.06, 1.1), (lh[0] + 0.15, lh[1] - 0.63, lh[2] + 0.3), WHITE, WHITE, bev=0.0,
                rot=(12, 0, -8)))
parts.append(bb("Clip", (0.4, 0.14, 0.14), (lh[0] + 0.21, lh[1] - 0.7, lh[2] + 0.98), METAL, METAL, bev=0.03,
                rot=(12, 0, -8)))
ra, rh = limb("ArmR", (1.2, 0, TZ1 - 0.45), -160, 1.7, 0.75, 0.8, COAT_LO, COAT)
parts.append(ra)
parts.append(blob("HandR", 0.38, rh, SKIN, subdiv=2, jitter=0))
parts.append(box("Point", (0.16, 0.16, 0.55), (rh[0], rh[1], rh[2] + 0.45), SKIN))

# head
HZ0, HZ1 = TZ1 + 0.1, TZ1 + 1.75
HC = (HZ0 + HZ1) / 2
parts.append(bb("Head", (1.65, 1.5, HZ1 - HZ0), (0, 0, HC), mix(SKIN, WOOD, 0.15), SKIN, bev=0.33))
parts += blocky_face("F", 0, -0.76, HC - 0.08)
# round glasses
for s in (-1, 1):
    parts.append(cylinder(f"Rim{s}", 0.3, 0.06, (s * 0.36, -0.82, HC + 0.04), INK, segs=12, rot=(90, 0, 0)))
    parts.append(cylinder(f"Lens{s}", 0.25, 0.05, (s * 0.36, -0.85, HC + 0.04), rgb(220, 244, 255), segs=12,
                          rot=(90, 0, 0)))
    parts += eye(f"G{s}", s * 0.36, -0.9, HC + 0.04, r=0.15)
# wild hair: puffs around the sides/back and a tall tuft
for k, (x, y, z, r) in enumerate(((-0.95, 0.1, HC + 0.3, 0.5), (0.95, 0.1, HC + 0.3, 0.5), (-0.7, 0.55, HZ1, 0.55),
                                  (0.7, 0.55, HZ1, 0.55), (0, 0.65, HZ1 + 0.1, 0.6), (-0.4, 0.1, HZ1 + 0.25, 0.5),
                                  (0.45, 0.0, HZ1 + 0.3, 0.48), (0.05, 0.3, HZ1 + 0.6, 0.45))):
    parts.append(gr(blob(f"Hair{k}", r, (x, y, z), HAIR, subdiv=2, jitter=0.12, seed=k), HAIR_LO, HAIR))
# goggles pushed up on the hair
parts.append(bb("GogStrap", (1.85, 1.6, 0.2), (0, 0.05, HZ1 - 0.05), INK, mix(INK, WOOD_D, 0.4), bev=0.08))
for s in (-1, 1):
    parts.append(cylinder(f"Gog{s}", 0.3, 0.3, (s * 0.38, -0.7, HZ1 + 0.05), METAL, segs=12, rot=(90, 0, 0)))
    parts.append(cylinder(f"GogL{s}", 0.22, 0.1, (s * 0.38, -0.98, HZ1 + 0.05), GOO, segs=12, rot=(90, 0, 0)))

# goo tank backpack + hose
parts.append(bb("Harness", (1.4, 0.3, 1.9), (0, 0.65, (TZ0 + TZ1) / 2 + 0.1), WOOD_D, WOOD, bev=0.08))
parts.append(gr(cylinder("TankBase", 0.7, 0.3, (0, 1.2, TZ0 - 0.1), METAL, segs=14), mix(METAL, INK, 0.3), METAL))
parts.append(smooth(gr(cylinder("Tank", 0.6, 2.0, (0, 1.2, TZ0 + 0.2), GOO, segs=16), GOO, GOO_HI)))
parts.append(gr(cylinder("TankCap", 0.7, 0.35, (0, 1.2, TZ0 + 2.2), METAL, segs=14, r_top=0.45),
                mix(METAL, INK, 0.3), METAL))
parts.append(tube("Hose", [(0.5, 1.3, TZ0 + 2.4), (1.1, 1.0, TZ0 + 2.6), (1.5, 0.4, TZ0 + 1.6), (1.4, 0.0, TZ0 + 0.6)],
                  [0.14, 0.14, 0.14, 0.14], INK, segs=6))
for k in range(3):
    parts.append(smooth(blob(f"Bub{k}", 0.12 + 0.03 * k, (0.25 - 0.2 * k, 0.6, TZ0 + 0.6 + 0.55 * k), GOO_HI,
                             subdiv=2, jitter=0)))

finish_smooth("guide_professor", parts)
