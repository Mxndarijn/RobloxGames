# Base concept (design sketch, not an asset): THE SLIMEWOOD TREEHOUSE.
# A giant hollow tree. Floor 1 is a round room inside the flared stump, among the roots, with a round plank door on
# -Y; the merge vat and the lock button stand either side of the door inside, the spawn (0, -12.5) is on the walkway
# between the door and the trunk. You climb a spiral ramp INSIDE the hollow trunk (inner radius 8.5, ramp 6.8 wide,
# one turn per floor, 15 studs headroom); an arch in the trunk opens onto each floor at the front. Floors 2-4 are
# plank cabins round the trunk, each a lopsided circle that grows wider upwards (like a crown), so the tree gets
# its silhouette from the stack. A leafy canopy and a bird nest with the mascot cap whatever floor is on top.
# Owner exit: the hollow-branch slide, a bark tube that curls down the back from the top cabin into the moat.
# Env: FLOORS, CUT (see _base_concept_common).
import math

import bmesh

from lib import blob, cylinder, obj_from_bm, rgb, shade, mix, tube
from models._base_concept_common import *

BARK = rgb(160, 110, 76)
BARK_L = rgb(198, 142, 94)
PLANK = rgb(226, 174, 112)
PLANK_D = rgb(198, 146, 94)
DECK = rgb(206, 156, 104)
TEAL = rgb(70, 196, 186)
RIMS = [ROOF, TEAL, BUTTER, PINK]
LEAF = rgb(124, 204, 92)
LEAF_L = rgb(176, 232, 112)
LEAF_D = rgb(96, 166, 84)
GLOW = rgb(255, 226, 132)
RAMP = rgb(250, 196, 90)  # the climb, bright so it reads in the cut-away

TRUNK_IN, TRUNK_OUT = 8.5, 10.5
STUMP_IN = 27.0
# Floors 1-2 are inside the bark trunk; 3-4: cabin circle radius and centre offset (lopsided, wider upwards), pad ring radius round the trunk.
CABIN = {1: (STUMP_IN, (0.0, 0.0)), 2: (STUMP_IN, (0.0, 0.0)), 3: (31.0, (3.2, -1.8)), 4: (32.0, (-3.0, 2.6))}
PAD_R = {1: 19.0, 2: 19.0, 3: 19.5, 4: 20.0}
SEG = 40


def rad_at(f, a):
    """Inner wall radius of cabin f along the ray from the trunk centre at angle a."""
    rc, (ox, oy) = CABIN[f]
    ux, uy = math.cos(math.radians(a)), math.sin(math.radians(a))
    d = ux * ox + uy * oy
    return d + math.sqrt(d * d - (ox * ox + oy * oy) + rc * rc)


def lop_ring(name, f, r_in_fn, r_out_fn, z0, h, cols, into="shell", gap=None):
    """A ring whose radii vary with angle; segments alternate between cols (plank stripes)."""
    bms = [bmesh.new() for _ in cols]
    for i in range(SEG):
        a1, a2 = i * 360 / SEG, (i + 1) * 360 / SEG
        mid = (a1 + a2) / 2
        if gap and (mid - gap[0]) % 360 <= (gap[1] - gap[0]) % 360:
            continue
        bm = bms[i % len(cols)]
        pts = []
        for r_fn in (r_in_fn, r_out_fn):
            for a in (a1, a2):
                pts.append(polar(r_fn(a), a))
        (i1, i2, o1, o2) = pts
        vs = [bm.verts.new(p) for p in (
            (*i1, z0), (*i2, z0), (*o2, z0), (*o1, z0), (*i1, z0 + h), (*i2, z0 + h), (*o2, z0 + h), (*o1, z0 + h))]
        for fc in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            bm.faces.new([vs[j] for j in fc])
    for k, bm in enumerate(bms):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        add(obj_from_bm(f"{name}{k}", bm, cols[k]), into=into)


def revolve(name, profile, col, segs=32, into="shell", lo=None, gap=None):
    """A closed (r, z) profile spun round Z; gap = (from, to) degrees left open."""
    bm = bmesh.new()
    rings = []
    for k in range(segs):
        a = k * math.tau / segs
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile])
    n = len(profile)
    for k in range(segs):
        A, B = rings[k], rings[(k + 1) % segs]
        mid = (k + 0.5) * 360 / segs
        if gap and (mid - gap[0]) % 360 <= (gap[1] - gap[0]) % 360:
            continue
        for j in range(n):
            bm.faces.new((A[j], A[(j + 1) % n], B[(j + 1) % n], B[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), lo if lo else None, col if lo else None, into)


def window(name, r, a, z, size=1.8):
    rot = (90, 0, a + 90)
    x, y = polar(r - 0.1, a)
    S(cylinder(name + "F", size + 0.45, 0.35, (x, y, z), BARK, segs=12, rot=rot))
    x, y = polar(r + 0.05, a)
    S(cylinder(name, size, 0.35, (x, y, z), GLOW, segs=12, rot=rot))


def puff(name, r, pos, col=LEAF, seed=0):
    S(blob(name, r, pos, col, seed=seed, subdiv=2, squash=(1, 1, 0.8), jitter=0.08), shade(col, 0.72), mix(col, LEAF_L, 0.6))


plot_foot(moat=True, door_r=STUMP_IN + 2.5, bridge_len=8.0)

# ---- Floors 1-2: rooms inside the fat bark trunk (roots, knot-hole windows); the doorway is on floor 1 ----
z1 = top(1)
BARK_FLOORS = min(FLOORS, 2)
ring_wall("StumpDeck", TRUNK_OUT, STUMP_IN, 0.75, 0.25, DECK, segs=48, into=None)
disc("ShaftFloor", TRUNK_IN, 0.25, (0, 0, 0.75), DECK, segs=24)
DOOR_GAP = (-90 - 10, -90 + 10)
inner = lambda a: STUMP_IN
outer = lambda a: STUMP_IN + 2.6
bark_top = top(BARK_FLOORS + 1)
# See-through rule: every floor is a low bark wall, a glass band and a bark top band, so the slimes always show.
TREE_GLASS = mix(GOO_HI, rgb(190, 236, 210), 0.5)
for f in range(1, BARK_FLOORS + 1):
    zf = 0.7 if f == 1 else top(f)
    g = DOOR_GAP if f == 1 else None
    lop_ring(f"StumpKick{f}", 1, inner, outer, zf, top(f) + 3.0 - zf, [BARK, shade(BARK, 0.88)], gap=g)
    lop_ring(f"StumpGlass{f}", 1, lambda a: STUMP_IN + 1.0, lambda a: STUMP_IN + 1.4, top(f) + 3.0, FLOOR_H - 5.5,
             [TREE_GLASS], into="glass", gap=g)
    lop_ring(f"StumpBand{f}", 1, inner, outer, top(f) + FLOOR_H - 2.5, 2.5, [BARK, shade(BARK, 0.88)])
    for k in range(12):
        a = -90 + 15 + k * 30
        disc(f"StumpPost{f}_{k}", 0.9, FLOOR_H - 5.5, (*polar(STUMP_IN + 1.9, a), top(f) + 3.0), BARK_L, segs=8, into="shell")
revolve("StumpFlare", [(STUMP_IN + 2.4, 0.5), (STUMP_IN + 5.5, 0.5), (STUMP_IN + 2.4, 6.0)], BARK, segs=40, gap=DOOR_GAP)
# a tapered bark skin over the trunk walls: fat at the roots, slimmer at the top; ridges for bark
skin_r = lambda z: STUMP_IN + 4.4 - 2.6 * min(z / 33.0, 1.0)
for nm, z0, z1_, g in (("SkinLo", 0.6, 4.0, DOOR_GAP),):
    revolve(nm, [(STUMP_IN + 2.5, z0), (skin_r(z0), z0), (skin_r(z1_), z1_), (STUMP_IN + 2.5, z1_)], BARK, segs=40,
            lo=shade(BARK, 0.82), gap=g)
revolve("StumpLip", [(STUMP_IN - 0.2, bark_top - 1.0), (STUMP_IN + 2.6 + 0.8 * (FLOORS < 2), bark_top - 1.0), (STUMP_IN + 2.6 + 0.8 * (FLOORS < 2), bark_top),
                     (STUMP_IN - 0.2, bark_top)], BARK_L)
for k, a in enumerate((-50, -15, 25, 70, 115, 160, 205, 240)):
    p0, p1, p2 = polar(STUMP_IN + 2.0, a), polar(STUMP_IN + 5.0, a + 4), polar(STUMP_IN + 7.2, a + 9)
    S(tube(f"Root{k}", [(*p0, 5.5), (*p1, 2.6), (*p2, 0.3)], [1.9, 1.3, 0.6], BARK, segs=8), BARK, BARK_L)
fy = -(STUMP_IN + 4.4 - 2.6 * 6.0 / 33.0 + 0.3)  # on the bark skin
ring = [(5.6 * math.cos(math.radians(t)), fy, 6.0 + 5.6 * math.sin(math.radians(t))) for t in range(-15, 196, 15)]
add(tube("DoorFrame", ring, [0.6] * len(ring), BARK_L, segs=6))
add(cylinder("Door", 5.0, 0.8, (-9.5, fy - 2.6, 6.0), PLANK, segs=16, rot=(90, 0, 40)), shade(PLANK, 0.85), PLANK)
add(blob("DoorKnob", 0.6, (-8.4, fy - 4.2, 6.0), BUTTER, subdiv=1, jitter=0))
vx, vy = polar(20.0, -62)
vat(vx, vy, z1)
lx, ly = polar(20.0, -118)
lock_button(lx, ly, z1)
avatar(0, -12.5, z1)
avatar(4, -STUMP_IN - 9.0, 1.3, rgb(230, 120, 90))
pad_ring(1, PAD_R[1], n=8, a0=-90 + 60, arc=240, trim=LEAF)
if FLOORS >= 2:
    z2 = top(2)
    ring_wall("Deck2", TRUNK_OUT, STUMP_IN, z2 - 1.0, 1.0, DECK, segs=48, into=None)
    pad_ring(2, PAD_R[2], n=8, a0=-90 + 22.5, trim=LEAF)
    for k, a in enumerate((-20, 200)):
        p0, p1 = polar(STUMP_IN + 2.0, a), polar(STUMP_IN + 8.0, a + 5)
        S(tube(f"Stub{k}", [(*p0, z2 + 10), (*p1, z2 + 14)], [1.4, 0.7], BARK, segs=6))
        puff(f"StubLeaf{k}", 3.4, (*polar(STUMP_IN + 9.0, a + 7), z2 + 15.0), LEAF, seed=40 + k)

if FLOORS >= 3:
    for k, a in enumerate((-40, 95, 215)):
        zb = top(3) - 3.0
        p0, p1, p2 = polar(STUMP_IN, a), polar(STUMP_IN + 7.0, a + 4), polar(STUMP_IN + 11.0, a + 10)
        S(tube(f"Arm{k}", [(*p0, zb - 4), (*p1, zb + 1), (*p2, zb + 8)], [2.2, 1.5, 0.8], BARK, segs=8), shade(BARK, 0.85), BARK)
        for j, (dr, da, dz, rad) in enumerate(((11.5, 11, 0, 5.0), (9.0, 18, 1.5, 4.0), (13.0, 2, 2, 3.6))):
            puff(f"ArmLeaf{k}_{j}", rad, (*polar(STUMP_IN + dr, a + da), zb + dz), [LEAF, LEAF_L, LEAF_D][j], seed=80 + k * 3 + j)

# ---- the shaft: a bark tube up the middle with the spiral ramp, an arch onto every floor at the front ----
ARCH = (-90 - 26, -90 + 26)
crown_z = top(FLOORS) + FLOOR_H
for f in range(1, FLOORS + 1):
    z = top(f)
    ring_wall(f"TrunkLo{f}", TRUNK_IN, TRUNK_OUT, z - 0.3, 9.3, BARK_L, segs=24, gap=ARCH, a0=-90 + 7.5)
    ring_wall(f"TrunkHi{f}", TRUNK_IN, TRUNK_OUT, z + 9.0, FLOOR_H - 9.0, BARK_L, segs=24, a0=-90 + 7.5)
    pts = [polar(TRUNK_OUT + 0.3, -90 + 25 * math.cos(math.radians(t))) + (z + 5.2 + 3.6 * math.sin(math.radians(t)),)
           for t in range(0, 181, 20)]
    S(tube(f"Arch{f}", [(p[0], p[1], p[2]) for p in pts], [0.55] * len(pts), BARK, segs=6))
    if f < FLOORS:
        helix_ramp(f"Ramp{f}", 1.5, TRUNK_IN - 0.2, z, FLOOR_H, -90, 360, RAMP, segs=32)
ring_wall("TrunkCrown", TRUNK_IN - 0.5, TRUNK_OUT - 0.5, crown_z, 11, BARK, segs=24)
disc("ShaftLid", TRUNK_IN, 0.6, (0, 0, crown_z - 1.0), DECK, segs=24)
disc("Post", 1.5, crown_z - 1.0, (0, 0, 0.5), BARK, segs=12)

# ---- floors 3-4: lopsided plank cabins up in the crown, wider than the trunk, on struts, wrapped in leaves ----
for f in range(3, FLOORS + 1):
    z = top(f)
    lop_ring(f"Deck{f}", f, lambda a: TRUNK_OUT, lambda a, f=f: rad_at(f, a) + 1.6, z - 1.0, 1.0, [DECK, shade(DECK, 0.9)],
             into=None)
    lop_ring(f"Wall{f}", f, lambda a, f=f: rad_at(f, a), lambda a, f=f: rad_at(f, a) + 1.0, z, 3.0,
             [PLANK, PLANK_D])
    lop_ring(f"Glass{f}", f, lambda a, f=f: rad_at(f, a) + 0.3, lambda a, f=f: rad_at(f, a) + 0.7, z + 3.0,
             FLOOR_H - 5.2, [TREE_GLASS], into="glass")
    for k in range(12):
        a = k * 30
        disc(f"CabinPost{f}_{k}", 0.6, FLOOR_H - 5.2, (*polar(rad_at(f, a) + 0.5, a), z + 3.0), PLANK_D, segs=6,
             into="shell")
    rim = RIMS[(f - 3) % len(RIMS)]
    lop_ring(f"Rim{f}", f, lambda a, f=f: rad_at(f, a) - 0.2, lambda a, f=f: rad_at(f, a) + 1.8, z + FLOOR_H - 2.2, 1.4,
             [rim])
    lop_ring(f"DeckRim{f}", f, lambda a, f=f: rad_at(f, a) + 1.0, lambda a, f=f: rad_at(f, a) + 1.9, z - 1.6, 1.2,
             [BARK_L])
    below = (lambda a: STUMP_IN + 2.0) if f == 3 else (lambda a, g=f - 1: rad_at(g, a) + 1.9)
    for k in range(12):
        a = k * 30 + 15
        r = rad_at(f, a) + 1.0
        if r > below(a) + 0.8:
            p0, p1 = polar(r - 0.4, a), polar(below(a) - 0.6, a)
            S(tube(f"Strut{f}_{k}", [(*p0, z - 1.4), (*p1, z - 3.0 - (r - below(a)) * 1.2)], [0.5, 0.5], BARK, segs=6))
    pad_ring(f, PAD_R[f], n=8, a0=-90 + 22.5, trim=LEAF)
    # leaf clumps hugging the cabin at its rim, so the cabins sit in the crown
    for k in range(5):
        a = k * 360 / 5 + f * 23
        r = rad_at(f, a) + 2.4
        puff(f"Hug{f}_{k}", 3.2 + (k % 3) * 0.6, (*polar(r, a), z - 2.0 - (k % 2)), [LEAF, LEAF_L, LEAF_D][k % 3],
             seed=60 + f * 10 + k)

# ---- the crown: canopy puffs that hang over the edge of the top floor, bird nest + mascot ----
cr = CABIN[FLOORS][0]
revolve("Roof", [(TRUNK_OUT, crown_z + 6.0), (cr + 3.0, crown_z - 0.5), (cr + 3.0, crown_z - 1.6),
                 (TRUNK_OUT, crown_z - 1.0)], LEAF_D, segs=36)
rr = random.Random(3)
cz = crown_z + 7.0  # the canopy sits above the top floor's glass, never over it
for k in range(10):
    a = k * 36 + rr.uniform(-6, 6)
    puff(f"Canopy{k}", rr.uniform(7.5, 9.0), (*polar(cr + 1.0 + rr.uniform(-1, 1.5), a), cz + 2.0 + rr.uniform(-1, 2)),
         [LEAF_D, LEAF, LEAF_D][k % 3], seed=k)
for k in range(8):
    a = k * 45 + 20
    puff(f"CanopyMid{k}", rr.uniform(8.5, 10.0), (*polar(21.0, a), cz + 9.5 + rr.uniform(-1, 1.5)), LEAF, seed=20 + k)
for k in range(5):
    a = k * 72 + 5
    puff(f"CanopyHi{k}", rr.uniform(8.0, 9.0), (*polar(10.0, a), cz + 16.0 + rr.uniform(-1, 1.5)), LEAF_L, seed=50 + k)
puff("CanopyTop", 9.0, (0, 0, cz + 21), LEAF_L, seed=31)
for k in range(5):
    a = k * 72
    S(tube(f"CrownBranch{k}", [(0, 0, cz + 6), (*polar(9, a), cz + 9), (*polar(18, a + 10), cz + 7)], [1.6, 1.0, 0.5],
           BARK, segs=6))
# bird nest on the very top
nz = cz + 28.0
for k in range(10):
    a = k * 36
    pts = [(*polar(5.2, a), nz + 0.8), (*polar(5.4, a + 30), nz + 1.6), (*polar(5.0, a + 60), nz + 0.9)]
    S(tube(f"Twig{k}", pts, [0.7, 0.8, 0.7], [BARK_L, BARK][k % 2], segs=6))
S(cylinder("NestBowl", 5.0, 1.6, (0, 0, nz - 0.6), BARK, segs=16, r_top=5.6))
mascot(0, 0, nz + 0.6, s=4.2)

# ---- owner exit: the hollow-branch slide, curling down the back from the top cabin into the moat ----
if FLOORS > 1:
    zs = top(FLOORS) + 3.0
    pts = []
    N = 14
    for k in range(N + 1):
        t = k / N
        a = 150 - 125 * t
        r = (rad_at(FLOORS, 150) + 1.5) * (1 - t) + 36.0 * t if t < 0.25 else 36.0
        pts.append((*polar(r, a), zs * (1 - t) ** 1.05 + 1.2 * t))
    add(tube("Slide", pts, [2.0] * len(pts), BARK, segs=10), shade(BARK, 0.85), BARK_L)
    add(tube("SlideGoo", [(p[0], p[1], p[2] + 1.75) for p in pts], [0.7] * len(pts), GOO, segs=6))
    hx, hy = polar(rad_at(FLOORS, 150) + 1.1, 150)
    S(cylinder("Hatch", 2.6, 0.4, (hx, hy, zs + 1.0), BARK_L, segs=12, rot=(90, 0, 150 + 90)))
    px, py = polar(36.0, 25)
    disc("SplashPool", 4.0, 0.5, (px, py, 0.8), GOO_HI, segs=16)

ship("_base_tree_scene", turn=-25)
