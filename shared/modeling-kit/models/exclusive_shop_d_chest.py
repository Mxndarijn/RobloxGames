# Exclusive shop concept D, "Treasure Chest": the shop IS a giant open treasure chest. The chest rim is the
# counter (top z ~4.1), the open lid stands behind as the sign wall, gold and gems overflow onto the ground,
# exclusive pet clouds sit on the treasure. Front faces -Y.
import math
import random
import bmesh
from mathutils import Matrix
from lib import *
from models._phoenix_ranch import *
from models._exclusive_parts import *

parts = []
R = random.Random(3)
W, D, H = 12.0, 7.0, 4.1
WOODP = rgb(132, 78, 190)        # purple-painted wood
WOODP_LO = rgb(88, 48, 140)


def half_drum(name, w, r, pos, lo, hi, segs=12, hinge=None, angle=0.0):
    """Half cylinder along X (flat face down at z=0, dome up), optionally rotated about a hinge line along X."""
    bm = bmesh.new()
    pts = [(-math.cos(i * math.pi / segs) * r, math.sin(i * math.pi / segs) * r) for i in range(segs + 1)]
    L = [bm.verts.new((-w / 2, y, z)) for y, z in pts]
    Rr = [bm.verts.new((w / 2, y, z)) for y, z in pts]
    bm.faces.new(L)
    bm.faces.new(list(reversed(Rr)))
    for i in range(segs):
        bm.faces.new((L[i], L[i + 1], Rr[i + 1], Rr[i]))
    bm.faces.new((L[-1], L[0], Rr[0], Rr[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    m = Matrix.Translation(pos)
    if hinge is not None:
        hy, hz = hinge
        m = Matrix.Translation((0, hy, hz)) @ Matrix.Rotation(math.radians(angle), 4, "X") @ Matrix.Translation((0, -hy, -hz)) @ m
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    o = obj_from_bm(name, bm, hi)
    gradient(o, lo, hi)
    return o


def rot_box(name, size, pos, lo, hi, hinge, angle, bev=0.1):
    o = bbox(name, size, pos, lo, hi, bev=bev)
    hy, hz = hinge
    m = Matrix.Translation((0, hy, hz)) @ Matrix.Rotation(math.radians(angle), 4, "X") @ Matrix.Translation((0, -hy, -hz))
    o.data.transform(m)
    gradient(o, lo, hi)
    return o


# chest body: purple planks, gold corner caps and bands
parts.append(bbox("Body", (W, D, H), (0, 0, H / 2), WOODP_LO, WOODP, bev=0.2))
for k in range(4):
    z = 0.5 + k * 0.95
    parts.append(bbox(f"Plank{k}", (W + 0.1, D + 0.1, 0.12), (0, 0, z + 0.45), shade(WOODP_LO, 0.9), WOODP_LO, bev=0))
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(bbox(f"Corner{sx}{sy}", (1.0, 1.0, H + 0.2), (sx * (W / 2 - 0.35), sy * (D / 2 - 0.35), H / 2), GOLD_LO, GOLD, bev=0.15))
for k, x in enumerate((-3.4, 3.4)):
    parts.append(bbox(f"Band{k}", (0.9, D + 0.3, H + 0.1), (x, 0, H / 2), GOLD_LO, GOLD, bev=0.1))
parts.append(bbox("Rim", (W + 0.5, D + 0.5, 0.5), (0, 0, H - 0.05), GOLD_LO, GOLD_HI, bev=0.15))
# big lock plate on the front with a keyhole and a gem
parts.append(bbox("Lock", (2.0, 0.45, 2.3), (0, -D / 2 - 0.15, H - 1.3), GOLD_LO, GOLD_HI, bev=0.2))
parts.append(gem("LockGem", 0.5, (0, -D / 2 - 0.55, H - 0.9), GEM_PINK, rot=(90, 0, 0)))
parts.append(box("Keyhole", (0.32, 0.15, 0.7), (0, -D / 2 - 0.4, H - 1.9), VIOLET_DEEP))
# chunky gold feet
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(blob(f"Foot{sx}{sy}", 0.6, (sx * (W / 2 - 0.4), sy * (D / 2 - 0.4), 0.15), GOLD, subdiv=1, jitter=0, squash=(1, 1, 0.6)))

# open lid: hinge at the back top edge, opened 100 deg so it leans slightly back
HY, HZ = D / 2, H
ANG = -100
LR = 3.2
parts.append(half_drum("Lid", W, D / 2, (0, 0, H), WOODP_LO, WOODP, hinge=(HY, HZ), angle=ANG))
for k, x in enumerate((-W / 2 + 0.4, -3.4, 3.4, W / 2 - 0.4)):
    parts.append(half_drum(f"LidBand{k}", 0.9, D / 2 + 0.18, (x, 0, H - 0.01), GOLD_LO, GOLD, hinge=(HY, HZ), angle=ANG))
# lid inner face: velvet panel + sign (SurfaceGui "EXCLUSIVE") facing front
parts.append(rot_box("LidVelvet", (W - 1.0, D - 0.8, 0.2), (0, 0, H - 0.05), VIOLET_DEEP, PURPLE_D, (HY, HZ), ANG))
parts.append(rot_box("SignFrame", (7.6, 2.4, 0.4), (0, -0.4, H - 0.25), GOLD_LO, GOLD, (HY, HZ), ANG, bev=0.15))
parts.append(rot_box("SignFace", (6.8, 1.6, 0.3), (0, -0.4, H - 0.45), PURPLE_D, PURPLE, (HY, HZ), ANG, bev=0.06))
# gold star + gems on the lid top edge
top_y = HY + math.sin(math.radians(-ANG - 90)) * D
top_z = HZ + math.cos(math.radians(-ANG - 90)) * D
parts.append(star("LidStar", 0, top_y - 0.1, top_z + 1.7, 1.6, 0.6, GOLD_LO, GOLD_HI))
parts.append(gem("LidStarGem", 0.4, (0, top_y - 0.5, top_z + 1.7), GEM_CYAN, rot=(90, 0, 0)))
for sx in (-1, 1):
    parts.append(gem(f"LidGem{sx}", 0.7, (sx * 4.6, top_y, top_z + 0.6), (GEM_PINK, GEM_GREEN)[sx > 0], h=1.4))

# treasure heap inside, mounded above the rim
heap = blob("Heap", 4.6, (0, 0.3, H - 0.8), GOLD, subdiv=3, squash=(1.25, 0.72, 0.5), jitter=0.04, seed=2)
gradient(heap, GOLD_LO, GOLD_HI)
parts.append(heap)
for k in range(26):   # loose coins on the heap
    x = R.uniform(-5.0, 5.0)
    y = R.uniform(-2.6, 2.6)
    zt = H - 0.8 + 4.6 * 0.5 * math.sqrt(max(0.0, 1 - (x / 5.75) ** 2 - ((y - 0.3) / 3.3) ** 2))
    parts.append(gcyl(f"Coin{k}", 0.42, 0.14, (x, y, zt - 0.02), GOLD_LO, GOLD_HI, segs=8,
                      rot=(R.uniform(-35, 35), R.uniform(-35, 35), 0)))
# gems on the heap
for k, (x, y, col) in enumerate(((-3.8, -1.6, GEM_CYAN), (-2.2, 1.2, GEM_PINK), (3.9, -1.2, GEM_GREEN), (2.4, 1.6, GEM_CYAN), (4.8, 0.4, GEM_PINK), (-4.8, 0.3, PURPLE_HI))):
    parts.append(gem(f"HGem{k}", 0.55, (x, y, H + 1.0), col, h=1.1, rot=(R.uniform(-25, 25), R.uniform(-25, 25), 0)))

# exclusive pet clouds sitting on the treasure + a crown
parts += puffs("PetL", -3.0, 0.2, H + 1.3, 1.2, rgb(230, 150, 210), rgb(255, 214, 236), seed=5)
parts += puffs("PetR", 3.0, 0.2, H + 1.3, 1.2, rgb(130, 190, 250), rgb(206, 238, 255), seed=8)
parts += crown("Crown", 0, -0.6, H + 1.9, r=1.1, h=1.0)

# spill on the ground: coin pools + stacks + a fallen goblet
for k, (x, y, r) in enumerate(((-4.5, -4.6, 1.5), (3.8, -4.9, 1.8), (6.8, -2.4, 1.2))):
    pool = blob(f"Pool{k}", r, (x, y, 0.0), GOLD, subdiv=2, squash=(1.3, 1.0, 0.25), jitter=0.05, seed=k)
    gradient(pool, GOLD_LO, GOLD_HI)
    parts.append(pool)
for k, (x, y, n) in enumerate(((-6.8, -3.6, 5), (5.6, -5.6, 3), (-2.6, -5.4, 2))):
    for j in range(n):
        parts.append(gcyl(f"Stack{k}{j}", 0.5, 0.2, (x + R.uniform(-0.06, 0.06), y, j * 0.21), GOLD_LO, GOLD_HI, segs=8))
for k in range(10):
    parts.append(gcyl(f"Loose{k}", 0.42, 0.14, (R.uniform(-7, 7), R.uniform(-6.2, -4.0), 0.02), GOLD_LO, GOLD_HI, segs=8, rot=(R.uniform(-8, 8), 0, 0)))
parts.append(gem("GroundGem", 0.6, (1.0, -5.6, 0.35), GEM_PINK, h=1.1, rot=(70, 0, 30)))
parts.append(gem("GroundGem2", 0.5, (-5.8, -5.4, 0.3), GEM_CYAN, h=1.0, rot=(60, 0, -20)))

finish("exclusive_shop_d_chest", parts)
