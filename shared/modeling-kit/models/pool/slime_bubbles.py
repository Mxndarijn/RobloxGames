# Bubbles (Common): round sky-blue ball, soap bubbles floating round its head, blowing one more.
from models._slimepool import *

SKY, SKY_D, SKY_L = hexc("5cc4ff"), hexc("2f8fe6"), hexc("bfeaff")


def paint(a, z, p):
    return mix(SKY, SKY_L, 0.45 * smoothstep(1.6, 2.9, z))


def soap(c):
    """iridescent pearl: cyan / pink / lemon by direction from the centre, very light."""
    def fn(p, n):
        d = (p - Vector(c)).normalized()
        col = mix(hexc("8eeaff"), hexc("ffa8e4"), 0.5 + 0.5 * d.x)
        col = mix(col, hexc("fff08a"), max(0.0, -d.z) * 0.7)
        rim = 1 - abs(d.y)  # brighter centre, coloured rim: soapy film
        return mix(WHITE, col, 0.35 + 0.65 * rim)
    return fn


def bubble(name, c, r):
    out = [ball(name, r, c, soap(c), subdiv=2)]
    out.append(ball(name + "Hi", r * 0.22, (c[0] - r * 0.45, c[1] - r * 0.6, c[2] + r * 0.45), WHITE, squash=(1, 0.6, 1.3), subdiv=1))
    return out


# one squashed sphere clipped by the floor: a ball, no waist
SPH = [(z, 1.55 * math.sqrt(max(0.0, 1 - ((z - 1.25) / 1.6) ** 2))) for z in (0.0, 0.12, 0.35, 0.75, 1.25, 1.75, 2.15, 2.47, 2.7)]
b = Body(SPH + [(2.85, 0)],
         paint=paint, segs=32, gloss=0.8)
parts = [b.obj]
parts += bubble("BubA", (1.35, -0.3, 2.95), 0.42)
parts += bubble("BubB", (-1.2, 0.1, 3.3), 0.3)
parts += bubble("BubC", (0.3, 0.45, 3.65), 0.21)
f = Face(b, eye_u=0.52, eye_v=1.62, mouth_v=1.05).eyes("big", iris=hexc("2a7fd9")).mouth("o", w=1.0).cheeks()
parts += f.parts
# the bubble it is blowing, stuck to the 'o'
parts += bubble("BubM", (0.05, -1.66, 0.62), 0.26)
ship("slime_bubbles", parts)
