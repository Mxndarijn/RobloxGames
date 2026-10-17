# ranch_bat: the default melee bat (Tool 'Bat'), Slime Ranch held tool, 5.0 studs long, held upright.
# Same build as the Squeaky Hammer icon: wood shaft, red grip wrap + red pommel knob (cream trim ring),
# and a goo-dipped barrel end (ranch_goo shell with a wavy lower edge and short drips, goo_hi lip).
# Wood body and goo shell are surfaces of revolution; the goo edge is snapped per column (LESSONS:
# displacing the surface reads as melting goo, separate drip tubes read as stubby limbs).
# Grip (hand) point: centre of the red wrap, z = 1.2 above the pommel bottom.
import math
import bmesh
from lib import *
from lib.shapes import obj_from_bm

WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM, ROOF, ROOF_D = PALETTE["ranch_cream"], PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]

WOOD_LO, WOOD_HI = mix(WOOD_D, WOOD, 0.45), mix(WOOD, CREAM, 0.18)
RED, RED_LO = ROOF, mix(ROOF_D, ROOF, 0.5)
SEGS = 16

# (r, z) bottom -> top of the wood body; z=0 is the pommel bottom.
PROFILE = [
    (0.00, 0.00), (0.34, 0.00), (0.44, 0.16), (0.46, 0.38), (0.34, 0.62),  # pommel knob
    (0.27, 0.80), (0.28, 1.80),                                            # red grip wrap
    (0.31, 1.86), (0.31, 2.00),                                            # cream trim ring
    (0.34, 2.50), (0.43, 3.20), (0.53, 3.80), (0.59, 4.30), (0.57, 4.65),  # taper up to the barrel
    (0.43, 4.90), (0.00, 5.00),                                            # rounded end
]


def radius_at(z):
    for (r0, z0), (r1, z1) in zip(PROFILE, PROFILE[1:]):
        if z0 <= z <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    return 0.0


def wood_color(z, k):
    if z < 0.66:
        t = z / 0.66
        return mix(RED_LO, RED, t)
    if z < 1.83:
        return mix(RED_LO, RED, (z - 0.66) / 1.17)
    if z < 2.02:
        return mix(CREAM, mix(CREAM, WOOD, 0.35), 0.3)
    t = min(1.0, (z - 2.02) / 2.9)
    c = mix(WOOD_LO, WOOD_HI, t)
    return mix(c, WOOD_LO, 0.18) if k % 4 == 1 else c  # faint plank-stripe in the grain


def lathe_wood():
    bm = bmesh.new()
    rings = []
    for r, z in PROFILE:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(k * math.tau / SEGS), r * math.sin(k * math.tau / SEGS), z))
                          for k in range(SEGS)])
    faces = []
    for a, b in zip(rings, rings[1:]):
        for k in range(SEGS):
            k1 = (k + 1) % SEGS
            if len(a) == 1:
                vs = (a[0], b[k1], b[k])
            elif len(b) == 1:
                vs = (a[k], a[k1], b[0])
            else:
                vs = (a[k], a[k1], b[k1], b[k])
            faces.append((bm.faces.new(vs), k))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f, k in faces:
        c = wood_color(f.calc_center_median().z, k)
        for lp in f.loops:
            lp[layer] = (*c[:3], 1.0)
    return obj_from_bm("Wood", bm)


# goo dip: lower edge height per column (z), short drips where the edge is lowest
EDGE = 4.10
DRIP = [0.00, 0.20, 0.55, 0.85, 0.30, 0.00, 0.10, 0.45, 0.60, 0.15, 0.00, 0.00, 0.40, 1.10, 0.75, 0.25]
GOO_ROWS = [4.38, 4.68, 4.88]  # fixed rows above the free edge row
THICK = 0.09


def goo_cap():
    bm = bmesh.new()

    def ring(z_of_col, dr, kcount=SEGS):
        out = []
        for k in range(kcount):
            z = z_of_col(k)
            r = radius_at(z) + dr
            a = k * math.tau / SEGS
            out.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        return out

    edge = ring(lambda k: EDGE - DRIP[k], 0.045)  # free row, snapped per column
    rows = [edge] + [ring(lambda k, z=z: z, THICK) for z in GOO_ROWS]
    top = bm.verts.new((0, 0, 5.0 + THICK))
    faces = []
    for ri, (a, b) in enumerate(zip(rows, rows[1:])):
        for k in range(SEGS):
            k1 = (k + 1) % SEGS
            faces.append((bm.faces.new((a[k], a[k1], b[k1], b[k])), ri, k))
    for k in range(SEGS):
        k1 = (k + 1) % SEGS
        faces.append((bm.faces.new((rows[-1][k], rows[-1][k1], top)), len(rows) - 1, k))
    # close the underside: a skirt from the free edge into the wood, capped inside it (hidden, keeps 0 nm)
    inner = [bm.verts.new((v.co.x * 0.7, v.co.y * 0.7, v.co.z)) for v in edge]
    for k in range(SEGS):
        k1 = (k + 1) % SEGS
        faces.append((bm.faces.new((edge[k1], edge[k], inner[k], inner[k1])), 0, k))
    cap = bm.faces.new(inner[::-1])
    bmesh.ops.triangulate(bm, faces=[cap])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        if f not in [x[0] for x in faces]:
            for lp in f.loops:
                lp[layer] = (*GOO[:3], 1.0)
    for f, ri, k in faces:
        c = mix(GOO, GOO_HI, 0.55) if ri == 0 else (GOO if ri < 3 else mix(GOO, GOO_HI, 0.35))
        if ri == 0 and DRIP[k] > 0.5:
            c = mix(GOO, GOO_HI, 0.75)  # drip tips catch the light
        for lp in f.loops:
            lp[layer] = (*c[:3], 1.0)
    return obj_from_bm("Goo", bm)


parts = [lathe_wood(), goo_cap()]
finish("ranch_bat", parts)
