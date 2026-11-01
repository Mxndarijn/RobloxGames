# Diver (Legendary, Frost & Sea): deep-sea diver slime. The upper body is a bright brass diving
# helmet (one surface with the goo: no seam to flicker) with a big round front porthole where the
# aqua slime face shows through a light tinted window, a bolted rim, two small side portholes, a
# bolted collar where the goo bulges out below, an air valve on top and bubbles floating up. The
# face blows a bubble ("ooh") with wide wondering eyes.
from models._slimepool import *

AQ_D, AQ, AQ_L = hexc("1aa8e8"), hexc("3cd2ff"), hexc("b4f2ff")  # slime goo
BR_D, BR, BR_L = hexc("ffc850"), hexc("ffd862"), hexc("fff4b8")  # brass (stays above f2b440)
COP = hexc("ff9a5a")  # copper accents (valve wheel)
GLASS = hexc("d8f8ff")
BUB, BUB_L = hexc("c4f2ff"), hexc("f4feff")

ZC = 1.12  # collar height: goo below, helmet above
WZ, WR = 1.92, 0.84  # window centre height and radius (front projection)
KEY = Vector((-0.4, -0.6, 0.7)).normalized()


def in_window(a, z):
    """0..1 how far inside the front porthole (front projection, x ~ sin(a) * 1.5)."""
    if math.cos(a) <= 0.2:
        return 0.0
    x = math.sin(a) * 1.5
    d = math.hypot(x, z - WZ)
    return smoothstep(WR + 0.02, WR - 0.06, d)


def helmet_k(z):
    return smoothstep(ZC - 0.04, ZC + 0.04, z)


def bump(a, z):
    k = helmet_k(z)
    return 0.05 * k - 0.07 * in_window(a, z)


def paint(a, z, p):
    goo = mix(AQ_D, AQ, smoothstep(0.0, 0.9, z))
    brass = mix(mix(BR_D, BR, smoothstep(1.15, 1.7, z)), BR_L, 0.55 * smoothstep(2.0, 3.0, z))
    c = mix(goo, brass, helmet_k(z))
    w = in_window(a, z)
    if w > 0:
        win = mix(mix(AQ, AQ_L, 0.35), GLASS, 0.22 * smoothstep(1.4, 2.5, z))
        c = mix(c, win, w)
    return c


b = Body([(0, 1.1), (0.16, 1.4), (0.55, 1.52), (1.0, 1.5), (1.12, 1.38), (1.5, 1.42), (2.1, 1.36), (2.6, 1.05),
          (2.92, 0.55), (3.05, 0)], paint=paint, bump=bump, segs=40, sub=2, gloss=0.55)
parts = [b.obj]
H = b.H

brass_col = lambda p, n: mix(BR_D, mix(BR, BR_L, smoothstep(0.3, 0.9, n.dot(KEY))), smoothstep(-0.7, 0.1, n.dot(KEY)))

# ---- collar: chunky brass ring at the seam + bolts
cr = b.radius(ZC) * 1.05 + 0.04
parts.append(torus("Collar", cr, 0.11, (0, 0, ZC), (0, 0, 1), brass_col, segs=32, rsegs=6))
for k in range(8):
    a = math.radians(22.5 + k * 45)
    parts.append(ball(f"CollarBolt{k}", 0.075, (math.sin(a) * (cr + 0.09), -math.cos(a) * (cr + 0.09), ZC + 0.02), BR_L, subdiv=1))

# ---- front porthole rim: thick brass torus round the window, 8 bolts on its face
# the rim follows the helmet: a closed tube through the window outline cast onto the body
RR = WR + 0.05
ring = []
for k in range(28):
    t = k * math.tau / 28
    u, v = math.cos(t) * RR, WZ + math.sin(t) * RR
    loc, n, _ = cast(Vector((u, -12, v)), Vector((0, 1, 0)), ["Body"])
    ring.append(loc + Vector((0, -0.05, 0)))
parts.append(keep(tube("WinRim", ring + ring[:2], [0.12] * (len(ring) + 2), None, segs=7, twist_free=True), True))
paint_fn(parts[-1], brass_col)
for k in range(8):
    q = ring[int(k * 28 / 8 + 2) % 28] + Vector((0, -0.11, 0))
    parts.append(ball(f"RimBolt{k}", 0.055, tuple(q), BR_L, subdiv=1))
# window glint: two white streaks in the upper-left of the glass (behind the eyes)
fr = FRONT
parts.append(decal("Glint0", rect(-0.5, WZ + 0.38, 0.09, 0.32, math.radians(-40)), WHITE, fr, off=0.012, th=0.012, on=["Body"]))
parts.append(decal("Glint1", rect(-0.36, WZ + 0.5, 0.06, 0.18, math.radians(-40)), WHITE, fr, off=0.012, th=0.012, on=["Body"]))

# ---- side portholes (small, at the slime's left and right)
for sd in (-1, 1):
    a = math.radians(sd * 88)
    q = b.point(a, 1.95, 0.0)
    nrm = Vector((math.sin(a), -math.cos(a), 0))
    parts.append(decal(f"SideWin{sd}", oval(0, 0, 0.5, 0.5, n=16), lambda p, n: mix(AQ, GLASS, 0.45), frame_at(sd * 88, 1.95), off=0.01, th=0.015, on=["Body"]))
    parts.append(torus(f"SideRim{sd}", 0.28, 0.07, tuple(q + nrm * 0.03), tuple(nrm), brass_col, segs=14, rsegs=5))

# ---- top: air valve stem + copper handwheel, and a hose fitting at the back
top = Vector((0, 0.0, H))
parts.append(lathe("Valve", [(-0.1, 0.26), (0.12, 0.24), (0.2, 0.14), (0.42, 0.12), (0.46, 0.0)], brass_col, pos=tuple(top), segs=12))
parts.append(torus("Wheel", 0.24, 0.05, (0, 0, H + 0.42), (0, -0.25, 1), lambda p, n: mix(shade(COP, 0.9), COP, smoothstep(-0.3, 0.6, n.dot(KEY))), segs=14, rsegs=5))
for k in range(3):
    a = k * math.tau / 3
    parts.append(tube(f"Spoke{k}", [(0, 0, H + 0.43), (math.cos(a) * 0.22, math.sin(a) * 0.22 - 0.0, H + 0.42 + 0.055 * math.sin(a) * 0)], [0.03, 0.03], COP, segs=4))
parts.append(ball("WheelHub", 0.07, (0, 0, H + 0.45), BR_L, subdiv=1))
# hose fitting on the back with a short hose curling down
hb = b.point(math.pi, 2.3, 0.0)
parts.append(lathe("HoseNut", [(0, 0.17), (0.16, 0.17), (0.18, 0.11), (0.3, 0.11)], brass_col, pos=tuple(hb - Vector((0, 0.05, 0))), axis=(0, 1, 0.2), segs=10))
hose = [hb + Vector((0, 0.28, 0.06)), hb + Vector((0, 0.55, -0.1)), hb + Vector((0, 0.7, -0.5)), hb + Vector((0, 0.62, -0.95))]
hose = [Vector((0, y, z)) for y, z in catmull([(q.y, q.z) for q in hose], 3)]
parts.append(keep(tube("Hose", hose, [0.09] * len(hose), hexc("aab6d0"), segs=8, twist_free=True), True))
for k, t in enumerate((0.4, 0.75)):
    i = int(t * (len(hose) - 1))
    d = (hose[i + 1] - hose[i - 1]).normalized()
    parts.append(torus(f"HoseRib{k}", 0.09, 0.025, tuple(hose[i]), tuple(d), hexc("b8c2d8"), segs=8, rsegs=4))

# ---- face inside the window: wide wondering eyes, an "ooh" mouth blowing a bubble
f = Face(b, eye_v=2.08, eye_u=0.36, mouth_v=1.52)
f.eyes("round", w=0.4, h=0.54, iris=hexc("2a6cff"))
f.mouth("ooh", w=1.1)
f.cheeks(color=hexc("ff8fb0"), u=0.6, v=1.66, w=0.22, h=0.11)
parts += f.parts

# ---- bubbles floating up from the valve and the mouth side
bk = Vector((-0.4, -0.7, 0.6)).normalized()
for k, (x, y, z, r) in enumerate([(0.32, -0.15, H + 0.85, 0.15), (0.62, -0.05, H + 1.3, 0.2), (0.44, 0.0, H + 1.82, 0.13),
                                  (-1.25, -0.9, 2.55, 0.13), (-1.5, -0.75, 3.0, 0.09)]):
    c = Vector((x, y, z))
    parts.append(ball(f"Bubble{k}", r, c, lambda p, n: mix(BUB, BUB_L, 0.4 + 0.6 * max(0.0, n.dot(bk))), subdiv=2))
    parts.append(ball(f"BubbleHi{k}", r * 0.3, c + bk * r * 0.8, WHITE, subdiv=1))

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_diver", parts)
