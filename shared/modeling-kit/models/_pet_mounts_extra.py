# The second set of pet_mount_* builders (not an asset), merged into MOUNTS by models/_pet_mounts.py. Same contract:
# painted, smooth-flagged parts in the pet_cloud frame (origin bottom centre, front -Y, the pet on top); ship() fits
# the footprint to 3.3 x 2.4 unless the mount's NOFIT entry keeps its own proportions (a star or a board stretched
# to 3.3 x 2.4 stops reading as one).
import math
from models._pet_mount import *
from lib.goo import Ball, metaball_mesh

GOLD, GOLD_D = rgb(255, 208, 72), rgb(226, 160, 48)
NOFIT = {"star_cushion", "hoverboard", "crescent_moon"}


def rings_mesh(name, rings, colour=None, poles=(None, None)):
    """Closed smooth shell through rings (each a list of M 3D points, first ring to last), capped with a pole at each
    end (given point, or the ring centroid). colour(i, k, centre) -> one colour per face (band i: 0 = first cap fan,
    len(rings) = last cap fan; segment k) keeps hard steps crisp on a smooth mesh; None leaves it for paint()."""
    bm = bmesh.new()
    M = len(rings[0])
    R = [[bm.verts.new(p) for p in r] for r in rings]

    def cen(r):
        return sum((Vector(p) for p in r), Vector()) / len(r)
    b = bm.verts.new(poles[0] if poles[0] is not None else cen(rings[0]))
    t = bm.verts.new(poles[1] if poles[1] is not None else cen(rings[-1]))
    faces = []
    for k in range(M):
        j = (k + 1) % M
        faces.append((bm.faces.new((b, R[0][j], R[0][k])), 0, k))
    for i, (r0, r1) in enumerate(zip(R, R[1:])):
        for k in range(M):
            j = (k + 1) % M
            faces.append((bm.faces.new((r0[k], r0[j], r1[j], r1[k])), i + 1, k))
    for k in range(M):
        j = (k + 1) % M
        faces.append((bm.faces.new((t, R[-1][k], R[-1][j])), len(R), k))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if colour:
        col = bm.loops.layers.color.new("Col")
        sm = bm.faces.layers.int.new("keep_smooth")
        bm.faces.ensure_lookup_table()
        for fi, (_, i, k) in enumerate(faces):  # (face refs die in recalc: look them up by creation index)
            f = bm.faces[fi]
            f.smooth = True
            f[sm] = 1
            c = colour(i, k, f.calc_center_median())
            for lp in f.loops:
                lp[col] = c
    return obj_from_bm(name, bm, smooth=True)


def ellipse(a, b, wob=None):
    def f(t):
        k = 1.0 + (wob(t) if wob else 0.0)
        return (a * math.cos(t) * k, b * math.sin(t) * k)
    return f


def lathe_rings(outline, profile, M, off=(0.0, 0.0), bend=None):
    """rings of a plan outline(theta) scaled by s at height z for each (s, z) of the profile."""
    out = []
    for s, z in profile:
        ring = []
        for k in range(M):
            x, y = outline(k * math.tau / M)
            p = Vector((x * s + off[0], y * s + off[1], z))
            ring.append(bend(p) if bend else p)
        out.append(ring)
    return out


def place(o, mat):
    o.data.transform(mat)
    o.data.update()
    return o


def on_surface(n):
    """rotation matrix taking +Z to the direction n."""
    return Vector(n).normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()


# ---------------------------------------------------------------- star cushion
def star_cushion():
    """A puffy golden star pillow, one point to the front; pillowed top for the seat, orange rim."""
    R0, R1 = 0.66, 1.32

    def outline(t):
        w = 0.5 + 0.5 * math.cos(5 * (t + math.pi / 2))
        return (1.12 * (R0 + (R1 - R0) * w ** 1.6) * math.cos(t), 0.9 * (R0 + (R1 - R0) * w ** 1.6) * math.sin(t) - 0.08)
    zc = 0.55

    def puff(p):
        r = min(1.0, math.hypot(p.x / 1.12, (p.y + 0.08) / 0.9) / R1)
        d = 1 - r * r
        return Vector((p.x, p.y, p.z + (0.22 * d if p.z >= zc else -0.12 * d)))
    body = slab("Star", outline, 0.3, pos=(0, 0, zc), M=60, nt=6, nr=4, nb=2, e=0.1, bend=puff)
    TOP_C, MID, RIM = rgb(255, 234, 120), rgb(255, 204, 56), rgb(244, 150, 40)

    def f(co, n):
        r = math.hypot(co.x / 1.12, co.y) / R1
        c = mix(MID, TOP_C, clamp(n.z) * (1 - sstep(0.45, 0.9, r)))
        c = mix(c, RIM, clamp(0.6 - n.z) * 0.8)
        return shade(c, 1 - 0.18 * clamp(-n.z))
    paint(body, f)
    return [body]


# ---------------------------------------------------------------- crescent moon
def crescent_moon():
    """A pale crescent moon lying flat like a cushion: a round disc with a big bite taken out of the back. The pet sits
    on the thick front band; the slim horns sweep round behind it, low, so nothing rises up round the pet.
    Pale lemon on top, cool silver sides (warm gold and a puffy, lumpy body read as a croissant), a star on each horn.
    Built at its final size (NOFIT)."""
    R, HC, HR = 1.48, 1.2, 1.45  # outer disc radius; the bite: a disc centred at y = HC with radius HR

    def depth(x, y):  # how far (x, y) is inside the crescent (distance to the nearer edge), < 0 outside
        return min(R - math.hypot(x, y), math.hypot(x, y - HC) - HR)
    balls = []
    st = 0.12
    n = int(R / st) + 1
    for i in range(-n, n + 1):
        for j in range(-n, n + 1):
            x, y = i * st, j * st
            d = depth(x, y)
            if d > 0.05:
                # balls shrink toward the edges and the horns, so the horns taper to sharp points and drop lower
                r = min(0.26, 0.04 + 0.5 * d)
                balls.append(Ball((x, y, 0.08 + 0.9 * r), (r, r, r)))
    body = metaball_mesh("Moon", balls, resolution=0.05, tris=1400, smooth=2)
    me = body.data
    z_lo = min(v.co.z for v in me.vertices)
    for v in me.vertices:
        v.co.z -= z_lo
    raw = max(v.co.z for v in me.vertices if math.hypot(v.co.x, v.co.y + 0.8) < 0.4)  # top of the front band
    K = 0.16
    for v in me.vertices:  # soft flat top, like the cloud
        z0 = raw - K
        if v.co.z > z0:
            v.co.z = z0 + K * math.tanh((v.co.z - z0) / K)
    me.update()
    TOP_C, SIDE, BELLY = rgb(255, 246, 196), rgb(212, 212, 238), rgb(160, 166, 214)

    def f(co, n):  # pale lemon top fading to cool silver sides and a lavender belly
        c = mix(SIDE, TOP_C, sstep(0.1, 0.85, n.z))
        return mix(c, BELLY, clamp(-n.z) * 0.8)
    paint(body, f)
    parts = [body]
    # a small star standing on each horn
    pts = []
    for k in range(10):
        a = math.pi / 2 + k * math.pi / 5
        r = 0.24 if k % 2 == 0 else 0.1
        pts.append((r * math.cos(a), r * math.sin(a)))
    for side, size in ((-1, 1.0), (1, 0.72)):
        tip = max((v.co for v in me.vertices if v.co.x * side > 0), key=lambda c: c.y)  # the horn's tip
        hx, hy = tip.x - side * 0.12, tip.y - 0.22  # a little back from the tip, where the horn still has some body
        hz = max(v.co.z for v in me.vertices if math.hypot(v.co.x - hx, v.co.y - hy) < 0.18)
        star = extrude_poly("HornStar%d" % side, [(x * size, z * size) for x, z in pts], 0.1, pos=(hx, hy, hz + 0.15 * size),
                            bevel_w=0.03)  # its lower points sink into the horn
        paint(star, lambda co, n: mix(rgb(255, 210, 70), rgb(255, 246, 180), clamp(-n.y * 0.8 + 0.2)))
        parts.append(star)
    return parts


# ---------------------------------------------------------------- mushroom
def mushroom():
    """A fat red toadstool cap with raised white spots, cream gills underneath and a short stout stem."""
    a, b = 1.62, 1.18
    out = ellipse(a, b)
    cap_prof = [(0.34, 0.72), (0.62, 0.68), (0.86, 0.62), (1.0, 0.62), (1.03, 0.7), (1.0, 0.84), (0.92, 0.98), (0.78, 1.1),
                (0.56, 1.19), (0.3, 1.23)]
    NG = 4  # bands 1..NG-1 are the gills (underside), the rest the red cap
    M = 48
    RED, RED_L, RED_D, GILL, GILL_D = rgb(232, 50, 56), rgb(252, 96, 84), rgb(186, 34, 48), rgb(250, 232, 196), rgb(214, 182, 140)

    def colour(i, k, cen):
        if i < NG:
            return GILL_D if (k % 2 == 0 and i > 0) else GILL
        t = clamp((cen.z - 0.62) / 0.6)
        return mix(RED_D, mix(RED, RED_L, clamp((t - 0.6) / 0.4)), clamp(t * 1.6))
    cap = rings_mesh("Cap", lathe_rings(out, cap_prof, M), colour=colour, poles=(Vector((0, 0, 0.74)), Vector((0, 0, 1.235))))
    stem_prof = [(0.4, 0.0), (0.44, 0.08), (0.38, 0.3), (0.34, 0.55), (0.32, 0.74)]
    stem = rings_mesh("Stem", lathe_rings(ellipse(1.0, 0.85), stem_prof, 20), poles=(Vector((0, 0, 0.0)), Vector((0, 0, 0.74))))
    paint(stem, lambda co, n: mix(rgb(226, 206, 170), rgb(252, 242, 220), clamp(co.z / 0.5)))
    parts = [cap, stem]
    # raised spots on the cap sides (and two on the top, round the pet)
    for k, (ang, s, z, r) in enumerate([(-1.75, 0.95, 0.84, 0.21), (-1.0, 0.88, 0.94, 0.17), (-2.45, 0.9, 0.92, 0.18), (-0.25, 0.97, 0.8, 0.2),
                                        (2.9, 0.96, 0.82, 0.19), (0.75, 0.93, 0.88, 0.17), (1.9, 0.9, 0.9, 0.2), (2.4, 0.66, 1.16, 0.15), (0.9, 0.62, 1.17, 0.14)]):
        x, y = a * s * math.cos(ang), b * s * math.sin(ang)
        n = Vector((x / (a * a), y / (b * b), (z - 0.62) * 1.6))
        sp = sphere("Spot%d" % k, r, (0, 0, 0), subdiv=2)
        place(sp, Matrix.Translation((x, y, z)) @ on_surface(n) @ Matrix.Diagonal((1.0, 1.0, 0.42, 1.0)))
        paint(sp, lambda co, nn: mix(rgb(236, 232, 226), rgb(255, 255, 252), clamp(nn.z * 0.5 + 0.5)))
        parts.append(sp)
    return parts


# ---------------------------------------------------------------- pancakes
def pancakes():
    """A stack of four golden pancakes, slightly off-centre each, maple syrup glazed on top with drips down the side."""
    a, b, M = 1.5, 1.08, 30
    parts = []
    BROWN, SIDE, SIDE_L = rgb(196, 112, 46), rgb(238, 172, 84), rgb(252, 214, 140)
    h = 0.245
    for p in range(4):
        z0 = p * (h - 0.01)
        ox, oy = [(0.0, 0.0), (0.05, -0.03), (-0.04, 0.03), (0.02, 0.02)][p]
        wob = (lambda t, p=p: 0.025 * math.sin(3 * t + p * 1.3) + 0.015 * math.sin(7 * t + p))
        prof = [(0.9, z0), (0.99, z0 + 0.05), (1.0, z0 + h * 0.5), (0.99, z0 + h - 0.05), (0.9, z0 + h)]

        def colour(i, k, cen, z0=z0):
            if i in (0, 5):
                return BROWN
            if i in (1, 4):
                return mix(BROWN, SIDE, 0.55)
            return SIDE_L if i == 2 else SIDE
        cake = rings_mesh("Cake%d" % p, lathe_rings(ellipse(a, b, wob), prof, M, off=(ox, oy)), colour=colour,
                          poles=(Vector((ox, oy, z0)), Vector((ox, oy, z0 + h))))
        parts.append(cake)
    top = 3 * (h - 0.01) + h
    # syrup: a thin glaze on the top cake, lobed outline, drips over the rim
    SYR, SYR_L = rgb(150, 60, 16), rgb(208, 104, 30)

    DRIPS = [(-1.95, 0.3), (-1.2, 0.2), (-0.45, 0.34), (0.6, 0.22), (2.25, 0.28)]

    def soutline(t):  # lobed glaze edge that reaches the rim where a drip runs down
        k = 0.86 + 0.05 * math.sin(5 * t + 0.4) + 0.02 * math.sin(11 * t)
        for td, _ in DRIPS:
            d = math.atan2(math.sin(t - td), math.cos(t - td))
            k = max(k, 1.01 - 0.6 * d * d)
        return (a * k * math.cos(t), b * k * math.sin(t))
    glaze = slab("Syrup", soutline, 0.035, pos=(0, 0, top + 0.005), M=40, nt=2, nr=3, nb=1, e=0.04)
    paint(glaze, lambda co, n: mix(SYR, SYR_L, clamp(n.z * 0.7)))
    parts.append(glaze)
    for k, (t, ln) in enumerate(DRIPS):
        # a drip hanging flat against the side of the stack, its top tucked under the glaze lip
        e = Vector((math.cos(t) / a, math.sin(t) / b, 0)).normalized()
        rim = Vector((a * math.cos(t), b * math.sin(t), top))
        pts = [rim + e * 0.02 + Vector((0, 0, 0.02)), rim + e * 0.035 - Vector((0, 0, ln * 0.5)), rim + e * 0.04 - Vector((0, 0, ln))]
        pts.insert(2, rim + e * 0.04 - Vector((0, 0, ln * 0.85)))
        drip = soft_tube("Drip%d" % k, pts, [0.11, 0.09, 0.12, 0.06], segs=6)  # fat round drop at the end
        paint(drip, lambda co, n: mix(SYR, SYR_L, clamp(0.35 + n.z * 0.5)))
        parts.append(drip)
    return parts


# ---------------------------------------------------------------- jelly
def jelly():
    """A wobbly three-layer jelly (raspberry, mango, lime) with a glossy streak, whipped cream and a cherry on one corner."""
    sq = squircle(1.48, 1.06, 3.4)
    prof = [(0.88, 0.0), (1.0, 0.06), (0.995, 0.22), (0.99, 0.38), (0.975, 0.56), (0.965, 0.74), (0.95, 0.9), (0.94, 1.04),
            (0.9, 1.13), (0.76, 1.17)]
    LAYERS = [(0.38, rgb(226, 48, 92), rgb(246, 110, 140)), (0.74, rgb(250, 160, 40), rgb(255, 206, 98)), (9, rgb(96, 206, 86), rgb(170, 238, 140))]

    def bend(p):
        return Vector((p.x + 0.035 * math.sin(p.z * 5.5), p.y + 0.03 * math.sin(p.z * 5.5 + 1.2), p.z))

    def colour(i, k, cen):
        for zt, c, cl in LAYERS:
            if cen.z < zt:
                break
        ang = math.atan2(cen.y / 1.06, cen.x / 1.48)
        glint = (1 - sstep(0.03, 0.07, abs(ang + 2.25))) * sstep(0.12, 0.3, cen.z) * (1 - sstep(0.62, 0.8, cen.z))
        if cen.z > 1.1:
            c = cl
        return mix(c, rgb(255, 246, 250), glint * 0.5)
    body = rings_mesh("Jelly", lathe_rings(sq, prof, 52, bend=bend), colour=colour, poles=(Vector((0, 0, 0)), Vector((0, 0, 1.175))))
    parts = [body]
    cx, cy, cz = 1.02, -0.62, 1.1
    for k, (r, dz) in enumerate([(0.3, 0.1), (0.22, 0.27), (0.13, 0.4)]):
        cr = sphere("Cream%d" % k, r, (cx, cy, cz + dz), squash=(1, 1, 0.75), subdiv=2)
        paint(cr, lambda co, n: mix(rgb(236, 232, 228), rgb(255, 254, 250), clamp(n.z * 0.6 + 0.4)))
        parts.append(cr)
    cherry = sphere("Cherry", 0.19, (cx + 0.02, cy, cz + 0.62), subdiv=3)
    paint(cherry, lambda co, n: mix(rgb(170, 10, 36), rgb(240, 50, 70), clamp(n.z * 0.6 + 0.4 - n.y * 0.2)))
    stem = soft_tube("CherryStem", [(cx + 0.02, cy, cz + 0.76), (cx + 0.06, cy + 0.02, cz + 0.95), (cx + 0.16, cy + 0.06, cz + 1.06)], [0.035, 0.03, 0.025], segs=5)
    paint(stem, lambda co, n: rgb(96, 140, 50))
    return parts + [cherry, stem]


# ---------------------------------------------------------------- hoverboard
def hoverboard():
    """A sleek hoverboard: purple deck with cyan neon stripes and a dark grip pad, nose and tail kicked up,
    two thruster pods underneath with pale cyan glow cones."""
    a, b, n, M = 1.58, 0.68, 3.0, 48
    sq = squircle(a, b, n)
    SQ = [sq(k * math.tau / M) for k in range(M)]

    def sring(s):
        return [(x * s, y * s) for x, y in SQ]
    top_rings = [sring(s) for s in (0.3, 0.6, 0.66, 0.74, 0.86, 0.91, 1.0)]
    DECK, GRIP, NEON, RIM = rgb(118, 72, 210), rgb(64, 46, 116), rgb(96, 236, 255), rgb(236, 86, 200)

    def colour(zone, i, k, cen):
        if zone == "rim":
            return RIM
        if zone == "bot":
            return shade(DECK, 0.6)
        return {0: GRIP, 1: GRIP, 2: NEON, 3: DECK, 4: DECK, 5: NEON, 6: DECK}.get(i, DECK)

    def bend(p):
        u = abs(p.x) / a
        return Vector((p.x, p.y, p.z + 0.62 + 0.3 * sstep(0.62, 1.0, u) ** 1.3))
    deck = ring_slab("Deck", top_rings, 0.08, colour, nr=3, e=0.04, bottom=(0.8, 0.4), bend=bend)
    parts = [deck]
    for sx in (-1, 1):
        x = sx * 0.92
        pod = sphere("Pod%d" % sx, 0.3, (x, 0, 0.44), squash=(1.25, 1.0, 0.62), subdiv=3)
        paint(pod, lambda co, nn: mix(rgb(70, 80, 120), rgb(170, 182, 214), clamp(nn.z * 0.6 + 0.45)))
        ring = sphere("Glow%d" % sx, 0.22, (x, 0, 0.3), squash=(1.2, 1.0, 0.35), subdiv=2)
        paint(ring, lambda co, nn: rgb(130, 246, 255))
        jet = cylinder("Jet%d" % sx, 0.2, 0.28, pos=(x, 0, 0.0), segs=10, r_top=0.12)
        paint(jet, lambda co, nn: mix(rgb(220, 252, 255), rgb(120, 236, 255), clamp(co.z / 0.3)))
        parts += [pod, ring, jet]
    return parts


# ---------------------------------------------------------------- clam shell
def clam_shell():
    """An open scallop shell: fluted coral dish the pet sits in, the lid standing open behind it, a pearl in front."""
    a, b, M = 1.5, 1.05, 44
    NR = 11  # ribs
    out = ellipse(a, b)

    def rib(t):  # 1 on a rib crest, 0 in a groove, by plan angle measured from the hinge (+y)
        return 0.5 + 0.5 * math.cos(NR * (t - math.pi / 2))

    def bend(p):
        t = math.atan2(p.y / b, p.x / a)
        r = math.hypot(p.x / a, p.y / b)
        return Vector((p.x, p.y, p.z + 0.07 * rib(t) * sstep(0.35, 1.0, r)))
    outer = [(0.5, 0.1), (0.85, 0.36), (1.0, 0.72)]
    inner = [(0.95, 0.8), (0.78, 0.76), (0.45, 0.72)]
    CORAL, CORAL_L, PEARL, PEARL_S = rgb(244, 120, 132), rgb(255, 186, 176), rgb(255, 232, 232), rgb(232, 214, 246)

    def colour(i, k, cen):
        t = math.atan2(cen.y / b, cen.x / a)
        if i <= len(outer):
            return mix(CORAL, CORAL_L, rib(t) * 0.8)
        return mix(PEARL, PEARL_S, clamp(1 - math.hypot(cen.x / a, cen.y / b)) * 0.7)
    dish = rings_mesh("Dish", lathe_rings(out, outer + inner, M, bend=bend), colour=colour, poles=(Vector((0, 0, 0)), Vector((0, 0, 0.72))))
    lid = rings_mesh("Lid", lathe_rings(out, outer + inner, M, bend=bend), colour=colour, poles=(Vector((0, 0, 0)), Vector((0, 0, 0.72))))
    # the lid: the same shell turned over, hinged on the back edge, opened 135 degrees so it leans back behind the pet
    hinge = Vector((0, b * 0.98, 0.74))
    flip = Matrix.Rotation(math.pi, 4, "X")  # turned over: its dish faces down onto the bottom one
    place(lid, Matrix.Translation(hinge) @ Matrix.Rotation(math.radians(-135), 4, "X") @ Matrix.Translation(-hinge)
          @ Matrix.Translation((0, 0, 1.48)) @ flip)
    pearl = sphere("Pearl", 0.24, (-0.92, -0.4, 0.92), subdiv=3)
    paint(pearl, lambda co, n: mix(rgb(226, 222, 238), rgb(255, 255, 255), clamp(n.z * 0.5 + 0.5 - n.y * 0.3)))
    return [dish, lid, pearl]


# ---------------------------------------------------------------- royal cushion
def royal_cushion():
    """A plump purple velvet throne cushion with a gold button, gold piping round the seam and a tassel on each corner."""
    a, b, c = 1.52, 1.08, 0.36
    zc = 0.46

    def bend(p):
        r2 = (p.x / a) ** 2 + (p.y / b) ** 2
        return Vector((p.x, p.y, p.z - (0.07 * math.exp(-r2 / 0.03) if p.z > zc else 0.0)))
    body = pillow("Cushion", a, b, c, pos=(0, 0, zc), nx=12, ny=8, nz=5, pxy=0.6, pz=0.75, bend=bend)
    VEL, VEL_L, VEL_D = rgb(124, 52, 176), rgb(172, 102, 222), rgb(78, 30, 122)

    def f(co, n):
        c_ = mix(VEL_D, VEL, clamp(0.5 + 0.6 * n.z))
        return mix(c_, VEL_L, clamp(n.z) ** 3 * 0.6)
    paint(body, f)
    parts = [body]
    # gold piping round the seam (a closed tube along the rounded-square rim)
    pts = []
    N = 34
    for k in range(N + 2):
        t = k * math.tau / N
        ct, st = math.cos(t), math.sin(t)
        pts.append((a * 1.01 * math.copysign(abs(ct) ** 0.6, ct), b * 1.01 * math.copysign(abs(st) ** 0.6, st), zc))
    pipe = soft_tube("Piping", pts, [0.07] * len(pts), segs=6)
    paint(pipe, lambda co, n: mix(GOLD_D, GOLD, clamp(n.z * 0.6 + 0.5)))
    parts.append(pipe)
    button = sphere("Button", 0.11, (0, 0, zc + c - 0.05), squash=(1, 1, 0.6), subdiv=2)
    paint(button, lambda co, n: GOLD)
    parts.append(button)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * a * 1.01 * 0.812, sy * b * 1.01 * 0.812  # the piping's corner (t = 45 degrees)
            knot = sphere("Knot%d%d" % (sx, sy), 0.12, (x, y, zc - 0.02), subdiv=2)
            tas = cylinder("Tassel%d%d" % (sx, sy), 0.12, 0.3, pos=(x + sx * 0.03, y + sy * 0.03, zc - 0.42), segs=8, r_top=0.05)
            for o in (knot, tas):
                paint(o, lambda co, n: mix(GOLD_D, GOLD, clamp(n.z * 0.5 + 0.5)))
            parts += [knot, tas]
    return parts


EXTRA = {
    "star_cushion": star_cushion,
    "crescent_moon": crescent_moon,
    "mushroom": mushroom,
    "pancakes": pancakes,
    "jelly": jelly,
    "hoverboard": hoverboard,
    "clam_shell": clam_shell,
    "royal_cushion": royal_cushion,
}
