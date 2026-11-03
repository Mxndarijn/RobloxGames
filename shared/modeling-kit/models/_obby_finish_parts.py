# Shared helpers for the obby finish options (obby_finish_a/b/c), not an asset.
# Layout every option is built against (1 BU = 1 stud, Z up): the finish slab's TOP is z = 0, the lane runs
# x in [-12, 12] (24 wide), the slab y in [-6, 6] (12 deep). Runners arrive from -Y (the course) and walk +Y.
# Decor stays clear of the walking box x in [-12, 12], z in [0, 12] except low flat floor marks and things at the
# back/edges; the slab itself is the game's part, not part of these meshes.
import math
import bmesh
from mathutils import Vector
from lib import *
from lib.shapes import obj_from_bm, _place
from models._obby_cannon_parts import lathe, band, bb, smooth, finish_smooth, GOO_DEEP, GOO, GOO_HI

LANE = 12.0  # half lane width
SLAB_Y = 6.0  # half slab depth
CLEAR = 12.0  # head clearance over the slab top

# Colours (lifted for the Roblox look; red is kept for hazards in the obby, so none here)
GOLD_LO = rgb(250, 190, 60)
GOLD = rgb(255, 212, 70)
GOLD_HI = rgb(255, 244, 160)
VIOLET_LO = rgb(140, 100, 226)
VIOLET = rgb(176, 136, 255)
VIOLET_HI = rgb(214, 190, 255)
CYAN_LO = rgb(70, 170, 240)
CYAN = rgb(110, 204, 255)
CYAN_HI = rgb(180, 234, 255)
LIME = rgb(150, 230, 70)
WHITE = rgb(250, 250, 255)
CHECK_DARK = rgb(58, 52, 84)  # the dark squares: dark on purpose, a checker needs the contrast
INK = rgb(36, 28, 44)
SLAB = rgb(255, 206, 64)  # the game's finish slab colour (ObbyParts look `finish`), preview only


def checker(name, w, h, nx, ny, c1=WHITE, c2=CHECK_DARK, thick=0.3, sub=1, wave=None, pos=(0, 0, 0),
            rot=(0, 0, 0), edge=None):
    """A closed checker panel in the XZ plane (x across, z up, centred), `thick` deep along Y.
    nx x ny squares; `sub` columns per square (for a smooth wave); wave(u, v) -> y offset, u/v in 0..1 across/up."""
    edge = edge or c1
    bm = bmesh.new()
    lay = bm.loops.layers.color.new("Col")
    cols = nx * sub
    F, B = [], []
    for j in range(ny + 1):
        rf, rb = [], []
        for i in range(cols + 1):
            u, v = i / cols, j / ny
            dy = wave(u, v) if wave else 0.0
            x, z = (u - 0.5) * w, (v - 0.5) * h
            rf.append(bm.verts.new((x, dy - thick / 2, z)))
            rb.append(bm.verts.new((x, dy + thick / 2, z)))
        F.append(rf)
        B.append(rb)

    def face(vs, c):
        f = bm.faces.new(vs)
        for lp in f.loops:
            lp[lay] = c
        return f

    for j in range(ny):
        for i in range(cols):
            c = c1 if ((i // sub) + j) % 2 == 0 else c2
            face((F[j][i], F[j][i + 1], F[j + 1][i + 1], F[j + 1][i]), c)
            face((B[j][i + 1], B[j][i], B[j + 1][i], B[j + 1][i + 1]), c)
    # the rim
    loop = [(0, i) for i in range(cols + 1)] + [(j, cols) for j in range(1, ny + 1)]
    loop += [(ny, i) for i in range(cols - 1, -1, -1)] + [(j, 0) for j in range(ny - 1, 0, -1)]
    for k in range(len(loop)):
        (ja, ia), (jb, ib) = loop[k], loop[(k + 1) % len(loop)]
        face((F[ja][ia], B[ja][ia], B[jb][ib], F[jb][ib]), edge)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm)


def slab(name, pts, depth, col, pos=(0, 0, 0), rot=(0, 0, 0), back=None):
    """A flat cut-out: 2D outline [(x, z)] (convex or fan-able from its first point) extruded `depth` along Y."""
    back = back or col
    bm = bmesh.new()
    lay = bm.loops.layers.color.new("Col")
    fr = [bm.verts.new((x, -depth / 2, z)) for x, z in pts]
    bk = [bm.verts.new((x, depth / 2, z)) for x, z in pts]
    n = len(pts)

    def face(vs, c):
        f = bm.faces.new(vs)
        for lp in f.loops:
            lp[lay] = c

    face(list(reversed(fr)), col)
    face(bk, back)
    for k in range(n):
        face((fr[k], fr[(k + 1) % n], bk[(k + 1) % n], bk[k]), mix(col, back, 0.5))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _place(bm, pos, rot)
    return obj_from_bm(name, bm)


def pole(name, base, height, r, lo, hi, stripes=0, c2=None, segs=10, tilt=(0, 0, 0)):
    """An upright pole (lathe) with optional candy stripes (bands of c2)."""
    if stripes:
        prof, cols = [(0, 0)], []
        n = stripes * 2
        for k in range(n + 1):
            prof.append((r, height * k / n))
        prof.append((0, height))
        cols.append(lo)
        for k in range(n):
            cols.append(mix(lo, hi, k / n) if k % 2 == 0 else c2)
        cols.append(hi)
    else:
        prof = [(0, 0), (r, 0), (r, height), (0, height)]
        cols = [lo, mix(lo, hi, 0.5), hi]
    return lathe(name, prof, cols, segs=segs, pos=base, rot=tilt)


def ball(name, r, pos, lo, hi, subdiv=2):
    o = blob(name, r, pos, hi, subdiv=subdiv, jitter=0)
    gradient(o, lo, hi)
    return smooth(o)


def pennant(name, at, length, height, col, down=True, rot=(0, 0, 0), depth=0.16):
    """A triangle flag: its top edge at `at`, pointing down (bunting) or along +X (pole flag)."""
    if down:
        pts = [(-length / 2, 0), (length / 2, 0), (0, -height)]
    else:
        pts = [(0, 0), (length, -height / 2), (0, -height)]
    return slab(name, pts, depth, col, pos=at, rot=rot, back=shade(col, 0.9))


def catenary(a, b, sag, n=12):
    a, b = Vector(a), Vector(b)
    pts = []
    for k in range(n + 1):
        t = k / n
        p = a.lerp(b, t)
        p.z -= sag * 4 * t * (1 - t)
        pts.append(p)
    return pts


def rope(name, pts, r, col, segs=5):
    return tube(name, [tuple(p) for p in pts], [r] * len(pts), col, segs=segs)


def balloon(name, pos, r, col, lo=None):
    """A balloon: a lathe teardrop (round top, narrower bottom) with a little knot."""
    lo = lo or shade(col, 0.78)
    prof = []
    for k in range(9):
        t = k / 8  # 0 = bottom tip, 1 = top pole
        a = math.pi * (1 - t)
        rr = math.sin(a) * r * (0.62 + 0.38 * t)
        z = -math.cos(a) * r * 1.12
        prof.append((rr if 0 < k < 8 else 0.0, z))
    cols = [mix(lo, col, k / 7) for k in range(8)]
    cols[-2] = mix(col, WHITE, 0.35)  # a soft shine near the top
    o = lathe(name, prof, cols, segs=12, pos=pos)
    knot = lathe(name + "Knot", [(0, -0.28 * r), (0.16 * r, -0.12 * r), (0, 0)], [lo, lo], segs=6,
                 pos=(pos[0], pos[1], pos[2] - r * 1.12))
    return [smooth(o), knot]


def eyes(prefix, centre, face_dir, spread, r=0.55, pupil=0.3):
    """Two cartoon eyes on a body surface at `centre` (eye midpoint), facing `face_dir` (unit, horizontal)."""
    d = Vector(face_dir).normalized()
    side = d.cross(Vector((0, 0, 1))).normalized()
    out = []
    for s in (-1, 1):
        c = Vector(centre) + side * (s * spread)
        w = blob(f"{prefix}W{s}", r, c, WHITE, subdiv=2, squash=(1, 1, 1.15), jitter=0)
        p = blob(f"{prefix}P{s}", pupil, c + d * (r * 0.78) + Vector((0, 0, 0.06)), INK, subdiv=2,
                 squash=(1, 1, 1.2), jitter=0)
        glint = blob(f"{prefix}G{s}", pupil * 0.32, c + d * (r * 0.78 + pupil * 0.55) + side * (-0.1) +
                     Vector((0, 0, pupil * 0.45)), WHITE, subdiv=1, jitter=0)
        out += [smooth(w), smooth(p), glint]
    return out


def goo_color(lo=GOO_DEEP, mid=GOO, hi=GOO_HI, z0=0.0, z1=1.0):
    def f(co, n):
        t = max(0.0, min(1.0, (co.z - z0) / max(1e-6, z1 - z0)))
        c = mix(lo, mid, min(1.0, 0.3 + t))
        g = n.dot(Vector((0, -0.45, 0.89)).normalized())
        if g > 0.75:
            c = mix(c, hi, min(1.0, (g - 0.75) / 0.25) * 0.75)
        return c
    return f


def drip_balls(top, length, w):
    """Metaball chain for one hanging goo drip: thin neck, round drop."""
    top = Vector(top)
    out = []
    for k in range(6):
        t = k / 5
        out.append(Ball(top + Vector((0, 0, -length * t)), w * (1 - t) ** 1.6 * 0.8 + w * 0.32))
    out.append(Ball(top + Vector((0, 0, -length - w * 0.25)), w * 0.7))
    return out


def report(name, objs):
    """Print the set's bbox in slab coordinates (before finish() re-centres it) for wiring it in the game."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for v in o.data.vertices:
            p = o.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    c = (lo + hi) / 2
    print(f"FINISH {name}: bbox x {lo.x:.2f}..{hi.x:.2f} y {lo.y:.2f}..{hi.y:.2f} z {lo.z:.2f}..{hi.z:.2f}; "
          f"mesh origin (bottom centre) at slab ({c.x:.2f}, {c.y:.2f}, {lo.z:.2f})")
