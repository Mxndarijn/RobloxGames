# Shared pieces for the Exclusive shop design concepts (not an asset).
# Premium palette: royal purple + warm gold + pink/cyan gem accents. Gold lows stay warm (LESSONS: pvp_knock_glove).
import math
import bmesh
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import prism, gcyl, counter

PURPLE = rgb(150, 88, 220)
PURPLE_D = rgb(98, 54, 168)
PURPLE_HI = rgb(196, 150, 250)
VIOLET_DEEP = rgb(70, 40, 130)
GOLD = rgb(252, 204, 72)
GOLD_LO = rgb(240, 150, 40)
GOLD_HI = rgb(255, 236, 150)
GEM_PINK = rgb(255, 110, 190)
GEM_CYAN = rgb(90, 220, 250)
GEM_GREEN = rgb(110, 236, 150)
WHITE = rgb(252, 250, 255)
CLOUD = rgb(244, 246, 255)
CLOUD_LO = rgb(196, 204, 240)
RAINBOW = [rgb(250, 96, 96), rgb(252, 160, 70), rgb(252, 222, 90), rgb(110, 220, 120), rgb(90, 170, 250), rgb(170, 120, 240)]


def gem(name, r, pos, col, h=None, rot=(0, 0, 0), segs=6):
    """Faceted gem: a short crown cone on top of a long pavilion cone, per-face shaded for sparkle."""
    h = h or r * 1.6
    bm = bmesh.new()
    x, y, z = pos
    top = bm.verts.new((0, 0, h * 0.42))
    bot = bm.verts.new((0, 0, -h * 0.58))
    ring = [bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0)) for a in (i * math.tau / segs for i in range(segs))]
    ring2 = [bm.verts.new((math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, h * 0.3)) for a in (i * math.tau / segs + math.pi / segs for i in range(segs))]
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((ring[i], ring[j], bot))
        bm.faces.new((ring[i], ring2[i], ring[j]))
        bm.faces.new((ring2[i], ring2[j], ring[j]))
        bm.faces.new((ring2[i], top, ring2[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    from mathutils import Euler, Matrix
    bmesh.ops.transform(bm, matrix=Matrix.Translation((x, y, z)) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4(), verts=bm.verts)
    o = obj_from_bm(name, bm, col)
    facet(o, col)
    return o


def lathe(name, prof, pos=(0, 0, 0), segs=16, col=(1, 1, 1, 1), sy=1.0):
    """Closed lathe round Z: prof = [(r, z), ...] bottom to top; r == 0 rows become a pole, ends are capped."""
    bm = bmesh.new()
    x0, y0, z0 = pos
    rows = []
    for r, z in prof:
        if r < 1e-4:
            rows.append([bm.verts.new((x0, y0, z0 + z))])
        else:
            rows.append([bm.verts.new((x0 + math.cos(i * math.tau / segs) * r, y0 + math.sin(i * math.tau / segs) * r * sy, z0 + z)) for i in range(segs)])
    for a, b in zip(rows, rows[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1 and len(b) == 1:
                continue
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


def facet(o, col, lo=0.72, hi=1.25):
    """Per-face shade by normal vs a light from upper front-left: cheap sparkle on gems/crystals."""
    import mathutils
    L = mathutils.Vector((-0.5, -0.6, 0.65)).normalized()
    me = o.data
    attr = me.color_attributes.get("Col") or me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for p in me.polygons:
        d = max(-1.0, min(1.0, p.normal.dot(L)))
        k = lo + (hi - lo) * (d + 1) / 2
        c = tuple(min(1.0, ch * k) for ch in col[:3])
        if d > 0.8:
            c = tuple(min(1.0, ch + (1 - ch) * 0.55) for ch in c)
        for li in p.loop_indices:
            attr.data[li].color = (*c, 1.0)


def crown(prefix, x, y, z, r=1.6, h=1.3, pts=5):
    """Gold crown: band + pointed tines with ball tips + gems round the band."""
    out = [gcyl(prefix + "Band", r, h * 0.45, (x, y, z), GOLD_LO, GOLD, segs=16)]
    for k in range(pts):
        a = k * math.tau / pts - math.pi / 2
        px, py = x + math.cos(a) * r * 0.92, y + math.sin(a) * r * 0.92
        out.append(gcyl(f"{prefix}Tine{k}", r * 0.34, h, (px, py, z + h * 0.4), GOLD_LO, GOLD_HI, segs=4, r_top=0.02))
        out.append(blob(f"{prefix}Ball{k}", r * 0.13, (px, py, z + h * 1.42), GOLD_HI, subdiv=1, jitter=0))
        out.append(gem(f"{prefix}Gem{k}", r * 0.16, (x + math.cos(a + math.pi / pts) * r * 1.02, y + math.sin(a + math.pi / pts) * r * 1.02, z + h * 0.22),
                       (GEM_PINK, GEM_CYAN)[k % 2], rot=(90, 0, math.degrees(a + math.pi / pts) + 90)))
    return out


def puffs(prefix, x, y, z, s, col_lo, col_hi, n=6, seed=1):
    """A little cloud cluster (pet cloud stand-in)."""
    import random
    R = random.Random(seed)
    out = [blob(prefix + "C", 0.9 * s, (x, y, z + 0.55 * s), col_hi, subdiv=2, squash=(1.25, 1, 0.75), jitter=0)]
    for k in range(n):
        a = k * math.tau / n + R.uniform(-0.3, 0.3)
        rr = R.uniform(0.45, 0.62) * s
        out.append(blob(f"{prefix}P{k}", rr, (x + math.cos(a) * 0.85 * s, y + math.sin(a) * 0.6 * s, z + 0.45 * s + R.uniform(-0.1, 0.2) * s), col_hi, subdiv=2, jitter=0))
    for o in out:
        gradient(o, col_lo, col_hi, z, z + 1.3 * s)
    return out


def pedestal(prefix, x, y, z, r=0.9, h=2.4, top=None, col=PURPLE, col_lo=PURPLE_D):
    """Gold-trimmed display pillar."""
    out = [gcyl(prefix + "Foot", r * 1.3, 0.35, (x, y, z), GOLD_LO, GOLD, segs=8),
           gcyl(prefix + "Shaft", r, h - 0.7, (x, y, z + 0.35), col_lo, col, segs=8),
           gcyl(prefix + "Cap", r * 1.3, 0.35, (x, y, z + h - 0.35), GOLD_LO, GOLD_HI, segs=8)]
    return out


def star(prefix, x, y, z, R, depth, lo, hi, rot_y=0.0):
    pts = [(x + math.cos(math.radians(90 + i * 36)) * (R if i % 2 == 0 else R * 0.45),
            z + math.sin(math.radians(90 + i * 36)) * (R if i % 2 == 0 else R * 0.45)) for i in range(10)]
    o = prism(prefix, pts, y - depth / 2, y + depth / 2, lo, hi)
    return o


def sparkle(prefix, x, y, z, s, col=GOLD_HI):
    """4-point twinkle star (flat, both sides)."""
    pts = []
    for i in range(8):
        a = math.radians(90 + i * 45)
        rr = s if i % 2 == 0 else s * 0.25
        pts.append((x + math.cos(a) * rr, z + math.sin(a) * rr))
    return prism(prefix, pts, y - 0.08, y + 0.08, shade(col, 0.9), col)


def sign_board(prefix, y, z, w, h, frame_lo=GOLD_LO, frame=GOLD, face_lo=PURPLE_D, face=PURPLE):
    """Blank sign face for a SurfaceGui 'EXCLUSIVE'."""
    return [bbox(prefix + "Frame", (w + 0.8, 0.5, h + 0.7), (0, y, z), frame_lo, frame, bev=0.15),
            bbox(prefix + "Face", (w, 0.3, h), (0, y - 0.25, z), face_lo, face, bev=0.06)]
