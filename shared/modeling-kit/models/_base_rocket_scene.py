# Base concept (design sketch, not an asset): THE SLIME ROCKET.
# A chunky 4-stage cartoon rocket on a launch pad. No centre post: the middle of every stage is an open atrium, so
# you see up and down through all floors. The ramp spirals round the atrium edge (red rail on the atrium side), one
# turn per floor; the 8 pads stand round the outer hull. Floor 1: a round airlock hatch on -Y (it swings shut when
# locked), the merge vat and the lock button either side inside. Owner exit: jump down the atrium onto the bouncy
# goo cushion on floor 1. The nose cone with the glass cockpit (the mascot as pilot) sits on whatever stage is on top.
# Env: FLOORS, CUT (see _base_concept_common).
import math

import bmesh

from lib import blob, box, cylinder, obj_from_bm, rgb, shade, tube
from models._base_concept_common import *

WHITE = rgb(238, 240, 248)
TEAL = rgb(70, 196, 200)
RED_H = rgb(236, 82, 78)
PORT = rgb(70, 140, 220)
DECK = rgb(196, 204, 218)
HAZ = rgb(250, 206, 70)
DARK = rgb(80, 84, 100)
ATRIUM = 6.0          # open shaft radius
RAMP_OUT = 10.5       # ramp walks from ATRIUM to RAMP_OUT (4.5 wide)
RB = [29.0, 28.0, 27.0, 26.0]   # stage outer radius at its bottom
RT = [28.0, 27.0, 26.0, 25.0]   # ... and at its top (one smooth taper up the body)
STAGE_COL = [WHITE, WHITE, TEAL, WHITE]
TRIMS = [HAZ, PINK, LILAC, BUTTER]
DOOR_GAP = (-99.0, -81.0)       # 10 studs of hull left open for the hatch, 12 tall
DOOR_H = 12.0


def in_arc(a, arc):
    return (a - arc[0]) % 360 <= (arc[1] - arc[0]) % 360


def hull(name, rb, rt, z0, h, col, segs=40, a0=-99.0, gap=None, gap_h=None, thick=1.0):
    """A tapered round hull wall; `gap` arc is left open below z0 + gap_h (the doorway)."""
    bm = bmesh.new()

    def rad(z):
        return rb + (rt - rb) * (z - z0) / h

    for i in range(segs):
        a1 = a0 + i * 360 / segs
        a2 = a0 + (i + 1) * 360 / segs
        spans = [(z0, z0 + h)]
        if gap and in_arc((a1 + a2) / 2, gap):
            spans = [(z0 + gap_h, z0 + h)]
        for za, zb in spans:
            vs = []
            for z in (za, zb):
                ro = rad(z)
                ri = ro - thick
                pts = [polar(ri, a1), polar(ri, a2), polar(ro, a2), polar(ro, a1)]
                vs += [bm.verts.new((x, y, z)) for x, y in pts]
            for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
                bm.faces.new([vs[j] for j in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S(obj_from_bm(name, bm, col), shade(col, 0.84), col)


def fin(name, a, col, prof=((27.5, 1.0), (37.0, 1.0), (37.0, 14.0), (27.5, 36.0)), t=1.5):
    """A flat swept fin in the (radial, z) plane at angle a."""
    ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
    bm = bmesh.new()
    vs = []
    for s in (t, -t):
        for u, z in prof:
            vs.append(bm.verts.new((u * ca - s * sa, u * sa + s * ca, z)))
    for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([vs[j] for j in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return S(obj_from_bm(name, bm, col), shade(col, 0.8), col)


def porthole(name, r, a, z):
    x, y = polar(r + 0.1, a)
    S(cylinder(name + "F", 2.3, 0.6, (x, y, z), WHITE, segs=14, rot=(90, 0, a + 90)))
    xo, yo = polar(r + 0.4, a)
    S(cylinder(name + "G", 1.7, 0.5, (xo, yo, z), PORT, segs=14, rot=(90, 0, a + 90)))


plot_foot(moat=False)
# Launch pad: a grey concrete disc with a hazard ring.
disc("LaunchPad", 37.5, 0.35, (0, 0, 0.7), rgb(180, 184, 192), segs=64, k=0.9)
ring_wall("PadRing", 34.0, 35.5, 1.0, 0.12, HAZ, segs=64, into=None)

for i in range(FLOORS):
    f = i + 1
    z = top(f)
    rin = RB[i] - 1.0
    # Deck: floor 1 is a full disc with the goo cushion in the atrium; upper decks are rings round the ramp hole.
    if f == 1:
        disc("Deck1", rin + 0.2, 0.3, (0, 0, z - 0.3), DECK, segs=40)
        add(blob("Cushion", ATRIUM - 0.6, (0, 0, z + 0.2), GOO, subdiv=2, squash=(1, 1, 0.28), jitter=0.0),
            shade(GOO, 0.8), GOO_HI)
        ring_wall("CushionRim", ATRIUM - 0.6, ATRIUM, z, 1.0, HAZ, segs=24, into=None)
    else:
        ring_wall(f"Deck{f}", RAMP_OUT, rin + 0.2, z - 0.6, 0.6, DECK, segs=40, into=None)
        ring_wall(f"DeckEdge{f}", RAMP_OUT, RAMP_OUT + 0.4, z, 0.15, HAZ, segs=40, into=None)
    # Hull (shell), joint band at its top.
    # See-through rule: a low hull band, a glass band and a top band per stage, so the slimes always show.
    zs = z if f > 1 else 1.0
    rr = lambda dz, i=i: RB[i] + (RT[i] - RB[i]) * dz / FLOOR_H
    g = DOOR_GAP if f == 1 else None
    hull(f"HullLo{f}", RB[i], rr(3.0), zs, 3.0, STAGE_COL[i], gap=g, gap_h=3.0)
    hull(f"HullGlass{f}", rr(3.0) - 0.3, rr(FLOOR_H - 2.5) - 0.3, zs + 3.0, FLOOR_H - 5.5, rgb(190, 225, 245), gap=g,
         gap_h=FLOOR_H, thick=0.4)
    glass.append(shell.pop())
    hull(f"HullHi{f}", rr(FLOOR_H - 2.5), RT[i], zs + FLOOR_H - 2.5, 2.5, STAGE_COL[i])
    for k in range(10):
        a = -90 + 18 + k * 36
        x, y = polar(rr(8.0) + 0.1, a)
        S(cylinder(f"Rib{f}_{k}", 0.5, FLOOR_H - 5.5, (x, y, zs + 3.0), STAGE_COL[i], segs=6))
    ring_wall(f"Joint{f}", RT[i] - 0.6, RT[i] + 0.35, z + FLOOR_H - 0.4, 0.8, RED_H, segs=40)
    # Portholes round the stage (stage 1 keeps clear of the door and the fins).
    # Pads round the outer hull; floor 1 leaves the front either side of the hatch free.
    ring = rin - 4.5 - 3.2
    if f == 1:
        pad_ring(1, ring, n=8, a0=-90 + 60, arc=240, trim=TRIMS[i])
    else:
        pad_ring(f, ring, n=8, a0=-90 + 22.5, trim=TRIMS[i])
    # Spiral ramp round the atrium up to the next floor, with a red rail on the atrium side.
    if f < FLOORS:
        helix_ramp(f"Ramp{f}", ATRIUM, RAMP_OUT, z, FLOOR_H, 90, 360, HAZ, segs=32)
        pts = [(*polar(ATRIUM + 0.3, 90 + 360 * t / 16), z + FLOOR_H * t / 16 + 2.6) for t in range(17)]
        add(tube(f"Rail{f}", pts, [0.25] * len(pts), RED_H, segs=6))
        for t in range(0, 16, 2):
            px, py = polar(ATRIUM + 0.3, 90 + 360 * t / 16)
            add(cylinder(f"RailPost{f}_{t}", 0.18, 2.6, (px, py, z + FLOOR_H * t / 16 - 0.1), RED_H, segs=5))

# Floor 1 front: the airlock hatch (open: swung flat against the hull to the right), its bolted ring, vat and lock.
z1 = top(1)
ry = -(RB[0] + 0.3)
hx, hy = polar(RB[0] + 0.4, -66)
for k in range(18):
    a = k * 20
    dx, dz = 6.6 * math.cos(math.radians(a)), 6.6 * math.sin(math.radians(a))
    if 1.0 + 6.5 + dz < 1.2:
        continue
    part(f"HatchRing{k}", (1.5, 1.2, 1.5), (dx, ry - 0.2, 7.0 + dz), RED_H, k=0.9)
S(cylinder("HatchDoor", 5.8, 0.9, (hx, hy, 7.0), shade(WHITE, 0.95), segs=24, rot=(90, 0, 24)))
wx, wy = polar(RB[0] + 1.1, -66)
S(cylinder("HatchWheel", 2.0, 0.6, (wx, wy, 7.0), RED_H, segs=12, rot=(90, 0, 24)))
vat(*polar(22.0, -62), z1)
lock_button(*polar(22.0, -118), z1)
avatar(0, -12.5, z1)
avatar(4, -38, 1.0, rgb(230, 120, 90))

# Fins with booster pods at their tips (red fins, white boosters).
for a in (-45, -135, 45, 135):
    fin(f"Fin{a}", a, RED_H)
    bx_, by_ = polar(37.0, a)
    S(cylinder(f"Nozzle{a}", 2.6, 2.0, (bx_, by_, 1.0), DARK, segs=14, r_top=1.8))
    S(cylinder(f"Booster{a}", 2.4, 12.0, (bx_, by_, 3.0), WHITE, segs=14), shade(WHITE, 0.85), WHITE)
    S(cylinder(f"BoosterBand{a}", 2.5, 1.2, (bx_, by_, 9.0), TEAL, segs=14))
    S(cylinder(f"BoosterTip{a}", 2.4, 4.0, (bx_, by_, 15.0), RED_H, segs=14, r_top=0.3), shade(RED_H, 0.85), RED_H)

# Nose cone on the top stage, the glass cockpit and the mascot pilot.
zt = top(FLOORS) + FLOOR_H
rt = RT[FLOORS - 1]
# An ogive nose: three tapering rings, a white band, then the glass cockpit bubble at the tip.
S(cylinder("Nose1", rt + 0.2, 9.0, (0, 0, zt), RED_H, segs=40, r_top=rt * 0.8), shade(RED_H, 0.8), RED_H)
S(cylinder("NoseBand", rt * 0.8, 2.0, (0, 0, zt + 9.0), WHITE, segs=40, r_top=rt * 0.72))
S(cylinder("Nose2", rt * 0.72, 12.0, (0, 0, zt + 11.0), RED_H, segs=40, r_top=rt * 0.42), shade(RED_H, 0.85), RED_H)
S(cylinder("Nose3", rt * 0.42, 6.0, (0, 0, zt + 23.0), RED_H, segs=32, r_top=5.6), shade(RED_H, 0.9), RED_H)
S(cylinder("CockpitRing", 6.2, 1.0, (0, 0, zt + 29.0), WHITE, segs=32))
mascot(0, 0, zt + 30.0, s=3.2)
add(blob("Cockpit", 6.0, (0, 0, zt + 30.0), rgb(190, 232, 250), subdiv=3, squash=(1, 1, 1.15), jitter=0.0),
    into="glass")
S(cylinder("Antenna", 0.3, 4.0, (0, 0, zt + 36.5), DARK, segs=6))
add(blob("AntennaTip", 0.8, (0, 0, zt + 40.8), RED_H, subdiv=2, jitter=0.0), into="shell")

# Goo exhaust puffs round the base (decor, non-colliding in game).
for k in range(10):
    a = -60 + k * 36 + R.uniform(-8, 8)
    if in_arc(a, (-115, -65)):
        continue
    px, py = polar(R.uniform(31.5, 34.0), a)
    add(blob(f"Puff{k}", R.uniform(1.6, 2.4), (px, py, 1.6), GOO_HI, subdiv=2, squash=(1.2, 1.2, 0.8), jitter=0.06),
        shade(GOO_HI, 0.85), GOO_HI)

ship("_base_rocket_scene", turn=-25)
