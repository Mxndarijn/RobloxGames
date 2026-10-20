# Shared helpers for the Guide NPC design concepts (not an asset). 1 BU = 1 stud, Z up, front faces -Y.
import math
import bmesh
from lib import *

P = PALETTE
WOOD, WOOD_D = P["ranch_wood"], P["ranch_wood_dark"]
CREAM, PLAZA = P["ranch_cream"], P["ranch_plaza"]
ROOF, ROOF_D = P["ranch_roof"], P["ranch_roof_dark"]
GOO, GOO_HI = P["ranch_goo"], P["ranch_goo_hi"]
BUTTER, PINK, LILAC = P["ranch_butter"], P["ranch_pink"], P["ranch_lilac"]
METAL = P["ranch_metal"]
SKIN = rgb(255, 210, 166)
INK = rgb(40, 34, 44)
WHITE = rgb(255, 255, 255)
DENIM, DENIM_D = rgb(84, 140, 214), rgb(58, 98, 168)


def bb(name, size, pos, lo, hi, bev=0.12, rot=(0, 0, 0)):
    """Bevelled box with a dark-below / light-above gradient."""
    o = box(name, size, pos, hi, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, lo, hi)
    return o


def gr(o, lo, hi):
    gradient(o, lo, hi)
    return o


def smooth(o):
    """Flag every face of a part to be smooth-shaded after finish() (see finish_smooth)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    sm = bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")
    for f in bm.faces:
        f[sm] = 1
    bm.to_mesh(o.data)
    bm.free()
    return o


def finish_smooth(name, parts):
    for p in parts:
        if "keep_smooth" not in p.data.attributes:
            p.data.attributes.new("keep_smooth", "INT", "FACE")
    o = finish(name, parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    return o


def gumdrop(name, r, h, pos, lo, hi, segs=24, rings=14, n=2.6, squash_y=1.0):
    """Slime body: closed superellipse surface of revolution standing on pos.z."""
    bm = bmesh.new()
    x0, y0, z0 = pos
    bottom = bm.verts.new((x0, y0, z0))
    ring_vs = []
    for i in range(rings):
        a = (i / rings) * (math.pi / 2)
        c, s = math.cos(a), math.sin(a)
        rr = r * (c ** (2 / n)) * (1 + 0.06 * (1 - s))
        zz = h * (s ** (2 / n))
        ring = [bm.verts.new((x0 + rr * math.cos(k * math.tau / segs),
                              y0 + rr * math.sin(k * math.tau / segs) * squash_y, z0 + zz))
                for k in range(segs)]
        ring_vs.append(ring)
    top = bm.verts.new((x0, y0, z0 + h))
    for k in range(segs):
        k2 = (k + 1) % segs
        bm.faces.new((bottom, ring_vs[0][k2], ring_vs[0][k]))
        for a_, b_ in zip(ring_vs, ring_vs[1:]):
            bm.faces.new((a_[k], a_[k2], b_[k2], b_[k]))
        bm.faces.new((ring_vs[-1][k], ring_vs[-1][k2], top))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, hi)
    gradient(o, lo, hi)
    return smooth(o)


def eye(prefix, x, y, z, r=0.2, tall=1.35, look=(0, 0), sub=2):
    """Cartoon eye on a -Y face: white, dark pupil, catchlight."""
    out = [blob(prefix + "W", r, (x, y, z), WHITE, subdiv=sub, squash=(1, 0.35, tall), jitter=0)]
    out.append(blob(prefix + "P", r * 0.62, (x + look[0] * r * 0.3, y - r * 0.2, z + look[1] * r * 0.3 - r * 0.08),
                    INK, subdiv=sub, squash=(1, 0.35, tall), jitter=0))
    out.append(blob(prefix + "C", r * 0.2, (x + r * 0.18, y - r * 0.36, z + r * 0.3), WHITE, subdiv=1,
                    squash=(1, 0.4, 1), jitter=0))
    return out


def smile(prefix, x, y, z, w=0.5, depth=0.14, col=INK, n=7, t=0.1):
    """Curved smile: one tapered tube along an arc on a -Y face."""
    pts, radii = [], []
    for k in range(n):
        u = (k - (n - 1) / 2) / ((n - 1) / 2)
        pts.append((x + u * w / 2, y, z - depth * (1 - u * u)))
        radii.append(t / 2 * (0.75 + 0.25 * (1 - u * u)))
    return [tube(prefix, pts, radii, col, segs=6)]


def cheeks(prefix, dx, y, z, r=0.17):
    return [blob(f"{prefix}{s}", r, (s * dx, y, z), PINK, subdiv=1, squash=(1.2, 0.35, 0.8), jitter=0)
            for s in (-1, 1)]


def pet_slime(prefix, pos, r=0.9, col=GOO, hi=GOO_HI, look=(0, 0), segs=18, rings=10, eye_sub=2):
    """Small companion slime facing -Y."""
    x, y, z = pos
    h = r * 1.35
    out = [gumdrop(prefix + "Body", r, h, pos, mix(col, INK, 0.12), mix(col, hi, 0.45), segs=segs, rings=rings)]
    out.append(smooth(blob(prefix + "Shine", r * 0.22, (x - r * 0.35, y - r * 0.55, z + h * 0.72), hi, subdiv=2,
                           squash=(1, 0.5, 0.7), jitter=0)))
    ey = y - r * 0.93
    out += eye(prefix + "EL", x - r * 0.32, ey, z + h * 0.5, r=r * 0.17, look=look, sub=eye_sub)
    out += eye(prefix + "ER", x + r * 0.32, ey, z + h * 0.5, r=r * 0.17, look=look, sub=eye_sub)
    out += smile(prefix + "M", x, ey - 0.02, z + h * 0.3, w=r * 0.36, depth=r * 0.08, t=r * 0.07)
    return out


def limb(name, top, phi, length, w, d, lo, hi, bev=0.15):
    """Box limb hanging from `top`, swung by phi degrees about Y (0 = straight down,
    +phi swings the far end toward -X, -phi toward +X). Returns (part, far-end point)."""
    s, c = math.sin(math.radians(phi)), math.cos(math.radians(phi))
    dx, dz = -s, -c
    cx, cy, cz = top[0] + dx * length / 2, top[1], top[2] + dz * length / 2
    o = box(name, (w, d, length), (cx, cy, cz), hi, rot=(0, phi, 0))
    if bev:
        bevel(o, bev)
    gradient(o, lo, hi)
    return o, (top[0] + dx * length, top[1], top[2] + dz * length)


def blocky_face(prefix, cx, fy, cz, eye_dx=0.36, eye_r=0.19, mouth=True):
    out = eye(prefix + "EL", cx - eye_dx, fy, cz + 0.12, r=eye_r)
    out += eye(prefix + "ER", cx + eye_dx, fy, cz + 0.12, r=eye_r)
    out += cheeks(prefix + "Ch", eye_dx + 0.2, fy + 0.02, cz - 0.2)
    if mouth:
        out += smile(prefix + "M", cx, fy - 0.02, cz - 0.34, w=0.46, depth=0.1, t=0.08)
    return out


def gum_r(r, h, z, n=2.6):
    """Radius of a gumdrop() body at height z above its base."""
    s = min(max(z / h, 0.0), 1.0) ** (n / 2)
    c = math.sqrt(max(1 - s * s, 0.0))
    return r * (c ** (2 / n)) * (1 + 0.06 * (1 - s))
