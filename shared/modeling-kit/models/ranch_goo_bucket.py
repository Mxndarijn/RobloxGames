# ranch_goo_bucket: wooden farm bucket with glossy slime goo fill (Slime Ranch).
# Tapered stave body (wider at top), pewter bands, arched bail.
# Goo = body top-cap painted + dipped (closed, 0 nm) + small highlight bubbles.
# Small prop — under ~500 tris OK. cylinder() pos = base.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
METAL = PALETTE["ranch_metal"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, WOOD_D, 0.1)
METAL_HI = mix(METAL, CREAM, 0.25)
GOO_LO = shade(GOO, 0.82)
parts = []

R_BOT, R_TOP, H = 0.72, 0.95, 1.85
SEGS = 10


def radius_at(t):
    return R_BOT + (R_TOP - R_BOT) * max(0.0, min(1.0, t))


# body frustum; top-cap verts dipped + painted as goo (keeps mesh closed)
body = cylinder("Body", R_BOT, H, (0, 0, 0), WOOD, segs=SEGS, r_top=R_TOP)
bm = bmesh.new()
bm.from_mesh(body.data)
for v in bm.verts:
    if v.co.z >= H - 1e-4:
        d = math.hypot(v.co.x, v.co.y) / max(R_TOP, 1e-6)
        v.co.z = H - 0.14 * (1 - min(1.0, d ** 2.5))
bm.faces.ensure_lookup_table()
bm.normal_update()
layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    # top goo: any face whose verts are all near the dipped top
    topish = sum(1 for v in f.verts if v.co.z > H - 0.2) >= len(f.verts) - 0
    if topish and f.normal.z > 0.15:
        d = math.hypot(c.x, c.y) / max(R_TOP, 1e-6)
        col = mix(GOO, GOO_HI, min(1.0, d ** 5 * 1.25))
    elif f.normal.z < -0.85:
        col = WOOD_LO
    else:
        ang = math.atan2(c.y, c.x)
        stave = int(((ang + math.pi) / (2 * math.pi)) * SEGS) % 2
        t = max(0.0, min(1.0, c.z / H))
        col = mix(WOOD_LO, WOOD_HI, t)
        if stave:
            col = shade(col, 0.93)
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
bm.to_mesh(body.data)
bm.free()
parts.append(body)

# bottom lid
parts.append(cylinder("Bot", R_BOT * 0.88, 0.12, (0, 0, 0.04), WOOD_LO, segs=SEGS))
gradient(parts[-1], WOOD_D, WOOD_LO)

# pewter bands
for i, t in enumerate((0.22, 0.72)):
    z = t * H - 0.08
    rh = radius_at(t) + 0.04
    hoop = cylinder(f"Band{i}", rh, 0.16, (0, 0, z), METAL, segs=SEGS)
    gradient(hoop, METAL_LO, METAL_HI)
    parts.append(hoop)

# wood rim lip — sits around the goo, not over it (radius outside top)
rim = cylinder("Rim", R_TOP + 0.07, 0.12, (0, 0, H - 0.14), WOOD_HI, segs=SEGS, r_top=R_TOP + 0.07)
# hollow the rim? keep as solid band outside — use larger r only
gradient(rim, WOOD, WOOD_HI)
parts.append(rim)

# bail
bail_r = R_TOP + 0.05
bail_z0 = H - 0.02
bail_pts, bail_rads = [], []
for i in range(7):
    ang = math.pi * i / 6
    bail_pts.append((-bail_r * math.cos(ang), 0.0, bail_z0 + bail_r * 0.9 * math.sin(ang)))
    bail_rads.append(0.09)
bail = tube("Bail", bail_pts, bail_rads, METAL, segs=5)
gradient(bail, METAL_LO, METAL_HI)
parts.append(bail)
for sx in (-1, 1):
    parts.append(box(f"Ear{sx}", (0.18, 0.26, 0.26), (sx * (R_TOP + 0.02), 0, H - 0.05), METAL))
    gradient(parts[-1], METAL_LO, METAL_HI)

# highlight bubbles on goo (small; goo_hi OK)
parts.append(blob("Bub1", 0.11, (0.25, -0.15, H - 0.02), GOO_HI, subdiv=1,
                  squash=(1.1, 1.0, 0.7), jitter=0.04, seed=2))
parts.append(blob("Bub2", 0.08, (-0.3, 0.2, H - 0.05), GOO_HI, subdiv=1,
                  squash=(1.0, 1.0, 0.65), jitter=0.04, seed=8))

# soft drip over rim (-Y)
parts.append(blob("Drip", 0.18, (0.15, -(R_TOP + 0.02), H - 0.35), GOO, subdiv=1,
                  squash=(0.7, 0.65, 1.5), jitter=0.06, seed=3))
gradient(parts[-1], GOO_LO, GOO_HI)
parts.append(blob("DripHi", 0.08, (0.12, -(R_TOP + 0.05), H - 0.15), GOO_HI, subdiv=1,
                  squash=(1, 1, 0.9), jitter=0.04, seed=5))

finish("ranch_goo_bucket", parts)
