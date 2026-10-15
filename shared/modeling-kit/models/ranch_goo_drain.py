# ranch_goo_drain: round goo drain at the silo foot / plaza edge where unclaimed wild slimes
# visibly slurp away (despawn telegraph, Steal-a-Brainrot style: the slime slides to the drain and
# sinks through a swirling goo funnel, never a silent pop). Visual prop only, no wiring.
# ~9 x 9 footprint, low (curb ~1.3 + warning post ~4.2). Swirl funnel + brass grate + barn-red /
# butter warning ring + small "drain" post with a down-arrow plaque.
import math
import bmesh
from lib import *

PLAZA = PALETTE["ranch_plaza"]
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
BUTTER, ROOF, ROOF_D = PALETTE["ranch_butter"], PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
METAL, CREAM = PALETTE["ranch_metal"], PALETTE["ranch_cream"]
WOOD_LO = mix(WOOD_D, WOOD, 0.4)
PLAZA_LO = mix(PLAZA, WOOD, 0.35)
parts = []


def ring(name, r0, r1, z0, z1, segs, a0=0.0, a1=360.0, closed=True):
    """Closed annular (sector) solid."""
    bm = bmesh.new()
    n = segs if closed else segs + 1
    ang = [math.radians(a0 + (a1 - a0) * i / segs) for i in range(n)]
    def lay(r, z):
        return [bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)) for a in ang]
    ob, ib, ot, it = lay(r1, z0), lay(r0, z0), lay(r1, z1), lay(r0, z1)
    m = segs
    for i in range(m):
        j = (i + 1) % n if closed else i + 1
        bm.faces.new((ob[i], ob[j], ot[j], ot[i]))
        bm.faces.new((ib[j], ib[i], it[i], it[j]))
        bm.faces.new((ot[i], ot[j], it[j], it[i]))
        bm.faces.new((ob[j], ob[i], ib[i], ib[j]))
    if not closed:
        bm.faces.new((ob[0], ot[0], it[0], ib[0]))
        bm.faces.new((ob[-1], ib[-1], it[-1], ot[-1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


# base: plaza-stone curb ring (the lip a slime slides over)
o = ring("Curb", 3.3, 4.4, 0, 1.0, 24)
bevel(o, 0.15)
gradient(o, PLAZA_LO, PLAZA)
parts.append(o)
# warning ring on the curb top: alternating barn-red / butter tiles (readable from afar)
N = 12
for k in range(N):
    a0 = k * 360 / N + 2
    t = ring(f"Warn{k}", 3.45, 4.25, 1.0, 1.22, 3, a0, a0 + 360 / N - 4, closed=False)
    c = ROOF if k % 2 == 0 else BUTTER
    gradient(t, mix(ROOF_D, ROOF, 0.5) if c is ROOF else mix(BUTTER, WOOD, 0.25), c)
    parts.append(t)


# goo funnel: sunken swirl cone, spiral bands coloured goo / goo_hi so it reads as draining
def funnel(name, r_top, z_top, z_bot, rings=6, segs=24):
    bm = bmesh.new()
    rows = []
    for i in range(rings + 1):
        t = i / rings
        r = r_top * (1 - t) ** 1.3 + 0.35 * t
        z = z_top - (z_top - z_bot) * t ** 0.7
        rows.append([bm.verts.new((math.cos(k * math.tau / segs + t * 2.2) * r, math.sin(k * math.tau / segs + t * 2.2) * r, z)) for k in range(segs)])
    for i in range(rings):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((rows[i][k], rows[i][j], rows[i + 1][j], rows[i + 1][k]))
    bot = bm.verts.new((0, 0, z_bot - 0.2))
    for k in range(segs):
        bm.faces.new((rows[-1][(k + 1) % segs], rows[-1][k], bot))
    # close the top with a flat bottom plate so the solid is manifold
    under = [bm.verts.new((v.co.x, v.co.y, 0.0)) for v in rows[0]]
    for k in range(segs):
        j = (k + 1) % segs
        bm.faces.new((rows[0][j], rows[0][k], under[k], under[j]))
    bm.faces.new(list(reversed(under)))
    # the funnel tip vertex sits above `under`: fine, it's an internal cavity-free closed shell
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        cx = sum(v.co.x for v in f.verts) / len(f.verts)
        cy = sum(v.co.y for v in f.verts) / len(f.verts)
        r = math.hypot(cx, cy)
        a = math.atan2(cy, cx)
        band = math.sin(3 * a + r * 1.8) > 0.25
        col = GOO_HI if band else GOO
        col = shade(col, 0.75 + 0.25 * min(1, r / r_top))
        for lp in f.loops:
            lp[layer] = col
    return obj_from_bm(name, bm)


parts.append(funnel("Funnel", 3.35, 0.9, 0.4))
# brass grate across the throat: 2 crossed bars + small hoop
for rot in (0, 90):
    g = box("Bar", (2.4, 0.28, 0.22), (0, 0, 0.5), rot=(0, 0, rot + 45))
    gradient(g, shade(METAL, 0.85), METAL)
    parts.append(g)
h = ring("Hoop", 0.85, 1.15, 0.38, 0.6, 12)
gradient(h, shade(METAL, 0.85), METAL)
parts.append(h)
# goo dribbles spilling over the curb into the funnel
for k, a in enumerate((20, 140, 250)):
    x, y = math.cos(math.radians(a)), math.sin(math.radians(a))
    d = blob(f"Drip{k}", 0.42, (x * 3.5, y * 3.5, 1.05), GOO, seed=k, subdiv=2, squash=(1.3, 1.3, 0.5), jitter=0.03)
    gradient(d, GOO, GOO_HI)
    parts.append(d)

# warning post with a down-arrow plaque, behind the drain (silo side = +Y)
px, py = 0, 5.0
p = box("Post", (0.7, 0.7, 4.2), (px, py, 2.1))
bevel(p, 0.1)
gradient(p, WOOD_LO, WOOD)
parts.append(p)
pl = box("Plaque", (2.6, 0.35, 1.9), (px, py - 0.5, 3.5))
bevel(pl, 0.12)
gradient(pl, mix(ROOF_D, ROOF, 0.5), ROOF)
parts.append(pl)
# butter down-arrow on both faces
for sy in (-1, 1):
    yy = py - 0.5 + sy * 0.25
    s = box("ArrowStem", (0.45, 0.2, 0.8), (px, yy, 3.85))
    gradient(s, BUTTER, BUTTER)
    parts.append(s)
    bm = bmesh.new()
    tri = [(-0.65, 3.45), (0.65, 3.45), (0, 2.8)]
    vs = [bm.verts.new((x, yy - 0.1, z)) for x, z in tri]
    bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    for v in ext["geom"]:
        if isinstance(v, bmesh.types.BMVert):
            v.co.y += 0.2
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    hd = obj_from_bm("ArrowHead", bm, BUTTER)
    parts.append(hd)

finish("ranch_goo_drain", parts)
