# Bonsai (Legendary, Garden): a calm little bonsai keeper. Jade goo sitting in a round terracotta
# bonsai pot on four feet, a twisted S-curve trunk growing from its crown with flat cloud pads of
# foliage, and a serene face (closed eyes, soft smile, blush).
from models._slimepool import *

JADE_D, JADE, JADE_L = hexc("5cdcb6"), hexc("7aeec8"), hexc("bff8e2")
POT_D, POT, POT_L = hexc("dc7a4c"), hexc("e8844e"), hexc("f8a870")
POT_RIM = hexc("b8552f")
TRUNK_D, TRUNK, TRUNK_L = hexc("a06a40"), hexc("a8703c"), hexc("c89058")
PAD_D, PAD, PAD_L = hexc("4cb444"), hexc("5cc44a"), hexc("aee868")
MOSS = hexc("8ed84a")
INKB = hexc("2a3a34")

RIM_Z = 1.08  # pot rim top


def paint(a, z, p):
    c = mix(JADE_D, JADE, smoothstep(0.9, 1.6, z))
    return mix(c, JADE_L, 0.55 * smoothstep(1.9, 2.75, z))


b = Body([(0.2, 0.9), (0.6, 1.3), (0.98, 1.4), (1.2, 1.56), (1.45, 1.5), (1.85, 1.3), (2.3, 0.96), (2.64, 0.5), (2.78, 0)],
         paint=paint, segs=32, sub=2, tuck=0.0)
parts = [b.obj]
H = b.H

# ---- pot: lathe with an outer wall, a rolled rim and an inner wall down to the goo
pot_prof = [(0.14, 0.0), (0.14, 1.18), (0.2, 1.3), (0.55, 1.42), (0.9, 1.5), (0.96, 1.6), (1.04, 1.64), (RIM_Z, 1.6),
            (RIM_Z, 1.44), (0.95, 1.38), (0.95, 0.0)]


def pot_col(p, n):
    c = mix(POT_D, POT, smoothstep(0.1, 0.8, p.z))
    c = mix(c, POT_L, 0.6 * smoothstep(0.2, 0.9, n.dot(Vector((-0.5, -0.6, 0.5)).normalized())))
    return mix(c, POT_RIM, smoothstep(0.92, 0.97, p.z) * (1 - smoothstep(1.02, 1.06, p.z)))


parts.append(lathe("Pot", pot_prof, pot_col, segs=36, smooth=True))
for k in range(4):
    a = math.radians(45 + 90 * k)
    parts.append(ball(f"PotFoot{k}", 0.2, (math.sin(a) * 1.0, -math.cos(a) * 1.0, 0.12), POT_D, squash=(1.2, 1.2, 0.7), subdiv=1))

# ---- bonsai: S-curve trunk from the crown, two branches, flat cloud pads
T0 = Vector((0, 0.15, H - 0.12))
trunk = [T0, T0 + Vector((0.3, 0.05, 0.32)), T0 + Vector((-0.1, 0.0, 0.7)), T0 + Vector((0.2, -0.05, 1.02)), T0 + Vector((0.05, -0.05, 1.32))]
parts.append(horn("Trunk", [tuple(p) for p in trunk], [0.44, 0.3, 0.23, 0.17, 0.11], TRUNK_D, TRUNK_L, segs=8, smooth=False))
# root flare + moss mound where the trunk meets the goo
for k in range(4):
    a = math.radians(30 + 90 * k)
    d = Vector((math.sin(a), -math.cos(a), 0))
    p0 = T0 + Vector((0, 0, 0.12))
    parts.append(horn(f"Root{k}", [tuple(p0), tuple(p0 + d * 0.38 + Vector((0, 0, -0.12))), tuple(p0 + d * 0.62 + Vector((0, 0, -0.3)))],
                      [0.16, 0.1, 0.04], TRUNK_D, TRUNK, segs=5, smooth=False))
parts.append(ball("Moss", 0.5, tuple(T0 + Vector((0, 0, -0.06))), lambda p, n: mix(PAD, MOSS, smoothstep(T0.z - 0.1, T0.z + 0.12, p.z)), squash=(1.25, 1.2, 0.36), subdiv=2))
br_l = [trunk[2], trunk[2] + Vector((-0.45, -0.05, 0.08)), trunk[2] + Vector((-0.95, -0.12, 0.22))]
br_r = [trunk[3], trunk[3] + Vector((0.4, 0.05, 0.05)), trunk[3] + Vector((0.85, 0.1, 0.15))]
parts.append(horn("BranchL", [tuple(p) for p in br_l], [0.13, 0.1, 0.07], TRUNK, TRUNK_L, segs=6, smooth=False))
parts.append(horn("BranchR", [tuple(p) for p in br_r], [0.12, 0.09, 0.06], TRUNK, TRUNK_L, segs=6, smooth=False))


def pad(name, centre, w, seed):
    """flat-topped cloud pad: a wide squashed core + uneven rim puffs, dark under, light top."""
    rng_ = __import__("random").Random(seed)
    C = Vector(centre)
    specs = [(C, w * 0.5, (1.25, 1.1, 0.5))]
    n = 5
    for k in range(n):
        a = k * math.tau / n + rng_.uniform(-0.3, 0.3)
        q = C + Vector((math.cos(a) * w * 0.48, math.sin(a) * w * 0.36, rng_.uniform(-0.05, 0.08)))
        specs.append((q, w * rng_.uniform(0.26, 0.33), (1.15, 1.1, 0.62)))
    out = []
    for k, (q, rr, sq) in enumerate(specs):
        def fn(p, n, q=q, rr=rr, sq=sq):
            hz = rr * sq[2]
            c = mix(PAD_D, PAD, smoothstep(q.z - hz, q.z + 0.1 * hz, p.z))
            return mix(c, PAD_L, smoothstep(q.z + 0.2 * hz, q.z + hz, p.z))
        out.append(ball(f"{name}_{k}", rr, tuple(q), fn, squash=sq, subdiv=2))
    return out


parts += pad("PadL", br_l[-1] + Vector((-0.1, -0.05, 0.18)), 1.25, 3)
parts += pad("PadR", br_r[-1] + Vector((0.1, 0.05, 0.18)), 1.1, 5)
parts += pad("PadTop", trunk[-1] + Vector((0, 0, 0.2)), 1.35, 7)

# ---- face: serene closed eyes, soft smile, blush
f = Face(b, eye_u=0.52, eye_v=1.82, mouth_v=1.45, s=1.15, ink=INKB, mouth_col=hexc("6a2a3a"))
f.eyes("sleepy", w=0.5)
f.mouth("smile", w=0.9)
f.cheeks(color=hexc("ff9ab8"))
parts += f.parts
ship("slime_bonsai", parts)
