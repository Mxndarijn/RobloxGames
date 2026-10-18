# Rocky Road (hybrid: pebble + cheddar + mochi). Ice-cream scoop slime: a lumpy chocolate scoop
# (pebble's lumps) sitting in a waffle-cone collar, melting chocolate drips running over the waffle,
# chunky marshmallow cubes (cheddar's cube, mochi's pink and white) and nut bits pressed into the top,
# a cheeky wink with the tongue out.
from models._slimepool import *

CHOC_D, CHOC, CHOC_L = hexc("5e2614"), hexc("9a4a2a"), hexc("d08a5a")
WAF, WAF_D, WAF_L = hexc("f4b85a"), hexc("a8601e"), hexc("ffe09a")
MALLOW, MALLOW_P = hexc("fffaf4"), hexc("ffb8d0")
NUT, NUT_D = hexc("e8c088"), hexc("b08050")



def nz(a, z, s=1.0):
    return noise.noise(Vector((math.sin(a) * 1.7 * s, math.cos(a) * 1.7 * s, z * 1.3 * s)))


def adiff(a, b):
    return math.atan2(math.sin(a - b), math.cos(a - b))


CT = 1.3  # cone top


def bump(a, z):
    s = smoothstep(CT + 0.05, CT + 0.4, z)
    lip = 0.07 * math.exp(-((z - CT - 0.12) / 0.1) ** 2) * (1 + 0.8 * math.sin(a * 8 + 0.4))  # scooped, ruffled lip
    return s * (0.07 * nz(a, z, 1.0) + 0.03 * nz(a, z, 3.0)) + lip


def paint(a, z, p):
    c = mix(CHOC_D, CHOC, smoothstep(CT - 0.1, 2.0, z))
    return mix(c, CHOC_L, 0.55 * max(0.0, nz(a, z, 2.6)) * smoothstep(1.6, 2.6, z))


b = Body([(CT - 0.3, 1.1), (CT, 1.32), (CT + 0.12, 1.44), (1.8, 1.52), (2.3, 1.48), (2.8, 1.18), (3.15, 0.66), (3.32, 0.12), (3.34, 0)],
         paint=paint, bump=bump, segs=36, sub=2, gloss=0.5)
parts = [b.obj]


# waffle cone: diamond lattice, every cell inset so the grid ridges stand out
def waffle_cone(N=14, R=6, r0=0.64, r1=1.34, h=CT + 0.02):
    bm = bmesh.new()
    rings = []
    for i in range(R + 1):
        z = h * i / R
        r = r0 + (r1 - r0) * i / R
        rings.append([bm.verts.new((math.sin((k + 0.5 * (i % 2)) * math.tau / N) * r,
                                     -math.cos((k + 0.5 * (i % 2)) * math.tau / N) * r, z)) for k in range(N)])
    cells = []
    for i in range(R - 1):
        A, B, C = rings[i], rings[i + 1], rings[i + 2]
        for k in range(N):
            if i % 2 == 0:  # B[k] sits at k + 0.5
                f = bm.faces.new((A[k], B[k], C[k], B[(k - 1) % N]))
            else:  # B at integer k, A/C at k + 0.5
                f = bm.faces.new((A[k], B[(k + 1) % N], C[k], B[k]))
            cells.append(f)
    edge = []
    for (lo, hi) in ((rings[0], rings[1]), (rings[R], rings[R - 1])):
        par_lo = (rings.index(lo)) % 2
        for k in range(N):
            if par_lo == 0:
                edge.append(bm.faces.new((lo[k], lo[(k + 1) % N], hi[k])))
            else:
                edge.append(bm.faces.new((lo[k], lo[(k + 1) % N], hi[(k + 1) % N])))
    bm.faces.new(rings[0])
    bm.faces.new(rings[R])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.inset_individual(bm, faces=cells, thickness=0.05, depth=-0.035)
    col = bm.loops.layers.color.new("Col")
    cellset = set(cells)
    for f in bm.faces:
        for lp in f.loops:
            z = lp.vert.co.z
            if f in cellset:
                c = mix(WAF, WAF_L, 0.5 * smoothstep(0.0, CT, z))
            else:
                c = mix(shade(WAF_D, 0.85), WAF_D, smoothstep(0.0, CT, z))
            lp[col] = c
    bmesh.ops.triangulate(bm, faces=bm.faces)
    return keep(obj_from_bm("Cone", bm), False)


parts.append(waffle_cone())

# melting chocolate drips running down over the waffle (one goo shell, fat round tips)
balls = []
for yaw, depth in ((-24, 0.45), (30, 0.7), (95, 0.55), (165, 0.75), (205, 0.45), (-95, 0.62)):
    a = math.radians(yaw)
    sq = (1.5, 0.55, 1.2) if abs(math.cos(a)) > 0.7 else (0.55, 1.5, 1.2)
    n = max(3, int(depth / 0.09))
    for k in range(n + 1):
        z = CT + 0.08 - depth * k / n
        r = 0.64 + 0.7 * max(z, 0) / (CT + 0.02) - 0.03
        rad = 0.14 * (1 - 0.25 * k / n) if k < n else 0.15
        balls.append(((math.sin(a) * r, -math.cos(a) * r, z), rad, sq))
parts.append(goo("Drips", balls, lambda p, n: mix(shade(CHOC, 0.85), mix(CHOC, CHOC_L, 0.3), smoothstep(0.4, CT + 0.1, p.z)), tris=300, resolution=0.06))

# toppings: marshmallow cubes (faceted, white and pink) + nut bits pressed into the scoop
def cube(name, s, pos, rot, col):
    o = box(name, (s, s, s * 0.9), pos, None, rot)
    paint_fn(o, lambda p, n: mix(shade(col, 0.86), col, smoothstep(-0.3, 0.8, n.z)))
    return keep(o, False)


# (x, y, size, rot, colour, sink): on top and pressed into the sides
TOP = [(-0.5, -0.3, 0.46, (0.3, 0.2, 0.5), MALLOW, 0.1), (0.55, 0.3, 0.5, (-0.25, 0.35, 0.2), MALLOW_P, 0.1),
       (-0.2, 0.7, 0.4, (0.4, -0.2, 0.9), MALLOW, 0.1), (1.12, -0.6, 0.4, (0.2, 0.5, -0.3), MALLOW, 0.2),
       (-1.25, 0.5, 0.38, (-0.3, 0.1, 0.6), MALLOW_P, 0.2), (0.1, 1.35, 0.4, (0.6, 0.3, 0.1), MALLOW_P, 0.2),
       (1.3, 0.55, 0.36, (0.1, 0.7, 0.4), MALLOW, 0.2)]
for k, (x, y, s, rot, col, sink) in enumerate(TOP):
    r = math.hypot(x, y)
    a = math.atan2(x, -y)
    zs = None
    # sit on the surface: find height where radius matches
    for zz in [b.H - i * 0.02 for i in range(120)]:
        if b.radius(zz) * (1 + bump(a, zz)) >= r:
            zs = zz
            break
    parts.append(cube(f"Mallow{k}", s, (x, y, zs + s * 0.3 - sink * s * 2), rot, col))

NUTS = [(0.0, 0.0), (-0.75, 0.1), (0.75, -0.1), (0.3, 0.85), (-0.5, -0.85), (1.15, 0.3), (-1.2, -0.2), (0.55, -0.95)]
for k, (x, y) in enumerate(NUTS):
    r = math.hypot(x, y)
    a = math.atan2(x, -y)
    for zz in [b.H - i * 0.02 for i in range(90)]:
        if b.radius(zz) * (1 + bump(a, zz)) >= r:
            break
    c = (x, y, zz + 0.04)
    parts.append(ball(f"Nut{k}", 0.15, c, along(NUT_D, NUT, (0, 0, zz - 0.1), (0, 0, zz + 0.15)),
                      squash=(1.3, 0.85, 0.7), rot=(0.3 * k, 0.5, k * 1.1), subdiv=1, smooth=False))

f = Face(b, eye_u=0.56, eye_v=2.12, mouth_v=1.72, s=1.2)
f.eyes("wink", w=0.5, h=0.64).mouth("tongue", w=1.3).cheeks(color=hexc("ff8a9a"))
f.d("Brow", arc(-0.56, 2.56, 0.22, 50, 130, 0.08, n=6), INK)
parts += f.parts
ship("slime_rocky_road", parts)
