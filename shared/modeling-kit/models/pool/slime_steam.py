# Steampuff (hybrid, tier 5: blaze + frostbite + zap): fire meets ice. Body split down the middle
# with a wavy seam: Blaze's red-orange-yellow on one side, Frostbite's icy blue + snow on the
# other, flame tongues licking up the warm shoulder, icicle crystals on the cold one, a billowing
# white steam cloud on top with Zap's yellow bolts crackling out, sweaty nervous clenched grin.
from models._slimepool import *

RED, RED_D, ORA, YEL = hexc("e8261c"), hexc("b0140f"), hexc("ff7a1a"), hexc("ffd23a")
ICE, ICE_D, ICE_L, SNOW = hexc("6cc8ff"), hexc("2a7fe0"), hexc("b4e8ff"), hexc("ffffff")
CRY0, CRY1 = hexc("1f86e8"), hexc("c8f6ff")
BOLT, BOLT_L = hexc("ffe02a"), hexc("fff6a0")
SWEAT = hexc("8fd8ff")


def seam(z):
    """x of the fire/ice seam at height z (wavy, so it reads as two forces pushing)."""
    return 0.1 * math.sin(z * 3.2 + 0.4)


def warm(z):
    c = mix(RED_D, RED, smoothstep(0.0, 0.5, z))
    c = mix(c, ORA, smoothstep(0.5, 1.3, z))
    return mix(c, YEL, smoothstep(1.4, 2.5, z))


def cold(z):
    c = mix(ICE_D, ICE, smoothstep(0.0, 1.1, z))
    return mix(c, ICE_L, smoothstep(1.3, 2.4, z))


def paint(a, z, p):
    t = smoothstep(-0.035, 0.035, p.x - seam(z))  # 1 = +X (viewer right) = fire
    return mix(cold(z), warm(z), t)


b = Body([(0, 1.15), (0.15, 1.45), (0.55, 1.6), (1.2, 1.54), (1.8, 1.3), (2.3, 0.95), (2.62, 0.5), (2.75, 0)],
         paint=paint, segs=40, sub=2, gloss=0.6)
parts = [b.obj]

# ---- steam cloud: one billowing goo shell, puffs bulging out of it
cloud_base = [((0, 0.05, 2.5), 0.85, (1.5, 1.15, 0.4)), ((-1.15, 0.05, 2.55), 0.4), ((1.15, 0.05, 2.55), 0.4)]
puffs = [(-0.8, 0.0, 2.8, 0.55), (0.05, 0.05, 3.05, 0.68), (0.85, 0.0, 2.8, 0.55), (-0.4, -0.42, 2.75, 0.45),
         (0.45, -0.42, 2.75, 0.45), (-0.4, 0.55, 2.85, 0.48), (0.45, 0.55, 2.85, 0.48), (-1.3, 0.05, 2.6, 0.34),
         (1.3, 0.05, 2.62, 0.34), (-0.2, 0.05, 3.55, 0.42), (0.3, 0.1, 3.8, 0.32)]


def cloud_col(p, n):
    c = mix(hexc("c9d2e2"), SNOW, smoothstep(2.3, 3.2, p.z))
    # faint warm / cool tint per side, so the cloud ties both halves together
    t = smoothstep(-0.8, 0.8, p.x)
    return mix(c, mix(hexc("cfe6ff"), hexc("ffe4cc"), t), 0.35 * smoothstep(3.4, 2.4, p.z))


parts.append(goo("Steam", cloud_base, cloud_col, tris=350, resolution=0.09))
for k, (x, y, z, r) in enumerate(puffs):
    parts.append(ball(f"Puff{k}", r, (x, y, z), cloud_col, subdiv=2))
# little steam wisps drifting off the top
for k, (x, y, z, r) in enumerate([(-0.85, -0.1, 4.0, 0.2), (0.75, 0.2, 4.35, 0.16), (-0.25, 0.1, 4.6, 0.12)]):
    parts.append(ball(f"Wisp{k}", r, (x, y, z), SNOW, subdiv=2))

# ---- fire side: flame tongues licking up the warm shoulder
def flame_col(p, n):
    c = mix(hexc("fff2a0"), YEL, smoothstep(1.0, 1.5, p.z))
    c = mix(c, ORA, smoothstep(1.5, 1.95, p.z))
    return mix(c, hexc("e82010"), smoothstep(1.95, 2.45, p.z))


fb = []
for k, (yaw, z0, L) in enumerate(((68, 1.3, 1.25), (104, 1.05, 1.0), (135, 1.25, 0.8))):
    a = math.radians(yaw)
    base = b.point(a, z0, -0.2)
    out = Vector((math.sin(a), -math.cos(a), 0))
    for j in range(7):
        t = j / 6
        # leaves the body sideways, then curls straight up: a tongue licking off the shoulder
        p = base + out * (0.75 * math.sin(t * math.pi / 2)) + Vector((0, 0, L * t ** 1.4))
        fb.append(((p.x, p.y, p.z), 0.34 - 0.27 * t ** 0.8, (1, 1, 1.3)))
parts.append(goo("Flame", fb, flame_col, tris=420, resolution=0.07))
for k, (x, y, z, r) in enumerate([(2.0, -0.2, 2.6, 0.12), (1.75, 0.3, 3.1, 0.1), (2.15, 0.1, 1.9, 0.09)]):
    parts.append(gem(f"Ember{k}", (x, y, z), r, hexc("ffc020") if k % 2 else hexc("ff6a1a"), segs=4))

# ---- ice side: crystals jutting from the cold shoulder + snow cap rim + icicles
for k, (yaw, z, L, rad) in enumerate(((-72, 1.45, 1.25, 0.2), (-102, 1.15, 1.0, 0.17), (-45, 1.7, 0.8, 0.15),
                                      (-130, 1.5, 0.85, 0.15), (-85, 0.75, 0.6, 0.13))):
    a = math.radians(yaw)
    base = b.point(a, z, -0.1)
    d = (math.sin(a) * 0.9, -math.cos(a) * 0.9, 0.6)
    parts.append(crystal(f"Crystal{k}", base, d, L, rad, CRY0, CRY1))
for k, yaw in enumerate((-30, -60, -90, -120, -150)):
    a = math.radians(yaw)
    p = b.point(a, 2.25, 0.02)
    L = 0.32 + 0.12 * (k % 2)
    parts.append(lathe(f"Icicle{k}", [(0, 0.1), (L, 0)], along(ICE_L, hexc("3aa8ff"), p, p - Vector((0, 0, L))),
                       pos=p, axis=(0, 0, -1), segs=5, smooth=False))

# ---- Zap's bolts crackling out of the cloud on both sides
def bolt_poly(s=1.0):
    pts = [(-0.05, 0.5), (0.25, 0.5), (0.08, 0.1), (0.3, 0.1), (-0.15, -0.55), (0.0, -0.08), (-0.22, -0.08)]
    return [(x * s, y * s) for x, y in pts]


for sd in (-1, 1):
    parts.append(slab(f"Bolt{sd}", bolt_poly(1.35), 0.13, (sd * 2.05, 0.15, 3.15), (sd * 0.75, 0.66, 0), (0, 0, 1),
                      zgrad(BOLT, BOLT_L, 2.7, 3.8)))
# a bolt marking on the back seam
parts.append(decal("Mark", bolt_poly(1.0), BOLT, frame_at(180, 1.1), off=0.015, on=["Body"], step=0))

# ---- face: wide worried eyes, nervous clenched grin, sweat drops
f = Face(b, eye_v=1.45, mouth_v=0.88, eye_u=0.52, s=1.1)
f.eyes("round", w=0.46, h=0.6, look=(0, 0.02))
f.brows("angry", w=0.36, th=0.08, lift=0.02)  # lib swap: "angry" draws inner ends UP = worried
mv = f.mv
W, H = 0.42, 0.22
outline = [(-W, mv + H / 2), (W, mv + H / 2), (W * 1.05, mv), (W, mv - H / 2), (-W, mv - H / 2), (-W * 1.05, mv)]
f.d("Mouth", [(-W - 0.05, mv + H / 2 + 0.05), (W + 0.05, mv + H / 2 + 0.05), (W + 0.1, mv),
              (W + 0.05, mv - H / 2 - 0.05), (-W - 0.05, mv - H / 2 - 0.05), (-W - 0.1, mv)], MOUTH)
f.d("Teeth", outline, WHITE, off=0.035, th=0.012)
f.d("TeethLine", rect(0, mv, 2 * W, 0.03), hexc("9aa6c0"), off=0.05, th=0.008)
for k in range(5):
    f.d(f"TeethV{k}", rect(-W + (k + 1) * 2 * W / 6, mv, 0.025, H), hexc("9aa6c0"), off=0.05, th=0.008)
parts += f.parts
# sweat: a big drop on the forehead (3D) + one running down the cold cheek
sp = b.point(math.radians(-32), 2.0, 0.02)
parts.append(lathe("Sweat", [(0, 0.0), (0.06, 0.1), (0.16, 0.12), (0.28, 0.07), (0.36, 0)], zgrad(SWEAT, SNOW, sp.z - 0.1, sp.z + 0.3),
                   pos=sp - Vector((0, 0, 0.15)), axis=(0.1, -0.2, 1), segs=10))
parts.append(decal("Drop", [(-0.6 + math.cos(t) * 0.08, 1.1 + math.sin(t) * 0.08) for t in [math.radians(d) for d in range(-200, 30, 20)]]
                   + [(-0.6, 1.3)], SWEAT, off=0.03, th=0.02, on=["Body"]))
ship("slime_steam", parts)
