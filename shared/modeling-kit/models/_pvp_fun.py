"""Shared builders for the PvP fun held items (models/pvp_fun_*.py).

Every builder returns a closed shell (0 non-manifold edges) painted per face in "Col", with a
"keep_smooth" face attribute so `ship()` can restore smooth shading after `finish()` (which sets
every face flat). Parts are built in a local frame (axis = +Z) and placed with `place(pos, rot)`.

Held-tool convention (LESSONS ranch_bat): upright items have their long axis on Z with the hand
end at z=0; launchers point their muzzle to -Y (the kit's front) with a pistol grip underneath.
`ship(name, parts, grip)` prints the grip point relative to the final origin (bbox bottom-centre)
and as a Roblox offset from the MeshPart centre (Roblox X, Y, Z = Blender X, Z, -Y).
"""
import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

from lib import PALETTE, finish, mix, rgb
from lib.shapes import obj_from_bm

P = PALETTE
WOOD, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
CREAM, RED, RED_D = P["ranch_cream"], P["ranch_roof"], P["ranch_roof_dark"]
GOO, GOO_HI = P["ranch_goo"], P["ranch_goo_hi"]
PINK, LILAC, BUTTER, METAL = P["ranch_pink"], P["ranch_lilac"], P["ranch_butter"], P["ranch_metal"]
SKY = rgb(140, 200, 240)  # party blue (soft, warm-ish; no cold blue-grey)
WHITE = rgb(240, 247, 255)  # cool white (LESSONS: pure white reads cream under the warm sun)


def place(pos=(0, 0, 0), rot=(0, 0, 0)):
    return Matrix.Translation(Vector(pos)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()


def _paint(bm, faces, colour, smooth):
    col = bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.new("keep_smooth")
    bm.faces.ensure_lookup_table()
    for fi, key in enumerate(faces):
        f = bm.faces[fi]
        f[sm] = int(smooth)
        c = colour(*key, f.calc_center_median()) if callable(colour) else colour
        for lp in f.loops:
            lp[col] = (*c[:3], 1.0)


def rings_shell(name, rings, colour, smooth=True, M=None, poles=(None, None), cap=(True, True)):
    """Closed shell through rings (each a list of N 3D points). colour(i, k, centre) or one RGBA;
    band i: 0 = first cap, len(rings) = last cap. A pole point (or the ring centroid) closes each end."""
    bm = bmesh.new()
    N = len(rings[0])
    R = [[bm.verts.new(p) for p in r] for r in rings]
    keys = []

    def cen(r):
        return sum((Vector(p) for p in r), Vector()) / len(r)

    b = bm.verts.new(poles[0] if poles[0] is not None else cen(rings[0]))
    for k in range(N):
        bm.faces.new((b, R[0][(k + 1) % N], R[0][k]))
        keys.append((0, k))
    for i, (r0, r1) in enumerate(zip(R, R[1:])):
        for k in range(N):
            j = (k + 1) % N
            bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
            keys.append((i + 1, k))
    t = bm.verts.new(poles[1] if poles[1] is not None else cen(rings[-1]))
    for k in range(N):
        bm.faces.new((t, R[-1][k], R[-1][(k + 1) % N]))
        keys.append((len(R), k))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    _paint(bm, keys, colour, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def lathe(name, profile, colour, segs=16, smooth=True, M=None, phase=0.0, rx=1.0, ry=1.0):
    """Surface of revolution around local Z. profile: [(r, z)] bottom -> top; an end with r=0 is a
    pole, an end with r>0 gets a flat cap to the axis. colour(i, k, centre) with i = profile band."""
    pts = list(profile)
    poles = [None, None]
    if pts[0][0] <= 1e-6:
        poles[0] = (0, 0, pts[0][1])
        pts = pts[1:]
    else:
        poles[0] = (0, 0, pts[0][1])
    if pts[-1][0] <= 1e-6:
        poles[1] = (0, 0, pts[-1][1])
        pts = pts[:-1]
    else:
        poles[1] = (0, 0, pts[-1][1])
    rings = [[(r * rx * math.cos(phase + k * math.tau / segs), r * ry * math.sin(phase + k * math.tau / segs), z)
              for k in range(segs)] for r, z in pts]
    return rings_shell(name, rings, colour, smooth, M, poles)


def torus(name, R, r, colour, segs=20, rsegs=8, smooth=True, M=None):
    """Torus in the local XY plane. colour(i, k, centre): i = around-tube index, k = around-ring index."""
    bm = bmesh.new()
    V = [[bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
          for b in (j * math.tau / rsegs for j in range(rsegs))] for a in (k * math.tau / segs for k in range(segs))]
    keys = []
    for k in range(segs):
        k1 = (k + 1) % segs
        for j in range(rsegs):
            j1 = (j + 1) % rsegs
            bm.faces.new((V[k][j], V[k1][j], V[k1][j1], V[k][j1]))
            keys.append((j, k))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    _paint(bm, keys, colour, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def sweep(name, points, radii, colour, segs=8, smooth=True):
    """Tube along a polyline with parallel-transported rings (no twist), capped. colour(i, k, centre)."""
    pts = [Vector(p) for p in points]
    rings = []
    prev_n = None
    for i, (p, rad) in enumerate(zip(pts, radii)):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        if prev_n is None:
            a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            n = d.cross(a).normalized()
        else:
            n = (prev_n - d * prev_n.dot(d)).normalized()
        prev_n = n
        bnorm = d.cross(n)
        rings.append([tuple(p + (n * math.cos(k * math.tau / segs) + bnorm * math.sin(k * math.tau / segs)) * rad)
                      for k in range(segs)])
    return rings_shell(name, rings, colour, smooth, poles=(tuple(pts[0]), tuple(pts[-1])))


def box_part(name, size, colour, M=None, bevel_w=0.0):
    """Bevelled box (flat shaded) with one colour or colour(0, 0, centre)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel_w > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel_w, segments=1, affect="EDGES", profile=0.5)
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    _paint(bm, [(0, 0)] * len(bm.faces), colour, False)
    return obj_from_bm(name, bm)


def ico(name, radius, colour, subdiv=2, M=None, squash=(1, 1, 1), smooth=True, spikes=1.0):
    """Icosphere; spikes > 1 pushes the 12 valence-5 corners out (a cartoon spark / star burst)."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    if spikes != 1.0:
        for v in bm.verts:
            if len(v.link_edges) == 5:
                v.co *= spikes
    bmesh.ops.scale(bm, vec=Vector(squash), verts=bm.verts)
    if M is not None:
        bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    _paint(bm, [(0, 0)] * len(bm.faces), colour, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def ship(name, parts, grip):
    """finish() -> restore smooth flags -> print tris per part, size and the grip offset."""
    bpy.context.view_layer.update()
    per = " ".join("%s=%d" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons)) for o in parts)
    lo = Vector((min(min((o.matrix_world @ v.co)[i] for v in o.data.vertices) for o in parts) for i in range(3)))
    hi = Vector((max(max((o.matrix_world @ v.co)[i] for v in o.data.vertices) for o in parts) for i in range(3)))
    base = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    g = Vector(grip) - base
    h = hi.z - lo.z
    o = finish(name, parts)
    a = o.data.attributes.get("keep_smooth")
    if a is not None:
        for p, d in zip(o.data.polygons, a.data):
            p.use_smooth = bool(d.value)
        o.data.attributes.remove(a)
    o["smooth_normals"] = 1
    print("PVP_PARTS %s %s" % (name, per))
    print("PVP_GRIP %s blender_from_bottom_centre=(%.2f, %.2f, %.2f) roblox_from_mesh_centre=(%.2f, %.2f, %.2f)"
          % (name, g.x, g.y, g.z, g.x, g.z - h / 2, -g.y))
    return o
