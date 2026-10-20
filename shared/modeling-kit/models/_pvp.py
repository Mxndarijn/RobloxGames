# PvP gear helpers (not an asset): goo blasters and goo traps.
# Blasters: kit convention, barrel points -Y (front), Z up, pistol-grip bottom on z=0.
# Traps: lie on the ground (z=0), round footprint.
import math
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm

P = PALETTE
WOOD, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
CREAM, ROOF, ROOF_D = P["ranch_cream"], P["ranch_roof"], P["ranch_roof_dark"]
GOO, GOO_HI = P["ranch_goo"], P["ranch_goo_hi"]
BUTTER, METAL, PINK, LILAC = P["ranch_butter"], P["ranch_metal"], P["ranch_pink"], P["ranch_lilac"]
BRASS = mix(METAL, BUTTER, 0.45)
BRASS_HI = mix(BRASS, CREAM, 0.35)
PEWTER = mix(METAL, CREAM, 0.30)
GLOW = rgb(120, 255, 150)       # live goo (gameplay signal): neon green
GLOW_HI = rgb(210, 255, 220)

AX_Y = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0))).to_4x4()   # local z -> world -Y (barrel axis, forward)
AX_X = Matrix(((0, 0, 1), (0, 1, 0), (-1, 0, 0))).to_4x4()   # local z -> world +X


def col(c):
    return (*c[:3], 1.0)


def lathe(name, profile, M=None, segs=12, color_fn=None, phase=0.0, sx=1.0, sy=1.0):
    """Closed surface of revolution about local z. profile = [(r, z), ...]; r == 0 rows collapse to a pole.
    M: 4x4 placement (default identity). color_fn(row, seg, z_local) -> colour per face."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((sx * r * math.cos(phase + k * math.tau / segs),
                                        sy * r * math.sin(phase + k * math.tau / segs), z)) for k in range(segs)])
    faces = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            faces.append((bm.faces.new(vs), i, k))
    if len(rings[0]) > 1:
        f = bm.faces.new(rings[0][::-1]); faces.append((f, -1, 0))
    if len(rings[-1]) > 1:
        f = bm.faces.new(rings[-1]); faces.append((f, len(rings) - 1, 0))
    layer = bm.loops.layers.color.new("Col")
    for f, i, k in faces:
        z = f.calc_center_median().z
        c = color_fn(i, k, z) if color_fn else WOOD
        for lp in f.loops:
            lp[layer] = col(c)
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def torus(name, R, r, M=None, segs=16, rsegs=6, color_fn=None):
    """Closed torus in the local XY plane; color_fn(seg, rseg, local co) -> colour."""
    bm = bmesh.new()
    rings = []
    for k in range(segs):
        a = k * math.tau / segs
        ring = []
        for j in range(rsegs):
            b = j * math.tau / rsegs
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), r * math.sin(b))))
        rings.append(ring)
    layer = bm.loops.layers.color.new("Col")
    for k in range(segs):
        a, b = rings[k], rings[(k + 1) % segs]
        for j in range(rsegs):
            j1 = (j + 1) % rsegs
            f = bm.faces.new((a[j], b[j], b[j1], a[j1]))
            c = color_fn(k, j, f.calc_center_median()) if color_fn else METAL
            for lp in f.loops:
                lp[layer] = col(c)
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def rbox(name, size, pos=(0, 0, 0), lo=None, hi=None, bev=0.08, rot=(0, 0, 0), segs=1):
    """Bevelled box with a vertical gradient lo -> hi."""
    o = box(name, size, pos, lo or WOOD, rot=rot)
    if bev:
        bevel(o, bev, segments=segs, angle=30)
    if hi is not None:
        gradient(o, lo, hi)
    return o


def grad_fn(lo, hi, z0, z1):
    def f(i, k, z):
        t = min(1.0, max(0.0, (z - z0) / max(z1 - z0, 1e-6)))
        return mix(lo, hi, t)
    return f


def mat_at(pos, axis="z"):
    T = Matrix.Translation(Vector(pos))
    if axis == "-y":
        return T @ AX_Y
    if axis == "x":
        return T @ AX_X
    return T


def report_grip(parts, grip):
    """Call BEFORE finish(). Prints the grip point vs the origin finish() makes (bbox bottom centre) and vs the
    bbox centre (where Roblox centres a MeshPart), both in Roblox axes (X = x, Y = z, Z = -y)."""
    vs = [o.matrix_world @ v.co for o in parts for v in o.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    g = Vector(grip)
    bc = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    cc = (lo + hi) / 2
    rb = lambda d: tuple(round(x, 3) for x in (d.x, d.z, -d.y))
    print("GRIP from origin (bottom centre), Roblox XYZ:", rb(g - bc))
    print("GRIP from bbox centre, Roblox XYZ:", rb(g - cc), " bbox Roblox size:", rb(Vector((hi.x - lo.x, -(hi.y - lo.y), hi.z - lo.z))))


def splat(name, radius_fn, rows, segs=32, color_fn=None, pos=(0, 0, 0)):
    """Closed polar dome ("goo splat") standing on pos. radius_fn(theta) -> outline radius.
    rows = [(f, z), ...] from the centre (f = 0) to the rim (last row usually z = 0); f scales radius_fn.
    Flat bottom cap at the last row. color_fn(row, theta, vertex co) -> colour per corner."""
    bm = bmesh.new()
    rings = []
    for f, z in rows:
        if f <= 1e-6:
            rings.append([bm.verts.new((pos[0], pos[1], pos[2] + z))])
        else:
            ring = []
            for k in range(segs):
                a = k * math.tau / segs
                r = f * radius_fn(a)
                ring.append(bm.verts.new((pos[0] + r * math.cos(a), pos[1] + r * math.sin(a), pos[2] + z)))
            rings.append(ring)
    faces = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            vs = (a[0], b[k], b[k1]) if len(a) == 1 else (a[k], b[k], b[k1], a[k1])
            faces.append((bm.faces.new(vs), i, (k + 0.5) * math.tau / segs))
    cap = bm.faces.new(rings[-1][::-1])
    faces.append((cap, -1, 0.0))
    layer = bm.loops.layers.color.new("Col")
    for f, i, th in faces:  # per corner (vertex position): smooth gradients, no terraces between rows
        for lp in f.loops:
            lp[layer] = col(color_fn(i, th, lp.vert.co) if color_fn else GOO)
    bmesh.ops.triangulate(bm, faces=[cap])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def mark_smooth(o, flag=True):
    """Face attribute keep_smooth (survives the join); flat bottom caps stay flat."""
    a = o.data.attributes.get("keep_smooth") or o.data.attributes.new("keep_smooth", "INT", "FACE")
    for p, d in zip(o.data.polygons, a.data):
        d.value = int(flag and p.normal.z > -0.9)
    return o


def ship(name, parts):
    """finish() with per-face smooth shading: goo parts marked by mark_smooth() export smooth (FBX normals),
    wood/metal stays faceted (LESSONS pet_mounts: finish() clears smooth flags)."""
    for o in parts:
        if "keep_smooth" not in o.data.attributes:
            mark_smooth(o, False)
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    o["smooth_normals"] = 1
    return o


def bubble(name, r, pos, lo, hi, squash=1.0):
    """Goo bubble: subdiv-2 icosphere with a vertical gradient (place it sunk ~35 % into the goo)."""
    o = blob(name, r, pos, lo, subdiv=2, squash=(1, 1, squash), jitter=0.0)
    return gradient(o, lo, hi)
