# ranch_scarecrow: friendly field scarecrow (Slime Ranch), ~8.5 studs tall field/plot decor.
# Wood post + cross-arm, burlap shirt with hay cuffs, red bandana, sack head with a smile,
# butter straw hat with a red band and a goo "icing" splat on the crown (displaced disc, not tubes).
# Front faces -Y. cylinder() pos = base; rot=(0,90,0) grows toward +X, rot=(90,0,0) toward -Y.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_plaza"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
BUTTER, PINK = PALETTE["ranch_butter"], PALETTE["ranch_pink"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
PATH = PALETTE["ranch_path"]

WOOD_LO = mix(WOOD_D, WOOD, 0.45)
SACK, SACK_LO = mix(WOOD, PLAZA, 0.55), mix(WOOD, PLAZA, 0.15)
SHIRT, SHIRT_LO = mix(ROOF, WOOD, 0.2), mix(ROOF_D, WOOD_D, 0.3)
HAY_LO, HAY_HI = mix(BUTTER, WOOD, 0.15), mix(BUTTER, CREAM, 0.25)
RED_LO = mix(ROOF_D, ROOF, 0.5)
parts = []


def pbox(name, size, pos, bot, top, bev=0.1, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


def grad(o, bot, top):
    gradient(o, bot, top)
    return o


# --- post, foot, cross-arm ---
POST_TOP = 6.6
ARM_Z = 5.0
parts.append(pbox("Post", (0.9, 0.9, POST_TOP), (0, 0.15, POST_TOP / 2), WOOD_LO, WOOD, bev=0.12))
for i, (sx, sy, rz) in enumerate(((1, 0, 0), (0, 1, 0))):
    parts.append(pbox(f"Foot{i}", (3.0 if sx else 0.7, 0.7 if sx else 3.0, 0.5), (0, 0.15, 0.25),
                      WOOD_LO, mix(WOOD_LO, WOOD, 0.6), bev=0.12))
parts.append(pbox("Arm", (6.4, 0.75, 0.75), (0, 0.15, ARM_Z), WOOD_LO, WOOD, bev=0.12))

# --- burlap shirt (tapered body), sleeves along the arm ---
parts.append(grad(cylinder("Shirt", 1.25, 2.7, (0, 0, 2.8), SHIRT, segs=8, r_top=1.05), SHIRT_LO, SHIRT))
parts[-1].scale = (1.0, 0.72, 1.0)
for sx in (-1, 1):
    base = 0.6 if sx > 0 else -0.6
    s = cylinder(f"Sleeve{sx}", 0.62, 2.0, (base, 0.1, ARM_Z), SHIRT, segs=8, r_top=0.52,
                 rot=(0, 90 * sx, 0))
    grad(s, SHIRT_LO, SHIRT)
    parts.append(s)
    # cream cuff band + hay tuft hands
    parts.append(grad(cylinder(f"Cuff{sx}", 0.58, 0.28, (sx * 2.45, 0.1, ARM_Z), CREAM, segs=8,
                               rot=(0, 90 * sx, 0)), mix(CREAM, WOOD, 0.3), CREAM))
    for k, (dz, dy, rr) in enumerate(((0.15, -0.1, 0.42), (-0.25, 0.15, 0.36), (0.05, 0.25, 0.3))):
        parts.append(grad(blob(f"Tuft{sx}{k}", rr, (sx * (2.95 + 0.1 * k), 0.1 + dy, ARM_Z + dz), HAY_HI,
                               subdiv=2, squash=(1.5, 0.9, 0.8), jitter=0.06, seed=3 + k + sx),
                          HAY_LO, HAY_HI))
# hay sticking out under the shirt hem
for k, a in enumerate((-55, 10, 80, 190)):
    x, y = math.cos(math.radians(a)) * 0.95, math.sin(math.radians(a)) * 0.65
    parts.append(grad(blob(f"Hem{k}", 0.38, (x, y, 2.75), HAY_HI, subdiv=2, squash=(1.1, 1.1, 0.8),
                           jitter=0.05, seed=20 + k), HAY_LO, HAY_HI))
# cream patch + buttons on the shirt front
parts.append(pbox("Patch", (0.7, 0.12, 0.65), (0.45, -0.93, 3.6), mix(CREAM, PLAZA, 0.35), CREAM, bev=0.04,
                  rot=(0, 8, 0)))
for k, z in enumerate((4.45, 3.8)):
    parts.append(blob(f"Btn{k}", 0.14, (-0.35, -0.86, z), CREAM, subdiv=1, squash=(1, 0.5, 1), jitter=0))

# --- red bandana: neck band + front triangle ---
parts.append(grad(cylinder("Band", 0.95, 0.4, (0, 0.05, 5.45), BUTTER, segs=8), HAY_LO, HAY_HI))
parts[-1].scale = (1.0, 0.85, 1.0)
bm = bmesh.new()
tri = [(-0.85, -0.78, 5.75), (0.85, -0.78, 5.75), (0.1, -0.98, 4.55)]
vs = [bm.verts.new(p) for p in tri] + [bm.verts.new((x, y + 0.22, z)) for x, y, z in tri]
bm.faces.new((vs[0], vs[2], vs[1])); bm.faces.new((vs[3], vs[4], vs[5]))
for a, b in ((0, 1), (1, 2), (2, 0)):
    bm.faces.new((vs[a], vs[b], vs[b + 3], vs[a + 3]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
parts.append(grad(obj_from_bm("Kerchief", bm, BUTTER), HAY_LO, HAY_HI))
for k, (x, z) in enumerate(((-0.35, 5.4), (0.4, 5.25), (0.05, 4.95))):
    parts.append(blob(f"Dot{k}", 0.09, (x, -0.97, z), ROOF, subdiv=1, squash=(1, 0.4, 1), jitter=0))

# --- sack head with a friendly face ---
HZ = 6.75
parts.append(grad(blob("Head", 1.15, (0, 0.05, HZ), PATH, subdiv=2, squash=(1.0, 0.92, 1.0), jitter=0.03, seed=7),
                  mix(PATH, CREAM, 0.3), mix(PATH, CREAM, 0.6)))
parts.append(grad(cylinder("Tie", 0.62, 0.3, (0, 0.05, 5.7), WOOD, segs=8, r_top=0.7), WOOD_LO, WOOD))
for sx in (-1, 1):
    parts.append(blob(f"Eye{sx}", 0.17, (sx * 0.4, -1.0, HZ + 0.2), WOOD_D, subdiv=1, squash=(1, 0.5, 1.2), jitter=0))
    parts.append(blob(f"Cheek{sx}", 0.2, (sx * 0.65, -0.93, HZ - 0.2), PINK, subdiv=1, squash=(1.1, 0.4, 0.8), jitter=0))
# smile: 5 small stitch boxes along an arc
for k in range(5):
    t = (k - 2) / 2.0
    x, z = t * 0.42, HZ - 0.35 - 0.16 * (1 - t * t)
    parts.append(box(f"Smile{k}", (0.2, 0.12, 0.09), (x, -1.02 + 0.08 * abs(t), z), WOOD_D,
                     rot=(0, math.degrees(math.atan(t * 0.6)), 0)))
parts.append(blob("Nose", 0.15, (0, -1.08, HZ - 0.02), mix(WOOD, ROOF, 0.4), subdiv=1, squash=(1, 0.7, 0.9), jitter=0))

# --- butter straw hat with red band, tipped a little ---
HAT_Z = HZ + 0.8
BR = 1.75
parts.append(grad(cylinder("Brim", BR, 0.22, (0, 0.05, HAT_Z), BUTTER, segs=14, r_top=BR - 0.15),
                  HAY_LO, HAY_HI))
parts.append(grad(cylinder("Crown", 1.05, 1.0, (0, 0.05, HAT_Z + 0.2), BUTTER, segs=12, r_top=0.92),
                  HAY_LO, HAY_HI))
parts.append(grad(cylinder("HatBand", 1.08, 0.32, (0, 0.05, HAT_Z + 0.22), ROOF, segs=12, r_top=1.02),
                  RED_LO, ROOF))
parts.append(blob("Flower", 0.2, (-0.75, -0.7, HAT_Z + 0.4), PINK, subdiv=1, squash=(1, 0.6, 1), jitter=0))
parts.append(blob("FlowerC", 0.09, (-0.78, -0.82, HAT_Z + 0.4), BUTTER, subdiv=1, jitter=0))

# goo icing on the crown: closed disc, wavy rim that sags into 3 short drips down the crown
GSEG = 18
cz = HAT_Z + 1.2
bm = bmesh.new()
top_c = bm.verts.new((0, 0.05, cz + 0.18))
bot_c = bm.verts.new((0, 0.05, cz - 0.05))
tops, bots, sag = [], [], []
for i in range(GSEG):
    a = 2 * math.pi * i / GSEG
    s = max(0.0, math.cos(3 * (a + 0.4))) ** 6  # 3 drip lobes
    r = 0.98 + 0.06 * s
    z = cz - 0.02 - 0.55 * s
    x, y = r * math.cos(a), 0.05 + r * math.sin(a)
    tops.append(bm.verts.new((x, y, z + 0.08)))
    bots.append(bm.verts.new((x * 0.9, 0.05 + (y - 0.05) * 0.9, z - 0.04)))
    sag.append(s)
for i in range(GSEG):
    j = (i + 1) % GSEG
    bm.faces.new((top_c, tops[i], tops[j]))
    bm.faces.new((bot_c, bots[j], bots[i]))
    bm.faces.new((tops[i], bots[i], bots[j], tops[j]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
layer = bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    if top_c in f.verts:
        col = mix(GOO, GOO_HI, 0.3)
    else:
        col = GOO if c.z > cz - 0.2 else mix(GOO, GOO_HI, 0.5)
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
parts.append(obj_from_bm("Goo", bm))
parts.append(blob("GooBub", 0.13, (0.3, -0.2, cz + 0.2), GOO_HI, subdiv=1, squash=(1, 1, 0.6), jitter=0))

finish("ranch_scarecrow", parts)
