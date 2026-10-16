# Shared helpers for the Slime Ranch world-border set (ranch_hedge_segment, ranch_rail_fence,
# ranch_pine_cluster, ranch_border_hill, ranch_border_rocks). Not a model: no finish().
import math, random
import bmesh
from mathutils import Vector
from lib import *

FIELD, FIELD_L, FIELD_D = PALETTE["ranch_field"], PALETTE["ranch_field_light"], PALETTE["ranch_field_dark"]
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
PINK, LILAC, BUTTER, CREAM = PALETTE["ranch_pink"], PALETTE["ranch_lilac"], PALETTE["ranch_butter"], PALETTE["ranch_cream"]


def tuft(name, pos, R, h=0.9, blades=3, color=None):
    """Grass tuft: a few thin leaning 3-sided cones (12 tris per blade)."""
    out = []
    for k in range(blades):
        a = k * math.tau / blades + R.uniform(-0.4, 0.4)
        lean = R.uniform(10, 24)
        hh = h * R.uniform(0.7, 1.15)
        o = cone(f"{name}_{k}", 0.16, hh, (pos[0] + math.cos(a) * 0.12, pos[1] + math.sin(a) * 0.12, pos[2] - 0.05),
                 color or FIELD, segs=3, rot=(math.cos(a + 1.57) * lean, math.sin(a + 1.57) * lean, R.uniform(0, 120)))
        gradient(o, FIELD_D, color or FIELD_L)
        out.append(o)
    return out


def flower(name, pos, R, color, r=0.32):
    """Squashed subdiv-1 bloom with a butter eye (LESSONS ranch_flower_planter)."""
    b = blob(name, r, pos, color, seed=R.randint(0, 999), subdiv=1, squash=(1, 1, 0.55), jitter=0.05)
    e = blob(name + "Eye", r * 0.4, (pos[0], pos[1], pos[2] + r * 0.32), BUTTER, subdiv=1, squash=(1, 1, 0.6), jitter=0.0)
    return [b, e]


def heightfield(name, nx, ny, sx, sy, height, paint, skirt=0.15):
    """Closed grid mound: top verts z = height(u, v) (u, v in -1..1), extruded down `skirt`.
    paint(face_center, normal) -> colour for top faces; skirt/bottom get FIELD_D."""
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=nx, y_segments=ny, size=1.0)
    for v in bm.verts:
        u, w = v.co.x, v.co.y  # create_grid spans -1..1 for size=1
        v.co.z = height(u, w)
        v.co.x, v.co.y = u * sx / 2, w * sy / 2
    top = list(bm.faces)
    res = bmesh.ops.extrude_face_region(bm, geom=top)
    new = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, -skirt)), verts=new)
    for v in new:
        v.co.z = -skirt
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    top_set = set(top)
    for f in bm.faces:
        c = paint(f.calc_center_median(), f.normal) if f in top_set else FIELD_D
        for lp in f.loops:
            lp[layer] = c
    return obj_from_bm(name, bm)


def fir(prefix, x, y, H, R, tips=8, tiers=5, dark=None, mid=None, light=None):
    """Stylised fir (tree_pine recipe, ranch greens): trunk tube + cone skirts whose rim alternates
    drooping tips and notches, painted per corner (tips light, core dark, underside darkest)."""
    dark = dark or mix(FIELD_D, rgb(70, 136, 96), 0.5)
    mid = mid or FIELD_D
    light = light or mix(FIELD, FIELD_L, 0.5)
    parts = []
    tr = 0.22 * H / 10 + 0.3
    parts.append(tube(f"{prefix}Trunk", [(x, y, -0.05), (x, y, H * 0.25), (x, y, H * 0.55)],
                      [tr * 1.5, tr, tr * 0.7], WOOD, segs=6, seed=R))
    gradient(parts[-1], WOOD_D, WOOD)
    base_r = H * 0.33
    for i in range(tiers):
        t = i / (tiers - 1)
        r = base_r * (1 - 0.68 * t)
        z = H * (0.2 + 0.62 * t)
        h = H * (0.27 - 0.07 * t)
        parts.append(_tier(f"{prefix}Tier{i}", x, y, r, h, z, tips - i // 2, 0.4 + 0.2 * (1 - t), i * 0.37 + R.uniform(0, 1), R,
                           mix(dark, mid, t * 0.5), mix(mid, light, 0.45 + 0.55 * t)))
    return parts


def _tier(name, x, y, r, h, z, tips, droop, twist, R, dark, light):
    bm = bmesh.new()
    n = tips * 2
    rim = []
    for k in range(n):
        a = k * math.tau / n + twist
        tip = k % 2 == 0
        rr = r * (1.0 if tip else 0.62) * R.uniform(0.92, 1.06)
        rim.append(bm.verts.new((x + math.cos(a) * rr, y + math.sin(a) * rr, z - (droop if tip else 0.0))))
    apex = bm.verts.new((x + R.uniform(-0.06, 0.06), y + R.uniform(-0.06, 0.06), z + h))
    under = bm.verts.new((x, y, z + h * 0.18))
    for k in range(n):
        a, b = rim[k], rim[(k + 1) % n]
        bm.faces.new((a, b, apex))
        bm.faces.new((b, a, under))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        below = f.normal.z < 0
        for lp in f.loops:
            v = lp.vert
            d = math.hypot(v.co.x - x, v.co.y - y) / r
            if below:
                c = shade(dark, 0.86)
            elif v is apex:
                c = mix(dark, light, 0.8)
            else:
                c = mix(dark, light, max(0.0, min(1.0, (d - 0.5) / 0.5)))
            lp[layer] = c
    return obj_from_bm(name, bm)
