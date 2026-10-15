# parade_lane_countdown_ring: flat annulus that sits in the parade_lane_gate drain basin's ring seat
# (r 1.5..2.3 groove, floor z 0.20 above the gate's base). r 1.6..2.2, 0.1 thick, one colour
# (ranch_butter); the game tints it neon and sweeps/fades it as the despawn countdown while the slime
# (3 studs, r ~1.5) shrinks into the drain inside it.
# Placement: MeshPart centre = basin centre (printed by parade_lane_gate.py), bottom at the gate's
# base + 0.20 (pivot = bbox centre, so CFrame y = gate base + 0.25). Top sits 0.03 proud of the groove.
import math
import bmesh
from lib import *

R0, R1, TH, SEGS = 1.6, 2.2, 0.1, 40
bm = bmesh.new()
rings = []
for r in (R0, R1):
    for z in (0.0, TH):
        rings.append([bm.verts.new((r * math.cos(k * math.tau / SEGS), r * math.sin(k * math.tau / SEGS), z))
                      for k in range(SEGS)])
ib, it, ob, ot = rings
for k in range(SEGS):
    j = (k + 1) % SEGS
    bm.faces.new((it[k], it[j], ot[j], ot[k]))
    bm.faces.new((ob[k], ob[j], ib[j], ib[k]))
    bm.faces.new((ot[k], ot[j], ob[j], ob[k]))
    bm.faces.new((ib[k], ib[j], it[j], it[k]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
parts = [obj_from_bm("Ring", bm, PALETTE["ranch_butter"])]
finish("parade_lane_countdown_ring", parts)
