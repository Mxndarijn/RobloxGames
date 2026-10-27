# Goo Oracle (Divine, tier 9): a wise mystic slime. Royal purple foot -> violet -> white-gold crown
# with a faint starry shimmer, a gold circlet holding a glowing third-eye gem on the forehead, calm
# half-lidded knowing eyes and a small serene smile. Three floating layers: a flat circle of glowing
# rune tiles under it, two small orbs orbiting at mid height, and a crystal ball hovering over the
# crown in a gold cradle.
from models._slimepool import *

PURP_D, PURP, VIOLET = hexc("4a2a9e"), hexc("6a3cd0"), hexc("a77cf0")
PALE, CROWN = hexc("d9b8ff"), hexc("ffe9a8")
GOLD_W = hexc("fff4c8")
EYE_G, EYE_L = hexc("ff5ad8"), hexc("ffd6f8")
RUNE, RUNE_L = hexc("5ae8ff"), hexc("d8fbff")
ORB, ORB_L = hexc("8a7cff"), hexc("f0eaff")
INKP = hexc("2a1648")


def paint(a, z, p):
    c = mix(PURP_D, PURP, smoothstep(0.0, 0.9, z))
    c = mix(c, VIOLET, smoothstep(0.9, 1.9, z))
    c = mix(c, PALE, smoothstep(1.95, 2.45, z))
    c = mix(c, CROWN, smoothstep(2.45, 2.95, z))
    # starry shimmer low on the robe: tiny bright specks from noise
    n = noise.noise(Vector((p.x * 9.0, p.y * 9.0, p.z * 9.0 + 11.0)))
    c = mix(c, hexc("e8dcff"), 0.8 * smoothstep(0.5, 0.56, n) * smoothstep(1.6, 1.0, z))
    return c


H = 3.05
b = Body([(0, 1.05), (0.13, 1.38), (0.5, 1.54), (1.1, 1.5), (1.8, 1.25), (2.45, 0.86), (2.85, 0.4), (H, 0)],
         paint=paint, segs=48, sub=2, gloss=0.55, bands=[(0.12, 0.24, GOLD)])
parts = [b.obj]

# ---------------------------------------------------------------- gold circlet + third eye
CZ = 2.3
# tiara-like band hugging the head: dips to the gem at the front, sits higher at the back
cl = [b.point(math.radians(d), CZ - 0.08 * math.cos(math.radians(d)) + 0.12 * (1 - math.cos(math.radians(d))) / 2, 0.035) for d in range(-176, 180, 8)]
parts.append(horn("Circlet", cl, [0.065] * len(cl), GOLD, GOLD_L, segs=6))
gp = b.point(0, CZ - 0.06, 0.02)
gnrm = (b.point(0, CZ - 0.06, 1) - gp).normalized()
# almond setting + rays (decals), then the gem itself standing proud
EV3 = CZ - 0.02
parts.append(decal("EyeSet", [(-0.32, EV3), (-0.16, EV3 + 0.13), (0, EV3 + 0.17), (0.16, EV3 + 0.13), (0.32, EV3),
                               (0.16, EV3 - 0.13), (0, EV3 - 0.17), (-0.16, EV3 - 0.13)], GOLD, FRONT, off=0.02, th=0.03, on=["Body"]))
parts.append(gem("ThirdEye", tuple(gp + gnrm * 0.11), 0.19, EYE_G, h=0.24, segs=8, axis=tuple(gnrm)))
parts.append(ball("ThirdEyeHi", 0.04, tuple(gp + gnrm * 0.23 + Vector((-0.06, 0, 0.06))), WHITE, subdiv=1))
for k, ang in enumerate((40, 90, 140)):  # glowing rays above the setting
    r = math.radians(ang)
    parts.append(decal(f"EyeRay{k}", rect(math.cos(r) * 0.36, EV3 + math.sin(r) * 0.3, 0.17 if k != 1 else 0.2, 0.05, r), EYE_L, FRONT, off=0.02, th=0.02, on=["Body"]))

# ---------------------------------------------------------------- rune circle under it
RC = Vector((0, 0, 0.22))
RR = 2.15
parts.append(torus("RuneRing", RR, 0.06, tuple(RC), (0, 0, 1), GOLD, segs=48, rsegs=5))
parts.append(torus("RuneRingIn", RR - 0.42, 0.035, tuple(RC), (0, 0, 1), RUNE, segs=40, rsegs=4))
NR = 12
for k in range(NR):
    a = k * math.tau / NR + math.pi / NR
    rad = Vector((math.sin(a), -math.cos(a), 0))
    tng = Vector((math.cos(a), math.sin(a), 0))
    up = (Vector((0, 0, 1)) * 0.82 + rad * 0.57).normalized()  # standing tiles leaning outward
    c = RC + rad * (RR - 0.2) + up * 0.3
    nrm = tng.cross(up).normalized()
    parts.append(slab(f"RuneRim{k}", rect(0, 0, 0.46, 0.56), 0.05, tuple(c), tuple(tng), tuple(up), GOLD))
    parts.append(slab(f"Rune{k}", rect(0, 0, 0.36, 0.46), 0.05, tuple(c + nrm * 0.03), tuple(tng), tuple(up),
                      lambda p, n, c=c: mix(hexc("3a2280"), hexc("5a3cb0"), smoothstep(-0.25, 0.25, (p - c).z))))
    gl = [rect(0, 0, 0.06, 0.3), arc(0, -0.06, 0.13, 20, 160, 0.06, n=6), star(0, 0, 0.17, 0.06, n=3), oval(0, 0, 0.2, 0.2, n=8)][k % 4]
    parts.append(slab(f"Glyph{k}", gl, 0.02, tuple(c + nrm * 0.065), tuple(tng), tuple(up), RUNE_L if k % 2 else RUNE))
    if k % 4 == 3:  # ring glyph: hollow it with a dark dot
        parts.append(slab(f"GlyphDot{k}", oval(0, 0, 0.09, 0.09, n=8), 0.02, tuple(c + nrm * 0.08), tuple(tng), tuple(up), hexc("3a2280")))

# ---------------------------------------------------------------- two orbiting orbs
key = Vector((-0.35, -0.75, 0.55)).normalized()
for k, (yaw, z) in enumerate(((-118, 1.75), (62, 2.25))):
    a = math.radians(yaw)
    c = Vector((math.sin(a) * 2.1, -math.cos(a) * 2.1, z))
    parts.append(ball(f"Orb{k}", 0.24, tuple(c), lambda p, n: mix(ORB, ORB_L, 0.2 + 0.8 * max(0.0, n.dot(key)) ** 0.8), subdiv=2))
    parts.append(torus(f"OrbRing{k}", 0.34, 0.025, tuple(c), (0.3, -0.2, 1), GOLD, segs=16, rsegs=4))

# ---------------------------------------------------------------- crystal ball over the crown
BC = Vector((0, 0.05, H + 1.05))
parts.append(ball("CrystalBall", 0.55, tuple(BC), lambda p, n: mix(mix(hexc("9a8cff"), RUNE, 0.35 * smoothstep(0.2, -0.6, n.z)), hexc("f4f8ff"), 0.1 + 0.9 * max(0.0, n.dot(key)) ** 0.7), subdiv=3))
for k, (dx, dz, r) in enumerate(((-0.14, 0.12, 0.13), (0.12, -0.08, 0.09))):  # glints on the glass
    parts.append(slab(f"BallGlint{k}", star(0, 0, r, r * 0.3, n=4), 0.03, tuple(BC + Vector((dx, -0.54, dz))), (1, 0, 0), (0, 0, 1), WHITE))
parts.append(torus("Cradle", 0.38, 0.06, tuple(BC + Vector((0, 0, -0.42))), (0, 0, 1), lambda p, n: mix(GOLD_D, GOLD_L, 0.5 + 0.5 * n.z), segs=24, rsegs=6))
for k in range(3):
    a = k * math.tau / 3 + math.pi / 2
    r0 = Vector((math.cos(a) * 0.38, math.sin(a) * 0.38, -0.36))
    parts.append(horn(f"Prong{k}", [tuple(BC + r0), tuple(BC + r0 * 1.15 + Vector((0, 0, 0.22))), tuple(BC + r0 * 1.05 + Vector((0, 0, 0.42)))],
                      [0.05, 0.04, 0.02], GOLD, GOLD_L, segs=5))
parts.append(lathe("CradleTip", [(0, 0.08), (0.12, 0.04), (0.24, 0)], GOLD, pos=tuple(BC + Vector((0, 0, -0.48))), axis=(0, 0, -1), segs=8))

# gold stars scattered on the robe (sides and back)
st = []
for k, (yaw, z, r) in enumerate([(70, 0.9, 0.16), (100, 1.5, 0.11), (125, 0.7, 0.12), (150, 1.35, 0.15), (180, 0.85, 0.12), (205, 1.55, 0.11),
                                  (235, 0.8, 0.15), (260, 1.4, 0.12), (290, 0.95, 0.11), (-62, 0.65, 0.1), (60, 1.75, 0.09)]):
    parts.append(decal(f"RobeStar{k}", star(0, 0, r, r * 0.38, n=4 if k % 2 else 5), GOLD_L, frame_at(yaw, z), off=0.015, th=0.02, on=["Body"]))

# ---------------------------------------------------------------- calm knowing face
f = Face(b, eye_u=0.5, eye_v=1.6, mouth_v=1.18, ink=INKP)
for sd in (-1, 1):
    f._eye_round(sd, 0.46, 0.52, lid=0.42, tilt=0.0, iris=GOLD)
f.mouth("smile", w=0.85)
f.cheeks(color=hexc("ff9ad8"), w=0.28, h=0.13)
parts += f.parts

ship("slime_goo_oracle", parts)
