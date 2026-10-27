# Elder Oak (Mythic, Garden family): an ancient tree-spirit slime. Ridged bark-brown goo grading into a
# mossy green crown, gnarled branches growing up and out with leaf-puff clusters (a small canopy), a
# tiny owl on one branch, root flares at the foot, glowing amber eyes over a long moss beard, and
# glowing leaves floating around it.
from models._slimepool import *

BARK_D, BARK, BARK_L = hexc("7c4e2e"), hexc("aa7040"), hexc("c48e56")
MOSS_D, MOSS, MOSS_L = hexc("3f8f34"), hexc("62b844"), hexc("9ade62")
LEAF_D, LEAF, LEAF_L = hexc("2f8a3a"), hexc("4cb84a"), hexc("a6e86a")
AMBER, AMBER_L = hexc("ffa21a"), hexc("ffe27a")
GLOW, GLOW_L = hexc("b8f23a"), hexc("f4ffa8")
OWL, OWL_L, OWL_B = hexc("b07a48"), hexc("dcae78"), hexc("fff0cc")

NR = 14  # bark ridges round the body


def groove(a, z):
    """0 on a ridge, 1 in a groove; fades out where the moss starts."""
    g = 1 - abs(math.cos(NR * a / 2 + 0.6 * math.sin(z * 2.2))) ** 0.45
    return g * (1 - smoothstep(1.7, 2.3, z))


def moss_line(a, p):
    # wavy moss edge, dripping lower at a few places
    n = noise.noise(Vector((math.cos(a) * 1.6, math.sin(a) * 1.6, 3.3)))
    return 2.05 + 0.35 * n


def paint(a, z, p):
    c = mix(BARK_D, BARK, smoothstep(0.1, 1.2, z))
    c = mix(c, BARK_D, 0.75 * groove(a, z))
    m = smoothstep(-0.12, 0.12, z - moss_line(a, p))
    return mix(c, mix(MOSS, MOSS_L, smoothstep(2.2, 3.0, z)), m)


H = 3.0
b = Body([(0, 1.1), (0.12, 1.36), (0.5, 1.52), (1.1, 1.48), (1.8, 1.26), (2.45, 0.86), (2.85, 0.4), (H, 0)],
         paint=paint, segs=42, sub=2, gloss=0.35, bump=lambda a, z: -0.045 * groove(a, z))
parts = [b.obj]

# ---- roots: flared tubes from the lower body down to the ground
for k, (yaw, L) in enumerate(((35, 0.75), (100, 0.6), (165, 0.7), (-140, 0.65), (-75, 0.7), (-20, 0.55))):
    a = math.radians(yaw)
    o = Vector((math.sin(a), -math.cos(a), 0))
    p0 = b.point(a, 0.55, -0.25)
    pts = [tuple(p0), tuple(Vector((p0.x, p0.y, 0.3)) + o * 0.35), tuple(Vector((p0.x, p0.y, 0.1)) + o * (0.35 + L * 0.6)),
           tuple(Vector((p0.x, p0.y, 0.06)) + o * (0.35 + L))]
    parts.append(horn(f"Root{k}", pts, [0.3, 0.24, 0.14, 0.06], BARK_D, BARK, segs=7, smooth=False))


# ---- gnarled branches from the crown, each with a leaf cluster
def leafy(name, centre, r, seed):
    """leaf cluster: overlapping round puffs (big core + uneven rim puffs + a top puff), each with
    a dark-underside -> light-top gradient, so the lumps read separately."""
    rng_ = __import__("random").Random(seed)
    C = Vector(centre)
    specs = [(C, r * 0.85)]
    n = 4 if r > 0.4 else 3
    for k in range(n):
        a = k * math.tau / n + rng_.uniform(-0.35, 0.35)
        q = C + Vector((math.cos(a) * r * 0.75, math.sin(a) * r * 0.75, rng_.uniform(-0.2, 0.2) * r))
        specs.append((q, r * rng_.uniform(0.55, 0.7)))
    specs.append((C + Vector((rng_.uniform(-0.2, 0.2) * r, rng_.uniform(-0.2, 0.2) * r, r * 0.6)), r * 0.6))
    out = []
    for k, (q, rr) in enumerate(specs):
        def fn(p, n, q=q, rr=rr):
            c = mix(LEAF_D, LEAF, smoothstep(q.z - rr, q.z + 0.1 * rr, p.z))
            return mix(c, LEAF_L, smoothstep(q.z + 0.2 * rr, q.z + rr, p.z))
        out.append(ball(f"{name}_{k}", rr, tuple(q), fn, subdiv=2))
    return out


branches = [  # path points, radii, leaf cluster (centre, radius)
    ([(-0.3, 0.05, 2.7), (-0.75, 0.0, 3.1), (-1.15, -0.05, 3.3), (-1.45, 0.05, 3.6), (-1.6, 0.1, 3.85)],
     [0.26, 0.2, 0.16, 0.13, 0.1], ((-1.7, 0.15, 4.0), 0.5)),
    ([(0.3, 0.1, 2.72), (0.7, 0.2, 3.15), (0.95, 0.15, 3.55), (1.3, 0.3, 3.8), (1.5, 0.35, 4.1)],
     [0.26, 0.2, 0.16, 0.12, 0.1], ((1.55, 0.4, 4.3), 0.55)),
    ([(0.0, 0.35, 2.75), (0.05, 0.75, 3.3), (-0.15, 1.0, 3.75), (-0.1, 1.2, 4.15)],
     [0.24, 0.18, 0.14, 0.1], ((-0.1, 1.25, 4.45), 0.52)),
    ([(0.05, -0.15, 2.85), (0.2, -0.25, 3.3), (0.15, -0.2, 3.6)],
     [0.18, 0.13, 0.09], ((0.15, -0.15, 3.82), 0.36)),
]
for k, (pts, radii, (lc, lr)) in enumerate(branches):
    parts.append(horn(f"Branch{k}", pts, radii, BARK, BARK_L, segs=7, smooth=False))
    parts += leafy(f"Leaves{k}", lc, lr, 11 + k)
# a short twig with a small cluster off the left branch, under the owl
parts.append(horn("Twig", [(-1.15, -0.05, 3.3), (-1.55, -0.3, 3.25), (-1.9, -0.45, 3.4)], [0.1, 0.08, 0.06], BARK, BARK_L, segs=6, smooth=False))
parts += leafy("LeavesTwig", (-2.1, -0.5, 3.48), 0.32, 99)

# ---- tiny owl sitting on the left branch, looking forward
OC = Vector((-1.05, -0.12, 3.62))
parts.append(ball("Owl", 0.36, tuple(OC), lambda p, n: mix(OWL, OWL_L, smoothstep(OC.z - 0.3, OC.z + 0.35, p.z)), squash=(1, 0.9, 1.2), subdiv=2))
parts.append(ball("OwlBelly", 0.2, tuple(OC + Vector((0, -0.17, -0.08))), OWL_B, squash=(1, 0.6, 1.15), subdiv=2))
for sd in (-1, 1):
    ec = OC + Vector((sd * 0.14, -0.27, 0.12))
    parts.append(ball(f"OwlEyeW{sd}", 0.125, tuple(ec), WHITE, squash=(1, 0.5, 1), subdiv=1))
    parts.append(ball(f"OwlEye{sd}", 0.07, tuple(ec + Vector((0, -0.04, 0))), INK, squash=(1, 0.5, 1), subdiv=1))
    parts.append(lathe(f"OwlTuft{sd}", [(0, 0.08), (0.18, 0)], OWL, pos=tuple(OC + Vector((sd * 0.19, 0, 0.34))), axis=(sd * 0.45, 0, 1), segs=5, smooth=False))
    parts.append(ball(f"OwlWing{sd}", 0.16, tuple(OC + Vector((sd * 0.3, 0.02, -0.05))), OWL, squash=(0.5, 0.9, 1.3), subdiv=1))
parts.append(lathe("OwlBeak", [(0, 0.05), (0.1, 0)], GOLD, pos=tuple(OC + Vector((0, -0.32, 0.0))), axis=(0, -1, -0.5), segs=5, smooth=False))

# ---- face: glowing amber eyes under bark brows, long moss beard with a mustache
EV = 1.7
f = Face(b, eye_v=EV, eye_u=0.48)
for sd in (-1, 1):
    u = sd * 0.48
    eye = oval(u, EV, 0.5, 0.48, n=16)
    eye = [(x, min(y, EV + 0.12 - (x - u) * 0.25 * sd)) for x, y in eye]
    f.d(f"Eye{sd}", eye, INK, off=0.015)
    glow = oval(u, EV - 0.02, 0.42, 0.38, n=14)
    glow = [(x, min(y, EV + 0.08 - (x - u) * 0.25 * sd)) for x, y in glow]
    f.d(f"EyeGlow{sd}", glow, lambda p, n: mix(AMBER, AMBER_L, smoothstep(EV - 0.15, EV + 0.08, p.z)), off=0.03, th=0.01)
    f.d(f"Pupil{sd}", oval(u, EV - 0.04, 0.12, 0.15, n=10), hexc("5a2a08"), off=0.042, th=0.008)
    f.d(f"EyeHi{sd}", oval(u - 0.08, EV + 0.0, 0.07, 0.07, n=8), WHITE, off=0.052, th=0.008)
    f.d(f"Brow{sd}", rect(u + sd * 0.02, EV + 0.32, 0.5, 0.13, math.radians(-12 * sd)), BARK_D, off=0.03, th=0.04)
parts += f.parts

beard = []
for sd in (-1, 1):  # mustache lobes, then a side strand per side
    beard += [((sd * 0.26, -1.5, 1.33), 0.27, (1.3, 0.75, 0.7)), ((sd * 0.58, -1.38, 1.24), 0.23, (1.1, 0.8, 0.8)),
              ((sd * 0.5, -1.46, 0.9), 0.3, (0.95, 0.8, 1.1)), ((sd * 0.42, -1.55, 0.5), 0.26, (0.95, 0.8, 1.2)),
              ((sd * 0.36, -1.58, 0.2), 0.18, (1, 0.85, 1.1))]
beard += [((0, -1.6, 0.98), 0.34, (1, 0.8, 1.05)), ((0, -1.7, 0.56), 0.3, (1, 0.8, 1.2)), ((0, -1.76, 0.18), 0.22, (1, 0.9, 1.2))]
BB = [(Vector(q[0]), q[1] * 0.574 * max(q[2])) for q in beard]


def beard_col(p, n):
    c = mix(MOSS, hexc("c4f088"), smoothstep(0.1, 1.45, p.z))
    d = min((p - q).length / r for q, r in BB)
    return mix(c, MOSS_D, 0.8 * smoothstep(1.1, 1.5, d))


parts.append(goo("Beard", beard, beard_col, tris=520, resolution=0.09))

# ---- glowing leaves floating round it
leaf = [(0, 0), (0.12, 0.1), (0.3, 0.13), (0.48, 0.08), (0.6, 0), (0.48, -0.08), (0.3, -0.13), (0.12, -0.1)]
for k in range(6):
    a = k * math.tau / 6
    R = 2.2 + 0.15 * math.sin(k * 2.3)
    p = Vector((math.cos(a) * R, math.sin(a) * R * 0.85, 1.1 + 0.6 * math.sin(a * 2 + 0.5) + 0.25 * (k % 2)))
    d = Vector((-math.sin(a), math.cos(a), 0.45)).normalized()
    side = Vector((0, 0, 1)).cross(d).normalized()
    sc = 1.9 + 0.25 * math.cos(k)
    poly = [(x * sc, y * sc * 1.25) for x, y in leaf]
    parts.append(puffy_slab(f"GlowLeaf{k}", poly, 0.07, tuple(p), tuple(d), tuple(side),
                            along(GLOW, GLOW_L, p, p + d * 0.7), rows=2))

ship("slime_elder_oak", parts)
