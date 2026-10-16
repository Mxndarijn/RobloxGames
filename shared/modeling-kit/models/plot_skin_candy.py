# plot_skin_candy: Candy Patch plot decor (replaces the plot's mailbox slot in game).
# Candy-cane lamp post: striped red/cream cane with a hooked top, a swirl lollipop lamp hanging from the hook, gumdrop base.
# ~4.2 x 7.4 x 3.0 studs, origin bottom-centre. Target < ~1000 tris.
import math
from lib import *
from models._phoenix_pad import lathe

CREAM, ROOF, ROOF_D = PALETTE["ranch_cream"], PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
PINK, LILAC, BUTTER = PALETTE["ranch_pink"], PALETTE["ranch_lilac"], PALETTE["ranch_butter"]
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
PINK_D = mix(PINK, ROOF_D, 0.35)
parts = []

# gumdrop base (squat dome, ~2/3 above the soil)
BASE = [(0, 0), (1.55, 0), (1.7, 0.3), (1.45, 0.8), (0.9, 1.1), (0, 1.2)]
parts.append(lathe("Gumdrop", BASE, segs=12, color_fn=lambda i, k, z: shade(mix(PINK_D, PINK, min(1, z / 1.1)), 1.0 + 0.04 * ((k % 3) - 1))))

# cane: straight shaft with red/cream bands, then a half-ring hook towards +X
SEG = 8
H0, H1 = 1.0, 5.2
STEP = 0.7
n = int((H1 - H0) / STEP)
for i in range(n):
    c = ROOF if i % 2 == 0 else CREAM
    parts.append(cylinder(f"Band{i}", 0.42, STEP + 0.02, (0, 0, H0 + i * STEP), c, segs=SEG))
    gradient(parts[-1], shade(c, 0.88), c)
# hook: arc of short segments
arc = []
for j in range(7):
    t = math.pi * j / 6
    arc.append((1.05 - 1.05 * math.cos(t) - 0.0, 0, H1 + 1.05 * math.sin(t)))
arc = [(x - 0.0, y, z) for x, y, z in arc]
pts = [(0, 0, H1 - 0.05)] + arc[1:]
parts.append(tube("Hook", pts, [0.4] * len(pts), ROOF, segs=8))
gradient(parts[-1], shade(ROOF, 0.9), mix(ROOF, CREAM, 0.35))
# cream stripe cap ring
parts.append(cylinder("Cap", 0.55, 0.28, (0, 0, H1 - 0.05), CREAM, segs=SEG))

# swirl lollipop lamp hanging from the hook tip (disc facing -Y)
LX, LZ = 2.1, H1 + 0.15
parts.append(cylinder("Chain", 0.13, 0.9, (LX, 0, LZ - 0.7), PALETTE["ranch_metal"], segs=6))
parts.append(cylinder("Ring", 0.3, 0.16, (LX, 0, LZ - 0.12), PALETTE["ranch_metal"], segs=8))
SW = [(0, -0.2), (0.4, -0.22), (1.15, -0.16), (1.2, 0.0), (1.15, 0.16), (0.4, 0.22), (0, 0.2)]


def swirl(i, k, z):
    return [PINK, CREAM, LILAC, CREAM][(k + i * 2) // 2 % 4] if i > 0 else PINK


lol = lathe("Lolly", SW, segs=16, color_fn=lambda i, k, z: [PINK, CREAM, LILAC, BUTTER][((k + i * 2) // 2) % 4])
lol.rotation_euler = (math.radians(90), 0, 0)
lol.location = (LX, 0, LZ - 1.85)
lol.data.transform(lol.matrix_basis)
lol.rotation_euler = (0, 0, 0)
lol.location = (0, 0, 0)
parts.append(lol)
# lollipop stick tip + sprinkle bows on the shaft
for i, a in enumerate((35, 150, 265)):
    parts.append(blob(f"Drop{i}", 0.42, (1.9 * math.cos(math.radians(a)), 1.9 * math.sin(math.radians(a)), 0.35), [BUTTER, LILAC, CREAM][i], seed=i, subdiv=1, squash=(1, 1, 0.8), jitter=0.05))
finish("plot_skin_candy", parts)
