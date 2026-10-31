# obby_goo_ring: the Obby's Goo Ring portal (steal-a-slime). A standing ring of slime rising out of a goo puddle,
# drips hanging off its lower sides, bubbles on top. Ring in the XZ plane (you walk through it along Y), front -Y.
# Built at the yard size (ring 5.2, tube 1.4); the game scales the MeshPart for the smaller ring home.
# The swirl inside is a separate mesh (obby_goo_swirl) so the game can turn it.
# GOO_RING_EYES=1 builds the variant with two slime eyes on the top front.
import math, os
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo, frame_quat
from mathutils import Vector

R = 5.2  # ring centre-line radius
T = 1.7  # tube thickness
CZ = R + T * 0.42  # ring centre height: the bottom of the tube sinks into the puddle
EYES = os.environ.get("GOO_RING_EYES") == "1"

DEEP = hexc("#1F6E25")
GOO = hexc("#4FC234")
HI = hexc("#A8F062")
GLOSS = hexc("#D9FFB0")


def on_ring(a, out=0.0, z=0.0, y=0.0):
    """point on the ring's centre line at angle a (0 = right, pi/2 = top), pushed `out` from the centre line."""
    return Vector(((R + out) * math.cos(a), y, CZ + (R + out) * math.sin(a) + z))


def tube_r(a):
    """tube radius round the ring: fatter at the bottom (goo sags), a slow lumpy wobble."""
    sag = max(0.0, -math.sin(a))
    lump = 0.05 * math.sin(5 * a + 0.7) + 0.03 * math.sin(11 * a + 2.1)
    # goo gathered in a few fat bulges (angle, strength, width)
    for c, k, w in ((2.35, 0.2, 0.28), (0.55, 0.16, 0.22), (-0.35, 0.14, 0.25), (3.55, 0.18, 0.3)):
        d = math.atan2(math.sin(a - c), math.cos(a - c))
        lump += k * math.exp(-(d / w) ** 2)
    return T / 2 * (0.88 + 0.25 * sag ** 1.5 + lump)


balls = []
N = 64
for i in range(N):
    a = i / N * math.tau
    r = tube_r(a)
    # slightly flattened front-back, so the face of the ring reads wide and the profile stays round
    balls.append(Ball(on_ring(a), (r * 1.05, r * 0.95, r * 1.05)))

# Puddle: a wide flat lens with lobes, the ring's foot fused into it.
balls.append(Ball((0, 0, 0.18), (2.9, 2.2, 0.32)))
for k, (x, y, s) in enumerate(((-2.4, -0.9, 1.3), (2.1, -1.3, 1.1), (1.6, 1.5, 1.2), (-1.8, 1.3, 1.0), (0.2, -2.1, 0.9))):
    balls.append(Ball((x, y, 0.14), (s, s * 0.8, 0.24)))
# The foot: goo thickening where the ring meets the puddle.
for x in (-1.2, -0.5, 0.5, 1.2):
    balls.append(Ball((x, 0, 0.55), (0.9, 0.85, 0.6)))

# Drips: off the outer sides (side +1, from the outer edge, clear of the ring below) and from the inside of the top
# arch (side -1, hanging into the opening over the swirl). Lens chains, narrowing, with a fat round drop.
DRIPS = ((-14, 2.3, 1), (9, 1.4, 1), (27, 0.8, 1), (163, 1.0, 1), (187, 2.7, 1), (203, 1.5, 1),
         (64, 0.7, -1), (83, 2.5, -1), (117, 1.2, -1))
if EYES:  # no drip between the eyes (it reads as a runny nose): two off to the sides instead
    DRIPS = DRIPS[:6] + ((58, 1.9, -1), (124, 1.3, -1), (108, 0.6, -1))


def surface_out(a, side):
    """outer (side 1) or inner (side -1) edge of the tube at angle a, and the angle-dependent hang start below it."""
    return on_ring(a, out=side * tube_r(a) * 0.55) + Vector((0, -0.05, -tube_r(a) * 0.55))


for deg, length, side in DRIPS:
    a = math.radians(deg)
    top = surface_out(a, side)
    steps = max(3, int(length / 0.2))
    for s_ in range(steps + 1):
        t = s_ / steps
        # wide where it leaves the tube, a thin neck, then the drop
        w = 0.44 * (1 - t) ** 1.6 + 0.12
        balls.append(Ball(top + Vector((0, 0, -length * t)), (w, w * 0.9, 0.2)))
    balls.append(Ball(top + Vector((0, 0, -length - 0.2)), (0.36, 0.34, 0.42)))

ring = metaball_mesh("GooRing", balls, resolution=0.13, tris=5200, clamp_z=0.0)


def goo_color(co, n):
    # dark at the bottom, bright goo higher up; the inside of the ring a shade darker for depth;
    # a glossy highlight on the faces turned to the sky, strongest on the top of the ring.
    h = max(0.0, min(1.0, co.z / (CZ + R)))
    c = mix(DEEP, GOO, min(1.0, 0.15 + h * 1.25))
    to_centre = Vector((-co.x, 0, CZ - co.z))
    if to_centre.length > 1e-6 and co.z > 0.5:
        inward = max(0.0, n.dot(to_centre.normalized()))
        c = mix(c, shade(DEEP, 0.95), inward * 0.55)
    # gloss: faces turned up and a little to the front catch a pale streak
    g = n.dot(Vector((0, -0.45, 0.89)))
    if g > 0.45:
        c = mix(c, HI, min(1.0, (g - 0.45) / 0.4) * (0.4 + 0.5 * h))
    if g > 0.9:
        c = mix(c, GLOSS, (g - 0.9) / 0.1 * 0.6)
    return c


parts = [paint_goo(ring, goo_color)]

# Bubbles in the goo: a few glossy domes sunk into the tube's front.
for k, (deg, out, s_) in enumerate(((58, 0.2, 0.5), (104, 0.18, 0.36), (152, 0.08, 0.42), (14, 0.1, 0.34), (222, 0.0, 0.3))):
    a = math.radians(deg)
    p = on_ring(a, out=out * T, y=-tube_r(a) * 0.92)
    parts.append(blob(f"Bub{k}", s_, tuple(p), mix(HI, GLOSS, 0.35), subdiv=2, squash=(1, 0.55, 1), jitter=0, seed=k))
    parts.append(blob(f"BubHi{k}", s_ * 0.28, tuple(p + Vector((s_ * 0.32, -s_ * 0.5, s_ * 0.38))), hexc("#FFFFFF"),
                      subdiv=1, squash=(1, 0.5, 1), jitter=0, seed=k))

if EYES:
    # Two slime eyes on the top front, looking down at whoever walks up.
    for side in (-1, 1):
        a = math.radians(90 - side * 13)
        p = on_ring(a, out=0.1, y=-tube_r(a) * 0.8)
        parts.append(blob(f"Eye{side}", 0.82, tuple(p), hexc("#FFFFFF"), subdiv=3, squash=(0.86, 0.5, 1.0), jitter=0))
        # the pupil's front sits just proud of the white's; set low, looking down at whoever walks up
        pp = p + Vector((side * -0.05, -0.3, -0.18))
        parts.append(blob(f"Pupil{side}", 0.46, tuple(pp), hexc("#14261A"), subdiv=2, squash=(0.86, 0.3, 1.0), jitter=0))
        gp = pp + Vector((0.14, -0.12, 0.16))
        parts.append(blob(f"Glint{side}", 0.15, tuple(gp), hexc("#FFFFFF"), subdiv=1, squash=(1, 0.6, 1), jitter=0))
        cp = on_ring(math.radians(90 - side * 30), out=-0.35, y=-tube_r(a) * 0.9)
        parts.append(blob(f"Cheek{side}", 0.32, tuple(cp), hexc("#F59BB8"), subdiv=2, squash=(1.2, 0.35, 0.7), jitter=0))

finish("obby_goo_ring_eyes" if EYES else "obby_goo_ring", parts)
