# guide_scout (concept D): young ranch scout. Khaki shirt with a green neckerchief and badge sash, green
# shorts, tall socks, a campaign hat, a big backpack with bedroll and lantern, an open map in both hands,
# and a pink pet slime at the feet. ~6.6 studs tall. Front faces -Y.
from lib import *
from models._guide_parts import *

parts = []
KHAKI, KHAKI_LO = rgb(232, 200, 132), rgb(196, 160, 98)
GREEN, GREEN_LO = rgb(88, 176, 96), rgb(58, 132, 72)
SOCK = CREAM

for s in (-1, 1):
    parts.append(bb(f"Boot{s}", (0.95, 1.3, 0.55), (s * 0.5, -0.12, 0.28), WOOD_D, WOOD, bev=0.15))
    parts.append(bb(f"Sock{s}", (0.8, 0.85, 0.85), (s * 0.5, 0, 0.95), mix(SOCK, PLAZA, 0.4), SOCK, bev=0.1))
    parts.append(bb(f"SockBand{s}", (0.84, 0.9, 0.16), (s * 0.5, 0, 1.25), ROOF_D, ROOF, bev=0.03))
    parts.append(bb(f"Shorts{s}", (0.95, 1.0, 0.85), (s * 0.5, 0, 1.75), GREEN_LO, GREEN, bev=0.12))

TZ0, TZ1 = 2.15, 4.2
parts.append(bb("Torso", (2.0, 1.1, TZ1 - TZ0), (0, 0, (TZ0 + TZ1) / 2), KHAKI_LO, KHAKI, bev=0.18))
parts.append(bb("Belt", (2.04, 1.14, 0.25), (0, 0, TZ0 + 0.15), WOOD_D, WOOD_D, bev=0.05))
parts.append(bb("Buckle", (0.35, 0.1, 0.25), (0, -0.6, TZ0 + 0.15), BUTTER, BUTTER, bev=0.03))
# sash with badges, shoulder to hip
parts.append(bb("Sash", (0.45, 1.2, 2.5), (0.05, 0, (TZ0 + TZ1) / 2), ROOF_D, ROOF, bev=0.05, rot=(0, -38, 0)))
for k, (c, t) in enumerate(((GOO, -0.65), (BUTTER, 0.0), (LILAC, 0.65))):
    parts.append(cylinder(f"Badge{k}", 0.15, 0.08, (0.05 + t * 0.6, -0.63, (TZ0 + TZ1) / 2 + t * 0.78), c, segs=8,
                          rot=(90, 0, 0)))
for s in (-1, 1):
    parts.append(bb(f"PocketF{s}", (0.5, 0.1, 0.45), (s * 0.55, -0.58, TZ1 - 0.6), KHAKI_LO, KHAKI, bev=0.03))

# arms forward, holding an open map
for s in (-1, 1):
    parts.append(bb(f"Arm{s}", (0.8, 1.6, 0.8), (s * 1.38, -0.5, TZ1 - 0.6), KHAKI_LO, KHAKI, bev=0.15))
    parts.append(bb(f"Sleeve{s}", (0.85, 0.85, 0.85), (s * 1.38, 0, TZ1 - 0.45), KHAKI_LO, KHAKI, bev=0.15))
    parts.append(blob(f"Hand{s}", 0.36, (s * 1.25, -1.35, TZ1 - 0.55), SKIN, subdiv=2, jitter=0))
# map: two panels, slightly folded, tilted toward the viewer
for s in (-1, 1):
    parts.append(bb(f"Map{s}", (1.25, 0.06, 1.25), (s * 0.62, -1.55, TZ1 - 0.25), PLAZA, mix(CREAM, BUTTER, 0.2),
                    bev=0.0, rot=(-20, 0, s * -10)))
parts.append(tube("Route", [(-1.0, -1.66, TZ1 - 0.5), (-0.5, -1.62, TZ1 - 0.05), (0.1, -1.64, TZ1 - 0.45),
                            (0.7, -1.66, TZ1 - 0.1)], [0.05] * 4, ROOF, segs=4))
parts.append(blob("XMark", 0.12, (0.8, -1.7, TZ1 - 0.05), ROOF_D, subdiv=1, jitter=0))

# neckerchief
parts.append(bb("Kerchief", (1.45, 1.2, 0.3), (0, 0, TZ1 + 0.05), GREEN_LO, GREEN, bev=0.1))
parts.append(cone("KTip", 0.38, 0.6, (0, -0.55, TZ1 + 0.05), GREEN, segs=4, rot=(180, 0, 45)))

# head
HZ0, HZ1 = TZ1 + 0.15, TZ1 + 1.75
HC = (HZ0 + HZ1) / 2
parts.append(bb("Head", (1.7, 1.5, HZ1 - HZ0), (0, 0, HC), mix(SKIN, WOOD, 0.15), SKIN, bev=0.35))
parts += blocky_face("F", 0, -0.76, HC - 0.05)
parts.append(bb("Hair", (1.78, 1.58, 0.35), (0, 0.06, HZ1 - 0.2), ROOF_D, mix(ROOF, BUTTER, 0.3), bev=0.1))

# campaign hat: flat wide brim, pinched crown
HAT = HZ1 - 0.05
parts.append(gr(cylinder("Brim", 1.85, 0.14, (0, 0.05, HAT), KHAKI, segs=18), KHAKI_LO, KHAKI))
parts.append(gr(cylinder("Crown", 0.95, 1.0, (0, 0.05, HAT + 0.1), KHAKI, segs=4, r_top=0.35, rot=(0, 0, 45)),
                KHAKI_LO, mix(KHAKI, CREAM, 0.3)))
parts.append(gr(cylinder("HBand", 0.97, 0.22, (0, 0.05, HAT + 0.12), WOOD_D, segs=4, r_top=0.9, rot=(0, 0, 45)),
                WOOD_D, WOOD))

# backpack with bedroll and lantern
parts.append(bb("Pack", (1.7, 1.0, 2.1), (0, 1.0, (TZ0 + TZ1) / 2 + 0.1), GREEN_LO, GREEN, bev=0.2))
parts.append(bb("PackFlap", (1.75, 1.05, 0.6), (0, 1.0, TZ1 + 0.05), mix(GREEN_LO, INK, 0.2), GREEN_LO, bev=0.15))
parts.append(gr(cylinder("Bedroll", 0.42, 2.3, (-1.15, 1.05, TZ1 + 0.65), ROOF, segs=10, rot=(0, 90, 0)),
                ROOF_D, ROOF))
parts.append(gr(cylinder("Lantern", 0.3, 0.6, (1.0, 1.55, TZ0 + 0.3), BUTTER, segs=8), WOOD_D, BUTTER))
parts.append(cylinder("LanternCap", 0.33, 0.15, (1.0, 1.55, TZ0 + 0.9), WOOD_D, segs=8))

# pink pet slime at the feet, looking up at the player
parts += pet_slime("Pet", (1.75, -1.15, 0), r=0.85, col=PINK, hi=rgb(255, 214, 228), look=(-0.3, 0.3))

finish_smooth("guide_scout", parts)
