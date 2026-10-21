# Design preview (not an asset): three base remodel concepts at version BASE_V (1..4), true scale in studs.
# BASE_CONCEPT = jar | tree | islands. Every concept fits the 80 x 80 plot (entrance at -Y), holds 8 pads per floor,
# and stacks floors 14 studs apart. None reuses the plank fence, crate pads or gate arch of today's base.
import math
import os
import random

from lib import *
from models._phoenix_ranch import bbox, rpost

P = PALETTE
CONCEPT = os.environ.get("BASE_CONCEPT", "jar")
V = int(os.environ.get("BASE_V", "4"))
FLOOR_H = 14.0
WOOD, WOOD_D, CREAM = P["ranch_wood"], P["ranch_wood_dark"], P["ranch_cream"]
GOO, GOO_HI, METAL = P["ranch_goo"], P["ranch_goo_hi"], P["ranch_metal"]
PINK, LILAC, BUTTER, ROOF = P["ranch_pink"], P["ranch_lilac"], P["ranch_butter"], P["ranch_roof"]
FIELD, FIELD_L, FIELD_D, PATH = P["ranch_field"], P["ranch_field_light"], P["ranch_field_dark"], P["ranch_path"]
GLASS = mix(GOO_HI, rgb(150, 214, 236), 0.55)
TRIM = mix(LILAC, CREAM, 0.2)
SLIME_COLS = [PINK, LILAC, BUTTER, GOO, rgb(120, 190, 250), rgb(250, 160, 90)]
R = random.Random(11)
parts = []


def top(f):
    return 1.0 + (f - 1) * FLOOR_H


def add(o, lo=None, hi=None):
    if lo is not None:
        gradient(o, lo, hi)
    parts.append(o)
    return o


def ring_xy(n, radius, phase=0.0):
    return [(radius * math.cos(phase + k * math.tau / n), radius * math.sin(phase + k * math.tau / n)) for k in range(n)]


def slime(x, y, z, k, r=1.6):
    col = SLIME_COLS[k % len(SLIME_COLS)]
    add(blob(f"Slime{len(parts)}", r, (x, y, z + r * 0.78), col, subdiv=2, squash=(1, 1, 0.78), jitter=0.02), shade(col, 0.82), col)


def spiral(cx, cy, r, z0, z1, turns, phase, n=40):
    pts = []
    for i in range(n + 1):
        t = i / n
        a = phase + t * turns * math.tau
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a), z0 + (z1 - z0) * t))
    return pts


# --- A. Goo jar tower ------------------------------------------------------------------------------------------
def jar_concept():
    radii = [30, 26, 22, 18]
    # Wooden foot: a low round plinth with a goo moat ring, the door step at the front.
    add(cylinder("Foot", 34, 1.0, (0, 0, 0), WOOD, segs=40), shade(WOOD, 0.85), WOOD)
    add(cylinder("Moat", 35.5, 0.6, (0, 0, 0), GOO, segs=40))
    add(bbox("Step", (12, 6, 1.0), (0, -35, 0.5), shade(PATH, 0.9), PATH, bev=0.2))
    for f in range(1, V + 1):
        r = radii[f - 1]
        z = top(f)
        # goo pool floor with a raised wooden ring edge
        add(cylinder(f"Pool{f}", r - 0.6, 0.5, (0, 0, z - 0.5), GOO, segs=40), shade(GOO, 0.85), GOO)
        add(cylinder(f"Rim{f}", r, 0.8, (0, 0, z - 0.9), WOOD_D, segs=40), shade(WOOD_D, 0.9), WOOD_D)
        # glass jar wall: low glass band, ribs, a fat rounded shoulder, the brass lip and a cork lid ring
        add(cylinder(f"GlassLow{f}", r, 2.4, (0, 0, z - 0.4), GLASS, segs=40), shade(GLASS, 0.9), GLASS)
        # jam-jar label on the front in the plot colour
        add(bbox(f"Label{f}", (r * 0.55, 0.5, 3.4), (0, -r - 0.1, z + 5.2), shade(CREAM, 0.95), CREAM, bev=0.15))
        add(bbox(f"LabelBand{f}", (r * 0.55 + 0.2, 0.6, 1.0), (0, -r - 0.15, z + 5.2), shade(TRIM, 0.9), TRIM, bev=0.1))
        add(blob(f"LabelDot{f}", 0.9, (0, -r - 0.6, z + 5.2), GOO, subdiv=2, squash=(1, 0.4, 1), jitter=0))
        for k, (x, y) in enumerate(ring_xy(12, r - 0.2, math.pi / 12)):
            add(cylinder(f"Rib{f}{k}", 0.35, FLOOR_H - 3.4, (x, y, z), GLASS, segs=6))
        add(cylinder(f"Shoulder{f}", r + 0.3, 2.6, (0, 0, z + FLOOR_H - 5.4), GLASS, segs=40, r_top=r - 2.5),
            shade(GLASS, 0.9), GLASS)
        add(cylinder(f"Lip{f}", r - 2.2, 0.9, (0, 0, z + FLOOR_H - 2.8), METAL, segs=40))
        if f == V:
            add(cylinder("Cork", r - 2.6, 2.6, (0, 0, z + FLOOR_H - 1.9), mix(WOOD, BUTTER, 0.35), segs=40, r_top=r - 3.2),
                shade(WOOD, 0.95), mix(WOOD, BUTTER, 0.35))
            if V >= 4:
                add(blob("GooCrown", 5.0, (0, 0, z + FLOOR_H + 2.2), GOO, subdiv=3, squash=(1, 1, 0.7), jitter=0.03))
                for k, (x, y) in enumerate(ring_xy(7, r - 3.4)):
                    add(blob(f"Drip{k}", 1.1, (x, y, z + FLOOR_H - 0.4), GOO, subdiv=2, squash=(1, 1, 1.6), jitter=0))
        # lily-pad pods in a ring, slimes on most of them
        for k, (x, y) in enumerate(ring_xy(8, r * 0.62, math.pi / 8)):
            add(cylinder(f"Lily{f}{k}", 3.6, 0.5, (x, y, z), FIELD_L, segs=14), FIELD, FIELD_L)
            add(blob(f"Bloom{f}{k}", 0.8, (x + 2.2, y, z + 0.7), PINK, subdiv=1, jitter=0))
            if R.random() < 0.8:
                slime(x, y, z + 0.5, f * 8 + k)
        # centre: a spiral stair post with treads
        add(cylinder(f"Post{f}", 2.2, FLOOR_H, (0, 0, z), WOOD_D, segs=16), shade(WOOD_D, 0.9), WOOD_D)
        for k in range(8):
            a = k / 8 * math.tau + f
            add(bbox(f"Tread{f}{k}", (5.0, 2.2, 0.5), (3.6 * math.cos(a), 3.6 * math.sin(a), z + 1.5 + k * 1.6), shade(WOOD, 0.9), WOOD,
                     bev=0.08, rot=(0, 0, math.degrees(a))))
    # round door at the front of jar 1
    add(bbox("Door", (8, 1.2, 9), (0, -radii[0] - 0.2, 5.5), shade(ROOF, 0.85), ROOF, bev=0.4))
    add(blob("DoorTop", 4.0, (0, -radii[0] - 0.2, 10.0), ROOF, subdiv=2, squash=(1, 0.3, 0.6), jitter=0))
    add(blob("DoorKnob", 0.5, (2.4, -radii[0] - 1.0, 5.5), BUTTER, subdiv=1, jitter=0))
    # goo slide spiralling down the outside from the top jar
    if V >= 2:
        pts = spiral(0, 0, radii[0] + 2.5, top(V) + 2, 1.5, V * 0.6, math.pi * 0.25)
        add(tube("Slide", pts, [1.6] * len(pts), GOO, segs=8), shade(GOO, 0.85), GOO_HI)
    # lock: a big goo button on a cork pedestal by the step
    add(cylinder("LockPed", 1.8, 3, (11, -35, 0), mix(WOOD, BUTTER, 0.35), segs=12))
    add(blob("LockBtn", 1.4, (11, -35, 3.2), ROOF, subdiv=2, squash=(1, 1, 0.55), jitter=0))


# --- B. Slime tree -----------------------------------------------------------------------------------------------
def tree_concept():
    bark, bark_hi = shade(WOOD_D, 0.95), WOOD
    # mossy clearing with roots as the border, no fence
    add(cylinder("Clearing", 38, 0.8, (0, 0, 0), FIELD_L, segs=40), FIELD, FIELD_L)
    for k in range(9):
        a = k / 9 * math.tau + 0.3
        if abs(math.degrees(a) % 360 - 270) < 25:
            continue  # leave the entrance free
        pts = [(9 * math.cos(a), 9 * math.sin(a), 3.0), (22 * math.cos(a + 0.1), 22 * math.sin(a + 0.1), 1.2),
               (35 * math.cos(a + 0.05), 35 * math.sin(a + 0.05), 0.8)]
        add(tube(f"Root{k}", pts, [3.0, 2.2, 1.2], bark, segs=7, seed=k, jitter=0.1), shade(bark, 0.85), bark_hi)
    trunk_top = top(V) + 12
    add(cylinder("Trunk", 9.5, trunk_top, (0, 0, 0), bark, segs=18, r_top=7.0, jitter=0.06, seed=3), shade(bark, 0.85), bark_hi)
    add(bbox("TrunkDoor", (6, 2, 8), (0, -9.2, 4.5), shade(ROOF, 0.85), ROOF, bev=0.5))
    add(blob("DoorArch", 3.0, (0, -9.2, 8.4), ROOF, subdiv=2, squash=(1, 0.4, 0.7), jitter=0))
    for f in range(1, V + 1):
        z = top(f)
        spots = []
        for b in range(2):
            a = f * math.pi / 2 + b * math.pi
            px, py = 18 * math.cos(a), 18 * math.sin(a)
            if f > 1:
                add(cylinder(f"Plat{f}{b}", 13.5, 1.0, (px, py, z - 1.0), WOOD, segs=24, jitter=0.03, seed=f * 2 + b), shade(WOOD, 0.88), WOOD)
                add(cylinder(f"PlatEdge{f}{b}", 13.9, 0.5, (px, py, z - 1.3), mix(LILAC, CREAM, 0.25), segs=24))
                add(tube(f"Branch{f}{b}", [(px * 0.3, py * 0.3, z - 6), (px * 0.75, py * 0.75, z - 2.5), (px * 1.15, py * 1.15, z - 1.2)],
                         [2.6, 1.8, 0.9], bark, segs=7, seed=f + b), shade(bark, 0.85), bark_hi)
                for k, (x, y) in enumerate(ring_xy(10, 13.3, a)):
                    if k in (4, 5, 6):
                        continue  # open towards the trunk
                    add(cylinder(f"Rail{f}{b}{k}", 0.4, 2.8, (px + x, py + y, z), WOOD_D, segs=5))
                for k in range(2):
                    add(blob(f"Lantern{f}{b}{k}", 0.9, (px + 11 * math.cos(a + 0.6 - 1.2 * k), py + 11 * math.sin(a + 0.6 - 1.2 * k), z + 3.6),
                             BUTTER, subdiv=2, squash=(1, 1, 1.3), jitter=0))
                spots += [(px + x, py + y) for x, y in ring_xy(4, 7.0, a + math.pi / 4)]
            else:
                spots += [(px * 1.1 + x, py * 1.1 + y) for x, y in ring_xy(4, 7.0, a + math.pi / 4)]
        for k, (x, y) in enumerate(spots):
            add(cylinder(f"Nest{f}{k}", 3.0, 1.6, (x, y, z), BUTTER, segs=12, r_top=3.4, jitter=0.08, seed=k), shade(BUTTER, 0.75), BUTTER)
            add(cylinder(f"NestIn{f}{k}", 2.4, 0.3, (x, y, z + 1.4), shade(BUTTER, 0.7), segs=12))
            if R.random() < 0.8:
                slime(x, y, z + 1.4, f * 8 + k)
        # spiral steps round the trunk up to the next floor
        if f < V:
            for k in range(14):
                a = k / 14 * math.tau * 0.9 + f * 2.0
                add(bbox(f"Step{f}{k}", (4.5, 2.4, 0.6), ((9.0 + 2.2) * math.cos(a), (9.0 + 2.2) * math.sin(a), z + 1.0 + k),
                         shade(WOOD, 0.9), WOOD, bev=0.1, rot=(0, 0, math.degrees(a))))
    # canopy grows with the version; goo fruit at version 4
    size = 13 + V * 3.0
    cz = trunk_top + size * 0.35
    add(blob("Canopy", size, (0, 0, cz), FIELD, subdiv=3, squash=(1, 1, 0.55), lumps=0.12, jitter=0.03), FIELD_D, FIELD_L)
    for k, (x, y) in enumerate(ring_xy(5, size * 0.8, 0.4)):
        add(blob(f"Puff{k}", size * 0.42, (x, y, cz - size * 0.15), FIELD, subdiv=2, squash=(1, 1, 0.7), jitter=0.05), FIELD_D, FIELD_L)
    if V >= 4:
        for k, (x, y) in enumerate(ring_xy(9, size * 0.9, 0.2)):
            add(blob(f"Fruit{k}", 1.6, (x, y, cz - size * 0.42), GOO, subdiv=2, squash=(1, 1, 1.25), jitter=0))
    add(rpost("LockPost", 12, -30, 3.0)[0])
    add(blob("LockBtn", 1.4, (12, -30, 3.6), ROOF, subdiv=2, squash=(1, 1, 0.55), jitter=0))


# --- C. Floating islands -----------------------------------------------------------------------------------------
def islands_concept():
    isl = [((0, -4), 34, 0.0), ((-17, 15), 18, top(2)), ((17, 15), 18, top(3)), ((0, 20), 17, top(4))]
    for f in range(1, V + 1):
        (cx, cy), r, z = isl[f - 1]
        z = max(z, 1.0)
        # grass top, dirt underside tapering to a point (floor 1 sits on a low mound)
        z = z + (2.0 if f == 1 else 0.0)
        add(cylinder(f"Grass{f}", r, 1.2, (cx, cy, z - 1.2), FIELD_L, segs=32, jitter=0.03, seed=f), mix(FIELD_L, BUTTER, 0.1), mix(FIELD_L, BUTTER, 0.25))
        depth = 3.0 if f == 1 else 2.5
        add(cylinder(f"Dirt{f}", r * 0.97, depth, (cx, cy, z - 1.2 - depth), PATH, segs=32, r_top=r * 0.97, jitter=0.04, seed=f),
            shade(PATH, 0.8), PATH)
        if f > 1:
            add(cone(f"Under{f}", r * 0.92, 9.0, (cx, cy, z - 3.7), shade(PATH, 0.9), segs=32, rot=(180, 0, 0)), shade(PATH, 0.7), PATH)
            for k, (x, y) in enumerate(ring_xy(6, r * 0.5, f)):
                add(tube(f"Dangle{f}{k}", [(cx + x, cy + y, z - 4), (cx + x * 1.1, cy + y * 1.1, z - 7.5)], [0.5, 0.2], WOOD_D, segs=5))
        # mushroom pads in a ring with slimes
        spots = ring_xy(8, r * 0.62, math.pi / 8)
        if f == 1:  # the ground island keeps its pads in front, clear of the islands floating over its back
            spots = [(x, y) for y in (-12.0, -25.0) for x in (-21.0, -7.0, 7.0, 21.0)]
        for k, (x, y) in enumerate(spots):
            add(cylinder(f"Stalk{f}{k}", 1.2, 1.4, (cx + x, cy + y, z), CREAM, segs=10))
            cap = PINK if (k + f) % 2 else ROOF
            add(cylinder(f"Cap{f}{k}", 3.5, 1.1, (cx + x, cy + y, z + 1.4), cap, segs=14, r_top=2.6), shade(cap, 0.85), cap)
            for d, (dx, dy) in enumerate(ring_xy(3, 1.6, k)):
                add(blob(f"Dot{f}{k}{d}", 0.4, (cx + x + dx, cy + y + dy, z + 2.55), CREAM, subdiv=1, squash=(1, 1, 0.5), jitter=0))
            if R.random() < 0.8:
                slime(cx + x, cy + y, z + 2.5, f * 8 + k)
        # bounce pad up to the next island + a goo waterfall down from this one
        if f < V:
            (nx, ny), nr, nz = isl[f]
            bx, by = cx + (nx - cx) * 0.25 + 6, cy + (ny - cy) * 0.25 - 6
            add(cylinder(f"BounceRing{f}", 4.4, 1.0, (bx, by, z), mix(LILAC, CREAM, 0.2), segs=18))
            add(blob(f"Bounce{f}", 3.0, (bx, by, z + 0.8), GOO, subdiv=2, squash=(1, 1, 0.35), jitter=0))
        if f > 1:
            wx, wy = cx + r * 0.9, cy - r * 0.3
            low = top(f - 1) + (2.0 if f == 2 else 0.0)
            add(blob(f"Lip{f}", 2.2, (wx, wy, z - 0.2), GOO, subdiv=2, squash=(1.4, 1, 0.5), jitter=0))
            add(box(f"Fall{f}", (3.2, 0.7, z - low), (wx + 0.8, wy - 0.3, (z + low) / 2), GOO), shade(GOO, 0.85), GOO_HI)
            add(blob(f"Splash{f}", 2.8, (wx + 0.8, wy - 0.3, low + 0.1), GOO_HI, subdiv=2, squash=(1.3, 1.3, 0.3), jitter=0.05))
            add(cylinder(f"Pole{f}", 0.3, 7, (cx - r * 0.7, cy + r * 0.3, z), WOOD_D, segs=6))
            add(box(f"Flag{f}", (3.6, 0.2, 2.2), (cx - r * 0.7 + 1.9, cy + r * 0.3, z + 6), mix(LILAC, CREAM, 0.15)))
    if V >= 4:
        (cx, cy), r, z = isl[3]
        add(blob("Crystal", 3.2, (cx, cy, z + 4.5), GOO, subdiv=1, squash=(1, 1, 2.0), jitter=0.0))
        add(cylinder("CrystalBase", 3.4, 1.2, (cx, cy, z), mix(LILAC, CREAM, 0.2), segs=12))
    # entrance: a flower arch on the front of island 1; lock as a mushroom button
    for s in (-1, 1):
        add(tube(f"Arch{s}", [(s * 6, -34, 0.8), (s * 6.5, -34.5, 7), (s * 3, -34.5, 10.5), (0, -34.5, 11.5)], [0.8, 0.7, 0.6, 0.6],
                 FIELD_D, segs=6))
        for k in range(4):
            add(blob(f"Flower{s}{k}", 0.9, (s * (6.4 - k * 1.5), -35.2, 4.5 + k * 2.0), [PINK, BUTTER, LILAC][k % 3], subdiv=1, jitter=0))
    add(cylinder("LockStalk", 1.0, 2.2, (14, -33, 1.0), CREAM, segs=10))
    add(blob("LockBtn", 1.6, (14, -33, 3.4), ROOF, subdiv=2, squash=(1, 1, 0.55), jitter=0))


{"jar": jar_concept, "tree": tree_concept, "islands": islands_concept}[CONCEPT]()

import bpy

everything = [o for o in bpy.data.objects if o.type == "MESH"]
turn = math.radians(float(os.environ.get("BASE_TURN", "-25")))
for o in everything:
    o.rotation_euler.z += turn
finish("base_concepts_scene", everything)
