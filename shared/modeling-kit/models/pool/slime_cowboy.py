# Cowboy (Legendary, Meadow): the ranch sheriff. Bright denim-blue goo under a wide caramel cowboy hat
# (curled-up brim, pinched crown, red band), a gold sheriff star, a red bandana knotted at the side,
# a cool squint with a straw in the corner of its smirk, and a rope lasso swung up over its head.
from models._slimepool import *

BLUE, BLUE_D, BLUE_L = hexc("3ea6ff"), hexc("4088ee"), hexc("a8dcff")
HAT, HAT_D, HAT_L = hexc("ecb272"), hexc("d4945a"), hexc("f8cc92")
BANDR, BANDR_D = hexc("ee3040"), hexc("dc2c40")
STAR, STAR_D, STAR_L = hexc("ffd040"), hexc("f6b83c"), hexc("fff2a8")
ROPE, ROPE_D = hexc("f0cc7a"), hexc("e2b468")
STRAW = hexc("ffe27a")
KEY = Vector((-0.4, -0.6, 0.7)).normalized()


def lit(c0, c1, c2=None):
    def fn(p, n):
        k = n.dot(KEY)
        c = mix(c0, c1, 0.45 + 0.55 * smoothstep(-0.6, 0.2, k))
        return mix(c, c2, smoothstep(0.55, 0.95, k)) if c2 else c
    return fn


ZB0, ZB1 = 0.5, 0.74  # bandana band


def paint(a, z, p):
    c = mix(BLUE_D, BLUE, smoothstep(0.0, 1.2, z))
    return mix(c, BLUE_L, 0.35 * smoothstep(0.7, 0.1, abs(a)) * smoothstep(1.4, 0.5, z))


def bandana(a, z):
    if not (ZB0 <= z <= ZB1):
        return None
    return BANDR


b = Body([(0, 1.1), (0.14, 1.36), (0.5, 1.5), (1.1, 1.48), (1.8, 1.28), (2.4, 0.95), (2.78, 0.5), (2.9, 0)],
         paint=paint, segs=30, sub=2, bands=[(ZB0, ZB1, BANDR)], sectors=bandana)
parts = [b.obj]
H = b.H

# ---- hat: brim as one closed swept section (sides curl up, front dips a touch), pinched crown, red band
ZH = 2.3
R0 = b.radius(ZH) + 0.02
R1 = 2.05


def brim(name, segs=36, nt=5, th=0.09):
    bm = bmesh.new()
    loops = []
    for i in range(segs):
        a = i * math.tau / segs
        curl = 0.62 * math.sin(a) ** 2 - 0.1 * max(0.0, -math.cos(a)) ** 2 + 0.05 * max(0.0, math.cos(a))
        top, bot = [], []
        for j in range(nt + 1):
            t = j / nt
            r = R0 + (R1 - R0) * t
            z = ZH + curl * t ** 2.2
            top.append((r, z + th / 2))
            bot.append((r + 0.0, z - th / 2))
        sec = top + list(reversed(bot))
        loops.append([bm.verts.new((math.sin(a) * r, -math.cos(a) * r, z)) for r, z in sec])
    m = len(loops[0])
    for i in range(segs):
        A, B = loops[i], loops[(i + 1) % segs]
        for j in range(m):
            k = (j + 1) % m
            bm.faces.new((A[j], A[k], B[k], B[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None)
    paint_fn(o, lambda p, n: mix(lit(HAT_D, HAT, HAT_L)(p, n), HAT_L, 0.3 * smoothstep(1.6, 2.05, math.hypot(p.x, p.y))))
    return keep(o, True)


parts.append(brim("Brim"))
crown_prof = [(ZH - 0.1, R0 * 0.98), (ZH + 0.3, R0 * 0.97), (ZH + 0.65, R0 * 0.9), (ZH + 0.92, R0 * 0.8), (ZH + 1.0, R0 * 0.55), (ZH + 0.93, 0)]
crown = lathe("Crown", crown_prof, lit(HAT_D, HAT, HAT_L), segs=28, sx=0.92, sy=1.05)
parts.append(register(crown, "Crown"))
# crease along the top + front pinch dents (dark strokes painted on)
parts.append(lathe("HatBand", [(0, R0 * 0.99 + 0.03), (0.22, R0 * 0.97 + 0.03)], lit(BANDR_D, BANDR), pos=(0, 0, ZH - 0.02), segs=28, sx=0.92, sy=1.05))
parts.append(register(parts[-1], "HatBand"))
# little gold star on the band front
parts.append(decal("BandStar", star(0, ZH + 0.09, 0.1, 0.045), STAR, FRONT, off=0.01, th=0.03, on=["HatBand"]))
for sd in (-1, 1):
    parts.append(decal(f"Pinch{sd}", rect(sd * 0.28, ZH + 0.62, 0.06, 0.32, math.radians(-14 * sd)), HAT_D, FRONT, off=0.005, th=0.015, on=["Crown"]))

# ---- face: cool half-lidded squint, one raised brow, smirk with a straw
f = Face(b, eye_v=1.6, eye_u=0.5, mouth_v=1.08)
f.eyes("sly", w=0.5, h=0.68, iris=hexc("6a3c1e"))
f.d("Brow-1", rect(-0.5, 2.0, 0.4, 0.085, math.radians(-6)), INK)
f.d("Brow1", arc(0.5, 1.9, 0.22, 50, 130, 0.085, n=8), INK)
f.mouth("smirk", w=1.0, u=-0.05, v=1.04)
f.cheeks(color=hexc("ff8fb0"), w=0.24, h=0.11)
parts += f.parts
# straw: thin stalk from the low corner of the smirk out to the viewer's left, seed head at the tip
mc = b.point(math.radians(-9), 1.0, 0.0)
st0 = mc + Vector((0.0, -0.06, 0.0))
st1 = st0 + Vector((-0.62, -0.36, -0.12))
parts.append(horn("Straw", [tuple(st0), tuple((st0 + st1) / 2 + Vector((0, 0, 0.03))), tuple(st1)], [0.05, 0.045, 0.038], hexc("f2c650"), STRAW, segs=5))
parts.append(ball("StrawSeed", 0.075, tuple(st1 + (st1 - st0).normalized() * 0.07), STRAW, squash=(1, 1, 1.6), subdiv=1))

# ---- sheriff star on the bandana front-left (viewer's right)
fr = frame_at(26, (ZB0 + ZB1) / 2 + 0.02)
parts.append(decal("Badge", star(0, 0, 0.4, 0.2), lit(STAR_D, STAR, STAR_L), fr, off=0.02, th=0.05, on=["Body"], step=0.06))
for k in range(5):
    a = math.radians(90 + k * 72)
    parts.append(decal(f"BadgeTip{k}", oval(math.cos(a) * 0.4, math.sin(a) * 0.4, 0.12, 0.12, n=8), STAR, fr, off=0.02, th=0.05, on=["Body"]))
parts.append(decal("BadgeHi", oval(0, 0, 0.17, 0.17, n=10), STAR_L, fr, off=0.08, th=0.01, on=["Body"]))

# ---- bandana knot on its right side (viewer's left) with two tails
ka = math.radians(-70)
kp = b.point(ka, (ZB0 + ZB1) / 2, 0.06)
kd = Vector((math.sin(ka), -math.cos(ka), 0))
parts.append(ball("Knot", 0.16, tuple(kp), BANDR, squash=(1, 1, 0.9)))
side = Vector((math.cos(ka), math.sin(ka), 0))
for j, (dx, L) in enumerate(((-0.13, 0.42), (0.13, 0.34))):
    p0 = kp + kd * 0.05
    pts = [p0, p0 + kd * 0.12 + side * dx + Vector((0, 0, -0.2)), p0 + kd * 0.16 + side * dx * 1.6 + Vector((0, 0, -L))]
    parts.append(horn(f"Tail{j}", [tuple(p) for p in pts], [0.1, 0.09, 0.07], BANDR, BANDR_D, segs=6))

# ---- lasso: goo hand raised on its left (viewer's right), rope up to a loop swung over the head
HC = Vector((1.75, -0.4, 1.95))
parts.append(goo("Hand", [((1.3, -0.25, 1.45), 0.3), ((1.55, -0.35, 1.72), 0.24), (tuple(HC), 0.22, (1.0, 1.0, 0.95))],
                 lambda p, n: mix(BLUE_D, BLUE, smoothstep(1.2, 2.0, p.z)), tris=140, resolution=0.08))
LC = Vector((1.55, -0.25, 3.95))
LN = Vector((0.3, -0.5, 1)).normalized()
LR = 0.8
q = LN.to_track_quat("Z", "Y")
near = LC + q @ Vector((math.cos(math.radians(-110)), math.sin(math.radians(-110)), 0)) * LR
parts.append(torus("RibbonLasso", LR, 0.075, tuple(LC), tuple(LN), lambda p, n: mix(ROPE_D, ROPE, 0.4 + 0.6 * smoothstep(-0.4, 0.6, n.dot(KEY))), segs=26, rsegs=5))
rope = [HC + Vector((0, 0, 0.15)), HC + Vector((0.15, -0.08, 0.7)), (HC + near) / 2 + Vector((0.2, -0.05, 0.1)), near]
parts.append(horn("Rope", [tuple(p) for p in rope], [0.075] * 4, ROPE_D, ROPE, segs=6))
parts.append(ball("Honda", 0.09, tuple(near), ROPE_D, subdiv=1))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_cowboy", parts)
