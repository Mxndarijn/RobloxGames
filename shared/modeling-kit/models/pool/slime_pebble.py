# Pebble (Common): lumpy grey-tan rock slime, mossy green cap with a pebble or two, grumpy unibrow.
from models._slimepool import *

ROCK, ROCK_D, ROCK_L = hexc("b0a594"), hexc("706660"), hexc("e2d7c0")
MOSS, MOSS_L, MOSS_D = hexc("5cb83a"), hexc("b0e860"), hexc("2f7a2a")


def nz(a, z, s=1.0):
    return noise.noise(Vector((math.sin(a) * 1.7 * s, math.cos(a) * 1.7 * s, z * 1.3 * s)))


def moss_edge(a):
    return 1.95 + 0.22 * nz(a, 0.0, 2.0) - 0.15 * math.cos(a)


def moss_w(a, z):
    edge = moss_edge(a)
    return smoothstep(edge - 0.03, edge + 0.03, z)


def bump(a, z):
    return 0.11 * nz(a, z, 0.8) + 0.035 * nz(a, z, 2.6) + moss_w(a, z) * (0.08 + 0.05 * nz(a, z, 5.0))


def paint(a, z, p):
    c = mix(ROCK_D, ROCK, smoothstep(0.0, 1.0, z))
    c = mix(c, ROCK_L, 0.45 * max(0.0, nz(a, z, 2.5)))
    e = moss_edge(a)
    c = mix(c, shade(ROCK_D, 0.8), 0.7 * smoothstep(e - 0.22, e - 0.03, z))  # shadow under the moss lip
    t = nz(a, z, 4.0)
    m = mix(MOSS, MOSS_L, 0.8 * max(0.0, t)) if t > 0 else mix(MOSS, MOSS_D, -0.9 * t)
    return mix(c, m, moss_w(a, z))


b = Body([(0, 1.25), (0.15, 1.5), (0.6, 1.6), (1.2, 1.52), (1.8, 1.22), (2.3, 0.72), (2.6, 0.22), (2.66, 0)],
         paint=paint, bump=bump, gloss=0.3, segs=26, sub=2)
keep(b.obj, False)  # faceted: reads as stone
parts = [b.obj]
parts += spots(b, [(150, 0.7, 0.18), (200, 1.2, 0.12), (110, 1.4, 0.14), (-120, 0.6, 0.16)], ROCK_D, n=7)
for name, r, pos, col in (("PebA", 0.36, (0.4, 0.2, 2.6), hexc("8a8fa0")), ("PebB", 0.24, (-0.4, 0.45, 2.5), hexc("e0cfa8"))):
    parts.append(ball(name, r, pos, along(shade(col, 0.8), mix(col, WHITE, 0.3), (0, 0, pos[2] - r), (0, 0, pos[2] + r)), squash=(1.25, 1.0, 0.62), subdiv=2))
for k, (yaw, z, w, h) in enumerate(((125, 0.55, 0.42, 0.26), (235, 0.8, 0.34, 0.22), (-75, 0.45, 0.3, 0.2))):
    parts.append(decal(f"MossPatch{k}", blotch(k + 5, w, h), MOSS, frame_at(yaw, z), off=0.012, th=0.03, on=["Body"]))
parts.append(decal("Crack", zigzag(-0.35, 0.35, 0.0, 0.06, 5, 0.05), shade(ROCK_D, 0.7), frame_at(160, 1.2, cx=0, cy=0), off=0.012, th=0.02, on=["Body"]))
f = Face(b, eye_u=0.5, eye_v=1.45, mouth_v=1.0).eyes("angry", w=0.42, h=0.48).brows("unibrow", lift=-0.12).mouth("flat", w=1.3)
parts += f.parts
ship("slime_pebble", parts)
