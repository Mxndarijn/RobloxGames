# claw_prize_capsule: the gacha prize capsule the Exclusive Shop claw machine grabs after a purchase that has no own
# display mesh (games/steal-a-slime ShopDisplayFx makePrize, CAPSULE_SIZE 1.3 studs). Replaces the plain lilac Ball.
# A round capsule: lilac "glass" dome on top (opaque, vertex colour only: light lilac + a bold white highlight streak),
# a saturated mint bottom half, a gold band on the seam and a gold star on the front of the bottom half.
# Origin bottom centre, 1 BU = 1 stud, front faces -Y. Smooth shaded, vertex colours, one mesh.
# The game spins it (SPIN_RPM), so the star shows every turn. MeshPart.Color multiplies vertex colours: keep it white.
import math
from models._pet_mounts import *
from models._pet_mounts_extra import rings_mesh, lathe_rings, place

R = 0.62  # capsule radius (the band sticks out to ~0.68: 1.3 across with the band)
ZC = R  # centre height: the capsule stands on z = 0
M = 24  # lathe segments

GLASS_LO, GLASS, GLASS_HI = rgb(200, 176, 246), rgb(218, 200, 252), rgb(238, 230, 255)
MINT_LO, MINT, MINT_HI = rgb(74, 206, 164), rgb(72, 220, 172), rgb(140, 246, 206)
GOLD_LO, GOLD_C, GOLD_HI = rgb(250, 184, 60), rgb(255, 204, 64), rgb(255, 240, 150)
WHITE = rgb(255, 255, 255)
LIGHT = Vector((-0.45, -0.6, 0.66)).normalized()  # kit key light side (front-left, up): where the gloss sits


def circle(t):
    return (math.cos(t), math.sin(t))


def hemi(name, el0, el1, n, poles):
    """sphere band from elevation el0 to el1 (radians, ascending), n rings, closed with the given poles."""
    prof = [(R * math.cos(el0 + (el1 - el0) * i / n), ZC + R * math.sin(el0 + (el1 - el0) * i / n)) for i in range(n + 1)]
    return rings_mesh(name, lathe_rings(circle, prof, M), poles=poles)


# glass dome: from just under the seam (hidden by the band) to near the top pole
dome = hemi("Dome", -0.06, math.radians(82), 7, (None, Vector((0, 0, ZC + R))))


def glass(co, n):
    h = clamp((co.z - ZC) / R)
    c = mixn([(0, GLASS_LO), (0.45, GLASS), (1, GLASS_HI)], h)
    c = mix(c, GLASS_HI, sstep(0.55, 0.9, n.dot(LIGHT)) * 0.6)  # soft sheen toward the light
    return c
paint(dome, glass)

# saturated mint bottom half: from near the bottom pole up to the seam
base = hemi("Base", math.radians(-84), 0.0, 6, (Vector((0, 0, ZC - R)), None))


def mint(co, n):
    h = clamp((co.z) / ZC)
    c = mixn([(0, MINT_LO), (0.55, MINT), (1, MINT_HI)], h)
    return mix(c, MINT_HI, sstep(0.6, 0.95, n.dot(LIGHT)) * 0.5)
paint(base, mint)

# gold band on the seam: a torus
bm = bmesh.new()
RT, rt, NS = R - 0.005, 0.06, 5
rings = []
for k in range(M):
    a = k * math.tau / M
    ring = []
    for j in range(NS):
        b = j * math.tau / NS
        rr = RT + rt * math.cos(b)
        ring.append(bm.verts.new((rr * math.cos(a), rr * math.sin(a), ZC + rt * 1.15 * math.sin(b))))
    rings.append(ring)
for k in range(M):
    r0, r1 = rings[k], rings[(k + 1) % M]
    for j in range(NS):
        i = (j + 1) % NS
        bm.faces.new((r0[j], r1[j], r1[i], r0[i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
band = obj_from_bm("Band", bm, smooth=True)
paint(band, lambda co, n: mixn([(-1, GOLD_LO), (0.2, GOLD_C), (1, GOLD_HI)], n.z * 0.7 + n.dot(LIGHT) * 0.5))

# chunky faceted gold star on the front of the bottom half: a 10-point outline with a raised centre (front) and a flat
# back sunk into the shell, tilted to face out along the sphere normal
EL = math.radians(-26)


def make_star(name, yaw):
    """star at the front (yaw 0) or turned round the capsule by yaw radians"""
    star = facet_star(name, 0.24, 0.105, tip=0.12, back=0.1, rim=0.03)
    place(star, Matrix.Rotation(yaw, 4, "Z") @ Matrix.Translation((0, -(R - 0.035) * math.cos(EL), ZC + (R - 0.035) * math.sin(EL))) @ Matrix.Rotation(-EL, 4, "X"))
    paint(star, lambda co, n: mixn([(-1, GOLD_LO), (0.3, GOLD_C), (1, GOLD_HI)], n.dot(Vector((co.x, co.y, 0)).normalized()) * 0.6 + n.z * 0.5 + n.dot(LIGHT) * 0.4), smooth=False)
    return star


star = make_star("Star", 0.0)
star_back = make_star("StarBack", math.pi)  # it spins: the back gets one too

# bold white highlight streak on the glass (front-left, curving with the dome) + a small dot
streak_pts, streak_r = [], []
for i in range(7):
    t = i / 6
    az = math.radians(222 + 42 * t)  # around the front-left
    el = math.radians(18 + 42 * t)
    rr = R + 0.012
    streak_pts.append((rr * math.cos(el) * math.cos(az), rr * math.cos(el) * math.sin(az), ZC + rr * math.sin(el)))
    streak_r.append(0.03 + 0.06 * math.sin(math.pi * t))
streak = tube("Streak", streak_pts, streak_r, segs=6)
paint(streak, lambda co, n: WHITE)
az, el = math.radians(280), math.radians(30)
dot = sphere("Dot", 0.05, (R * math.cos(el) * math.cos(az), R * math.cos(el) * math.sin(az), ZC + R * math.sin(el)), subdiv=1)
paint(dot, lambda co, n: WHITE)

o = ship("claw_prize_capsule", [dome, base, band, star, star_back, streak, dot], fit=False)
lo, hi = bbox([o])
print("CAPSULE size=%.3f x %.3f x %.3f (target 1.3 +-10%%)" % (hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
