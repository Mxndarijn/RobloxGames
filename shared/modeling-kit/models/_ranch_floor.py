# Shared builders for the B11 floor meshes (ranch_floor_deck, ranch_floor_paths): hub-centred, 8-fold symmetric
# boardwalk geometry in studs, flat on z = 0. Placed once each at the hub (0, 0) by WorldLayout via FloorLayout; the
# bbox is symmetric about the hub on purpose, so the slot box centre IS the hub whatever the mesh's import turn.
#
# Colour: the game tints these with the slot colour (MeshTint, MeshPart.Color x vertex colour) and SnowGround frosts the
# MeshPart colour toward snow white. So the slot colour is the BRIGHTEST colour of the mesh and every vertex colour is a
# ratio <= 1 of it (a multiply can only darken: the mesh must not hold anything brighter than its slot colour).
#
# Angles are Roblox bearings (0 = +Z, clockwise towards +X). Kit (x, y) = (r sin a, -r cos a), because Roblox z = -kit y.
import math, random

import bmesh
from lib import *
from lib.shapes import obj_from_bm

# Walk surface layers above FLOOR_Y (mirrors shared FloorLayout, which is the source of truth for the game side).
PLANK_TOP = 0.17
TRIM_TOP = 0.21

PLANK_A = (184, 134, 84)
PLANK_B = (168, 120, 72)
TRIM_DARK = (112, 72, 42)
INLAY = (244, 232, 200)


def pol(a_deg, r):
    a = math.radians(a_deg)
    return (r * math.sin(a), -r * math.cos(a))


def ratio(c, base, k=1.0):
    """Vertex colour = c / base (per channel, <= 1), times a brightness jitter k."""
    return tuple(min(1.0, c[i] / base[i] * k) for i in range(3)) + (1.0,)


def _solid(name, bottom, top, z0, z1, color):
    """Closed prism between two plan polylines of equal length (`bottom` and `top` edges of a strip), quads per step."""
    bm = bmesh.new()
    n = len(bottom)
    lo = [bm.verts.new((x, y, z0)) for x, y in bottom]
    hi = [bm.verts.new((x, y, z1)) for x, y in bottom]
    lo2 = [bm.verts.new((x, y, z0)) for x, y in top]
    hi2 = [bm.verts.new((x, y, z1)) for x, y in top]
    for i in range(n - 1):
        bm.faces.new((hi[i], hi[i + 1], hi2[i + 1], hi2[i]))  # top
        bm.faces.new((lo[i], lo2[i], lo2[i + 1], lo[i + 1]))  # bottom
        bm.faces.new((lo[i], lo[i + 1], hi[i + 1], hi[i]))  # wall on the `bottom` edge
        bm.faces.new((lo2[i + 1], lo2[i], hi2[i], hi2[i + 1]))  # wall on the `top` edge
    bm.faces.new((lo[0], hi[0], hi2[0], lo2[0]))  # end caps
    bm.faces.new((lo[n - 1], lo2[n - 1], hi2[n - 1], hi[n - 1]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return obj_from_bm(name, bm, color)


def arc_strip(name, r0, r1, a0, a1, step, z0, z1, color):
    """Ring segment between radii r0 < r1 and bearings a0 -> a1, one quad per `step` degrees."""
    n = max(1, int(math.ceil((a1 - a0) / step - 1e-9)))
    angles = [a0 + (a1 - a0) * i / n for i in range(n + 1)]
    return _solid(name, [pol(a, r0) for a in angles], [pol(a, r1) for a in angles], z0, z1, color)


def trapezoid(name, a0, a1, r0, r1, z0, z1, color):
    """One radial plank: straight edges from (a0, a1 at r0) to (a0, a1 at r1)... a0/a1 = the plank's edge bearings."""
    return _solid(name, [pol(a0, r0), pol(a0, r1)], [pol(a1, r0), pol(a1, r1)], z0, z1, color)


def slab(name, bearing, s0, s1, l0, l1, z0, z1, color):
    """Box along a spoke: s = distance along the bearing, l = lateral offset (right of the bearing is +)."""
    a = math.radians(bearing)
    dx, dy = math.sin(a), -math.cos(a)  # along, kit
    lx, ly = math.cos(a), math.sin(a)  # lateral, kit

    def p(s, l):
        return (dx * s + lx * l, dy * s + ly * l)

    return _solid(name, [p(s0, l0), p(s1, l0)], [p(s0, l1), p(s1, l1)], z0, z1, color)
