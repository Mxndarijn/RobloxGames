"""Shared building blocks for the item-icon recipes (runs inside Blender, kit conventions:
Z up, front faces -Y, 1 BU = 1 stud). Every recipe returns a list of objects; render_icons.py
frames and lights them identically."""
import math, os, sys
import bmesh, bpy
from mathutils import Euler, Matrix, Vector

KIT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if KIT not in sys.path:
    sys.path.insert(0, KIT)
from lib import *  # noqa: E402,F401,F403
from lib.shapes import obj_from_bm  # noqa: E402

# Flat saturated icon palette (a touch brighter than the world palette).
C = {
    "gold": rgb(255, 196, 40), "gold_d": rgb(214, 144, 24), "gold_l": rgb(255, 230, 120),
    "red": rgb(232, 62, 70), "red_d": rgb(176, 40, 56),
    "orange": rgb(255, 140, 50), "orange_d": rgb(214, 96, 36),
    "green": rgb(96, 214, 98), "green_d": rgb(54, 160, 74), "green_l": rgb(170, 245, 150),
    "teal": rgb(60, 200, 190), "blue": rgb(70, 140, 240), "blue_d": rgb(44, 96, 190), "blue_l": rgb(150, 205, 255),
    "purple": rgb(160, 96, 230), "purple_d": rgb(112, 62, 180), "purple_l": rgb(210, 170, 255),
    "pink": rgb(255, 130, 180), "pink_d": rgb(214, 84, 140),
    "white": rgb(250, 248, 242), "cream": rgb(248, 232, 200), "cream_d": rgb(222, 196, 150),
    "grey": rgb(176, 184, 198), "grey_d": rgb(118, 126, 144), "ink": rgb(46, 34, 58),
    "brown": rgb(160, 104, 62), "brown_d": rgb(118, 74, 46), "stone": rgb(170, 160, 150), "stone_d": rgb(122, 114, 108),
    "night": rgb(60, 62, 150), "yellow": rgb(255, 232, 80),
}


def paint(o, color):
    """Flat vertex colour on an existing object (text / converted meshes have none)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            lp[layer] = color
    bm.to_mesh(o.data)
    bm.free()
    return o


def put(o, pos=(0, 0, 0), rot=(0, 0, 0), scale=None):
    """Set transform (rot in degrees, XYZ). Parts keep their transform; the renderer reads matrix_world."""
    o.location = Vector(pos)
    o.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    if scale is not None:
        o.scale = (scale, scale, scale) if isinstance(scale, (int, float)) else Vector(scale)
    return o


def group(parts, pos=(0, 0, 0), rot=(0, 0, 0), scale=1.0, name="grp"):
    """Parent parts under an empty so a sub-assembly moves / turns / scales as one. Returns the empty
    (recipes may include it in their part list; renderers use all descendants)."""
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    for p in parts:
        if p.parent is None:
            p.parent = e
    put(e, pos, rot, scale)
    return e


def meshes_of(objs):
    out = []
    for o in objs:
        if o.type == "MESH":
            out.append(o)
        out += meshes_of(list(o.children))
    return out


def smooth(o, on=True):
    for p in o.data.polygons:
        p.use_smooth = on
    return o


def prism(name, pts, depth, color, pos=(0, 0, 0), rot=(0, 0, 0), bevel_w=0.0, scale=None):
    """Polygon (x, z) points extruded along Y (front face looks at -Y), centred on y=0."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in pts]
    bm.faces.new(front[::-1] if _area(pts) > 0 else front)
    bm.faces.new(back if _area(pts) > 0 else back[::-1])
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        q = (front[i], front[j], back[j], back[i])
        bm.faces.new(q if _area(pts) > 0 else q[::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, color)
    if bevel_w:
        bevel(o, bevel_w, 1, 50)
    return put(o, pos, rot, scale)


def _area(pts):
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2


def star_pts(n, r_out, r_in, rot=90.0):
    return [((r_out if i % 2 == 0 else r_in) * math.cos(math.radians(rot + i * 180 / n)),
             (r_out if i % 2 == 0 else r_in) * math.sin(math.radians(rot + i * 180 / n))) for i in range(2 * n)]


def circle_pts(r, n=16, a0=0.0):
    return [(r * math.cos(math.radians(a0 + i * 360 / n)), r * math.sin(math.radians(a0 + i * 360 / n))) for i in range(n)]


def disc(name, r, h, color, pos=(0, 0, 0), rot=(0, 0, 0), segs=16, r_top=None, bevel_w=0.0):
    """A round slab whose axis is Y (a coin / plate facing -Y); centred."""
    o = cylinder(name, r, h, (0, 0, 0), color, segs=segs, r_top=r_top)
    for v in o.data.vertices:
        v.co.z -= h / 2
    o.rotation_euler = Euler((math.radians(-90), 0, 0))
    bpy.context.view_layer.update()
    apply_transforms(o)
    if bevel_w:
        bevel(o, bevel_w, 1, 50)
    return put(o, pos, rot)


def torus(name, R, r, color, pos=(0, 0, 0), rot=(0, 0, 0), a0=0.0, a1=360.0, segs=16, rsegs=6, plane="xz"):
    """Ring (or arc) of radius R and tube radius r in the XZ plane (facing -Y)."""
    n = max(3, int(segs * abs(a1 - a0) / 360.0))
    pts = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((R * math.cos(a), 0, R * math.sin(a)))
    closed = abs(a1 - a0) >= 360.0
    if closed:
        pts = pts[:-1]
        bm = bmesh.new()
        rings = []
        for i, p in enumerate(pts):
            a = math.radians(a0 + 360.0 * i / len(pts))
            cx, cz = math.cos(a), math.sin(a)
            ring = []
            for k in range(rsegs):
                t = k * math.tau / rsegs
                rr = R + r * math.cos(t)
                ring.append(bm.verts.new((rr * cx, r * math.sin(t), rr * cz)))
            rings.append(ring)
        for i in range(len(rings)):
            j = (i + 1) % len(rings)
            for k in range(rsegs):
                m = (k + 1) % rsegs
                bm.faces.new((rings[i][k], rings[i][m], rings[j][m], rings[j][k]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = obj_from_bm(name, bm, color)
    else:
        o = tube(name, pts, [r] * len(pts), color, segs=rsegs)
    return put(o, pos, rot)


def blobc(name, r, pos, color, squash=(1, 1, 1), subdiv=2, rot=(0, 0, 0), flat=False):
    o = blob(name, r, pos, color, subdiv=subdiv, squash=squash, jitter=0, rot=rot)
    return smooth(o, not flat)


def gem(name, r, pos, color, squash=(1, 1, 1.3), rot=(0, 0, 0)):
    """Octahedron-ish sparkle / crystal (6 verts, 8 faces)."""
    o = blob(name, r, pos, color, subdiv=1, squash=squash, jitter=0, rot=rot)
    return o


def sparkle(pos, s=0.4, color=None, name="Sparkle"):
    """4-point twinkle that reads from any angle: two crossed thin spikes."""
    color = color or C["white"]
    a = prism(name + "a", [(0, s), (s * 0.22, s * 0.22), (s, 0), (s * 0.22, -s * 0.22), (0, -s), (-s * 0.22, -s * 0.22), (-s, 0), (-s * 0.22, s * 0.22)],
              s * 0.2, color)
    b = prism(name + "b", [(0, s), (s * 0.22, s * 0.22), (s, 0), (s * 0.22, -s * 0.22), (0, -s), (-s * 0.22, -s * 0.22), (-s, 0), (-s * 0.22, s * 0.22)],
              s * 0.2, color, rot=(0, 0, 90))
    return group([a, b], pos, name=name)


def text(string, size, color, depth=0.25, pos=(0, 0, 0), rot=(0, 0, 0), bold=True):
    """Extruded text facing -Y, centred (Blender's built-in font)."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = string
    cu.size = size
    cu.extrude = depth / 2
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.bevel_depth = size * 0.01
    ob = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    ob.rotation_euler = Euler((math.radians(90), 0, 0))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    me.transform(ob.matrix_world)
    bpy.data.objects.remove(ob)
    o = bpy.data.objects.new("Text_" + string, me)
    bpy.context.scene.collection.objects.link(o)
    paint(o, color)
    smooth(o, False)
    return put(o, pos, rot)


def lathe_obj(name, profile, color_fn=None, segs=16, pos=(0, 0, 0), rot=(0, 0, 0), phase=0.0):
    """Surface of revolution, profile = [(r, z), ...]; colour_fn(i, k, z) or a plain colour."""
    from models._phoenix_pad import lathe
    fn = color_fn if callable(color_fn) else (lambda i, k, z: color_fn)
    o = lathe(name, profile, segs=segs, color_fn=fn, phase=phase)
    return put(o, pos, rot)


def shaded(o, bottom, top):
    gradient(o, bottom, top)
    return o


# ---------------------------------------------------------------- slime (models/_slime.py body + face)
def slime(tint=(110, 225, 130), face_name="happy", pos=(0, 0, 0), rot=(0, 0, 0), scale=1.0, squash=1.0):
    """Gumdrop slime: models/_slime.py body tinted like the game + a face decal set. 3 studs tall at scale 1."""
    from models import _slime as S
    t = [c / 255 for c in tint]
    body = S.body()
    for d in body.data.color_attributes["Col"].data:
        c = d.color
        d.color = (min(1, c[0] * t[0] * 1.08), min(1, c[1] * t[1] * 1.08), min(1, c[2] * t[2] * 1.08), 1.0)
    parts = [body] + (S.face(face_name) if face_name else [])
    for p in parts:
        S._smooth(p, p is body)
    g = group(parts, pos, rot, scale, name="slime")
    if squash != 1.0:
        g.scale = (scale, scale, scale * squash)
    return g


def slime_accessory(kind, tint):
    from models import _slime as S
    return {"leaf": S.leaf, "crown": S.crown, "crystal": S.crystal}[kind]()


def run_model(name, pos=(0, 0, 0), rot=(0, 0, 0), scale=1.0):
    """Execute models/<name>.py (it ends in finish(<name>, parts)) and return its joined mesh, placed."""
    path = os.path.join(KIT, "models", name + ".py")
    before = set(bpy.data.objects.keys())
    g = {"__name__": "__model__", "__file__": path}
    exec(compile(open(path).read(), path, "exec"), g)
    new = [bpy.data.objects[n] for n in bpy.data.objects.keys() if n not in before]
    top = [o for o in new if o.parent is None and o.type == "MESH"]
    o = top[-1]
    return put(o, pos, rot, scale)
