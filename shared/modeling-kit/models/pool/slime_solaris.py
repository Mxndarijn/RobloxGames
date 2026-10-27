# Solaris (Celestial): a sun spirit slime. Glowing gold-orange body, deep orange at the foot and
# white-gold at the crown, a flame curl on top, a big rayed corona floating behind it (long and
# short rays alternating round a glowing ring), tiny solar flares floating round it, and a beaming
# happy face with warm cheeks.
from models._slimepool import *

ORA_D, ORA, GOLDB, YEL, CROWN = hexc("ff6a1a"), hexc("ff9420"), hexc("ffb92a"), hexc("ffe25a"), hexc("fff8c8")
RAY_D, RAY, RAY_L = hexc("ff9420"), hexc("ffc02a"), hexc("fff3a0")
FLARE_D, FLARE, FLARE_L = hexc("ff4a1a"), hexc("ff9a2a"), hexc("ffe680")
INKS = hexc("5a1e0a")


def paint(a, z, p):
    c = mix(ORA_D, ORA, smoothstep(0.0, 0.8, z))
    c = mix(c, GOLDB, smoothstep(0.7, 1.6, z))
    c = mix(c, YEL, smoothstep(1.5, 2.4, z))
    c = mix(c, CROWN, smoothstep(2.35, 3.0, z))
    # soft hot swirls (sun granulation), stronger low on the body
    n = noise.noise(Vector((p.x * 1.8, p.y * 1.8, p.z * 1.4 + 7.0)))
    c = mix(c, YEL, 0.35 * smoothstep(0.15, 0.5, n) * smoothstep(2.4, 1.2, z))
    return c


b = Body([(0, 1.08), (0.14, 1.38), (0.55, 1.56), (1.2, 1.55), (1.85, 1.33), (2.4, 0.95), (2.8, 0.48), (3.0, 0)],
         paint=paint, segs=44, sub=3, gloss=0.6, shade=0.45)
parts = [b.obj]
H = b.H

# ---- corona: glowing ring + alternating long/short rays, standing behind the body, tilted to the face
C = Vector((0, 0.7, 1.75))
cn = Vector((0, -1, 0.2)).normalized()
cq = cn.to_track_quat("Z", "Y")
R = 1.92
parts.append(torus("Corona", R, 0.17, C, cn, lambda p, n: mix(hexc("ff6a1a"), RAY, 0.4 + 0.6 * max(0.0, n.dot(Vector((0, -0.6, 0.8))))), segs=48, rsegs=6))
parts.append(torus("CoronaIn", R - 0.24, 0.06, C + cn * 0.02, cn, FLARE_L, segs=44, rsegs=4))
NR = 24
for k in range(NR):
    a = k * math.tau / NR + math.pi / 2
    deg = math.degrees(a) % 360
    if 240 < deg < 300:
        continue  # no rays into the ground
    radial = cq @ Vector((math.cos(a), math.sin(a), 0))
    tang = cn.cross(radial)
    long = k % 2 == 0
    L = 0.95 if long else 0.5
    w = 0.34 if long else 0.24
    base = C + radial * (R + 0.02) - cn * 0.02
    poly = [(-w, 0), (-w * 0.55, L * 0.4), (0, L), (w * 0.55, L * 0.4), (w, 0)]
    parts.append(puffy_slab(f"Ray{k}", poly, 0.12, base, tang, radial,
                            along(RAY_D if long else FLARE, RAY_L, base, base + radial * L, power=0.8), rows=2))

# ---- tiny solar flares floating round it (teardrop flames pointing up and out)
def flame_poly(L, w, n=6):
    right = [(w * math.sin(math.pi * (k / n) ** 0.7) * (1 - k / n) ** 0.25, L * k / n) for k in range(1, n)]
    left = [(-x, y) for x, y in reversed(right)]
    bottom = [(math.cos(math.radians(180 + 180 * j / 6)) * w * 0.55, math.sin(math.radians(180 + 180 * j / 6)) * w * 0.45) for j in range(1, 6)]
    return [(-w * 0.55, 0)] + bottom + [(w * 0.55, 0)] + right + [(0, L)] + left


for k, (pos, L, lean) in enumerate((((-2.35, -0.4, 2.7), 0.62, 0.35), ((2.4, -0.5, 2.35), 0.55, -0.3), ((-2.2, -0.6, 0.6), 0.42, 0.25),
                                    ((2.3, -0.7, 0.75), 0.4, -0.2), ((1.3, -0.9, 3.55), 0.38, -0.2), ((-1.2, -0.9, 3.6), 0.34, 0.25))):
    P = Vector(pos)
    up = Vector((lean, 0, 1)).normalized()
    parts.append(puffy_slab(f"Flare{k}", flame_poly(L * 1.3, L * 0.55), 0.14, P, Vector((up.z, 0, -up.x)), up,
                            lambda p, n, P=P, up=up, L=L: mix(FLARE_D, FLARE_L, smoothstep(-0.1 * L, 0.9 * L, (p - P).dot(up))), rows=2))
    parts.append(ball(f"FlareCore{k}", L * 0.16, P + up * L * 0.08 + Vector((0, -0.06, 0)), FLARE_L, subdiv=1))

# ---- flame tuft on top of the head: three tongues in the front plane + one across for depth
for k, (x, L, lean, w) in enumerate(((0.0, 1.35, 0.0, 0.46), (-0.4, 0.85, 0.5, 0.32), (0.42, 0.95, -0.45, 0.34))):
    P = Vector((x, 0.0, H - 0.32 - abs(x) * 0.25))
    up = Vector((-lean, 0, 1)).normalized()
    parts.append(puffy_slab(f"Tuft{k}", flame_poly(L, w), 0.22 if k == 0 else 0.16, P, Vector((up.z, 0, -up.x)), up,
                            lambda p, n, P=P, up=up, L=L: mix(FLARE_D, FLARE_L, smoothstep(0.1 * L, 0.95 * L, (p - P).dot(up))), rows=3))
parts.append(puffy_slab("TuftX", flame_poly(1.0, 0.34), 0.16, Vector((0, 0.05, H - 0.32)), Vector((0, 1, 0)), Vector((0, 0.15, 1)).normalized(),
                        lambda p, n: mix(FLARE_D, FLARE_L, smoothstep(H - 0.1, H + 0.75, p.z)), rows=3))

# ---- little sun spots / sparkle specks on the back
import random
rng = random.Random(5)
for i in range(16):
    yaw = rng.uniform(70, 290)
    z = rng.uniform(0.5, 2.6)
    r = rng.uniform(0.06, 0.11)
    parts.append(decal(f"Speck{i}", star(0, 0, r, r * 0.35, n=4), CROWN, frame_at(yaw, z), off=0.01, th=0.012, on=["Body"], step=0))

# ---- beaming happy face, warm cheeks
f = Face(b, eye_u=0.55, eye_v=1.62, mouth_v=1.18, s=1.15, ink=INKS, mouth_col=hexc("8a1a1a"))
f.eyes("happy")
f.mouth("open", w=1.2)
f.cheeks(color=hexc("ff4a3a"), w=0.36, h=0.18)
for sd in (-1, 1):  # cheek shine
    f.d(f"CheekHi{sd}", oval(sd * (f.eu + 0.36 * f.s) - 0.05, f.ev - 0.3 * f.s + 0.04, 0.09, 0.05, n=8), hexc("ffc0a0"), off=0.03, th=0.008)
parts += f.parts

ship("slime_solaris", parts)
