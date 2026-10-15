# volcano: hub volcano (replaces v17 volcano_v3, 56.4 x 40.4 x 57.2 studs). One closed surface of
# revolution: NOTHING sticks out of the cone (v23 gate F1). Lava is vertex colour only, painted
# flush into shallow gullies on the 4 diagonals (WorldLayout.LAVA_YAWS 45/135/225/315 -> Blender
# angles 135/-135/-45/45; the game's lava pools sit at their feet).
# Profile follows the invisible collider tiers (VOLCANO_TIERS 56/46/36/26/18, 8 studs each), so the
# surface is where players stand. Crater: rim at 40.4, inner radius >= 8 at z 40.3 so the game's
# 15-stud Neon "Crater" disc at y 40.3 sits inside; the floor below it is painted lava too.
import math, random
import bmesh
from mathutils import noise, Vector
from lib import *

R = random.Random(7)
SEGS = 44
PROFILE = [(0.0, 28.2), (1.2, 27.4), (4, 25.8), (8, 23.6), (12, 21.6), (13, 20.9), (16, 19.6), (17, 18.4), (20, 17.2),
           (24, 14.8), (25, 14.1), (28, 13.1), (29, 12.1), (32, 11.0), (35, 9.9), (37.6, 9.3), (39.6, 9.1), (40.4, 8.7)]
# (two soft shoulders at ~15-17 and ~27-29 echo the collider tiers without stepping out of them)
CRATER = [(40.4, 8.4), (40.0, 8.1), (39.3, 7.9), (39.0, 6.0), (38.9, 0.0)]  # inner wall, floor
LAVA_ANG = [math.radians(a) for a in (45, 135, -135, -45)]

EARTH, ROCK, ROCK_HI, CHAR = rgb(126, 104, 86), rgb(108, 92, 90), rgb(134, 116, 108), rgb(82, 70, 72)
LAVA_EDGE, LAVA, LAVA_HOT = rgb(214, 70, 34), rgb(255, 128, 36), rgb(255, 206, 84)


def lava_offset(z):
    """wiggle of the lava streak centre line (radians) with height: it meanders down."""
    return 0.10 * math.sin(z * 0.23) + 0.05 * math.sin(z * 0.61 + 1.3)


def lava_amount(ang, z):
    """0..1: how much lava at this point. Streaks run from the rim to ~z 1, wider low down."""
    best = 0.0
    for k, a0 in enumerate(LAVA_ANG):
        d = math.atan2(math.sin(ang - a0 - lava_offset(z + k * 7)), math.cos(ang - a0 - lava_offset(z + k * 7)))
        r = dict(PROFILE).get(z, 15)
        width = (1.6 + 1.6 * (1 - z / 40)) / max(r, 8)  # studs -> radians
        best = max(best, math.exp(-(d / width) ** 2))
    return best


def ridge(a, z):
    return noise.noise(Vector((math.cos(a) * 1.4, math.sin(a) * 1.4, z * 0.05))) + \
        0.5 * noise.noise(Vector((math.cos(a) * 3.5 + 9, math.sin(a) * 3.5, z * 0.12)))


def rim_notch(a):
    return max(0.0, noise.noise(Vector((math.cos(a) * 2.0, math.sin(a) * 2.0, 5.0)))) * 4.0


def strata(a, z):
    """wavy horizontal rock bands every ~5.5 studs: scale cue on the big slope."""
    w = z + 1.2 * math.sin(a * 3 + z * 0.1)
    return 1.0 if (w % 5.5) < 1.1 else 0.0


bm = bmesh.new()
rings = []
for z, r in PROFILE:
    ring = []
    for i in range(SEGS):
        a = i * math.tau / SEGS
        n = ridge(a, z)
        k = 1 + 0.08 * n * (0.6 + 0.4 * z / 40)  # lobes and spurs: asymmetric outline, at most ~2 studs
        k -= 0.04 * lava_amount(a, z) * (0.3 < z < 40.0)  # lava gullies: indent, never proud
        rr = r * (k if 0.3 < z < 40.0 else 1.0)
        zz = z - (rim_notch(a) if z > 40 else 0.0)  # notched rim: cut down, never up
        ring.append(bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
    rings.append(ring)
for z, r in CRATER:
    if r == 0:
        rings.append([bm.verts.new((0, 0, z))])
        continue
    angs = [i * math.tau / SEGS for i in range(SEGS)]
    rings.append([bm.verts.new((math.cos(a) * r, math.sin(a) * r, z - (rim_notch(a) if z > 40 else 0.0))) for a in angs])
for a, b in zip(rings, rings[1:]):
    for i in range(SEGS):
        j = (i + 1) % SEGS
        if len(b) == 1:
            bm.faces.new((a[i], a[j], b[0]))
        else:
            bm.faces.new((a[i], a[j], b[j], b[i]))
bottom = bm.faces.new(list(reversed(rings[0])))
bmesh.ops.triangulate(bm, faces=[bottom])
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

# paint per corner: earthy foot -> rock -> charred top, ridges lighter, lava streaks, crater glow
col = bm.loops.layers.color.new("Col")
for f in bm.faces:
    for lp in f.loops:
        v = lp.vert.co
        z = v.z
        a = math.atan2(v.y, v.x)
        rad = math.hypot(v.x, v.y)
        if z > 38.8 and rad < 8.5 and (rad < 8.45 or z < 38.0):
            # crater: inner wall glows, floor is lava
            c = LAVA_HOT if z < 39.2 else mix(LAVA, LAVA_EDGE, min(1, (z - 39.2) / 1.2))
        else:
            t = z / 40.4
            c = mix(EARTH, ROCK, min(1, t * 3)) if t < 0.33 else mix(ROCK, CHAR, (t - 0.33) / 0.67)
            n = ridge(a, z)
            c = mix(c, ROCK_HI, min(1, max(0, n) * 1.2))  # ridges catch light
            c = mix(c, shade(c, 0.78), max(0, -n) * 0.8)  # valleys darker
            for z0 in (16.0, 28.0):  # terraces: light ledge on top, shadow band below it
                if z0 - 0.6 < z < z0 + 1.6:
                    c = shade(c, 1.18)
                elif z0 - 3.2 < z <= z0 - 0.6:
                    c = shade(c, 0.8)
            L = lava_amount(a, z) if 0.8 < z < 40.5 else 0
            if L > 0.12:
                c = mix(LAVA_EDGE, LAVA, min(1, (L - 0.12) / 0.4))
                if L > 0.7:
                    c = mix(LAVA, LAVA_HOT, (L - 0.7) / 0.3)
        lp[col] = c
o = obj_from_bm("Cone", bm)
finish("volcano", [o])
