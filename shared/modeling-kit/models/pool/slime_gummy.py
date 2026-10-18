# Gummy (Common): the classic lime gumdrop, big grin. The baseline every other slime is compared to.
from models._slimepool import *

GREEN, GREEN_D, BELLY = hexc("7ee84f"), hexc("3fae3a"), hexc("d8ff9e")


def paint(a, z, p):
    # soft lighter belly patch low on the front
    f = smoothstep(0.85, 0.35, abs(a)) * smoothstep(1.5, 0.6, z)
    return mix(GREEN, BELLY, 0.55 * f)


b = Body([(0, 1.05), (0.12, 1.32), (0.45, 1.5), (0.95, 1.48), (1.6, 1.25), (2.25, 0.82), (2.75, 0.32), (2.95, 0)],
         paint=paint, lean=lambda z: 0.25 * max(0.0, (z - 2.0) / 0.95) ** 2, gloss=0.55)
parts = [b.obj]
parts += spots(b, [(140, 1.0, 0.32), (165, 1.9, 0.22), (215, 1.3, 0.28), (110, 1.7, 0.18)], GREEN_D)
parts += Face(b, eye_v=1.62, mouth_v=1.18).eyes("round", w=0.52, h=0.7).mouth("grin", w=1.2).cheeks().parts
ship("slime_gummy", parts)
