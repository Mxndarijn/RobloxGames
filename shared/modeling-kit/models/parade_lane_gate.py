# parade_lane_gate: the despawn-gate segment of the goo-parade lane (Slime Ranch, Steal a Slime hub).
# Same 45-degree channel as parade_lane_arc45 (identical end profiles: 7 arcs + this gate = full ring),
# plus, at its middle (-90 deg, kit front):
#  - a round goo drain basin where a wild slime stops, the countdown ring lights up round it and the
#    slime shrinks away into the swirl (telegraphed despawn, never a silent pop);
#  - a flat ring seat (groove) r 1.5..2.3, floor z = SEAT_Z, for parade_lane_countdown_ring
#    (r 1.6..2.2, 0.1 thick -> top 0.03 proud of the groove rims);
#  - a small ranch arch over the lane: posts on the lane edges (outside the edging), beam
#    underside >= 9 (players can walk the lane under it), red sign board with butter faces and a
#    little red roof. The lane edging bulges round the basin.
# Placement: like the arc (hub offset printed); basin/ring centre printed too.
import math
import bmesh
from mathutils import Vector
from lib import *
from models._parade_lane import *

SPAN = 45.0
ARC = math.radians(SPAN) * R_C            # centreline length of the segment
BX, BY = 0.0, -R_C                        # basin centre (kit, hub at the origin)
WB, LB = 3.35, 5.2                        # channel half width at the basin, blend half length
SEAT_Z = 0.20                             # countdown-ring seat floor
BEAM_UNDER = 9.6
POST_D = 4.75                             # posts' radial offset from the centreline


def width(t):
    x = (t - 0.5) * ARC
    if abs(x) >= LB:
        return W_CH
    return W_CH + (WB - W_CH) * (1 + math.cos(math.pi * x / LB)) / 2


dense = [0.5 + x / ARC for x in (-4.0, -2.4, -0.8, 0.8, 2.4, 4.0)]
ts = ring_ts(SPAN, planks=6, interior=1, extra=dense)


# ------------------------------------------------------------------ drain basin (surface of revolution)
SEGS = 24
BASIN = [  # (r, z, tag) top profile from the drain outward
    (0.0, 0.07, "drain"), (0.8, 0.11, "swirl"), (1.32, 0.23, "lip"),
    (1.5, 0.27, "groove"), (1.54, SEAT_Z, "seat"), (2.26, SEAT_Z, "groove"), (2.3, 0.27, "lip"),
    (2.65, 0.38, "rim"), (2.95, 0.50, "rim"), (3.3, 0.40, "goo"), (3.6, 0.24, "goo"), (3.6, 0.0, "base")]


def basin_top(r):
    """basin top-profile height at radius r (linear between the profile rows)"""
    for (r0, z0, _), (r1, z1, _) in zip(BASIN, BASIN[1:]):
        if r0 <= r <= r1 and r1 > r0:
            return z0 + (z1 - z0) * (r - r0) / (r1 - r0)
    return None


def basin_cut(d, t, z):
    """keep the channel goo just under the basin (the basin shell is the visible surface there)"""
    a = ang(t, SPAN)
    r = math.hypot((R_C + d) * math.cos(a) - BX, (R_C + d) * math.sin(a) - BY)
    if r < 2.4:
        return 0.03
    bz = basin_top(r)
    return min(z, bz - 0.05) if bz is not None else z


goo_ts = sorted([(k / 16, False) for k in range(17) if abs(k / 16 - 0.5) > 0.07] + [(t, False) for t in dense])
parts = [channel("Goo", SPAN, goo_ts, width_fn=width, z_fn=basin_cut)]
parts.append(rail("RailIn", -1, SPAN, ts, width))
parts.append(rail("RailOut", 1, SPAN, ts, width))
for side, t in ((1, 1 / 6), (1, 5 / 6), (-1, 2 / 6 - 0.04), (-1, 4 / 6 + 0.04)):
    parts += post(f"Stake{side}{t:.2f}", side, SPAN, t)


def basin():
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    rings = []
    for r, z, _ in BASIN[1:]:
        rings.append([bm.verts.new((BX + r * math.cos(k * math.tau / SEGS), BY + r * math.sin(k * math.tau / SEGS), z))
                      for k in range(SEGS)])
    top, bot = bm.verts.new((BX, BY, BASIN[0][1])), bm.verts.new((BX, BY, 0.0))
    SW = shade(GOO, 0.8)

    def col(row, k):
        tag = BASIN[row][2]
        if tag in ("drain", "swirl"):   # spiral stripes running into the drain
            return GOO_HI if ((k + 2 * row) // 2) % 2 == 0 else (shade(GOO, 0.74) if row == 0 else SW)
        if tag in ("lip", "rim"):
            return mix(GOO, GOO_HI, 0.75 if tag == "rim" else 0.45)
        if tag in ("groove", "seat"):
            return shade(GOO, 0.82)
        return GOO

    def face(vs, c):
        f = bm.faces.new(vs)
        for lp in f.loops:
            lp[layer] = c
    for k in range(SEGS):
        j = (k + 1) % SEGS
        face((top, rings[0][k], rings[0][j]), col(0, k))
        for row in range(len(rings) - 1):
            face((rings[row][k], rings[row + 1][k], rings[row + 1][j], rings[row][j]), col(row + 1, k))
        face((rings[-1][j], rings[-1][k], bot), shade(GOO, 0.8))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm("Basin", bm)


parts.append(basin())


# ------------------------------------------------------------------ ranch arch (spans radially, Y)
def wbox(name, size, pos, lo, hi, bev=0.12, rot=(0, 0, 0)):
    o = box(name, size, pos, lo, rot=rot)
    if bev:
        bevel(o, bev)
    gradient(o, lo, hi)
    return o


TOP = 11.2  # post top
for sy in (-1, 1):
    y = BY + sy * POST_D
    parts.append(wbox(f"Foot{sy}", (2.0, 2.0, 0.7), (BX, y, 0.35), mix(WOOD_LO, WOOD, 0.4), WOOD, bev=0.16))
    parts.append(wbox(f"Post{sy}", (1.45, 1.45, TOP), (BX + 0.05 * sy, y, TOP / 2), mix(WOOD_LO, WOOD, 0.5), WOOD_HI))
    parts.append(cylinder(f"Knob{sy}", 0.85, 0.55, (BX, y, TOP), CAP, segs=8, r_top=0.5))
    # knee brace post -> beam (stays above the edging, never over the goo)
    parts.append(wbox(f"Brace{sy}", (0.5, 0.5, 2.0), (BX, y - sy * 1.15, BEAM_UNDER - 0.55), WOOD_LO, WOOD,
                      bev=0, rot=(sy * 45, 0, 0)))
# plaque on the hub-facing side of the inner post: what players on the plaza see (SurfaceGui-ready)
PY = BY + POST_D + 0.725
parts.append(wbox("Plaque", (2.6, 0.3, 2.0), (BX, PY + 0.1, 6.2), mix(ROOF_D, ROOF, 0.5), ROOF, bev=0.1))
parts.append(wbox("PlaqueFace", (2.0, 0.2, 1.4), (BX, PY + 0.3, 6.2), shade(BUTTER, 0.92), BUTTER, bev=0))
parts.append(wbox("Beam", (1.1, 2 * POST_D + 2.4, 1.0), (BX, BY, BEAM_UNDER + 0.5), WOOD_LO, WOOD_HI))


def drop_icon(name, sx, x, y, z, r=0.48, h=1.25, th=0.18):
    """goo drop: round bottom + pointed top, a 2D outline extruded along X (proud of the face)"""
    pts = [(math.cos(math.radians(a)) * r, math.sin(math.radians(a)) * r) for a in range(30, -211, -24)]
    pts.append((0.0, h))
    bm = bmesh.new()
    vs = [bm.verts.new((x, y + u, z + v)) for u, v in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(sx * th, 0, 0), verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, GOO)
    gradient(o, shade(GOO, 0.9), mix(GOO, GOO_HI, 0.5))
    return o


# sign board above the beam: red frame, butter faces both ways along the lane, goo-drop icon
SZ0, SH, SW_ = BEAM_UNDER + 1.0, 2.5, 7.4
parts.append(wbox("Sign", (0.6, SW_, SH), (BX, BY, SZ0 + SH / 2), mix(ROOF_D, ROOF, 0.5), ROOF, bev=0.14))
for sx in (-1, 1):
    parts.append(wbox(f"Face{sx}", (0.24, SW_ - 1.0, SH - 0.8), (BX + sx * 0.36, BY, SZ0 + SH / 2), shade(BUTTER, 0.92), BUTTER, bev=0))
    parts.append(drop_icon(f"Drop{sx}", sx, BX + sx * 0.44, BY, SZ0 + SH / 2 - 0.35))

# little red gable roof over the sign (ridge along the beam)
RZ = SZ0 + SH
for sx in (-1, 1):
    parts.append(wbox(f"Roof{sx}", (1.6, SW_ + 1.4, 0.3), (BX + sx * 0.62, BY, RZ + 0.42), ROOF_D, ROOF,
                      bev=0.08, rot=(0, sx * 32, 0)))

lo, hi = report("parade_lane_gate", parts)
print(f"parade_lane_gate: beam underside z {BEAM_UNDER:.2f} (>= 9), edging top <= 1.0")
print(f"parade_lane_gate: COUNTDOWN RING centre = basin centre, kit from bbox-bottom-centre origin: "
      f"x {BX - (lo.x + hi.x) / 2:.3f}, y {BY - (lo.y + hi.y) / 2:.3f}, ring bottom z {SEAT_Z:.2f}; "
      f"hub frame: r {R_C:.1f} at the gate's centre angle")
finish("parade_lane_gate", parts)
