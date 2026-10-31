# habitat_theme_space: starry-space theme for the habitat pad (Cosmo, Eclipse, Lunara, Solaris, Nebulon, Star
# Emperor). Props on the back and sides of the rim only (the frame mesh supplies the ring): grey-violet moon rocks
# with craters round the back and sides, two little planets on short stalks at the back (a ringed orange one and a
# teal one), chunky yellow stars floating over the side rocks and a few small ones. The front arc stays clear.
import math, random
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
import bmesh
from lib import *
from models._habitat_overlay import *
from models._habitat_theme_bits import *
from models._phoenix_pad import lathe

MOON_LO, MOON_HI = rgb(170, 160, 212), rgb(228, 224, 250)  # lifted: the Roblox look darkens violet-greys a lot
CRATER, CRATER_RIM = rgb(138, 126, 188), rgb(236, 232, 252)
STAR, STAR_D = rgb(255, 240, 110), rgb(254, 222, 84)  # lows near the base or yellow goes brown in game
RINGED, RINGED_B = rgb(255, 170, 80), rgb(255, 214, 130)
TEAL, TEAL_B = rgb(80, 210, 220), rgb(170, 240, 240)
RING = rgb(250, 236, 180)
STALK = rgb(176, 168, 214)
parts = []


def moon_rock(name, r, ang, seed, h=0.8, w=1.0, dt=0.0, craters=2):
    """Lumpy moon rock with craters (a dished lathe ring cast onto the side facing the slime)."""
    a = math.radians(ang)
    b = blob(name, r, (0, 0, 0), None, seed=seed, subdiv=2, squash=(0.95, w, h), jitter=0.1, lumps=0.12)
    stand(b, -0.03)
    b.data.transform(Matrix.Translation(at(ang, dt=dt)) @ Matrix.Rotation(a, 4, "Z"))
    b.data.update()
    gradient(b, MOON_LO, MOON_HI)
    out = [b]
    bm = bmesh.new()
    bm.from_mesh(b.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    rr = random.Random(seed)
    inward = Vector((-math.cos(a), -math.sin(a), 0))
    tg = Vector((-math.sin(a), math.cos(a), 0))
    base = Vector(at(ang, dt=dt))
    zs = [v.co.z for v in b.data.vertices]
    for k in range(craters):
        # one big crater high on one side, a smaller one low on the other: a level pair reads as a pair of eyes
        side = 1 if (seed + k) % 2 else -1
        t = side * r * (0.3 + 0.15 * k) + rr.uniform(-0.05, 0.05)
        z = min(zs) + (max(zs) - min(zs)) * (0.66 if k == 0 else 0.3)
        o = base + tg * t + Vector((0, 0, z)) + inward * 3
        d = -inward
        hit, nrm, _, _ = tree.ray_cast(o, d, 6)
        if hit is None:
            continue
        cr = r * (0.42 if k == 0 else 0.26)
        prof = [(0, -0.03), (cr * 0.72, 0.0), (cr, 0.05), (cr * 1.25, -0.06), (0, -0.06)]
        c = lathe(f"{name}Crater{k}", prof, segs=6,
                  color_fn=lambda i, kk, zz: CRATER if i == 0 else (CRATER_RIM if i in (1, 2) else MOON_LO))
        c.data.transform(Matrix.Translation(hit - nrm * 0.01) @ nrm.to_track_quat("Z", "Y").to_matrix().to_4x4())
        c.data.update()
        out.append(c)
    return out


def planet(name, pos, r, col, band, ring=False, tilt=20):
    """Planet ball with two pale bands; ring = a flat tilted disc ring round it."""
    p = blob(name, r, pos, None, seed=3, subdiv=2, jitter=0.0)
    cz = pos[2]
    paint_faces(p, lambda c, n: band if abs(c.z - cz - r * 0.15) < r * 0.16 or abs(c.z - cz + r * 0.45) < r * 0.12 else
                (shade(col, 1.08) if n.z > 0.3 else col))
    out = [p]
    if ring:
        prof = [(r * 1.25, -0.03), (r * 1.75, -0.02), (r * 1.75, 0.02), (r * 1.25, 0.03)]
        bm = bmesh.new()
        segs = 14
        rows = [[bm.verts.new((rr * math.cos(k * math.tau / segs), rr * math.sin(k * math.tau / segs), z)) for k in range(segs)]
                for rr, z in prof]
        cl = bm.loops.layers.color.new("Col")
        for i in range(4):
            a, b2 = rows[i], rows[(i + 1) % 4]
            for k in range(segs):
                f = bm.faces.new((a[k], a[(k + 1) % segs], b2[(k + 1) % segs], b2[k]))
                for lp in f.loops:
                    lp[cl] = RING if i in (0, 2) else shade(RING, 0.85)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        from lib.shapes import obj_from_bm
        rg = obj_from_bm(f"{name}Ring", bm)
        rg.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(math.radians(tilt), 4, "X") @ Matrix.Rotation(math.radians(10), 4, "Y"))
        rg.data.update()
        out.append(rg)
    return out


def star(name, pos, ang, r, th=0.16, spin=0):
    s = star_slab(name, r, r * 0.46, th, (0, 0, 0), STAR, rim=STAR_D)
    s.data.transform(Matrix.Translation(pos) @ Matrix.Rotation(math.radians(ang + 90), 4, "Z") @ Matrix.Rotation(math.radians(spin), 4, "Y"))
    s.data.update()
    return s


# --- back: two planets on short stalks, each rising out of a moon rock ---
for side, ang, col, band, ring, z, r in ((1, 66, RINGED, RINGED_B, True, 2.25, 0.37), (-1, 114, TEAL, TEAL_B, False, 1.95, 0.47)):
    parts += moon_rock(f"StalkRock{side}", 0.4, ang, 10 + side, h=0.7, craters=1)
    x, y, _ = at(ang)
    parts.append(tube(f"Stalk{side}", [(x, y, 0.2), (x + 0.03 * side, y, z * 0.5), (x, y, z - r * 0.8)], [0.09, 0.075, 0.065], STALK, segs=6))
    parts += planet(f"Planet{side}", (x, y, z), r, col, band, ring=ring)

# --- back centre and corners: bigger cratered rocks ---
parts += moon_rock("BackRock", 0.5, 90, 1, h=1.05, w=1.15, craters=2)
for side in (1, -1):
    parts += moon_rock(f"CornerRock{side}", 0.5, 90 - 50 * side, 3 + side, h=1.25, w=1.1, craters=2)
    parts += moon_rock(f"SideRock{side}", 0.44, 90 - 78 * side, 5 + side, h=1.0, w=1.15, craters=1)
    parts += moon_rock(f"LowRock{side}", 0.3, 90 - 112 * side, 7 + side, h=0.8, w=1.2, craters=0)
    parts += moon_rock(f"Pebble{side}", 0.18, 90 - 128 * side, 9 + side, h=0.7, w=1.2, craters=0)

# --- stars: chunky ones floating over the side rocks, small ones round the planets ---
for side in (1, -1):
    ang = 90 - 78 * side
    x, y, _ = at(ang)
    parts.append(star(f"BigStar{side}", (x, y, 1.6), ang, 0.4, th=0.18, spin=14 * side))
    x, y, _ = at(90 - 50 * side)  # right over the corner rock (same rigid group, no extra width)
    parts.append(star(f"SmallStar{side}", (x, y, 1.8 if side == 1 else 2.0), 90 - 50 * side, 0.18, th=0.1))
x, y, _ = at(90, dr=0.0)
parts.append(star("TopStar", (x, y, 2.45), 90, 0.2, th=0.1, spin=10))

theme_finish("habitat_theme_space", parts)
