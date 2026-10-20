# guide_elder_slime (concept B): the Guide is a big, wise old slime. Teal goo body, bushy cream
# moustache + eyebrows, round spectacles, a ranger hat, and a walking staff topped with a goo orb.
# ~7.5 studs tall with the hat. Front faces -Y.
from lib import *
from models._guide_parts import *

parts = []
BODY, BODY_LO, BODY_HI = rgb(96, 206, 186), rgb(52, 150, 140), rgb(170, 240, 222)
R, H = 2.3, 3.7
parts.append(gumdrop("Body", R, H, (0, 0, 0), BODY_LO, BODY_HI, segs=28, rings=16))
parts.append(smooth(blob("Shine", 0.45, (-1.05, -gum_r(R, H, 2.9) * 0.62, 2.9), rgb(230, 255, 246), subdiv=2,
                         squash=(1, 0.45, 0.65), jitter=0, rot=(0, 0, 30))))

# face (front surface at height z sits at y = -gum_r)
EZ = 2.35
fy = -gum_r(R, H, EZ) + 0.12
for s in (-1, 1):
    parts += eye(f"E{s}", s * 0.62, fy - 0.02, EZ, r=0.3, tall=1.2)
    # spectacles: dark rim disc + pale lens disc in front
    parts.append(cylinder(f"Rim{s}", 0.5, 0.08, (s * 0.62, fy - 0.12, EZ), INK, segs=16, rot=(90, 0, 0)))
    parts.append(cylinder(f"Lens{s}", 0.42, 0.06, (s * 0.62, fy - 0.15, EZ), rgb(220, 244, 255), segs=16,
                          rot=(90, 0, 0)))
    parts += eye(f"G{s}", s * 0.62, fy - 0.22, EZ, r=0.26, tall=1.2)
    # bushy brows
    for k in range(3):
        parts.append(blob(f"Brow{s}{k}", 0.2, (s * (0.35 + k * 0.22), fy - 0.05, EZ + 0.62 + 0.06 * (1 - k)),
                          CREAM, subdiv=1, squash=(1.2, 0.8, 0.8), jitter=0.05, seed=k + 3 * s))
parts.append(box("Bridge", (0.3, 0.08, 0.08), (0, fy - 0.16, EZ + 0.05), INK))
# cheeks
parts += cheeks("Ch", 1.1, -gum_r(R, H, EZ - 0.55) + 0.12, EZ - 0.55, r=0.24)
# big cream moustache: two drooping lobes of blobs
MZ = EZ - 0.55
my = -gum_r(R, H, MZ) + 0.05
for s in (-1, 1):
    for k, (dx, dz, rr) in enumerate(((0.18, 0.05, 0.3), (0.5, -0.02, 0.3), (0.82, -0.15, 0.26), (1.05, -0.35, 0.2))):
        parts.append(smooth(blob(f"Mou{s}{k}", rr, (s * dx, my - 0.05 + 0.08 * k, MZ + dz), CREAM, subdiv=2,
                                 squash=(1.15, 0.8, 0.85), jitter=0.04, seed=10 + k)))
parts.append(gr(blob("Nose", 0.24, (0, my - 0.22, MZ + 0.3), BODY, subdiv=2, squash=(1, 0.9, 0.9), jitter=0),
                BODY_LO, BODY_HI))

# ranger hat on the crown, tipped
HZ = H - 0.35
parts.append(gr(cylinder("Brim", 1.9, 0.18, (0, 0.1, HZ), WOOD, segs=18, r_top=1.8, rot=(-8, 0, 6)),
                WOOD_D, WOOD))
parts.append(gr(cylinder("Crown", 1.15, 1.05, (0, 0.12, HZ + 0.1), WOOD, segs=14, r_top=0.7, rot=(-8, 0, 6)),
                WOOD_D, mix(WOOD, CREAM, 0.2)))
parts.append(gr(cylinder("Band", 1.13, 0.3, (0, 0.12, HZ + 0.15), GOO, segs=14, r_top=1.05, rot=(-8, 0, 6)),
                mix(GOO, INK, 0.2), GOO))
parts.append(blob("Feather", 0.25, (0.95, 0.3, HZ + 0.65), ROOF, subdiv=1, squash=(0.4, 0.5, 2.0), jitter=0,
                  rot=(0, 25, 0)))

# walking staff on the right with a goo orb
SX, SY = 2.55, -0.6
parts.append(gr(cylinder("Staff", 0.16, 5.0, (SX, SY, 0), WOOD, segs=8, r_top=0.13), WOOD_D, WOOD))
top = (SX, SY, 5.25)
parts.append(gr(cylinder("Prong", 0.28, 0.5, (top[0], top[1], top[2] - 0.45), WOOD, segs=8, r_top=0.42),
                WOOD_D, WOOD))
parts.append(smooth(gr(blob("Orb", 0.5, (top[0], top[1], top[2] + 0.35), GOO, subdiv=3, jitter=0),
                       GOO, GOO_HI)))
# a stubby goo hand holding the staff
parts.append(smooth(gr(blob("Hand", 0.42, (SX + 0.05, SY + 0.2, 2.1), BODY, subdiv=2, squash=(1, 0.9, 1.1),
                            jitter=0), BODY_LO, BODY_HI)))

finish_smooth("guide_elder_slime", parts)
