"""Eye audit: build a pool slime with its rig, pose it the way the game's ui/SlimeBones does (eyes in and lids
out for a blink, eyes out for a surprised face) and raycast it from the front. Prints one AUDIT json line:
visible eye / lid area (stud^2) per pose and how far the eye stack stands in front of the skin (studs).
A shut pose with lid ~0 is an eyeless slime; a surprised stand far over the open one is a sticking-out eye.

    blender -b --factory-startup -P tools/slime_eye_audit.py -- models/pool/slime_froggo.py
AUDIT_SHARE / AUDIT_POP override SlimeBones.EYE_SHARE / POP_OUT."""
import sys, os, runpy, json, bpy, bmesh, io, contextlib
from mathutils import Vector
from mathutils.bvhtree import BVHTree
KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KIT); os.chdir(KIT)
os.environ["SLIME_RIG"] = "1"; os.environ["SLIME_PREVIEW"] = "1"
model = sys.argv[sys.argv.index("--") + 1]
SHARE = float(os.environ.get("AUDIT_SHARE", "0.25"))
EYE_IN, LID_OUT, POP = 0.13, 0.165, float(os.environ.get("AUDIT_POP", "0.25"))
bpy.ops.wm.read_factory_settings(use_empty=True)
with contextlib.redirect_stdout(io.StringIO()):
    runpy.run_path(model, run_name="__main__")
o = [x for x in bpy.data.objects if x.type == "MESH" and x.vertex_groups][0]
gi = {g.index: g.name for g in o.vertex_groups}
me = o.data
we = [0.0] * len(me.vertices); wl = [0.0] * len(me.vertices)
for v in me.vertices:
    for g in v.groups:
        if gi[g.group] == "Eyes": we[v.index] = g.weight
        if gi[g.group] == "Lids": wl[v.index] = g.weight
res = {"name": os.path.basename(model)[6:-3]}
eye_v = [i for i, w in enumerate(we) if w > 0]
if not eye_v:
    res["note"] = "no Eyes weights"; print("AUDIT " + json.dumps(res)); sys.exit(0)
role = []  # per face: 'e' eye, 'l' lid, 'o' other
for p in me.polygons:
    vs = p.vertices
    role.append("e" if all(we[i] > 0 for i in vs) else "l" if all(wl[i] > 0 for i in vs) else "o")
co0 = [v.co.copy() for v in me.vertices]
xs = [co0[i].x for i in eye_v]; zs = [co0[i].z for i in eye_v]
x0, x1, z0, z1 = min(xs) - 0.05, max(xs) + 0.05, min(zs) - 0.05, max(zs) + 0.05
N = 70
def pose(closed, pop):
    eIn = EYE_IN / SHARE; lOut = LID_OUT / SHARE
    pts = []
    for i, c in enumerate(co0):
        dy = we[i] * eIn * (closed - POP * pop) - wl[i] * lOut * closed  # +y = into the body (front is -y)
        pts.append(Vector((c.x, c.y + dy, c.z)))
    polys = [list(p.vertices) for p in me.polygons]
    full = BVHTree.FromPolygons(pts, polys)
    other_idx = [k for k, r in enumerate(role) if r == "o"]
    skin = BVHTree.FromPolygons(pts, [polys[k] for k in other_idx])
    eye_hits = lid_hits = 0; stand = []
    for a in range(N):
        for b in range(N):
            x = x0 + (x1 - x0) * (a + 0.5) / N; z = z0 + (z1 - z0) * (b + 0.5) / N
            org = Vector((x, -20, z))
            loc, n, idx, d = full.ray_cast(org, Vector((0, 1, 0)))
            if idx is None: continue
            r = role[idx]
            if r == "e":
                eye_hits += 1
                h = skin.ray_cast(org, Vector((0, 1, 0)))
                if h[0] is not None: stand.append(h[3] - d)
            elif r == "l":
                lid_hits += 1
    cell = (x1 - x0) * (z1 - z0) / (N * N)
    stand.sort()
    return {"eye": round(eye_hits * cell, 4), "lid": round(lid_hits * cell, 4),
            "stand_max": round(stand[-1], 3) if stand else None,
            "stand_p90": round(stand[int(len(stand) * 0.9)], 3) if stand else None}
res["open"] = pose(0, 0); res["closed"] = pose(1, 0); res["pop"] = pose(0, 1)
res["H"] = round(max(c.z for c in co0), 2)
print("AUDIT " + json.dumps(res))
