# Skyisle (Secret): the slime IS a tiny floating island. Grassy top with a mini tree and a cottage,
# a pond whose waterfall pours off the left edge into a little cloud, a cliff front with the face,
# an upside-down purple crag below with glowing crystals and dangling roots, small islets orbiting.
# It floats: the lowest crystal tip is the origin.
from models._slimepool import *

GRASS, GRASS_L, GRASS_D = hexc("4fd23e"), hexc("a8f25e"), hexc("2f9e38")
CLIFF, CLIFF_D = hexc("ffbe6e"), hexc("f08a48")
ROCK, ROCK_L, ROCK_D = hexc("8d72c4"), hexc("b39be0"), hexc("5b4590")
WATER, WATER_L, FOAM = hexc("39a8ff"), hexc("8fe0ff"), hexc("f2fdff")
CRYS, CRYS_L, CRYS2, CRYS2_L = hexc("23d8ff"), hexc("d8fbff"), hexc("ff4fd2"), hexc("ffd6f6")
ROOT, ROOT_D = hexc("a8683c"), hexc("6e3e22")
WALL, WOOD, WOOD_D = hexc("fff1d6"), hexc("b8743c"), hexc("7a4826")
ROOF, ROOF_D, WIN = hexc("ff4f5e"), hexc("c42a44"), hexc("ffe46a")
LEAF, LEAF_L, APPLE = hexc("3ccf4a"), hexc("9cf060"), hexc("ff3d4a")


def sweep(name, pts, widths, thick, side, color, n=10):
    """closed sweep of a flattened oval section (w x thick) along pts; side(i) -> horizontal width
    direction at point i. Used for the waterfall sheet and the stream."""
    P = [Vector(p) for p in pts]
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(P):
        t = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        s = Vector(side(i)).normalized()
        s = (s - t * s.dot(t)).normalized()
        nrm = t.cross(s).normalized()
        ring = []
        for k in range(n):
            a = k * math.tau / n
            ring.append(bm.verts.new(p + s * math.cos(a) * widths[i] / 2 + nrm * math.sin(a) * thick / 2))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True)


def prism(name, poly, depth, origin, xaxis, yaxis, color):
    return slab(name, poly, depth, origin, xaxis, yaxis, color)


# ---------------------------------------------------------------- the island body
Z0 = 0.95  # bottom of the crag (crystals hang below it)
prof = [(Z0, 0.07), (Z0 + 0.35, 0.33), (Z0 + 0.8, 0.7), (Z0 + 1.3, 1.08), (Z0 + 1.8, 1.42), (Z0 + 2.25, 1.6),
        (Z0 + 2.55, 1.62), (Z0 + 2.78, 1.5), (Z0 + 2.9, 1.05), (Z0 + 2.95, 0)]
TOPZ = Z0 + 2.95
GRASS_Z = Z0 + 2.5  # grass edge height (wavy)
ROCK_Z = Z0 + 1.46  # cliff -> rock


def grass_edge(a):
    e = GRASS_Z + 0.06 * math.sin(7 * a) + 0.03 * math.sin(13 * a + 1)
    for c, w, d in ((-2.3, 0.22, 0.32), (2.2, 0.2, 0.38), (2.9, 0.18, 0.26), (1.15, 0.16, 0.2), (-1.35, 0.17, 0.24)):
        dd = abs((a - c + math.pi) % math.tau - math.pi)
        e -= d * max(0.0, 1 - (dd / w) ** 2)
    return e


def rock_edge(a):
    return ROCK_Z + 0.09 * math.sin(3 * a + 0.5) + 0.04 * math.sin(7 * a)


def paint(a, z, p):
    if z > grass_edge(a):
        return mix(GRASS, GRASS_L, smoothstep(GRASS_Z + 0.2, TOPZ, z))
    if z > rock_edge(a):
        # warm cliff with two soft strata lines
        t = smoothstep(rock_edge(a), GRASS_Z, z)
        c = mix(CLIFF_D, CLIFF, t)
        sl = math.sin((z - Z0) * 7.5 + 0.5 * math.sin(4 * a))
        return mix(c, CLIFF_D, 0.55 * smoothstep(0.86, 0.97, sl) * (1 - smoothstep(0.55, 0.25, abs(a)) * smoothstep(Z0 + 1.6, Z0 + 1.8, z)))
    t = smoothstep(Z0, ROCK_Z, z)
    c = mix(ROCK_D, ROCK, t)
    s = math.sin(z * 9.0 + 0.6 * math.sin(3 * a))
    return mix(c, ROCK_L, 0.35 * smoothstep(0.75, 0.95, s))


def sectors(a, z):
    # crisp per-face regions (cliff / rock); the grass is a separate cap shell with a smooth edge
    return paint(a, z, None)


b = Body(prof, paint=paint, sectors=sectors, segs=36, sub=2, gloss=0.5, shade=0.7,
         bump=lambda a, z: (0.05 * noise.noise(Vector((math.cos(a) * 2.2, math.sin(a) * 2.2, z * 1.6)))) * smoothstep(ROCK_Z + 0.3, Z0, z))
parts = [b.obj]


def grass_cap(cols=60, rows=6):
    """grass carpet: closed shell hugging the top, its lower edge exactly on the wavy grass line
    (smooth scalloped edge with drips; per-face body colours would stair-step)."""
    bm = bmesh.new()
    ztop = TOPZ - 0.04
    layers = []
    for extra in (0.035, -0.03):
        grid = []
        for i in range(cols):
            a = i * math.tau / cols
            e = grass_edge(a)
            col = []
            for r in range(rows):
                t = (r / (rows - 1)) ** 1.25
                z = e + (ztop - e) * t
                col.append(bm.verts.new(b.point(a, z, extra + 0.02 * (1 - t) * (extra > 0))))
            grid.append(col)
        cen = bm.verts.new((0, 0, TOPZ + (0.035 if extra > 0 else -0.04)))
        layers.append((grid, cen))
    (go, co), (gi, ci) = layers
    for grid, cen, flip in ((go, co, False), (gi, ci, True)):
        for i in range(cols):
            j = (i + 1) % cols
            for r in range(rows - 1):
                f = (grid[i][r], grid[j][r], grid[j][r + 1], grid[i][r + 1])
                bm.faces.new(tuple(reversed(f)) if flip else f)
            f = (grid[i][-1], grid[j][-1], cen)
            bm.faces.new(tuple(reversed(f)) if flip else f)
    for i in range(cols):  # rim strip joining outer and inner edge
        j = (i + 1) % cols
        bm.faces.new((gi[i][0], gi[j][0], go[j][0], go[i][0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm("Grass", bm)

    def col(p, n):
        a = math.atan2(p.x, -p.y)
        d = p.z - grass_edge(a)
        c = mix(GRASS, GRASS_L, smoothstep(GRASS_Z + 0.15, TOPZ, p.z))
        return mix(GRASS_D, c, smoothstep(0.0, 0.09, d))
    paint_fn(o, col)
    return keep(o, True)


parts.append(grass_cap())
register(parts[-1], "Grass")

# ---------------------------------------------------------------- face on the cliff front
f = Face(b, eye_u=0.5, eye_v=Z0 + 2.06, mouth_v=Z0 + 1.72, s=1.0)
f.eyes("sparkle", w=0.48, h=0.62, iris=hexc("2fc4ff")).mouth("open", w=1.0).cheeks(color=hexc("ff5f86"), w=0.34, h=0.17)
parts += f.parts

# ---------------------------------------------------------------- pond, stream and waterfall (left side, yaw -72)
WY = math.radians(-72)
dirv = Vector((math.sin(WY), -math.cos(WY), 0))
sidev = Vector((math.cos(WY), math.sin(WY), 0))
pond_c = (-0.5, -0.12)
parts.append(decal("Pond", oval(pond_c[0], pond_c[1], 0.78, 0.6, n=18), WATER, TOP, off=0.012, th=0.03, on=["Grass"]))
parts.append(decal("PondHi", oval(pond_c[0] - 0.12, pond_c[1] + 0.08, 0.26, 0.14, n=10), WATER_L, TOP, off=0.05, th=0.01, on=["Grass"]))

fall = []
ws = []
for rr, zz, w in ((0.55, None, 0.32), (0.95, None, 0.34), (1.3, None, 0.38), (1.5, None, 0.42)):
    p = b.point(WY, 0, 0)
    z = TOPZ
    # height of the surface at this radius: find z on the profile above GRASS_Z with radius rr
    best = None
    for k in range(60):
        zt = GRASS_Z + (TOPZ - GRASS_Z) * k / 59
        if b.radius(zt) >= rr:
            best = zt
    z = (best or GRASS_Z) + 0.08
    fall.append(dirv * rr + Vector((0, 0, z)))
    ws.append(w)
lip = fall[-1]
for k, (dr, dz, w) in enumerate(((0.16, -0.08, 0.44), (0.28, -0.3, 0.46), (0.36, -0.7, 0.48), (0.42, -1.15, 0.5),
                                 (0.46, -1.6, 0.52), (0.48, -2.0, 0.54), (0.49, -2.3, 0.56))):
    fall.append(lip + dirv * dr + Vector((0, 0, dz)))
    ws.append(w)


def water_col(p, n):
    # streaks across the sheet + foam at the lip and bottom
    u = (p - lip).dot(sidev)
    s = 0.5 + 0.5 * math.sin(u * 34 + p.z * 2)
    c = mix(WATER, WATER_L, 0.6 * s)
    c = mix(c, FOAM, smoothstep(lip.z - 0.15, lip.z + 0.05, p.z) * 0.7)
    return mix(c, FOAM, smoothstep(lip.z - 1.9, lip.z - 2.3, p.z) * 0.8)


parts.append(sweep("Waterfall", fall, ws, 0.07, lambda i: sidev, water_col))
# cloud the waterfall drops into
cbase = lip + dirv * 0.5 + Vector((0, 0, -2.38))
cloud_balls = [(cbase + Vector(o), r) for o, r in (((0, 0, 0), 0.34), (sidev * 0.36 + Vector((0, 0, -0.05)), 0.27),
                                                       (-sidev * 0.36 + Vector((0, 0, -0.04)), 0.28), (dirv * 0.22 + Vector((0, 0, 0.02)), 0.27),
                                                       (-dirv * 0.18 + sidev * 0.15, 0.25), (sidev * 0.62 + Vector((0, 0, -0.1)), 0.18),
                                                       (-sidev * 0.6 + Vector((0, 0, -0.1)), 0.19))]
parts.append(goo("Cloud", [(tuple(c), r, (1, 1, 0.7)) for c, r in cloud_balls], zgrad(hexc("cfe6ff"), WHITE, cbase.z - 0.25, cbase.z + 0.25), tris=300, resolution=0.08))

# ---------------------------------------------------------------- cottage (back-left, faces front-left)
HY = math.radians(-28)
HX = Vector((math.cos(HY), math.sin(HY), 0))
HF = Vector((math.sin(HY), -math.cos(HY), 0))  # house front direction
hc = Vector((-0.42, 0.62, 0))


def surf_z(x, y):
    hit = cast(Vector((x, y, 10)), Vector((0, 0, -1)), ["Grass"])
    return hit[0].z


hz = surf_z(hc.x, hc.y) - 0.08
W, D, Hh = 0.9, 0.7, 0.58
parts.append(box("House", (W, D, Hh), tuple(hc + Vector((0, 0, hz + Hh / 2))), WALL, rot=(0, 0, math.degrees(HY))))
# gables + roof
for sd in (-1, 1):
    O = hc + HX * (sd * W / 2) + Vector((0, 0, hz + Hh))
    parts.append(slab(f"Gable{sd}", [(-D / 2, 0), (D / 2, 0), (0, 0.36)], 0.04, O, -HF, (0, 0, 1), WALL))
ang = math.atan2(0.36, D / 2)
for sd in (-1, 1):
    # roof panel: along HX, sloping from the ridge down towards front (sd -1) / back (sd 1)
    ridge = hc + Vector((0, 0, hz + Hh + 0.42))
    down = (-HF * sd * math.cos(ang) + Vector((0, 0, -1)) * math.sin(ang)).normalized()
    mid = ridge + down * 0.27
    nrm = HX.cross(down) * (-sd)
    poly = [(-W / 2 - 0.1, -0.29), (W / 2 + 0.1, -0.29), (W / 2 + 0.1, 0.29), (-W / 2 - 0.1, 0.29)]
    parts.append(slab(f"Roof{sd}", poly, 0.09, mid + nrm * 0.02, HX, down, along(ROOF, ROOF_D, ridge, ridge + down * 0.55)))
# chimney, door, windows
cp = hc + HX * 0.22 + HF * -0.12 + Vector((0, 0, hz + Hh + 0.2))
parts.append(box("Chimney", (0.14, 0.14, 0.42), tuple(cp + Vector((0, 0, 0.16))), hexc("d65a4a"), rot=(0, 0, math.degrees(HY))))
fr = hc + HF * (D / 2 + 0.012)
parts.append(box("Door", (0.18, 0.03, 0.3), tuple(fr + HX * 0.12 + Vector((0, 0, hz + 0.23))), WOOD_D, rot=(0, 0, math.degrees(HY))))
parts.append(box("Win0", (0.17, 0.03, 0.15), tuple(fr + HX * -0.19 + Vector((0, 0, hz + 0.32))), WIN, rot=(0, 0, math.degrees(HY))))
parts.append(box("WinF0", (0.21, 0.02, 0.19), tuple(fr + HF * -0.006 + HX * -0.19 + Vector((0, 0, hz + 0.32))), WOOD, rot=(0, 0, math.degrees(HY))))
sp = hc + HX * (-W / 2 - 0.012)
parts.append(box("Win1", (0.03, 0.17, 0.15), tuple(sp + Vector((0, 0, hz + 0.32))), WIN, rot=(0, 0, math.degrees(HY))))

# ---------------------------------------------------------------- tree (back-right)
tb = Vector((0.62, 0.55, surf_z(0.62, 0.55) - 0.05))
parts.append(horn("Trunk", [tuple(tb), tuple(tb + Vector((0.03, 0.02, 0.5))), tuple(tb + Vector((-0.02, 0.0, 0.95)))],
                  [0.13, 0.09, 0.07], WOOD_D, WOOD, segs=7))
cc = tb + Vector((0, 0, 1.25))
canopy = [((0, 0, 0.05), 0.4), ((0.36, 0.05, -0.1), 0.3), ((-0.36, -0.02, -0.08), 0.31), ((0.02, -0.36, -0.08), 0.3),
          ((0.05, 0.34, -0.06), 0.3), ((0.18, -0.12, 0.34), 0.27), ((-0.2, 0.1, 0.32), 0.27), ((-0.26, -0.26, 0.12), 0.24),
          ((0.28, 0.26, 0.14), 0.24)]
parts.append(goo("Canopy", [(tuple(cc + Vector(o)), r) for o, r in canopy], zgrad(LEAF, LEAF_L, cc.z - 0.35, cc.z + 0.6), tris=420, resolution=0.07))
for k, o in enumerate(((-0.38, -0.36, 0.02), (0.3, -0.42, 0.06), (-0.12, -0.5, 0.3), (0.08, -0.52, -0.16), (-0.55, -0.1, -0.12), (0.5, -0.2, -0.2))):
    parts.append(ball(f"Apple{k}", 0.085, tuple(cc + Vector(o) * 0.95), APPLE, subdiv=1))

# a few flowers/bushes on the grass
for k, (x, y, c) in enumerate(((0.15, -0.95, hexc("ff7ad9")), (0.75, -0.7, WHITE), (-0.95, 0.35, hexc("ffe14a")), (0.95, 0.05, hexc("ff7ad9")))):
    z = surf_z(x, y)
    parts.append(ball(f"Bush{k}", 0.14, (x, y, z + 0.04), GRASS_D, squash=(1, 1, 0.75), subdiv=1))
    parts.append(ball(f"Flower{k}", 0.06, (x + 0.05, y - 0.06, z + 0.15), c, subdiv=1))

# ---------------------------------------------------------------- crag underside: rock chunks, crystals, roots
for k, (yaw, z, r) in enumerate(((30, Z0 + 1.0, 0.34), (-110, Z0 + 0.75, 0.3), (150, Z0 + 1.05, 0.36), (95, Z0 + 0.55, 0.26),
                                 (-30, Z0 + 0.45, 0.22), (220, Z0 + 0.4, 0.24), (-160, Z0 + 1.15, 0.3), (75, Z0 + 1.2, 0.26))):
    p = b.point(math.radians(yaw), z, -0.06)
    parts.append(blob(f"Crag{k}", r, tuple(p), None, seed=k + 3, subdiv=1, jitter=0.18, squash=(1, 1, 0.8)))
    paint_fn(parts[-1], zgrad(ROCK_D, ROCK, p.z - r, p.z + r))
    keep(parts[-1], False)

cry = [((0, 0, Z0 + 0.15), (0, 0, -1), 1.15, 0.2, CRYS, CRYS_L),
       ((0.3, -0.18, Z0 + 0.45), (0.45, -0.3, -1), 0.8, 0.15, CRYS2, CRYS2_L),
       ((-0.33, -0.12, Z0 + 0.48), (-0.5, -0.2, -1), 0.85, 0.15, CRYS, CRYS_L),
       ((-0.1, 0.36, Z0 + 0.45), (-0.1, 0.5, -1), 0.7, 0.14, CRYS2, CRYS2_L),
       ((0.72, 0.3, Z0 + 1.0), (0.8, 0.4, -0.7), 0.6, 0.13, CRYS, CRYS_L),
       ((-0.78, -0.45, Z0 + 1.15), (-0.8, -0.5, -0.6), 0.55, 0.12, CRYS2, CRYS2_L),
       ((0.2, 0.75, Z0 + 0.95), (0.2, 0.8, -0.8), 0.5, 0.11, CRYS, CRYS_L)]
for k, (base, d, L, r, c0, c1) in enumerate(cry):
    parts.append(crystal(f"Crystal{k}", base, d, L, r, c0, c1))

roots = [[(0.25, 0.12, Z0 + 0.7), (0.42, 0.18, Z0 + 0.25), (0.5, 0.08, Z0 - 0.2), (0.42, -0.04, Z0 - 0.5)],
         [(-0.2, 0.3, Z0 + 0.7), (-0.38, 0.45, Z0 + 0.25), (-0.5, 0.5, Z0 - 0.1), (-0.58, 0.42, Z0 - 0.32)],
         [(0.55, -0.55, Z0 + 1.2), (0.75, -0.72, Z0 + 0.8), (0.82, -0.76, Z0 + 0.4)],
         [(-0.72, 0.7, Z0 + 1.25), (-0.95, 0.88, Z0 + 0.85), (-1.0, 0.95, Z0 + 0.5)]]
for k, pts in enumerate(roots):
    parts.append(horn(f"Root{k}", pts, [0.07, 0.055, 0.04, 0.025][:len(pts)], ROOT_D, ROOT, segs=6))

# ---------------------------------------------------------------- orbiting islets
for k, (yaw, rr, z, s) in enumerate(((-140, 2.3, 3.2, 0.3), (60, 2.25, 2.0, 0.34), (165, 2.1, 3.9, 0.24))):
    a = math.radians(yaw)
    c = Vector((math.sin(a) * rr, -math.cos(a) * rr, z))
    rk = lathe(f"Islet{k}", [(-s * 1.6, 0), (-s * 0.9, s * 0.55), (-s * 0.3, s * 0.92), (0, s), (0.02, 0)],
               lambda p, n, c=c, s=s: mix(ROCK_D, ROCK_L, smoothstep(c.z - s * 1.6, c.z, p.z)),
               pos=tuple(c), segs=7, smooth=False, spin=k)
    parts.append(rk)
    parts.append(ball(f"IsletG{k}", s * 1.02, tuple(c + Vector((0, 0, 0.0))), zgrad(GRASS, GRASS_L, c.z, c.z + s * 0.4), squash=(1, 1, 0.42), subdiv=2))
    if k == 1:  # a tiny pine on the biggest islet
        parts.append(lathe("IsletTree", [(0, s * 0.55), (s * 0.7, s * 0.35), (s * 0.75, s * 0.42), (s * 1.4, s * 0.2), (s * 1.45, s * 0.28), (s * 2.1, 0)],
                           zgrad(GRASS_D, LEAF, c.z, c.z + s * 2.2), pos=tuple(c + Vector((0, 0, s * 0.3))), segs=7, smooth=False))

ship("slime_isle", parts)
