# slime_fountain_emerge: OPTIONAL second MeshPart for the slime_fountain centrepiece: the gumdrop
# slimes welling up out of the goo crown (A, B, C) + one setting off down the slide (D), with eyes.
# Split out of slime_fountain.py (2026-10-15) so the fountain mesh stays static and Phoenix can place,
# bob or hide these separately.
#
# Built in the SAME silo space as slime_fountain.py (silo axis at the origin, z=0 ground). finish()
# re-centres each mesh on its own bbox, so the script prints the offset that puts this mesh back
# on the fountain: EMERGE_OFFSET = emerge bbox centre - fountain bbox centre (MeshParts are
# positioned by their bbox centre). Kit axes (x, y, z up) and Roblox axes (X = x, Y = z,
# Z = -y; the kit FBX is written forward -Z, up Y) for an unrotated fountain. Per-slime base
# points (relative to the fountain bbox centre) are printed too, for animating them one by one.
import math
import bmesh, bpy
from mathutils import Euler, Matrix, Vector
from lib import *
from models._slime import radius as slime_radius, TIP as SLIME_TIP
import models.slime_fountain as sf

P = PALETTE
CREAM, WOOD_D = P["ranch_cream"], P["ranch_wood_dark"]
ZP = sf.ZP


def gumdrop(name, pos, scale, color, tilt=(0, 0, 0)):
    bm = bmesh.new()
    segs = 10
    zs = [0.0, 0.35, 1.0, 1.7, 2.35, 2.8]
    rings = [[bm.verts.new((math.cos(k * math.tau / segs) * slime_radius(z) * scale,
                            math.sin(k * math.tau / segs) * slime_radius(z) * scale, z * scale))
              for k in range(segs)] for z in zs]
    top = bm.verts.new((0, 0, SLIME_TIP * scale))
    bot = bm.verts.new((0, 0, 0))
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((a[k], a[j], b[j], b[k]))
    for k in range(segs):
        j = (k + 1) % segs
        bm.faces.new((rings[-1][k], rings[-1][j], top))
        bm.faces.new((rings[0][j], rings[0][k], bot))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    sm = sf.smooth_layer(bm)
    for f in bm.faces:
        f.smooth = True
        f[sm] = 1
        for lp in f.loops:
            lp[col] = mix(shade(color, 0.9), mix(color, CREAM, 0.35), min(1, lp.vert.co.z / (SLIME_TIP * scale)))
    m = Matrix.Translation(Vector(pos)) @ Euler([math.radians(x) for x in tilt]).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    o = obj_from_bm(name, bm)
    eyes = []
    for s in (-1, 1):
        e = m @ Vector((s * 0.5 * scale, -slime_radius(1.65) * scale + 0.08, 1.65 * scale))
        eyes.append(blob(f"{name}Eye{s}", 0.22 * scale, e, WOOD_D, subdiv=1, jitter=0, squash=(0.8, 0.6, 1.2)))
    return [o] + eyes


def slimes(pts):
    """(parts, {name: base point}) in silo space. A sits in the crown's centre bubble, B and C on the
    two front ring bubbles (sunk ~1 stud into the goo, tilted outward), D at the slide head."""
    out, bases = [], {}
    i = next(i for i, p in enumerate(pts) if p.xy.length > 12.5)  # just out of the basin
    d = (pts[i + 1] - pts[i - 1]).normalized()
    yaw = math.degrees(math.atan2(d.x, -d.y))
    for name, pos, scale, color, tilt in (
            ("SlimeA", (0.3, 0.1, ZP + sf.CROWN_TOP - 1.1), 1.6, P["ranch_pink"], (0, 0, -12)),
            ("SlimeB", (3.0, -3.4, ZP + 3.6), 1.35, P["ranch_lilac"], (-16, 12, 28)),
            ("SlimeC", (-2.3, -3.7, ZP + 3.6), 1.25, P["ranch_butter"], (-14, -18, -40)),
            ("SlimeD", tuple(pts[i] + Vector((0, 0, 0.1))), 1.25, P["ranch_lilac"], (0, 0, yaw))):
        out += gumdrop(name, pos, scale, color, tilt)
        bases[name] = Vector(pos)
    for o in out:
        o.data.attributes.new("keep_smooth", "INT", "FACE") if "keep_smooth" not in o.data.attributes else None
    return out, bases


def bbox3(objs):
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def rbx(v):
    return f"({v.x:.2f}, {v.z:.2f}, {-v.y:.2f})"


if __name__ == "__main__":
    fparts, pts = sf.build()  # the fountain's bbox in silo space, then throw it away
    flo, fhi = bbox3(fparts)
    for o in fparts:
        bpy.data.objects.remove(o, do_unlink=True)
    fc = (flo + fhi) / 2
    parts, bases = slimes(pts)
    lo, hi = bbox3(parts)
    off = (lo + hi) / 2 - fc
    o = finish("slime_fountain_emerge", parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    print(f"EMERGE_OFFSET (emerge bbox centre - fountain bbox centre): kit x {off.x:.2f}, y {off.y:.2f}, "
          f"z {off.z:.2f} studs; Roblox (X, Y, Z) {rbx(off)}")
    for n, b in bases.items():
        r = b - fc
        print(f"EMERGE_BASE {n}: kit ({r.x:.2f}, {r.y:.2f}, {r.z:.2f}); Roblox {rbx(r)} from the fountain bbox centre")
