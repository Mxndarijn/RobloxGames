# ranch_crate_goo: variant of ranch_crate (same 3 x 3 x 3 footprint, flat top and bottom, so
# both stack on each other): barn-red painted slats, cream posts, and a goo label band with
# a raised goo-drop emblem on front and back. Builder in models/_ranch_crate.py.
import math
import bmesh
from lib import *
from models._ranch_crate import crate, pbox, H

# Slime Ranch palette (theme table, sRGB 0-255)
WOOD, WOOD_D = PALETTE["ranch_wood"], PALETTE["ranch_wood_dark"]
CREAM = PALETTE["ranch_cream"]
ROOF, ROOF_D = PALETTE["ranch_roof"], PALETTE["ranch_roof_dark"]
GOO, GOO_HI = PALETTE["ranch_goo"], PALETTE["ranch_goo_hi"]
C = {"core": WOOD_D}

WOOD_LO = mix(WOOD_D, WOOD, 0.4)
WOOD_HI = mix(WOOD, CREAM, 0.2)
parts = crate(C, slat_lo=mix(ROOF_D, ROOF, 0.5), slat_hi=ROOF, post_lo=mix(CREAM, WOOD, 0.3), post_hi=CREAM,
              deck_lo=WOOD_LO, deck_hi=WOOD_HI, seed=1)


def drop(name, w, h, thick, pos, face, color_lo, color_hi):
    """Teardrop emblem: 2D outline (round bottom, pointed top) extruded `thick` along -face*Y."""
    bm = bmesh.new()
    pts = []
    n = 14
    for i in range(n):
        a = -math.pi / 2 + i * math.tau / n          # start at the bottom
        x, z = math.cos(a) * w / 2, math.sin(a) * w / 2
        if z > 0:                                     # pull the upper half into a point
            k = z / (w / 2)
            x *= (1 - k) ** 1.4
            z = z + k * (h - w)
        pts.append((x, z))
    vs = [bm.verts.new((pos[0] + x, pos[1], pos[2] + z)) for x, z in pts]
    f = bm.faces.new(vs)
    ex = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, face * thick, 0), verts=[e for e in ex["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, color_hi)
    gradient(o, color_lo, color_hi)
    return o


# goo label band: a painted board across the slats of front and back, flush with the posts
# (footprint stays 3 x 3 so it stacks), drop emblem sunk into it, its face at the post line
for face in (-1, 1):
    y = face * (H - 0.18)
    band = pbox(f"Band{face}", (1.7, 0.3, 1.0), (0, y, 1.55), GOO, mix(GOO, GOO_HI, 0.45), bev=0.1)
    parts.append(band)
    parts.append(drop(f"Drop{face}", 0.72, 0.95, 0.1, (0, face * (H - 0.1), 1.1), face, mix(GOO_HI, CREAM, 0.2), CREAM))

finish("ranch_crate_goo", parts)
