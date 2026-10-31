# Small helpers for the habitat_theme_* models (not an asset). Themes are authored in the square layout that
# overlay_finish() / round_up() bends onto the round dish; these helpers place props by angle on that layout.
# Angles: degrees, math convention, -90 = the FRONT (-Y, walkway), 90 = the back. Keep tall props out of
# -135..-45 (the front arc is the signature prop's).
# round_up() moves each rigid group (parts <= 1.6 wide whose centres sit within 0.7 of the group's first part)
# whole and shrinks a tall group to fit a 0.65 radius round its centre, so author clusters inside that radius.
import math
import bmesh
from mathutils import Vector
from lib import *
from models._habitat_overlay import BAND


def sq(ang, r=BAND):
    """The square-layout point that round_up() puts at polar (r, ang)."""
    a = math.radians(ang)
    c, s = math.cos(a), math.sin(a)
    k = r / max(abs(c), abs(s))
    return c * k, s * k


def at(ang, r=BAND, z=0.0, dt=0.0, dr=0.0):
    """Square-layout point at angle ang, nudged dr outward and dt along the tangent (counter-clockwise)."""
    a = math.radians(ang)
    x, y = sq(ang, r)
    return (x + dr * math.cos(a) - dt * math.sin(a), y + dr * math.sin(a) + dt * math.cos(a), z)


def paint_faces(o, fn):
    """Per-face paint: fn(world_centre, world_normal) -> colour."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    mw = o.matrix_world
    rot = mw.to_3x3()
    bm.normal_update()
    for f in bm.faces:
        c = fn(mw @ f.calc_center_median(), (rot @ f.normal).normalized())
        for lp in f.loops:
            lp[col] = c
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    return o


def stand(o, floor=0.0):
    """Drop the part so its lowest vertex sits on floor (blob bottoms)."""
    zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
    o.data.transform(__import__("mathutils").Matrix.Translation((0, 0, floor - min(zs))))
    o.data.update()
    return o


def star_slab(name, r_out, r_in, th, pos, col, rot=(0, 0, 0), points=5, rim=None):
    """Chunky 5-point star standing upright (faces -Y before rot), centred on pos."""
    from lib.shapes import obj_from_bm, _place
    bm = bmesh.new()
    cl = bm.loops.layers.color.new("Col")
    n = points * 2
    pts = [((r_out if k % 2 == 0 else r_in) * math.sin(k * math.pi / points),
            (r_out if k % 2 == 0 else r_in) * math.cos(k * math.pi / points)) for k in range(n)]
    front = [bm.verts.new((x, -th / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, th / 2, z)) for x, z in pts]
    cf, cb = bm.verts.new((0, -th / 2 - th * 0.35, 0)), bm.verts.new((0, th / 2 + th * 0.35, 0))
    rim = rim or shade(col, 0.82)
    for k in range(n):
        k1 = (k + 1) % n
        for f, c in ((bm.faces.new((front[k], front[k1], cf)), shade(col, 1.06 if k % 2 else 0.94)),
                     (bm.faces.new((back[k1], back[k], cb)), shade(col, 1.06 if k % 2 else 0.94)),
                     (bm.faces.new((front[k], back[k], back[k1], front[k1])), rim)):
            for lp in f.loops:
                lp[cl] = c
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm)


def theme_finish(name, parts):
    """overlay_finish() for a theme, plus a warning for any part that reaches past the stand's foot. The bbox is
    lopsided on purpose (front arc clear): write_deck_offset() records its centre in out/<name>.deck.json and the
    game puts the mesh back on the dish centre with it."""
    import bpy
    from models import _habitat_overlay as ho
    ho.round_up(parts)
    ho.on_deck(parts, 0.0)
    bpy.context.view_layer.update()
    for p in parts:  # a prop past the stand's foot hangs in the air beside the dish
        far = max(math.hypot(*(p.matrix_world @ v.co).xy) for v in p.data.vertices)
        if far > ho.STAND_FOOT + 0.02:
            print(f"THEME far part {p.name} reach={far:.3f}")
    if ho.PREVIEW:
        stand_parts = ho.cork_stand()
        for o in stand_parts:
            o.location.z -= ho.DECK
        return finish(name, parts + stand_parts)
    ho.check(parts)
    ho.write_deck_offset(name, parts)
    return finish(name, parts)


def vein(name, target, centre, face_deg, path, radius, col, lift=0.02, segs=4):
    """A tube laid on target's surface: path = [(t, z), ...] on the side of target that faces face_deg (t along
    that side's tangent, z height), each point ray-cast onto the surface from outside and lifted `lift` off it.
    For glowing cracks on rocks, lava runs on a cone. Points that miss are dropped."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(target.data)
    bm.transform(target.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    a = math.radians(face_deg)
    f = Vector((math.cos(a), math.sin(a), 0))
    tg = Vector((-f.y, f.x, 0))
    pts = []
    for t, z in path:
        o = Vector((centre[0], centre[1], z)) + tg * t + f * 4
        hit = tree.ray_cast(o, -f, 8)
        if hit[0] is not None:
            pts.append(hit[0] + hit[1] * lift)
    if len(pts) < 2:
        return None
    rad = radius if isinstance(radius, (list, tuple)) else [radius * (1 - 0.35 * i / (len(pts) - 1)) for i in range(len(pts))]
    return tube(name, pts, rad[:len(pts)], col, segs=segs)


def zigzag(t0, z0, z1, n, amp, seed):
    """A crack path from (t0, z0) up to z1 in n steps, wandering amp sideways."""
    import random
    r = random.Random(seed)
    out, t = [], t0
    for i in range(n + 1):
        out.append((t, z0 + (z1 - z0) * i / n))
        t += r.uniform(-amp, amp)
    return out
