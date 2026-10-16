# Shared helpers for the Slime Ranch world-border chunks (ranch_border_chunk_a..h): one mesh per
# ~50-58 stud stretch of edge that combines hedge / rail fence / pines / hill / rocks / goo, so the
# whole border fits in ~40 MeshPart slots. Low-poly versions of the _border.py pieces (fewer,
# bigger puffs, 6-sided posts and trunks, coarse polar mounds). Not a model: no finish().
#
# Mirrored twin: CHUNK_MIRROR=1 python3 iterate.py models/ranch_border_chunk_a.py --name ranch_border_chunk_a_m
# (a Roblox MeshPart can't take a negative scale, so the game gets a second mesh).
import math, os, random
import bmesh
from mathutils import Vector
from lib import *
from models._border import FIELD, FIELD_L, FIELD_D, WOOD, WOOD_D, GOO, GOO_HI, PINK, LILAC, BUTTER, CREAM, fir, flower, tuft
from models._rocks import stone, pebble

SAND = rgb(204, 182, 150)
MOSS = mix(FIELD, FIELD_D, 0.3)
WOOD_LO = mix(WOOD_D, WOOD, 0.45)
MIRROR = os.environ.get("CHUNK_MIRROR") == "1"


def lowpoly(o, ratio):
    """Collapse-decimate one closed part (keeps it closed; LESSONS ranch_windmill: spend tris on outline)."""
    return decimate(o, ratio) if ratio < 1 else o


def hedge_run(prefix, x0, x1, y, R, h=5.0, d=3.6, blooms=2, ratio=0.6):
    """Clipped hedge from x0 to x1 along X at depth y: hidden core + one row of big puffs + crown."""
    w = x1 - x0
    cx = (x0 + x1) / 2
    parts = []
    core = box(f"{prefix}Core", (w - 2.4, d - 1.6, h - 2.0), (cx, y, (h - 2.0) / 2), FIELD_D)
    gradient(core, shade(FIELD_D, 0.92), FIELD)
    parts.append(core)
    n = max(2, round(w / 2.9))
    for k in range(n):
        x = x0 + 1.4 + k * (w - 2.8) / (n - 1) + R.uniform(-0.3, 0.3)
        r = R.uniform(1.75, 2.1)
        p = blob(f"{prefix}Puff{k}", r, (x, y + R.uniform(-0.25, 0.25), r * 0.9 + R.uniform(0.0, 0.3)), FIELD,
                 seed=R.randint(0, 999), subdiv=2, squash=(1.0, 0.85, 0.95), jitter=0.05)
        gradient(lowpoly(p, ratio), FIELD_D, FIELD)
        parts.append(p)
    m = max(1, round(w / 3.6))
    for k in range(m):
        x = x0 + 2.0 + k * (w - 4.0) / max(1, m - 1) if m > 1 else cx
        r = R.uniform(1.4, 1.7)
        p = blob(f"{prefix}Crown{k}", r, (x + R.uniform(-0.3, 0.3), y + R.uniform(-0.2, 0.3), h - r * 0.85 + R.uniform(-0.2, 0.15)),
                 FIELD_L, seed=R.randint(0, 999), subdiv=2, squash=(1.15, 0.95, 0.75), jitter=0.05)
        gradient(lowpoly(p, ratio), FIELD, FIELD_L)
        parts.append(p)
    cols = (PINK, BUTTER, LILAC)
    for k in range(blooms):
        x = x0 + (k + 0.5 + R.uniform(-0.2, 0.2)) * w / blooms
        parts += flower(f"{prefix}Bloom{k}", (x, y - d * 0.42 - 0.35, R.uniform(2.4, h - 0.8)), R, cols[(k + R.randint(0, 2)) % 3], r=0.4)
    return parts


def fence_run(prefix, x0, x1, y, R, bay=6.0, rails=(1.6, 3.1), broken=None, goo_at=None):
    """Log rail fence from x0 to x1: posts every ~bay studs, two sagging rails per bay.
    broken = bay index whose top rail has dropped to lean on the ground (a mended-fence read)."""
    n = max(1, round((x1 - x0) / bay))
    posts = [x0 + k * (x1 - x0) / n for k in range(n + 1)]
    parts = []
    for k, x in enumerate(posts):
        hgt = 4.3 + R.uniform(-0.25, 0.25)
        p = cylinder(f"{prefix}Post{k}", 0.58, hgt, (x, y, -0.05), WOOD, segs=6, r_top=0.5, jitter=0.04, seed=R.randint(0, 99))
        gradient(p, WOOD_D, WOOD)
        parts.append(p)
        parts.append(cylinder(f"{prefix}Cap{k}", 0.54, 0.22, (x, y, hgt - 0.08), mix(WOOD, CREAM, 0.35), segs=6, r_top=0.36))
    for b in range(n):
        xa, xb = posts[b], posts[b + 1]
        for k, z in enumerate(rails):
            if broken == b and k == 1:
                # dropped rail: one end on the ground in front, the other still on the lower rail
                ln = xb - xa + 0.3
                rail = cylinder(f"{prefix}Fallen{b}", 0.34, ln, (xa + 0.2, y - 0.9, 0.3), WOOD, segs=6,
                                rot=(0, 90 - math.degrees(math.atan2(rails[0] - 0.1, ln)), -8), seed=R.randint(0, 99))
            else:
                tilt = R.uniform(-1.8, 1.8)
                rail = cylinder(f"{prefix}Rail{b}{k}", 0.34, xb - xa + 0.5, (xa - 0.25, y - 0.12 * (-1) ** k, z), WOOD, segs=6,
                                rot=(0, 90 + tilt, 0), jitter=0.05, seed=R.randint(0, 99))
            gradient(rail, WOOD_LO, mix(WOOD, CREAM, 0.15), z0=0, z1=z + 0.35)
            parts.append(rail)
    if goo_at is not None:
        gx = goo_at
        g = blob(f"{prefix}Goo", 0.46, (gx, y - 0.1, rails[1] + 0.3), GOO, subdiv=2, squash=(1.7, 1.2, 0.5), jitter=0.03)
        gradient(g, GOO, GOO_HI)
        parts.append(g)
        parts.append(blob(f"{prefix}GooDrop", 0.24, (gx + 0.2, y - 0.4, rails[1] - 0.12), GOO_HI, subdiv=1, squash=(0.8, 0.8, 1.25), jitter=0.0))
    return parts


def lift(o, dz):
    for v in o.data.vertices:
        v.co.z += dz
    return o


def pines(prefix, spots, R, tips=6, tiers=4, hz=None):
    """spots: (x, y, height). Low-poly firs (_border.fir with fewer tips/tiers); hz(x, y) stands
    them on a mound (r01: firs at z=0 sank into it and read stumpy)."""
    parts = []
    for k, (x, y, hgt) in enumerate(spots):
        dz = max(0.0, hz(x, y) - 0.4) if hz else 0.0
        parts += [lift(o, dz) for o in fir(f"{prefix}{k}", x, y, hgt, R, tips=tips, tiers=tiers if hgt > 9 else 3)]
    return parts


def mound(name, cx, cy, sx, sy, H, R, humps=((-0.2, 0.1, 0.7, 0.75, 1.0), (0.45, 0.0, 0.45, 0.6, 0.6)), NS=22, NR=6):
    """Polar-grid grassy mound (LESSONS world border set: polar, rim ring at z=0, paint per vertex).
    humps: (cu, cv, su, sv, weight) gaussian bumps in -1..1 ellipse space."""
    ph = R.uniform(0, 6)

    def height(u, v):
        edge = max(0.0, 1 - (u * u + v * v)) ** 0.7
        h = sum(H * wgt * math.exp(-(((u - cu) / su) ** 2 + ((v - cv) / sv) ** 2) * 1.4) for cu, cv, su, sv, wgt in humps)
        h += 0.25 * math.sin(u * 5.3 + ph) * math.cos(v * 4.1)
        return max(0.0, h * edge)

    bm = bmesh.new()
    centre = bm.verts.new((cx, cy, height(0, 0)))
    rings = []
    for i in range(1, NR + 1):
        rho = (i / NR) ** 0.8
        ring = []
        for k in range(NS):
            a = k * math.tau / NS + (0.5 * math.tau / NS if i % 2 else 0)
            u, w = math.cos(a) * rho, math.sin(a) * rho
            ring.append(bm.verts.new((cx + u * sx / 2, cy + w * sy / 2, height(u, w) if i < NR else 0.0)))
        rings.append(ring)
    for k in range(NS):
        bm.faces.new((centre, rings[0][k], rings[0][(k + 1) % NS]))
    for a, b in zip(rings, rings[1:]):
        for k in range(NS):
            bm.faces.new((a[k], b[k], b[(k + 1) % NS], a[(k + 1) % NS]))
    bmesh.ops.triangulate(bm, faces=bm.faces)
    top = list(bm.faces)
    res = bmesh.ops.extrude_face_region(bm, geom=top)
    for e in res["geom"]:
        if isinstance(e, bmesh.types.BMVert):
            e.co.z = -0.12
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    layer = bm.loops.layers.color.new("Col")
    top_set = set(top)
    for f in bm.faces:
        for lp in f.loops:
            t = min(1.0, lp.vert.co.z / (H * 0.8))
            lp[layer] = mix(FIELD_D, FIELD_L, t ** 0.85) if f in top_set else FIELD_D
    o = obj_from_bm(name, bm)

    def hz(x, y):
        return height((x - cx) / (sx / 2), (y - cy) / (sy / 2))

    return o, hz


def rocks(prefix, x, y, R, s=1.0, n=3):
    """Sandstone boulder clump at (x, y): one big, one mid, one low stone + a pebble, moss caps."""
    spec = [((6.0, 5.2, 6.2), (-1.4, 0.6), 0.6), ((4.2, 3.8, 4.0), (2.8, 1.0), 0.66), ((3.4, 3.0, 2.2), (0.8, -2.0), None),
            ((3.2, 2.8, 3.2), (-4.4, 1.8), 0.7)][:n]
    parts = []
    for k, (size, (dx, dy), moss) in enumerate(spec):
        parts.append(stone(f"{prefix}Stone{k}", tuple(c * s for c in size), (x + dx * s, y + dy * s, 0), seed=R.randint(0, 999),
                           base=shade(SAND, R.uniform(0.93, 1.04)), moss=MOSS if moss else None, moss_from=moss or 0.7,
                           lean=R.uniform(-0.4, 0.4), cuts=2, n=16))
    parts.append(pebble(f"{prefix}Peb", 0.7 * s, (x + 4.6 * s, y - 1.6 * s, 0), seed=R.randint(0, 999), base=shade(SAND, 0.9)))
    return parts


def goo_puddle(prefix, x, y, R, r=1.6):
    g = blob(f"{prefix}Goo", r, (x, y, 0.08), GOO, subdiv=2, squash=(1.6, 0.9, 0.13), jitter=0.03)
    gradient(g, GOO, mix(GOO, GOO_HI, 0.4))
    return [g, blob(f"{prefix}GooHi", r * 0.3, (x + r * 0.4, y - r * 0.1, 0.24), GOO_HI, subdiv=1, squash=(1.4, 1, 0.35), jitter=0.0)]


def bush(prefix, x, y, R, r=1.6):
    b = blob(f"{prefix}Bush", r, (x, y, r * 0.7), FIELD, seed=R.randint(0, 999), subdiv=2, squash=(1.2, 1.0, 0.75), jitter=0.06)
    gradient(lowpoly(b, 0.6), FIELD_D, FIELD_L)
    return [b]


def tufts(prefix, spots, R, hz=None):
    parts = []
    for k, (x, y) in enumerate(spots):
        parts += tuft(f"{prefix}{k}", (x, y, hz(x, y) if hz else 0), R, h=1.1, blades=3)
    return parts


def ship(name, parts):
    """finish(), mirrored in X first when CHUNK_MIRROR=1 (normals recomputed by finish's cleanup)."""
    if MIRROR:
        for o in parts:
            bm = bmesh.new()
            bm.from_mesh(o.data)
            for v in bm.verts:
                v.co.x = -v.co.x
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(o.data)
            bm.free()
            o.location.x = -o.location.x
        name += "_m"
    return finish(name, parts)
