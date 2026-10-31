# Habitat frame helpers (not an asset). A frame is the rarity ring on the dish round the slime: inner radius R_IN
# (2.6, just round the slime), outer radius R_OUT (3.75, the dish rim), ring top <= 0.30, tier detail (planks,
# blocks, rivets, gems, stars) <= 0.45 and inside the band. z = 0 = the dish rim, like the overlays.
# Frames are built ROUND (polar coordinates) and skip overlay_finish's round_up: round_up maps the square layout
# onto the circle by radius max(|x|, |y|), so a point already on a circle at 45 degrees would land at 0.71 of its
# radius (inside the slime). frame_finish keeps the rest of overlay_finish: on_deck, the HABITAT_PREVIEW stand and
# the OVERLAY check line.
import math
import bmesh
from lib import *
from lib.shapes import obj_from_bm
from models._habitat_overlay import DECK, INNER, HALF, PREVIEW, check, on_deck
from models._goo_jar import cork_stand

R_IN = INNER / 2  # 2.6
R_OUT = HALF  # 3.75
MID = (R_IN + R_OUT) / 2  # 3.175, band centre line
TAU = math.tau


def polar(r, th, z=0.0):
    return (r * math.cos(th), r * math.sin(th), z)


def spots(n, phase=0.0, r=MID):
    """n evenly spaced spots round the ring, from the front (-Y) counter-clockwise: (x, y, theta, outward_deg).
    phase is in fractions of one step."""
    out = []
    for i in range(n):
        th = -math.pi / 2 + (i + phase) * TAU / n
        out.append((r * math.cos(th), r * math.sin(th), th, math.degrees(th)))
    return out


def arc_mesh(name, th0, th1, profile, col, segs=8, closed=False, col_fn=None, side_k=0.8):
    """A ring (closed=True, th1 ignored) or capped arc piece swept round the centre.
    profile: list of (r, z), or fn(theta) -> list, an open polyline from the inner bottom over the top to the outer
    bottom (the bottom edge closes it). Arc pieces need a convex profile (their end caps are n-gons).
    Colours: col_fn(seg, edge, kind, theta_mid) -> colour, else col on top edges, shade(col, side_k) on walls,
    darker underneath. kind is 'top', 'side' or 'bottom'."""
    prof = profile if callable(profile) else (lambda th, p=profile: p)
    n = segs if closed else segs + 1
    if closed:
        ths = [th0 + TAU * k / segs for k in range(segs)]
    else:
        ths = [th0 + (th1 - th0) * k / segs for k in range(n)]
    bm = bmesh.new()
    lay = bm.loops.layers.color.new("Col")
    rings = []
    for th in ths:
        c, s = math.cos(th), math.sin(th)
        rings.append([bm.verts.new((r * c, r * s, z)) for r, z in prof(th)])
    m = len(rings[0])

    def kind(p, q):
        (r0, z0), (r1, z1) = p, q
        if z0 < 1e-6 and z1 < 1e-6:
            return "bottom"
        return "top" if abs(z1 - z0) < abs(r1 - r0) * 1.2 else "side"

    def paint(f, c):
        for lp in f.loops:
            lp[lay] = c

    base = prof(ths[0])
    for si in range(segs):
        a, b = rings[si], rings[(si + 1) % n]
        tm = (ths[si] + (ths[(si + 1) % n] if (si + 1) < n else ths[0] + TAU)) / 2
        for j in range(m):
            j1 = (j + 1) % m
            k = kind(base[j], base[j1])
            f = bm.faces.new((a[j], a[j1], b[j1], b[j]))
            if col_fn:
                c = col_fn(si, j, k, tm)
            else:
                c = col if k == "top" else (shade(col, side_k) if k == "side" else shade(col, 0.6))
            paint(f, c)
    if not closed:
        for ring in (rings[0], rings[-1]):
            f = bm.faces.new(ring)
            paint(f, shade(col, side_k * 0.95))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def chamfer_profile(r0, r1, z0, h, ch=0.05):
    """Convex block section: from (r0, z0) up to h with chamfered top corners."""
    return [(r0, z0), (r0, h - ch), (r0 + ch, h), (r1 - ch, h), (r1, h - ch), (r1, z0)]


def star_prism(name, r_out, r_in, h, pos, col, rot=(0, 0, 0), points=5, side_k=0.82):
    """A flat star (points-pointed) prism standing on pos, its top facing +Z: 4 * points tris on each face."""
    import mathutils
    bm = bmesh.new()
    lay = bm.loops.layers.color.new("Col")
    n = points * 2
    lo, hi = [], []
    for k in range(n):
        a = math.pi / 2 + k * math.pi / points
        r = r_out if k % 2 == 0 else r_in
        lo.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0)))
        hi.append(bm.verts.new((r * math.cos(a), r * math.sin(a), h)))
    cl, ch_ = bm.verts.new((0, 0, 0)), bm.verts.new((0, 0, h * 1.25))  # a slightly domed top catches the light
    for k in range(n):
        k1 = (k + 1) % n
        for f, c in ((bm.faces.new((hi[k], hi[k1], ch_)), col),
                     (bm.faces.new((lo[k1], lo[k], cl)), shade(col, 0.6)),
                     (bm.faces.new((lo[k], lo[k1], hi[k1], hi[k])), shade(col, side_k))):
            for lp in f.loops:
                lp[lay] = c
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    m = mathutils.Matrix.Translation(pos) @ mathutils.Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return obj_from_bm(name, bm)


def gem(name, r, pos, col, h=None, segs=6, bezel=None, rot=(0, 0, 0)):
    """A cut gem: a crown (light table on top, darker facets) standing on pos, optionally in a low metal bezel
    (bezel colour) a bit wider than the stone. 20 tris per part at 6 segs."""
    h = h or r * 0.7
    parts = []
    z = pos[2]
    if bezel is not None:
        parts.append(cylinder(name + "_bz", r * 1.3, h * 0.35, (pos[0], pos[1], z), bezel, segs=segs, r_top=r * 1.22,
                              rot=rot))
        z += h * 0.2
    top = cylinder(name, r, h, (pos[0], pos[1], z), col, segs=segs, r_top=r * 0.55, rot=rot)
    me = top.data
    lay = me.color_attributes["Col"]
    for p in me.polygons:
        c = mix(col, rgb(255, 255, 255), 0.3) if p.normal.z > 0.95 else (col if p.normal.z > 0.2 else shade(col, 0.7))
        for li in p.loop_indices:
            lay.data[li].color = c
    parts.append(top)
    return parts


def _bm_obj(name, verts, faces, cols):
    bm = bmesh.new()
    lay = bm.loops.layers.color.new("Col")
    vs = [bm.verts.new(v) for v in verts]
    for f, c in zip(faces, cols):
        face = bm.faces.new([vs[i] for i in f])
        for lp in face.loops:
            lp[lay] = c
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm)


def ray(name, r0, r1, th, half_w, h, col, z=0.0):
    """A flat sun-ray point lying on the band: a low ridged triangle from radius r0 (base, width 2 * half_w) to a
    point at r1, its ridge rising to h at the base. 6 tris."""
    c, s = math.cos(th), math.sin(th)
    tx, ty = -s, c

    def P(r, w, zz):
        return (r * c + w * tx, r * s + w * ty, z + zz)

    v = [P(r0, -half_w, 0), P(r0, half_w, 0), P(r1, 0, 0), P(r0, 0, h)]
    f = [(0, 2, 3), (2, 1, 3), (1, 0, 3), (0, 1, 2)]
    return _bm_obj(name, v, f, [shade(col, 0.95), shade(col, 1.12), shade(col, 0.8), shade(col, 0.6)])


def octa(name, r, pos, col, squash=(1, 1, 0.7), rot_deg=0.0):
    """A small 8-tri bead (octahedron), light on top, darker below."""
    x, y, z = pos
    sx, sy, sz = squash
    a = math.radians(rot_deg)
    ring = [(x + r * sx * math.cos(a + k * math.pi / 2), y + r * sy * math.sin(a + k * math.pi / 2), z) for k in range(4)]
    v = ring + [(x, y, z + r * sz), (x, y, z - r * sz)]
    f = [(k, (k + 1) % 4, 4) for k in range(4)] + [((k + 1) % 4, k, 5) for k in range(4)]
    return _bm_obj(name, v, f, [shade(col, 1.08)] * 4 + [shade(col, 0.7)] * 4)


def frame_finish(name, parts):
    """finish() for a frame (see the header: no round_up). HABITAT_PREVIEW=1 draws the cork stand under it."""
    on_deck(parts, 0.0)
    if PREVIEW:
        stand = cork_stand()
        for o in stand:
            o.location.z -= DECK
        return finish(name, parts + stand)
    check(parts)
    o = finish(name, parts)
    print(f"FRAME {name} tris={tris(o)}")
    return o
