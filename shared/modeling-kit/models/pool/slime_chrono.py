# Chrono (Secret): time slime shaped like an hourglass. Two sapphire goo bulbs pinched at a gold
# waist ring, held by a gold frame (two plates + three turned posts). Golden sand drains from the top
# bulb in a thin stream onto a pile in the bottom one. Clock-dial eyes with little hands (each eye
# shows a different time), a smug smirk, a tilted ring of Roman numerals and brass gears orbiting.
from models._slimepool import *


# ---- grid-projected decal (copied from slime_moo.py): wide decals that follow the curve
def _inside(pt, poly):
    x, y = pt
    c = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            c = not c
    return c


def grid_decal(name, poly, color, frame=FRONT, off=0.008, th=0.012, on=None, step=0.08, cell=0.12):
    from mathutils.geometry import delaunay_2d_cdt
    poly = densify(poly, step)
    n = len(poly)
    us, vs = [p[0] for p in poly], [p[1] for p in poly]
    inner = []
    u = min(us) + cell / 2
    while u < max(us):
        v = min(vs) + cell / 2
        while v < max(vs):
            if _inside((u, v), poly) and min((u - a) ** 2 + (v - b) ** 2 for a, b in poly) > (cell * 0.45) ** 2:
                inner.append((u, v))
            v += cell
        u += cell
    pts = [Vector(p) for p in poly + inner]
    V2, _, F, *_ = delaunay_2d_cdt(pts, [(i, (i + 1) % n) for i in range(n)], [list(range(n))], 1, 1e-6)
    F = [f for f in F if _inside(tuple(sum((V2[i] for i in f), Vector((0, 0))) / len(f)), poly)]
    bm = bmesh.new()
    top, bot = {}, {}
    for f in F:
        for i in f:
            if i in top:
                continue
            uu, vv = V2[i]
            hit = cast(frame.O + frame.U * uu + frame.V * vv + frame.D * 12, -frame.D, on)
            if hit is None:
                raise ValueError(f"grid_decal {name}: ({uu:.2f}, {vv:.2f}) misses every surface")
            loc, nn, _ = hit
            if nn.dot(frame.D) < 0:
                nn = -nn
            nn = (nn * 0.6 + frame.D * 0.4).normalized()
            bot[i] = bm.verts.new(loc + nn * off)
            top[i] = bm.verts.new(loc + nn * (off + th))
    ecount = {}
    for f in F:
        bm.faces.new([top[i] for i in f])
        bm.faces.new([bot[i] for i in reversed(f)])
        for a, b in zip(f, f[1:] + f[:1]):
            ecount[(a, b)] = ecount.get((a, b), 0) + 1
    for (a, b) in ecount:
        if (b, a) not in ecount:
            bm.faces.new((bot[a], bot[b], top[b], top[a]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, False)



GLASS_D, GLASS, GLASS_L = hexc("1f3fd8"), hexc("3a7cff"), hexc("8fd2ff")
SAND, SAND_L, SAND_D = hexc("ffd83a"), hexc("fff4a8"), hexc("f5a623")
BRASS_D, BRASS, BRASS_L = hexc("8a4410"), hexc("d98424"), hexc("ffcf70")
IVORY, IVORY_D, NUM = hexc("fff7e2"), hexc("f0d8a8"), hexc("3a2440")
DIAL = hexc("fffdf6")

S = 0.95  # vertical squash so the whole thing stays near the body frame
ZB, ZT = 0.2, 3.72 * S  # plates
WAIST = 1.62 * S

prof = [(ZB, 1.0), (0.32 * S, 1.28), (0.66 * S, 1.42), (1.02 * S, 1.24), (1.3 * S, 0.8), (1.48 * S, 0.45),
        (WAIST, 0.36), (1.78 * S, 0.47), (2.05 * S, 0.95), (2.5 * S, 1.4), (3.0 * S, 1.48), (3.42 * S, 1.18),
        (ZT - 0.02, 0.86), (ZT, 0)]

SAND_BOT = 0.8 * S    # sand level in the bottom bulb
SAND_TOP = 2.55 * S    # sand level in the top bulb (draining)


def paint(a, z, p):
    return mix(GLASS_D, GLASS, smoothstep(ZB, 1.2, z)) if z < WAIST else mix(GLASS, GLASS_L, smoothstep(2.3, ZT, z))


b = Body(prof, paint=paint, segs=32, sub=2, gloss=0.55, shade=0.6,
         bands=[(ZB - 0.01, SAND_BOT, SAND), (WAIST - 0.1, SAND_TOP, SAND)])
parts = [b.obj]

# ---------------------------------------------------------------- the falling sand stream (front + back)
for nm, yaw in (("Stream", 0), ("StreamB", 180)):
    fr = frame_at(yaw)
    pile = [(-0.75 + 1.5 * k / 16, SAND_BOT - 0.03 + 0.34 * math.exp(-((-0.75 + 1.5 * k / 16) / 0.3) ** 2)) for k in range(17)]
    parts.append(grid_decal(f"{nm}Pile", pile + [(0.75, SAND_BOT - 0.06), (-0.75, SAND_BOT - 0.06)], SAND, fr, off=0.006, th=0.014, on=["Body"], cell=0.22))
    top, bot = WAIST + 0.05, SAND_BOT + 0.28
    poly = [(-0.06, top), (0.06, top), (0.095, bot), (-0.095, bot)]
    parts.append(decal(nm, densify(poly, 0.06), along(SAND, SAND_L, (0, 0, bot), (0, 0, top)), fr, off=0.016, th=0.012, on=["Body"], step=None))
    if yaw:
        continue
    dip = [(-0.36, SAND_TOP + 0.02), (0.36, SAND_TOP + 0.02), (0.05, SAND_TOP - 0.2), (-0.05, SAND_TOP - 0.2)]
    parts.append(grid_decal(f"{nm}Dip", dip, mix(GLASS, GLASS_L, 0.25), fr, off=0.006, th=0.014, on=["Body"], cell=0.2))
    for k, (u, v, r) in enumerate(((0.14, 1.0, 0.035), (-0.15, 1.15, 0.03), (0.11, 1.3, 0.028))):
        parts.append(decal(f"{nm}Grain{k}", oval(u, v * S, r * 2, r * 2, n=8), SAND_L, fr, off=0.012, th=0.015, on=["Body"]))

# ---------------------------------------------------------------- face: clock-dial eyes + smirk
EV, EU = 3.08 * S, 0.55
f = Face(b, eye_u=EU, eye_v=EV, mouth_v=2.74 * S)
for sd, (hh, mm) in ((-1, (10, 10)), (1, (2, 50))):
    u = sd * EU
    f.parts.append(grid_decal(f"Eye{sd}", oval(u, EV, 0.76, 0.8, n=18), BRASS_D, FRONT, off=0.01, th=0.012, on=["Body"], cell=0.26))
    f.parts.append(grid_decal(f"EyeRim{sd}", oval(u, EV, 0.68, 0.72, n=18), BRASS_L, FRONT, off=0.022, th=0.01, on=["Body"], cell=0.26))
    f.parts.append(grid_decal(f"EyeW{sd}", oval(u, EV, 0.57, 0.61, n=18), DIAL, FRONT, off=0.032, th=0.01, on=["Body"], cell=0.22))
    for t in (0, 3, 6, 9):
        ang = math.radians(90 - t * 30)
        big = t % 3 == 0
        rr = 0.23
        f.d(f"Tick{sd}{t}", rect(u + math.cos(ang) * rr, EV + math.sin(ang) * rr * 1.07, 0.05 if big else 0.025, 0.025 if big else 0.02,
                                 ang), NUM, off=0.047, th=0.008)
    for nm, val, L, w in (("Hour", (hh % 12 + mm / 60) / 12, 0.14, 0.06), ("Min", mm / 60, 0.22, 0.038)):
        ang = math.radians(90 - val * 360)
        cu, cv = u + math.cos(ang) * L / 2, EV + math.sin(ang) * L / 2 * 1.07
        f.d(f"{nm}{sd}", rect(cu, cv, L, w, ang), NUM, off=0.05, th=0.01)
    f.d(f"Pin{sd}", oval(u, EV, 0.06, 0.06, n=8), hexc("ff4a6a"), off=0.062, th=0.008)
    f.d(f"EyeHi{sd}", oval(u - 0.12, EV + 0.14, 0.09, 0.06, n=8, rot=0.5), WHITE, off=0.07, th=0.006)
f.mouth("smirk", w=1.05).cheeks(color=hexc("ff7fb0"), w=0.28, h=0.13, v=EV - 0.38)
parts += f.parts

# ---------------------------------------------------------------- gold frame
plate = [(0, 0), (0, 1.62), (0.05, 1.76), (0.13, 1.8), (0.2, 1.72), (0.22, 1.5), (0.24, 0)]
parts.append(lathe("PlateB", plate, along(BRASS_D, BRASS, (0, 0, 0), (0, 0, 0.24)), pos=(0, 0, -0.04), segs=20, smooth=False))
parts.append(lathe("PlateT", [(0, 0), (0.02, 1.5), (0.04, 1.72), (0.11, 1.8), (0.19, 1.76), (0.24, 1.62), (0.24, 0)],
                   along(BRASS, BRASS_L, (0, 0, ZT), (0, 0, ZT + 0.24)), pos=(0, 0, ZT - 0.02), segs=20, smooth=False))
# finial: knob + small ring on top
parts.append(lathe("Finial", [(0, 0.3), (0.1, 0.22), (0.18, 0.1), (0.28, 0.15), (0.38, 0.08), (0.46, 0)],
                   along(BRASS, BRASS_L, (0, 0, ZT + 0.2), (0, 0, ZT + 0.7)), pos=(0, 0, ZT + 0.22), segs=8, sub=2))
parts.append(torus("FinialRing", 0.14, 0.035, (0, 0, ZT + 0.8), (0, 1, 0), BRASS, segs=10, rsegs=4))
# turned posts
post = [(0, 0.1), (0.14, 0.07), (0.5, 0.06), (1.2, 0.05), (1.36, 0.1), (1.5, 0.11), (1.64, 0.1), (1.8, 0.05),
        (2.6, 0.06), (3.0, 0.07), (ZT - 0.18, 0.1)]
for k, yaw in enumerate((60, 180, 300)):
    a = math.radians(yaw)
    pp = (math.sin(a) * 1.62, -math.cos(a) * 1.62, 0.18)
    parts.append(lathe(f"Post{k}", [(t * (ZT - 0.18) / (ZT - 0.18), r) for t, r in post], along(BRASS_D, BRASS_L, (0, 0, 0.2), (0, 0, ZT)),
                       pos=pp, segs=6, sub=0))
parts.append(torus("WaistRing", 0.44, 0.08, (0, 0, WAIST), (0, 0, 1), along(BRASS, BRASS_L, (0, 0, WAIST - 0.08), (0, 0, WAIST + 0.08)), segs=16, rsegs=5))

# ---------------------------------------------------------------- tilted Roman numeral ring
RN = Vector((0, math.sin(math.radians(18)), math.cos(math.radians(18)))).normalized()  # halo axis (front tips up, so the numerals face a low camera)
RC = Vector((0, 0.05, ZT + 0.62))
RR, RH, RT = 1.5, 0.28, 0.05


def band_ring(name, R, h, t, center, normal, color, segs=32):
    q = Vector(normal).normalized().to_track_quat("Z", "Y")
    bm = bmesh.new()
    rings = []
    for rad, zz in ((R - t, -h / 2), (R, -h / 2), (R, -h * 0.28), (R, h * 0.28), (R, h / 2), (R - t, h / 2), (R - t, h * 0.28), (R - t, -h * 0.28)):
        rings.append([bm.verts.new(Vector(center) + q @ Vector((math.cos(k * math.tau / segs) * rad, math.sin(k * math.tau / segs) * rad, zz))) for k in range(segs)])
    for i in range(len(rings)):
        A, B = rings[i], rings[(i + 1) % len(rings)]
        for k in range(segs):
            bm.faces.new((A[k], A[(k + 1) % segs], B[(k + 1) % segs], B[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, False)


def ring_col(p, n):
    h = (p - RC).dot(RN)
    edge = smoothstep(RH * 0.3, RH * 0.45, abs(h))
    return mix(IVORY, BRASS, edge)


parts.append(band_ring("NumRing", RR, RH, RT, RC, RN, ring_col))
q = RN.to_track_quat("Z", "Y")
NUMS = ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
glyphs = []
for k, txt in enumerate(NUMS):
    ang = math.radians(90 + k * 30)
    out = q @ Vector((math.cos(ang), math.sin(ang), 0))
    up = RN
    side = up.cross(out).normalized()
    base = RC + out * (RR + 0.004)
    # stroke list in local (x along side, y up) for each letter, letters laid out left to right
    strokes = []
    x = 0.0
    for ch in txt:
        if ch == "I":
            strokes.append((x, 0.0, 0.0)); x += 0.07
        elif ch == "V":
            strokes.append((x + 0.035, 0.0, -17)); strokes.append((x + 0.085, 0.0, 17)); x += 0.15
        elif ch == "X":
            strokes.append((x + 0.06, 0.0, 28)); strokes.append((x + 0.06, 0.0, -28)); x += 0.15
    w = x - 0.07 if txt[-1] == "I" else x - 0.03
    for j, (sx, sy, rot) in enumerate(strokes):
        r = math.radians(rot)
        ax = (up * math.cos(r) + side * math.sin(r)).normalized()  # stroke direction on the band
        perp = out.cross(ax).normalized()
        cen = base + side * (sx - w / 2) + out * 0.015
        parts.append(slab(f"Num{k}_{j}", rect(0, 0, 0.17, 0.032), 0.03, cen, ax, perp, NUM))

# ---------------------------------------------------------------- floating brass gears
def gear_poly(r_out, r_in, teeth):
    pts = []
    for t in range(teeth):
        a0 = t * math.tau / teeth
        for da, r in ((0.0, r_in), (0.18, r_out), (0.5, r_out), (0.68, r_in)):
            a = a0 + da * math.tau / teeth
            pts.append((math.cos(a) * r, math.sin(a) * r))
    return pts


for k, (pos, rr, teeth, nrm) in enumerate((((-2.05, 0.15, 3.55), 0.42, 9, (-0.5, -1, 0.35)), ((2.15, 0.35, 3.1), 0.32, 8, (0.6, -1, 0.2)),
                                           ((-1.95, 0.3, 0.85), 0.26, 7, (-0.6, -0.8, 0.5)))):
    N = Vector(nrm).normalized()
    X = N.cross(Vector((0, 0, 1))).normalized()
    Y = N.cross(X).normalized()
    P = Vector(pos)
    rr *= 1.15
    parts.append(slab(f"Gear{k}", gear_poly(rr, rr * 0.8, teeth), 0.08, P, X, Y, along(BRASS, BRASS_L, P - Y * rr, P + Y * rr)))
    parts.append(slab(f"GearHub{k}", oval(0, 0, rr * 0.42, rr * 0.42, n=8), 0.12, P, X, Y, BRASS_D))

ship("slime_chrono", parts)
