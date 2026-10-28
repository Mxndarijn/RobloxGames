# Shared helpers for the Exclusive Shop concepts (not an asset): lathe, per-face paint, goo bands with drips,
# FBX import of kit meshes (the trophy slime), a raycast slime face and small gold / bulb pieces.
import math
import os
import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from lib import *
from models._phoenix_ranch import *

LILAC = PALETTE["ranch_lilac"]
LILAC_LO = mix(LILAC, ROOF_D, 0.3)
LILAC_HI = mix(LILAC, CREAM, 0.3)
GOLD = rgb(252, 204, 80)
GOLD_LO = rgb(232, 146, 46)
GOLD_HI = rgb(255, 236, 160)
SG, SG_LO, SG_HI = rgb(244, 168, 36), rgb(214, 116, 30), rgb(255, 222, 110)  # deep trophy gold for big surfaces
BUTTER_LO = mix(BUTTER, GOLD_LO, 0.45)
PLAZA = PALETTE["ranch_plaza"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)
PLANK = mix(WOOD, CREAM, 0.12)
GOO_LO = mix(GOO, rgb(70, 170, 130), 0.5)
GLASS = rgb(214, 244, 236)
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out")
L = Vector((-0.45, -0.65, 0.6)).normalized()


def lathe(name, prof, pos, segs=24, col=CREAM, phase=0.0):
    bm = bmesh.new()
    x0, y0, z0 = pos
    rows = []
    for r, z in prof:
        if r < 1e-4:
            rows.append([bm.verts.new((x0, y0, z0 + z))])
        else:
            rows.append([bm.verts.new((x0 + math.cos(i * math.tau / segs + phase) * r, y0 + math.sin(i * math.tau / segs + phase) * r, z0 + z)) for i in range(segs)])
    for a, b in zip(rows, rows[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    for row in (rows[0], rows[-1]):
        if len(row) > 2:
            bm.faces.new(row)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


def paint(o, fn):
    lay = o.data.color_attributes["Col"]
    for p in o.data.polygons:
        col = fn(p.center, p.normal)
        for li in p.loop_indices:
            lay.data[li].color = (*col[:3], 1.0)


def goo_ring(name, cx, cy, z0, Rr, n=48, seed=4, drip=(0.7, 2.0), thick=0.55):
    """Closed goo band poured over a round edge at radius Rr / height z0, with tapered drips hanging down."""
    import random
    rnd = random.Random(seed)
    tips = {}
    k = 0
    while k < n:
        tips[k] = rnd.uniform(*drip)
        k += rnd.choice((5, 6, 6, 7))
    d = [0.0] * n
    for i in range(n):
        for t, L in tips.items():
            gap = min((i - t) % n, (t - i) % n)
            d[i] = max(d[i], L * (1.0, 0.8, 0.3)[gap] if gap < 3 else 0.0)   # U-shaped, round-tipped drips
    loop = lambda di: [(Rr - thick, 0.62), (Rr + 0.3, 0.48), (Rr + 0.55, 0.05), (Rr + 0.58, -0.25 - di),
                       (Rr + 0.2, -0.32 - di * 0.92), (Rr - thick, 0.2)]
    bm = bmesh.new()
    rings = []
    for i in range(n):
        a = i * math.tau / n
        rings.append([bm.verts.new((cx + math.cos(a) * r, cy + math.sin(a) * r, z0 + z)) for r, z in loop(d[i])])
    m = len(rings[0])
    for i in range(n):
        A, B = rings[i], rings[(i + 1) % n]
        for j in range(m):
            jj = (j + 1) % m
            bm.faces.new((A[j], A[jj], B[jj], B[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, GOO)
    paint(o, lambda c, nrm: mix(GOO, GOO_HI, 0.55) if nrm.z > 0.8 else (GOO if c.z > z0 - 0.2 else mix(GOO_LO, GOO, min(1, max(0, (c.z - z0 + 2.2) / 2.0)))))
    return o


def _load(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), axis_forward="-Z", axis_up="Y")
    got = []
    for o in set(bpy.data.objects) - before:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
            continue
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.parent = None
        bpy.context.view_layer.update()
        o.data.transform(o.matrix_world)
        o.matrix_world.identity()
        o.vertex_groups.clear()
        if o.data.shape_keys:
            o.shape_key_clear()
        o.data.materials.clear()
        if "Col" not in o.data.color_attributes:
            for ca in list(o.data.color_attributes):
                ca.name = "Col"
                break
        if "Col" not in o.data.color_attributes:
            o.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for extra in [c for c in o.data.color_attributes if c.name != "Col"]:
            o.data.color_attributes.remove(extra)
        got.append(o)
    return got


def import_fbx(names, scale, pos, col_fns):
    """Import several FBXs that share one frame (body + face decal); fit them by the FIRST one's bbox.
    col_fns[i] = None keeps that mesh's own vertex colours."""
    groups = [_load(n) for n in names]
    vs = [v.co.copy() for o in groups[0] for v in o.data.vertices]
    span = max(max(v.x for v in vs) - min(v.x for v in vs), max(v.z for v in vs) - min(v.z for v in vs))
    k = scale / span
    cx = (min(v.x for v in vs) + max(v.x for v in vs)) / 2
    cy = (min(v.y for v in vs) + max(v.y for v in vs)) / 2
    z0 = min(v.z for v in vs)
    out = []
    for objs, fn in zip(groups, col_fns):
        for o in objs:
            o.data.transform(Matrix.Translation(pos) @ Matrix.Scale(k, 4) @ Matrix.Translation((-cx, -cy, -z0)))
            if fn:
                paint(o, fn)
            out.append(o)
    return out


def glass(o, t=0.55):
    """Mark an object as see-through glass for the Roblox-look preview (Transparency on its own MeshPart in game)."""
    o["rbx_transparency"] = t
    return o


def ring(name, r, z, thick=0.32, pos=(0, 0), col=None, segs=28):
    """A round gold band (a closed tube round a circle) at radius r, height z."""
    x, y = pos
    pts = [(x + math.cos(i * math.tau / segs) * r, y + math.sin(i * math.tau / segs) * r, z) for i in range(segs + 1)]
    o = tube(name, pts, [thick] * len(pts), col or GOLD, segs=6)
    paint(o, lambda c, n: GOLD_HI if n.z > 0.6 else (GOLD_LO if n.z < -0.3 else (col or GOLD)))
    return o


def bulb(name, pos, r=0.2):
    return blob(name, r, pos, mix(BUTTER, CREAM, 0.4), subdiv=1, jitter=0)


def trophy_slime(cx, cy, z, size=3.8, decim=0.55):
    """The game's own slime (slime_base FBX) in deep trophy gold with the crown accessory and a raycast happy face."""
    def gold_shine(c, n):
        d = n.dot(L)
        base = mix(SG_LO, SG, min(1, max(0, (c.z - z - 0.4) / (size * 0.7))))
        return mix(base, SG_HI, 0.75) if d > 0.8 else (mix(base, SG_LO, 0.5) if d < -0.1 else base)
    slime = import_fbx(["slime_base"], size, (cx, cy, z), [gold_shine])
    for o in slime:
        decimate(o, decim)
    out = list(slime)
    sz = max(v.co.z for o in slime for v in o.data.vertices)
    out += import_fbx(["slime_acc_crown"], size * 0.55, (cx, cy - 0.04 * size, sz - 0.12 * size), [None])
    bm = bmesh.new()
    for o in slime:
        bm.from_mesh(o.data)
    tree = BVHTree.FromBMesh(bm)
    k = size / 3.8

    def on_face(dx, dz, lift=0.05):
        hit = tree.ray_cast(Vector((cx + dx * k, cy - 50, z + (1.0 + dz) * k)), Vector((0, 1, 0)))
        return hit[0] + hit[1] * lift * k
    eye = rgb(70, 46, 40)
    for sx in (-1, 1):
        out.append(blob(f"Eye{sx}", 0.3 * k, tuple(on_face(sx * 0.62, 1.35)), eye, subdiv=2, squash=(0.8, 0.35, 1.15), jitter=0))
        out.append(blob(f"EyeHi{sx}", 0.1 * k, tuple(on_face(sx * 0.62 - 0.08, 1.5, 0.2)), CREAM, subdiv=1, squash=(1, 0.5, 1), jitter=0))
        out.append(blob(f"Blush{sx}", 0.24 * k, tuple(on_face(sx * 1.05, 0.95, 0.03)), mix(PINK, GOLD, 0.25), subdiv=1, squash=(1.3, 0.3, 0.75), jitter=0))
    smile = [tuple(on_face(t * 0.42, 0.95 - 0.22 * (1 - t * t), 0.04)) for t in ((i / 6) * 2 - 1 for i in range(7))]
    out.append(tube("Smile", smile, [0.08 * k] * 7, eye, segs=5))
    return out
