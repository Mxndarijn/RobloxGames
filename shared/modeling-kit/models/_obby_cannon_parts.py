# Shared helpers for the obby cannon options (obby_cannon_a/b/c), not an asset.
# The old cannon (AimTheCannon BARREL) is one 4 x 3 x 4 box: 4 along the aim, 3 tall, 4 wide, standing on the deck,
# turning (sweep) round its vertical axis through the box centre. Every option fits that box within 10 % and keeps
# the swivel axis at x = y = 0. 1 BU = 1 stud, Z up, the mouth aims at -Y (front).
import math
import bmesh
from mathutils import Vector
from lib import *
from lib.shapes import obj_from_bm, _place

# The old look's colours (ObbyParts `cannon`: metal 70,66,96 + orange 255,140,40), lifted for the Roblox look.
METAL_LO = rgb(124, 118, 166)
METAL = rgb(150, 144, 194)
METAL_HI = rgb(188, 182, 226)
ORANGE_LO = rgb(232, 112, 34)
ORANGE = rgb(255, 146, 44)
ORANGE_HI = rgb(255, 190, 96)
BORE = rgb(52, 40, 70)  # the inside of the mouth: dark on purpose, so the hole reads
BORE_HI = rgb(84, 68, 108)
GOO_DEEP = hexc("#2F8E35")
GOO = hexc("#4FC234")
GOO_HI = hexc("#A8F062")
WHITE = rgb(255, 255, 255)
INK = rgb(36, 28, 44)

AIM_TILT = 12.0  # degrees the barrel points up (the real arc is drawn by the dotted line)


def barrel_rot(tilt=AIM_TILT):
    """Euler that turns a lathe built along +Z into one aiming at -Y, `tilt` degrees up."""
    return (90.0 - tilt, 0.0, 0.0)


def axis_dir(tilt=AIM_TILT):
    t = math.radians(tilt)
    return Vector((0.0, -math.cos(t), math.sin(t)))


def lathe(name, prof, cols, segs=20, pos=(0, 0, 0), rot=(0, 0, 0), loop=False, phase=0.0, wobble=None):
    """Surface of revolution round local +Z. prof: [(r, z)]; an end with r == 0 becomes a pole (closed).
    loop=True joins the last point back to the first (a closed ring band). cols: one colour, or one per segment
    (len(prof) - 1, plus one for the closing segment when loop). wobble(i, a) -> radius factor (goo lumps)."""
    n = len(prof)
    nseg = n if loop else n - 1
    if not isinstance(cols, (list, tuple)) or not isinstance(cols[0], (list, tuple)):
        cols = [cols] * nseg
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    rings = []
    for i, (r, z) in enumerate(prof):
        if r < 1e-6:
            rings.append(bm.verts.new((0, 0, z)))
            continue
        ring = []
        for k in range(segs):
            a = phase + k * math.tau / segs
            f = wobble(i, a) if wobble else 1.0
            ring.append(bm.verts.new((math.cos(a) * r * f, math.sin(a) * r * f, z)))
        rings.append(ring)
    for i in range(nseg):
        A, B = rings[i], rings[(i + 1) % n]
        faces = []
        if isinstance(A, list) and isinstance(B, list):
            for k in range(segs):
                faces.append(bm.faces.new((A[k], A[(k + 1) % segs], B[(k + 1) % segs], B[k])))
        elif isinstance(A, list):
            for k in range(segs):
                faces.append(bm.faces.new((A[k], A[(k + 1) % segs], B)))
        elif isinstance(B, list):
            for k in range(segs):
                faces.append(bm.faces.new((A, B[(k + 1) % segs], B[k])))
        for f in faces:
            for lp in f.loops:
                lp[layer] = cols[i]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm)


def band(name, r_in, r_out, z0, z1, col, lo=None, segs=20, pos=(0, 0, 0), rot=(0, 0, 0), round_=0.35):
    """A rounded ring band (closed loop profile) round local +Z: top face light, bottom/back faces `lo`."""
    lo = lo or shade(col, 0.82)
    h = z1 - z0
    c = round_ * min(h, r_out - r_in)
    prof = [(r_in, z0), (r_out - c, z0), (r_out, z0 + c), (r_out, z1 - c), (r_out - c, z1), (r_in, z1)]
    cols = [lo, mix(lo, col, 0.6), col, mix(col, lo, 0.2), lo, lo]
    return lathe(name, prof, cols, segs, pos, rot, loop=True)


def disc(name, r, z0, h, lo, hi, segs=24, pos=(0, 0), r_top=None, bev=0.1):
    """A short bevelled cylinder standing at z0 with a dark side and a light top."""
    rt = r if r_top is None else r_top
    b = min(bev, h * 0.45)
    prof = [(0, z0), (r - b, z0), (r, z0 + b), (rt, z0 + h - b), (rt - b, z0 + h), (0, z0 + h)]
    cols = [lo, lo, mix(lo, hi, 0.45), mix(lo, hi, 0.75), hi]
    return lathe(name, prof, cols, segs, (pos[0], pos[1], 0))


def bolts(prefix, n, R, z, col, r=0.11, a0=0.0, h=0.08):
    out = []
    for k in range(n):
        a = a0 + k * math.tau / n
        out.append(blob(f"{prefix}{k}", r, (R * math.cos(a), R * math.sin(a), z + h * 0.3), col, subdiv=1,
                        squash=(1, 1, 0.55), jitter=0))
    return out


def bb(name, size, pos, lo, hi, bev=0.12, rot=(0, 0, 0)):
    o = box(name, size, pos, hi, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, lo, hi)
    return o


def smooth(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    sm = bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")
    for f in bm.faces:
        f[sm] = 1
    bm.to_mesh(o.data)
    bm.free()
    return o


def finish_smooth(name, parts):
    """finish() that keeps the smooth flag of parts passed through smooth() (or paint_goo)."""
    for p in parts:
        if "keep_smooth" not in p.data.attributes:
            p.data.attributes.new("keep_smooth", "INT", "FACE")
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    return o
