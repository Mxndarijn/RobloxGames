# wall_low: low warm-stone wall with a wooden top rail (plot kit), one 7-stud segment (x -3.5..+3.5),
# ~2.4 tall, ~1.1 deep. Alternative to fence_straight on the same grid; front faces -Y.
import random
import bmesh
from lib import *
from models._fence import *

L = SEGMENT
R = random.Random(11)
parts = []


def stone(name, x0, x1, z0, z1, depth, col):
    o = box(name, (x1 - x0 - 0.06, depth, z1 - z0 - 0.04), ((x0 + x1) / 2, R.uniform(-0.04, 0.04), (z0 + z1) / 2), col)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for v in bm.verts:  # chip the corners a little so the blocks read as stone, not bricks
        v.co.x += R.uniform(-0.06, 0.06)
        v.co.y += R.uniform(-0.05, 0.05)
        if v.co.z > z0 + 0.1:
            v.co.z += R.uniform(-0.07, 0.04)
    bm.to_mesh(o.data)
    bm.free()
    gradient(o, shade(col, 0.82), col)
    return o


# two courses of uneven stones, joints staggered
courses = [(0.0, 0.85, 1.1, [0, 1.9, 3.6, 5.4, 7.0]), (0.85, 1.65, 1.0, [0, 1.1, 2.9, 4.4, 6.0, 7.0])]
k = 0
for z0, z1, d, cuts in courses:
    for a, b in zip(cuts, cuts[1:]):
        col = (STONE, STONE_ALT, shade(STONE, 1.05))[k % 3]
        parts.append(stone(f"Stone{k}", a - L / 2, b - L / 2, z0, z1, d, col))
        k += 1
# wooden top: short posts at the ends, a sill beam on the stones and a top rail
for i, s in enumerate((-1, 1)):
    parts += post(f"Post{i}", s * L / 2, 0, 0.7, 2.3, cap_h=0.25)
parts.append(beam("Sill", -L / 2, L / 2, 0, 1.8, 0.9, 0.3, RAIL, lo=shade(RAIL, 0.88)))
parts.append(beam("Rail", -L / 2, L / 2, 0, 2.12, 0.5, 0.3, CAP, lo=shade(CAP, 0.88)))
finish("wall_low", parts)
