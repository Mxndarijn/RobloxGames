# Shared builder for the "Knockback" PvP glove line (not an asset): pvp_knock_glove_1..5 call glove().
# A cartoon boxing/slapping glove held in one hand, built like ranch_bat (held tool = one upright mesh):
#   long axis = Blender Z (Roblox Y), cuff opening at z = 0 (origin bottom centre), fist at the top,
#   back of the hand (knuckles, emblems, gem) faces -Y (the sheet's front view), thumb on -X (a right hand).
# Mitt = metaballs (palm + fist + knuckle roll + thumb fused into one smooth skin, lib/goo.py), cuff = closed lathe
# with per-row colours. Smooth shaded (keep_smooth face attribute -> o["smooth_normals"] = 1), vertex colours 'Col'.
# Grip (where the R15 hand sits, inside the cuff): x = 0, y = 0, z = GRIP_Z * scale above the cuff bottom.
# ship() prints it as GLOVE ... grip_from_bbox_centre_rbx=[gx, gy, gz] (Roblox axes; a MeshPart is centred on its bbox).
# Tool.Grip (derived from the R15 RightGripAttachment like tools/bat_in_hand.py, NOT checked in Studio yet):
#   upright like the bat (fist up):              Grip = CFrame.new(gx, gy, gz)
#   punch pose (fist forward, back of hand up):  Grip = CFrame.new(gx, gy, gz) * CFrame.Angles(math.rad(90), 0, 0)
# Decorations (fuse, crown, gem) are placed so they read in both poses.
import math
import bmesh, bpy
from mathutils import Matrix, Quaternion, Vector
from lib import *
from lib.goo import Ball, frame_quat, metaball_mesh, paint_goo
from lib.shapes import obj_from_bm
from mathutils.bvhtree import BVHTree

GRIP_Z = 0.50  # hand centre above the cuff bottom at scale 1 (cuff top 0.62, mitt from ~0.55)


def clamp(t, lo=0.0, hi=1.0):
    return max(lo, min(hi, t))


def ramp(cols, t):
    """piecewise-linear colour ramp: cols = [(stop, colour), ...] ascending."""
    if t <= cols[0][0]:
        return cols[0][1]
    for (t0, c0), (t1, c1) in zip(cols, cols[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return cols[-1][1]


def rgba(c):
    return (c[0], c[1], c[2], 1.0)


def _faces_out(bm, faces_cols, smooth=True):
    """faces_cols = [(face, colour)] in face creation order (recalc_face_normals kills the face refs, so faces are
    looked up again by index)."""
    cols = [c for _, c in faces_cols]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    col = bm.loops.layers.color.new("Col")
    sm = bm.faces.layers.int.new("keep_smooth")
    for i, c in enumerate(cols):
        f = bm.faces[i]
        f.smooth = smooth
        f[sm] = int(smooth)
        for lp in f.loops:
            lp[col] = rgba(c)


# ------------------------------------------------------------------ lathe (cuff, studs, crown band)
def lathe(name, profile, colour, segs=16, pos=(0, 0, 0), sx=1.0, sy=1.0, smooth=True, phase=0.0, rot=None):
    """Closed surface of revolution. profile = [(r, z), ...] bottom -> top, r = 0 rows close the ends.
    colour(row_index, k, z_mid) -> colour per face (rows are the profile segments). sx/sy squash the plan."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * sx * math.cos(phase + k * math.tau / segs),
                                        r * sy * math.sin(phase + k * math.tau / segs), z)) for k in range(segs)])
    fc = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        zm = (profile[i][1] + profile[i + 1][1]) / 2
        for k in range(segs):
            k1 = (k + 1) % segs
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            fc.append((bm.faces.new(vs), colour(i, k, zm)))
    m = Matrix.Translation(Vector(pos))
    if rot is not None:
        m = m @ rot.to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    _faces_out(bm, fc, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def torus(name, R, r, colour, pos=(0, 0, 0), segs=16, rsegs=6, sx=1.0, sy=1.0, rot=None, smooth=True):
    """Closed torus in the XY plane (ring radius R, tube r); colour(k, j) per face."""
    bm = bmesh.new()
    rings = []
    for k in range(segs):
        a = k * math.tau / segs
        c, s = math.cos(a), math.sin(a)
        ring = []
        for j in range(rsegs):
            b = j * math.tau / rsegs
            rr = R + r * math.cos(b)
            ring.append(bm.verts.new((rr * c * sx, rr * s * sy, r * math.sin(b))))
        rings.append(ring)
    fc = []
    for k in range(segs):
        a, b2 = rings[k], rings[(k + 1) % segs]
        for j in range(rsegs):
            j1 = (j + 1) % rsegs
            fc.append((bm.faces.new((a[j], b2[j], b2[j1], a[j1])), colour(k, j)))
    m = Matrix.Translation(Vector(pos))
    if rot is not None:
        m = m @ rot.to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    _faces_out(bm, fc, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def sweep(name, pts, radius, colour, segs=6, smooth=True):
    """Closed tube along a polyline (helix spring, fuse); constant radius, flat end caps; colour(i) per segment."""
    bm = bmesh.new()
    P = [Vector(p) for p in pts]
    rings = []
    up = Vector((0, 0, 1))
    for i, p in enumerate(P):
        d = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        side = d.cross(up)
        if side.length < 1e-4:
            side = d.cross(Vector((1, 0, 0)))
        side.normalize()
        nrm = side.cross(d).normalized()
        rad = radius(i / (len(P) - 1)) if callable(radius) else radius
        rings.append([bm.verts.new(p + (side * math.cos(k * math.tau / segs) + nrm * math.sin(k * math.tau / segs)) * rad)
                      for k in range(segs)])
    fc = []
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(segs):
            k1 = (k + 1) % segs
            fc.append((bm.faces.new((a[k], a[k1], b[k1], b[k])), colour(i / (len(rings) - 1))))
    fc.append((bm.faces.new(list(reversed(rings[0]))), colour(0.0)))
    fc.append((bm.faces.new(rings[-1]), colour(1.0)))
    _faces_out(bm, fc, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def slab(name, pts, depth, colour_fn, frame=Matrix.Identity(4), bevel_w=0.035, smooth=False):
    """Polygon pts (u, v) extruded `depth` along local w (centred), bevelled, then placed by `frame` (4x4: local
    u, v, w -> world). colour_fn(world centre, world normal) per face. Flat shaded: crisp emblem/fin edges."""
    bm = bmesh.new()
    vs = [bm.verts.new((u, v, -depth / 2)) for u, v in pts]
    f = bm.faces.new(vs)
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    vv = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, depth)), verts=vv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel_w:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel_w, segments=1, profile=0.5, affect="EDGES")
    bmesh.ops.triangulate(bm, faces=[x for x in bm.faces if len(x.verts) > 4])
    bmesh.ops.transform(bm, matrix=frame, verts=bm.verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    fc = [(x, colour_fn(x.calc_center_median(), x.normal)) for x in bm.faces]
    _faces_out(bm, fc, smooth)
    return obj_from_bm(name, bm, smooth=smooth)


def gem(name, r, h_top, h_bot, colour_fn, frame, segs=8):
    """Faceted brilliant-cut gem: table (top ring), girdle, pavilion point, flat shaded; local +w = up out of the
    surface. colour_fn(zone) with zone in table/crown/pavilion."""
    bm = bmesh.new()
    girdle = [bm.verts.new((r * math.cos(k * math.tau / segs + math.pi / segs), r * math.sin(k * math.tau / segs + math.pi / segs), 0)) for k in range(segs)]
    table = [bm.verts.new((0.55 * r * math.cos(k * math.tau / segs), 0.55 * r * math.sin(k * math.tau / segs), h_top)) for k in range(segs)]
    tip = bm.verts.new((0, 0, -h_bot))
    fc = [(bm.faces.new(table), colour_fn("table"))]
    for k in range(segs):
        k1 = (k + 1) % segs
        fc.append((bm.faces.new((girdle[k], girdle[k1], table[k1])), colour_fn("crown")))
        fc.append((bm.faces.new((girdle[k], table[k1], table[k])), colour_fn("crown2")))
        fc.append((bm.faces.new((girdle[k1], girdle[k], tip)), colour_fn("pavilion")))
    bmesh.ops.transform(bm, matrix=frame, verts=bm.verts)
    _faces_out(bm, fc, smooth=False)
    return obj_from_bm(name, bm)


def frame_at(origin, w, up_hint=Vector((0, 0, 1))):
    """4x4 whose local w (z) = w, local v (y) ~ up_hint, at origin."""
    w = Vector(w).normalized()
    u = up_hint.cross(w)
    if u.length < 1e-4:
        u = Vector((1, 0, 0))
    u.normalize()
    v = w.cross(u).normalized()
    m = Matrix((u, v, w)).transposed().to_4x4()
    m.translation = Vector(origin)
    return m


def surface(o, origin, direction):
    """first hit of a ray on object o (identity matrix): (location, face normal) or (None, None)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    t = BVHTree.FromBMesh(bm)
    hit = t.ray_cast(Vector(origin), Vector(direction).normalized())
    bm.free()
    return hit[0], hit[1]


def on_surface(o, origin, direction, sink=0.0):
    """(point, quaternion with +Z along the surface normal) where a ray hits o, sunk `sink` along -normal."""
    p, n = surface(o, origin, direction)
    assert p is not None, ("ray missed", origin, direction)
    return p - n * sink, n.to_track_quat("Z", "Y"), n


def star_pts(r_out, r_in, n=5, phase=math.pi / 2):
    return [((r_out if i % 2 == 0 else r_in) * math.cos(phase + i * math.pi / n),
             (r_out if i % 2 == 0 else r_in) * math.sin(phase + i * math.pi / n)) for i in range(2 * n)]


# ------------------------------------------------------------------ mitt
CUFF_TOP = 0.80  # at scale 1


def mitt_balls(S=1.0, fist=1.0, lift=0.0):
    """Metaball elements of the glove body (back of the hand -Y, fingers curl over to +Y at the top) at scale S.
    fist > 1 makes the striking end chunkier (higher tiers); lift raises it (a longer glove)."""
    L = lift
    els = [
        Ball((0, 0.03, 0.80), (0.40, 0.36, 0.30)),                                # wrist, tucks into the cuff
        Ball((0, 0.06, 1.12 + L * 0.4), (0.60, 0.52, 0.42)),                      # hand
        Ball((0, -0.04, 1.54 + L), (0.70 * fist, 0.62 * fist, 0.44 * fist)),      # fist (striking end)
        Ball((0, -0.25, 1.40 + L * 0.8), (0.56 * fist, 0.38 * fist, 0.44)),       # knuckle roll (back of the hand)
        Ball((0, 0.22, 1.58 + L), (0.56 * fist, 0.36, 0.34 * fist)),              # fingers curled over the palm
    ]
    for b in els:
        b.co = b.co * S
        b.size = b.size * S
    return els


def thumb_balls(S=1.0, lift=0.0):
    """Separate thumb shell on -X (right hand, back of the hand facing -Y): its own mesh so the crease stays crisp."""
    q = Quaternion((0, 1, 0), math.radians(-16)) @ Quaternion((1, 0, 0), math.radians(-12))
    els = [
        Ball((-0.60, 0.06, 1.00 + lift * 0.4), (0.23, 0.26, 0.32), rot=q),
        Ball((-0.67, -0.06, 1.30 + lift * 0.5), (0.21, 0.23, 0.24), rot=q),
    ]
    for b in els:
        b.co = b.co * S
        b.size = b.size * S
    return els


def mitt_colour(lo, mid, hi, S=1.0, knuckle=None, palm_k=0.9, dz=0.0):
    """Vertical ramp lo (wrist) -> mid -> hi (fist top), palm side (+Y) a touch darker, optional knuckle colour on
    the back-of-hand roll (normal toward -Y, upper half)."""
    def fn(co, n):
        t = clamp((co.z / S - 0.55 - dz) / 1.35)
        c = ramp([(0.0, lo), (0.5, mid), (1.0, hi)], t)
        if n.y > 0.35:
            c = mix(c, shade(c, palm_k), clamp((n.y - 0.35) / 0.4))
        if knuckle is not None and n.y < -0.55 and (1.2 + dz) * S < co.z < (1.75 + dz) * S:
            c = mix(c, knuckle, clamp((-n.y - 0.55) / 0.3))
        return c
    return fn


def mitt(name, colour_fn, S=1.0, fist=1.0, lift=0.0, dz=0.0, tris=380, thumb_tris=90, extra=(), resolution=0.05):
    """returns [body, thumb]: two smooth closed metaball shells painted by colour_fn(world co, normal).
    dz raises the whole mitt (studs at scale 1) to show what sits on the cuff neck (spring)."""
    bb, tb = mitt_balls(S, fist, lift), thumb_balls(S, lift)
    for b in bb + tb:
        b.co.z += dz * S
    body = metaball_mesh(name, bb + list(extra), resolution=resolution * S, tris=tris, smooth=1)
    paint_goo(body, lambda co, n: rgba(colour_fn(co, n)))
    th = metaball_mesh(name + "Thumb", tb, resolution=resolution * S * 0.8, tris=thumb_tris, smooth=1)
    paint_goo(th, lambda co, n: rgba(colour_fn(co, n)))
    return [body, th]


def cuff(name, colour_row, S=1.0, segs=16, top=CUFF_TOP, flare=1.0):
    """Cuff lathe: dark recessed opening disc at the bottom, rolled lip, slightly tapered band, tucks into the mitt.
    colour_row(row name, k) -> colour; row names: hole, lip, band_lo, band, band_hi, top."""
    R = 0.60 * flare
    prof = [
        (0.00, 0.12), (0.46, 0.12),          # hole (recessed opening)
        (0.55, 0.00), (0.66 * flare, 0.03),  # lip underside
        (0.68 * flare, 0.12),                # lip roll
        (R + 0.02, 0.21),                    # band starts
        (R, 0.36), (R * 0.97, 0.52), (R * 0.93, top - 0.08),
        (R * 0.80, top), (0.00, top),        # top tucks under the mitt
    ]
    names = ["hole", "hole", "lip", "lip", "lip", "band_lo", "band", "band_hi", "top", "top"]
    prof = [(r * S, z * S) for r, z in prof]
    return lathe(name, prof, lambda i, k, z: colour_row(names[i], k), segs=segs, sy=0.88)


# ------------------------------------------------------------------ ship
def bbox(objs):
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in objs:
        mw = o.matrix_world
        for v in o.data.vertices:
            w = mw @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
    return lo, hi


def ship(name, parts, grip):
    """bake transforms -> finish() (join, origin bottom centre) -> restore smooth flags, FBX smooth normals.
    Prints the size in Roblox axes and the grip offset (from the origin and from the bbox centre)."""
    blo, bhi = bbox([o for o in parts if o.name.startswith(("Mitt", "Cuff"))])
    print("GLOVE_BODY %s cuff bottom -> fist top %.2f studs" % (name, bhi.z - blo.z))
    print("GLOVE_PARTS " + name + " " + " ".join("%s=%d" % (o.name, sum(len(p.vertices) - 2 for p in o.data.polygons)) for o in parts))
    for o in parts:
        bpy.context.view_layer.update()
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
        if "keep_smooth" not in o.data.attributes:
            a = o.data.attributes.new("keep_smooth", "INT", "FACE")
            for d in a.data:
                d.value = 1
    lo, hi = bbox(parts)
    origin = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))  # what finish() moves to (0, 0, 0)
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    o["smooth_normals"] = 1
    g = Vector(grip) - origin
    size = hi - lo
    c = Vector((0, 0, size.z / 2))
    gc = g - c
    # Roblox axes: (X, Y, Z) = (x, z, -y)
    print("GLOVE %s size_rbx=[%.2f, %.2f, %.2f] grip_from_origin_rbx=[%.2f, %.2f, %.2f] grip_from_bbox_centre_rbx=[%.2f, %.2f, %.2f]"
          % (name, size.x, size.z, size.y, g.x, g.z, -g.y, gc.x, gc.z, -gc.y))
    return o
