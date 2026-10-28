# Captain Goo (Legendary, Frost & Sea): pirate slime. Sea-teal goo with a black tricorn hat (gold
# trim, white skull and crossbones), an eye patch, a cocky one-eyed squint with a gold tooth grin,
# a gold hoop earring, a red/white striped sash with a knot, and a little red parrot on its shoulder.
from models._slimepool import *

SEA, SEA_D, SEA_L = hexc("22d0b4"), hexc("0c8a86"), hexc("a6f7e2")
HAT, HAT_D, HAT_L = hexc("2e2a3c"), hexc("16131e"), hexc("4a4460")
BONE, BONE_D = hexc("fffaf0"), hexc("d8d2c4")
SASH_R, SASH_W = hexc("e8283c"), hexc("fff4ec")
P_RED, P_RED_D = hexc("ff3030"), hexc("b8141e")
P_BLUE, P_YEL, P_GRN = hexc("2f7bff"), hexc("ffd23a"), hexc("3ad06a")
BEAK, BEAK_D = hexc("fff0c8"), hexc("3a3040")

ZS0, ZS1 = 0.32, 0.74  # sash band on the body


def paint(a, z, p):
    c = mix(SEA_D, SEA, smoothstep(0.0, 1.3, z))
    return mix(c, SEA_L, 0.4 * smoothstep(1.7, 2.7, z))


def sash(a, z):
    if not (ZS0 <= z <= ZS1):
        return None
    k = int(math.floor(a / math.tau * 22 + 0.5))
    return SASH_R if k % 2 == 0 else SASH_W


b = Body([(0, 1.1), (0.14, 1.36), (0.5, 1.5), (1.1, 1.48), (1.8, 1.28), (2.4, 0.95), (2.78, 0.5), (2.9, 0)],
         paint=paint, segs=36, sub=2, bands=[(ZS0, ZS1, SASH_R)], sectors=sash)
parts = [b.obj]
H = b.H


def shell(name, fn, nu, nv, thick, color):
    """closed thick sheet: fn(s, t) -> point (s, t in 0..1); offset along the sheet normal both ways."""
    bm = bmesh.new()
    P = [[Vector(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]

    def nrm(i, j):
        a = P[min(i + 1, nu)][j] - P[max(i - 1, 0)][j]
        b = P[i][min(j + 1, nv)] - P[i][max(j - 1, 0)]
        return a.cross(b).normalized()
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


KEY = Vector((-0.4, -0.6, 0.7)).normalized()
hat_col = lambda p, n: mix(HAT_D, mix(HAT, HAT_L, smoothstep(0.4, 0.9, n.dot(KEY))), smoothstep(-0.6, 0.2, n.dot(KEY)))

# ---- tricorn: crown dome + three upturned brim sides meeting in points (one at the front)
ZB = 2.3
RC = b.radius(ZB) + 0.06
crown = lathe("Crown", [(ZB - 0.15, RC), (ZB + 0.25, RC * 0.99), (ZB + 0.6, RC * 0.92), (ZB + 0.92, RC * 0.62), (ZB + 1.0, 0)],
              hat_col, segs=28, sub=2)
parts.append(register(crown, "Crown"))


def brim_fn(k):
    a0 = math.radians(k * 120)

    def fn(s, t):
        a = a0 + math.radians(120) * s
        c = abs(2 * s - 1)
        r_out = 1.4 + 0.5 * c ** 2
        h = 0.14 + 0.78 * (1 - c ** 2)
        r = RC * 0.97 + (r_out - RC * 0.97) * math.sqrt(t)
        z = ZB - 0.05 + h * t ** 2
        return (math.sin(a) * r, -math.cos(a) * r, z)
    return fn


for k in range(3):
    fn = brim_fn(k)
    parts.append(shell(f"Brim{k}", fn, 12, 4, 0.08, hat_col))
    trim = [Vector(fn(i / 12, 1.0)) for i in range(13)]
    parts.append(horn(f"Trim{k}", [tuple(p) for p in trim], [0.06] * 13, GOLD, GOLD_L, segs=6))
for k in range(3):  # gold bead on each point
    p = Vector(brim_fn(k)(0, 1.0))
    parts.append(ball(f"Point{k}", 0.09, tuple(p), GOLD_L, subdiv=1))

# skull and crossbones on the crown front, above the front point
SV = ZB + 0.45
fr = frame_at(0, 0, tilt=0)
for sd in (-1, 1):
    bone = rect(0, SV, 0.62, 0.09, math.radians(32 * sd))
    parts.append(decal(f"Bone{sd}", bone, BONE, fr, off=0.01, th=0.03, on=["Crown"]))
    for e in (-1, 1):
        c = Vector((math.cos(math.radians(32 * sd)), math.sin(math.radians(32 * sd)))) * 0.31 * e
        for j in (-1, 1):
            q = c + Vector((-math.sin(math.radians(32 * sd)), math.cos(math.radians(32 * sd)))) * 0.04 * j
            parts.append(decal(f"BoneEnd{sd}{e}{j}", oval(q.x, SV + q.y, 0.09, 0.09, n=6), BONE, fr, off=0.01, th=0.03, on=["Crown"]))
parts.append(decal("Skull", oval(0, SV + 0.06, 0.3, 0.27, n=14), BONE, fr, off=0.04, th=0.03, on=["Crown"]))
parts.append(decal("Jaw", rect(0, SV - 0.09, 0.16, 0.1), BONE, fr, off=0.04, th=0.03, on=["Crown"]))
for sd in (-1, 1):
    parts.append(decal(f"SkullEye{sd}", oval(sd * 0.065, SV + 0.05, 0.08, 0.09, n=8), HAT_D, fr, off=0.075, th=0.01, on=["Crown"]))

# ---- face: eye patch on its right (viewer's left) with a strap, cocky squint, gold-tooth grin
f = Face(b, eye_v=1.6, eye_u=0.5, mouth_v=1.0)
f._eye_round(1, 0.48, 0.62, lid=0.3, tilt=-0.2, iris=hexc("2f7bff"))
patch = [(-0.5 + math.cos(a) * 0.26, 1.6 + math.sin(a) * 0.24 - (0.04 if math.sin(a) < 0 else 0)) for a in [k * math.tau / 14 for k in range(14)]]
f.d("Patch", patch, HAT_D, off=0.02, th=0.04)
f.d("Strap0", [(-0.68, 1.74), (-0.6, 1.8), (0.95, 2.2), (0.95, 2.1)], HAT_D, off=0.015, th=0.03)
f.d("Strap1", [(-0.72, 1.55), (-0.72, 1.64), (-1.18, 1.68), (-1.18, 1.6)], HAT_D, off=0.015, th=0.03)
f.d("Brow1", arc(0.5, 1.84, 0.24, 50, 130, 0.09, n=8), INK)  # after the strap: it crosses the brow's top
f.mouth("grin", w=0.95)
f.d("GoldTooth", rect(0.09, f.mv + 0.03, 0.1, 0.085), GOLD, off=0.06, th=0.01)
f.cheeks(color=hexc("ff8fb0"), w=0.24, h=0.11)
parts += f.parts

# ---- gold hoop earring on its left side (viewer's right)
ea = math.radians(78)
ep = b.point(ea, 1.32, 0.02)
tang = Vector((math.cos(ea), math.sin(ea), 0))
parts.append(ball("EarStud", 0.07, tuple(ep), GOLD))
parts.append(torus("Hoop", 0.22, 0.045, tuple(ep + Vector((0, 0, -0.2)) + Vector((math.sin(ea), -math.cos(ea), 0)) * 0.08), tuple(tang),
                   lambda p, n: mix(GOLD_D, GOLD_L, smoothstep(-0.4, 0.6, n.dot(KEY))), segs=16, rsegs=6))

# ---- sash knot + two tails on its left hip
ka = math.radians(62)
kp = b.point(ka, (ZS0 + ZS1) / 2, 0.06)
kd = Vector((math.sin(ka), -math.cos(ka), 0))
parts.append(ball("Knot", 0.17, tuple(kp), SASH_R, squash=(1, 1, 0.9)))
for j, (dx, L) in enumerate(((-0.12, 0.42), (0.14, 0.33))):
    side = Vector((math.cos(ka), math.sin(ka), 0))
    p0 = kp + kd * 0.05
    pts = [p0, p0 + kd * 0.12 + side * dx + Vector((0, 0, -0.2)), p0 + kd * 0.16 + side * dx * 1.6 + Vector((0, 0, -L))]
    parts.append(horn(f"SashTail{j}", [tuple(p) for p in pts], [0.11, 0.1, 0.08], SASH_R, SASH_W if j else SASH_R, segs=6))

# ---- parrot perched on top of the hat, facing front (scaled about its body centre)
S = 1.5
PC = Vector((0.12, 0.08, ZB + 1.0 + 0.3 * S))


def P(x, y, z):
    return PC + Vector((x, y, z)) * S


body_col = lambda p, n: mix(P_RED_D, P_RED, smoothstep(-0.5, 0.4, n.dot(KEY)))
parts.append(ball("ParrotBody", 0.3 * S, tuple(PC), body_col, squash=(0.85, 0.85, 1.15)))
HD = P(0, -0.08, 0.4)
parts.append(ball("ParrotHead", 0.22 * S, tuple(HD), body_col))
parts.append(ball("ParrotBelly", 0.2 * S, tuple(P(0, -0.12, -0.04)), P_YEL, squash=(0.8, 0.6, 1.1)))
parts.append(lathe("Beak", [(0, 0.1 * S), (0.12 * S, 0.07 * S), (0.22 * S, 0)], BEAK, pos=tuple(P(0, -0.17, -0.02) - PC + HD - Vector((0, 0, 0))), axis=(0, -0.7, -0.7), segs=8))
for sd in (-1, 1):
    ep_ = HD + Vector((sd * 0.13, -0.12, 0.06)) * S
    parts.append(ball(f"PEyeW{sd}", 0.07 * S, tuple(ep_), WHITE, subdiv=1))
    parts.append(ball(f"PEye{sd}", 0.04 * S, tuple(ep_ + Vector((sd * 0.01, -0.045, 0)) * S), INK, subdiv=1))
for sd in (-1, 1):  # wings: blue to green, folded on each side
    wp = [(0, 0), (0.12, 0.14), (0.42, 0.12), (0.62, 0.0), (0.4, -0.1), (0.1, -0.1)]
    wp = [(x * S, y * S) for x, y in wp]
    o = P(sd * 0.24, 0.02, 0.14)
    X = Vector((sd * 0.12, 0.35, -1)).normalized()
    Y = Vector((0, 1, 0.3)).cross(X).normalized()
    parts.append(puffy_slab(f"PWing{sd}", wp, 0.09, tuple(o), tuple(X), tuple(Y), along(P_BLUE, P_GRN, o, o + X * 0.6 * S), rows=1))
for j, (dx, L, c) in enumerate(((-0.07, 0.7, P_BLUE), (0.07, 0.62, P_YEL), (0.0, 0.8, P_RED))):  # tail down the back
    o = P(dx, 0.2, -0.2)
    X = Vector((dx * 2, 0.6, -1)).normalized()
    L *= S
    fp = [(0, 0), (L * 0.3, 0.08), (L, 0.05), (L * 1.04, 0), (L, -0.05), (L * 0.3, -0.08)]
    parts.append(puffy_slab(f"PTail{j}", fp, 0.06, tuple(o), tuple(X), (1, 0, 0), along(c, mix(c, WHITE, 0.3), o, o + X * L), rows=1))
for sd in (-1, 1):  # feet gripping the hat
    parts.append(ball(f"PFoot{sd}", 0.06 * S, tuple(P(sd * 0.1, -0.05, -0.32)), hexc("4a4050"), squash=(1, 1.6, 0.6), subdiv=1))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_captain_goo", parts)
