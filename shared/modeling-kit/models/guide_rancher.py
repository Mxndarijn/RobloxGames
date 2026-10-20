# guide_rancher (concept A): friendly ranch hand, blocky Roblox proportions. Denim overalls over a red
# shirt, butter neckerchief, straw hat with a little goo slime riding on the crown, right arm waving.
# ~6.8 studs tall (a bit taller than a player). Front faces -Y.
from lib import *
from models._guide_parts import *

parts = []
SHIRT, SHIRT_LO = ROOF, ROOF_D
BOOT, BOOT_LO = WOOD_D, mix(WOOD_D, INK, 0.35)

# legs + boots
for s in (-1, 1):
    parts.append(bb(f"Boot{s}", (0.95, 1.25, 0.6), (s * 0.5, -0.12, 0.3), BOOT_LO, BOOT, bev=0.15))
    parts.append(bb(f"Leg{s}", (0.88, 0.95, 1.7), (s * 0.5, 0, 1.45), DENIM_D, DENIM, bev=0.12))
    parts.append(bb(f"Cuff{s}", (0.96, 1.02, 0.25), (s * 0.5, 0, 0.72), DENIM_D, mix(DENIM, CREAM, 0.3), bev=0.06))

# torso: shirt + overall bib + straps + pocket
TZ0, TZ1 = 2.25, 4.35
parts.append(bb("Torso", (2.1, 1.15, TZ1 - TZ0), (0, 0, (TZ0 + TZ1) / 2), SHIRT_LO, SHIRT, bev=0.18))
parts.append(bb("Hips", (2.12, 1.18, 0.75), (0, 0, TZ0 + 0.3), DENIM_D, DENIM, bev=0.15))
parts.append(bb("Bib", (1.3, 0.2, 1.1), (0, -0.56, TZ0 + 1.05), DENIM_D, DENIM, bev=0.06))
parts.append(bb("Pocket", (0.6, 0.12, 0.42), (0, -0.67, TZ0 + 1.05), DENIM_D, mix(DENIM, CREAM, 0.15), bev=0.03))
for s in (-1, 1):
    parts.append(bb(f"Strap{s}", (0.3, 1.24, 0.12), (s * 0.55, 0, TZ1 - 0.02), DENIM_D, DENIM, bev=0.03))
    parts.append(bb(f"StrapF{s}", (0.3, 0.14, 0.9), (s * 0.55, -0.6, TZ1 - 0.45), DENIM_D, DENIM, bev=0.03))
    parts.append(blob(f"Btn{s}", 0.1, (s * 0.55, -0.7, TZ0 + 1.55), BUTTER, subdiv=1, squash=(1, 0.5, 1), jitter=0))

# arms: left relaxed, right raised in a wave
la, lh = limb("ArmL", (-1.4, 0, TZ1 - 0.25), 8, 1.75, 0.82, 0.85, SHIRT_LO, SHIRT)
parts.append(la)
parts.append(blob("HandL", 0.42, lh, SKIN, subdiv=2, squash=(1, 1, 0.95), jitter=0))
ra, rh = limb("ArmR", (1.25, 0, TZ1 - 0.45), -150, 1.75, 0.82, 0.85, SHIRT_LO, SHIRT)
parts.append(ra)
parts.append(blob("HandR", 0.44, rh, SKIN, subdiv=2, squash=(1, 0.8, 1.1), jitter=0))
for k, dx in enumerate((-0.22, 0, 0.22)):
    parts.append(box(f"Finger{k}", (0.15, 0.2, 0.42), (rh[0] + dx, rh[1], rh[2] + 0.42), SKIN))

# neck + neckerchief
parts.append(bb("Neck", (0.7, 0.7, 0.3), (0, 0, TZ1 + 0.1), SKIN, SKIN, bev=0.08))
parts.append(bb("Kerchief", (1.5, 1.25, 0.32), (0, 0, TZ1 + 0.05), mix(BUTTER, WOOD, 0.3), BUTTER, bev=0.1))
parts.append(cone("KerchiefTip", 0.42, 0.65, (0, -0.58, TZ1 + 0.05), BUTTER, segs=4, rot=(180, 0, 45)))

# head: rounded block with face
HZ0, HZ1 = TZ1 + 0.2, TZ1 + 1.85
HC = (HZ0 + HZ1) / 2
parts.append(bb("Head", (1.75, 1.55, HZ1 - HZ0), (0, 0, HC), mix(SKIN, WOOD, 0.15), SKIN, bev=0.35))
parts += blocky_face("F", 0, -0.78, HC - 0.05)
for s in (-1, 1):
    parts.append(bb(f"Brow{s}", (0.36, 0.1, 0.1), (s * 0.36, -0.8, HC + 0.48), WOOD_D, WOOD_D, bev=0.03,
                    rot=(0, s * -8, 0)))
# hair tuft under the hat
parts.append(bb("Hair", (1.82, 1.6, 0.3), (0, 0.05, HZ1 - 0.15), WOOD_D, WOOD, bev=0.1))

# straw hat, tipped back a little
HAT = HZ1 - 0.05
parts.append(gr(cylinder("Brim", 1.75, 0.18, (0, 0.05, HAT), BUTTER, segs=16, r_top=1.6, rot=(-6, 0, 0)),
                mix(BUTTER, WOOD, 0.3), BUTTER))
parts.append(gr(cylinder("Crown", 1.0, 0.95, (0, 0.1, HAT + 0.1), BUTTER, segs=14, r_top=0.85, rot=(-6, 0, 0)),
                mix(BUTTER, WOOD, 0.2), mix(BUTTER, CREAM, 0.3)))
parts.append(gr(cylinder("HatBand", 1.02, 0.28, (0, 0.1, HAT + 0.14), ROOF, segs=14, r_top=0.98, rot=(-6, 0, 0)),
                ROOF_D, ROOF))

# little goo slime riding on top of the hat
parts += pet_slime("Pet", (0.05, 0.2, HAT + 1.0), r=0.62, look=(0.3, 0))

finish_smooth("guide_rancher", parts)
