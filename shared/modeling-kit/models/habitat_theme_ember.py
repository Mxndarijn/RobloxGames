# habitat_theme_ember ("Ember Rocks"): fire theme for the habitat pad (Blaze, Imp, Drako, Phoenix, Goozilla). Props on the back
# and sides of the rim only (the frame mesh supplies the ring): a little smoking volcano cone at the back with a lava
# crater and two lava runs, chunky dark lava rocks with glowing orange cracks on the back corners and sides, low
# rock-and-lava bits toward the front sides, glowing embers on the deck and in the air. Front arc stays clear.
import math, random
from lib import *
from models._habitat_overlay import *
from models._habitat_theme_bits import *
from models._phoenix_pad import lathe

ROCK_LO, ROCK_HI = rgb(122, 98, 104), rgb(176, 150, 150)  # lifted basalt: the Roblox look crushes darks
GLOW, GLOW_HI, GLOW_D = rgb(255, 120, 30), rgb(255, 214, 80), rgb(236, 74, 30)
SMOKE_LO, SMOKE_HI = rgb(170, 160, 168), rgb(236, 232, 236)
R = random.Random(11)
parts = []


def ember_rock(name, r, pos, seed, squash=(1.0, 1.0, 0.8), crack=0.16, subdiv=2):
    """Faceted basalt lump; faces on a few wavy bands glow lava (cracks)."""
    b = blob(name, r, pos, None, seed=seed, subdiv=subdiv, squash=squash, jitter=0.18, rot=(0, 0, seed * 37))
    stand(b, 0.0)
    top = max(v.co.z for v in b.data.vertices) * 0.82  # flat-topped, chunky (not an egg)
    for v in b.data.vertices:
        if v.co.z > top:
            v.co.z = top + (v.co.z - top) * 0.25
    rr = random.Random(seed)
    ph, fr, tilt = rr.uniform(0, 6.28), rr.uniform(5.5, 7.5), rr.uniform(-0.8, 0.8)
    z0 = min((b.matrix_world @ v.co).z for v in b.data.vertices)
    z1 = max((b.matrix_world @ v.co).z for v in b.data.vertices)

    def col(c, n):
        t = (c.z - z0) / max(z1 - z0, 1e-6)
        w = math.sin((c.x + tilt * c.y) * fr + ph + c.z * 3.0) + 0.6 * math.sin(c.y * fr * 0.8 - ph)
        if abs(w) < crack and n.z > -0.3 and t > 0.12:
            return GLOW_HI if abs(w) < crack * 0.4 else GLOW
        return mix(ROCK_LO, ROCK_HI, min(1.0, 0.15 + t * 0.9 + 0.12 * n.z))

    return paint_faces(b, col)


def ember(name, r, pos, seed, hot=True):
    e = blob(name, r, pos, None, seed=seed, subdiv=1, jitter=0.2)
    return paint_faces(e, lambda c, n: GLOW_HI if (n.z > 0.2 and hot) else GLOW)


# --- back: volcano cone, wide along the rim (> RIGID, so round_up bends it instead of shrinking it) ---
vx, vy, _ = at(90, dr=0.0)
CONE = [(0, 0), (0.62, 0), (0.6, 0.3), (0.47, 1.0), (0.34, 1.7), (0.27, 2.02), (0.32, 2.12), (0.2, 1.98), (0, 1.96)]
SH = (1.0, 0.86, 1.06, 0.93, 1.1, 0.9, 1.0, 0.86, 1.04, 0.95)
cone_col = lambda i, k, z: (GLOW_HI if i >= 7 else (ROCK_HI if i == 6 else
                            shade(mix(ROCK_LO, ROCK_HI, min(1.0, 0.25 + z / 1.8)), SH[k % 10])))
c = lathe("Mound", CONE, segs=10, pos=(0, 0, 0), color_fn=cone_col)
for v in c.data.vertices:  # lumpy, stretched along the rim
    a = math.atan2(v.co.y, v.co.x)
    k = 1 + (0.12 * math.sin(a * 3 + v.co.z * 4) if 0.1 < v.co.z < 1.95 else 0)
    v.co.x, v.co.y = v.co.x * k * 1.35, v.co.y * k
c.data.transform(__import__("mathutils").Matrix.Translation((vx, vy, 0)))
parts.append(c)
for k, (t0, ln) in enumerate(((-0.3, 1.35), (0.25, 1.0), (0.02, 0.6))):  # lava runs down the front-facing slope
    path = [(t0 + 0.12 * math.sin(j * 1.3 + k), 2.04 - ln * j / 5) for j in range(6)]
    run = vein(f"GlowRun{k}", c, (vx, vy), -90, path, [0.12, 0.11, 0.1, 0.09, 0.08, 0.07], GLOW, lift=0.0, segs=5)
    parts.append(paint_faces(run, lambda c, n: GLOW_HI if n.z > 0.2 else GLOW))
crater = blob("Vent", 0.34, (vx, vy, 2.03), None, seed=3, subdiv=2, squash=(1.3, 1.05, 0.42), jitter=0.06)
parts.append(paint_faces(crater, lambda c, n: GLOW_HI if n.z > 0.5 else GLOW))
for k, (dz, r, dx) in enumerate(((2.3, 0.24, 0.0), (2.52, 0.3, 0.16), (2.68, 0.2, -0.12))):  # smoke column
    sm = blob(f"Smoke{k}", r, (vx + dx, vy + 0.05, dz), None, seed=40 + k, subdiv=2, jitter=0.1, squash=(1.2, 1.0, 0.8))
    gradient(sm, SMOKE_LO, SMOKE_HI)
    parts.append(sm)

# --- rock wall round the back: tall cracked boulders stepping down toward the sides (each its own rigid group) ---
ROCKS = [(48, 0.58, 1.75, 1.15), (21, 0.52, 1.35, 1.2), (-4, 0.42, 1.0, 1.25), (-27, 0.28, 0.8, 1.2)]  # ang, r, h, wide
for side in (1, -1):
    for k, (ang, r, h, w) in enumerate(ROCKS):
        a = ang if side == 1 else 180 - ang
        o = ember_rock(f"Rock{side}{k}", r, (0, 0, 0), seed=5 + k * 7 + side, squash=(0.95, w, h),
                      subdiv=2 if r > 0.3 else 1, crack=0.05)
        o.data.transform(__import__("mathutils").Matrix.Translation(at(a)) @ __import__("mathutils").Matrix.Rotation(math.radians(a), 4, "Z"))
        parts.append(o)
        for j in range(2 if r > 0.35 else 1):  # glowing cracks on the side that faces the slime (and the walkway)
            v = vein(f"Crack{side}{k}{j}", o, at(a)[:2], a + 180, zigzag((j - 0.5) * r * 0.9, 0.08, r * h * 1.6, 4, 0.18, k * 3 + j + side),
                     0.065, GLOW_HI, lift=0.0)
            if v:
                parts.append(v)
    pool = cylinder(f"Pool{side}", 0.24, 0.22, at(64 if side == 1 else 116, z=0.0, dr=0.05), None, segs=8, r_top=0.2,
                    jitter=0.1, seed=side + 3)
    parts.append(paint_faces(pool, lambda c, n: GLOW_HI if n.z > 0.5 else GLOW_D))

# --- embers: in the air round the back and glowing bits on the deck ---
for k, (ang, z) in enumerate(((68, 1.6), (112, 1.45), (34, 1.95), (146, 2.0), (8, 1.5), (172, 1.4))):
    parts.append(ember(f"Float{k}", 0.09, at(ang, z=z, dr=-0.05), 80 + k))
for k, ang in enumerate((-40, 220)):
    parts.append(ember(f"Coal{k}", 0.13, at(ang, z=0.0, dr=0.05), 90 + k))

theme_finish("habitat_theme_ember", parts)
