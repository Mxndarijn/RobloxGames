# habitat_theme_ice: ice-floe theme for the habitat pad (Pengoo, Frostbite, Snow Bunny, Steampuff, Yeti). Props on
# the back and sides of the rim only (the frame mesh supplies the ring): a little snowy pine at the back, chunky
# stacked ice blocks with snow caps and icicle fringes on the back corners, a smaller block pair on each side, soft
# snow drifts and snowballs between them. The front arc stays clear.
import math, random
from mathutils import Matrix
from lib import *
from models._habitat_overlay import *
from models._habitat_theme_bits import *
from models._habitat import place

ICE, ICE_HI, ICE_D = rgb(136, 212, 250), rgb(204, 242, 255), rgb(88, 170, 232)  # saturated sky cyan (pale goes slate)
SNOW, SNOW_D = rgb(250, 252, 255), rgb(206, 226, 246)
PINE, PINE_D = rgb(70, 178, 130), rgb(46, 138, 110)
BARK = rgb(160, 110, 76)
parts = []


def ice_block(name, size, pos, yaw, tilt=(0, 0)):
    """Bevelled ice cube: cyan sides (one facet lighter), white-blue top."""
    b = box(name, size, (0, 0, size[2] / 2), None)
    rr = random.Random(name + "j")
    for v in b.data.vertices:  # hand-cut, not a perfect cube
        v.co.x += rr.uniform(-0.07, 0.07)
        v.co.y += rr.uniform(-0.07, 0.07)
        if v.co.z > 0.01:
            v.co.z += rr.uniform(-0.1, 0.06)
    bevel(b, 0.07, 1)
    b.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
                     @ Matrix.Rotation(math.radians(tilt[0]), 4, "X") @ Matrix.Rotation(math.radians(tilt[1]), 4, "Y"))
    b.data.update()
    k = random.Random(name).uniform(0, 6.28)
    return paint_faces(b, lambda c, n: (ICE_HI if n.z > 0.7 else
                                        shade(mix(ICE_D, ICE, 0.5 + 0.5 * math.sin(math.atan2(n.y, n.x) * 2 + k)), 1.0)))


def snow_cap(name, w, d, pos, yaw, seed):
    s = blob(name, 0.5, (0, 0, 0), None, seed=seed, subdiv=2, squash=(w, d, 0.36), jitter=0.08)
    for v in s.data.vertices:  # flat underside: a cap sitting on the block, drooping a little over its edge
        v.co.z = max(v.co.z, -0.04)
    s.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(math.radians(yaw), 4, "Z"))
    s.data.update()
    return paint_faces(s, lambda c, n: SNOW if n.z > 0.35 else SNOW_D)


def icicles(base, ang, width, z, n, seed, ln=0.4, inset=0.45):
    """Fringe of downward cones along the inner face (toward the slime) of a block at the band."""
    r = random.Random(seed)
    a = math.radians(ang)
    f = (-math.cos(a), -math.sin(a))  # toward the centre
    tg = (-math.sin(a), math.cos(a))
    out = []
    for i in range(n):
        t = -width / 2 + width * (i + 0.5) / n
        l = ln * r.uniform(0.55, 1.0)
        x = base[0] + tg[0] * t + f[0] * inset
        y = base[1] + tg[1] * t + f[1] * inset
        ic = cone(f"Icicle{seed}_{i}", 0.07, l, (x, y, z), None, segs=5, rot=(180, 0, 0))
        out.append(paint_faces(ic, lambda c, nn: ICE_HI if nn.z > -0.2 else ICE))
    return out


def drift(name, ang, w, h, seed, dr=0.0):
    a = math.radians(ang)
    s = blob(name, 0.5, (0, 0, 0), None, seed=seed, subdiv=2, squash=(0.9, w, h), jitter=0.1, lumps=0.15)
    s.data.transform(Matrix.Translation(at(ang, dr=dr)) @ Matrix.Rotation(a, 4, "Z"))
    s.data.update()
    stand(s, -0.02)
    return paint_faces(s, lambda c, n: SNOW if n.z > 0.3 else SNOW_D)


# --- back: snowy pine (trunk, three tiers, snow on every tier, a snowball top) ---
px, py, _ = at(90)
parts.append(cylinder("Trunk", 0.12, 0.5, (px, py, 0), BARK, segs=6))
for k, (z, r, h) in enumerate(((0.35, 0.64, 0.95), (0.95, 0.5, 0.85), (1.5, 0.36, 0.8))):
    t = cone(f"Tier{k}", r, h, (px, py, z), None, segs=8)
    gradient(t, PINE_D, PINE)
    parts.append(t)
    sc = cone(f"TierSnow{k}", r * 0.62, h * 0.52, (px, py, z + h * 0.5), None, segs=8)
    for v in sc.data.vertices:  # wavy hem on the snow cap
        if v.co.z < z + h * 0.5 + 0.01:
            a = math.atan2(v.co.y - py, v.co.x - px)
            v.co.z -= 0.06 * (1 + math.sin(a * 4))
    parts.append(paint_faces(sc, lambda c, n: SNOW if n.z > 0.2 else SNOW_D))
parts.append(paint_faces(blob("TreeTop", 0.13, (px, py, 2.36), None, seed=2, subdiv=1), lambda c, n: SNOW))

# --- back corners: three staggered ice blocks with a snow cap and an icicle fringe on the side facing the slime ---
for side in (1, -1):
    ang = 52 if side == 1 else 128
    bx, by, _ = at(ang)
    a = math.radians(ang)
    tx, ty = -math.sin(a) * side, math.cos(a) * side  # along the rim, away from the back
    parts.append(ice_block(f"BlockA{side}", (0.88, 0.88, 0.95), (bx, by, 0), ang + 8 * side))
    parts.append(ice_block(f"BlockB{side}", (0.7, 0.7, 0.72), (bx + tx * 0.04, by + ty * 0.04, 0.9), ang - 18 * side, (5, -4)))
    parts.append(snow_cap(f"CapB{side}", 0.9, 0.84, (bx + tx * 0.04, by + ty * 0.04, 1.58), ang, 10 + side))
    parts += icicles((bx, by), ang, 0.7, 0.9, 5, 20 + side, 0.48, inset=0.47)
    cx, cy = bx + tx * 0.8, by + ty * 0.8  # a small block of its own (its own rigid group, so the stack keeps its size)
    parts.append(ice_block(f"BlockC{side}", (0.52, 0.56, 0.5), (cx, cy, 0), ang - 30 * side, (0, 8 * side)))
    parts.append(snow_cap(f"CapC{side}", 0.6, 0.64, (cx, cy, 0.46), ang, 12 + side))

# --- sides: a block with a snow cap and icicles, and a pair of ice spikes ---
for side in (1, -1):
    ang = 16 if side == 1 else 164
    bx, by, _ = at(ang)
    parts.append(ice_block(f"SideA{side}", (0.72, 0.8, 0.7), (bx, by, 0), ang + 25 * side, (0, 6 * side)))
    parts.append(snow_cap(f"CapS{side}", 0.84, 0.9, (bx, by, 0.66), ang, 30 + side))
    parts += icicles((bx, by), ang, 0.56, 0.66, 4, 40 + side, 0.34, inset=0.4)
    sx, sy, _ = at(ang - 28 * side)
    sp = cone(f"Spike{side}", 0.26, 1.15, (sx, sy, 0), None, segs=6)
    parts.append(paint_faces(sp, lambda c, n: ICE_HI if (n.x + n.y) > 0.3 else ICE))
    sp2 = cone(f"Spike2{side}", 0.16, 0.7, (0, 0, 0), None, segs=6)
    place(sp2, (sx + 0.2 * side, sy - 0.08, 0), 24, ang - 90 * side, 0)
    parts.append(paint_faces(sp2, lambda c, n: ICE_HI if (n.x + n.y) > 0.3 else ICE))

# --- snow drifts between the props and toward the front sides; snowballs ---
for side in (1, -1):
    m = (lambda a: a) if side == 1 else (lambda a: 180 - a)
    parts.append(drift(f"Drift{side}0", m(72), 1.0, 0.5, 50 + side, dr=0.05))
    parts.append(drift(f"Drift{side}1", m(-22), 1.1, 0.55, 52 + side))
    parts.append(drift(f"Drift{side}2", m(-36), 0.6, 0.3, 54 + side, dr=0.1))
    bx, by, _ = at(m(-14), dt=0.0, dr=-0.15)
    parts.append(paint_faces(blob(f"Ball{side}", 0.16, (bx, by, 0.5), None, seed=60 + side, subdiv=2, jitter=0.05),
                             lambda c, n: SNOW if n.z > -0.2 else SNOW_D))

theme_finish("habitat_theme_ice", parts)
