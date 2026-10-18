# Blaze (Epic): fire slime. Red foot -> orange -> yellow body whose top IS a flame, angry fangs grin, embers.
from models._slimepool import *

RED, RED_D, ORA, YEL, CREAM = hexc("e8261c"), hexc("b0140f"), hexc("ff7a1a"), hexc("ffd23a"), hexc("fff6c0")


def body_paint(a, z, p):
    if z < 1.2:
        return mix(RED_D, RED, smoothstep(0.0, 0.5, z)) if z < 0.5 else mix(RED, ORA, smoothstep(0.5, 1.2, z))
    return mix(ORA, YEL, smoothstep(1.3, 2.4, z))


def flame_col(p, n):
    # yellow where it grows out of the body -> orange -> red-orange tongue tips; centre stays hotter
    core = smoothstep(0.75, 0.15, math.hypot(p.x, p.y + 0.1))
    c = mix(YEL, ORA, smoothstep(2.7, 3.35, p.z))
    c = mix(c, hexc("ff3a12"), smoothstep(3.4, 4.1, p.z))
    return mix(c, mix(YEL, CREAM, smoothstep(2.6, 3.4, p.z)), core * smoothstep(4.0, 2.9, p.z))


b = Body([(0, 1.12), (0.15, 1.42), (0.55, 1.56), (1.2, 1.5), (1.8, 1.26), (2.3, 0.92), (2.6, 0.5), (2.72, 0)],
         paint=body_paint, gloss=0.6)
parts = [b.obj]


def tongue(base, top, r0, r1, sway=0.0, n=7):
    """chain of shrinking balls from base to top with a sideways S sway (x)."""
    out = []
    for k in range(n):
        t = k / (n - 1)
        p = Vector(base).lerp(Vector(top), t)
        p.x += sway * math.sin(t * math.pi * 1.2)
        r = r0 + (r1 - r0) * t ** 0.8
        out.append(((p.x, p.y, p.z), r, (1, 1, 1.25)))
    return out


balls = [((0, 0.05, 2.35), 0.85, (1.15, 1.1, 0.55))]
balls += tongue((0, 0.05, 2.5), (0.12, 0.1, 4.35), 0.6, 0.1, sway=-0.2, n=9)
balls += tongue((-0.55, 0.0, 2.45), (-1.05, 0.1, 3.7), 0.44, 0.08, sway=0.18)
balls += tongue((0.55, 0.0, 2.45), (1.1, 0.05, 3.85), 0.44, 0.08, sway=-0.18)
balls += tongue((0.05, 0.6, 2.4), (0.0, 0.85, 3.5), 0.4, 0.08, sway=0.15)
balls += tongue((-0.3, -0.4, 2.35), (-0.4, -0.45, 3.1), 0.32, 0.07, n=5)
balls += tongue((0.35, -0.4, 2.35), (0.45, -0.45, 3.2), 0.32, 0.07, n=5)
parts.append(goo("Flame", balls, flame_col, tris=1600, resolution=0.08))

# embers floating round the flame
for k, (x, y, z, r) in enumerate([(-1.5, -0.2, 3.2, 0.17), (1.55, 0.1, 2.9, 0.14), (-1.2, 0.4, 4.2, 0.12),
                                  (1.3, -0.3, 4.3, 0.13), (0.55, 0.3, 4.85, 0.1), (-0.5, -0.3, 4.6, 0.09)]):
    parts.append(gem(f"Ember{k}", (x, y, z), r, hexc("ffc020") if k % 2 else hexc("ff6a1a"), segs=4))

f = Face(b, eye_v=1.42, mouth_v=0.92, s=1.15)
f.eyes("angry", w=0.44, h=0.58).brows("angry", lift=-0.02, th=0.09)
# wicked open grin with two fangs
mv = f.mv
f.d("Mouth", half_oval(0, mv + 0.07, 0.62, 0.26, n=14), MOUTH)
f.d("Tongue", oval(0.04, mv - 0.1, 0.26, 0.09), hexc("ff6a3a"), off=0.04, th=0.012)
for sd in (-1, 1):
    f.d(f"Fang{sd}", [(sd * 0.1, mv + 0.07), (sd * 0.24, mv + 0.07), (sd * 0.17, mv - 0.08)], WHITE, off=0.045, th=0.012)
parts += f.parts
ship("slime_blaze", parts)
