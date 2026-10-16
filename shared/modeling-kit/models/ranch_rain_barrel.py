# ranch_rain_barrel: chunky wood-stave rain barrel (Slime Ranch), ~3.4 wide x ~5 tall.
# Bulged stave body with pewter hoops (radius tracks the bulge), top cap dipped + painted as
# goo-tinted water (closed, 0 nm), wood rim lip. Behind it (+Y) a post carries a short gutter
# trough + angled chute that pours into the barrel. Pewter spigot + tiny goo drip near the base on -Y.
# cylinder() pos = base; rot= in DEGREES.
import math
import bmesh
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL, PLAZA = PALETTE["ranch_cream"], PALETTE["ranch_metal"], PALETTE["ranch_plaza"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]

WOOD_LO = mix(WOOD_D, WOOD, 0.55)
WOOD_HI = mix(WOOD, CREAM, 0.18)
METAL_LO = mix(METAL, CREAM, 0.2)
METAL_HI = mix(METAL, CREAM, 0.55)
WATER = mix(GOO, GOO_HI, 0.25)
parts = []

R, H = 1.4, 3.9
SEGS = 14
BULGE = 0.12


def bulge(t):
    return 1.0 + BULGE * math.sin(math.pi * max(0.0, min(1.0, t)))


def radius_at(t):
    return R * bulge(t)


def pbox(name, size, pos, bot, top, bev=0.08, rot=(0, 0, 0)):
    o = box(name, size, pos, bot, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, bot, top)
    return o


# --- body: bulged staves, top cap dipped as water ---
WATER_Z = H - 0.22
body = cylinder("Body", R, H, (0, 0, 0), WOOD, segs=SEGS)
bm = bmesh.new()
bm.from_mesh(body.data)
for v in bm.verts:
    t = max(0.0, min(1.0, v.co.z / H))
    b = bulge(t)
    v.co.x *= b
    v.co.y *= b
    if v.co.z >= H - 1e-4:
        v.co.z = WATER_Z
# poke the top cap so the water can dip a little toward the centre
top = [f for f in bm.faces if f.calc_center_median().z > H - 0.3 and f.normal.z > 0.9]
res = bmesh.ops.poke(bm, faces=top)
for v in res["verts"]:
    v.co.z = WATER_Z - 0.06
bm.normal_update()
layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
for f in bm.faces:
    c = f.calc_center_median()
    if f.normal.z > 0.5 and c.z > H - 0.4:
        d = math.hypot(c.x, c.y) / R
        col = mix(WATER, GOO_HI, min(0.45, d ** 4 * 0.6))
    elif f.normal.z < -0.85:
        col = WOOD_LO
    else:
        stave = int(((math.atan2(c.y, c.x) + math.pi) / (2 * math.pi)) * SEGS) % 2
        col = mix(WOOD_LO, WOOD_HI, max(0.0, min(1.0, c.z / H)))
        if stave:
            col = shade(col, 0.93)
    for lp in f.loops:
        lp[layer] = (*col[:3], 1.0)
bm.to_mesh(body.data)
bm.free()
parts.append(body)

def ring(name, r_in, r_out, z0, z1, bot, top_c, segs=SEGS):
    """closed annulus (square section): an open hoop, unlike a capped cylinder disc."""
    bm = bmesh.new()
    rows = [(r_in, z0), (r_out, z0), (r_out, z1), (r_in, z1)]
    rings = [[bm.verts.new((math.cos(k * math.tau / segs) * r, math.sin(k * math.tau / segs) * r, z))
              for k in range(segs)] for r, z in rows]
    for i in range(4):
        a, b = rings[i], rings[(i + 1) % 4]
        for k in range(segs):
            bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, bot)
    gradient(o, bot, top_c)
    return o


# rim lip: open ring standing above the water line, so the water shows from above
parts.append(ring("Rim", radius_at(1.0) - 0.22, radius_at(1.0) + 0.1, H - 0.3, H + 0.12, WOOD, WOOD_HI))
# foot ring
parts.append(cylinder("Foot", radius_at(0.0) + 0.08, 0.22, (0, 0, 0), WOOD_LO, segs=SEGS))
gradient(parts[-1], WOOD_D, WOOD_LO)

# pewter hoops on the bulge
for i, t in enumerate((0.2, 0.5, 0.8)):
    hoop = cylinder(f"Hoop{i}", radius_at(t) + 0.1, 0.26, (0, 0, t * H - 0.12), METAL, segs=SEGS)
    gradient(hoop, METAL_LO, METAL_HI)
    parts.append(hoop)

# --- downspout post behind (+Y), gutter on top, chute pouring into the barrel ---
PX, PY = 0.55, R + 0.85
PH = 5.2
parts.append(pbox("Post", (0.8, 0.8, PH), (PX, PY, PH / 2), WOOD_LO, WOOD, bev=0.1))
parts.append(pbox("PostFoot", (1.3, 1.3, 0.35), (PX, PY, 0.17), WOOD_D, WOOD_LO, bev=0.08))
# gutter trough across the post top (along X): floor + two walls, red painted
GZ = PH - 0.1
parts.append(pbox("GutterFloor", (2.6, 0.9, 0.2), (PX - 0.2, PY - 0.05, GZ), mix(ROOF_D, ROOF, 0.5), ROOF, bev=0.05))
for s in (-1, 1):
    parts.append(pbox(f"GutterWall{s}", (2.6, 0.18, 0.45), (PX - 0.2, PY - 0.05 + s * 0.4, GZ + 0.22),
                      mix(ROOF_D, ROOF, 0.5), ROOF, bev=0.04))
for s in (-1, 1):
    parts.append(pbox(f"GutterEnd{s}", (0.18, 0.9, 0.45), (PX - 0.2 + s * 1.25, PY - 0.05, GZ + 0.22),
                      mix(ROOF_D, ROOF, 0.5), ROOF, bev=0.04))
# chute: open U trough angled down from the gutter toward the barrel centre
CH_ANG = 38
CL = 1.9
cy = PY - 0.55 - CL / 2 * math.cos(math.radians(CH_ANG))
cz = GZ - 0.1 - CL / 2 * math.sin(math.radians(CH_ANG))
parts.append(pbox("ChuteFloor", (0.7, CL, 0.16), (PX - 0.2, cy, cz), METAL_LO, METAL_HI, bev=0.04, rot=(CH_ANG, 0, 0)))
for s in (-1, 1):
    parts.append(pbox(f"ChuteSide{s}", (0.12, CL, 0.32), (PX - 0.2 + s * 0.33, cy, cz + 0.12), METAL_LO, METAL_HI,
                      bev=0.03, rot=(CH_ANG, 0, 0)))
# bracket from post to chute
parts.append(pbox("Brace", (0.3, 0.3, 1.4), (PX, PY - 0.55, GZ - 0.85), WOOD_LO, WOOD, bev=0.05, rot=(-25, 0, 0)))

# goo-tinted water stream from the chute lip into the barrel
lip_y = cy - CL / 2 * math.cos(math.radians(CH_ANG))
lip_z = cz - CL / 2 * math.sin(math.radians(CH_ANG)) + 0.1
balls = []
for j in range(6):
    t = j / 5
    balls.append(Ball((PX - 0.2, lip_y - 0.05 * t, lip_z - (lip_z - WATER_Z) * t), (0.22, 0.22, 0.26)))
balls.append(Ball((PX - 0.2, lip_y - 0.05, WATER_Z), (0.4, 0.4, 0.08)))
stream = metaball_mesh("Stream", balls, resolution=0.08, tris=200)
parts.append(paint_goo(stream, lambda co, n: mix(WATER, GOO_HI, 0.3 * max(0.0, n.z))))

# --- spigot near the base on -Y ---
SZ = 0.75
sy = -radius_at(SZ / H)
parts.append(cylinder("SpigotBoss", 0.24, 0.2, (0, sy + 0.05, SZ), METAL, segs=8, rot=(90, 0, 0)))
parts.append(cylinder("Spigot", 0.13, 0.5, (0, sy - 0.1, SZ), METAL_HI, segs=8, rot=(90, 0, 0)))
parts.append(cylinder("SpigotNose", 0.13, 0.3, (0, sy - 0.55, SZ + 0.05), METAL_HI, segs=8, rot=(180, 0, 0)))
parts.append(pbox("SpigotTap", (0.5, 0.12, 0.14), (0, sy - 0.4, SZ + 0.24), METAL, METAL_HI, bev=0.03))
gd = [Ball((0, sy - 0.55, SZ - 0.3), (0.1, 0.1, 0.12)), Ball((0, sy - 0.55, SZ - 0.46), (0.13, 0.13, 0.13))]
gd += [Ball((0.1, sy - 0.62, 0.02), (0.55, 0.45, 0.06))]
puddle = metaball_mesh("SpigotGoo", gd, resolution=0.06, tris=180, clamp_z=0.02)
parts.append(paint_goo(puddle, lambda co, n: mix(GOO, GOO_HI, 0.3 * max(0.0, n.z) ** 4)))

finish("ranch_rain_barrel", parts)
