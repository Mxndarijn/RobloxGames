# slime_fountain: Steal a Slime hub centrepiece (Slime Ranch theme, THEME.md + FOUNTAIN_SIZES.md).
# "Ranch silo meets goo fountain": a chunky wooden silo (staves, brass hoops, red dome roof) whose
# top is a goo basin that overflows. All the goo is METABALLS converted to mesh (lib/goo.py), so it
# merges like real goo: a bubbling crown, a wavy collar over the roof and drips down the staves
# that fuse into the collar and end in fat round drops (the shell sits GOO_T proud of the silo and
# runs into it); teardrop goo lumps on the slide floor; a splash pool where the slide ends.
# A goo spiral slide leaves the basin lip and winds ~1.5 turns down to the landing ring.
# The gumdrop slimes welling up out of the crown are NOT in this mesh: they are the optional
# second MeshPart models/slime_fountain_emerge.py (same silo space; it prints its offset).
#
# Kit space: studs, Z up, front -Y, z=0 ground. The silo axis is at the world origin while
# modelling; finish() re-centres the mesh on its bbox, so the silo axis offset is printed
# (SILO_AXIS) for placing the MeshPart in the hub.
import math, random
import bmesh, bpy
from mathutils import Vector
from lib import *

P = PALETTE
WOOD, WOOD_D, CREAM = P["ranch_wood"], P["ranch_wood_dark"], P["ranch_cream"]
ROOF, ROOF_D, METAL = P["ranch_roof"], P["ranch_roof_dark"], P["ranch_metal"]
GOO, GOO_HI = P["ranch_goo"], P["ranch_goo_hi"]
SEGS = 44

R = random.Random(11)


def smooth_layer(bm):
    return bm.faces.layers.int.get("keep_smooth") or bm.faces.layers.int.new("keep_smooth")


# ------------------------------------------------------------------ silo profile (r, z, tag, free)
# tag = what the band from this ring up to the next one is. "free" is left over from the
# displaced-goo version (rows snapped per column onto the goo edge); unused since the metaball goo.
WALL_TOP = 30.0


def wall_r(z):
    """staves bulge a little (barrel): chunky and rounded, 11.2 at the foot and top, 11.7 mid."""
    return 11.2 + 0.5 * math.sin(math.pi * min(1, max(0, (z - 2.4) / (WALL_TOP - 2.4))))


PROF = [(13.0, 0.0, "plinth", 0), (13.1, 1.5, "plinth_top", 0), (12.3, 2.3, "trim_lo", 0), (11.2, 2.4, "trim", 0)]
wall_z = [3.3, ("hoop", 6.5), 9.4, 10.0, ("hoop", 15.5), 19.5, ("hoop", 25.4), 27.8]
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
APEX = ZP + 0.4  # low basin floor: hidden under the metaball goo dome
RIM_I = next(i for i, p in enumerate(PROF) if p[2] == "rim_in")  # rim top ring: the goo starts here

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
DRIPS = [(-120, 32.4, 1.0), (-82, 21.0, 1.25), (-8, 25.8, 0.85), (38, 31.0, 1.1), (64, 17.6, 1.2), (135, 23.2, 0.9),
         (222, 19.2, 1.3), (292, 27.2, 0.8)]  # (angle deg, tip z, width)

# metaball goo (lib/goo.py): GOO_T = how far the goo skin stands proud of the silo surface
GOO_T, COLLAR_N, CROWN_RES, CROWN_TRIS = 0.5, 22, 0.32, 1450
GOO_LO_Z = Z0 - 1.0
CROWN_TOP = 7.1  # centre bubble top above the goo level (sets the model height)


def plank_tint(k):
    return [1.0, 0.93, 1.05, 0.97, 0.9, 1.02][k % 6] * (0.97 + 0.06 * R.random())


TINTS = [plank_tint(k) for k in range(SEGS // 2)]
DOOR_A, DOOR_W, DOOR_TOP = -math.pi / 2, 0.29, 10.0  # 4 columns of red planks


def silo():
    """plain silo surface of revolution; all the overflowing goo is the metaball crown on top."""
    nrow = len(PROF)
    bm = bmesh.new()
    rows = []  # rows[j][k]
    for j in range(nrow):
        tag = PROF[j][2]
        row = []
        for k in range(SEGS):
            a = k * math.tau / SEGS
            r, z = PROF[j][0], PROF[j][1]
            if tag in ("wall", "trim") and k % 2 == 0 and 2.5 < z < WALL_TOP - 0.1:
                r -= 0.16  # stave seams
            if abs(ang_d(a, DOOR_A)) < DOOR_W and 2.4 < z <= DOOR_TOP + 0.01:
                r -= 0.3  # door set into the staves
            row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rows.append(row)
    apex = bm.verts.new((0, 0, APEX))
    bot = bm.verts.new((0, 0, 0))
    col = bm.loops.layers.color.new("Col")
    smooth_layer(bm)

    def paint(f, k, j):
        tag = PROF[j][2]
        ac = (k + 0.5) * math.tau / SEGS
        for lp in f.loops:
            z = lp.vert.co.z
            if tag in ("pool", "rim_in", "rim"):
                c = GOO  # under the goo crown
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


# ------------------------------------------------------------------ metaball goo
def goo_col(co, n, lo=GOO_LO_Z):
    """goo base, a touch of goo_hi on up-facing upper parts, slightly deeper low down."""
    c = mix(GOO, GOO_HI, 0.3 * max(0.0, n.z) ** 2 * min(1, max(0, (co.z - ZP) / 3.5)))
    if co.z < lo:
        c = mix(c, shade(GOO, 0.95), min(1, (lo - co.z) / 12))
    return c


def surf_frame(a, sb):
    """point on the silo surface at angle a / profile arclength sb + (down-slope, lateral, normal)."""
    r, z, nr, nz = at(sb)
    ca, sa = math.cos(a), math.sin(a)
    n = Vector((ca * nr, sa * nr, nz)).normalized()
    lat = Vector((-sa, ca, 0))
    down = lat.cross(n).normalized()  # (down, lat, n) is right-handed
    return Vector((ca * r, sa * r, z)), down, lat, n


def goo_crown():
    balls = []
    # fat bubbling crown welling up out of the basin: a flat lens filling the basin, a ring of fat
    # bubbles and one big centre bubble (summed fields of nested ellipsoids peak into a cone)
    balls.append(Ball((0, 0, ZP + 0.3), (8.0, 8.0, 2.0)))
    for k, (rr, z, s) in enumerate(((4.9, 2.3, 2.2), (4.6, 2.8, 2.0), (5.0, 2.1, 2.3), (4.5, 2.6, 1.9), (4.8, 2.4, 2.1))):
        a = k * math.tau / 5 + 0.4
        balls.append(Ball((math.cos(a) * rr, math.sin(a) * rr, ZP + z), s))
    balls.append(Ball((0.3, 0.2, ZP + CROWN_TOP - 3.0), 3.0))
    sb_rim = SB[RIM_I]
    # collar spilling over the rim: flat lenses on the shoulder, reach set by collar()
    for k in range(COLLAR_N):
        a = k * math.tau / COLLAR_N
        reach = collar(a)
        p, down, lat, n = surf_frame(a, sb_rim - reach * 0.55)
        balls.append(Ball(p + n * (GOO_T - 0.75), (reach * 0.55 + 0.4, 1.5, 0.75), rot=frame_quat(down, lat, n)))
    # drips: a chain of flat lenses down the roof / staves, thinning, with a fat round drop at the tip
    for deg, zend, wd in DRIPS:
        a = math.radians(deg)
        s0, s1 = sb_rim - collar(a) * 0.8, sb_of_z(zend)
        m = max(2, int((s0 - s1) / 0.7))
        for i in range(m + 1):
            t = i / m
            p, down, lat, n = surf_frame(a, s0 + (s1 - s0) * t)
            w = wd * (1.05 - 0.45 * t)
            balls.append(Ball(p + n * (GOO_T - 0.6), (0.9, w, 0.6), rot=frame_quat(down, lat, n)))
        if s0 - s1 > 9:  # long runs carry a bead half way down
            p, down, lat, n = surf_frame(a, s0 + (s1 - s0) * 0.55)
            balls.append(Ball(p + n * (GOO_T - 0.6), (1.0, wd * 0.95, 0.75), rot=frame_quat(down, lat, n)))
        p, down, lat, n = surf_frame(a, s1 + 0.3)
        tip = 0.6 + 0.25 * wd
        balls.append(Ball(p + n * (GOO_T + 0.1 - tip), tip))
    o = metaball_mesh("GooCrown", balls, resolution=CROWN_RES, tris=CROWN_TRIS)
    return paint_goo(o, goo_col)


# ------------------------------------------------------------------ spiral slide
TURNS, THETA_END = 1.75, -math.pi / 2  # ends at the front (-Y)
R_START, R_HELIX, R_END = 4.8, 17.2, 35.5
Z_START, Z_END = ZP + 0.2, 0.7  # floor top; the head is sunk in the goo dome
FLARE = 0.62  # path fraction where the helix starts to open out to the landing ring
N = 66
LUMPS = [(9, 0.3), (17, -0.5), (26, 0.4), (34, -0.2), (44, 0.5), (53, -0.4)]  # (path index, lateral)
SLIDE_GOO_TRIS, POOL_TRIS = 400, 460
POOL_D, POOL_R = 4.8, (4.8, 3.3)  # puddle centre past the mouth, radii (along, across)


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


# ------------------------------------------------------------------ goo on the slide + splash pool
def slide_goo(pts):
    """flowing goo lumps on the slide floor: teardrops (fat head downstream, thin tail upstream)
    sunk into the floor so only a low swell shows."""
    fr = frames(pts)
    balls = []
    for i0, lat_off in LUMPS:
        p0, lat, up = fr[i0]
        tng = (pts[i0 + 1] - pts[i0 - 1]).normalized()
        n = lat.cross(tng).normalized()
        n = n if n.z > 0 else -n
        ln = n.cross(tng).normalized()
        for j, (s_al, s_lat, s_up) in enumerate(((1.2, 1.35, 0.7), (1.1, 1.05, 0.55), (1.0, 0.8, 0.45),
                                                 (0.9, 0.55, 0.38), (0.8, 0.4, 0.32))):
            p = p0.lerp(pts[i0 - 1], j * 0.27)  # tail trails upstream, ~0.95 studs per element
            balls.append(Ball(p + ln * lat_off * (1 - 0.15 * j) + n * (s_up * 0.6 - 0.25), (s_al, s_lat, s_up),
                              rot=frame_quat(tng, ln, n)))
    o = metaball_mesh("GooSlide", balls, resolution=0.3, tris=SLIDE_GOO_TRIS)
    return paint_goo(o, lambda co, n: mix(GOO, GOO_HI, 0.7 * max(0.0, n.z) ** 4))


def splash_pool(pts):
    """the goo the riders bring down: a low puddle past the slide mouth, ripple ring, a pour over the
    mouth lip and a couple of fat droplets merging into the rim. Flat bottom at the ground."""
    end = pts[-1]
    d = (pts[-1] - pts[-2]).xy.normalized()
    d3 = Vector((d.x, d.y, 0))
    side = Vector((-d.y, d.x, 0))
    c = end + d3 * POOL_D
    c.z = 0.0
    balls = [Ball(c, (POOL_R[0] * 0.8, POOL_R[1] * 0.8, 0.3)),
             Ball(c - d3 * 2.8, (2.2, 2.0, 0.4))]
    for k in range(14):  # ripple ring: a raised rim of uneven lenses round a lower middle
        a = k * math.tau / 14 + 0.3
        rr = 0.86 + 0.07 * math.sin(3 * a + 1)
        q = c + d3 * math.cos(a) * POOL_R[0] * rr + side * math.sin(a) * POOL_R[1] * rr
        tg = (side * math.cos(a) * POOL_R[1] - d3 * math.sin(a) * POOL_R[0]).normalized()
        balls.append(Ball(q, (1.0 + 0.2 * (k % 3), 0.62, 0.78 - 0.1 * (k % 2)),
                          rot=frame_quat(tg, Vector((0, 0, 1)).cross(tg), Vector((0, 0, 1)))))
    for t, z in ((-1.2, 0.55), (0.2, 0.45), (1.2, 0.2), (2.2, 0.05)):  # thin sheet pouring over the mouth lip
        balls.append(Ball(end + d3 * t + Vector((0, 0, z - end.z)), (0.8, 1.6, 0.4)))
    for off, h, rad in ((d3 * 2.0 + side * 1.4, 0.75, 0.6), (-d3 * 0.2 - side * 1.6, 0.6, 0.48),
                        (d3 * 3.4 - side * 0.5, 0.5, 0.42)):  # fat drops landing in the rim
        balls.append(Ball(c + off + Vector((0, 0, h)), rad))
    o = metaball_mesh("GooPool", balls, resolution=0.25, tris=POOL_TRIS, clamp_z=0.02)
    return paint_goo(o, lambda co, n: mix(shade(GOO, 0.95), GOO_HI, 0.35 * max(0.0, n.z) ** 3 * min(1, co.z / 1.2)))


def build():
    """all parts in silo space (silo axis at the origin); returns (parts, slide path)."""
    pts = slide_path()
    parts = [silo(), goo_crown(), slide(pts), slide_goo(pts), splash_pool(pts)] + supports(pts)
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
