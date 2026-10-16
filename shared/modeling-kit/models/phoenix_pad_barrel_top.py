# phoenix_pad_barrel_top: a big barrel lying on its side (axis X, 7.6 long), sawn open along the top at z=2.4
# (= crate pad top) and brimming with goo; the slime stands on the flat goo fill inside the wood rim.
# Rests on two dark cradle chocks; pewter hoops, red painted heads; one metaball goo drip over the front (-Y) rim.
import math
import bmesh
from mathutils import Vector
from lib import *
from lib.goo import Ball, frame_quat, metaball_mesh, paint_goo
from lib.shapes import obj_from_bm
from models._phoenix_pad import *

L, R0, BULGE = 7.6, 3.6, 0.09   # length, mid radius, end shrink fraction
ZB, ZT = 0.3, 2.4                # belly bottom (mid), sawn top
ZC = ZB + R0                     # barrel axis height
RIM, DIP = 0.32, 0.12            # wood rim width, goo fill below the rim
METAL, PLAZA = P["ranch_metal"], P["ranch_plaza"]
WOOD_LO, WOOD_HI = mix(WOOD_D, WOOD, 0.75), mix(WOOD, CREAM, 0.15)  # r05: lows lifted, belly went mud-brown in shade
parts = []


def rad(x):
    return R0 * (1 - BULGE * (2 * x / L) ** 2)


def hull(name, x0, x1, nx, grow=0.0, zt=ZT, cols=14, open_top=False):
    """closed barrel segment between x0..x1, cut flat at zt; returns (obj)."""
    bm = bmesh.new()
    rows = []
    for i in range(nx + 1):
        x = x0 + (x1 - x0) * i / nx
        r = rad(x) + grow
        tc = math.acos((ZC - zt) / r)
        rows.append([bm.verts.new((x, r * math.sin(-tc + 2 * tc * j / cols), ZC - r * math.cos(-tc + 2 * tc * j / cols)))
                     for j in range(cols + 1)])
    side, top = [], []
    for i in range(nx):
        a, b = rows[i], rows[i + 1]
        for j in range(cols):
            side.append((bm.faces.new((a[j], b[j], b[j + 1], a[j + 1])), j))
        top.append(bm.faces.new((a[cols], b[cols], b[0], a[0])))
    caps = [bm.faces.new(rows[0]), bm.faces.new(list(reversed(rows[-1])))]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    inner = []
    if open_top:
        bmesh.ops.inset_region(bm, faces=top, thickness=RIM, depth=0)
        bmesh.ops.translate(bm, vec=(0, 0, -DIP), verts=list({v for f in top for v in f.verts}))
        # r03: thin goo_hi meniscus ring along the rim; the flat fill read as a pool-table felt
        men = bmesh.ops.inset_region(bm, faces=top, thickness=0.14, depth=0)["faces"]
        bmesh.ops.translate(bm, vec=(0, 0, -0.03), verts=list({v for f in top for v in f.verts}))
        inner = top
    else:
        men = []
    # r02: recessed heads behind a stave chime, so the ends read as barrel heads, not a half-moon slab
    heads = []
    for cf, dx in ((caps[0], 0.22), (caps[1], -0.22)):
        bmesh.ops.inset_region(bm, faces=[cf], thickness=0.28, depth=0)
        bmesh.ops.translate(bm, vec=(dx, 0, 0), verts=list(cf.verts))
        heads.append(cf)
    caps = heads
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = f.calc_center_median()
        if f in inner:
            col = GOO
        elif f in men:
            col = mix(GOO, GOO_HI, 0.6)
        elif f.normal.z > 0.9:
            col = WOOD_HI                       # sawn rim
        elif f in caps:
            col = mix(ROOF, PINK, 0.35)         # r06 red heads (r07: lifted toward pink, the shadow-side head went maroon)
        elif abs(f.normal.x) > 0.9:
            col = WOOD_HI                       # chime (stave ends)
        else:
            j = next((j for g, j in side if g == f), 0)
            col = mix(WOOD_LO, WOOD, max(0.0, min(1.0, (c.z - ZB) / (ZT - ZB))))
            if j % 2:
                col = shade(col, 0.88)  # r04: stronger stave read
        for lp in f.loops:
            lp[layer] = (*col[:3], 1.0)
    return obj_from_bm(name, bm)


parts.append(hull("Barrel", -L / 2, L / 2, 8, open_top=True))
for k, x in enumerate((-3.2, -1.2, 1.2, 3.2)):
    h = hull(f"Hoop{k}", x - 0.18, x + 0.18, 1, grow=0.07, zt=ZT - 0.3, cols=14)  # r02: hoop deck under the goo
    gradient(h, METAL, mix(METAL, CREAM, 0.35))  # r04: light pewter (churn lesson)
    parts.append(h)
for s in (-1, 1):
    parts.append(bbox(f"Chock{s}", (0.9, 5.4, 1.1), (s * 2.2, 0, 0.55), shade(WOOD_D, 0.92), WOOD_D, bev=0.12))

# goo: lip roll + short drip over the front (-Y) rim
def surf(x, th, off=0.0):
    r = rad(x) + off
    return Vector((x, r * math.sin(th), ZC - r * math.cos(th))), Vector((0, math.sin(th), -math.cos(th)))

balls = []
X0 = 0.5
tc = math.acos((ZC - ZT) / rad(X0))
p, n = surf(X0, -tc)
balls.append(Ball((X0, p.y + 0.3, ZT - 0.17), (0.8, 0.55, 0.1)))  # lip roll (r03/r04: lowered, r02 bulged 0.25 over the top)
# r03: a short drip hanging off the rim (the belly curves in under the cut, so a run along it tucked out of sight)
for j, (dz, w) in enumerate(((0.36, 0.5), (0.62, 0.42), (0.86, 0.34))):  # r05: first lens poked 0.06 over the rim
    balls.append(Ball((X0, p.y - 0.12 - 0.05 * j, ZT - dz), (w, 0.13, 0.26)))
balls.append(Ball((X0, p.y - 0.28, ZT - 1.1), 0.27))                     # fat tip
# r04: ground puddle dropped; 1.3 below the drip tip it read as a separate decal
spill = metaball_mesh("GooSpill", balls, resolution=0.12, tris=260)
parts.append(paint_goo(spill, lambda co, n: mix(GOO, GOO_HI, 0.12 + 0.2 * max(0.0, n.z) ** 6)))
# r06: goo_hi bubbles dropped: at sheet size they read as grey specks on the fill

finish("phoenix_pad_barrel_top", parts)
