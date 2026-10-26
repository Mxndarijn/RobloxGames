# Goo Factory base: one builder per mesh piece (design stage; nothing uploaded). Numbers come from _factory_layout.
# Every builder returns a list of parts in plot-local kit coords with its floor's walking surface at z = 0 (the scene
# lifts it to floor_top(f)). Tint-only pieces are painted in value greys only, so MeshPart.Color themes them (assumed
# multiply, see LESSONS [slimes]): each storey is four tint-only meshes (brick shell, cream trim, window strips, goo
# pipes), so bands stay cream and glass stays glass under any theme. Themed pieces (foot, roof kit, dressing) take a
# theme palette; the sign, door frame, shutter and belt keep fixed colours in every theme.
import math

from lib import PALETTE, blob, box, cone, cylinder, gradient, rgb, shade, mix, tube
import models._factory_layout as L

H = L.FLOOR_H
P = PALETTE


def g(v):
    """Value grey (for tint-only pieces)."""
    return (v, v, v, 1.0)


def B(name, size, pos, col, rot=(0, 0, 0), k=0.88):
    o = box(name, size, pos, col, rot=rot)
    gradient(o, shade(col, k), col)
    return o


def CY(name, r, h, pos, col, segs=16, r_top=None, k=0.85, rot=(0, 0, 0)):
    o = cylinder(name, r, h, pos, col, segs=segs, r_top=r_top, rot=rot)
    gradient(o, shade(col, k), col)
    return o


# ---------- storeys ----------
# Wall frame helper: a side is (name, axis, fixed, sign) with axis "x" (wall runs along x at y = fixed) or "y".
SIDES = (("S", "x", -L.WC, -1), ("N", "x", L.WC, 1), ("W", "y", -L.WC, -1), ("E", "y", L.WC, 1))
SPAN = 2 * L.HALF
WIN_Z0, WIN_H = 8.6, 4.4      # the long industrial window strip: sill height and height
BAND_Z = H - 0.45             # the cream band at the top of a storey


def _at(axis, fixed, u, out=0.0, sign=1):
    """Plot (x, y) of a point u along a side (u = 0 at its low end) pushed `out` outward."""
    if axis == "x":
        return (-L.HALF + u, fixed + sign * out)
    return (fixed + sign * out, -L.HALF + u)


def _sbox(name, axis, fixed, sign, u0, u1, z0, z1, depth, out, col):
    """A box along a side from u0 to u1, z0..z1, `depth` thick, its centre `out` outward of the wall centre line."""
    c = (u0 + u1) / 2
    x, y = _at(axis, fixed, c, out, sign)
    size = (u1 - u0, depth, z1 - z0) if axis == "x" else (depth, u1 - u0, z1 - z0)
    return box(name, size, (x, y, (z0 + z1) / 2), col)


def _win_spans(side, ground):
    """Window strip spans (u0, u1) along a side."""
    nm = side[0]
    if nm == "S" and ground:
        return [(3.5, 15.5), (32.5, 44.5)]          # either side of the door and the sign
    if nm == "E" and not ground:
        u = L.HATCH_Y + L.HALF                      # keep clear of the drop hatch
        return [(u + 4.0, SPAN - 4.0)]
    return [(4.0, SPAN - 4.0)]


def _holes(side, ground):
    nm = side[0]
    if nm == "S" and ground:
        dw = L.DOOR["width"] / 2
        return [(L.HALF - dw, L.HALF + dw, 0.0, L.DOOR["height"])]
    if nm == "E" and not ground:
        u = L.HATCH_Y + L.HALF
        return [(u - 2, u + 2, 1.0, 8.0)]
    return []


def storey_shell(ground):
    """Tint-only brick shell (brick 0.84 at the foot to 1.0 at the top of each storey, mortar courses 0.74,
    plinth and pilasters 0.82)."""
    parts = []
    T = L.WALL
    for side in SIDES:
        nm, axis, fixed, sign = side
        cuts = sorted(_holes(side, ground) + [(u0, u1, WIN_Z0, WIN_Z0 + WIN_H) for u0, u1 in _win_spans(side, ground)])
        # wall body: horizontal slices between cut rows, columns between cuts inside each slice
        zs = sorted({0.0, H} | {c[2] for c in cuts} | {c[3] for c in cuts})
        for i in range(len(zs) - 1):
            z0, z1 = zs[i], zs[i + 1]
            inside = sorted((c[0], c[1]) for c in cuts if c[2] <= z0 and c[3] >= z1)
            u = 0.0
            for a, b in inside + [(SPAN, SPAN)]:
                if a - u > 0.01:
                    w = _sbox(f"Wall{nm}{i}_{u:.0f}", axis, fixed, sign, u, a, z0, z1, T, 0.0, g(1.0))
                    gradient(w, g(0.84), g(1.0), 0.0, H)
                    parts.append(w)
                u = max(u, b)
        # brick courses: thin darker strips proud of the face, every 1.6 studs, not across cuts
        for k in range(1, 10):
            zz = k * 1.6
            if zz > H - 1.2:
                break
            spans = [(0.0, SPAN)]
            for c in cuts:
                if c[2] - 0.1 <= zz <= c[3] + 0.1:
                    spans = [(a, b) for (a0, b0) in spans for (a, b) in ((a0, min(b0, c[0])), (max(a0, c[1]), b0)) if b - a > 0.3]
            for j, (a, b) in enumerate(spans):
                parts.append(_sbox(f"Course{nm}{k}_{j}", axis, fixed, sign, a + 0.2, b - 0.2, zz - 0.12, zz + 0.12, 0.1,
                                   T / 2 + 0.04, g(0.74)))
        # plinth
        parts.append(_sbox(f"Plinth{nm}", axis, fixed, sign, 0.0, SPAN, 0.0, 1.0, 0.3, T / 2 + 0.12, g(0.82))
                     if not (nm == "S" and ground) else _sbox(f"PlinthSL", axis, fixed, sign, 0.0, L.HALF - 6.3, 0.0, 1.0,
                                                               0.3, T / 2 + 0.12, g(0.82)))
        if nm == "S" and ground:
            parts.append(_sbox("PlinthSR", axis, fixed, sign, L.HALF + 6.3, SPAN, 0.0, 1.0, 0.3, T / 2 + 0.12, g(0.82)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(B(f"Pil{sx}{sy}", (2.2, 2.2, H), (sx * (L.HALF - 0.5), sy * (L.HALF - 0.5), H / 2), g(0.82), k=0.95))
    return parts


def storey_trim(ground):
    """Tint-only cream trim: the band at the top of the storey, window frames and sills, pilaster caps."""
    parts = []
    T = L.WALL
    for side in SIDES:
        nm, axis, fixed, sign = side
        parts.append(_sbox(f"Band{nm}", axis, fixed, sign, -0.6, SPAN + 0.6, BAND_Z - 0.55, BAND_Z + 0.55, 1.0,
                           T / 2 + 0.2, g(1.0)))
        for j, (u0, u1) in enumerate(_win_spans(side, ground)):
            parts.append(_sbox(f"Sill{nm}{j}", axis, fixed, sign, u0 - 0.6, u1 + 0.6, WIN_Z0 - 0.6, WIN_Z0, 0.8,
                               T / 2 + 0.25, g(1.0)))
            parts.append(_sbox(f"Lintel{nm}{j}", axis, fixed, sign, u0 - 0.4, u1 + 0.4, WIN_Z0 + WIN_H, WIN_Z0 + WIN_H + 0.5,
                               0.5, T / 2 + 0.15, g(0.9)))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(box(f"PilCap{sx}{sy}", (2.6, 2.6, 0.6), (sx * (L.HALF - 0.5), sy * (L.HALF - 0.5), H - 1.4), g(0.92)))
    return parts


def storey_windows(ground):
    """Tint-only window strips (tinted with the theme's glass): panes 0.85, mullions 0.55, a transom bar."""
    parts = []
    T = L.WALL
    for side in SIDES:
        nm, axis, fixed, sign = side
        for j, (u0, u1) in enumerate(_win_spans(side, ground)):
            parts.append(_sbox(f"Pane{nm}{j}", axis, fixed, sign, u0, u1, WIN_Z0, WIN_Z0 + WIN_H, 0.3, 0.0, g(0.85)))
            n = max(2, int((u1 - u0) / 2.6))
            for k in range(n + 1):
                u = u0 + (u1 - u0) * k / n
                parts.append(_sbox(f"Mull{nm}{j}_{k}", axis, fixed, sign, u - 0.18, u + 0.18, WIN_Z0, WIN_Z0 + WIN_H, 0.4,
                                   0.05, g(0.55)))
            parts.append(_sbox(f"Transom{nm}{j}", axis, fixed, sign, u0, u1, WIN_Z0 + WIN_H * 0.62 - 0.15,
                               WIN_Z0 + WIN_H * 0.62 + 0.15, 0.4, 0.05, g(0.55)))
    return parts


PIPE_X = (-8.6, 8.6)


def storey_pipes(ground):
    """Tint-only goo pipes up the facade either side of the door (tinted with the theme's goo), with clamps."""
    parts = []
    y = -L.HALF - 0.9
    for x in PIPE_X:
        parts.append(CY(f"Pipe{x}", 0.85, H, (x, y, 0), g(1.0), segs=10, k=0.92))
        for zz in (2.0, 7.0, 13.0):
            parts.append(box(f"Clamp{x}{zz}", (2.2, 1.0, 0.5), (x, y + 0.35, zz), g(0.55)))
        if ground:
            parts.append(CY(f"PipeFoot{x}", 1.3, 1.2, (x, y, 0), g(0.7), segs=10))
    return parts


def parapet():
    """Tint-only cream parapet with coping round the roof of the top storey (sits at z = 16)."""
    parts = []
    W = L.WC
    for nm, size, pos in (("ParS", (SPAN, 0.8, 1.8), (0, -W, H + 0.9)), ("ParN", (SPAN, 0.8, 1.8), (0, W, H + 0.9)),
                          ("ParW", (0.8, SPAN, 1.8), (-W, 0, H + 0.9)), ("ParE", (0.8, SPAN, 1.8), (W, 0, H + 0.9))):
        parts.append(B(nm, size, pos, g(0.9)))
    for nm, size, pos in (("CopS", (SPAN + 1, 1.4, 0.4), (0, -W, H + 2.0)), ("CopN", (SPAN + 1, 1.4, 0.4), (0, W, H + 2.0)),
                          ("CopW", (1.4, SPAN + 1, 0.4), (-W, 0, H + 2.0)), ("CopE", (1.4, SPAN + 1, 0.4), (W, 0, H + 2.0))):
        parts.append(box(nm, size, pos, g(1.0)))
    return parts


# ---------- the GOO CO sign (fixed colours in every theme; the game writes the plot's name on a SurfaceGui) ----------
FONT = {  # 3 x 5 block letters, rows top to bottom
    "G": ["111", "100", "101", "101", "111"], "O": ["111", "101", "101", "101", "111"],
    "C": ["111", "100", "100", "100", "111"],
}


def sign():
    cream, rim, ink = P["ranch_cream"], P["ranch_roof"], rgb(70, 52, 44)
    y = -L.HALF - 1.7   # stands proud on arms, in front of the band and the shutter drum
    z = 16.3
    parts = [B("SignBoard", (19.0, 0.6, 3.9), (0, y, z), cream, k=0.95)]
    parts.append(box("SignRim", (19.8, 0.4, 4.7), (0, y + 0.25, z), rim))
    word, px = "GOO CO", 0.42
    x = -((len(word) * 4 - 1) * px) / 2
    for ch in word:
        if ch != " ":
            for r, row in enumerate(FONT[ch]):
                for c, bit in enumerate(row):
                    if bit == "1":
                        parts.append(box(f"Px{x:.1f}{r}{c}", (px, 0.25, px), (x + c * px + px / 2, y - 0.4, z + 1.35 - r * px),
                                         ink))
        x += 4 * px
    for k, col in enumerate((P["ranch_goo"], P["ranch_pink"], P["ranch_butter"], P["ranch_lilac"], P["ranch_goo"])):
        parts.append(blob(f"Dot{k}", 0.55, (-4.4 + k * 2.2, y - 0.45, z - 1.2), col, subdiv=2, squash=(1, 0.5, 1), jitter=0))
    for s in (-1, 1):
        parts.append(box(f"SignArm{s}", (0.5, 1.8, 0.5), (s * 8.0, y + 1.0, z), shade(P["ranch_metal"], 0.8)))
    return parts
# ---------- floor pieces ----------
def slab():
    parts = []
    yb = L.CORE_FRONT_Y + L.CORE_FRONT_T / 2
    S = L.SLAB
    parts.append(B("SlabMain", (2 * L.IN, yb + L.IN, S), (0, (-L.IN + yb) / 2, -S / 2), g(0.92)))
    parts.append(B("SlabW", (L.XS + L.IN, L.IN - yb, S), ((-L.IN + L.XS) / 2, (yb + L.IN) / 2, -S / 2), g(0.92)))
    ex0 = L.END_X + L.END_T / 2
    parts.append(B("SlabE", (L.IN - ex0, L.IN - yb, S), ((ex0 + L.IN) / 2, (yb + L.IN) / 2, -S / 2), g(0.92)))
    # floor tile seams (value lines), every 8 studs
    for k in range(-2, 3):
        parts.append(box(f"SeamX{k}", (0.15, 2 * L.IN - 0.4, 0.04), (k * 9.2, -2, 0.02), g(0.8)))
    # hazard stripes on the deck strip edge where the stair arrives (value stripes: tint makes them theme-coloured)
    for k in range(5):
        parts.append(box(f"Haz{k}", (0.9, 0.4, 0.05), (L.XS - 0.5, L.LANE_B - 2.0 + k * 1.0, 0.03), g(0.55 if k % 2 else 1.0)))
    return parts


def floor_1_slab():
    """Floor 1's factory floor (part of the static floor 1, tint-only)."""
    return [B("Floor1", (2 * L.IN, 2 * L.IN, 0.3), (0, 0, -0.15), g(0.92))] + \
        [box(f"Seam1X{k}", (0.15, 2 * L.IN - 0.4, 0.04), (k * 9.2, 0, 0.02), g(0.8)) for k in range(-2, 3)]


def stair():
    """Run A + landing + run B, built relative to the floor it starts from (z = 0)."""
    parts = []
    hr = L.HALF_RISE
    for nm, lane, x0, z0, x1, z1 in (("RunA", L.LANE_A, L.XS, 0, L.XE, hr), ("RunB", L.LANE_B, L.XE, hr, L.XS, H)):
        run = abs(x1 - x0)
        ln = math.hypot(run, z1 - z0)
        ang = math.degrees(math.atan2(z1 - z0, run)) * (-1 if x1 > x0 else 1)
        parts.append(B(nm, (ln, L.LANE_W, L.RAMP_T), ((x0 + x1) / 2, lane, (z0 + z1) / 2 - L.RAMP_T / 2), g(0.95),
                       rot=(0, ang, 0)))
        # tread ribs every 1.5 studs along the run (grip lines, proud 0.08)
        n = int(run / 1.5)
        for k in range(1, n):
            t = k / n
            x = x0 + (x1 - x0) * t
            z = z0 + (z1 - z0) * t
            parts.append(box(f"{nm}Rib{k}", (0.25, L.LANE_W - 0.4, 0.12), (x, lane, z + 0.02), g(0.7), rot=(0, ang, 0)))
        # edge kick strips
        for s in (-1, 1):
            parts.append(box(f"{nm}Kick{s}", (ln, 0.2, 0.3), ((x0 + x1) / 2, lane + s * (L.LANE_W / 2 - 0.1),
                                                              (z0 + z1) / 2 + 0.1), g(0.6), rot=(0, ang, 0)))
    lg = L.LANDINGS[0]
    parts.append(B("Landing", (lg["sx"], lg["sy"], L.RAMP_T), (lg["x"], lg["y"], hr - L.RAMP_T / 2), g(0.95)))
    parts.append(box("LandingPlate", (lg["sx"] - 0.6, lg["sy"] - 0.6, 0.05), (lg["x"], lg["y"], hr + 0.02), g(0.8)))
    return parts


def core():
    parts = []
    x0, x1 = L.XS, L.END_X + L.END_T / 2
    parts.append(B("CoreFront", (x1 - x0, L.CORE_FRONT_T, H), ((x0 + x1) / 2, L.CORE_FRONT_Y, H / 2), g(0.86)))
    # portholes on the factory side, so you can see the ramps behind
    for k in range(4):
        x = x0 + 3 + k * 6
        parts.append(CY(f"Port{k}", 1.3, 0.2, (x, L.CORE_FRONT_Y - 0.25, 9.0), g(0.42), segs=12, rot=(90, 0, 0)))
        parts.append(CY(f"PortRim{k}", 1.6, 0.15, (x, L.CORE_FRONT_Y - 0.2, 9.0), g(1.0), segs=12, rot=(90, 0, 0)))
    parts.append(B("Spine", (L.XE - L.XS, L.SPINE_T, H), ((L.XS + L.XE) / 2, L.SPINE_Y, H / 2), g(0.86)))
    parts.append(B("End", (L.END_T, L.IN - L.CORE_FRONT_Y, H), (L.END_X, (L.CORE_FRONT_Y + L.IN) / 2, H / 2), g(0.86)))
    # an arrow sign at the core entrance
    parts.append(box("CoreSign", (0.2, 3.0, 1.6), (L.XS - 0.15, (L.CORE_FRONT_Y + L.IN) / 2 + 2.5, 9.0), g(1.0)))
    return parts


def core_cap():
    S = L.SLAB
    return [B("CapA", (L.XL - L.XS, L.LANE_W, S), ((L.XS + L.XL) / 2, L.LANE_A, -S / 2), g(0.92)),
            B("CapLanding", (L.XL - L.XE, L.LANE_W, S), ((L.XE + L.XL) / 2, L.LANE_B, -S / 2), g(0.92))]


def roof():
    """Roof slab with 4 sawtooth skylights, sitting on the top storey (z = 16 above its floor)."""
    parts = [B("RoofSlab", (2 * L.HALF - 1.6, 2 * L.HALF - 1.6, 0.8), (0, 0, H + 0.4), g(0.85))]
    for k in range(4):
        y = -L.HALF + 7 + k * 11
        parts.append(B(f"Saw{k}", (2 * L.HALF - 8, 7.6, 0.5), (0, y, H + 3.1), g(0.9), rot=(36, 0, 0)))
        parts.append(box(f"Sky{k}", (2 * L.HALF - 9, 0.3, 4.2), (0, y + 3.15, H + 2.9), g(0.45)))
    return parts




# ---------- themed pieces: roof kit, foot (+ door-zone touches), per-storey dressing (<= 3 meshes per theme) ----------
WALL_KEY = {"classic": "brick", "garden": "butter", "crystal": "path", "starlight": "wood", "candy": "pink",
            "mushroom": "wood"}
ROLES = {"walls (brick shell)": "WALL_KEY", "bands, frames, parapet": "cream", "window strips": "glass",
         "goo pipes, stair, chute": "goo", "floors, core cap, yard": "path", "core walls": "wood_d",
         "roof, hatch, silos": "metal", "tank goo / puffs": "goo / goo_hi", "moat": "goo", "bridge": "wood"}


def wall_col(tid, th):
    """The brick shell's tint. Classic is the concept's red-orange brick: the lib's ranch roof red warmed 25 % toward
    the theme's wood (~ rgb 209, 104, 85); every other theme reads one palette key."""
    k = WALL_KEY[tid]
    return mix(P["ranch_roof"], th["wood"], 0.25) if k == "brick" else th[k]


def _stripes_ring(name, x, y, z0, z1, r, cols, step=1.6):
    out = []
    k, z = 0, z0
    while z < z1 - 0.1:
        out.append(cylinder(f"{name}{k}", r, min(step * 0.5, z1 - z), (x, y, z), cols[k % len(cols)], segs=12))
        z += step
        k += 1
    return out


def _star(name, x, y, z, r, col, facing="y"):
    """A flat 5-point star standing up, facing -y (or +x for facing='x')."""
    from lib import obj_from_bm
    import bmesh
    bm = bmesh.new()
    pts = []
    for i in range(10):
        a = math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.45
        pts.append((rr * math.cos(a), rr * math.sin(a)))
    t = r * 0.25
    front, back = [], []
    for u, v in pts:
        if facing == "y":
            front.append(bm.verts.new((x + u, y - t, z + v)))
            back.append(bm.verts.new((x + u, y + t, z + v)))
        else:
            front.append(bm.verts.new((x + t, y + u, z + v)))
            back.append(bm.verts.new((x - t, y + u, z + v)))
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(10):
        j = (i + 1) % 10
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


def roof_kit(tid, th):
    """Themed: goo tank on legs (the mascot sits on it), two brick chimneys with goo puffs, and the theme's roof
    touches (sprinkles, snow, moss, sparkle orbs, planters). Sits on the top storey (roof surface at z = 16.8)."""
    metal, goo, goo_hi = th["metal"], th["goo"], th["goo_hi"]
    brick = wall_col(tid, th)
    parts = []
    tx, ty, z = 9.0, 4.0, H + 0.8
    for k in range(4):
        lx, ly = math.cos(math.radians(45 + 90 * k)) * 6.2, math.sin(math.radians(45 + 90 * k)) * 6.2
        parts.append(B(f"TankLeg{k}", (0.9, 0.9, 4.0), (tx + lx, ty + ly, z + 2.0), shade(metal, 0.8)))
    parts.append(CY("TankBot", 7.6, 1.6, (tx, ty, z + 4.0), metal, segs=20))
    parts.append(CY("TankGoo", 7.3, 4.6, (tx, ty, z + 5.6), goo, segs=20))
    for zz in (5.6, 10.2):
        parts.append(CY(f"TankHoop{zz}", 7.5, 0.4, (tx, ty, z + zz), shade(metal, 0.85), segs=20))
    parts.append(CY("TankTop", 7.6, 1.0, (tx, ty, z + 10.2), metal, segs=20, r_top=6.8))
    chims = ((-14.0, 14.0, 13.0), (-7.0, 17.0, 16.0))
    for k, (x, y, hh) in enumerate(chims):
        parts.append(CY(f"Chim{k}", 2.4, hh, (x, y, z), brick, segs=12, r_top=2.1))
        parts.append(CY(f"ChimBand{k}", 2.45, 0.6, (x, y, z + hh - 2.0), th["cream"], segs=12))
        parts.append(CY(f"ChimCap{k}", 2.8, 0.8, (x, y, z + hh), shade(metal, 0.7), segs=12))
        if tid != "crystal":
            parts.append(blob(f"Puff{k}", 2.6, (x + 0.6, y, z + hh + 2.8), goo_hi, subdiv=2, squash=(1.2, 1, 0.8), jitter=0.05))
    parts.append(tube("TankPipe", [(tx - 7.4, ty - 2, z + 7.5), (-2.0, -6.0, z + 5.0), (-2.0, -6.0, z + 0.4)],
                      [0.8, 0.8, 0.8], goo, segs=8))
    import random
    r = random.Random(5)
    if tid == "candy":
        for k, (x, y, hh) in enumerate(chims):
            parts += _stripes_ring(f"ChimStripe{k}", x, y, z + 0.6, z + hh - 2.2, 2.55, [th["cream"]], step=2.0)
        cols = [th["pink"], th["butter"], th["lilac"], th["metal"], th["cream"]]
        for k in range(46):
            x, y = r.uniform(-20, 20), r.uniform(-20, 10)
            if (x - tx) ** 2 + (y - ty) ** 2 < 70:
                continue
            parts.append(cylinder(f"Sprinkle{k}", 0.38, 2.2, (x, y, z + 0.4), cols[k % 5], segs=6,
                                  rot=(90, 0, r.uniform(0, 180))))
    elif tid == "crystal":
        for k, (x, y, hh) in enumerate(chims):
            parts.append(blob(f"ChimSnow{k}", 3.0, (x, y, z + hh + 0.9), th["cream"], subdiv=2, squash=(1, 1, 0.45), jitter=0.04))
        parts.append(blob("TankSnow", 7.4, (tx, ty, z + 11.3), th["cream"], subdiv=2, squash=(1, 1, 0.2), jitter=0.03))
        for k, (x, y) in enumerate(((-17, -17), (16, -16), (-17, 3), (17, 16), (0, -10))):
            parts.append(blob(f"RoofSnow{k}", 4.5, (x, y, z), th["cream"], subdiv=2, squash=(1.3, 1, 0.3), jitter=0.06))
        for k in range(4):
            a = k * 90
            parts.append(cone(f"RoofIce{k}", 1.0, 4.0, (12 * math.cos(math.radians(a + 30)), -12 + 4 * k, z), th["goo"], segs=6))
    elif tid == "mushroom":
        for k, (x, y, rr) in enumerate(((-15, -14, 5.0), (14, -15, 4.0), (-17, 4, 4.0), (0, -8, 3.5), (18, 16, 4.0))):
            parts.append(blob(f"Moss{k}", rr, (x, y, z), th["leaves"], subdiv=2, squash=(1.4, 1.1, 0.22), jitter=0.12))
        for k, (x, y, hh) in enumerate(chims):
            parts.append(blob(f"ChimMoss{k}", 2.6, (x, y, z + hh + 0.6), th["leaves"], subdiv=2, squash=(1, 1, 0.4), jitter=0.1))
        for k, (x, y) in enumerate(((-12, -16), (-15, -12), (15, -13))):
            parts.append(CY(f"RShroomStem{k}", 0.6, 2.0, (x, y, z), th["cream"], segs=8))
            parts.append(blob(f"RShroomCap{k}", 1.7, (x, y, z + 2.2), rgb(236, 90, 84), subdiv=2, squash=(1, 1, 0.5), jitter=0))
    elif tid == "starlight":
        for k, (x, y) in enumerate(((-16, -16), (16, -16), (-17, 4))):
            parts.append(CY(f"OrbPost{k}", 0.35, 4.0, (x, y, z), th["metal"], segs=8))
            parts.append(blob(f"Orb{k}", 1.6, (x, y, z + 5.2), th["goo_hi"], subdiv=2, jitter=0))
            parts.append(_star(f"OrbStar{k}", x, y - 1.7, z + 5.2, 1.0, th["metal"]))
        parts.append(_star("TankStar", tx, ty - 7.5, z + 8.0, 2.4, th["metal"]))
        for k, (x, y, hh) in enumerate(chims):
            parts.append(CY(f"ChimGold{k}", 2.5, 0.5, (x, y, z + hh - 0.6), th["metal"], segs=12))
    elif tid == "garden":
        for k, (x, y) in enumerate(((-15, -15), (15, -15), (-16, 2))):
            parts.append(B(f"Planter{k}", (5.0, 3.0, 1.6), (x, y, z + 0.8), th["pot"]))
            parts.append(blob(f"PlanterBush{k}", 2.2, (x, y, z + 2.6), th["cork"], subdiv=2, squash=(1.3, 0.9, 0.8), jitter=0.08))
            for j in range(3):
                parts.append(blob(f"PlanterBud{k}{j}", 0.8, (x - 1.5 + 1.5 * j, y - 1.4, z + 3.2), th["buds"][j % 3], subdiv=1, jitter=0))
    return parts


def dress(tid, th, ground):
    """Themed per-storey dressing (one mesh per theme on floors 2-4; floor 1's version is built into the foot):
    icicles, window boxes, vines, candy-stripe pilasters, gold trim. Classic has none."""
    import random
    r = random.Random(17 if ground else 23)
    parts = []
    T = L.WALL
    out_band = T / 2 + 0.7
    if tid == "crystal":
        for side in SIDES:
            nm, axis, fixed, sign = side
            parts.append(_sbox(f"BandSnow{nm}", axis, fixed, sign, -0.6, SPAN + 0.6, BAND_Z + 0.5, BAND_Z + 0.95, 1.4,
                               T / 2 + 0.25, th["cream"]))
            for k in range(16):
                u = 1.0 + k * 3.05
                x, y = _at(axis, fixed, u, out_band, sign)
                parts.append(cone(f"Ice{nm}{k}", 0.85, 3.0 + r.random() * 2.5, (x, y, BAND_Z - 0.5), th["goo"], segs=6,
                                  rot=(180, 0, 0)))
            for j, (u0, u1) in enumerate(_win_spans(side, ground)):
                parts.append(_sbox(f"SillSnow{nm}{j}", axis, fixed, sign, u0 - 0.6, u1 + 0.6, WIN_Z0, WIN_Z0 + 0.35, 0.9,
                                   T / 2 + 0.3, th["cream"]))
    elif tid == "garden":
        for side in SIDES:
            nm, axis, fixed, sign = side
            for j, (u0, u1) in enumerate(_win_spans(side, ground)):
                parts.append(_sbox(f"WinBox{nm}{j}", axis, fixed, sign, u0 + 0.5, u1 - 0.5, WIN_Z0 - 2.0, WIN_Z0 - 0.6, 1.6,
                                   T / 2 + 0.9, th["pot"]))
                n = int((u1 - u0) / 2.0)
                for k in range(n):
                    x, y = _at(axis, fixed, u0 + 1.2 + k * 2.0, T / 2 + 1.0, sign)
                    parts.append(blob(f"Flw{nm}{j}{k}", 0.95, (x, y, WIN_Z0 - 0.2), th["buds"][k % 3], subdiv=1, jitter=0.05))
        for k, x in enumerate((-L.HALF + 0.3, L.HALF - 0.3)):
            pts = [(x + math.sin(t * 1.3) * 0.8, -L.HALF - 1.4, 0.3 + t * 2.4) for t in range(7)]
            parts.append(tube(f"Vine{k}", pts, [0.45] * len(pts), shade(th["cork"], 0.8), segs=6))
            for j, p in enumerate(pts[1:]):
                parts.append(blob(f"VLeaf{k}{j}", 1.15, (p[0] + (1 if j % 2 else -1), p[1] - 0.2, p[2]), th["cork"], subdiv=1,
                                  squash=(1, 0.45, 0.75), jitter=0))
    elif tid == "candy":
        for sx in (-1, 1):
            for sy in (-1, 1):
                for k in range(5):
                    parts.append(box(f"Cane{sx}{sy}{k}", (2.6, 2.6, 1.3),
                                     (sx * (L.HALF - 0.5), sy * (L.HALF - 0.5), 1.4 + k * 2.6), th["cream"]))
        for side in SIDES:
            nm, axis, fixed, sign = side
            for k in range(12):
                x, y = _at(axis, fixed, 2.0 + k * 4.0, out_band, sign)
                parts.append(blob(f"Drip{nm}{k}", 0.85, (x, y, BAND_Z - 0.9), th["goo"], subdiv=1, squash=(1, 0.6, 1.4), jitter=0))
    elif tid == "starlight":
        for side in SIDES:
            nm, axis, fixed, sign = side
            parts.append(_sbox(f"Gold{nm}", axis, fixed, sign, -0.7, SPAN + 0.7, BAND_Z - 0.25, BAND_Z + 0.25, 1.2,
                               T / 2 + 0.3, th["metal"]))
            for j, (u0, u1) in enumerate(_win_spans(side, ground)):
                parts.append(_sbox(f"GoldSill{nm}{j}", axis, fixed, sign, u0 - 0.7, u1 + 0.7, WIN_Z0 - 0.35, WIN_Z0 - 0.05, 1.0,
                                   T / 2 + 0.3, th["metal"]))
        for sx in (-1, 1):
            parts.append(_star(f"PilStar{sx}", sx * (L.HALF - 0.5), -L.HALF - 0.9, 8.0, 1.3, th["metal"]))
    elif tid == "mushroom":
        xs = (-19.0, -12.0, 13.0, 19.5) if not ground else (-19.0, -13.5, 13.5, 19.5)
        for k, x in enumerate(xs):
            pts = [(x + math.sin(t * 1.1 + k) * 0.9, -L.HALF - 1.3, 0.2 + t * 2.6) for t in range(7)]
            parts.append(tube(f"Vine{k}", pts, [0.5] * len(pts), shade(th["metal"], 0.85), segs=6))
            for j, p in enumerate(pts[1:]):
                parts.append(blob(f"VLeaf{k}{j}", 1.2, (p[0] + (1.1 if j % 2 else -1.1), p[1] - 0.2, p[2]), th["leaves"],
                                  subdiv=1, squash=(1, 0.45, 0.75), jitter=0))
        for side in SIDES:
            nm, axis, fixed, sign = side
            for k in range(6):
                x, y = _at(axis, fixed, 4.0 + k * 8.0, T / 2 + 0.5, sign)
                parts.append(blob(f"BandMoss{nm}{k}", 1.6, (x, y, BAND_Z + 0.5), th["leaves"], subdiv=2, squash=(1.5, 0.8, 0.5),
                                  jitter=0.1))
    return parts


def foot(tid, th):
    """Themed: round plot (grass), goo moat, concrete yard, plank bridge, plus the theme's door-zone and yard touches
    (candy awning, star on the sign, sunflowers, ice crystals, toadstools...)."""
    gx = [int(c) for c in th["ground"].split(",")]
    grass = rgb(*gx)
    # tops: grass -0.1, moat goo -0.3, yard -0.03 (floor 1's factory floor is the top at 0)
    parts = [CY("PlotOut", L.HALF + 16.0, 0.5, (0, 0, -0.6), grass, segs=64, k=0.8)]
    parts.append(CY("MoatGoo", 38.5, 0.45, (0, 0, -0.75), th["goo"], segs=64))
    parts.append(CY("PlotIn", 34.5, 0.6, (0, 0, -0.7), grass, segs=64, k=0.85))
    parts.append(B("Yard", (2 * L.HALF + 4, 2 * L.HALF + 4, 0.3), (0, 0, -0.18), th["path"], k=0.95))
    parts.append(B("Bridge", (10, 15, 0.6), (0, -(L.HALF + 7.5), 0.0), th["wood"]))
    for k in range(6):
        parts.append(box(f"Plank{k}", (10.2, 0.15, 0.05), (0, -(L.HALF + 1.5) - k * 2.4, 0.31), th["wood_d"]))
    for s in (-1, 1):
        parts.append(B(f"BridgeRail{s}", (0.5, 15, 0.6), (s * 4.8, -(L.HALF + 7.5), 1.6), th["wood_d"]))
    yf = -L.HALF
    import random
    r = random.Random(3)
    if tid == "candy":
        for k in range(6):
            x = -6.25 + k * 2.5
            col = th["pink"] if k % 2 == 0 else th["cream"]
            parts.append(box(f"Awning{k}", (2.5, 4.2, 0.35), (x, yf - 2.1, 12.4), col, rot=(-22, 0, 0)))
            parts.append(blob(f"AwnScallop{k}", 1.0, (x, yf - 4.0, 11.5), col, subdiv=2, squash=(1.2, 0.4, 0.8), jitter=0))
        for k, (x, y, c) in enumerate(((26, -19, "pink"), (-25, -21, "butter"), (27, 19, "lilac"))):
            parts.append(blob(f"Gum{k}", 2.4, (x, y, 1.2), th[c], subdiv=2, squash=(1, 1, 0.85), jitter=0))
        for k, x in enumerate((-7.0, 7.0)):
            parts.append(CY(f"LolliStick{k}", 0.3, 7.0, (x, yf - 5.0, 0), th["cream"], segs=6))
            parts.append(CY(f"Lolli{k}", 2.2, 0.5, (x, yf - 5.25, 7.6), th["pink"] if k else th["lilac"], segs=16, rot=(90, 0, 0)))
            parts.append(CY(f"LolliSwirl{k}", 1.2, 0.55, (x, yf - 5.3, 7.6), th["cream"], segs=12, rot=(90, 0, 0)))
    elif tid == "crystal":
        for k, (x, y) in enumerate(((26, -19), (-25, -21), (27, 19))):
            for j in range(3):
                parts.append(cone(f"Crys{k}{j}", 1.4 - 0.3 * j, 7.0 - 1.8 * j, (x + j * 1.3, y + (j % 2) * 1.2, 0),
                                  [th["goo"], th["lilac"], th["goo_hi"]][j], segs=6, rot=(0, 10 * (j - 1), 0)))
        for k in range(8):
            x = -21 + k * 6.0
            if abs(x) < 7:
                continue
            parts.append(blob(f"Drift{k}", 2.4, (x, yf - 1.6, 0.0), th["cream"], subdiv=2, squash=(1.5, 1, 0.5), jitter=0.05))
    elif tid == "garden":
        for s in (-1, 1):
            parts.append(B(f"Bed{s}", (11.0, 2.4, 0.9), (s * 14.5, yf - 2.0, 0.45), th["wood_d"]))
            for k in range(7):
                parts.append(blob(f"BedFlw{s}{k}", 1.0, (s * 14.5 - 4.8 + k * 1.6, yf - 2.0 + (k % 2) * 0.6 - 0.3, 1.4),
                                  th["buds"][k % 3], subdiv=1, jitter=0.05))
        for k, x in enumerate((-7.0, 7.0)):
            parts.append(CY(f"SunStem{k}", 0.35, 9.0, (x, yf - 5.5, 0), th["cork"], segs=6))
            parts.append(CY(f"SunHead{k}", 2.4, 0.6, (x, yf - 5.8, 9.4), th["butter"], segs=14, rot=(90, 0, 0)))
            parts.append(CY(f"SunEye{k}", 1.1, 0.7, (x, yf - 5.9, 9.4), th["wood_d"], segs=10, rot=(90, 0, 0)))
            parts.append(blob(f"SunLeaf{k}", 1.3, (x + 1.0, yf - 5.5, 4.0), th["cork"], subdiv=1, squash=(1.2, 0.4, 0.6), jitter=0))
    elif tid == "starlight":
        parts.append(_star("SignStar", 11.6, yf - 2.2, 16.3, 2.4, th["metal"]))
        for k, x in enumerate((-7.0, 7.0)):
            parts.append(CY(f"LampPost{k}", 0.35, 6.5, (x, yf - 5.5, 0), th["wood_d"], segs=8))
            parts.append(blob(f"LampOrb{k}", 1.6, (x, yf - 5.5, 7.6), th["goo_hi"], subdiv=2, jitter=0))
            parts.append(_star(f"LampStar{k}", x, yf - 7.2, 7.6, 0.9, th["metal"]))
        for k, (x, y) in enumerate(((26, -19), (-25, -21), (27, 19))):
            parts.append(blob(f"GlowStone{k}", 1.8, (x, y, 0.6), th["lilac"], subdiv=2, squash=(1, 1, 0.7), jitter=0.1))
    elif tid == "mushroom":
        for k, (x, y, rr, hh) in enumerate(((26, -19, 3.2, 4.5), (-25, -21, 2.6, 3.6), (27, 19, 3.0, 4.2), (23, -23, 1.6, 2.2))):
            parts.append(CY(f"ToadStem{k}", rr * 0.32, hh, (x, y, 0), th["cream"], segs=10))
            parts.append(blob(f"ToadCap{k}", rr, (x, y, hh + rr * 0.15), rgb(236, 90, 84), subdiv=2, squash=(1, 1, 0.5), jitter=0))
            for j in range(4):
                a = j * 1.6
                parts.append(blob(f"ToadDot{k}{j}", rr * 0.18, (x + math.cos(a) * rr * 0.6, y + math.sin(a) * rr * 0.6,
                                                               hh + rr * 0.55), th["cream"], subdiv=1, jitter=0))
        for k in range(6):
            x = -21 + k * 8.4
            if abs(x) < 7:
                continue
            parts.append(blob(f"FootMoss{k}", 2.2, (x, yf - 1.4, 0.0), th["leaves"], subdiv=2, squash=(1.6, 1, 0.45), jitter=0.1))
    # floor 1's storey dressing rides in the foot (floor 1 is static), so a theme needs only 3 meshes
    return parts + dress(tid, th, True)


# ---------- door frame (fixed colours: the lock signal) ----------
HAZ, DARK, STEEL = rgb(250, 206, 70), rgb(70, 70, 84), rgb(150, 160, 176)


def door_frame():
    """Big yellow/black hazard frame round the doorway and the shutter drum above it."""
    parts = []
    y = -L.HALF - 0.6
    dw = L.DOOR["width"] / 2
    for s in (-1, 1):
        x = s * (dw + 0.75)
        parts.append(B(f"Post{s}", (1.5, 2.2, L.DOOR["height"] + 0.8), (x, y, (L.DOOR["height"] + 0.8) / 2), HAZ, k=0.95))
        for k in range(5):
            parts.append(box(f"Stripe{s}{k}", (1.55, 2.25, 1.0), (x, y, 1.0 + k * 2.2), DARK, rot=(0, 25 * s, 0)))
    parts.append(B("Header", (2 * dw + 3.0, 2.2, 1.0), (0, y, L.DOOR["height"] + 0.5), HAZ, k=0.95))
    for k in range(6):
        parts.append(box(f"HStripe{k}", (0.9, 2.25, 1.05), (-dw - 0.6 + k * 2.3, y, L.DOOR["height"] + 0.5), DARK,
                         rot=(0, 30, 0)))
    zc = L.SHUTTER_DRUM_Z
    parts.append(CY("Drum", 1.35, 2 * dw + 2.4, (-(dw + 1.2), y - 0.4, zc), STEEL, segs=16, rot=(0, 90, 0)))
    for s in (-1, 1):
        parts.append(CY(f"DrumCap{s}", 1.6, 0.5, ((dw + 1.2) * s - (0.5 if s > 0 else 0), y - 0.4, zc), DARK, segs=16,
                        rot=(0, 90, 0)))
    for k in range(3):
        parts.append(CY(f"DrumRib{k}", 1.4, 0.3, (-3.5 + k * 3.3, y - 0.4, zc), shade(STEEL, 0.8), segs=16, rot=(0, 90, 0)))
    return parts
def shutter(shut=False):
    """The roll-up shutter: slats filling the doorway when shut; rolled into the drum when open (a short apron shows)."""
    parts = []
    dw = L.DOOR["width"] / 2
    y = -L.HALF - 0.1
    hgt = L.DOOR["height"] if shut else 1.2
    z0 = 0.0 if shut else L.DOOR["height"] - 1.2
    n = max(1, int(hgt / 0.9))
    for k in range(n):
        parts.append(B(f"Slat{k}", (2 * dw - 0.2, 0.5, 0.82), (0, y, z0 + 0.45 + k * hgt / n), STEEL if k % 2 else shade(STEEL, 0.9)))
    parts.append(B("BottomBar", (2 * dw - 0.1, 0.7, 0.4), (0, y, z0 + 0.2), RED_LOCK if shut else DARK))
    return parts


RED_LOCK = rgb(240, 70, 60)


def belt():
    parts = []
    y = L.BELT["y"]
    x0, x1, w, h = L.BELT["x0"], L.BELT["x1"], L.BELT["w"], L.BELT["h"]
    parts.append(B("BeltTop", (x1 - x0, w - 0.4, 0.3), ((x0 + x1) / 2, y, h - 0.15), DARK))
    for s in (-1, 1):
        parts.append(B(f"BeltRail{s}", (x1 - x0 + 0.6, 0.3, h + 0.2), ((x0 + x1) / 2, y + s * (w / 2 - 0.15), (h + 0.2) / 2), STEEL))
    for k in range(7):
        x = x0 + 1 + k * (x1 - x0 - 2) / 6
        parts.append(B(f"BeltLeg{k}", (0.6, w - 0.6, h - 0.3), (x, y, (h - 0.3) / 2), shade(STEEL, 0.8)))
    for s in (-1, 1):
        parts.append(CY(f"Roller{s}", 0.7, w - 0.2, ((x0 if s < 0 else x1), y + (w - 0.2) / 2, h - 0.7), STEEL, segs=10,
                        rot=(90, 0, 0)))
    return parts


def hatch():
    """Drop hatch in the east wall (tint): a 4 x 7 door with a round goo window and a frame."""
    x = L.WC
    parts = [B("HatchDoor", (0.5, 3.8, 6.8), (x, L.HATCH_Y, 1.0 + 3.4), g(0.85))]
    for s in (-1, 1):
        parts.append(box(f"HatchJamb{s}", (1.4, 0.4, 7.4), (x, L.HATCH_Y + s * 2.1, 1.0 + 3.6), g(1.0)))
    parts.append(box("HatchHead", (1.4, 4.6, 0.5), (x, L.HATCH_Y, 8.2), g(1.0)))
    parts.append(CY("HatchWin", 1.1, 0.7, (x - 0.35, L.HATCH_Y, 5.6), g(0.45), segs=12, rot=(0, 90, 0)))
    parts.append(box("HatchArrow", (0.1, 1.6, 0.5), (x - 0.3, L.HATCH_Y, 3.2), g(1.0)))
    return parts


def chute(top_floor):
    """The goo chute from floor top_floor's hatch down the outside of the east wall (tint: the goo colour).
    Built in plot coords with floor 1's walking surface at z = 0. Zig-zag in y, one leg per half storey."""
    parts = []
    zs = (top_floor - 1) * H + 3.0
    legs = (top_floor - 1) * 2 + 1
    pts = []
    for k in range(legs + 1):
        y = L.HATCH_Y if k == 0 else (16.0 if k % 2 else -18.0)
        pts.append((L.CHUTE_X, y, zs - zs * k / legs))
    pts[-1] = (L.CHUTE_X, pts[-1][1], 0.3)
    for k in range(legs):
        (x0, y0, z0), (x1, y1, z1) = pts[k], pts[k + 1]
        run = abs(y1 - y0)
        ln = math.hypot(run, z0 - z1)
        ang = math.degrees(math.atan2(z0 - z1, run)) * (1 if y1 > y0 else -1)
        cy_, cz = (y0 + y1) / 2, (z0 + z1) / 2
        parts.append(B(f"Bed{k}", (3.0, ln, 0.4), (x0, cy_, cz), g(0.95), rot=(ang, 0, 0)))
        for s in (-1, 1):
            parts.append(B(f"Lip{k}{s}", (0.4, ln, 1.2), (x0 + s * 1.6, cy_, cz + 0.5), g(0.75), rot=(ang, 0, 0)))
        if k < legs - 1:
            parts.append(CY(f"Turn{k}", 2.0, 1.4, (x1, y1, z1 - 0.7), g(0.85), segs=12))
        # wall brackets
        parts.append(box(f"Brk{k}", (2.6, 0.4, 0.4), (L.HALF + 0.9, cy_, cz - 0.6), g(0.6)))
    parts.append(CY("Splash", 4.0, 0.5, (L.CHUTE_X + 1.5, pts[-1][1] + (2 if pts[-1][1] > 0 else -2), 0.0), g(1.0), segs=20))
    return parts


def silo():
    parts = [CY("SiloBody", L.SILO_R, L.SILO_H - 3, (0, 0, 0), g(0.88), segs=18)]
    parts.append(CY("SiloCap", L.SILO_R + 0.2, 3.0, (0, 0, L.SILO_H - 3), g(0.95), segs=18, r_top=0.8))
    for zz in (1.0, 7.0, 13.0):
        parts.append(CY(f"SiloHoop{zz}", L.SILO_R + 0.15, 0.4, (0, 0, zz), g(0.7), segs=18))
    parts.append(B("SiloGauge", (0.3, 1.2, 6.0), (L.SILO_R + 0.1, 0, 9.5), g(0.45)))
    return parts




# name -> (builder taking (theme id, theme dict), tint role or None). Roles are resolved by role_col in the scene.
PIECES = {
    "factory_storey_1": (lambda tid, th: storey_shell(True), "brick"),
    "factory_storey": (lambda tid, th: storey_shell(False), "brick"),
    "factory_trim_1": (lambda tid, th: storey_trim(True), "cream"),
    "factory_trim": (lambda tid, th: storey_trim(False), "cream"),
    "factory_windows_1": (lambda tid, th: storey_windows(True), "glass"),
    "factory_windows": (lambda tid, th: storey_windows(False), "glass"),
    "factory_pipes": (lambda tid, th: storey_pipes(False), "goo"),
    "factory_pipes_1": (lambda tid, th: storey_pipes(True), "goo"),
    "factory_parapet": (lambda tid, th: parapet(), "cream"),
    "factory_sign": (lambda tid, th: sign(), None),
    "factory_floor_1": (lambda tid, th: floor_1_slab(), "path"),
    "factory_slab": (lambda tid, th: slab(), "path"),
    "factory_stair": (lambda tid, th: stair(), "goo"),
    "factory_core": (lambda tid, th: core(), "wood_d"),
    "factory_core_cap": (lambda tid, th: core_cap(), "path"),
    "factory_roof": (lambda tid, th: roof(), "metal"),
    "factory_roof_kit": (lambda tid, th: roof_kit(tid, th), None),
    "factory_door_frame": (lambda tid, th: door_frame(), None),
    "factory_shutter": (lambda tid, th: shutter(), None),
    "factory_belt": (lambda tid, th: belt(), None),
    "factory_hatch": (lambda tid, th: hatch(), "metal"),
    "factory_chute_2": (lambda tid, th: chute(2), "goo"),
    "factory_chute_3": (lambda tid, th: chute(3), "goo"),
    "factory_chute_4": (lambda tid, th: chute(4), "goo"),
    "factory_silo": (lambda tid, th: silo(), "metal"),
    "factory_foot": (lambda tid, th: foot(tid, th), None),
    "factory_dress": (lambda tid, th: dress(tid, th, False), None),
}
THEMED = ("factory_foot", "factory_roof_kit", "factory_dress")  # one each per theme (classic: no dress)
