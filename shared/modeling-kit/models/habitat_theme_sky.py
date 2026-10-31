# habitat_theme_sky: sky-isle theme for the habitat pad (Zap, Thunderbee, Seraph, Prism, Aurora, Kirin, Skyisle).
# Props on the back and sides of the rim only (the frame mesh supplies the ring): a small rainbow arc over the back
# whose feet stand in fluffy cloud puffs, more cloud puffs stepping down the sides, two golden stars floating over
# the side clouds and little sparkles. The front arc stays clear.
import math, random
from mathutils import Matrix, Vector
import bmesh
from lib import *
from lib.shapes import obj_from_bm
from models._habitat_overlay import *
from models._habitat_theme_bits import *

CLOUD, CLOUD_D = rgb(255, 255, 255), rgb(226, 236, 255)  # light underside: the Roblox look turns periwinkle grey
GOLD, GOLD_D = rgb(255, 216, 76), rgb(250, 192, 60)  # lows near the base or gold goes brown in game
BANDS = [rgb(255, 92, 92), rgb(255, 160, 60), rgb(255, 226, 80), rgb(110, 214, 110), rgb(90, 170, 255), rgb(176, 120, 240)]
parts = []


def cloud(name, ang, puffs, seed, dr=0.0):
    """Cloud cluster: separate overlapping smooth icospheres (a scalloped cartoon outline), bottoms flattened onto
    the deck, painted white on top and soft periwinkle underneath. puffs = [(dt, dr, z, r), ...]."""
    a = math.radians(ang)
    bx, by, _ = at(ang, dr=dr)
    tg = Vector((-math.sin(a), math.cos(a), 0))
    out = Vector((math.cos(a), math.sin(a), 0))
    objs = []
    for k, (dt, ddr, z, r) in enumerate(puffs):
        c = Vector((bx, by, z)) + tg * dt + out * ddr
        p = blob(f"{name}{k}", r, c, None, seed=seed + k, subdiv=2, jitter=0.03, squash=(1.0, 1.0, 0.9))
        if c.z - r * 0.9 < 0.0:  # cut off the buried bottom and cap it (fewer tris than a squashed-flat underside)
            bm = bmesh.new()
            bm.from_mesh(p.data)
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
            edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
            bm.to_mesh(p.data)
            bm.free()
            p.data.update()
        objs.append(paint_faces(p, lambda cc, n: CLOUD if n.z > -0.45 else CLOUD_D))
    return objs


def rainbow(name, cx, cy, z0, r_out, r_in, depth=0.22, segs=10):
    """Rainbow arc in the x-z plane at y = cy (wider than RIGID, so round_up bends it round the back of the rim):
    one closed shell, a colour band per ring on the front and back faces, outer band red."""
    n = len(BANDS)
    bm = bmesh.new()
    cl = bm.loops.layers.color.new("Col")
    radii = [r_out - (r_out - r_in) * b / n for b in range(n + 1)]
    rows = []
    for k in range(segs + 1):
        t = math.pi * k / segs
        c, s = math.cos(t), math.sin(t)
        rows.append(([bm.verts.new((cx + c * r, cy - depth / 2, z0 + s * r)) for r in radii],
                     [bm.verts.new((cx + c * r, cy + depth / 2, z0 + s * r)) for r in radii]))

    def face(vs, cc):
        f = bm.faces.new(vs)
        for lp in f.loops:
            lp[cl] = cc

    for k in range(segs):
        (fa, ba), (fb, bb) = rows[k], rows[k + 1]
        for b in range(n):
            face((fa[b], fa[b + 1], fb[b + 1], fb[b]), BANDS[b])
            face((ba[b], bb[b], bb[b + 1], ba[b + 1]), BANDS[b])
        face((fa[0], fb[0], bb[0], ba[0]), shade(BANDS[0], 0.86))
        face((fa[n], ba[n], bb[n], fb[n]), shade(BANDS[-1], 0.86))
    for (f, bk), flip in ((rows[0], False), (rows[-1], True)):
        for b in range(n):
            vs = (f[b], bk[b], bk[b + 1], f[b + 1])
            face(tuple(reversed(vs)) if flip else vs, shade(BANDS[b], 0.8))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return [obj_from_bm(name, bm)]


# --- back: rainbow arc with its feet in two big clouds ---
parts += rainbow("Rainbow", 0.0, BAND, 0.45, 1.72, 1.06)
for side in (1, -1):
    ang = 90 - 26 * side  # under each foot of the arc
    parts += cloud(f"FootCloud{side}", ang, [(0.0, 0.0, 0.36, 0.46), (0.34 * side, 0.05, 0.24, 0.33), (-0.06 * side, 0.1, 0.7, 0.3)], 10 + side * 5)

# --- sides: a tall cloud stack with a golden star floating over it, then a lower puff toward the front ---
for side in (1, -1):
    ang = 20 if side == 1 else 160
    parts += cloud(f"SideCloud{side}", ang, [(0.0, 0.0, 0.32, 0.42), (-0.32 * side, 0.03, 0.22, 0.3), (0.1 * side, 0.02, 0.68, 0.28)], 40 + side * 5)
    sx, sy, _ = at(ang, dr=0.0)
    st = star_slab(f"Star{side}", 0.4, 0.18, 0.16, (0, 0, 0), GOLD, rim=GOLD_D)
    st.data.transform(Matrix.Translation((sx, sy, 1.45)) @ Matrix.Rotation(math.radians(ang + 90), 4, "Z")
                      @ Matrix.Rotation(math.radians(12 * side), 4, "Y"))
    st.data.update()
    parts.append(st)
    parts += cloud(f"LowCloud{side}", -12 if side == 1 else 192, [(0.0, 0.0, 0.18, 0.3), (0.28 * side, 0.02, 0.12, 0.22)], 60 + side * 5)

# --- sparkles: small gold stars round the rainbow ---
for k, (ang, z, r) in enumerate(((60, 2.0, 0.18), (122, 2.15, 0.16))):
    x, y, _ = at(ang, dr=-0.05)
    sp = star_slab(f"Sparkle{k}", r, r * 0.42, 0.08, (0, 0, 0), GOLD, rim=GOLD_D, points=4)
    sp.data.transform(Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(ang + 90), 4, "Z"))
    sp.data.update()
    parts.append(sp)

theme_finish("habitat_theme_sky", parts)
