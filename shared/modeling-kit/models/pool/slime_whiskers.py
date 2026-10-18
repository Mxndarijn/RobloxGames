# Whiskers (Rare): smug orange tabby cat slime. Loaf-wide goo, pointy ears with pink inners,
# bold tiger stripes over the back, cream muzzle with a :3 mouth, heavy-lidded green eyes, curly tail.
from models._slimepool import *

OR, OR_D, OR_L = hexc("ff9a2e"), hexc("d4561a"), hexc("ffc070")
CREAM, PINK, GREEN = hexc("fff1d6"), hexc("ff9fb8"), hexc("7be05a")


def paint(a, z, p):
    c = mix(OR, OR_L, 0.4 * smoothstep(1.4, 2.6, z))
    f = smoothstep(0.75, 0.35, abs(a)) * smoothstep(1.25, 0.7, z)
    return mix(c, CREAM, 0.85 * f)


b = Body([(0, 1.2), (0.15, 1.5), (0.55, 1.64), (1.2, 1.55), (1.85, 1.22), (2.35, 0.7), (2.62, 0.22), (2.7, 0)],
         paint=paint, sx=1.06, segs=44)
parts = [b.obj]

# ears: pointy, tilted out, pink inner
for sd in (-1, 1):
    t = math.radians(-sd * 22)
    X = (math.cos(t), 0, math.sin(t))
    Y = (-math.sin(t), 0, math.cos(t))
    parts.append(puffy_slab(f"Ear{sd}", [(-0.42, 0), (0.42, 0), (0.08, 0.92), (-0.04, 0.92)], 0.26,
                            (sd * 0.72, 0.05, 2.12), X, Y, zgrad(OR, OR_D, 2.3, 3.0)))
    parts.append(puffy_slab(f"EarIn{sd}", [(-0.26, 0.1), (0.26, 0.1), (0.03, 0.72)], 0.08,
                            (sd * 0.72, -0.1, 2.14), X, Y, PINK))

# tiger stripes: bold tapered wedges down the back and sides, plus three on the forehead
for yaw in (90, 122, 152, 180, 208, 238, 270):
    w = 0.3 if abs(yaw - 180) < 50 else 0.24
    poly = [(-w, 0.8), (-w * 0.3, 0.86), (w * 0.3, 0.86), (w, 0.8), (0.04, -0.6), (-0.04, -0.6)]
    parts.append(decal(f"Stripe{yaw}", poly, OR_D, frame_at(yaw, 1.7, tilt=20), off=0.01, th=0.015, on=["Body"]))
for k, (u, rot, ln) in enumerate(((-0.24, 14, 0.32), (0.0, 0, 0.4), (0.24, -14, 0.32))):
    top = 2.5 if k == 1 else 2.42
    poly = [(-0.08, 0), (0.08, 0), (0.02, -ln), (-0.02, -ln)]
    c, sn = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    poly = [(u + x * c - y * sn, top + x * sn + y * c) for x, y in poly]
    parts.append(decal(f"M{k}", poly, OR_D, FRONT, off=0.01, th=0.015, on=["Body"]))

# tail: curls up beside the body (viewer-right), tip flicking outward, so it reads from the front
ctrl = [(0.7, 1.25, 0.32), (1.35, 1.1, 0.42), (1.82, 0.85, 0.75), (1.95, 0.7, 1.25), (1.92, 0.62, 1.7),
        (2.02, 0.6, 2.02), (2.22, 0.62, 2.14), (2.36, 0.66, 2.04)]
tp = [(x, y, z) for (x, z), (_, y) in zip(catmull([(c[0], c[2]) for c in ctrl], 3), catmull([(c[0], c[1]) for c in ctrl], 3))]
rad = [0.25 - 0.13 * (i / (len(tp) - 1)) ** 1.5 for i in range(len(tp))]
tail = horn("Tail", tp, rad, OR, OR, segs=10)
paint_fn(tail, lambda p, n: OR_D if math.sin(p.z * 6.0 + p.x * 4) > 0.4 else OR)
parts.append(tail)

f = Face(b, eye_v=1.62, mouth_v=1.08, eye_u=0.55)
f.d("MuzzleL", oval(-0.17, 1.03, 0.46, 0.34, n=16), CREAM, off=0.012, th=0.012)
f.d("MuzzleR", oval(0.17, 1.03, 0.46, 0.34, n=16), CREAM, off=0.013, th=0.012)
# mischievous wink: one big green eye, one ^ closed
f._eye_round(-1, 0.54, 0.66, iris=GREEN)
f.d("Wink", arc(0.55, 1.56, 0.2, 20, 160, 0.09), INK)
f.d("WinkLash", rect(0.8, 1.6, 0.14, 0.05, math.radians(20)), INK)
f.nose(color=PINK, w=0.22, h=0.14, v=1.2)
f.mouth("cat", w=1.1, v=1.08)
f.whiskers(color=hexc("5a3020"))
f.cheeks(color=hexc("ff8fa8"), u=0.95, v=1.25)
parts += f.parts
ship("slime_whiskers", parts)
