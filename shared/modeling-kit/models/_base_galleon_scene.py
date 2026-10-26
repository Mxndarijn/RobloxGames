# Base concept (design sketch, not an asset): THE GOO GALLEON.
# A chunky pirate ship moored in a little goo sea (the moat fills the plot round the hull), lying along X, bow at +X.
# Floor 1 is the enclosed hull (portholes); floors 2-4 are stacked cabin decks above it (a stern-castle ark), each a
# bit shorter, all walled and roofed. You climb LONG STRAIGHT GANGWAY RAMPS along the ship's length: floor 1 -> 2 runs
# bow-wards along the back (+Y) wall, 2 -> 3 runs back stern-wards along the front (-Y) wall, 3 -> 4 bow-wards again.
# Floor 1: the door is a drawbridge gangplank on the -Y broadside (lowered onto a pier; pulled up shut while locked),
# with the merge vat and the lock button either side of it inside. 8 pads per deck in two rows. Owner exit: walk the
# plank from the top deck through an owner-only hatch in the +Y wall, splash into the goo sea. Cap: the captain's
# pitched roof with lanterns on the top deck; the bow mast with sails, crow's nest (mascot) and slime flag always stands.
# Env: FLOORS, CUT (see _base_concept_common).
import math

import bmesh
from mathutils import Vector

from lib import blob, box, cylinder, obj_from_bm, rgb, shade, mix, tube
from models._base_concept_common import *

HULL = rgb(176, 108, 70)       # warm hull wood
HULL_D = rgb(140, 84, 58)
STRIPE = rgb(80, 196, 200)     # teal band
GOLD = BUTTER
PLANK = rgb(236, 206, 150)     # cabin walls
TRIMR = rgb(220, 84, 78)       # red trim / roofs
ROOFC = rgb(214, 80, 80)
DECK = rgb(214, 170, 116)
SAIL = rgb(250, 242, 222)
SEA = rgb(96, 214, 184)
GLASSC = rgb(190, 232, 240)
RAMPC = rgb(120, 200, 240)     # the climb, bright so it reads in the cut-away
DARK = rgb(52, 48, 60)

HW = 18.0                      # half beam at deck height
X0 = -29.0                     # stern
X1 = {2: 20.0, 3: 17.0, 4: 15.0}  # each cabin deck's front wall (shorter upward)
LANE = 12.8                    # ramp lane centre |y|: lane A +Y (odd floors), lane B -Y (floor 2)
RW = 4.4
RAMP_X = (-24.0, 12.0)         # every ramp runs between these x (36 studs run, 16 rise: ~24 degrees)
ROWS = (-4.4, 4.4)             # pad rows (front, back)

# Deck outline at z = 17.6 (CCW, -Y side first, the door edge is index 1).
TOP = [(-29, -18), (-5, -18), (5, -18), (20, -18), (27, -14), (31, -8.5), (34, 0), (31, 8.5), (27, 14), (20, 18),
       (-29, 18), (-30.5, 9), (-31, 0), (-30.5, -9)]
BOW = [(20, -18), (27, -14), (31, -8.5), (34, 0), (31, 8.5), (27, 14), (20, 18)]


def hull_outline(z):
    t = min(max(z / 17.6, 0.0), 1.0)
    sx, sy = 0.92 + 0.08 * t, 0.86 + 0.14 * t
    return [(x * sx, y * sy) for x, y in TOP]


def _normals(poly):
    n = len(poly)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        e1, e2 = (p1 - p0).normalized(), (p2 - p1).normalized()
        nv = Vector((e1.y, -e1.x)) + Vector((e2.y, -e2.x))
        out.append(nv.normalized())
    return out


def loft(name, zs, thick, col, skip=(), grow=0.0, into="shell", k=0.85):
    """A ship-hull wall: the deck outline lofted through heights zs, `thick` thick, grown `grow` outwards.
    skip = {(band, edge)} quads left open (doorways)."""
    bm = bmesh.new()
    O, I = [], []
    for z in zs:
        poly = hull_outline(z)
        nr = _normals(poly)
        O.append([bm.verts.new((p[0] + n.x * grow, p[1] + n.y * grow, z)) for p, n in zip(poly, nr)])
        I.append([bm.verts.new((p[0] - n.x * (thick - grow), p[1] - n.y * (thick - grow), z)) for p, n in zip(poly, nr)])
    n = len(TOP)
    for b in range(len(zs) - 1):
        for j in range(n):
            j2 = (j + 1) % n
            if (b, j) in skip:
                bm.faces.new((O[b][j], O[b + 1][j], I[b + 1][j], I[b][j]))
                bm.faces.new((O[b][j2], I[b][j2], I[b + 1][j2], O[b + 1][j2]))
                bm.faces.new((O[b + 1][j], O[b + 1][j2], I[b + 1][j2], I[b + 1][j]))
                continue
            bm.faces.new((O[b][j], O[b][j2], O[b + 1][j2], O[b + 1][j]))
            bm.faces.new((I[b][j], I[b + 1][j], I[b + 1][j2], I[b][j2]))
    for lvl, rev in ((0, True), (len(zs) - 1, False)):
        for j in range(n):
            j2 = (j + 1) % n
            if lvl == 0 and (0, j) in skip:
                continue
            q = (O[lvl][j], O[lvl][j2], I[lvl][j2], I[lvl][j])
            bm.faces.new(q[::-1] if rev else q)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), shade(col, k), col, into)


def prism(name, poly, z0, z1, col, into=None, k=0.85):
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in poly]
    hi = [bm.verts.new((x, y, z1)) for x, y in poly]
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    n = len(poly)
    for j in range(n):
        j2 = (j + 1) % n
        bm.faces.new((lo[j], lo[j2], hi[j2], hi[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), shade(col, k), col, into)


def sail(name, x, y0, y1, z0, z1, bulge, col, yaw=0.0):
    """A billowing square sail in the y-z plane at x, bulging +X, closed slab, braced `yaw` degrees round the mast."""
    nu, nv, t = 6, 5, 0.35
    bm = bmesh.new()
    F, B = [], []
    for i in range(nu + 1):
        u = i / nu
        rf, rb = [], []
        for j in range(nv + 1):
            v = j / nv
            b = bulge * math.sin(math.pi * u) * (0.35 + 0.65 * math.sin(math.pi * v))
            y, z = y0 + (y1 - y0) * u, z0 + (z1 - z0) * v
            rf.append(bm.verts.new((x + b + t, y, z)))
            rb.append(bm.verts.new((x + b - t, y, z)))
        F.append(rf)
        B.append(rb)
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((F[i][j], F[i + 1][j], F[i + 1][j + 1], F[i][j + 1]))
            bm.faces.new((B[i][j], B[i][j + 1], B[i + 1][j + 1], B[i + 1][j]))
    for i in range(nu):
        for j in (0, nv):
            bm.faces.new((F[i][j], B[i][j], B[i + 1][j], F[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((F[i][j], F[i][j + 1], B[i][j + 1], B[i][j]))
    c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    for v in bm.verts:
        dx, dy = v.co.x - x, v.co.y
        v.co.x, v.co.y = x + dx * c - dy * sn, dx * sn + dy * c
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), shade(col, 0.88), col)


def deck_slab(f, x1, hole_y=None, col=DECK):
    """Floor f's deck, x0..x1 across the full beam, with an open stairwell strip over a ramp lane."""
    z = top(f)
    w = HW * 2 - 2
    if hole_y is None:
        part(f"Deck{f}", (x1 - X0, w, 0.6), ((X0 + x1) / 2, 0, z - 0.3), col)
        return
    s = 1 if hole_y > 0 else -1
    edge = s * (LANE - RW / 2)  # inner edge of the hole
    # the part of the deck that is not over the lane
    lo, hi = (-w / 2, edge) if s > 0 else (edge, w / 2)
    part(f"Deck{f}", (x1 - X0, hi - lo, 0.6), ((X0 + x1) / 2, (lo + hi) / 2, z - 0.3), col)
    lw = w / 2 - abs(edge)
    for nm, a, b in (("S", X0, RAMP_X[0]), ("E", RAMP_X[1], x1)):
        part(f"Deck{f}{nm}", (b - a, lw, 0.6), ((a + b) / 2, s * (abs(edge) + lw / 2), z - 0.3), col)
    # gold rail along the stairwell edge
    part(f"WellRail{f}", (RAMP_X[1] - RAMP_X[0], 0.4, 2.6), ((RAMP_X[0] + RAMP_X[1]) / 2, edge - s * 0.2, z + 1.3), GOLD,
         k=0.9)


def gangway(f, lane_s, forward):
    """Ramp from floor f to f + 1 in the lane on side lane_s (+1 / -1), bow-wards if forward."""
    z = top(f)
    a, b = (RAMP_X[0], RAMP_X[1]) if forward else (RAMP_X[1], RAMP_X[0])
    y = lane_s * LANE
    straight_ramp(f"Ramp{f}", (a, y, z), (b, y, z + FLOOR_H), RW, RAMPC)
    # rail on the room side over the upper two thirds
    ya = y - lane_s * (RW / 2 + 0.2)
    ta = 0.33
    pa = (a + (b - a) * ta, ya, z + FLOOR_H * ta + 2.4)
    straight_ramp(f"RampRail{f}", pa, (b, ya, z + FLOOR_H + 2.4), 0.4, GOLD, thick=1.0)


# ---- sea, pier --------------------------------------------------------------------------------------------------
plot_foot(moat=False, ground=FIELD)
disc("Sea", 38.5, 0.5, (0, 0, 0.55), SEA, segs=64, k=0.9)
part("Pier", (10, 18, 0.7), (0, -31.0, 1.3), WOOD)
for x in (-4.5, 4.5):
    for y in (-38, -31, -24):
        disc(f"PierPost{x}{y}", 0.6, 3.2, (x, y, 0.4), WOOD_D, segs=8)

# ---- floor 1: the hull ------------------------------------------------------------------------------------------
loft("Hull", [0.0, 12.0, 17.6], 1.0, HULL, skip={(0, 1)})
loft("HullStripe", [12.4, 14.2], 0.4, STRIPE, grow=0.25)
loft("Gunwale", [17.0, 18.0], 1.2, GOLD, grow=0.3)
loft("Keel", [-0.6, 0.0], 3.0, HULL_D, grow=0.0)
# portholes along both sides
for s in (-1, 1):
    for x in (-22, -14, 12, 20) if s < 0 else (-22, -14, -6, 2, 10, 18):
        yy = s * (HW * (0.86 + 0.14 * 7.5 / 17.6)) + s * 0.1
        add(cylinder(f"Port{s}{x}", 1.5, 0.8, (x, yy - s * 0.3, 7.5), GOLD, segs=12, rot=(90, 0, 0)), into="shell")
        add(cylinder(f"PortG{s}{x}", 1.05, 0.9, (x, yy - s * 0.25, 7.5), DARK, segs=12, rot=(90, 0, 0)), into="shell")
# floor 1 deck inside the hull
prism("HoldFloor", [(x * 0.93, y * 0.84) for x, y in TOP], 0.4, 1.0, DECK)

# ---- the gangplank door, vat and lock ---------------------------------------------------------------------------
dy = -HW * 0.865
straight_ramp("Gangplank", (0, dy, 1.0), (0, -22.2, 1.65), 8.6, WOOD, thick=0.6)
for s in (-1, 1):
    straight_ramp(f"PlankRope{s}", (s * 4.4, dy - 0.5, 9.5), (s * 4.4, -22.0, 2.4), 0.25, DARK, thick=0.25)
    part(f"DoorFrame{s}", (1.0, 1.6, 12), (s * 5.2, dy - 0.3, 6.0), GOLD, k=0.9)
part("DoorLintel", (11.4, 1.6, 1.2), (0, dy - 0.3, 12.2), GOLD, k=0.9)
vat(-10.0, -10.0, 1.0)
lock_button(8.0, -11.5, 1.0)
avatar(0, -12.5, 1.0)
avatar(2.5, -33, 1.65, rgb(230, 120, 90))

# floor 1 pads: back row of 5, front row of 3 round the vat/lock/door corner
for k, x in enumerate((-23.5, -14.1, -4.7, 4.7, 14.1)):
    stand(f"Pad1b{k}", x, ROWS[1], 1.0, trim=TRIMR)
for k, x in enumerate((-23.5, 14.6, 24.0)):
    stand(f"Pad1a{k}", x, ROWS[0], 1.0, trim=TRIMR)
# cargo on the hold floor (decor)
for k, (x, y) in enumerate(((27, 5), (-27, -12))):
    part(f"Barrel{k}", (2.4, 2.4, 3), (x, y, 2.5), WOOD_D)

if FLOORS > 1:
    gangway(1, +1, True)

# ---- floors 2..FLOORS: the stacked cabin decks --------------------------------------------------------------------
for f in range(2, FLOORS + 1):
    z = top(f)
    x1 = X1[f]
    deck_slab(f, x1, hole_y=(+1 if f % 2 == 0 else -1) * LANE)
    # cabin walls: plank sides with a red band and windows, the stern wall with big galleon windows
    h = FLOOR_H
    for s in (-1, 1):
        S(box(f"Side{f}{s}", (x1 - X0, 1.0, h), ((X0 + x1) / 2, s * (HW - 0.5), z + h / 2), PLANK), shade(PLANK, 0.86), PLANK)
        S(box(f"Band{f}{s}", (x1 - X0 + 0.4, 1.4, 1.2), ((X0 + x1) / 2, s * (HW - 0.5), z + 0.6), TRIMR), shade(TRIMR, 0.9), TRIMR)
        for k in range(4):
            wx = X0 + 6 + k * (x1 - X0 - 12) / 3
            add(box(f"Win{f}{s}{k}", (5.0, 1.4, 4.2), (wx, s * (HW - 0.5), z + 9.0), GLASSC), into="glass")
            S(box(f"WinF{f}{s}{k}", (6.0, 1.2, 5.2), (wx, s * (HW - 0.4), z + 9.0), GOLD), GOLD, GOLD)
        for k in (5.0, 11.0):
            S(box(f"PlankLine{f}{s}{k}", (x1 - X0 + 0.2, 1.15, 0.25), ((X0 + x1) / 2, s * (HW - 0.5), z + k), shade(PLANK, 0.78)))
    S(box(f"Front{f}", (1.0, HW * 2, h), (x1 - 0.5, 0, z + h / 2), PLANK), shade(PLANK, 0.86), PLANK)
    S(box(f"Stern{f}", (1.0, HW * 2, h), (X0 + 0.5, 0, z + h / 2), PLANK), shade(PLANK, 0.86), PLANK)
    for k in range(3):
        add(box(f"SternWin{f}{k}", (1.4, 6.0, 7.0), (X0 + 0.4, -10 + k * 10, z + 8.5), GLASSC), into="glass")
    # roof ledge round the next deck: a gold rail on the cabin's front roof edge
    S(box(f"Eave{f}", (x1 - X0 + 1.6, HW * 2 + 1.6, 0.8), ((X0 + x1) / 2, 0, z + h + 0.1), TRIMR), shade(TRIMR, 0.85), TRIMR)
    for k in range(4):
        x = (X0 + x1) / 2 - 13.95 + k * 9.3
        for row, y in enumerate(ROWS):
            stand(f"Pad{f}_{row}_{k}", x, y, z, trim=TRIMR)
    if f < FLOORS:
        gangway(f, -1 if f % 2 == 0 else +1, f % 2 == 1)

# ---- the cap: the deck roof over the top floor, the captain's pitched roof, lanterns -----------------------------
zt = top(FLOORS) + FLOOR_H
xt = X1.get(FLOORS, 20.0)
if FLOORS == 1:
    part("MainDeck", (20 - X0, HW * 2 - 1, 0.6), ((X0 + 20) / 2, 0, zt - 0.3), DECK, into="shell")
    zr, xr0, xr1 = zt, X0 + 1, -6.0
    for s in (-1, 1):
        S(box(f"CabSide{s}", (xr1 - xr0, 0.8, 7), ((xr0 + xr1) / 2, s * 8, zr + 3.5), PLANK), shade(PLANK, 0.86), PLANK)
    S(box("CabEnd", (0.8, 16, 7), (xr1, 0, zr + 3.5), PLANK), shade(PLANK, 0.86), PLANK)
    rw, base = 9.0, zr + 7.0
else:
    xr0, xr1, rw, base = X0, xt, HW + 0.8, zt + 0.5
a = 28.0
for s in (-1, 1):
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    S(box(f"Roof{s}", (xr1 - xr0 + 2, rw, 0.9), ((xr0 + xr1) / 2, s * rw / 2 * ca, base + rw / 2 * sa),
          ROOFC, rot=(-s * a, 0, 0)), shade(ROOFC, 0.8), ROOFC)
ridge = base + rw * math.sin(math.radians(a))
S(box("Ridge", (xr1 - xr0 + 2.4, 1.2, 1.2), ((xr0 + xr1) / 2, 0, ridge), GOLD), GOLD, GOLD)
for s in (-1, 1):
    disc(f"Lantern{s}", 1.0, 2.2, (X0 - 1.2, s * 9, base - 3.5), GOLD, segs=8)
    add(blob(f"LanternGlow{s}", 0.8, (X0 - 1.2, s * 9, base - 2.2), rgb(255, 230, 140), subdiv=1, jitter=0))

# ---- owner exit: walk the plank off the top deck's +Y side --------------------------------------------------------
zp = top(FLOORS)
px = -4.0
part("ExitPlank", (3.2, 9.0, 0.6), (px, HW + 4.5, zp - 0.3), WOOD)
part("ExitHatch", (4.6, 0.6, 7.5), (px - 2.6, HW + 0.4, zp + 3.75), TRIMR, rot=(0, 0, 70))  # swung open
part("ExitSign", (4.0, 0.3, 1.6), (px, HW + 0.1, zp + 9.0), GOLD)
add(cylinder("SplashRing", 4.6, 0.3, (px, HW + 12.0, 1.05), GOO_HI, segs=24))

# ---- bow: mast, sails, crow's nest with the mascot, slime flag, bowsprit, figurehead ------------------------------
mx = 26.5
zd = top(2) - 0.3
prism("BowDeck", [(x, y * 0.97) for x, y in BOW], zd - 0.3, zd + 0.3, DECK)
mast_top = max(zt + 16, 84.0)
disc("Mast", 1.3, mast_top - zd, (mx, 0, zd), WOOD_D, segs=10, r_top=0.9)
BRACE = -25.0
cb, sb = math.cos(math.radians(BRACE)), math.sin(math.radians(BRACE))
for k, (z0, z1, half) in enumerate(((zd + 5, zd + 27, 16), (zd + 30, zd + 47, 12.5))):
    part(f"Yard{k}", (0.9, half * 2 + 3, 0.9), (mx, 0, z1 + 0.6), WOOD_D, rot=(0, 0, BRACE))
    sail(f"Sail{k}", mx + 0.8, -half, half, z0, z1, 3.6, SAIL, yaw=BRACE)
    off = 0.9 + 4.0
    add(blob(f"SailSlime{k}", 3.6 - k * 0.7, (mx + off * cb, off * sb, (z0 + z1) / 2), GOO, subdiv=2,
             squash=(0.35, 1, 0.85), jitter=0, rot=(0, 0, BRACE)))
nest = mast_top - 8
disc("Nest", 3.6, 3.2, (mx, 0, nest), WOOD, segs=16)
disc("NestRim", 3.9, 0.6, (mx, 0, nest + 3.2), GOLD, segs=16)
mascot(mx, 0, nest + 3.4, s=3.2)
part("Flag", (0.3, 7.0, 4.6), (mx, 3.6, mast_top - 2.2), DARK, k=1.0)
add(blob("FlagSlime", 1.6, (mx - 0.3, 3.6, mast_top - 2.6), GOO, subdiv=2, squash=(0.3, 1, 0.8), jitter=0))
for s in (-1, 1):
    add(blob(f"FlagEye{s}", 0.35, (mx - 0.6, 3.6 + s * 0.6, mast_top - 2.2), rgb(250, 250, 250), subdiv=1, jitter=0))
straight_ramp("Bowsprit", (33.0, 0, zd + 1.5), (38.5, 0, zd + 7.0), 1.2, WOOD_D, thick=1.2)
straight_ramp("Jib", (mx + 1.0, 0, nest - 4), (38.0, 0, zd + 7.5), 0.5, DARK, thick=0.3)
add(blob("Figurehead", 2.0, (34.3, 0, 12.5), PINK, subdiv=2, squash=(1.1, 0.9, 1), jitter=0))
# cannons out the hull front corners
for s in (-1, 1):
    add(cylinder(f"Cannon{s}", 0.9, 3.0, (22, s * (HW * 0.95), 10.5), DARK, segs=10, rot=(s * -90, 0, 0)))
# anchor hanging off the bow
tube("AnchorChain", [(30, -9.5, 15), (30.5, -10.8, 8), (30.5, -10.8, 3)], [0.3, 0.3, 0.3], DARK, segs=6)
part("Anchor", (0.6, 3.6, 0.8), (30.5, -10.8, 2.6), DARK)

# mizzen mast through the captain's roof at the stern, with a small sail and a pennant; rigging to the main mast
zm = ridge
disc("Mizzen", 0.9, 15, (X0 + 7, 0, zm - 1), WOOD_D, segs=8, r_top=0.6)
sail("MizzenSail", X0 + 7.6, -6, 6, zm + 3, zm + 11, 1.6, SAIL, yaw=BRACE)
part("MizzenYard", (0.7, 14, 0.7), (X0 + 7, 0, zm + 11.4), WOOD_D, rot=(0, 0, BRACE))
part("Pennant", (0.2, 0.6, 1.6), (X0 + 7, 0, zm + 15), TRIMR)
straight_ramp("Pennant2", (X0 + 7, 0.2, zm + 14.3), (X0 + 7, 6, zm + 14.0), 1.4, TRIMR, thick=0.2)
straight_ramp("Stay", (X0 + 7, 0, zm + 13.5), (mx, 0, nest + 1), 0.35, DARK, thick=0.35)
for s in (-1, 1):
    straight_ramp(f"Shroud{s}", (mx, 0, nest - 1), (mx - 2, s * (HW * 0.95), zd + 1), 0.3, DARK, thick=0.3)
# gun ports along the hull band
for s in (-1, 1):
    for x in (-24, -16, 16, 24) if s < 0 else (-24, -16, -8, 0, 8, 16, 24):
        add(box(f"GunPort{s}{x}", (2.2, 0.6, 1.8), (x, s * (HW * 0.985), 14.9), DARK), into="shell")

ship("_base_galleon_scene", turn=-55)
