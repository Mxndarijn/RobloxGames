# habitat_prop_sunny: a tiny striped sun lounger (white wooden frame, orange/white striped cloth) with sunglasses.
import math
from lib import *
from models._habitat_prop2 import *

ORANGE = rgb(255, 140, 50)
L = 1.5  # seat length along x
parts = []
# frame: seat rail pair, legs, back rest raised at the -x end
SEAT_Z = 0.32
for s in (-1, 1):
    y = s * 0.36
    parts.append(box(f"Rail{s}", (1.0, 0.06, 0.06), (0.2, y, SEAT_Z), WOOD))
    for x in (-0.25, 0.65):
        parts.append(box(f"Leg{s}{x}", (0.06, 0.06, SEAT_Z), (x, y, SEAT_Z / 2), WOOD_D))
    # back rest rail, tilted 50 deg
    parts.append(move(box(f"Back{s}", (0.7, 0.06, 0.06), (0, 0, 0), WOOD), (-0.55, y, SEAT_Z + 0.25), rot=(0, 50, 0)))
    parts.append(box(f"Strut{s}", (0.06, 0.06, 0.45), (-0.44, y, SEAT_Z / 2 + 0.05), WOOD_D))


def stripes(o, axis_fn):
    return paint(o, lambda c, n: ORANGE if int(axis_fn(c) / 0.12 + 100) % 2 else WHITE)


# cloth: seat slab and back slab, striped across the length
seat = box("Seat", (1.0, 0.66, 0.05), (0.2, 0, SEAT_Z + 0.04))
bm_sub = seat
import bmesh
bm = bmesh.new()
bm.from_mesh(seat.data)
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.x - e.verts[1].co.x) > 0.5], cuts=7)
bm.to_mesh(seat.data)
bm.free()
stripes(seat, lambda c: c.x)
parts.append(seat)
back = box("BackCloth", (0.72, 0.66, 0.05), (0, 0, 0))
bm = bmesh.new()
bm.from_mesh(back.data)
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.x - e.verts[1].co.x) > 0.5], cuts=5)
bm.to_mesh(back.data)
bm.free()
stripes(back, lambda c: c.x)
parts.append(move(back, (-0.53, 0, SEAT_Z + 0.29), rot=(0, 50, 0)))
# pillow at the head
parts.append(blob("Pillow", 0.17, (-0.62, -0.0, SEAT_Z + 0.5), YELLOW, subdiv=2, squash=(0.6, 1.5, 0.6), jitter=0, rot=(0, 50, 0)))
# sunglasses on the seat
for s in (-1, 1):
    parts.append(lathe(f"Lens{s}", [(0.0, 0), (0.08, 0), (0.08, 0.025), (0.0, 0.025)], pos=(0.45, s * 0.1, SEAT_Z + 0.065), segs=10, col=BLACK))
parts.append(box("Bridge", (0.03, 0.06, 0.02), (0.45, 0, SEAT_Z + 0.075), BLACK))
ship("habitat_prop_sunny", parts)
