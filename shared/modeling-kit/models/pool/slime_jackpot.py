# Jackpot (Secret tier jackpot): a slot-machine slime. Glossy candy-red body with a squarish
# cabinet cross-section and gold trim bands, a coin slot on its crown with a coin half inside,
# a ring of marquee bulbs round the head, a gold-framed window on the belly showing three red
# "7" reels, a chrome lever with a big red ball on its right side, gold coins orbiting on a
# tilted ring and spilling at its feet, star eyes and a giddy open grin.
from models._slimepool import *
import re

RED_D, RED, RED_L = hexc("a3081f"), hexc("ee1c32"), hexc("ff6a6a")
GD, G, GL, GW = hexc("c86a00"), hexc("ffb81c"), hexc("ffe46a"), hexc("fff8d6")
CHROME_D, CHROME = hexc("8a94a8"), hexc("eef2fa")
WIN_BG = hexc("2a0a2a")
REEL_D, REEL = hexc("d6d0e0"), hexc("ffffff")
SEVEN = hexc("e8102a")
BULB_A, BULB_B = hexc("fff6c0"), hexc("ffd23a")

SQ = 3.4  # superellipse exponent of the cabinet cross-section (2 = round)


def squarish(a, z):
    """radius factor add that squares the cross-section low down and keeps the crown round."""
    f = (abs(math.cos(a)) ** SQ + abs(math.sin(a)) ** SQ) ** (-1 / SQ) - 1
    return f * smoothstep(3.0, 1.9, z) * 0.85


def paint(a, z, p):
    c = mix(RED_D, RED, smoothstep(0.1, 1.4, z))
    return mix(c, RED_L, 0.4 * smoothstep(2.0, 3.1, z))


BANDS = [(0.2, 0.4, G), (1.48, 1.62, GL)]
b = Body([(0, 1.15), (0.14, 1.4), (0.55, 1.48), (1.5, 1.46), (2.3, 1.28), (2.85, 0.8), (3.15, 0)],
         paint=paint, bump=squarish, bands=BANDS, segs=48, sub=3, gloss=1.0)
parts = [b.obj]
H = b.H


# ---------------------------------------------------------------- grid decal (from slime_abyss.py)
def pdecal(name, poly, color, frame=FRONT, off=0.02, th=0.025, on=("Body",), step=0.14, passes=1):
    poly = densify(poly, step)
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((u, v, 0)) for u, v in poly])
    bmesh.ops.triangulate(bm, faces=[f], quad_method="BEAUTY", ngon_method="BEAUTY")
    for _ in range(passes):
        bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
    nrm = {}
    for v in bm.verts:
        u, w = v.co.x, v.co.y
        o = frame.O + frame.U * u + frame.V * w + frame.D * 12
        hit = cast(o, -frame.D, list(on))
        if hit is None:
            raise ValueError(f"pdecal {name}: ({u:.2f}, {w:.2f}) misses")
        loc, n, _ = hit
        if n.dot(frame.D) < 0:
            n = -n
        n = (n * 0.6 + frame.D * 0.4).normalized()
        v.co = loc + n * off
        nrm[v] = n
    for fc in bm.faces:
        if fc.normal.dot(frame.D) < 0:
            fc.normal_flip()
    bm.normal_update()
    old = list(bm.verts)
    res = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces) + list(bm.edges) + list(bm.verts))
    new = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
    lookup = {tuple(round(c, 6) for c in v.co): nrm[v] for v in old}
    for v in new:
        v.co += lookup[tuple(round(c, 6) for c in v.co)] * th
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return separate(keep(o, False), frame, on, off=off)


def rrect(cu, cv, w, h, r, n=4):
    """rounded rectangle polygon."""
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(n + 1):
            a = math.radians(a0 + 90 * k / n)
            pts.append((cu + cx + math.cos(a) * r, cv + cy + math.sin(a) * r))
    return pts


# ---------------------------------------------------------------- belly window with three 7 reels
WV, WW, WH = 0.92, 2.05, 0.95  # window centre height, width, height
parts.append(pdecal("WinFrame", rrect(0, WV, WW + 0.22, WH + 0.22, 0.2), lambda p, n: mix(GD, GL, smoothstep(WV - 0.6, WV + 0.6, p.z)),
                    off=0.012, th=0.05, step=0.2, passes=0))
parts.append(pdecal("WinBg", rrect(0, WV, WW, WH, 0.12), WIN_BG, off=0.05, th=0.02, step=0.2, passes=0))
RW = 0.58
for k, u in enumerate((-0.66, 0.0, 0.66)):
    parts.append(pdecal(f"Reel{k}", rrect(u, WV, RW, WH - 0.12, 0.06),
                        lambda p, n: mix(REEL_D, REEL, 1 - abs(p.z - WV) / 0.42), off=0.06, th=0.02, step=0.16, passes=0))
    # a chunky "7": top bar + slanted stem
    s = 0.62
    seven = [(-0.2, 0.26), (0.2, 0.26), (0.2, 0.17), (0.02, -0.28), (-0.12, -0.28), (0.06, 0.15), (-0.2, 0.15)]
    parts.append(decal(f"Seven{k}", [(u + x * s / 0.5, WV + 0.01 + y * s / 0.55) for x, y in seven], SEVEN, FRONT,
                       off=0.085, th=0.02, on=["Body"], step=0.06))
for k in range(7):
    u = -0.9 + 0.3 * k
    hit = cast(Vector((u, -12, WV + WH / 2 + 0.11)), Vector((0, 1, 0)), ["Body"])
    parts.append(ball(f"WinBulb{k}", 0.085, hit[0] + Vector((0, -0.09, 0)), BULB_A if k % 2 else BULB_B, subdiv=1))
# divider bars between the reels and a red payline marker on each side
for k, u in enumerate((-0.33, 0.33)):
    parts.append(decal(f"WinBar{k}", rect(u, WV, 0.07, WH), GL, FRONT, off=0.06, th=0.03, on=["Body"], step=0.2))
for sd in (-1, 1):
    parts.append(decal(f"Payline{sd}", [(sd * (WW / 2 + 0.02), WV + 0.08), (sd * (WW / 2 + 0.02), WV - 0.08), (sd * (WW / 2 - 0.1), WV)],
                       SEVEN, FRONT, off=0.09, th=0.02, on=["Body"]))

# ---------------------------------------------------------------- face: star eyes, giddy open grin
EV, EU = 2.5, 0.55
for sd in (-1, 1):
    u = sd * EU
    parts.append(pdecal(f"Eye{sd}", star(u, EV, 0.39, 0.2), INK, off=0.015, th=0.02, step=0.12))
    parts.append(pdecal(f"EyeC{sd}", star(u, EV + 0.01, 0.285, 0.145), lambda p, n: mix(G, GW, smoothstep(EV - 0.2, EV + 0.3, p.z)),
                        off=0.035, th=0.012, step=0.12))
    parts.append(decal(f"EyeHi{sd}", oval(u - 0.07, EV + 0.09, 0.09, 0.09, n=8), WHITE, FRONT, off=0.055, th=0.01, on=["Body"]))
MV = 1.92
grin = half_oval(0, MV + 0.12, 0.92, 0.36, n=16)
parts.append(pdecal("Mouth", grin, MOUTH, off=0.015, th=0.02, step=0.1))
parts.append(pdecal("Teeth", [(-0.4, MV + 0.115), (0.4, MV + 0.115), (0.34, MV + 0.02), (-0.34, MV + 0.02)], WHITE, off=0.035, th=0.012, step=0.1))
parts.append(pdecal("Tongue", oval(0, MV - 0.12, 0.42, 0.14), TONGUE, off=0.035, th=0.012, step=0.1))
for sd in (-1, 1):
    parts.append(decal(f"Cheek{sd}", oval(sd * 0.98, 2.12, 0.3, 0.15, n=12), hexc("ff9ab0"), FRONT, off=0.012, th=0.015, on=["Body"]))

# ---------------------------------------------------------------- coin slot on the crown with a coin going in
parts.append(decal("Slot", rrect(0, 0.0, 0.62, 0.14, 0.05), hexc("1a0410"), TOP, off=0.012, th=0.03, on=["Body"]))
parts.append(decal("SlotRim", rrect(0, 0.0, 0.78, 0.28, 0.1), GL, TOP, off=0.006, th=0.03, on=["Body"]))
coin_col = lambda p, n: mix(G, GW, 0.15 + 0.6 * max(0.0, n.dot(Vector((-0.4, -0.6, 0.7)).normalized())))
parts.append(lathe("SlotCoin", [(0, 0), (0, 0.3), (0.09, 0.3), (0.09, 0)], coin_col, pos=(0, -0.045, H + 0.05), axis=(0, 1, 0), segs=18, smooth=False))

# ---------------------------------------------------------------- marquee bulbs round the head
MZ = 1.55
for k in range(18):
    a = k * math.tau / 18
    if abs(math.degrees(a) - 0) < 50 or abs(math.degrees(a) - 360) < 50:
        continue  # the window frame has its own bulbs
    p = b.point(a, MZ, 0.05)
    parts.append(ball(f"Bulb{k}", 0.12, p, BULB_A if k % 2 else BULB_B, subdiv=1))

# ---------------------------------------------------------------- lever on the right side (+X)
piv = b.point(math.radians(90), 1.35, -0.05)
parts.append(lathe("LeverBoss", [(0, 0.3), (0.2, 0.3), (0.32, 0.22), (0.38, 0)], lambda p, n: mix(CHROME_D, CHROME, 0.4 + 0.6 * max(0, n.z)),
                   pos=piv, axis=(1, 0, 0), segs=14))
rod = [piv + Vector((0.3, 0, 0)), piv + Vector((0.55, 0.05, 0.25)), piv + Vector((0.66, 0.12, 1.0)), piv + Vector((0.7, 0.16, 1.7))]
parts.append(horn("LeverRod", [tuple(q) for q in rod], [0.11, 0.1, 0.09, 0.085], CHROME_D, CHROME, segs=8))
knob = rod[-1] + Vector((0.02, 0.02, 0.28))
parts.append(ball("LeverKnob", 0.36, knob, lambda p, n: mix(RED, hexc("ffd0d0"), 0.85 * smoothstep(0.88, 0.99, n.dot(Vector((-0.45, -0.6, 0.65)).normalized())))
                  if True else RED, subdiv=3))

# ---------------------------------------------------------------- orbiting coins on a tilted ring + spill
OC = Vector((0, 0, 1.6))
tilt = math.radians(16)


def orbit(t, R=2.3):
    x, y = math.cos(t) * R, math.sin(t) * R * 0.85
    return OC + Vector((x, y * math.cos(tilt), y * math.sin(tilt) - x * 0.1))


def coin(name, pos, axis, r=0.32):
    return lathe(name, [(0, 0), (0, r), (0.09, r), (0.09, 0)], coin_col, pos=tuple(Vector(pos) - Vector(axis).normalized() * 0.04),
                 axis=axis, segs=16, smooth=False)


for k in range(8):
    t = k * math.tau / 8 + 0.35
    if abs(math.degrees(t) % 360 - 270) < 38:
        continue  # keep the window clear
    p = orbit(t)
    tang = (orbit(t + 0.01) - orbit(t - 0.01)).normalized()
    ax = (tang + Vector((0.25 * math.sin(k * 1.9), 0, 0.3 * math.cos(k * 2.3)))).normalized()
    parts.append(coin(f"Coin{k}", p, tuple(ax)))
# spill at the front-left foot: a stack and loose coins
for k, (x, y, z, ax) in enumerate([(-1.55, -1.05, 0.04, (0, 0, 1)), (-1.53, -1.07, 0.12, (0.05, 0, 1)), (-1.56, -1.03, 0.2, (-0.06, 0.03, 1)),
                                   (-1.54, -1.05, 0.28, (0.04, -0.05, 1)), (-1.05, -1.5, 0.12, (0.2, -1, 0.6)),
                                   (1.25, -1.35, 0.04, (0, 0, 1)), (1.6, -0.95, 0.1, (-0.3, -0.5, 1))]):
    parts.append(coin(f"Spill{k}", (x, y, z), ax))

# ---------------------------------------------------------------- payout: coins jumping out of the slot, a tray under the window
for k, (x, z, ax) in enumerate([(-0.3, H + 0.5, (0.5, -1, 0.5)), (-0.72, H + 0.85, (-0.2, -1, 0.35)), (-1.18, H + 0.9, (0.45, -1, -0.15)),
                                (-1.58, H + 0.66, (-0.35, -1, 0.4))]):
    parts.append(coin(f"Jump{k}", (x, -0.1 - 0.06 * k, z), ax, r=0.3 - 0.02 * k))
tz = 0.42
tp = b.point(0, tz, 0)
parts.append(slab("Tray", rrect(0, 0, 1.3, 0.42, 0.12), 0.14, (0, tp.y - 0.12, tz - 0.05), (1, 0, 0), (0, 1, 0),
                  lambda p, n: mix(GD, GL, 0.3 + 0.6 * max(0.0, n.z))))
parts.append(slab("TrayLip", rrect(0, 0, 1.3, 0.2, 0.06), 0.08, (0, tp.y - 0.33, tz + 0.04), (1, 0, 0), (0, 0, 1), GL))
for k, (x, ax) in enumerate([(-0.3, (0.2, -0.3, 1)), (0.22, (-0.1, 0.4, 1))]):
    parts.append(coin(f"TrayCoin{k}", (x, tp.y - 0.16, tz + 0.06 + 0.05 * k), ax, r=0.24))
# big gold star on the back
parts.append(pdecal("BackStar", star(0, 1.95, 0.62, 0.3), INK, frame=frame_at(180), off=0.012, th=0.02, step=0.14))
parts.append(pdecal("BackStarC", star(0, 1.96, 0.5, 0.24), lambda p, n: mix(G, GW, smoothstep(1.6, 2.4, p.z)), frame=frame_at(180), off=0.03, th=0.012, step=0.14))
# sparkles
for k, (x, y, z, sz) in enumerate([(-0.75, -0.6, 4.25, 0.2), (1.25, -0.9, 3.85, 0.18), (-2.05, -0.6, 2.6, 0.16)]):
    parts.append(slab(f"Glint{k}", star(0, 0, sz, sz * 0.28, n=4), 0.05, (x, y, z), (1, 0, 0), (0, 0, 1), GW))

if os.environ.get("TRI_DBG"):
    import collections
    cnt = collections.Counter()
    for o in parts:
        cnt[re.sub(r"[-0-9]+$", "", o.name)] += sum(len(pl.vertices) - 2 for pl in o.data.polygons)
    print("TRIS", sorted(cnt.items(), key=lambda x: -x[1]))
ship("slime_jackpot", parts)
