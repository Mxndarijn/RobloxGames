# Nightwing (hybrid, tier 7: seraph + imp + eclipse): a fallen angel goo split down the middle.
# Viewer's left half is pearly seraph white with a feathered wing and one sweet sparkly eye; the
# right half is eclipse void (stars, hot pink rim glow) with a bat wing, an imp horn, an arrow tail
# and one glowing eye. Above it floats a tilted, cracked gold halo whose broken piece drifts off.
from models._slimepool import *

PEARL, PINK, BLUE, LAV = hexc("fbf6ff"), hexc("ffd6ec"), hexc("cfe6ff"), hexc("e6d6ff")
FEATH, FEATH_D = hexc("ffffff"), hexc("d6d6f2")
HALO, HALO_L, HALO_K = hexc("ffd24a"), hexc("fff6b8"), hexc("6a3a8a")
VOID, VOID_M = hexc("0c0620"), hexc("2a1252")
RIM, RIM_H = hexc("ff3fb4"), hexc("ffb3f0")
HORN_D, HORN_L = hexc("120a1c"), hexc("4a3060")
EYE_G = hexc("ffe6fb")

H = 3.1


def seam(z):
    """yaw of the split (radians, + = viewer's right): a jagged crack wandering down the front."""
    return 0.0  # straight split on a vertex column; the jagged crack is a glowing decal on top


def is_void(a, z):
    if abs(a) < math.pi / 2:
        return a > seam(z)
    return a > 0  # back: straight split


def pearl(a, z, p):
    c = mix(LAV, PEARL, smoothstep(0.0, 1.6, z))
    n1 = noise.noise(Vector((p.x * 0.9, p.y * 0.9, p.z * 0.9 + 7.0)))
    n2 = noise.noise(Vector((p.x * 0.8 + 3.1, p.y * 0.8, p.z * 0.8)))
    c = mix(c, PINK, 0.45 * smoothstep(0.05, 0.45, n1))
    return mix(c, BLUE, 0.45 * smoothstep(0.1, 0.5, n2))


def void(a, z):
    ad = abs(math.degrees(a))
    c = mix(VOID, VOID_M, smoothstep(0.3, 2.6, z))
    side = smoothstep(55, 88, ad) * smoothstep(140, 108, ad) * smoothstep(2.9, 2.2, z)
    c = mix(c, RIM, 0.85 * side)
    c = mix(c, RIM_H, 0.4 * smoothstep(78, 92, ad) * smoothstep(106, 92, ad) * smoothstep(2.6, 2.0, z))
    return mix(c, RIM, 0.75 * smoothstep(0.35, 0.0, z))


class SplitBody(Body):
    """Body whose faces pick a side by their centre (crisp jagged seam) but are painted per corner
    with that side's smooth gradient (lib sectors() would paint each face one flat colour)."""

    def _paint(self, bm):
        col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
        for f in bm.faces:
            cz = f.calc_center_median()
            ca = math.atan2(cz.x / self.sx, -(cz.y - self.lean(cz.z)) / self.sy)
            band = any(z0 <= cz.z <= z1 for z0, z1, _ in self.bands)
            dark = is_void(ca, cz.z)
            for lp in f.loops:
                p = lp.vert.co
                a = math.atan2(p.x / self.sx, -(p.y - self.lean(p.z)) / self.sy) if (abs(p.x) + abs(p.y)) > 1e-6 else ca
                if band:
                    c = GOLD
                elif dark:
                    if a < 0 and abs(a) < math.pi / 2:
                        a = 0.0  # seam corners: keep the void gradient continuous
                    c = void(a, p.z)
                else:
                    c = pearl(a, p.z, p)
                lp[col] = self.lit(c, p)


b = SplitBody([(0, 1.02), (0.12, 1.3), (0.5, 1.47), (1.1, 1.45), (1.8, 1.23), (2.45, 0.85), (2.88, 0.4), (H, 0)],
         paint=pearl, segs=48, sub=2, bands=[(0.13, 0.26, GOLD)],
         lean=lambda z: 0.12 * max(0.0, (z - 2.3) / 0.8) ** 2, gloss=0.8)
parts = [b.obj]


# ---- feathered wing on the pearl side (seraph), bat wing on the void side (imp)
def feather_poly(L, w, n=5):
    top = []
    for k in range(n + 1):
        t = k / n
        x = t * L
        if t < 0.7:
            y = w / 2 * (0.45 + 0.55 * math.sin(math.pi / 2 * t / 0.7))
        else:
            q = (t - 0.7) / 0.3
            y = w / 2 * math.sqrt(max(0.0, 1 - q * q))
        top.append((x, y))
    bot = [(x, -y) for x, y in reversed(top[1:-1])]
    return top + bot


def feather_wing(sd):
    out = []
    root = b.point(math.radians(sd * 112), 1.75, -0.15)
    e_out = Vector((sd * 0.95, 0.32, 0)).normalized()
    e_up = Vector((0, 0.18, 1)).normalized()
    N = e_out.cross(e_up).normalized()

    def dirv(deg):
        th = math.radians(deg)
        return e_out * math.cos(th) + e_up * math.sin(th)
    arm = dirv(50)
    n = 7
    for i in range(n):
        t = i / (n - 1)
        o = root + arm * (0.1 + 1.0 * t) + N * (0.03 * i * sd)
        d = dirv(-70 + 98 * t)
        L = 0.8 + 0.78 * t ** 0.8
        y = d.cross(N).normalized()
        col = along(FEATH_D, mix(FEATH, HALO_L, 0.7), o, o + d * L, power=1.8)
        out.append(puffy_slab(f"WingPrim{sd}{i}", feather_poly(L, 0.52), 0.1, tuple(o), tuple(d), tuple(y), col, rows=2))
    for i in range(4):
        t = i / 3
        o = root + arm * (0.05 + 0.85 * t) - N * (0.12 * sd) + N * (0.025 * i * sd)
        d = dirv(-45 + 85 * t)
        L = 0.6 + 0.25 * t
        y = d.cross(N).normalized()
        out.append(puffy_slab(f"WingCov{sd}{i}", feather_poly(L, 0.52), 0.12, tuple(o), tuple(d), tuple(y), along(FEATH_D, FEATH, o, o + d * L), rows=2))
    arm_pts = [tuple(root + arm * (1.12 * k / 4) + e_up * 0.06 * math.sin(k / 4 * math.pi) - N * 0.06 * sd) for k in range(5)]
    out.append(horn(f"WingArm{sd}", arm_pts, [0.2, 0.18, 0.15, 0.12, 0.09], FEATH, FEATH, segs=8))
    return out


parts += feather_wing(-1)

sd = 1
wing = [(0, 0), (0.65, 0.55), (1.3, 1.05), (2.0, 1.5), (1.95, 0.65), (1.62, 0.08), (1.28, 0.45), (0.95, -0.22),
        (0.6, 0.12), (0.25, -0.38)]
O, X, Y = Vector((sd * 0.75, 0.9, 1.72)), Vector((sd * 0.95, 0.26, 0.15)).normalized(), Vector((0, -0.1, 1)).normalized()
wing = [(x * 1.2, y * 1.2) for x, y in wing]
parts.append(slab("WingBat1", wing, 0.08, O, X, Y, along(VOID, hexc("4a1a6a"), O, O + X * 2.0 + Y * 1.0, power=0.8)))
for j, (x, y) in enumerate(((2.4, 1.8), (1.94, 0.1), (1.14, -0.26))):
    parts.append(horn(f"WingBone1{j}", [O + X * 0.05, O + X * x * 0.55 + Y * y * 0.6, O + X * x + Y * y],
                      [0.08, 0.055, 0.03], RIM, RIM_H, segs=6))
parts.append(lathe("WingClaw1", [(0, 0.06), (0.2, 0)], RIM_H, pos=tuple(O + X * 2.4 + Y * 1.8), axis=tuple(X * 0.3 + Y), segs=5))

# ---- imp horn on the void side of the head
root = b.point(math.radians(36), 2.32, -0.1)
pts = [root, root + Vector((0.26, -0.02, 0.32)), root + Vector((0.42, 0.0, 0.68)), root + Vector((0.35, 0.05, 0.98)),
       root + Vector((0.17, 0.06, 1.12))]
parts.append(horn("Horn1", pts, [0.22, 0.17, 0.12, 0.065, 0.015], HORN_L, HORN_D, segs=10))

# ---- arrow tail out of the void side of the back
tail = [(0.25, 1.3, 0.4), (0.45, 1.8, 0.35), (0.75, 2.12, 0.6), (0.9, 2.2, 1.0), (0.8, 2.05, 1.32)]
parts.append(horn("Tail", tail, [0.16, 0.12, 0.095, 0.08, 0.065], VOID, VOID_M, segs=8))
tip = Vector(tail[-1])
parts.append(slab("TailArrow", [(0, 0.4), (0.3, -0.05), (0.08, 0.0), (0.0, -0.12), (-0.08, 0.0), (-0.3, -0.05)], 0.1,
                  tip + Vector((0, 0, -0.05)), (1, 0.4, 0), (-0.15, 0.3, 1), RIM))

# ---- cracked tilted halo: two gold arcs with a gap, the broken piece drifting off and down
HC = Vector((0, 0.18, H + 0.6))
tilt = math.radians(-27)  # dips to the void side
HN = Vector((math.sin(tilt), 0.2, math.cos(tilt))).normalized()
HU = Vector((1, 0, 0)) - HN * HN.x
HU.normalize()
HV = HN.cross(HU).normalized()


def halo_pt(deg, R=0.74, shift=Vector()):
    a = math.radians(deg)
    return tuple(HC + shift + HU * math.cos(a) * R + HV * math.sin(a) * R)


def halo_col(p, n):
    # gold on the pearl side, tarnishing into violet black towards the void side
    t = smoothstep(-0.2, 0.75, p.x)
    return mix(mix(HALO, HALO_L, 0.5 + 0.4 * max(0.0, n.z)), HALO_K, t)


arc_a = [halo_pt(d) for d in range(36, 325, 12)]  # main arc (the gap is at the void side, deg 0)
parts.append(horn("Halo", arc_a, [0.085] * len(arc_a), HALO, HALO, segs=6))
paint_fn(parts[-1], halo_col)
shift = Vector((0.3, -0.08, -0.28))
arc_b = [halo_pt(d, shift=shift) for d in (-16, -6, 4, 14)]  # the broken piece
parts.append(horn("HaloShard", arc_b, [0.085] * 4, HALO_K, HALO_K, segs=6))
paint_fn(parts[-1], halo_col)
for k, (d, dz, r) in enumerate(((22, -0.38, 0.05), (-22, -0.5, 0.04))):  # crumbs falling from the crack
    q = Vector(halo_pt(d)) + Vector((0.1, 0, dz))
    parts.append(gem(f"Crumb{k}", tuple(q), r, HALO if k else HALO_K, segs=4))
parts.append(torus("HaloGlow", 0.92, 0.03, tuple(HC), tuple(HN), mix(HALO_L, WHITE, 0.4), segs=24, rsegs=3))

# ---- glowing crack along the split (zig-zag segments hugging the body), above and below the mouth
def crack(name, z0, z1, n, amp=0.07, w=0.06):
    pts = [((amp if k % 2 else -amp) * (0.4 if k in (0, n) else 1.0), z0 + (z1 - z0) * k / n) for k in range(n + 1)]
    for i in range(n):
        a, c = Vector(pts[i]), Vector(pts[i + 1])
        m = (a + c) / 2
        parts.append(decal(f"{name}{i}", rect(m.x, m.y, w, (c - a).length + w * 0.9, math.atan2(c.y - a.y, c.x - a.x) - math.pi / 2),
                           RIM_H, FRONT, off=0.014, th=0.012, on=["Body"], step=0.3))


crack("Crack", 2.98, 2.1, 5)
crack("CrackB", 0.82, 0.3, 3)

# ---- eclipse touches on the void half: stars, two tiny orbiting planets
stars = [(40, 0.6, 0.08), (55, 2.15, 0.07), (75, 1.2, 0.06), (120, 1.6, 0.09), (150, 0.8, 0.07), (165, 2.2, 0.08),
         (100, 2.45, 0.06), (30, 2.55, 0.05)]
for k, (yaw, z, s) in enumerate(stars):
    parts.append(decal(f"Star{k}", star(0, 0, s, s * 0.35, n=4), WHITE, frame_at(yaw, z), off=0.012, th=0.012, on=["Body"]))
for k, (p, r, c) in enumerate([((1.95, -0.3, 2.5), 0.17, hexc("57e8ff"))]):
    parts.append(ball(f"Orb{k}", r, p, lambda q, n, c=c: mix(c, WHITE, 0.55 * max(0.0, n.dot(Vector((-0.4, -0.6, 0.7)).normalized())))))
parts.append(torus("OrbRing", 0.27, 0.03, (1.95, -0.3, 2.5), (0.3, -0.3, 1), hexc("c9fbff"), segs=16, rsegs=3))

# ---- face: one sweet sparkly eye (pearl side), one glowing eye (void side), half smile / half fang
EV, EU = 1.6, 0.5
f = Face(b, eye_v=EV, eye_u=EU, mouth_v=1.12)
f._eye_round(-1, 0.58, 0.76, iris=hexc("6ab8ff"))
f.d("EyeHi3-1", star(-EU + 0.1, EV + 0.2, 0.08, 0.035, n=4), WHITE, off=0.055, th=0.01)
for j, (aa, ln) in enumerate(((150, 0.13), (130, 0.11))):  # lashes on the outer corner
    r = math.radians(aa)
    x0, y0 = -EU + math.cos(r) * 0.33, EV + math.sin(r) * 0.4
    f.d(f"Lash-1{j}", rect(x0 + math.cos(r) * 0.05, y0 + math.sin(r) * 0.05, 0.04, ln, r + math.pi / 2), INK)
f.d("EyeRim1", oval(EU, EV, 0.66, 0.66, n=16), RIM, off=0.012, th=0.01)
gl = oval(EU, EV, 0.54, 0.54, n=16)
gl = [(x, min(y, EV + 0.1 + (x - EU) * 0.5)) for x, y in gl]  # slanted top: a wicked glow
f.d("Eye1", gl, EYE_G, off=0.025)
f.d("EyePupil1", oval(EU + 0.02, EV - 0.04, 0.09, 0.26, n=10), RIM, off=0.04, th=0.01)
f.d("Brow1", rect(EU, EV + 0.42, 0.36, 0.08, math.radians(20)), RIM, off=0.02)
mv = 1.12
f.d("Mouth-1", arc(-0.02, mv + 0.16, 0.27, 212, 278, 0.08, n=8), INK)  # sweet half smile
f.d("Mouth1", arc(0.02, mv + 0.16, 0.27, 266, 338, 0.08, n=8), RIM)  # glowing half grin
f.d("Fang1", [(0.12, mv - 0.1), (0.25, mv - 0.06), (0.2, mv - 0.24)], WHITE, off=0.04, th=0.02)
f.d("Cheek-1", oval(-EU - 0.36, EV - 0.32, 0.3, 0.15, n=12), hexc("ffa6c8"), off=0.012, th=0.015)
parts += f.parts

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_nightwing", parts)
