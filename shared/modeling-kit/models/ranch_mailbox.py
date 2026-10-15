# ranch_mailbox: rural round-top mailbox on a wooden post with a red flag (Slime Ranch).
# Box + half-cylinder roof, door on -Y, flag on +X, post + foot. Small prop, target < 500 tris.
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
BUTTER = PALETTE["ranch_butter"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.15), mix(METAL, CREAM, 0.25)
parts = []

parts.append(box("Foot", (1.2, 1.2, 0.35), (0, 0, 0.175), WOOD_LO)); gradient(parts[-1], WOOD_D, WOOD_LO)
parts.append(box("Post", (0.6, 0.6, 3.6), (0, 0, 1.8), WOOD)); bevel(parts[-1], 0.06)
gradient(parts[-1], WOOD_LO, WOOD)
parts.append(box("Shelf", (1.3, 2.6, 0.2), (0, 0, 3.7), WOOD)); gradient(parts[-1], WOOD_LO, WOOD)
BZ, W, L = 3.8, 1.2, 2.4
parts.append(box("Body", (W, L, 0.7), (0, 0, BZ + 0.35), METAL)); gradient(parts[-1], METAL_LO, METAL)
parts.append(cylinder("Dome", W / 2, L, (0, L / 2, BZ + 0.7), METAL, segs=10, rot=(90, 0, 0)))
gradient(parts[-1], METAL, METAL_HI)
# door at -Y (faces the front view): red face slab pulled proud
parts.append(box("Door", (W * 0.9, 0.12, 0.65), (0, -(L / 2 + 0.06), BZ + 0.38), ROOF))
parts.append(cylinder("DoorTop", W * 0.45, 0.12, (0, -L / 2, BZ + 0.7), ROOF, segs=10, rot=(90, 0, 0)))
for p in parts[-2:]:
    gradient(p, mix(ROOF_D, ROOF, .5), ROOF)
parts.append(box("Latch", (0.2, 0.1, 0.12), (0, -(L / 2 + 0.17), BZ + 0.85), BUTTER))
# flag on +X side
parts.append(box("FlagArm", (0.1, 0.16, 1.3), (W / 2 + 0.08, 0.5, BZ + 0.9), METAL_LO))
parts.append(box("Flag", (0.1, 0.6, 0.45), (W / 2 + 0.08, 0.75, BZ + 1.35), ROOF))
gradient(parts[-1], mix(ROOF_D, ROOF, .5), ROOF)
parts.append(box("Pivot", (0.16, 0.22, 0.22), (W / 2 + 0.05, 0.5, BZ + 0.3), METAL))
finish("ranch_mailbox", parts)
