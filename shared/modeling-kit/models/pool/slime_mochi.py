# Mochi (Common): wide, low, squishy rice-cake. White with a pink blush crown, powder dots, a sakura
# blossom on top and a sleepy, content face.
from models._slimepool import *

RICE, PINK, PINK_D = hexc("fff6f2"), hexc("ffa6c4"), hexc("ff6f9c")


def paint(a, z, p):
    return mix(RICE, PINK, smoothstep(0.95, 2.05, z) ** 1.2)


b = Body([(0, 1.38), (0.1, 1.58), (0.4, 1.68), (0.8, 1.64), (1.25, 1.5), (1.62, 1.22), (1.9, 0.8), (2.05, 0.35), (2.1, 0)],
         paint=paint, sy=0.92, gloss=0.8)
parts = [b.obj]
# powder dusting: tiny dots, white on the pink crown, pale pink lower down
dots = []
for k in range(22):
    yaw = (k * 137.5 + 20 * math.sin(k * 3.1)) % 360
    z = 0.45 + ((k * 0.381 + 0.37 * math.sin(k * 7.7)) % 1.0) * 1.4
    if abs(((yaw + 180) % 360) - 180) < 55 and 0.6 < z < 1.5:
        continue  # keep the face clear
    dots.append((yaw, z, 0.09 + 0.035 * ((k * 7) % 3)))
parts += spots(b, [d for d in dots if d[1] >= 1.2], WHITE, n=6)
parts += spots(b, [d for d in dots if d[1] < 1.2], hexc("ffd2e0"), n=6)
# sakura blossom on top
petal = []
for k in range(40):
    t = k * math.tau / 40
    r = 0.44 * (0.55 + 0.45 * abs(math.cos(2.5 * t)) ** 0.7)
    petal.append((0.3 + math.cos(t) * r, -0.3 + math.sin(t) * r))
parts.append(decal("Sakura", petal, hexc("ff5e95"), TOP, off=0.02, th=0.04, step=None))
parts.append(decal("SakuraC", oval(0.3, -0.3, 0.16, 0.16, n=10), hexc("ffe36a"), TOP, off=0.06, th=0.02))
f = Face(b, eye_u=0.6, eye_v=1.05, mouth_v=0.76, s=1.25).eyes("sleepy", w=0.5).mouth("cat", w=1.0).cheeks(w=0.36, h=0.18, color=PINK_D)
parts += f.parts
ship("slime_mochi", parts)
