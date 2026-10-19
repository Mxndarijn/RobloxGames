# Design preview (not an asset): the "goo silo" plot remodel at version SILO_V (1..4, env), true scale in studs.
# 80 x 80 plot, entrance at -Y. A glass-staved goo silo stands on the merge vat in the centre; 8 crate pads sit on a
# 3 x 3 grid around it on every floor; floors are 14 studs apart; plank ramps beside the decks take turns
# (right side climbing to +Y, left side climbing to -Y). The plot colour in this preview is ranch_lilac.
import math
import os
import random

from lib import *
from models._phoenix_ranch import *
from models._pad_crate import crate_parts

V = int(os.environ.get("SILO_V", "4"))
FLOOR_H = 14.0
HALF = 40.0
DECK = 28.0  # deck half size
PITCH = 16.0
TRIM = mix(P["ranch_lilac"], CREAM, 0.25)
PLAZA = P["ranch_plaza"]
METAL = P["ranch_metal"]
LILAC = P["ranch_lilac"]

parts = []


def top(f):
    return 1.0 + (f - 1) * FLOOR_H


def moved(objs, dx=0.0, dy=0.0, dz=0.0, rz=0.0):
    for o in objs:
        if rz:
            o.rotation_euler.z += rz
            c, s = math.cos(rz), math.sin(rz)
            x, y = o.location.x, o.location.y
            o.location.x, o.location.y = x * c - y * s, x * s + y * c
        o.location.x += dx
        o.location.y += dy
        o.location.z += dz
    return objs


def slime(name, pos, col, r=1.7):
    o = blob(name, r, pos, col, subdiv=2, squash=(1, 1, 0.78), jitter=0.02)
    gradient(o, shade(col, 0.82), col)
    return o


# Ground: packed-dirt plot floor with a plot-colour edge band.
parts.append(bbox("Floor", (2 * HALF, 2 * HALF, 1.0), (0, 0, 0.5), shade(PLAZA, 0.9), PLAZA, bev=0.2))
for k, (sx, sy, w, d) in enumerate(((0, -1, 80, 1.2), (0, 1, 80, 1.2), (-1, 0, 1.2, 80), (1, 0, 1.2, 80))):
    parts.append(bbox(f"Band{k}", (w, d, 0.25), (sx * (HALF - 0.6), sy * (HALF - 0.6), 1.05), shade(TRIM, 0.9), TRIM, bev=0.05))

# Fence: plank walls on three sides, two front wings beside the gate.
for k, (x0, x1, rz, off) in enumerate(((-40, 40, 0, (0, HALF)), (-40, 40, -math.pi / 2, (-HALF, 0)), (-40, 40, math.pi / 2, (HALF, 0)))):
    wall = board_wall(f"W{k}", x0, x1, 8.0, seed=k + 3)
    if k == 0:
        moved(wall, rz=math.pi)
        moved(wall, dy=HALF)
    else:
        moved(wall, rz=rz)
        moved(wall, dx=off[0])
for k, (x0, x1) in enumerate(((-40, -10), (10, 40))):
    moved(board_wall(f"F{k}", x0, x1, 8.0, seed=k + 9), dy=-HALF)
for k, (x, y) in enumerate(((-40, -40), (40, -40), (-40, 40), (40, 40), (-10, -40), (10, -40))):
    parts += rpost(f"Corner{k}", x, y, 9.0, w=1.8)

# Gate arch: tall posts, the name board, a little goo-silo finial on top.
for s in (-1, 1):
    parts.append(bbox(f"GatePost{s}", (2.2, 2.2, 17), (s * 10, -HALF, 8.5), shade(WOOD_D, 0.9), WOOD_D, bev=0.2))
    parts.append(bbox(f"GateCap{s}", (2.8, 2.8, 0.6), (s * 10, -HALF, 17.3), shade(CREAM, 0.9), CREAM))
parts.append(bbox("GateBeam", (23, 1.6, 1.6), (0, -HALF, 15.5), shade(WOOD, 0.85), WOOD, bev=0.2))
parts.append(bbox("NameBoard", (12, 0.6, 3.2), (0, -HALF - 1.0, 12.5), shade(CREAM, 0.92), CREAM, bev=0.2))
parts.append(bbox("NameTrim", (12.8, 0.4, 3.8), (0, -HALF - 0.75, 12.5), shade(TRIM, 0.9), TRIM, bev=0.15))
parts.append(cylinder("FinialTank", 1.6, 3.0, (0, -HALF, 16.3 - 1.5), P["ranch_goo"], segs=12))
parts.append(cylinder("FinialBand", 1.85, 0.5, (0, -HALF, 17.0), METAL, segs=12))
parts.append(blob("FinialDome", 1.6, (0, -HALF, 19.3), P["ranch_goo_hi"], subdiv=2, squash=(1, 1, 0.7), jitter=0))

# Lock button pedestal, front right; Dex board on the back fence.
parts.append(bbox("LockPost", (3.0, 3.0, 3.2), (30, -30, 2.6), shade(WOOD_D, 0.9), WOOD_D, bev=0.25))
parts.append(blob("LockButton", 1.3, (30, -30, 4.5), P["ranch_roof"], subdiv=2, squash=(1, 1, 0.55), jitter=0))
for s in (-1, 1):
    parts.append(bbox(f"DexLeg{s}", (1.2, 1.2, 12), (s * 8, HALF - 2.5, 6.5), shade(WOOD_D, 0.9), WOOD_D))
parts.append(bbox("DexBoard", (18, 0.8, 8), (0, HALF - 2.5, 9.5), shade(WOOD, 0.85), WOOD, bev=0.25))
parts.append(bbox("DexFace", (16, 0.3, 6.2), (0, HALF - 3.0, 9.5), shade(CREAM, 0.92), CREAM))

# The silo: barrel merge vat at the bottom, goo column up to the current version, glass staves, a metal band per
# floor, a lid (or the dome crown at version 4).
SILO_R = 7.6
parts.append(cylinder("Vat", 9.0, 4.0, (0, 0, 1.0), WOOD, segs=24, r_top=8.6))
gradient(parts[-1], shade(WOOD, 0.85), WOOD)
for k, z in enumerate((1.6, 3.8)):
    parts.append(cylinder(f"VatHoop{k}", 9.1 - k * 0.3, 0.5, (0, 0, z), METAL, segs=24))
silo_top = top(V) + 20.0
goo_top = top(V) + 15.0
goo = cylinder("Goo", SILO_R - 0.6, goo_top - 5.0, (0, 0, 5.0), P["ranch_goo"], segs=24)
gradient(goo, shade(P["ranch_goo"], 0.85), mix(P["ranch_goo"], P["ranch_goo_hi"], 0.35))
parts.append(goo)
parts.append(cylinder("GooTop", SILO_R - 0.7, 0.4, (0, 0, goo_top), P["ranch_goo_hi"], segs=24))
GLASS = mix(P["ranch_goo_hi"], CREAM, 0.5)
for k in range(8):
    a = k / 8 * math.tau + math.pi / 8
    parts.append(cylinder(f"Stave{k}", 0.32, silo_top - 5.0, (SILO_R * math.cos(a), SILO_R * math.sin(a), 5.0), GLASS, segs=6))
for k, z in enumerate([5.0] + [top(f) + 7.0 for f in range(1, V + 1)] + [silo_top - 0.8]):
    parts.append(cylinder(f"Band{k}", SILO_R + 0.5, 0.8, (0, 0, z), METAL, segs=24))
if V >= 4:
    dome = blob("Dome", SILO_R + 0.4, (0, 0, silo_top), GLASS, subdiv=3, squash=(1, 1, 0.62), jitter=0)
    parts.append(dome)
    parts.append(blob("Crown", 3.0, (0, 0, silo_top + 4.6), P["ranch_goo"], subdiv=3, squash=(1, 1, 0.8), jitter=0.03))
    for k in range(7):
        a = k / 7 * math.tau
        parts.append(blob(f"Drip{k}", 1.0, (5.6 * math.cos(a), 5.6 * math.sin(a), silo_top + 2.4), P["ranch_goo"], subdiv=2,
                          squash=(1, 1, 1.4), jitter=0))
else:
    roof = cylinder("Roof", SILO_R + 1.2, 5.5, (0, 0, silo_top), P["ranch_roof"], segs=24, r_top=1.0)
    gradient(roof, shade(P["ranch_roof"], 0.8), P["ranch_roof"])
    parts.append(roof)
    parts.append(blob("RoofKnob", 1.2, (0, 0, silo_top + 5.6), CREAM, subdiv=2, jitter=0))

# Decks 2..V: planks, plot-colour fascia, corner posts, rope rails front and back.
for f in range(2, V + 1):
    z = top(f)
    for k, (x0, x1, y0, y1) in enumerate(((-DECK, DECK, 9.0, DECK), (-DECK, DECK, -DECK, -9.0), (-DECK, -9.0, -9.0, 9.0), (9.0, DECK, -9.0, 9.0))):
        parts.append(bbox(f"Deck{f}{k}", (x1 - x0, y1 - y0, 0.9), ((x0 + x1) / 2, (y0 + y1) / 2, z - 0.45),
                          shade(WOOD, 0.88), WOOD, bev=0.1))
    for k, (sx, sy, w, d) in enumerate(((0, -1, 2 * DECK + 0.4, 0.4), (0, 1, 2 * DECK + 0.4, 0.4), (-1, 0, 0.4, 2 * DECK + 0.4), (1, 0, 0.4, 2 * DECK + 0.4))):
        parts.append(bbox(f"Fascia{f}{k}", (w, d, 1.3), (sx * DECK, sy * DECK, z - 0.65), shade(TRIM, 0.88), TRIM, bev=0.08))
    for k, (x, y) in enumerate(((-DECK + 1, -DECK + 1), (DECK - 1, -DECK + 1), (-DECK + 1, DECK - 1), (DECK - 1, DECK - 1))):
        parts.append(bbox(f"Leg{f}{k}", (1.6, 1.6, FLOOR_H - 0.9), (x, y, top(f - 1) + (FLOOR_H - 0.9) / 2), shade(WOOD_D, 0.9), WOOD_D, bev=0.15))
    for sy in (-1, 1):
        for i in range(8):
            x = -DECK + 1.5 + i * (2 * DECK - 3) / 7
            parts.append(bbox(f"RailPost{f}{sy}{i}", (0.7, 0.7, 3.2), (x, sy * (DECK - 0.6), z + 1.6), shade(WOOD_D, 0.92), WOOD_D, bev=0.08))
        parts.append(bbox(f"Rope{f}{sy}", (2 * DECK - 2, 0.35, 0.35), (0, sy * (DECK - 0.6), z + 2.8), shade(P["ranch_butter"], 0.9), P["ranch_butter"], bev=0.05))

# Ramps: ramp f rises from floor f-1 to floor f beside the deck, right side towards +Y on even floors, left side
# towards -Y on odd floors. A plank slab on two leg pairs with an outer rope rail.
RUN = 24.0
for f in range(2, V + 1):
    side = 1 if f % 2 == 0 else -1
    x = side * (DECK + 3.5)
    z0, z1 = top(f - 1), top(f)
    length = math.hypot(RUN, z1 - z0)
    pitch = math.atan2(z1 - z0, RUN) * (1 if side > 0 else -1)
    ramp = bbox(f"Ramp{f}", (6.0, length, 0.7), (x, 0, (z0 + z1) / 2), shade(WOOD, 0.9), WOOD, bev=0.1, rot=(math.degrees(pitch), 0, 0))
    parts.append(ramp)
    for k in range(5):
        t = (k + 0.5) / 5
        y = (-RUN / 2 + t * RUN) * side
        zz = z0 + t * (z1 - z0)
        parts.append(bbox(f"Cleat{f}{k}", (6.0, 0.4, 0.25), (x, y, zz + 0.45), shade(WOOD_D, 0.92), WOOD_D, bev=0.04))
    high_y = RUN / 2 * side
    parts.append(bbox(f"RampLeg{f}", (1.2, 1.2, z1 - z0), (x + side * 2.4, high_y, (z0 + z1) / 2), shade(WOOD_D, 0.9), WOOD_D))
    parts.append(bbox(f"Landing{f}", (6.0, 4.0, 0.9), (x, high_y + side * 2.0, z1 - 0.45), shade(WOOD, 0.88), WOOD, bev=0.1))
    rail = bbox(f"RampRope{f}", (0.35, length, 0.35), (x + side * 3.0, 0, (z0 + z1) / 2 + 2.8), P["ranch_butter"], P["ranch_butter"],
                bev=0.05, rot=(math.degrees(pitch), 0, 0))
    parts.append(rail)

# Pads: the crate pad on every grid spot but the centre, on floors 1..V; slimes on most of them.
SLIMES = [P["ranch_pink"], LILAC, P["ranch_butter"], P["ranch_goo"], rgb(120, 190, 250), rgb(250, 160, 90)]
R = random.Random(7)
n = 0
for f in range(1, V + 1):
    for gx in (-1, 0, 1):
        for gy in (-1, 0, 1):
            if gx == 0 and gy == 0:
                continue
            px, py = gx * PITCH, gy * PITCH
            moved(crate_parts(dz=top(f)), dx=px, dy=py)
            n += 1
            if R.random() < 0.8:
                parts.append(slime(f"Slime{n}", (px, py, top(f) + 2.6 + 1.3), SLIMES[n % len(SLIMES)]))

import bpy

everything = [o for o in bpy.data.objects if o.type == "MESH"]
moved(everything, rz=math.radians(float(os.environ.get("SILO_TURN", "0"))))
finish("goo_silo_base_scene", everything)
