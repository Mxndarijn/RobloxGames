# ranch_sunflower_patch: raised plank bed of sunflowers for the plaza / farm edges (Slime Ranch).
# Bevelled plank border (corner posts) round a soil bed, 5 sunflowers of mixed
# heights (4.6-7.4 studs, the tallest over the 5-stud avatar) whose heads face front-left (-Y, toward
# the kit sun), tilted up: each head = closed slab of 9 pointed oval petals (butter) + domed seed centre +
# green back cup, on a curved stem with 2 slab leaves. A red watering can on the front-right corner
# dribbles goo (metaball, lib/goo.py) into a puddle.
# Medium prop, target 500-2000 tris. cylinder() pos = base; lib rot= is in DEGREES.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
BUTTER, PATH = PALETTE["ranch_butter"], PALETTE["ranch_path"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
FIELD, FIELD_D, FIELD_L = PALETTE["ranch_field"], PALETTE["ranch_field_dark"], PALETTE["ranch_field_light"]
WOOD_LO, WOOD_HI = mix(WOOD_D, WOOD, 0.45), mix(WOOD, CREAM, 0.12)
SOIL_LO, SOIL_HI = WOOD_D, mix(WOOD_D, WOOD, 0.3)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.15), mix(METAL, CREAM, 0.25)
R = random.Random(5)
parts = []

# --- dimensions --------------------------------------------------------------------------
BW, BD, BH, PT = 6.6, 3.6, 0.85, 0.4      # bed outer width (x), depth (y), border height, plank thickness


def paint(o, fn):
    """per-corner colour from fn(local co, face normal)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.normal_update()
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            lp[layer] = (*fn(lp.vert.co, f.normal)[:3], 1.0)
    bm.to_mesh(o.data)
    bm.free()
    return o


def slab(name, pts2d, thick, M, color_fn):
    """closed slab: 2D polygon (local x, y) extruded along local z by thick, placed by matrix M."""
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x, y, -thick / 2)) for x, y in pts2d])
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, 0, thick), verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=[x for x in bm.faces if len(x.verts) > 4])
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    o = obj_from_bm(name, bm)
    return paint(o, color_fn)


# --- raised bed ------------------------------------------------------------------------------
for i, (sx, sy, x, y) in enumerate(((BW, PT, 0, -BD / 2 + PT / 2), (BW, PT, 0, BD / 2 - PT / 2),
                                     (PT, BD - 2 * PT, -BW / 2 + PT / 2, 0), (PT, BD - 2 * PT, BW / 2 - PT / 2, 0))):
    parts.append(box(f"Plank{i}", (sx, sy, BH), (x, y, BH / 2), WOOD))
    bevel(parts[-1], 0.08)
    gradient(parts[-1], WOOD_LO, WOOD_HI)
for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
    parts.append(box(f"Post{i}", (0.55, 0.55, BH + 0.35), (sx * (BW / 2 - 0.1), sy * (BD / 2 - 0.1), (BH + 0.35) / 2), WOOD))
    bevel(parts[-1], 0.1)
    gradient(parts[-1], WOOD_LO, WOOD_HI)
parts.append(box("Soil", (BW - 2 * PT + 0.02, BD - 2 * PT + 0.02, 0.2), (0, 0, BH - 0.18), SOIL_HI))
gradient(parts[-1], SOIL_LO, SOIL_HI)

# --- sunflowers ------------------------------------------------------------------------------
FLOWERS = [  # (x, y, height, head radius, yaw deg, tilt up deg)
    (-2.35, 0.35, 5.0, 0.95, -8, 18),
    (-1.15, -0.1, 6.5, 1.15, -16, 12),
    (0.05, 0.45, 7.4, 1.25, -22, 16),
    (1.2, -0.05, 5.6, 1.05, -14, 10),
    (2.35, 0.4, 4.6, 0.9, -28, 20),
]
NP = 9


def petal_col(rmax):
    def fn(co, n):
        r = math.hypot(co.x, co.y)
        return mix(BUTTER, mix(BUTTER, CREAM, 0.45), min(1, r / rmax) ** 1.5)
    return fn


for i, (x, y, h, hr, yaw, tilt) in enumerate(FLOWERS):
    face = (Matrix.Rotation(math.radians(yaw), 3, "Z") @ Matrix.Rotation(math.radians(tilt), 3, "X")) @ Vector((0, -1, 0))
    head = Vector((x, y, h))
    # local frame: z = face direction, y = up-ish
    q = face.to_track_quat("Z", "Y")
    M = Matrix.Translation(head) @ q.to_matrix().to_4x4()
    star = []
    for k in range(NP):  # pointed oval petals: shoulder, tip, shoulder, valley
        a = k * math.tau / NP + R.uniform(-0.03, 0.03)
        r = hr * (1.0 + R.uniform(-0.06, 0.06))
        for da, rr in ((-0.17, r * 0.8), (0.0, r), (0.17, r * 0.8), (math.pi / NP, hr * 0.52)):
            star.append((math.cos(a + da) * rr, math.sin(a + da) * rr))
    parts.append(slab(f"Petals{i}", star, 0.16, M, petal_col(hr)))
    # seed centre: domed disc proud of the petals
    c = cylinder(f"Seeds{i}", hr * 0.46, 0.26, (0, 0, 0.0), WOOD_D, segs=8, r_top=hr * 0.36)
    c.data.transform(M)
    paint(c, lambda co, n: mix(mix(WOOD_D, WOOD, 0.15), mix(WOOD_D, BUTTER, 0.35), max(0.0, n.dot(face))))
    parts.append(c)
    # green back cup
    b = cylinder(f"Cup{i}", hr * 0.5, 0.3, (0, 0, -0.38), FIELD_D, segs=6, r_top=hr * 0.62)
    b.data.transform(M)
    gradient(b, FIELD_D, FIELD)
    parts.append(b)
    # stem: soil -> slight S-curve -> into the back of the head
    back = head - face * 0.35
    p0 = Vector((x, y, BH - 0.1))
    mid = p0.lerp(back, 0.55) + Vector((0.12 * (-1) ** i, 0.18, 0))
    parts.append(tube(f"Stem{i}", [p0, mid, back], [0.17, 0.15, 0.13], FIELD_D, segs=4))
    gradient(parts[-1], FIELD_D, FIELD)
    # 2 leaves: diamond slabs drooping outward from the stem
    for j, (zf, side) in enumerate(((0.35, 1), (0.58, -1))):
        base = p0.lerp(back, zf)
        out = Vector((side * math.cos(math.radians(yaw + 25 * j)), 0.25 * j - 0.15, 0)).normalized()
        xa0 = (out + Vector((0, 0, -0.5))).normalized()
        L = 1.2 + 0.15 * (i % 2)
        leaf = [(0, 0), (L * 0.3, 0.3), (L * 0.7, 0.26), (L, 0.02), (L * 0.68, -0.24), (L * 0.28, -0.26)]
        xa = xa0
        nf = Vector((0, -0.55, 1)).normalized()  # leaf normal leans toward the front (-Y)
        za = (nf - xa * nf.dot(xa)).normalized()
        ya = za.cross(xa)
        Ml = Matrix.Translation(base) @ Matrix((xa, ya, za)).transposed().to_4x4()
        parts.append(slab(f"Leaf{i}_{j}", leaf, 0.08, Ml,
                          lambda co, n, L=L: mix(FIELD, FIELD_L, min(1, math.hypot(co.x, co.y) / L) * 0.8)))

# --- watering can on the front-right corner, dribbling goo -----------------------------------
CX, CY, CZ = BW / 2 + 0.75, -BD / 2 - 0.55, 0.0
parts.append(cylinder("Can", 0.55, 0.95, (CX, CY, CZ), ROOF, segs=8, r_top=0.48))
gradient(parts[-1], mix(ROOF_D, ROOF, 0.5), ROOF)
parts.append(cylinder("CanRim", 0.5, 0.1, (CX, CY, CZ + 0.95), METAL, segs=8))
gradient(parts[-1], METAL_LO, METAL_HI)
parts.append(tube("CanSpout", [(CX - 0.35, CY - 0.1, CZ + 0.35), (CX - 0.8, CY - 0.25, CZ + 0.8), (CX - 1.05, CY - 0.32, CZ + 1.05)],
                  [0.12, 0.09, 0.11], METAL, segs=5))
gradient(parts[-1], METAL_LO, METAL_HI)
parts.append(tube("CanHandle", [(CX + 0.3, CY + 0.05, CZ + 0.95), (CX + 0.2, CY + 0.05, CZ + 1.45),
                                (CX - 0.2, CY + 0.05, CZ + 1.45), (CX - 0.3, CY + 0.05, CZ + 0.95)],
                  [0.08, 0.08, 0.08, 0.08], METAL, segs=4))
gradient(parts[-1], METAL_LO, METAL_HI)
balls = [Ball((CX - 1.08, CY - 0.33, CZ + 1.0), (0.13, 0.13, 0.12))]
for s in range(1, 4):  # dribble from the rose down to the ground
    t = s / 4
    balls.append(Ball((CX - 1.1, CY - 0.35, CZ + 1.0 - t * 0.85), (0.1 - 0.02 * t, 0.1 - 0.02 * t, 0.16)))
balls.append(Ball((CX - 1.1, CY - 0.35, 0.22), (0.15, 0.15, 0.17)))
for x, y, rr in ((CX - 1.1, CY - 0.4, 0.75), (CX - 1.6, CY - 0.2, 0.45), (CX - 0.6, CY - 0.8, 0.4)):
    balls.append(Ball((x, y, 0.02), (rr, rr * 0.8, 0.12)))
goo = metaball_mesh("CanGoo", balls, resolution=0.07, tris=180, clamp_z=0.0)
print("goo nm", goo["nm"])
paint_goo(goo, lambda co, n: (*mix(GOO, GOO_HI, 0.15 + 0.4 * max(0.0, n.z) ** 2 * (1 if co.z < 0.3 else 0.5))[:3], 1.0))
parts.append(goo)
for k, (x, y) in enumerate(((-BW / 2 - 0.4, -BD / 2 - 0.3), (BW / 2 - 0.6, BD / 2 + 0.45), (-BW / 2 + 1.2, BD / 2 + 0.4))):
    parts.append(blob(f"Tuft{k}", 0.45, (x, y, 0.15), FIELD_L, subdiv=1, squash=(1, 1, 0.7), jitter=0.15, seed=k + 3))
    gradient(parts[-1], FIELD_D, FIELD_L)

finish("ranch_sunflower_patch", parts)
