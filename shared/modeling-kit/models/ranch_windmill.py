# ranch_windmill: small ranch wind pump (Slime Ranch). ~16 studs tall vs the 5-stud avatar.
# Splayed 4-leg wood lattice tower -> plank deck -> pewter turntable + wood housing under a small
# red gable cap -> rotor of 8 chunky goo-tinted vanes on wood spokes facing -Y, each vane tip
# wearing a metaball goo lip (lib/goo.py) with drips hanging from the side/lower tips.
# Tail boom toward +Y with a butter fin in a barn-red frame. Pump rod down the middle into a
# small wooden goo tub at the base (metaball goo surface + front spill + ground puddle).
# Medium prop, target 500-2000 tris. cylinder() pos = base; lib rot= is in DEGREES.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, METAL = PALETTE["ranch_cream"], PALETTE["ranch_metal"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
BUTTER, PLAZA = PALETTE["ranch_butter"], PALETTE["ranch_plaza"]
WOOD_LO = mix(WOOD_D, WOOD, 0.6)
WOOD_HI = mix(WOOD, CREAM, 0.15)
METAL_LO, METAL_HI = mix(METAL, WOOD_D, 0.15), mix(METAL, CREAM, 0.25)
ROOF_LO = mix(ROOF_D, ROOF, 0.5)
parts = []

# --- dimensions --------------------------------------------------------------------------
B0, B1, TZ = 2.5, 0.85, 11.6     # leg half-spread at the ground / at the deck, deck height
HUB = Vector((0, -1.75, 13.1))   # rotor hub centre (rotor plane faces -Y)
NV, R0, R1 = 8, 1.0, 4.1         # vanes, vane inner/outer radius
W0, W1, VT = 1.05, 1.9, 0.3     # vane width at root / tip, thickness
PITCH = 14.0                     # vane twist about its radial axis (deg)


def leg_xy(z, sx, sy):
    b = B0 + (B1 - B0) * z / TZ
    return (sx * b, sy * b)


def P(z, sx, sy):
    x, y = leg_xy(z, sx, sy)
    return (x, y, z)


def paint(o, fn):
    """per-corner colour from fn(world co, face normal)."""
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


def zgrad(lo, hi, z0, z1):
    return lambda co, n: mix(lo, hi, max(0.0, min(1.0, (co.z - z0) / (z1 - z0))))


tower_col = zgrad(WOOD_LO, WOOD_HI, 0.0, TZ)

# --- tower: 4 splayed legs, 3 rail rings, one diagonal brace per side per bay -------------
CORNERS = ((1, 1), (-1, 1), (-1, -1), (1, -1))
for i, (sx, sy) in enumerate(CORNERS):
    parts.append(tube(f"Leg{i}", [P(0.0, sx, sy), P(TZ / 2, sx, sy), P(TZ + 0.1, sx, sy)], [0.46, 0.42, 0.38], WOOD, segs=5))
    paint(parts[-1], tower_col)
    fx, fy = leg_xy(0, sx, sy)
    parts.append(box(f"Foot{i}", (1.3, 1.3, 0.45), (fx, fy, 0.22), WOOD_LO))
    paint(parts[-1], zgrad(WOOD_D, WOOD_LO, 0, 0.45))
LEVELS = (0.0, 3.3, 6.6, 9.4)
for li, z in enumerate(LEVELS[1:], 1):
    for i in range(4):
        a, b = CORNERS[i], CORNERS[(i + 1) % 4]
        parts.append(tube(f"Rail{li}_{i}", [P(z, *a), P(z, *b)], [0.24, 0.24], WOOD, segs=4))
        paint(parts[-1], tower_col)
for li in range(3):
    z0, z1 = LEVELS[li] + (0.5 if li == 0 else 0.0), LEVELS[li + 1]
    for i in range(4):
        a, b = CORNERS[i], CORNERS[(i + 1) % 4]
        if (li + i) % 2:
            a, b = b, a
        parts.append(tube(f"Brace{li}_{i}", [P(z0, *a), P(z1, *b)], [0.19, 0.19], WOOD_D, segs=4))
        paint(parts[-1], zgrad(WOOD_LO, WOOD, 0.0, TZ))

# --- deck, turntable, housing, red gable cap ----------------------------------------------
parts.append(box("Deck", (2.9, 2.9, 0.42), (0, 0, TZ + 0.2), WOOD)); bevel(parts[-1], 0.1)
paint(parts[-1], zgrad(WOOD_LO, mix(PLAZA, WOOD, 0.3), TZ, TZ + 0.42))
parts.append(cylinder("Turn", 0.95, 0.3, (0, 0, TZ + 0.42), METAL, segs=10))
paint(parts[-1], zgrad(METAL_LO, METAL_HI, TZ + 0.42, TZ + 0.72))
HZ0, HZ1 = TZ + 0.72, TZ + 2.2
parts.append(box("House", (1.5, 2.3, HZ1 - HZ0), (0, -0.3, (HZ0 + HZ1) / 2), WOOD)); bevel(parts[-1], 0.12)
paint(parts[-1], zgrad(WOOD_LO, WOOD_HI, HZ0, HZ1))
RA, RW = 32.0, 1.2              # cap roof pitch (deg), slab half-width (slope length)
for s in (1, -1):
    cx = s * RW * math.cos(math.radians(RA)) / 2
    parts.append(box(f"Cap{s}", (RW + 0.15, 2.8, 0.26), (cx, -0.3, HZ1 + 0.28 + RW * math.sin(math.radians(RA)) / 2 - 0.25),
                     ROOF, rot=(0, s * RA, 0))); bevel(parts[-1], 0.08)
    paint(parts[-1], zgrad(ROOF_LO, ROOF, HZ1, HZ1 + 0.9))
parts.append(cylinder("Ridge", 0.16, 2.9, (0, 1.15, HZ1 + 0.62), ROOF_D, segs=6, rot=(90, 0, 0)))
paint(parts[-1], lambda co, n: mix(ROOF_LO, ROOF, 0.5))
# gable fill under the cap (front + back triangles as one prism)
bm = bmesh.new()
gz = HZ1 - 0.05
tri = [(-1.0, gz), (1.0, gz), (0.0, gz + 0.62)]
f0 = [bm.verts.new((x, -1.45, z)) for x, z in tri]
f1 = [bm.verts.new((x, 0.85, z)) for x, z in tri]
bm.faces.new(f0[::-1]); bm.faces.new(f1)
for k in range(3):
    j = (k + 1) % 3
    bm.faces.new((f0[k], f0[j], f1[j], f1[k]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
parts.append(obj_from_bm("Gable", bm, WOOD_HI))

# --- rotor: hub, spokes, 8 trapezoid goo vanes (pitched), front nose -----------------------
parts.append(cylinder("Shaft", 0.28, 0.9, (0, -1.15, HUB.z), METAL, segs=8, rot=(90, 0, 0)))
paint(parts[-1], zgrad(METAL_LO, METAL_HI, HUB.z - 0.3, HUB.z + 0.3))
parts.append(cylinder("Hub", 0.75, 0.55, (0, HUB.y + 0.3, HUB.z), WOOD, segs=10, rot=(90, 0, 0)))
paint(parts[-1], zgrad(WOOD_LO, WOOD_HI, HUB.z - 0.75, HUB.z + 0.75))
parts.append(blob("Nose", 0.5, (0, HUB.y - 0.3, HUB.z), ROOF, subdiv=2, squash=(1, 0.8, 1), jitter=0))
paint(parts[-1], zgrad(ROOF_LO, ROOF, HUB.z - 0.5, HUB.z + 0.5))


def vane_matrix(k):
    a = 2 * math.pi * k / NV + math.pi / NV
    d = Vector((math.cos(a), 0, math.sin(a)))       # radial direction in the XZ plane
    lat = Vector((0, 1, 0)).cross(d)                 # in-plane, perpendicular to d
    rot = Matrix((d, Vector((0, -1, 0)), lat)).transposed()   # local x->d, y->-Y, z->lat
    tw = Matrix.Rotation(math.radians(PITCH), 3, "X")
    return d, lat, Matrix.Translation(HUB) @ (rot @ tw).to_4x4()


TIPS = []
for k in range(NV):
    d, lat, M = vane_matrix(k)
    # spoke (wood) from hub to mid-vane, behind the vane
    sp = box(f"Spoke{k}", (R1 - 0.6, 0.32, 0.36), ((R1 - 0.6) / 2 + 0.3, -0.2, 0), WOOD)
    sp.data.transform(Matrix.Translation(HUB) @ Matrix((d, Vector((0, -1, 0)), lat)).transposed().to_4x4())
    paint(sp, lambda co, n: mix(WOOD_LO, WOOD, 0.5 + 0.5 * n.z) if abs(n.z) < 0.9 else (WOOD if n.z > 0 else WOOD_LO))
    parts.append(sp)
    # vane: box along local x from R0 to R1, widened toward the tip
    v = box(f"Vane{k}", (R1 - R0, VT, 1.0), ((R0 + R1) / 2, 0.08, 0), GOO)
    bm = bmesh.new(); bm.from_mesh(v.data)
    for vv in bm.verts:
        t = (vv.co.x - R0) / (R1 - R0)
        vv.co.z *= W0 + (W1 - W0) * t
    bm.to_mesh(v.data); bm.free()
    bevel(v, 0.1)
    v.data.transform(M)
    tint = 0.0 if k % 2 else 0.22
    paint(v, lambda co, n, tint=tint: mix(mix(shade(GOO, 0.9), GOO, max(0.0, min(1.0, (co - HUB).length - R0) / (R1 - R0))),
                                          GOO_HI, tint + 0.1 * max(0.0, n.z)))
    parts.append(v)
    TIPS.append((d, lat, M))

# --- goo lips on every vane tip + drips from the side/lower tips (one metaball skin) ------
balls = []
for k, (d, lat, M) in enumerate(TIPS):
    tip = M @ Vector((R1 - 0.02, 0.08, 0))     # tip centre on the vane
    nrm = (M.to_3x3() @ Vector((0, 1, 0))).normalized()  # vane face normal
    side = (M.to_3x3() @ Vector((0, 0, 1))).normalized()  # across the vane width
    q = frame_quat(d, side, d.cross(side).normalized())
    for j in range(-3, 4):
        c = tip + side * (j / 3) * (W1 / 2 - 0.14) - d * (0.1 + 0.05 * (j % 2))
        balls.append(Ball(c, (0.2, 0.3, 0.21), rot=q))
    # drip from the lowest corner of the tip when the tip isn't pointing up
    if d.z < -0.3:
        lo = min((tip + side * (W1 / 2 - 0.3), tip - side * (W1 / 2 - 0.3)), key=lambda p: p.z) - d * 0.1
        down = Vector((0, 0, -1))
        lat2 = down.cross(Vector((0, -1, 0))).normalized()
        qd = frame_quat(down, lat2, down.cross(lat2).normalized())
        L = 0.45 + 0.2 * (k % 2)
        n = 4
        for s in range(n):
            t = s / (n - 1)
            balls.append(Ball(lo + down * (t * L), (0.22, 0.2 - 0.06 * t, 0.15), rot=qd))
        balls.append(Ball(lo + down * (L + 0.08), (0.24, 0.24, 0.22)))
lips = metaball_mesh("VaneGoo", balls, resolution=0.12, tris=360)
print("lip nm", lips["nm"])
paint_goo(lips, lambda co, n: (*mix(GOO, GOO_HI, 0.35 + 0.4 * max(0.0, n.z))[:3], 1.0))
parts.append(lips)

# --- tail: boom + butter fin in a barn-red frame (+Y) -------------------------------------
parts.append(tube("Boom", [(0, 0.7, HZ0 + 0.6), (0, 2.6, HZ0 + 0.75), (0, 4.4, HZ0 + 0.9)], [0.22, 0.2, 0.18], WOOD_D, segs=6))
paint(parts[-1], zgrad(WOOD_LO, WOOD, HZ0 + 0.4, HZ0 + 1.1))


def fin(name, pad, th, col):
    bm = bmesh.new()
    prof = [(3.6, -0.4), (6.2, -1.0), (6.5, 2.0), (3.6, 1.0)]   # (y, z above the boom end)
    vs0 = [bm.verts.new((-th / 2, y + (pad if y > 5 else -pad), HZ0 + 0.9 + z * (1 + pad))) for y, z in prof]
    vs1 = [bm.verts.new((th / 2, v.co.y, v.co.z)) for v in vs0]
    bm.faces.new(vs0[::-1]); bm.faces.new(vs1)
    for k in range(4):
        j = (k + 1) % 4
        bm.faces.new((vs0[k], vs0[j], vs1[j], vs1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


parts.append(fin("FinFrame", 0.0, 0.22, ROOF))
paint(parts[-1], zgrad(ROOF_LO, ROOF, HZ0, HZ0 + 3.5))
parts.append(fin("FinFace", -0.18, 0.36, BUTTER))
paint(parts[-1], zgrad(mix(BUTTER, CREAM, 0.1), BUTTER, HZ0, HZ0 + 3.5))

# --- pump rod + goo tub at the base -------------------------------------------------------
parts.append(cylinder("Rod", 0.13, TZ - 1.0, (0, 0, 1.0), METAL, segs=6))
paint(parts[-1], zgrad(METAL_LO, METAL_HI, 1, TZ))
TR, TH = 1.15, 1.15
parts.append(cylinder("Tub", TR, TH, (0, 0, 0), WOOD, segs=10, r_top=TR + 0.12))
paint(parts[-1], lambda co, n: shade(mix(WOOD_LO, WOOD_HI, co.z / TH), 0.93 if int((math.atan2(co.y, co.x) + 4) * 12 / math.tau) % 2 else 1))
parts.append(cylinder("TubHoop", TR + 0.1, 0.18, (0, 0, TH * 0.62), METAL, segs=10))
paint(parts[-1], zgrad(METAL_LO, METAL_HI, TH * 0.6, TH * 0.75))
gb = []
for k in range(6):
    a = k * math.tau / 6
    gb.append(Ball((0.45 * math.cos(a), 0.45 * math.sin(a), TH - 0.12), (0.7, 0.7, 0.14)))
gb.append(Ball((0, -TR - 0.02, TH - 0.05), (0.4, 0.22, 0.16)))
for s in range(6):   # spill down the front face (+ tub flare) into a ground puddle
    t = s / 5
    z = TH - 0.15 - t * (TH - 0.2)
    gb.append(Ball((0.05, -(TR + 0.12 * z / TH) - 0.04, z), (0.28 - 0.06 * t, 0.12, 0.2)))
for x, y, r in ((0.1, -1.7, 0.85), (-0.5, -2.1, 0.6), (0.7, -2.15, 0.5)):
    gb.append(Ball((x, y, 0.02), (r, r * 0.85, 0.13)))
tub_goo = metaball_mesh("TubGoo", gb, resolution=0.1, tris=190, clamp_z=0.0)
print("tub nm", tub_goo["nm"])
paint_goo(tub_goo, lambda co, n: (*mix(GOO, GOO_HI, 0.15 + 0.35 * max(0.0, n.z) * (1 if co.z > 0.5 else 0.6))[:3], 1.0))
parts.append(tub_goo)

finish("ranch_windmill", parts)
