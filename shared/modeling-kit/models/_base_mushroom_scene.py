# Base concept (design sketch, not an asset): THE MUSHROOM PAGODA.
# Every floor is a round cream stalk room with glazed round windows under its own wide spotted mushroom cap; the
# cap overhangs like pagoda eaves and the next room stands on its flat top. The top floor wears a big domed cap with
# the mascot. You climb in a separate, thinner mushroom stalk turret on the +X side: an enclosed spiral ramp, one
# turn per floor, with an arch into each room; it pokes up through the top cap's rim. Floor 1: a round plank door on -Y, the vat and the lock button either
# side of it inside, 8 pads in two arcs that leave the front and the turret arch free. Upper floors: 8 pads on a ring
# round a free middle (glow-shroom lamps). Owner exit: a green vine slide from a hatch in the top room, out over the
# eaves and down into the goo moat behind the pagoda.
# Env: FLOORS, CUT (see _base_concept_common).
import math

import bmesh
from mathutils import Matrix

from lib import box, blob, cylinder, obj_from_bm, rgb, shade, mix, tube
from models._base_concept_common import *

STALK = rgb(246, 232, 204)
STALK_BAND = rgb(226, 200, 160)
GILL = rgb(214, 170, 150)
CAP_COLS = [rgb(232, 72, 72), rgb(176, 112, 232), rgb(250, 150, 60), rgb(232, 72, 72)]
SPOT = rgb(255, 250, 240)
VINE = rgb(96, 190, 96)
FLOORWOOD = rgb(206, 156, 102)
GLASS = rgb(196, 236, 244)
ROOM_R = [26.0, 24.0, 22.5, 21.5]       # inner wall radius per floor
PAD_R = [18.0, 15.5, 14.5, 13.5]        # pad ring radius per floor
WALL_H = 11.6
EAVE = 5.0                              # cap overhang past the wall
TUR = (27.0, 0.0)                       # turret centre (on the +X side)
TUR_IN, TUR_OUT = 5.8, 6.8


def shift(o, dx, dy):
    o.data.transform(Matrix.Translation((dx, dy, 0)))
    return o


def revolve(name, prof, col, segs=32, cx=0.0, cy=0.0, into="shell", lo=None):
    """Closed surface of revolution; prof = [(r, z), ...] from the axis round to the axis (r = 0 ends)."""
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        if r <= 1e-6:
            rings.append([bm.verts.new((cx, cy, z))])
        else:
            rings.append([bm.verts.new((cx + r * math.cos(k * math.tau / segs), cy + r * math.sin(k * math.tau / segs), z))
                          for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[k]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[j], b[0]))
            else:
                bm.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), lo or shade(col, 0.7), col, into)


def arc_wall(name, r_in, r_out, z0, h, col, a_from, a_to, step=8.0, into="shell"):
    """A curved wall from angle a_from to a_to (degrees, a_to > a_from)."""
    n = max(2, int(math.ceil((a_to - a_from) / step)))
    bm = bmesh.new()
    for i in range(n):
        a1 = a_from + (a_to - a_from) * i / n
        a2 = a_from + (a_to - a_from) * (i + 1) / n
        p = [polar(r, a) for r in (r_in, r_out) for a in (a1, a2)]
        (ix1, iy1), (ix2, iy2), (ox1, oy1), (ox2, oy2) = p
        vs = [bm.verts.new(q) for q in (
            (ix1, iy1, z0), (ix2, iy2, z0), (ox2, oy2, z0), (ox1, oy1, z0),
            (ix1, iy1, z0 + h), (ix2, iy2, z0 + h), (ox2, oy2, z0 + h), (ox1, oy1, z0 + h))]
        for fc in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            bm.faces.new([vs[j] for j in fc])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), shade(col, 0.85), col, into)


def spots(name, prof_pts, n, col, seed, cx=0.0, cy=0.0, size=1.6):
    """White spots on a cap: placed on a profile segment ((r0, z0), (r1, z1)), tilted to its slope."""
    (r0, z0), (r1, z1) = prof_pts
    slope = math.degrees(math.atan2(r1 - r0, z1 - z0))  # 0 = flat top, 90 = vertical side (outward)
    rr = random.Random(seed)
    for k in range(n):
        t = 0.25 + 0.5 * rr.random()
        r, z = r0 + (r1 - r0) * t, z0 + (z1 - z0) * t
        a = k * 360 / n + rr.uniform(-12, 12)
        x, y = polar(r, a)
        s = size * rr.uniform(0.75, 1.25)
        add(blob(f"{name}{k}", s, (cx + x, cy + y, z + 0.15), SPOT, subdiv=1, squash=(1, 1, 0.28), jitter=0.0,
                 rot=(0, -slope if r1 < r0 else slope, a)), into="shell")


# Ground: grass plot, goo moat, bridge to the door.
plot_foot(moat=True, door_r=ROOM_R[0] + 1)
disc("Floor1", ROOM_R[0] + 0.5, 0.35, (0, 0, 0.65), FLOORWOOD, segs=40)

for f in range(1, FLOORS + 1):
    z = top(f)
    r_in = ROOM_R[f - 1]
    r_out = r_in + 1.0
    if f > 1:
        disc(f"Floor{f}", r_in + 0.5, 0.6, (0, 0, z - 0.6), FLOORWOOD, segs=40)
    # Stalk wall with the door (floor 1) and the turret arch (every floor) left open.
    gaps = [(-9, 9)]
    if f == 1:
        gaps.append((-90 - 9.5, -90 + 9.5))
    edges = sorted(gaps)
    for k, (g0, g1) in enumerate(edges):
        nxt = edges[(k + 1) % len(edges)][0]
        end = nxt if nxt > g1 else nxt + 360
        arc_wall(f"Wall{f}_{k}", r_in, r_out, z, WALL_H, STALK, g1, end)
    # A darker band at the top of the stalk (the mushroom's ring) and round glazed windows.
    ring_wall(f"Band{f}", r_out - 0.2, r_out + 0.5, z + 1.0, 1.2, STALK_BAND, segs=40, into="shell",
              gap=(-9, 9) if f > 1 else (-90 - 10, -90 + 10))
    for k, a in enumerate((-40, 50, 100, 150, 200, 240) if f == 1 else (-90, -40, 50, 100, 150, 200, 240)):
        x, y = polar(r_out + 0.1, a)
        S(cylinder(f"WinFrame{f}{k}", 2.4, 1.0, (x, y, z + 6.5), STALK_BAND, segs=16, rot=(0, 90, a)))
        add(cylinder(f"Win{f}{k}", 1.9, 1.4, (x, y, z + 6.5), GLASS, segs=16, rot=(0, 90, a)), into="glass")

    # Cap: eave cap under the next room, or the big dome on the top floor.
    zc = z + WALL_H - 0.4
    r_eave = r_out + EAVE
    col = CAP_COLS[f - 1] if f < FLOORS else CAP_COLS[3]
    if f < FLOORS:
        r_next = ROOM_R[f] + 2.0
        zt = top(f + 1) - 0.6
        prof = [(0, zc + 0.4), (r_eave - 0.8, zc - 0.5), (r_eave, zc + 0.2), (r_eave - 0.8, zc + 1.8),
                (r_next + 2.5, zt - 0.6), (r_next, zt), (0, zt)]
        revolve(f"Cap{f}", prof, col)
        spots(f"Spot{f}", ((r_eave - 0.8, zc + 1.8), (r_next + 2.5, zt - 0.6)), 9, SPOT, f, size=1.5)
    else:
        prof = [(0, zc + 0.4), (r_eave - 1.0, zc - 0.6), (r_eave + 1.5, zc + 0.4), (r_eave + 1.0, zc + 2.6),
                (r_eave - 2.5, zc + 6.5), (r_eave - 9, zc + 10.0), (r_eave - 17, zc + 12.0), (0, zc + 12.6)]
        revolve(f"CapTop", prof, col, segs=40)
        spots("SpotTopA", ((r_eave + 1.0, zc + 2.6), (r_eave - 2.5, zc + 6.5)), 11, SPOT, 11, size=2.0)
        spots("SpotTopB", ((r_eave - 2.5, zc + 6.5), (r_eave - 9, zc + 10.0)), 8, SPOT, 12, size=2.2)
        spots("SpotTopC", ((r_eave - 9, zc + 10.0), (r_eave - 17, zc + 12.0)), 5, SPOT, 13, size=2.2)
        mascot(0, 0, zc + 12.4, s=4.6)

    # Pads.
    if f == 1:
        for k, a in enumerate((-30, 30, 60, 90, 120, 150, 180, 210)):
            x, y = polar(PAD_R[0], a)
            stand(f"Pad1_{k}", x, y, z, trim=CAP_COLS[0])
    else:
        pad_ring(f, PAD_R[f - 1], n=8, a0=30, arc=300, trim=CAP_COLS[f - 1])
        # glow-shroom lamps in the free middle
        for k in range(3):
            x, y = polar(2.2, k * 120 + 30 * f)
            disc(f"LampStem{f}{k}", 0.45, 2.2 + k * 0.8, (x, y, z), STALK, segs=8)
            add(blob(f"LampCap{f}{k}", 1.3, (x, y, z + 2.4 + k * 0.8), GOO_HI, subdiv=2, squash=(1, 1, 0.5), jitter=0))

# The stair turret: a thin stalk tower behind, an enclosed spiral ramp (one turn per floor) round a post, an arch
# into each room at the turret's inner side (local angle 180 = towards the pagoda's middle). It stands TUR_RISE
# above the top room so its own cap clears the big top cap's rim.
tx, ty = TUR
TUR_RISE = 9.0
z_top = top(FLOORS) + WALL_H + TUR_RISE
shift(disc("TurPost", 1.2, z_top - 1.0, (0, 0, 1.0), STALK_BAND, segs=12), tx, ty)
for f in range(1, FLOORS + 1):
    z = top(f)
    shift(ring_wall(f"TurWall{f}", TUR_IN, TUR_OUT, z, 9.0, STALK, segs=24, gap=(180 - 40, 180 + 40)), tx, ty)
    h = (FLOOR_H - 9.0) if f < FLOORS else (WALL_H + TUR_RISE - 9.0)
    shift(ring_wall(f"TurBand{f}", TUR_IN, TUR_OUT, z + 9.0, h, STALK, segs=24), tx, ty)
    # slit windows up the turret
    for k, a in enumerate((60, 300)):
        x, y = polar(TUR_OUT + 0.05, a)
        add(box(f"TurSlit{f}{k}", (0.4, 1.4, 4.0), (tx + x, ty + y, z + 9.5), GLASS, rot=(0, 0, a)), into="glass")
    if f < FLOORS:
        shift(helix_ramp(f"TurRamp{f}", 1.3, 5.75, z, FLOOR_H, 180, 360, BUTTER, segs=28), tx, ty)
    # landing lip at each arch, bridging turret and room floor
    shift(disc(f"TurLanding{f}", 3.0, 0.6, (-4.0, 0, z - 0.6), FLOORWOOD, segs=12), tx, ty)
    shift(ring_wall(f"TurRing{f}", TUR_OUT - 0.1, TUR_OUT + 0.5, z + 13.5, 1.0, CAP_COLS[f - 1], segs=24), tx, ty)
tcap = [(0, z_top - 0.2), (8.5, z_top - 0.6), (9.2, z_top + 0.4), (7.0, z_top + 4.0), (3.0, z_top + 5.6), (0, z_top + 6.0)]
revolve("TurCap", tcap, CAP_COLS[1], segs=28, cx=tx, cy=ty)
spots("TurSpot", ((9.2, z_top + 0.4), (7.0, z_top + 4.0)), 6, SPOT, 21, cx=tx, cy=ty, size=1.2)

# Floor 1 front: a round plank door swung open on its hinge, vat and lock button either side inside.
z1 = top(1)
dr = ROOM_R[0] + 0.5
S(cylinder("DoorFrame", 5.6, 1.6, (0, -dr, z1 + 5.0), STALK_BAND, segs=20, rot=(90, 0, 0)))
add(cylinder("Door", 4.6, 0.9, (-6.0, -dr - 3.2, z1 + 5.0), WOOD, segs=20, rot=(90, 0, 55)), shade(WOOD, 0.8), WOOD)
vat(*polar(15.0, -60), z1)
lock_button(*polar(16.0, -120), z1)
avatar(0, -12.5, z1)
avatar(4, -ROOM_R[0] - 6, 1.0, rgb(230, 120, 90))

# Owner exit: a green vine slide from a hatch in the top room (back-left), out over the eaves, spiralling down into
# the goo moat on the left.
zs = top(FLOORS) + 2.0
pts, rads = [], []
a0 = 140
for k in range(9):
    t = k / 8
    r = ROOM_R[FLOORS - 1] + 1.5 if k == 0 else 36.0
    a = a0 + 75 * t
    x, y = polar(r, a)
    pts.append((x, y, zs - (zs - 1.2) * (t ** 0.9)))
    rads.append(1.5)
add(tube("VineSlide", pts, rads, VINE, segs=10), shade(VINE, 0.7), VINE)
for k in range(1, 8, 2):
    x, y, zz = pts[k]
    add(blob(f"Leaf{k}", 1.6, (x, y, zz + 1.6), mix(VINE, BUTTER, 0.2), subdiv=1, squash=(1.4, 0.7, 0.3), jitter=0.05))

# Little mushrooms and grass tufts round the foot.
rr = random.Random(3)
for k in range(14):
    a = k * 360 / 14 + rr.uniform(-8, 8)
    if -105 < a - 360 * (a > 180) < -75:
        continue
    r = rr.uniform(ROOM_R[0] + 2.5, 33.0)
    x, y = polar(r, a)
    if abs(x) < 6 and y < 0:
        continue
    h = rr.uniform(1.0, 2.4)
    disc(f"MiniStem{k}", 0.35, h, (x, y, 0.7), STALK, segs=8)
    c = CAP_COLS[k % 3]
    add(blob(f"MiniCap{k}", 0.9 + h * 0.25, (x, y, 0.7 + h), c, subdiv=1, squash=(1, 1, 0.55), jitter=0), shade(c, 0.8), c)

ship("_base_mushroom_scene", turn=-25)
