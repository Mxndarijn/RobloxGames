# slime_lane: the whole parade goo lane as ONE smooth curved channel (replaces ~50 mitred Cylinder parts).
# Input: inputs/slime_lane_centreline.json (lune run tools/render/lane_centreline, from games/steal-a-slime):
# the lane's centreline in WORLD studs (x, z), LANE_Y, HALF_WIDTH and the taper to the drain. A centripetal Catmull-Rom spline is fitted
# through every point, resampled by curvature, and a domed cross-section is swept along it: flat-ish glossy crown
# at LANE_Y, edges rounded down to EDGE_Y (just under the ground, so no edge sticks up), darker rim in vertex colour.
# Kit frame: x = world x - PIVOT x, y = -(world z - PIVOT z), z = world y - PIVOT y  (Roblox (x, y, z) = (x, z, -y),
# see CLAUDE.md), so the game places the MeshPart at PIVOT (the bbox centre) with MeshAssets.IMPORT_YAW like MeshSwap.
# Writes out/slime_lane_pivot.json (pivot, bbox, centreline) for the game and the spec.
import json, math, os
import bmesh
from lib import *

HERE = os.path.dirname(os.path.abspath(__file__))
src = json.load(open(os.path.join(HERE, "..", "inputs", "slime_lane_centreline.json")))
LANE_Y, HW = src["laneY"], src["halfWidth"]
TAPER = src.get("taper")


def hw_at(p):
    """Half width at (x, z): HW, easing (smoothstep) to the taper's endHalfWidth over its last `length` studs before
    its circle (the drain lip), the same rule as ParadeLane.halfWidthAt."""
    if not TAPER:
        return HW
    gap = math.dist(p, (TAPER["x"], TAPER["z"])) - TAPER["radius"]
    u = max(0.0, min(1.0, gap / TAPER["length"]))
    return TAPER["endHalfWidth"] + (HW - TAPER["endHalfWidth"]) * (u * u * (3 - 2 * u))

BASE = tuple(c / 255 for c in src["color"])
CROWN = (BASE[0], BASE[1], BASE[2], 1.0)
RIM = mix(rgb(*src["color"]), rgb(70, 170, 160), 0.5)   # darker teal rim, only the outer edge
EDGE_Y = -0.05      # edge height: a hair under the ground, never above
BOTTOM_Y = -0.08    # flat underside (hidden in the ground)
SPS = [-1, -0.9, -0.74, -0.52, -0.26, 0, 0.26, 0.52, 0.74, 0.9, 1]   # lateral samples (fraction of HW)
MIN_STEP, MAX_STEP, FLAT_TOL = 0.6, 2.0, 0.01

P = [(p[0], p[1]) for p in src["points"]]


def cr_point(p0, p1, p2, p3, t, alpha=0.5):
    """Centripetal Catmull-Rom point between p1 and p2 (Barry-Goldman)."""
    def knot(a, b):
        return max(math.hypot(b[0] - a[0], b[1] - a[1]), 1e-6) ** alpha
    t0 = 0.0
    t1 = t0 + knot(p0, p1)
    t2 = t1 + knot(p1, p2)
    t3 = t2 + knot(p2, p3)
    tt = t1 + (t2 - t1) * t

    def lerp(a, b, ta, tb):
        k = (tt - ta) / (tb - ta)
        return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)
    a1, a2, a3 = lerp(p0, p1, t0, t1), lerp(p1, p2, t1, t2), lerp(p2, p3, t2, t3)
    b1, b2 = lerp(a1, a2, t0, t2), lerp(a2, a3, t1, t3)
    return lerp(b1, b2, t1, t2)


def ghost(a, b):
    return (2 * a[0] - b[0], 2 * a[1] - b[1])


# dense spline: 8 samples per segment, then resample by curvature
dense = []
ext = [ghost(P[0], P[1])] + P + [ghost(P[-1], P[-2])]
for i in range(len(P) - 1):
    for k in range(8):
        dense.append(cr_point(ext[i], ext[i + 1], ext[i + 2], ext[i + 3], k / 8))
dense.append(P[-1])


def turn_radius(a, b, c):
    ab, bc, ca = math.dist(a, b), math.dist(b, c), math.dist(c, a)
    area2 = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
    return float("inf") if area2 < 1e-9 else ab * bc * ca / (2 * area2)


path = [dense[0]]
acc = 0.0
for i in range(1, len(dense) - 1):
    acc += math.dist(dense[i - 1], dense[i])
    r = turn_radius(dense[max(0, i - 4)], dense[i], dense[min(len(dense) - 1, i + 4)])
    step = min(MAX_STEP, max(MIN_STEP, math.sqrt(8 * r * FLAT_TOL))) if r != float("inf") else MAX_STEP
    if hw_at(dense[i]) < HW - 1e-6:   # rings close together through the taper, so its edges curve instead of kinking
        step = MIN_STEP
    if acc >= step:
        path.append(dense[i])
        acc = 0.0
path.append(dense[-1])

# frames: tangent from neighbours, left normal (-tz, tx) as in ParadeLane (positive = fountain side)
n = len(path)
tang = []
for i in range(n):
    a, b = path[max(0, i - 1)], path[min(n - 1, i + 1)]
    d = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
    tang.append(((b[0] - a[0]) / d, (b[1] - a[1]) / d))
minr = min(turn_radius(path[i - 1], path[i], path[i + 1]) for i in range(1, n - 1))
assert minr > HW + 0.1, f"tightest bend radius {minr:.2f} <= half width {HW}: the sweep would fold"


# Extend the lane's end from its own last curve (a circular arc through the last rings), easing it onto the drain's
# centre, until it touches the goo drain's outer curb (src["drain"]: curb centre x, z and outer radius). Every ring that is already there stays as it is. The end is
# cut to follow the curb arc (each lateral sample stops on the circle), so no corner rides onto the curb: the lane butts
# against the curb's outer face with END_OVERLAP studs of overlap and no gap.
END_OVERLAP = 0.05
STEP_EXT = 0.5
if "drain" in src:
    dc = (src["drain"]["x"], src["drain"]["z"])
    rcurb = src["drain"]["radius"] - END_OVERLAP
    last = path[-1]
    back = next(p for p in reversed(path[:-1]) if math.dist(p, last) >= 4.0)
    back2 = next(p for p in reversed(path[:path.index(back)]) if math.dist(p, back) >= 4.0)
    hx, hz = last[0] - path[-2][0], last[1] - path[-2][1]
    hl = math.hypot(hx, hz)
    hx, hz = hx / hl, hz / hl
    r = turn_radius(back2, back, last)
    cross = (back[0] - back2[0]) * (last[1] - back[1]) - (back[1] - back2[1]) * (last[0] - back[0])
    turn = (1 if cross > 0 else -1) * STEP_EXT / r if r != float("inf") else 0.0   # heading change per ring (rad)
    ext = []
    x, z = last
    entered = [False] * len(SPS)   # each lateral sample line has crossed into the curb circle
    for _ in range(40):
        # steer the arc onto the drain centre (at most a radius-4 bend), so the lane's whole width reaches the curb
        ax, az = dc[0] - x, dc[1] - z
        aim = math.atan2(hx * az - hz * ax, hx * ax + hz * az)
        turn = turn + (max(-STEP_EXT / 4, min(STEP_EXT / 4, aim * 0.5)) - turn) * 0.5
        c, s_ = math.cos(turn), math.sin(turn)
        hx, hz = hx * c - hz * s_, hx * s_ + hz * c
        x, z = x + hx * STEP_EXT, z + hz * STEP_EXT
        ext.append((x, z))
        for j, s in enumerate(SPS):
            w = hw_at((x, z))
            if math.dist((x - hz * w * s, z + hx * w * s), dc) < rcurb:
                entered[j] = True
        if all(entered):
            break
    assert all(entered), "the arc does not reach the drain with the lane's whole width (its end half width must stay under the curb radius)"
    path = path + ext
    n = len(path)
    tang = []
    for i in range(n):
        a, b = path[max(0, i - 1)], path[min(n - 1, i + 1)]
        d = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
        tang.append(((b[0] - a[0]) / d, (b[1] - a[1]) / d))
    full = [[(path[i][0] + -tang[i][1] * hw_at(path[i]) * s, path[i][1] + tang[i][0] * hw_at(path[i]) * s) for s in SPS]
            for i in range(n)]
    firsts = []
    for j in range(len(SPS)):
        firsts.append(next(i for i in range(n) if math.dist(full[i][j], dc) < rcurb))
    keep = min(firsts)   # rings 0..keep-1 are entirely outside the curb
    end = []
    for j in range(len(SPS)):
        a, b = full[firsts[j] - 1][j], full[firsts[j]][j]
        lo, hi = 0.0, 1.0   # bisect the point where the offset line meets the curb circle
        for _ in range(40):
            mid = (lo + hi) / 2
            q = (a[0] + (b[0] - a[0]) * mid, a[1] + (b[1] - a[1]) * mid)
            if math.dist(q, dc) < rcurb:
                hi = mid
            else:
                lo = mid
        end.append((a[0] + (b[0] - a[0]) * lo, a[1] + (b[1] - a[1]) * lo))
    path, tang = path[:keep], tang[:keep]
    rows_override = full[:keep] + [end]
    n = keep + 1
    path.append(end[SPS.index(0)])   # the centreline ends on the circle
    tang.append(tang[-1])
else:
    rows_override = None


def height(s):
    """Cross-section height at lateral fraction s (-1..1): flat-ish crown, rounded fall to EDGE_Y."""
    a = abs(s)
    return EDGE_Y + (LANE_Y - EDGE_Y) * (1 - a ** 2.6) ** 0.9


# pivot = bbox centre (Roblox places a MeshPart by its bbox centre)
rows = []
for i in range(n):
    nx, nz = -tang[i][1], tang[i][0]
    w = hw_at(path[i])
    rows.append([(path[i][0] + nx * w * s, path[i][1] + nz * w * s) for s in SPS])
if rows_override:
    rows = rows_override
xs = [p[0] for r in rows for p in r]
zs = [p[1] for r in rows for p in r]
PIV = ((min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2, (BOTTOM_Y + LANE_Y) / 2)


def kit(x, z, y):
    return (x - PIV[0], -(z - PIV[1]), y - PIV[2])


bm = bmesh.new()
col = bm.loops.layers.color.new("Col")
m = len(SPS)
top = [[bm.verts.new(kit(p[0], p[1], height(SPS[j]))) for j, p in enumerate(r)] for r in rows]
low = [[bm.verts.new(kit(r[0][0], r[0][1], BOTTOM_Y)), bm.verts.new(kit(r[-1][0], r[-1][1], BOTTOM_Y))] for r in rows]


def paint(f, ss):
    for loop, s in zip(f.loops, ss):
        t = abs(s) ** 3
        loop[col] = mix(CROWN, RIM, min(1.0, t * 0.9))


def face(vs, ss):
    f = bm.faces.new(vs)
    paint(f, ss)
    return f


# The drain end follows the curb arc: a bottom vertex under every end-ring sample, so its cap is a vertical skirt along
# the arc and the last underside reaches the arc too (one flat cap polygon would span the curb's circular segment, a
# sheet over the drain's mouth).
curved = rows_override is not None
bottom_end = [low[n - 1][0]] + [bm.verts.new(kit(p[0], p[1], BOTTOM_Y)) for p in rows[n - 1][1:m - 1]] + [low[n - 1][1]]
for i in range(n - 1):
    for j in range(m - 1):   # crown (wound so normals face up; recalc below fixes any flip)
        face([top[i][j], top[i][j + 1], top[i + 1][j + 1], top[i + 1][j]], [SPS[j], SPS[j + 1], SPS[j + 1], SPS[j]])
    # underside + the two thin skirts at the edges
    if curved and i == n - 2:
        ring = [low[i][0]] + bottom_end + [low[i][1]]
        face(ring, [1] * len(ring))
    else:
        face([low[i][0], low[i + 1][0], low[i + 1][1], low[i][1]], [1, 1, 1, 1])
    face([top[i][0], top[i + 1][0], low[i + 1][0], low[i][0]], [1, 1, 1, 1])
    face([top[i][m - 1], low[i][1], low[i + 1][1], top[i + 1][m - 1]], [1, 1, 1, 1])
for i in (0, n - 1):   # end caps: flat at the slide mouth, a skirt along the curb arc at the drain
    if curved and i == n - 1:
        for j in range(m - 1):
            face([top[i][j], top[i][j + 1], bottom_end[j + 1], bottom_end[j]], [1, 1, 1, 1])
    else:
        ring = [top[i][j] for j in range(m)] + [low[i][1], low[i][0]]
        face(ring, [1] * len(ring))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4], quad_method="BEAUTY", ngon_method="BEAUTY")

lane = obj_from_bm("slime_lane", bm)
o = finish("slime_lane", [lane])
for p in o.data.polygons:
    p.use_smooth = True
o["smooth_normals"] = 1

# what the game needs: bbox centre (world), native bbox, the centreline
vz = [v.co.z for v in o.data.vertices]
vx = [v.co.x for v in o.data.vertices]
vy = [v.co.y for v in o.data.vertices]
info = {
    "pivot": [PIV[0], PIV[2], PIV[1]],   # Roblox world (x, y, z) of the bbox centre
    "size": [max(vx) - min(vx), max(vz) - min(vz), max(vy) - min(vy)],   # Roblox (x, y, z) studs
    "drain": src.get("drain"), "endRing": [[round(x, 3), round(z, 3)] for x, z in rows[-1]],
    "widths": [round(math.dist(r[0], r[-1]), 3) for r in rows[:-1]],   # every full ring (the last one follows the curb)
    "crownY": LANE_Y, "edgeY": EDGE_Y, "halfWidth": HW, "taper": TAPER, "rings": n,
    "centre": [[round(p[0], 3), round(p[1], 3)] for p in path],
}
json.dump(info, open(os.path.join(HERE, "..", "out", "slime_lane_pivot.json"), "w"))
print("slime_lane rings", n, "min bend radius", round(minr, 2), "pivot", info["pivot"], "size", info["size"])
