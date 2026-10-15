# slime_fountain: Steal a Slime hub centrepiece (Slime Ranch theme, THEME.md + FOUNTAIN_SIZES.md).
# "Ranch silo meets goo fountain": a chunky wooden silo (staves, brass hoops, red dome roof) whose
# top is a goo basin that overflows; goo streams run over the roof and down the staves as
# displacements of the silo surface itself (one surface of revolution, never stuck-on tubes).
# A goo spiral slide leaves the basin lip and winds ~1.5 turns down to the landing ring.
#
# Kit space: studs, Z up, front -Y, z=0 ground. The silo axis is at the world origin while
# modelling; finish() re-centres the mesh on its bbox, so the silo axis offset is printed
# (SILO_AXIS) for placing the MeshPart in the hub.
import math, random
import bmesh, bpy
from mathutils import Vector
from lib import *
from models._slime import radius as slime_radius, TIP as SLIME_TIP

P = PALETTE
WOOD, WOOD_D, CREAM = P["ranch_wood"], P["ranch_wood_dark"], P["ranch_cream"]
ROOF, ROOF_D, METAL = P["ranch_roof"], P["ranch_roof_dark"], P["ranch_metal"]
GOO, GOO_HI = P["ranch_goo"], P["ranch_goo_hi"]
SEGS = 44

R = random.Random(11)


def smooth_layer(bm):
    return bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")


# ------------------------------------------------------------------ silo profile (r, z, tag, free)
# tag = what the band from this ring up to the next one is. "free" rows may slide along the
# profile per column: they are snapped onto the goo edge (collar line, drip tips), so goo
# boundaries follow mesh edges instead of stair-stepping across faces.
WALL_TOP = 30.0


def wall_r(z):
    """staves bulge a little (barrel): chunky and rounded, 11.2 at the foot and top, 11.7 mid."""
    return 11.2 + 0.5 * math.sin(math.pi * min(1, max(0, (z - 2.4) / (WALL_TOP - 2.4))))


PROF = [(13.0, 0.0, "plinth", 0), (13.1, 1.5, "plinth_top", 0), (12.3, 2.3, "trim_lo", 0), (11.2, 2.4, "trim", 0)]
wall_z = [3.3, ("hoop", 6.5), 9.4, 10.0, 12.5, ("hoop", 15.5), 18.0, 20.5, 23.0, ("hoop", 25.4), 27.8]
for w in wall_z:
    if isinstance(w, tuple):
        h = w[1]
        PROF += [(wall_r(h - 0.4), h - 0.4, "hoop", 0), (wall_r(h) + 0.42, h, "hoop", 0),
                 (wall_r(h + 0.4), h + 0.4, "wall", 0)]
    else:
        PROF.append((wall_r(w), w, "wall", int(w > 16)))
Z0 = WALL_TOP + 1.3  # eave edge top
PROF += [(wall_r(WALL_TOP), WALL_TOP, "eave_under", 0), (13.0, WALL_TOP + 0.5, "eave_edge", 0), (13.4, Z0, "dome", 0)]
for deg in (15, 32, 50, 66, 80, 90):  # rounded red shoulder up to the basin
    phi = math.radians(deg)
    PROF.append((8.9 + 4.5 * math.cos(phi), Z0 + 4.6 * math.sin(phi), "dome" if deg < 90 else "rim", int(deg < 80)))
ZP = Z0 + 4.9  # goo level in the basin
PROF += [(8.5, ZP + 0.3, "rim", 0), (8.0, ZP + 0.7, "rim_in", 0), (7.4, ZP + 0.5, "pool", 0), (7.1, ZP, "pool", 0)]
# the goo wells up in a fat bubbling dome: the fountain crown
POOL = [(5.6, ZP + 0.2), (4.4, ZP + 1.4), (3.2, ZP + 2.9), (1.6, ZP + 3.8)]
PROF += [(r, z, "pool", 0) for r, z in POOL]
APEX = ZP + 4.05
RIM_I = next(i for i, p in enumerate(PROF) if p[2] == "rim_in")  # rim top ring: the goo starts here
JC = next(i for i, p in enumerate(PROF) if p[2] == "dome" and abs(p[1] - (Z0 + 4.6 * math.sin(math.radians(66)))) < 1e-6)

SB = [0.0]  # arclength from the bottom
for p0, p1 in zip(PROF, PROF[1:]):
    SB.append(SB[-1] + math.hypot(p1[0] - p0[0], p1[1] - p0[1]))


def prof_normal(i):
    a, b = PROF[max(i - 1, 0)], PROF[min(i + 1, len(PROF) - 1)]
    dr, dz = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dr, dz)
    return dz / n, -dr / n


def at(sb):
    """(r, z, nr, nz) on the profile at arclength sb (linear between rings)."""
    for i in range(len(PROF) - 1):
        if SB[i] <= sb <= SB[i + 1] + 1e-9:
            t = (sb - SB[i]) / max(SB[i + 1] - SB[i], 1e-9)
            n0, n1 = prof_normal(i), prof_normal(i + 1)
            return (PROF[i][0] + (PROF[i + 1][0] - PROF[i][0]) * t, PROF[i][1] + (PROF[i + 1][1] - PROF[i][1]) * t,
                    n0[0] + (n1[0] - n0[0]) * t, n0[1] + (n1[1] - n0[1]) * t)
    return PROF[-1][0], PROF[-1][1], 0.0, 1.0


def sb_of_z(z):
    for i in range(RIM_I):
        if PROF[i][1] <= z <= PROF[i + 1][1]:
            return SB[i] + (SB[i + 1] - SB[i]) * (z - PROF[i][1]) / (PROF[i + 1][1] - PROF[i][1])
    raise ValueError(z)


def ang_d(a, b):
    return math.atan2(math.sin(a - b), math.cos(a - b))


def collar(a):
    """arclength (from the rim top) the goo collar reaches at angle a: wavy, never round."""
    return 2.7 + 0.55 * math.sin(3 * a + 1.0) + 0.3 * math.sin(5 * a + 0.3)


# goo overflow: the wavy collar spilling over the rim (icing) + drips of mixed length:
# (angle deg, z where the drip tip ends). Short ones stop on the roof, long ones run down the staves.
# Kept off the slide head (180 deg).
DRIPS = [(-120, 32.4), (-82, 21.0), (-8, 25.8), (38, 31.0), (64, 17.6), (135, 23.2), (222, 19.2),
         (292, 27.2)]

TIP_RISE = 1.1  # the drip's side columns stop this much higher: round-ish tip


def plank_tint(k):
    return [1.0, 0.93, 1.05, 0.97, 0.9, 1.02][k % 6] * (0.97 + 0.06 * R.random())


TINTS = [plank_tint(k) for k in range(SEGS // 2)]
DOOR_A, DOOR_W, DOOR_TOP = -math.pi / 2, 0.29, 10.0  # 4 columns of red planks


def goo_layout():
    """per column: row arclengths (snapped) and G = lowest goo row index; drip centre columns."""
    nrow = len(PROF)
    sbs = [list(SB) for _ in range(SEGS)]
    G = [JC] * SEGS
    centre = {}
    sb_rim = SB[RIM_I]
    for k in range(SEGS):
        a = k * math.tau / SEGS
        sbs[k][JC] = min(SB[JC + 1] - 0.3, max(SB[JC - 1] + 0.3, sb_rim - collar(a)))
    for deg, zend in DRIPS:
        kc = round(math.radians(deg) / math.tau * SEGS) % SEGS
        se = sb_of_z(zend)
        free = [j for j in range(JC) if PROF[j][3]]
        j = min(free, key=lambda j: abs(SB[j] - se))
        lo, hi = SB[j - 1] + 0.3, SB[j + 1] - 0.3
        for dk, rise in ((0, 0.0), (-1, TIP_RISE), (1, TIP_RISE)):
            kk = (kc + dk) % SEGS
            sbs[kk][j] = min(hi, max(lo, se + rise))
            G[kk] = min(G[kk], j)
        centre[kc] = j
    return sbs, G, centre


def silo():
    sbs, G, centre = goo_layout()
    nrow = len(PROF)

    def face_goo(k, j):
        if PROF[j][2] in ("pool", "rim_in", "rim"):
            return True
        return j >= max(G[k], G[(k + 1) % SEGS]) and j < RIM_I

    bm = bmesh.new()
    rows = []  # rows[j][k]
    for j in range(nrow):
        tag = PROF[j][2]
        row = []
        for k in range(SEGS):
            a = k * math.tau / SEGS
            r, z, nr, nz = at(sbs[k][j])
            adj = [face_goo(kk % SEGS, jj) for kk in (k - 1, k) for jj in (j - 1, j) if 0 <= jj < nrow - 1]
            d = 0.0
            if j < RIM_I and any(adj):
                d = 0.4 if all(adj) else 0.1
                if k in centre and j >= centre[k]:
                    d += 0.25  # glossy ridge down the drip
                    if j == centre[k] or j == centre[k] + 1:
                        d += 0.45  # fat drop at the tip
            if tag in ("wall", "trim") and k % 2 == 0 and 2.5 < z < WALL_TOP - 0.1 and d == 0:
                r -= 0.16  # stave seams
            if abs(ang_d(a, DOOR_A)) < DOOR_W and 2.4 < z <= DOOR_TOP + 0.01:
                r -= 0.3  # door set into the staves
            row.append(bm.verts.new((math.cos(a) * (r + nr * d), math.sin(a) * (r + nr * d), z + nz * d)))
        rows.append(row)
    apex = bm.verts.new((0, 0, APEX))
    bot = bm.verts.new((0, 0, 0))
    col = bm.loops.layers.color.new("Col")
    sm = smooth_layer(bm)

    def paint(f, k, j):
        tag = PROF[j][2]
        ac = (k + 0.5) * math.tau / SEGS
        goo = face_goo(k, j)
        if goo:
            f.smooth = True
            f[sm] = 1
        for lp in f.loops:
            v = lp.vert.co
            z = v.z
            kk = round(math.atan2(v.y, v.x) / math.tau * SEGS) % SEGS
            if tag in ("pool", "rim_in"):
                rad = math.hypot(v.x, v.y)
                c = mix(GOO, GOO_HI, 0.5 * min(1, max(0, (z - ZP - 0.5) / 3.5)) + (0.4 if rad < 1.6 else 0))
            elif goo:
                c = mix(GOO, GOO_HI, 0.45) if (kk in centre and j < JC) else GOO
                if z < Z0:
                    c = mix(c, shade(GOO, 0.9), 0.5)
            elif tag in ("plinth", "plinth_top"):
                c = mix(shade(WOOD_D, 0.92), WOOD_D, min(1, z / 2.3))
            elif tag in ("trim", "trim_lo"):
                c = CREAM
            elif tag in ("hoop", "hoop_e"):
                c = METAL if tag == "hoop" else shade(METAL, 0.9)
            elif tag in ("eave_under", "eave_edge"):
                c = ROOF_D
            elif tag == "dome":
                t = (z - Z0) / 4.6
                c = mix(ROOF_D, ROOF, min(1, t * 2.2)) if t < 0.45 else mix(ROOF, shade(ROOF, 1.08), (t - 0.45) / 0.55)
            else:  # wall staves: dark foot -> light top, per-stave tint
                t = min(1, max(0, (z - 2.4) / 24))
                c = shade(mix(WOOD_D, WOOD, min(1, 0.25 + t * 1.2)), TINTS[k // 2])
                if abs(ang_d(ac, DOOR_A)) < DOOR_W and z <= DOOR_TOP + 0.01:
                    plank = 1.0 if (k % 2) else 0.9  # red barn-door planks, thin cream lintel only
                    c = CREAM if PROF[j][1] > DOOR_TOP - 0.61 else shade(mix(ROOF_D, ROOF, min(1, z / 9)), plank)


            lp[col] = c

    for j in range(nrow - 1):
        for k in range(SEGS):
            kn = (k + 1) % SEGS
            paint(bm.faces.new((rows[j][k], rows[j][kn], rows[j + 1][kn], rows[j + 1][k])), k, j)
    for k in range(SEGS):
        kn = (k + 1) % SEGS
        paint(bm.faces.new((rows[-1][k], rows[-1][kn], apex)), k, nrow - 1)
        f = bm.faces.new((rows[0][kn], rows[0][k], bot))
        for lp in f.loops:
            lp[col] = shade(WOOD_D, 0.92)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm("Silo", bm)


# ------------------------------------------------------------------ spiral slide
TURNS, THETA_END = 1.75, -math.pi / 2  # ends at the front (-Y)
R_START, R_HELIX, R_END = 4.8, 17.2, 35.5
Z_START, Z_END = ZP + 0.2, 0.7  # floor top; the head is sunk in the goo dome
FLARE = 0.62  # path fraction where the helix starts to open out to the landing ring
N = 66


def path_xy(t):
    th = THETA_END + TURNS * math.tau * (1 - t)
    if t < 0.07:
        u = t / 0.07
        r = R_START + (R_HELIX - R_START) * (1 - (1 - u) ** 2)
    elif t < FLARE:
        r = R_HELIX
    else:
        u = (t - FLARE) / (1 - FLARE)
        r = R_HELIX + (R_END - R_HELIX) * (u * u * (3 - 2 * u))
    return th, r


def slide_path():
    ts = [k / (N - 1) for k in range(N)]
    xy = []
    for t in ts:
        th, r = path_xy(t)
        xy.append(Vector((math.cos(th) * r, math.sin(th) * r)))
    L = [0.0]  # drop budget: the helix part drops faster than the run-out, so it visibly winds down
    for t, a, b in zip(ts, xy, xy[1:]):
        L.append(L[-1] + (b - a).length * (1.7 if t < FLARE else 1.0))
    tot = L[-1]
    pts = []
    for p, l in zip(xy, L):
        u = l / tot
        f = max(0.0, 1 - u / 0.9) ** 1.2  # flat run-out over the last 10 %
        pts.append(Vector((p.x, p.y, Z_END + (Z_START - Z_END) * f)))
    tot = sum((b - a).length for a, b in zip(xy, xy[1:]))
    grades = [math.degrees(math.atan2(a.z - b.z, (b.xy - a.xy).length)) for a, b in zip(pts, pts[1:])]
    print(f"SLIDE length {tot:.1f} studs, drop {Z_START - Z_END:.1f}, avg grade "
          f"{math.degrees(math.atan2(Z_START - Z_END, tot * 0.9)):.1f} deg, max {max(grades):.1f} deg, "
          f"end r {pts[-1].xy.length:.1f}")
    return pts


# U trough (lateral u, up v), closed loop; floor top at v=0
HW, IW, LIP, BOT = 3.5, 2.9, 1.9, -0.7
TROUGH = [(HW, LIP), (2.7, BOT), (-2.7, BOT), (-HW, LIP),
          (-IW, LIP), (-IW + 0.15, 0.5), (-1.9, 0.0), (1.9, 0.0), (IW - 0.15, 0.5), (IW, LIP)]
T_PART = ["out", "under", "out", "lip", "in", "floor", "floor", "floor", "in", "lip"]


def frames(pts):
    out = []
    for i, p in enumerate(pts):
        tng = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        lat = tng.cross(Vector((0, 0, 1))).normalized()
        up = lat.cross(tng).normalized()
        out.append((p, lat, up))
    return out


def slide(pts):
    bm = bmesh.new()
    rings = []
    for i, (p, lat, up) in enumerate(frames(pts)):
        m = min(1.0, max(0.0, (i / (len(pts) - 1) - 0.9) / 0.1))
        m = m * m * (3 - 2 * m)  # landing mouth: wider, lower walls, so riders spill out onto the ring
        rings.append([bm.verts.new(p + lat * u * (1 + 0.2 * m) + up * (v * (1 - 0.45 * m) if v > 0 else v))
                      for u, v in TROUGH])
    n = len(TROUGH)
    col = bm.loops.layers.color.new("Col")
    sm = smooth_layer(bm)
    for i in range(len(rings) - 1):
        for k in range(n):
            j = (k + 1) % n
            f = bm.faces.new((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]))
            part = T_PART[k]
            for lp in f.loops:
                z = lp.vert.co.z
                if part == "floor":
                    c = GOO
                elif part == "in":
                    c = mix(GOO, GOO_HI, 0.6)
                elif part == "lip":
                    c = CREAM
                elif part == "under":
                    c = WOOD_D
                else:
                    c = WOOD
                lp[col] = c
            if part in ("floor", "in"):
                f.smooth = True
                f[sm] = 1
    caps = [bm.faces.new(list(reversed(rings[0]))), bm.faces.new(rings[-1])]
    for f in caps:
        for lp in f.loops:
            lp[col] = WOOD
    bmesh.ops.triangulate(bm, faces=caps)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm("Slide", bm)


def supports(pts):
    out = []
    fr = frames(pts)
    last = -99
    for i, (p, lat, up) in enumerate(fr):
        if i - last < 6 or i < 5:
            continue
        last = i
        under = p + up * BOT
        r = under.xy.length
        a = math.atan2(under.y, under.x)
        if under.z > 9:  # high up: brackets from the staves
            zb = under.z - 0.45
            r0 = wall_r(zb) - 0.3
            mid = (r0 + r + 0.8) / 2
            out.append(box(f"Beam{i}", (r + 0.8 - r0, 0.9, 0.9), (math.cos(a) * mid, math.sin(a) * mid, zb),
                           WOOD_D, rot=(0, 0, math.degrees(a))))
            s0 = Vector((math.cos(a) * r0, math.sin(a) * r0, zb - 4.5))
            s1 = Vector((math.cos(a) * (r - 0.5), math.sin(a) * (r - 0.5), zb - 0.2))
            out.append(tube(f"Strut{i}", [s0, (s0 + s1) / 2, s1], [0.4, 0.4, 0.4], WOOD_D, segs=6))
        else:  # low: chunky posts on the ground
            for side in (-1, 1):
                q = under + lat * side * 2.3
                h = q.z + 0.2
                out.append(cylinder(f"Post{i}{side}", 0.6, h, (q.x, q.y, 0), WOOD_D, segs=6))
    for o in out:
        gradient(o, WOOD_D, mix(WOOD_D, WOOD, 0.6))

    return out


# ------------------------------------------------------------------ slimes popping out of the goo
def gumdrop(name, pos, scale, color, tilt=(0, 0, 0)):
    bm = bmesh.new()
    segs = 10
    zs = [0.0, 0.35, 1.0, 1.7, 2.35, 2.8]

    rings = [[bm.verts.new((math.cos(k * math.tau / segs) * slime_radius(z) * scale,
                            math.sin(k * math.tau / segs) * slime_radius(z) * scale, z * scale))
              for k in range(segs)] for z in zs]
    top = bm.verts.new((0, 0, SLIME_TIP * scale))
    bot = bm.verts.new((0, 0, 0))
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            bm.faces.new((a[k], a[j], b[j], b[k]))
    for k in range(segs):
        j = (k + 1) % segs
        bm.faces.new((rings[-1][k], rings[-1][j], top))
        bm.faces.new((rings[0][j], rings[0][k], bot))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    sm = smooth_layer(bm)
    for f in bm.faces:
        f.smooth = True
        f[sm] = 1
        for lp in f.loops:
            lp[col] = mix(shade(color, 0.9), mix(color, CREAM, 0.35), min(1, lp.vert.co.z / (SLIME_TIP * scale)))
    from mathutils import Euler, Matrix
    m = Matrix.Translation(Vector(pos)) @ Euler([math.radians(x) for x in tilt]).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    o = obj_from_bm(name, bm)
    eyes = []
    for s in (-1, 1):
        e = m @ Vector((s * 0.5 * scale, -slime_radius(1.65) * scale + 0.08, 1.65 * scale))
        eyes.append(blob(f"{name}Eye{s}", 0.22 * scale, e, WOOD_D, subdiv=1, jitter=0, squash=(0.8, 0.6, 1.2)))
    return [o] + eyes


def slimes(pts):
    """slimes welling up out of the goo crown (sunk in, tilted outward) + one setting off down the slide."""
    out = []
    out += gumdrop("SlimeA", (0.2, 0.3, ZP + 2.3), 1.6, P["ranch_pink"], tilt=(0, 0, -12))
    out += gumdrop("SlimeB", (2.6, -3.2, ZP + 0.9), 1.35, P["ranch_lilac"], tilt=(-16, 12, 28))
    out += gumdrop("SlimeC", (-3.6, -2.4, ZP + 0.4), 1.25, P["ranch_butter"], tilt=(-14, -18, -40))
    i = next(i for i, p in enumerate(pts) if p.xy.length > 12.5)  # just out of the basin
    d = (pts[i + 1] - pts[i - 1]).normalized()
    yaw = math.degrees(math.atan2(d.x, -d.y))
    out += gumdrop("SlimeD", pts[i] + Vector((0, 0, -0.1)), 1.25, P["ranch_lilac"], tilt=(0, 0, yaw))
    return out


def build():
    """all parts in silo space (silo axis at the origin); returns (parts, slide path)."""
    pts = slide_path()
    parts = [silo(), slide(pts)] + supports(pts) + slimes(pts)
    for o in parts:
        if "keep_smooth" not in o.data.attributes:
            o.data.attributes.new("keep_smooth", "INT", "FACE")
    return parts, pts


def bbox_xy(parts):
    xs = [(o.matrix_world @ v.co) for o in parts for v in o.data.vertices]
    return Vector((min(v.x for v in xs), min(v.y for v in xs))), Vector((max(v.x for v in xs), max(v.y for v in xs)))


if __name__ == "__main__":
    parts, pts = build()
    lo, hi = bbox_xy(parts)
    o = finish("slime_fountain", parts)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    c = (lo + hi) / 2
    print(f"SILO_AXIS from mesh bbox centre: x {-c.x:.2f}, y {-c.y:.2f} studs (kit axes); "
          f"bbox x {lo.x:.1f}..{hi.x:.1f}, y {lo.y:.1f}..{hi.y:.1f}")
