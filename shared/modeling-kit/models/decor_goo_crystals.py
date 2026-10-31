# decor_goo_crystals: chunky rounded-tip goo crystals sprouting from a low mossy rock mound (ground decor between plots).
# ~3.4 across, ~3.5 tall. Purely decorative (no collision in game). Colour from vertex colours only.
import math, random
import bmesh
from mathutils import Matrix, Vector
from lib import *
from lib.shapes import obj_from_bm
from models._rocks import stone, pebble

P = PALETTE
GOO, GOO_HI = P["ranch_goo"], P["ranch_goo_hi"]
LILAC, PINK = P["ranch_lilac"], mix(P["ranch_pink"], P["ranch_cream"], 0.15)  # r05: softer pink (read red in shade)
FIELD, FIELD_L, FIELD_D = P["ranch_field"], P["ranch_field_light"], P["ranch_field_dark"]
ROCK = mix(mix(P["ranch_wood_dark"], P["ranch_plaza"], 0.55), rgb(186, 174, 158), 0.5)  # r02: warm stone, less orange; r05: lighter (brown in game shade)
MOSS = mix(FIELD, FIELD_L, 0.35)
R = random.Random(31)
parts = []


def crystal(name, r, length, lo, hi, sides=6, face_k=(1.06, 0.88, 0.96, 1.16, 0.9, 1.02)):
    """Closed hex crystal along +Z from z=-0.6 (sunk) to `length`: slight taper, chamfered shoulder, blunt rounded tip."""
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    zs = length * 0.72
    rows = [(-0.6, 0.9), (zs * 0.5, 1.0), (zs, 0.97), (length * 0.88, 0.62), (length, 0.0)]
    rings = []
    for z, s in rows:
        if s == 0:
            rings.append([bm.verts.new((0, 0, z))])
        else:
            rings.append([bm.verts.new((r * s * math.cos(k * math.tau / sides), r * s * math.sin(k * math.tau / sides), z))
                          for k in range(sides)])

    def paint(f, c):
        for lp in f.loops:
            lp[col] = c

    paint(bm.faces.new(list(reversed(rings[0]))), lo)
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(sides):
            k1 = (k + 1) % sides
            fk = face_k[k % len(face_k)]
            if len(b) == 1:
                f = bm.faces.new((a[k], a[k1], b[0]))
                c = shade(mix(hi, P["ranch_cream"], 0.15), fk * 1.05)
            else:
                f = bm.faces.new((a[k], a[k1], b[k1], b[k]))
                t = [0.0, 0.35, 0.75, 1.0][i]
                c = shade(mix(lo, hi, t), fk)
            paint(f, c)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def place(o, pos, tilt, toward, spin=0.0):
    m = (Matrix.Translation(Vector(pos)) @ Matrix.Rotation(math.radians(toward), 4, "Z")
         @ Matrix.Rotation(math.radians(tilt), 4, "Y") @ Matrix.Rotation(math.radians(spin), 4, "Z"))
    o.data.transform(m)
    o.data.update()
    return o


# mound: wide low chiselled rock with a moss cap
parts.append(stone("Mound", (3.4, 3.1, 1.35), (0, 0, 0), seed=11, n=34, base=ROCK, moss=MOSS, moss_from=0.68, cuts=2))
parts.append(pebble("PebA", 0.45, (1.55, -0.9, 0), seed=12, base=shade(ROCK, 1.03)))
parts.append(pebble("PebB", 0.35, (-1.5, -0.7, 0), seed=13, base=ROCK))
parts.append(pebble("PebC", 0.4, (-0.4, 1.5, 0), seed=14, base=shade(ROCK, 0.97)))

# crystals: (x, y, base z, len, radius, tilt, toward, colour)
GOO_LO = mix(GOO, P["ranch_field_dark"], 0.25)
CR = [
    (-0.1, 0.2, 1.1, 2.9, 0.6, 10, 120, GOO),
    (-0.75, 0.45, 0.95, 2.2, 0.52, 34, 150, GOO),
    (0.7, 0.5, 0.95, 2.3, 0.52, 32, 45, LILAC),
    (0.35, -0.5, 1.0, 1.8, 0.48, 38, -60, GOO),
    (-0.65, -0.45, 0.9, 1.6, 0.44, 44, -135, PINK),
    (1.0, -0.15, 0.7, 1.2, 0.4, 56, -10, GOO),
    (-1.05, -0.05, 0.6, 0.9, 0.34, 58, 185, GOO),
    (1.7, 0.6, 0.1, 0.95, 0.36, 44, 25, GOO),  # r03: loose shard on the grass (r04: chunkier, clipped at z=0)
]
for i, (x, y, z, ln, r, tilt, tw, c) in enumerate(CR):
    lo = mix(c, GOO_LO, 0.15) if c is GOO else mix(c, P["ranch_cream"], 0.08)  # r04: lighter shadow sides (roblox look went dark)
    hi = GOO_HI if c is GOO else mix(c, P["ranch_cream"], 0.45)
    o = place(crystal(f"Crystal{i}", r, ln, lo, hi), (x, y, z), tilt, tw, R.uniform(0, 60))
    bm = bmesh.new()  # r04: clip at the ground so a sunk base never drops the origin below the grass
    bm.from_mesh(o.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
    bmesh.ops.contextual_create(bm, geom=[e for e in bm.edges if e.is_boundary])
    bm.to_mesh(o.data)
    bm.free()
    parts.append(o)

finish("decor_goo_crystals", parts)
