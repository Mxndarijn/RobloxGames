# Reef (Secret, Frost & Sea): a living coral reef slime. Bright lagoon-turquoise goo with glowing
# polyp dots, crowned with a whole little reef: hot-pink staghorn coral with glowing tips, an
# orange brain coral, a purple sea fan behind, a lime anemone with pink glowing tips and a striped
# shell; four tiny tropical fish (clownfish, blue tang, yellow tang, pink anthias) swim round it
# on a tilted orbit with glowing bubbles. Content, dreamy face with glowing pink eyes.
from models._slimepool import *

TQ_D, TQ, TQ_L = hexc("34dcd8"), hexc("5cf6e8"), hexc("c0fff6")
GLOW_P, GLOW_Y, GLOW_C = hexc("ff7ae0"), hexc("fff27a"), hexc("8afcff")
PINK_D, PINK, PINK_L = hexc("ff5a9e"), hexc("ff80b8"), hexc("ffdcf2")
OR_D, OR, OR_L = hexc("ffac50"), hexc("ffc05a"), hexc("ffeaa8")
PUR_D, PUR, PUR_L = hexc("b070ff"), hexc("cc9cff"), hexc("f2dcff")
LIME_D, LIME = hexc("8cf060"), hexc("c4ff7c")
KEY = Vector((-0.4, -0.6, 0.7)).normalized()


def paint(a, z, p):
    c = mix(TQ_D, TQ, smoothstep(0.0, 1.3, z))
    c = mix(c, TQ_L, 0.35 * smoothstep(1.8, 2.8, z))
    # light caustic ripples on the upper body (sunlight through water), faded off the face
    w = math.sin(a * 6 + 1.8 * math.sin(z * 3.1)) + math.sin(z * 7.5 - 1.6 * math.sin(a * 4))
    face = smoothstep(0.75, 0.35, abs(a)) * smoothstep(0.6, 1.0, z) * smoothstep(2.3, 1.9, z)
    c = mix(c, TQ_L, 0.55 * smoothstep(1.35, 1.75, w) * smoothstep(0.5, 1.2, z) * (1 - face))
    return mix(c, GLOW_C, 0.6 * smoothstep(0.3, 0.0, z))  # glowing foot


b = Body([(0, 1.12), (0.15, 1.42), (0.55, 1.55), (1.15, 1.5), (1.8, 1.26), (2.35, 0.86), (2.7, 0.38), (2.8, 0)],
         paint=paint, segs=40, sub=2, gloss=0.6)
parts = [b.obj]
H = b.H


def lit_col(c0, c1, c2):
    return lambda p, n: mix(c0, mix(c1, c2, smoothstep(0.3, 0.95, n.dot(KEY))), smoothstep(-0.6, 0.2, n.dot(KEY)))


# ---- glowing polyp dots round the sides and back (two glow colours), clear of the face
spec_p, spec_y = [], []
for k in range(14):
    yaw = 62 + k * 17.5
    z = 0.7 + 0.55 * ((k * 0.618) % 1.0) + (0.5 if k % 3 == 0 else 0.0)
    (spec_p if k % 2 else spec_y).append((yaw if yaw <= 180 else yaw - 360, z, 0.21 - 0.04 * (k % 3)))
parts += spots(b, spec_p, GLOW_P, n=8)
parts += [o for o in spots(b, spec_y, GLOW_Y, n=8)]
for o in parts[-len(spec_y):]:
    o.name = "Polyp" + o.name

# ---- staghorn coral (hot pink, glowing tips): branching tubes from the top-left
def branch(name, pts, r0, r1):
    return horn(name, pts, [r0 + (r1 - r0) * i / (len(pts) - 1) for i in range(len(pts))], PINK_D, PINK, segs=6)


stag = [
    [(-0.35, 0.05, H - 0.2), (-0.45, 0.0, H + 0.35), (-0.62, -0.05, H + 0.85), (-0.7, -0.08, H + 1.25)],
    [(-0.45, 0.0, H + 0.3), (-0.85, 0.0, H + 0.6), (-1.0, -0.02, H + 0.9)],
    [(-0.6, -0.05, H + 0.8), (-0.35, -0.1, H + 1.05), (-0.25, -0.12, H + 1.25)],
    [(-0.55, 0.25, H - 0.35), (-0.95, 0.35, H + 0.05), (-1.15, 0.4, H + 0.4)],
    [(-0.95, 0.35, H + 0.02), (-1.0, 0.55, H + 0.32)],
]
for k, pts in enumerate(stag):
    parts.append(branch(f"Coral{k}", pts, 0.13 if k in (0, 3) else 0.1, 0.07))
    parts.append(ball(f"CoralTip{k}", 0.09, pts[-1], lit_col(GLOW_P, PINK_L, WHITE), subdiv=1))

# ---- brain coral: orange dome with wavy grooves, top-right
BC = Vector((0.55, -0.05, H - 0.32))


def brain_col(p, n):
    q = p - BC
    w = math.sin(q.x * 13 + 2.4 * math.sin(q.y * 9) + 1.6 * math.sin(q.z * 8))
    c = mix(hexc("ff7030"), OR_L, smoothstep(-0.1, 0.5, w))
    return mix(c, WHITE, 0.25 * smoothstep(0.5, 0.95, n.dot(KEY)))


parts.append(ball("Brain", 0.5, BC, brain_col, squash=(1, 1, 0.78), subdiv=3))

# ---- sea fan: purple lacy fan behind the top, lighter rim, dark ribs
fan = []
for k in range(15):
    t = k / 14
    a = math.radians(-70 + 140 * t)
    r = 1.15 + 0.12 * math.sin(k * 2.1)
    fan.append((math.sin(a) * r, math.cos(a) * r))
fan = [(0.12, 0.0)] + fan + [(-0.12, 0.0)]
FO = Vector((0.1, 0.55, H - 0.45))
FX, FY = Vector((1, 0.15, 0)).normalized(), Vector((0, 0.3, 1)).normalized()
parts.append(puffy_slab("SeaFan", fan, 0.08, FO, FX, FY,
                        lambda p, n: mix(PUR_D, mix(PUR, PUR_L, smoothstep(0.85, 1.2, (p - FO).length)), smoothstep(0.1, 0.6, (p - FO).length)), rows=2))
for k, a in enumerate((-45, -15, 15, 45)):
    d = FX * math.sin(math.radians(a)) + FY * math.cos(math.radians(a))
    parts.append(tube(f"FanRib{k}", [FO - FX.cross(FY) * 0.06, FO + d * 1.0 - FX.cross(FY) * 0.06], [0.035, 0.02], PUR_D, segs=4))

# ---- anemone on the right shoulder: lime stalk ring + short tentacles with pink glow tips
AC = b.point(math.radians(70), 2.0, -0.05)
up = (AC - Vector((0, 0, 1.2))).normalized()
parts.append(lathe("Anemone", [(0, 0.24), (0.18, 0.21), (0.26, 0.24)], LIME_D, pos=AC, axis=up, segs=10))
q = up.to_track_quat("Z", "Y")
for k in range(9):
    a = k * math.tau / 9
    base = AC + q @ Vector((math.cos(a) * 0.16, math.sin(a) * 0.16, 0.24))
    out = q @ Vector((math.cos(a), math.sin(a), 0))
    pts = [base, base + up * 0.18 + out * 0.08, base + up * 0.32 + out * 0.2]
    parts.append(horn(f"Anem{k}", [tuple(x) for x in pts], [0.05, 0.04, 0.03], LIME, LIME, segs=5))
    parts.append(ball(f"AnemTip{k}", 0.045, tuple(pts[-1]), GLOW_P, subdiv=1))

# ---- striped scallop shell low on the left front
sp = b.point(math.radians(-58), 0.62, 0.02)
sn = Vector((math.sin(math.radians(-58)), -math.cos(math.radians(-58)), 0.25)).normalized()
shell = []
for k in range(13):
    a = math.radians(-75 + 150 * k / 12)
    r = 0.3 * (1 + 0.08 * (k % 2))
    shell.append((math.sin(a) * r, math.cos(a) * r))
shell = [(0, -0.05)] + shell
SX = Vector((0, 0, 1)).cross(sn).normalized()
SY = sn.cross(SX).normalized()
parts.append(puffy_slab("Shell", shell, 0.08, sp, SX, SY,
                        lambda p, n: mix(hexc("ffc4d8"), hexc("ffffff"), 0.5 + 0.5 * math.sin(math.atan2((p - sp).dot(SX), (p - sp).dot(SY)) * 12)), rows=2))

# ---- tiny fish on a tilted orbit round the body
def fish(name, kind, M):
    out = []
    if kind == "clown":
        def col(p, n):
            x = p.x
            c = OR if not (abs(x - 0.08) < 0.045 or abs(x + 0.12) < 0.04) else WHITE
            return mix(c, OR_D, 0.15 * smoothstep(0.0, -0.8, n.z))
        fin_c, tail_c = OR_D, OR
    elif kind == "tang":
        col = lit_col(hexc("4a90ff"), hexc("62acff"), hexc("b8dcff"))
        fin_c, tail_c = hexc("2a5cd8"), hexc("ffe03a")
    elif kind == "yellow":
        col = lit_col(hexc("ffe050"), hexc("ffec6a"), hexc("fff8c0"))
        fin_c, tail_c = hexc("ffc21a"), hexc("ffd23a")
    else:
        col = lit_col(hexc("ff6ab4"), hexc("ff8cc8"), hexc("ffd4ec"))
        fin_c, tail_c = hexc("ffd23a"), hexc("ff6ab4")
    sq = (1.0, 0.55, 0.8) if kind != "yellow" else (0.85, 0.45, 0.95)
    out.append(ball(name, 0.22, (0, 0, 0), col, squash=sq, subdiv=2))
    tail = [(0, 0), (-0.2, 0.15), (-0.16, 0), (-0.2, -0.15)]
    out.append(slab(name + "Tail", tail, 0.04, (-0.17, 0, 0), (1, 0, 0), (0, 0, 1), tail_c))
    out.append(slab(name + "Dorsal", [(-0.12, 0), (0.06, 0), (-0.08, 0.12)], 0.03, (0, 0, 0.14 * sq[2] / 0.8), (1, 0, 0), (0, 0, 1), fin_c))
    for sd in (-1, 1):
        out.append(ball(name + f"EyeW{sd}", 0.05, (0.13, sd * 0.085, 0.03), WHITE, subdiv=1))
        out.append(ball(name + f"EyeP{sd}", 0.03, (0.155, sd * 0.11, 0.035), INK, subdiv=1))
    for o in out:
        o.data.transform(M)
    return out


ORB_C, ORB_R = Vector((0, 0.1, 1.5)), 2.45
ON = Vector((0.18, -0.12, 1)).normalized()
OU = Vector((1, 0, 0)); OU = (OU - ON * OU.dot(ON)).normalized()
OV = ON.cross(OU)
for k, (deg, kind, dz) in enumerate(((-55, "clown", 0.15), (52, "tang", 0.35), (128, "yellow", 0.05), (232, "pink", -0.25))):
    a = math.radians(deg)
    pos = ORB_C + (OU * math.cos(a) + OV * math.sin(a)) * ORB_R + Vector((0, 0, dz))
    fwd = (-OU * math.sin(a) + OV * math.cos(a)).normalized()  # swimming round counter-clockwise
    side = ON.cross(fwd).normalized()
    upv = fwd.cross(side)
    M = Matrix((fwd.to_4d(), side.to_4d(), upv.to_4d(), (0, 0, 0, 1))).transposed()
    M[0][3], M[1][3], M[2][3] = pos.x, pos.y, pos.z
    s = 1.6 if kind != "clown" else 1.75
    parts += fish(f"Fish{k}", kind, M @ Matrix.Scale(s, 4))

# ---- glowing bubbles
bk = Vector((-0.4, -0.7, 0.6)).normalized()
for k, (x, y, z, r) in enumerate([(-1.55, -0.55, 3.25, 0.13), (-1.35, -0.35, 3.7, 0.09), (1.5, 0.2, 3.35, 0.12),
                                  (0.9, -0.9, 3.55, 0.1)]):
    c = Vector((x, y, z))
    parts.append(ball(f"Bubble{k}", r, c, lambda p, n: mix(GLOW_C, WHITE, 0.3 + 0.7 * max(0.0, n.dot(bk))), subdiv=2))

# ---- face: glowing pink eyes, content cat mouth, cheeks
f = Face(b, eye_v=1.52, eye_u=0.5, mouth_v=1.08)
f.eyes("big", w=0.42, h=0.54, iris=hexc("ff5ad2"))
f.mouth("cat", w=1.1)
f.cheeks(color=hexc("ff8ac4"), w=0.28, h=0.13)
parts += f.parts

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_reef", parts)
