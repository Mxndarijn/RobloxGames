# Not an asset: three looks for the owner's drop exit (the jar tower's drop tube on the other bases), for Merijn to
# pick from. Each builder returns (solid parts, glass parts) in the design scenes' plot coords (kit axes, z up):
#   tube      a see-through goo tube from the hatch straight down to a goo pool (the jar's drop tube look)
#   slide     the slide kept but made to read as one: goo running down the bed, high rails, a goo pool, an arrow sign
#   pipe      a solid pipe straight down (factory: metal goo pipe with an outlet; pagoda: a hollow mushroom stalk)
# Run through the design scenes: DROP=tube|slide|pipe python iterate.py models/_base_factory_design.py ...
import math

from lib import blob, box, cone, cylinder, shade, tube
from models._base_design_common import EXIT_TUBE_R, floor_top, polar

GOO_R = 0.55          # the goo stream inside a tube
TUBE_R = EXIT_TUBE_R


def _arrow_sign(name, pos, facing_deg, board, ink):
    """A small board with a down arrow, its face turned to facing_deg (0 = +x)."""
    x, y, z = pos
    a = math.radians(facing_deg)
    dx, dy = math.cos(a), math.sin(a)
    parts = [box(f"{name}Board", (0.3, 3.0, 3.0), (x, y, z), board, rot=(0, 0, facing_deg))]
    # arrow: a stem and a head, laid on the face
    parts.append(box(f"{name}Stem", (0.2, 0.6, 1.4), (x + dx * 0.2, y + dy * 0.2, z + 0.3), ink, rot=(0, 0, facing_deg)))
    parts.append(cone(f"{name}Head", 0.9, 1.0, (x + dx * 0.2, y + dy * 0.2, z - 0.4), ink, segs=3, rot=(180, 0, 0)))
    return parts


def _pool(name, x, y, rim, goo, z=0.0):
    return [cylinder(f"{name}Rim", 4.2, 0.7, (x, y, z), rim, segs=24),
            cylinder(f"{name}Goo", 3.6, 0.75, (x, y, z + 0.05), goo, segs=24),
            blob(f"{name}Splash", 1.2, (x, y, z + 0.9), goo, subdiv=2, squash=(1.6, 1.6, 0.5), jitter=0.0)]


def _slime_in(name, p, goo):
    return blob(name, 1.0, p, shade(goo, 1.1), subdiv=2, squash=(1, 1, 0.85), jitter=0.0)


# ---------------------------------------------------------------- factory (east wall, hatch at y = HATCH_Y)
def factory(style, top, L, col, pool=True):
    """col: goo, metal, glass, board, ink. z = 0 is floor 1's walking surface. pool=False leaves the pipe's pour and pool
    out (the game builds them into the themed foot: factory_pool)."""
    H = L.FLOOR_H
    zh = (top - 1) * H + 4.5           # hatch centre height
    x0 = L.HALF + 0.3                  # the wall's outer face
    xs = L.HALF + 3.0                  # the drop line
    y = L.HATCH_Y
    solid, glass = [], []
    if style == "tube":
        path = [(x0 - 0.5, y, zh), (xs - 1.4, y, zh), (xs, y, zh - 1.4), (xs, y, 2.4), (xs + 1.2, y, 1.0)]
        glass.append(tube("ExitGlass", path, [TUBE_R] * len(path), col["glass"], segs=20, twist_free=True))
        solid.append(tube("ExitGoo", [(xs, y, zh - 2.0), (xs, y, 1.2)], [GOO_R, GOO_R * 1.4], col["goo"], segs=10))
        for k, zz in enumerate(range(int(zh) - 6, 4, -8)):
            solid.append(tube(f"Band{k}", [(xs, y, zz - 0.3), (xs, y, zz + 0.3)], [TUBE_R + 0.25] * 2, col["metal"], segs=20))
            solid.append(box(f"Brk{k}", (2.4, 0.5, 0.5), (L.HALF + 1.3, y, zz), shade(col["metal"], 0.8)))
        solid.append(tube("Collar", [(x0 - 0.2, y, zh), (x0 + 0.6, y, zh)], [TUBE_R + 0.5] * 2, col["metal"], segs=20))
        solid.append(_slime_in("Rider", (xs, y, zh * 0.55), col["goo"]))
        solid += _pool("Pool", xs + 3.0, y, col["metal"], col["goo"])
    elif style == "slide":
        zs = (top - 1) * H + 3.0
        legs = (top - 1) * 2 + 1
        pts = []
        for k in range(legs + 1):
            yy = y if k == 0 else (16.0 if k % 2 else -18.0)
            pts.append((L.CHUTE_X, yy, zs - zs * k / legs))
        pts[-1] = (L.CHUTE_X, pts[-1][1], 0.3)
        for k in range(legs):
            (x, y0, z0), (_, y1, z1) = pts[k], pts[k + 1]
            run = abs(y1 - y0)
            ln = math.hypot(run, z0 - z1)
            ang = math.degrees(math.atan2(z0 - z1, run)) * (-1 if y1 > y0 else 1)
            cy, cz = (y0 + y1) / 2, (z0 + z1) / 2
            solid.append(box(f"Bed{k}", (3.2, ln, 0.4), (x, cy, cz), shade(col["goo"], 0.75), rot=(ang, 0, 0)))
            solid.append(box(f"GooRun{k}", (1.8, ln, 0.12), (x, cy, cz + 0.26), shade(col["goo"], 1.15), rot=(ang, 0, 0)))
            for s in (-1, 1):
                solid.append(box(f"Rail{k}{s}", (0.35, ln, 2.2), (x + s * 1.75, cy, cz + 1.0), col["metal"], rot=(ang, 0, 0)))
            if k < legs - 1:
                solid.append(cylinder(f"Turn{k}", 2.2, 1.4, (x, y1, z1 - 0.7), shade(col["goo"], 0.75), segs=16))
                solid.append(cylinder(f"TurnWall{k}", 2.4, 2.4, (x, y1, z1 - 0.7), col["metal"], segs=16, cap=False))
            solid.append(box(f"Brk{k}", (2.6, 0.4, 0.4), (L.HALF + 0.9, cy, cz - 0.6), shade(col["metal"], 0.8)))
            if k % 2 == 0:
                solid.append(_slime_in(f"Rider{k}", (x, cy, cz + 1.2), col["goo"]))
        solid += _pool("Pool", L.CHUTE_X + 1.5, pts[-1][1] + (3 if pts[-1][1] > 0 else -3), col["metal"], col["goo"])
        solid += _arrow_sign("Sign", (L.HALF + 0.5, y + 3.2, zh + 2.0), 0, col["board"], col["ink"])
    elif style == "pipe":
        path = L.pipe_path(top)
        xs, zh = path[2][0], path[0][2]    # the pipe's upright and its arm's height, from the layout
        solid.append(tube("ExitPipe", path, [L.PIPE_R] * len(path), col["metal"], segs=20, twist_free=True))
        for k, zz in enumerate(range(int(zh) - 4, 4, -6)):
            solid.append(tube(f"Ring{k}", [(xs, y, zz - 0.35), (xs, y, zz + 0.35)], [TUBE_R + 0.55] * 2,
                              shade(col["metal"], 0.75), segs=20))
            solid.append(box(f"Brk{k}", (2.4, 0.5, 0.5), (L.HALF + 1.3, y, zz), shade(col["metal"], 0.7)))
        if pool:
            solid += factory_pool(L, col)
        solid += _arrow_sign("Sign", (L.HALF + 0.5, y + 3.2, zh + 2.0), 0, col["board"], col["ink"])
    return solid, glass


def factory_pool(L, col):
    """The pipe's goo pour and pool at its outlet (the same for every top floor)."""
    xs, y = L.HALF + 3.0, L.HATCH_Y
    return [tube("Pour", [(xs + 2.7, y, 1.6), (xs + 3.2, y, 0.9), (xs + 3.4, y, 0.4)], [1.1, 0.9, 1.2], col["goo"], segs=10)
            ] + _pool("Pool", xs + 4.0, y, shade(col["metal"], 0.8), col["goo"])


# The pipe pool's middle (plot x, kit y): the factory's drop lands just behind it (models/_factory_layout.EXIT).
def factory_pool_at(L):
    return L.HALF + 7.0, L.HATCH_Y


# ---------------------------------------------------------------- pagoda
SLIDE_ARC = (130.0, 248.0)   # the helter-skelter winds between these angles: clear of the turret (90) and the door (270)


def _slide_r(L):
    return max(L.eave_r(f) for f in range(1, 5)) + TUBE_R + 1.7


def pagoda_pool_at(L):
    """The slide pool's middle (plot x, kit y), a little past the slide's foot and in from the plot's edge."""
    return polar(_slide_r(L) - 2.5, SLIDE_ARC[0] - 4.0)


# the pagoda's exit starts at the hatch on the top room's wall at HATCH_A
def pagoda(style, top, L, col, rider=True):
    """col: goo, stalk, glass, cap, spots, wood, board, ink. z = floor_top values (plot floor at z = 1). rider: a slime on
    the ride (the previews only)."""
    A = L.HATCH_A
    zh = floor_top(top) + 3.5
    r0 = L.room_out(top) - 0.3
    rd = max(L.eave_r(f) for f in range(1, 5)) + TUBE_R + 1.2    # drop line: clear of every cap's eave
    solid, glass = [], []

    def P(r, z, a=A):
        x, y = polar(r, a)
        return (x, y, z)

    if style == "tube":
        path = [P(r0, zh), P(rd - 1.5, zh), P(rd, zh - 1.5), P(rd, 3.2), P(rd + 1.3, 1.8)]
        glass.append(tube("ExitGlass", path, [TUBE_R] * len(path), col["glass"], segs=20, twist_free=True))
        solid.append(tube("ExitGoo", [P(rd, zh - 2.0), P(rd, 2.0)], [GOO_R, GOO_R * 1.4], col["goo"], segs=10))
        for k, zz in enumerate(range(int(zh) - 6, 6, -8)):
            solid.append(tube(f"Band{k}", [P(rd, zz - 0.3), P(rd, zz + 0.3)], [TUBE_R + 0.25] * 2, col["stalk"], segs=20))
        solid.append(tube("Collar", [P(r0 - 0.2, zh), P(r0 + 0.8, zh)], [TUBE_R + 0.5] * 2, col["stalk"], segs=20))
        solid.append(_slime_in("Rider", P(rd, zh * 0.5), col["goo"]))
        x, y, _ = P(rd + 3.0, 0)
        solid += _pool("Pool", x, y, col["wood"], col["goo"], z=1.0)
    elif style == "slide":
        # a helter-skelter slide winding round the outside between the door (270) and the turret (90), 3 legs
        a_lo, a_hi = SLIDE_ARC
        legs, steps = (1 if top == 2 else 3), 14   # an odd count, so every top floor's slide ends at a_lo
        rs = rd + 0.5
        # first the hatch bridge out to the slide's top
        solid.append(box("Bridge", (rs - r0, 3.0, 0.4), (*polar((r0 + rs) / 2, A), zh - 1.4), shade(col["wood"], 1.0),
                         rot=(0, 0, A)))
        angles = []
        for k in range(legs):
            a0, a1 = (A, a_lo) if k == 0 else ((a_lo, a_hi) if k % 2 else (a_hi, a_lo))
            angles.append((a0, a1))
        total = sum(abs(a1 - a0) for a0, a1 in angles)
        z = zh - 1.4
        dz_per_deg = (z - 1.0) / total
        for k, (a0, a1) in enumerate(angles):
            for s in range(steps):
                b0 = a0 + (a1 - a0) * s / steps
                b1 = a0 + (a1 - a0) * (s + 1) / steps
                z0 = z - abs(b0 - a0) * dz_per_deg
                z1 = z - abs(b1 - a0) * dz_per_deg
                p0, p1 = polar(rs, b0), polar(rs, b1)
                ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
                yaw = math.degrees(math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
                pitch = math.degrees(math.atan2(z0 - z1, ln))
                c = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, (z0 + z1) / 2)
                # a box along +x, tilted so its far end (the b1 end) is lower: rotate about y by +pitch, then yaw
                solid.append(box(f"Bed{k}_{s}", (ln + 0.3, 3.4, 0.4), c, shade(col["ramp"], 0.9), rot=(0, pitch, yaw)))
                solid.append(box(f"Goo{k}_{s}", (ln + 0.3, 1.8, 0.12), (c[0], c[1], c[2] + 0.26), col["goo"],
                                 rot=(0, pitch, yaw)))
                for side in (-1, 1):
                    q = polar(rs + side * 1.8, (b0 + b1) / 2)
                    solid.append(box(f"Rail{k}_{s}{side}", (ln + 0.3, 0.35, 1.6), (q[0], q[1], c[2] + 0.8), col["cap"],
                                     rot=(0, pitch, yaw)))
                if s % 4 == 2:
                    solid.append(cylinder(f"Post{k}_{s}", 0.35, c[2], (*polar(rs, (b0 + b1) / 2), 1.0),
                                          shade(col["stalk"], 0.9), segs=8))
            z -= abs(a1 - a0) * dz_per_deg
            if k < legs - 1:
                solid.append(cylinder(f"Turn{k}", 2.4, 0.5, (*polar(rs, a1), z - 0.4), shade(col["ramp"], 0.9), segs=16))
                solid.append(blob(f"TurnCap{k}", 2.6, (*polar(rs, a1), z + 2.6), col["cap"], subdiv=2,
                                  squash=(1, 1, 0.35), jitter=0.0))
                solid.append(cylinder(f"TurnPost{k}", 0.35, 2.6, (*polar(rs, a1), z), shade(col["stalk"], 0.9), segs=8))
        if rider:
            solid.append(_slime_in("Rider", (*polar(rs, (a_lo + a_hi) / 2), z + 18.0), col["goo"]))
        x, y = pagoda_pool_at(L)
        solid += _pool("Pool", x, y, col["wood"], col["goo"], z=1.0)
        solid += _arrow_sign("Sign", P(r0 + 0.4, zh + 3.0, A + 9.0), A, col["board"], col["ink"])
    elif style == "pipe":
        # a hollow mushroom stalk: the entry arm, the stalk down to the moat, a little cap on top, spots
        path = [P(r0, zh), P(rd - 1.6, zh), P(rd, zh - 1.6), P(rd, 3.0), P(rd + 1.6, 1.6), P(rd + 2.6, 1.6)]
        solid.append(tube("Stalk", path, [TUBE_R + 0.3] * len(path), col["stalk"], segs=20, twist_free=True))
        solid.append(blob("StalkCap", 3.6, P(rd, zh + 1.6), col["cap"], subdiv=2, squash=(1, 1, 0.55), jitter=0.0))
        for k in range(5):
            solid.append(blob(f"CapSpot{k}", 0.6, P(rd + 2.2 * math.cos(k * 1.3), zh + 2.6, A + 18 * math.sin(k * 1.3)),
                              col["spots"], subdiv=1, squash=(1, 1, 0.4), jitter=0.0))
        for k, zz in enumerate(range(int(zh) - 6, 6, -7)):
            solid.append(tube(f"Ring{k}", [P(rd, zz - 0.3), P(rd, zz + 0.3)], [TUBE_R + 0.55] * 2, shade(col["stalk"], 0.85),
                              segs=20))
        solid.append(tube("Pour", [P(rd + 2.7, 1.6), P(rd + 3.2, 0.9), P(rd + 3.4, 0.4)], [1.1, 0.9, 1.2], col["goo"], segs=10))
        x, y, _ = P(rd + 4.0, 0)
        solid += _pool("Pool", x, y, col["wood"], col["goo"], z=1.0)
        solid += _arrow_sign("Sign", P(r0 + 0.4, zh + 3.0, A + 9.0), A, col["board"], col["ink"])
    return solid, glass


# ---- the pagoda's exits that hug the caps (the old vine's path, no straight arm out of the hatch) ----
def pagoda_cap_pool_at(L):
    return polar(34.0, L.CAP_END_A + 7.0)


def _box_along(name, p0, p1, w, th, col, up=0.0, side=0.0):
    """A box from p0 to p1 (w wide, th thick), raised `up` and moved `side` sideways (to the path's left)."""
    dx, dy, dz = p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]
    run = math.hypot(dx, dy)
    ln = math.hypot(run, dz)
    yaw = math.degrees(math.atan2(dy, dx))
    pitch = math.degrees(math.atan2(-dz, run))
    sx, sy = -dy / max(run, 1e-6) * side, dx / max(run, 1e-6) * side
    c = ((p0[0] + p1[0]) / 2 + sx, (p0[1] + p1[1]) / 2 + sy, (p0[2] + p1[2]) / 2 + up)
    return box(name, (ln + 0.2, w, th), c, col, rot=(0, pitch, yaw))


def pagoda_cap(style, top, L, col, rider=True):
    """captube: a see-through goo tube along the cap path; capslide: an open goo slide along it."""
    pts = L.cap_path(top)
    solid, glass = [], []
    if style == "captube":
        glass.append(tube("ExitGlass", pts, [TUBE_R] * len(pts), col["glass"], segs=18, twist_free=True))
        solid.append(tube("ExitGoo", pts[1:], [GOO_R] * (len(pts) - 1), col["goo"], segs=8, twist_free=True))
        solid.append(tube("Collar", [pts[0], pts[1]], [TUBE_R + 0.45] * 2, col["stalk"], segs=18))
        for k in range(3, len(pts) - 1, 2):
            a, b = pts[k], pts[k + 1]
            m = [(a[i] + b[i]) / 2 for i in range(3)]
            d = [b[i] - a[i] for i in range(3)]
            ln = math.sqrt(sum(v * v for v in d)) or 1.0
            solid.append(tube(f"Band{k}", [[m[i] - d[i] / ln * 0.3 for i in range(3)], [m[i] + d[i] / ln * 0.3 for i in range(3)]],
                              [TUBE_R + 0.25] * 2, col["stalk"], segs=18))
        if rider:
            solid.append(_slime_in("Rider", pts[len(pts) // 2], col["goo"]))
    elif style == "capslide":
        for k in range(len(pts) - 1):
            a, b = pts[k], pts[k + 1]
            solid.append(_box_along(f"Bed{k}", a, b, 3.2, 0.4, shade(col["ramp"], 0.95)))
            solid.append(_box_along(f"Goo{k}", a, b, 1.7, 0.12, col["goo"], up=0.26))
            for sd in (-1, 1):
                solid.append(_box_along(f"Rail{k}{sd}", a, b, 0.35, 1.5, col["cap"], up=0.7, side=sd * 1.75))
        if rider:
            solid.append(_slime_in("Rider", (pts[6][0], pts[6][1], pts[6][2] + 1.0), col["goo"]))
    x, y = pagoda_cap_pool_at(L)
    solid += _pool("Pool", x, y, col["wood"], col["goo"], z=1.0)
    solid += _arrow_sign("Sign", (*polar(L.room_out(top) + 0.4, L.HATCH_A + 9.0), floor_top(top) + 6.5), L.HATCH_A,
                         col["board"], col["ink"])
    return solid, glass
