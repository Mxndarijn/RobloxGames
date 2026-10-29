# Shared tooling for the detailed base designs (models/_<id>_layout.py + _base_<id>_design.py). Design only, not assets.
#
# A design is ONE pure-data layout module, `models/_<id>_layout.py`, that everything else reads: the Blender scene,
# the collider overlay, the floor-plan SVGs and the checker. It has no bpy import, so plain python can run the checks.
#
# Coordinates (kit = plot-local): x right, y = plot-local z (y < 0 is the front, where the door is), z up (plot-local y).
# 1 unit = 1 stud. Floor f walks at floor_top(f) = 1 + 16 (f - 1), like WorldLayout.floorTop. The FBX axis flip is an
# export detail and not part of the layout.
#
# A layout module defines (names follow WorldLayout style where one exists):
#   ID, NAME
#   PADS        [ {j, floor, x, y, yaw} ]  pad centre on the floor, pad j on floor ceil(j / 8); 6.4-stud Pad box
#   DOOR        {x, y, width, height, facing}            floor-1 doorway (gap in the wall)
#   VAT, LOCK_BUTTON {x, y}                               floor 1, inside
#   SPAWN       (x, y)                                    floor 1, inside
#   WALLS       [ {floor, a:(x,y), b:(x,y), thick, h} ]  wall segments (centre line); a room's outline
#   OBSTACLES   [ {floor, x, y, r} ]                      anything solid on a floor pads must keep clear of (vat, belts...)
#   RAMPS       [ {name, floor, kind:"line", a:(x,y,z), b:(x,y,z), width} |
#                 {name, floor, kind:"helix", c:(x,y), r_in, r_out, a0, sweep, z0, rise} ]
#               the walking surface; floor = the floor it starts on
#   LANDINGS    [ {name, floor, x, y, z, sx, sy} ]        flat ramp landings (rectangles)
#   CEILINGS    callable (x, y, z) -> lowest solid z above z at (x, y)  (decks, landings, ramps above) or None
#   EXIT        {hatch:(x,y,z), lands:(x,y), floor_check:str}
#   COLLIDERS   [ {name, floor, role, kind:"box"|"cyl"|"ball", pos:(x,y,z), size:(sx,sy,sz), rot:(rx,ry,rz)} ]
#               every collidable primitive; floor = the Floor_<f> model it belongs to (1 = static); rot in degrees
#   MESHES      [ {name, floors, variant:"mid"|"top"|"all", tint:bool, tris:int|None, note} ]
#   NOTES       {topic: text}  contract mapping (LockBarrier, DropPrompt, HomeZone ReachUp, owner check...)
#   FOOTPRINT_MAX  radius limit (default 34.5, the moat's inner edge)
import math

FLOOR_H = 16.0
PAD = 6.4
PAD_GAP = 3.0          # walkway between pads (edge to edge)
WALL_CLEAR = 4.5       # pad edge to wall face
RAMP_MIN_W = 4.0
RAMP_MAX_SLOPE = 32.0  # degrees; the jar's ramp walks at about 31
HEADROOM = 7.0
SPAWN_CLEAR = 3.0
PLOT_R = 40.0
MOAT_IN = 34.5


def floor_top(f):
    return 1.0 + (f - 1) * FLOOR_H


def polar(r, a):
    a = math.radians(a)
    return r * math.cos(a), r * math.sin(a)


def seg_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def collider_reach(c):
    """Furthest horizontal distance from the plot centre of a collider (boxes by their 8 corners, turned by rot as
    Euler XYZ degrees like lib.box)."""
    x, y, _ = c["pos"]
    sx, sy, sz = c["size"]
    if c["kind"] != "box":
        return math.hypot(x, y) + max(sx, sy) / 2
    rx, ry, rz = (math.radians(v) for v in c.get("rot", (0, 0, 0)))
    best = 0.0
    for ux in (-1, 1):
        for uy in (-1, 1):
            for uz in (-1, 1):
                px, py, pz = ux * sx / 2, uy * sy / 2, uz * sz / 2
                py, pz = py * math.cos(rx) - pz * math.sin(rx), py * math.sin(rx) + pz * math.cos(rx)
                px, pz = px * math.cos(ry) + pz * math.sin(ry), -px * math.sin(ry) + pz * math.cos(ry)
                px, py = px * math.cos(rz) - py * math.sin(rz), px * math.sin(rz) + py * math.cos(rz)
                best = max(best, math.hypot(x + px, y + py))
    return best


def ramp_samples(r, n=48):
    """Points (x, y, z) along a ramp's centre line, plus its walking width and slope in degrees."""
    pts = []
    if r["kind"] == "line":
        (x0, y0, z0), (x1, y1, z1) = r["a"], r["b"]
        for i in range(n + 1):
            t = i / n
            pts.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t))
        run = math.hypot(x1 - x0, y1 - y0)
        slope = math.degrees(math.atan2(z1 - z0, run))
        return pts, r["width"], slope
    cx, cy = r["c"]
    rm = (r["r_in"] + r["r_out"]) / 2
    for i in range(n + 1):
        t = i / n
        x, y = polar(rm, r["a0"] + r["sweep"] * t)
        pts.append((cx + x, cy + y, r["z0"] + r["rise"] * t))
    run = math.radians(abs(r["sweep"])) * rm
    slope = math.degrees(math.atan2(r["rise"], run))
    return pts, r["r_out"] - r["r_in"], slope


def check(L):
    """Run every rule against layout module L. Returns rows (rule, detail, value, limit, ok)."""
    rows = []

    def row(rule, detail, value, limit, ok):
        rows.append((rule, detail, value, limit, bool(ok)))

    pads = L.PADS
    floors = sorted({p["floor"] for p in pads})
    row("pads", "8 per floor x 4 floors", len(pads), 32, len(pads) == 32 and all(
        sum(1 for p in pads if p["floor"] == f) == 8 for f in range(1, 5)))
    for f in floors:
        fp = [p for p in pads if p["floor"] == f]
        best = min((math.hypot(a["x"] - b["x"], a["y"] - b["y"]) - PAD for i, a in enumerate(fp) for b in fp[i + 1:]),
                   default=99)
        row("pad walkway", f"floor {f}: closest pads, edge to edge", round(best, 2), f">= {PAD_GAP}", best >= PAD_GAP - 1e-6)
        walls = [w for w in L.WALLS if w["floor"] == f]
        wc = min((seg_dist((p["x"], p["y"]), w["a"], w["b"]) - PAD / 2 - w["thick"] / 2 for p in fp for w in walls),
                 default=99)
        row("pad to wall", f"floor {f}: pad edge to wall face", round(wc, 2), f">= {WALL_CLEAR}", wc >= WALL_CLEAR - 1e-6)
        obs = [o for o in L.OBSTACLES if o["floor"] == f]
        oc = min((math.hypot(p["x"] - o["x"], p["y"] - o["y"]) - PAD / 2 - o["r"] for p in fp for o in obs), default=99)
        row("pad to obstacles", f"floor {f}: pad edge to vat/belts/props", round(oc, 2), f">= {PAD_GAP}", oc >= PAD_GAP - 1e-6)
        # pads vs ramps on this floor (the ramp footprint near floor height)
        rc = 99.0
        for r in L.RAMPS:
            pts, w, _ = ramp_samples(r)
            for (x, y, z) in pts:
                if abs(z - floor_top(f)) < 3.5:
                    for p in fp:
                        rc = min(rc, math.hypot(p["x"] - x, p["y"] - y) - w / 2 - PAD / 2)
        row("pad to ramp", f"floor {f}: pad edge to ramp edge (near floor height)", round(rc, 2), f">= {PAD_GAP}",
            rc >= PAD_GAP - 1e-6)
    sx, sy = L.SPAWN
    sc = min([math.hypot(sx - p["x"], sy - p["y"]) - PAD / 2 for p in pads if p["floor"] == 1] +
             [math.hypot(sx - o["x"], sy - o["y"]) - o["r"] for o in L.OBSTACLES if o["floor"] == 1])
    row("spawn clear", "spawn to nearest pad/obstacle on floor 1", round(sc, 2), f">= {SPAWN_CLEAR}", sc >= SPAWN_CLEAR)
    # front pieces inside the door
    for name, spot in (("vat", L.VAT), ("lock button", L.LOCK_BUTTON)):
        row(f"{name} inside", f"{name} behind the front wall (y > door y)", round(spot["y"] - L.DOOR["y"], 2), "> 1",
            spot["y"] - L.DOOR["y"] > 1)
    # footprint
    lim = getattr(L, "FOOTPRINT_MAX", MOAT_IN)
    far, who = 0.0, ""
    for c in L.COLLIDERS:
        if c.get("ignore_footprint"):
            continue
        d = collider_reach(c)
        if d > far:
            far, who = d, c["name"]
    row("footprint", f"furthest collider point from the centre ({who})", round(far, 2), f"<= {lim}", far <= lim + 1e-6)
    # ramps
    for r in L.RAMPS:
        pts, w, slope = ramp_samples(r)
        row("ramp width", r["name"], round(w, 2), f">= {RAMP_MIN_W}", w >= RAMP_MIN_W)
        row("ramp slope", f"{r['name']} (degrees)", round(slope, 1), f"<= {RAMP_MAX_SLOPE}", slope <= RAMP_MAX_SLOPE)
        hr = 99.0
        for (x, y, z) in pts:
            c = L.CEILINGS(x, y, z)
            if c is not None:
                hr = min(hr, c - z)
        row("ramp headroom", f"{r['name']}: least space above the walking surface", round(hr, 2), f">= {HEADROOM}",
            hr >= HEADROOM)
        top_z = pts[-1][2]
        levels = [floor_top(f) for f in range(1, 6)] + [g["z"] for g in getattr(L, "LANDINGS", [])]
        flush = min(abs(top_z - z) for z in levels)
        row("ramp ends flush", f"{r['name']}: top end vs a floor or landing height", round(flush, 2), "<= 0.1",
            flush <= 0.1)
    return rows


def print_rows(rows):
    bad = 0
    for rule, detail, value, limit, ok in rows:
        bad += not ok
        print(f"{'PASS' if ok else 'FAIL'}  {rule:18s} {detail:60s} {value!s:>8} {limit}")
    print(f"{len(rows) - bad} pass, {bad} fail")
    return bad


def part_count(L):
    """Runtime BaseParts per plot at 4 floors: colliders + one MeshPart per mesh slot + a Pad part per pad, + the
    floor-1 extras the contract needs (HomeZone, Base, LockBarrier, MergeVat, LockButton, Sign...) counted in COLLIDERS
    when they exist as parts."""
    colliders = len(L.COLLIDERS)
    mesh_slots = sum(m.get("slots", len(m["floors"])) for m in L.MESHES)
    pads = len(L.PADS) * 2  # the Pad box + its stand MeshPart
    return {"colliders": colliders, "mesh_slots": mesh_slots, "pads": pads, "total": colliders + mesh_slots + pads}


# ---- floor-plan SVG (one per floor) ----
def plan_svg(L, f, size=360):
    s = size / (2 * 42.0)

    def X(x):
        return size / 2 + x * s

    def Y(y):
        return size / 2 - y * s  # front (-y) at the bottom of the drawing

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" role="img" '
           f'aria-label="{L.NAME} floor {f} plan">']
    out.append(f'<circle cx="{X(0)}" cy="{Y(0)}" r="{PLOT_R * s}" class="p-plot"/>')
    out.append(f'<circle cx="{X(0)}" cy="{Y(0)}" r="{(MOAT_IN + 38.5) / 2 * s}" class="p-moat" '
               f'stroke-width="{4 * s}" fill="none"/>')
    for poly in getattr(L, "DECK_POLYS", {}).get(f, []):
        pts = " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y in poly)
        out.append(f'<polygon points="{pts}" class="p-deck"/>')
    for r in L.RAMPS:
        if r["floor"] != f:
            continue
        pts, w, _ = ramp_samples(r, 32)
        d = " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y, _ in pts)
        out.append(f'<polyline points="{d}" class="p-ramp" stroke-width="{w * s:.1f}" fill="none"/>')
        (x0, y0, _), (x1, y1, _) = pts[-3], pts[-1]
        ang = math.degrees(math.atan2(-(y1 - y0), x1 - x0))
        out.append(f'<path d="M -5 -5 L 5 0 L -5 5 z" class="p-arrow" '
                   f'transform="translate({X(x1):.1f},{Y(y1):.1f}) rotate({ang:.1f})"/>')
    for g in getattr(L, "LANDINGS", []):
        if g["floor"] != f:
            continue
        out.append(f'<rect x="{X(g["x"] - g["sx"] / 2):.1f}" y="{Y(g["y"] + g["sy"] / 2):.1f}" '
                   f'width="{g["sx"] * s:.1f}" height="{g["sy"] * s:.1f}" class="p-ramp-l"/>')
    for w in L.WALLS:
        if w["floor"] != f:
            continue
        out.append(f'<line x1="{X(w["a"][0]):.1f}" y1="{Y(w["a"][1]):.1f}" x2="{X(w["b"][0]):.1f}" '
                   f'y2="{Y(w["b"][1]):.1f}" class="p-wall" stroke-width="{max(w["thick"] * s, 1.5):.1f}"/>')
    for o in L.OBSTACLES:
        if o["floor"] == f and o.get("label") not in ("vat",):
            out.append(f'<circle cx="{X(o["x"]):.1f}" cy="{Y(o["y"]):.1f}" r="{o["r"] * s:.1f}" class="p-obs"/>')
    for p in L.PADS:
        if p["floor"] != f:
            continue
        h = PAD / 2 * s
        out.append(f'<rect x="{X(p["x"]) - h:.1f}" y="{Y(p["y"]) - h:.1f}" width="{2 * h:.1f}" height="{2 * h:.1f}" '
                   f'rx="{h * 0.5:.1f}" class="p-pad" transform="rotate({-p["yaw"]:.1f},{X(p["x"]):.1f},{Y(p["y"]):.1f})"/>')
        out.append(f'<text x="{X(p["x"]):.1f}" y="{Y(p["y"]) + 3.5:.1f}" class="p-padn">{p["j"]}</text>')
    if f == 1:
        d = L.DOOR
        out.append(f'<rect x="{X(d["x"] - d["width"] / 2):.1f}" y="{Y(d["y"]) - 3:.1f}" width="{d["width"] * s:.1f}" '
                   f'height="6" class="p-door"/>')
        for lab, spot, cls in (("V", L.VAT, "p-vat"), ("L", L.LOCK_BUTTON, "p-lock")):
            out.append(f'<circle cx="{X(spot["x"]):.1f}" cy="{Y(spot["y"]):.1f}" r="{3.6 * s:.1f}" class="{cls}"/>')
            out.append(f'<text x="{X(spot["x"]):.1f}" y="{Y(spot["y"]) + 3.5:.1f}" class="p-tag">{lab}</text>')
        sx, sy = L.SPAWN
        out.append(f'<path d="M {X(sx)} {Y(sy) - 6} L {X(sx) + 5} {Y(sy) + 4} L {X(sx) - 5} {Y(sy) + 4} z" class="p-spawn"/>')
    ex = getattr(L, "EXIT", None)
    if ex and ex.get("floor") == f:
        hx, hy, _ = ex["hatch"]
        out.append(f'<circle cx="{X(hx):.1f}" cy="{Y(hy):.1f}" r="5" class="p-exit"/>')
    out.append(f'<text x="8" y="18" class="p-title">Floor {f}</text>')
    out.append(f'<text x="{size / 2}" y="{size - 6}" class="p-front">front (door side)</text>')
    out.append("</svg>")
    return "\n".join(out)


def write_plans(L, out_dir):
    import os
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    for f in range(1, 5):
        p = os.path.join(out_dir, f"{L.ID}_plan_{f}.svg")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(plan_svg(L, f))
        paths.append(p)
    return paths


if __name__ == "__main__":
    # python models/_base_design_common.py <layout module name> [plan_out_dir]
    import importlib
    import sys
    sys.path.insert(0, ".")
    L = importlib.import_module("models." + sys.argv[1])
    bad = print_rows(check(L))
    print("parts per plot at 4 floors:", part_count(L))
    print("unique meshes:", len(L.MESHES), "of which tint-only:", sum(1 for m in L.MESHES if m["tint"]))
    if len(sys.argv) > 2:
        print("plans:", write_plans(L, sys.argv[2]))
    sys.exit(1 if bad else 0)


# ---- Blender helpers (import inside a scene only; they need bpy) ----
COLLIDER_COL = (255, 120, 40)


def build_colliders(L, into):
    """The COLLIDERS list as solid primitives (for COLLIDERS=1 overlay renders). `into(obj)` collects each one."""
    from lib import blob, box, cylinder, rgb
    col = rgb(*COLLIDER_COL)
    for c in L.COLLIDERS:
        x, y, z = c["pos"]
        sx, sy, sz = c["size"]
        rot = c.get("rot", (0, 0, 0))
        if c["kind"] == "box":
            into(box(c["name"], (sx, sy, sz), (x, y, z), col, rot=rot))
        elif c["kind"] == "cyl":
            into(cylinder(c["name"], sx / 2, sz, (x, y, z - sz / 2), col, segs=16, rot=rot))
        else:
            into(blob(c["name"], sx / 2, (x, y, z), col, subdiv=2, jitter=0))


def theme(tid):
    """The jar tower's theme palette for skin id tid (classic, garden, crystal, starlight, candy, mushroom)."""
    from models._goo_jar_themes import THEMES
    return THEMES[tid]


# ---- owner drop exits: the tube's size and the invisible guard round the part a player on the ground can reach ----
EXIT_TUBE_R = 2.0        # a drop tube's radius (a player is about 2 wide)
EXIT_GUARD_REACH = 6.0   # a stretch of tube whose underside is lower than this is reachable from the ground
EXIT_GUARD_H = 11.0      # the guard's height above the ground: higher than a jump (about 7.2), so it can't be climbed


def exit_guards(path, r, ground):
    """Invisible upright boxes over the stretches of a drop tube (centre line `path`, radius r) that a player on the
    ground at height `ground` can walk or jump into: [(centre (x, y, z), size (sx, sy, sz), yaw degrees)], each the
    stretch's footprint widened by r on every side, from the ground up EXIT_GUARD_H. They keep players out of the tube
    without turning it into a ramp; the tube itself stays decor."""
    out = []
    for (x0, y0, z0), (x1, y1, z1) in zip(path, path[1:]):
        if min(z0, z1) - r - ground >= EXIT_GUARD_REACH:
            continue
        dx, dy = x1 - x0, y1 - y0
        run = math.hypot(dx, dy)
        yaw = math.degrees(math.atan2(dy, dx)) if run > 1e-6 else 0.0
        out.append((((x0 + x1) / 2, (y0 + y1) / 2, ground + EXIT_GUARD_H / 2), (run + 2 * r, 2 * r, EXIT_GUARD_H), yaw))
    return out
