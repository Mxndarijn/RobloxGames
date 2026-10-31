# Astronaut (Legendary, Starlight): a slime in a white space suit. The suit is painted onto the body with a
# round visor window at the front, where the violet goo face shows through (a gold visor rim, glass glints);
# helmet ear discs with a star-tipped antenna, an orange chest panel, a backpack with oxygen tanks, and a
# little flag held up in a white glove. Awe-struck sparkle eyes.
from models._slimepool import *

GOO, GOO_D, GOO_L = hexc("a46cff"), hexc("8c5cee"), hexc("dcc4ff")
SUIT, SUIT_D, SUIT_L = hexc("f2f5fb"), hexc("d8deea"), hexc("ffffff")
GREY, GREY_D = hexc("9aa6bc"), hexc("8e9ab2")
ORANGE, ORANGE_D = hexc("ff8a3a"), hexc("f88442")
RIM, RIM_D, RIM_L = hexc("ffd040"), hexc("f6b83c"), hexc("fff2a8")
FLAG, FLAG_D = hexc("5ab8ff"), hexc("48a0f6")
KEY = Vector((-0.4, -0.6, 0.7)).normalized()

VC, VR = 1.6, 0.84  # visor window centre height and radius (front projection, studs)


def lit(c0, c1, c2=None):
    def fn(p, n):
        k = n.dot(KEY)
        c = mix(c0, c1, 0.45 + 0.55 * smoothstep(-0.6, 0.2, k))
        return mix(c, c2, smoothstep(0.55, 0.95, k)) if c2 else c
    return fn


def in_visor(p):
    return p.y < 0 and math.hypot(p.x, p.z - VC) < VR


def paint(a, z, p):
    if in_visor(p):
        c = mix(GOO_D, GOO, smoothstep(0.5, 1.6, z))
        return mix(c, GOO_L, 0.3 * smoothstep(1.7, 2.3, z))
    if z < 0.42 + 0.07 * math.sin(7 * a):  # goo oozing out under the suit hem
        return mix(GOO_D, GOO, smoothstep(0.0, 0.45, z))
    return mix(SUIT_D, SUIT, smoothstep(0.0, 1.0, z))


b = Body([(0, 1.1), (0.14, 1.36), (0.5, 1.5), (1.1, 1.48), (1.8, 1.28), (2.4, 0.95), (2.78, 0.5), (2.9, 0)],
         paint=paint, segs=36, sub=2)
parts = [b.obj]
H = b.H


def ring_tube(name, pts, r, color, rsegs=6):
    """closed tube through a closed loop of points."""
    P = [Vector(p) for p in pts]
    n = len(P)
    bm = bmesh.new()
    rings = []
    for i in range(n):
        t = (P[(i + 1) % n] - P[i - 1]).normalized()
        up = Vector((0, -1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
        x = t.cross(up).normalized()
        y = t.cross(x).normalized()
        rings.append([bm.verts.new(P[i] + (x * math.cos(j * math.tau / rsegs) + y * math.sin(j * math.tau / rsegs)) * r) for j in range(rsegs)])
    for i in range(n):
        A, B = rings[i], rings[(i + 1) % n]
        for j in range(rsegs):
            k = (j + 1) % rsegs
            bm.faces.new((A[j], A[k], B[k], B[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True)


# ---- visor rim: a gold tube following the body round the window
rim_pts = []
for k in range(32):
    t = k * math.tau / 32
    u, v = math.sin(t) * VR, VC + math.cos(t) * VR
    loc, nn, _ = cast(Vector((u, -12, v)), Vector((0, 1, 0)), ["Body"])
    rim_pts.append(tuple(loc + nn * 0.03))
parts.append(ring_tube("VisorRim", rim_pts, 0.1, lit(RIM_D, RIM, RIM_L), rsegs=6))

# ---- face inside the visor: awe-struck sparkle eyes, small open "wow" mouth, glass glints
f = Face(b, eye_v=1.66, eye_u=0.4, mouth_v=1.14)
f.eyes("sparkle", w=0.4, h=0.52, iris=hexc("58d8ff"))
f.mouth("o", w=0.8)
f.cheeks(color=hexc("ff8ad0"), w=0.22, h=0.1, u=0.62, v=1.3)
parts += f.parts
parts.append(decal("Glint0", arc(0, VC, VR - 0.14, 112, 152, 0.1, n=7), mix(GOO_L, WHITE, 0.75), FRONT, off=0.015, th=0.012, on=["Body"]))
parts.append(decal("Glint1", arc(0, VC, VR - 0.14, 159, 170, 0.1, n=3), mix(GOO_L, WHITE, 0.75), FRONT, off=0.015, th=0.012, on=["Body"]))

# ---- helmet ear discs + antenna with a star tip (Ant* so the rig wiggles it)
for sd in (-1, 1):
    p = b.point(math.radians(sd * 90), 1.6, -0.04)
    ax = Vector((sd, 0, 0))
    parts.append(lathe(f"EarDisc{sd}", [(0, 0.34), (0.1, 0.34), (0.15, 0.26), (0.17, 0)], lit(GREY_D, GREY, SUIT_L), pos=tuple(p), axis=tuple(ax), segs=16))
    parts.append(lathe(f"EarLight{sd}", [(0, 0.14), (0.05, 0.14), (0.07, 0)], ORANGE, pos=tuple(p + ax * 0.15), axis=tuple(ax), segs=10))
ap = b.point(math.radians(-90), 1.6, 0.06) + Vector((0, 0, 0.25))
parts.append(horn("AntRod", [tuple(ap), tuple(ap + Vector((-0.05, 0, 0.45))), tuple(ap + Vector((-0.12, 0.02, 0.85)))], [0.06, 0.05, 0.045], GREY, SUIT_L))
tipc = ap + Vector((-0.12, 0.02, 1.0))
parts.append(slab("AntStar", star(0, 0, 0.25, 0.11), 0.09, tuple(tipc), (1, 0, 0), (0, 0, 1), lit(RIM_D, RIM, RIM_L)))

# ---- chest panel: orange plate under the visor with three buttons
parts.append(decal("Panel", rect(0, 0.62, 0.74, 0.22), lit(GREY_D, GREY, SUIT_L), FRONT, off=0.02, th=0.04, on=["Body"]))
for k, c in enumerate((hexc("ff3a4a"), hexc("ffd23a"), hexc("3ad8ff"))):
    parts.append(decal(f"Btn{k}", oval((k - 1) * 0.21, 0.62, 0.12, 0.12, n=10), c, FRONT, off=0.065, th=0.02, on=["Body"]))
# orange shoulder patches (mission stripes) on both sides
for sd in (-1, 1):
    parts.append(decal(f"Patch{sd}", oval(0, 0, 0.36, 0.36, n=14), ORANGE, frame_at(sd * 55, 1.05), off=0.015, th=0.02, on=["Body"]))
    parts.append(decal(f"PatchStar{sd}", star(0, 0, 0.13, 0.055), SUIT_L, frame_at(sd * 55, 1.05), off=0.04, th=0.01, on=["Body"]))

# ---- backpack with two oxygen tanks
bp = b.point(math.pi, 1.3, 0.34)
parts.append(ball("Pack", 0.62, tuple(bp), lit(SUIT_D, SUIT, SUIT_L), squash=(1.25, 0.55, 1.25), subdiv=2))
for sd in (-1, 1):
    tp = bp + Vector((sd * 0.42, 0.24, -0.15))
    parts.append(lathe(f"Tank{sd}", [(0, 0), (0.02, 0.2), (0.15, 0.22), (0.95, 0.22), (1.08, 0.18), (1.12, 0)], lit(ORANGE_D, ORANGE, hexc("ffc89a")),
                       pos=tuple(tp + Vector((0, 0, -0.45))), segs=12))
    parts.append(lathe(f"Valve{sd}", [(0, 0.07), (0.14, 0.07), (0.16, 0)], GREY, pos=tuple(tp + Vector((0, 0, 0.66))), segs=8))

# ---- glove hand on its left (viewer's right) holding a flag pole up
HC = Vector((1.72, -0.5, 1.15))
parts.append(goo("Hand", [((1.3, -0.3, 1.1), 0.3), ((1.55, -0.42, 1.12), 0.22), (tuple(HC), 0.23, (1.0, 1.0, 1.05))],
                 lit(SUIT_D, SUIT, SUIT_L), tris=140, resolution=0.08))
parts.append(torus("Cuff", 0.2, 0.06, (1.5, -0.4, 1.12), (1, -0.35, 0.05), ORANGE, segs=12, rsegs=4))
P0, P1 = HC + Vector((0.0, -0.05, -0.75)), HC + Vector((0.0, -0.05, 2.05))
parts.append(lathe("Pole", [(0, 0.045), (P1.z - P0.z, 0.045)], lit(GREY_D, GREY, SUIT_L), pos=tuple(P0), segs=8))
parts.append(ball("PoleTop", 0.08, tuple(P1), RIM, subdiv=1))

# flag cloth: wavy sheet off the pole (Ribbon* so it sways), sky blue with a gold star
FW, FHt = 1.0, 0.62
FZ = P1.z - 0.08


def flag_pt(s, t):
    x = P1.x + 0.05 + FW * s
    z = FZ - FHt * t - 0.06 * s
    y = P1.y + 0.1 * math.sin(s * math.pi * 1.6) * s
    return (x, y, z)


def shell(name, fn, nu, nv, thick, color):
    bm = bmesh.new()
    P = [[Vector(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]

    def nrm(i, j):
        a = P[min(i + 1, nu)][j] - P[max(i - 1, 0)][j]
        c = P[i][min(j + 1, nv)] - P[i][max(j - 1, 0)]
        return a.cross(c).normalized()
    outer = [[bm.verts.new(P[i][j] + nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    inner = [[bm.verts.new(P[i][j] - nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]))
            bm.faces.new((inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j], inner[i][j]))
    for i in range(nu):
        for j in (0, nv):
            bm.faces.new((outer[i][j], inner[i][j], inner[i + 1][j], outer[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True)


flag = shell("RibbonFlag", flag_pt, 8, 2, 0.04, lambda p, n: mix(FLAG_D, FLAG, 0.5 + 0.5 * smoothstep(-0.3, 0.6, n.dot(KEY))))
parts.append(register(flag, "RibbonFlag"))
fc = Vector(flag_pt(0.5, 0.5))
parts.append(decal("FlagStar", star(fc.x, fc.z, 0.2, 0.09), RIM, FRONT, off=0.01, th=0.02, on=["RibbonFlag"], step=0.05))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_astronaut", parts)
