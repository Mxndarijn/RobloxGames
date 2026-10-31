# Jester (Legendary, Meadow): court-fool slime. Hot pink goo under a three-pointed harlequin hat
# (violet / teal / sunny lobes) with a gold jingle bell on every tip, a pointed collar of alternating
# flaps, painted diamonds under its eyes and a cheeky grin, juggling three tiny slimes over its head.
from models._slimepool import *

PINK, PINK_D, PINK_L = hexc("ff52b0"), hexc("e64a9c"), hexc("ffb8e0")
VIO, VIO_D, VIO_L = hexc("9a5aff"), hexc("8854ec"), hexc("c8a8ff")
TEAL, TEAL_D, TEAL_L = hexc("22dcc8"), hexc("30c0b2"), hexc("a0fff0")
SUN, SUN_D = hexc("ffd23a"), hexc("fab83a")
BELL_D, BELL, BELL_L = hexc("f8c44c"), hexc("ffd040"), hexc("fff2a8")
KEY = Vector((-0.4, -0.6, 0.7)).normalized()


def lit(c0, c1, c2=None):
    """dark facing away from the key light, c1 mid, optional c2 sheen facing it."""
    def fn(p, n):
        k = n.dot(KEY)
        c = mix(c0, c1, 0.45 + 0.55 * smoothstep(-0.6, 0.2, k))
        return mix(c, c2, smoothstep(0.55, 0.95, k)) if c2 else c
    return fn


def paint(a, z, p):
    c = mix(PINK_D, PINK, smoothstep(0.0, 1.2, z))
    return mix(c, PINK_L, 0.35 * smoothstep(0.7, 0.1, abs(a)) * smoothstep(1.3, 0.4, z))


b = Body([(0, 1.1), (0.14, 1.36), (0.5, 1.5), (1.1, 1.48), (1.8, 1.28), (2.4, 0.95), (2.78, 0.5), (2.9, 0)],
         paint=paint, segs=28, sub=2)
parts = [b.obj]
H = b.H

# ---- harlequin cap: dome over the head, left half violet, right half teal, gold band with diamonds
HZ = 2.08
prof = [(HZ - 0.04, b.radius(HZ) + 0.08)]
for k in range(1, 7):
    z = HZ + (H - HZ) * k / 7
    prof.append((z, b.radius(z) + 0.09))
prof.append((H + 0.09, 0))


def cap_col(p, n):
    base = (VIO_D, VIO, VIO_L) if p.x < 0 else (TEAL_D, TEAL, TEAL_L)
    return lit(*base)(p, n)


cap = lathe("Cap", prof, cap_col, segs=24)
parts.append(register(cap, "Cap"))
band = lathe("HatBand", [(0, b.radius(HZ) + 0.13), (0.24, b.radius(HZ + 0.24) + 0.13)], lit(SUN_D, SUN, hexc("fff0a0")),
             pos=(0, 0, HZ - 0.1), segs=28)
parts.append(register(band, "HatBand"))
for k, yaw in enumerate((-60, -30, 0, 30, 60)):
    fr = frame_at(yaw, HZ + 0.02)
    c = VIO if k % 2 == 0 else TEAL
    parts.append(decal(f"Diamond{k}", [(0, 0.11), (0.08, 0), (0, -0.11), (-0.08, 0)], c, fr, off=0.01, th=0.03, on=["HatBand"]))

# ---- three floppy lobes (Ribbon* so the rig sways them), each with a gold bell
def bell(name, tip, down):
    d = Vector(down).normalized()
    return [ball(f"{name}", 0.2, tuple(tip + d * 0.16), lit(BELL_D, BELL, BELL_L), subdiv=2),
            torus(f"{name}Rim", 0.15, 0.04, tuple(tip + d * 0.05), tuple(d), BELL_D, segs=10, rsegs=3)]


LOBES = [  # name, points, colour ramp, bell hang direction
    ("RibbonL", [(-0.3, 0.0, H - 0.1), (-0.8, 0.0, H + 0.3), (-1.3, 0.0, H + 0.62), (-1.75, -0.05, H + 0.72), (-2.0, -0.1, H + 0.5)],
     (VIO_D, VIO, VIO_L)),
    ("RibbonR", [(0.3, 0.0, H - 0.1), (0.8, 0.0, H + 0.3), (1.3, 0.0, H + 0.62), (1.75, -0.05, H + 0.72), (2.0, -0.1, H + 0.5)],
     (TEAL_D, TEAL, TEAL_L)),
    ("RibbonC", [(0.0, 0.25, H - 0.05), (0.0, 0.45, H + 0.55), (0.0, 0.85, H + 0.95), (0.0, 1.35, H + 0.85), (0.0, 1.6, H + 0.45)],
     (SUN_D, SUN, hexc("fff0a0"))),
]
for name, pts, (c0, c1, c2) in LOBES:
    radii = [0.42, 0.34, 0.24, 0.15, 0.09]
    parts.append(keep(paint_fn(tube(name, pts, radii, None, segs=10), lit(c0, c1, c2)), True))
    tip = Vector(pts[-1])
    dn = (tip - Vector(pts[-2])).normalized()
    dn = (dn + Vector((0, 0, -1))).normalized()
    parts += bell(name + "Bell", tip, dn)

# ---- pointed collar around the base: alternating flaps pointing down and out
ZC = 0.58
NF = 10
for k in range(NF):
    a = math.radians(k * 360 / NF)
    p = b.point(a, ZC, 0.04)
    out = Vector((math.sin(a), -math.cos(a), 0))
    side = Vector((math.cos(a), math.sin(a), 0))
    down = (Vector((0, 0, -1)) + out * 1.1).normalized()
    poly = [(-0.36, 0.0), (0.36, 0.0), (0.0, 0.5)]
    c = VIO if k % 2 == 0 else TEAL
    parts.append(puffy_slab(f"Flap{k}", poly, 0.08, tuple(p + Vector((0, 0, 0.12))), tuple(side), tuple(down),
                            along(shade(c, 0.85), c, p + down * 0.6, p), rows=1))
parts.append(torus("CollarRim", b.radius(ZC + 0.12) + 0.06, 0.07, (0, 0, ZC + 0.12), (0, 0, 1), SUN, segs=24, rsegs=4))

# ---- face: big bright eyes, painted diamonds under them, a wide cheeky grin
f = Face(b, eye_v=1.58, eye_u=0.5, mouth_v=1.1)
f.eyes("round", w=0.5, h=0.66, iris=hexc("2fb8ff"))
for sd in (-1, 1):
    c = VIO if sd < 0 else TEAL
    f.d(f"FacePaint{sd}", [(sd * 0.5, 1.23), (sd * 0.5 + 0.09, 1.11), (sd * 0.5, 0.98), (sd * 0.5 - 0.09, 1.11)], c, off=0.015, th=0.02)
f.mouth("grin", w=1.3, v=1.02)
f.cheeks(color=hexc("ff8ac8"), w=0.24, h=0.11, u=0.92, v=1.2)
parts += f.parts

# ---- goo hands raised at the sides
HANDS = [Vector((-1.8, -0.6, 1.2)), Vector((1.8, -0.6, 1.2))]
for k, hc in enumerate(HANDS):
    sd = -1 if hc.x < 0 else 1
    parts.append(goo(f"Hand{k}", [((sd * 1.3, -0.3, 1.2), 0.26), ((sd * 1.55, -0.45, 1.18), 0.2), (tuple(hc), 0.22, (1.05, 1.0, 0.75))],
                     lambda p, n: mix(PINK_D, PINK, smoothstep(0.9, 1.4, p.z)), tris=120, resolution=0.08))

# ---- three juggled mini slimes in an arc over the head (their face decals reuse the names Eye-1 etc.:
# keep the main face's PAINTED_ON entries so the rig's blink lids land on the big body)
main_painted = dict(PAINTED_ON)
MINIS = [(-2.0, -0.7, 2.05, hexc("ffd23a"), hexc("fff4b0")), (0.0, -0.9, 4.35, hexc("4ae0ff"), hexc("d6f8ff")),
         (2.0, -0.7, 2.05, hexc("7ae04a"), hexc("e0ffc8"))]
for k, (x, y, z, c0, c1) in enumerate(MINIS):
    name = f"Mini{k}"
    mb = Body([(zz * 1.25, r * 1.25) for zz, r in [(0, 0.36), (0.08, 0.44), (0.3, 0.47), (0.52, 0.42), (0.66, 0.32), (0.75, 0.18), (0.78, 0)]],
              paint=lambda a, zz, p, c0=c0, c1=c1: mix(c0, c1, smoothstep(0.1, 0.8, zz)), segs=12, sub=1, gloss=0.8, name=name, tuck=0.15, dome=0)
    mf = Face(mb, eye_u=0.2, eye_v=0.55, mouth_v=0.38, s=0.52)
    mf.eyes("dot", w=0.5)
    mf.mouth("open" if k == 1 else "smile", w=1.1)
    group = [mb.obj] + mf.parts
    spin = (-0.35, 0.0, 0.35)[k]
    T = Matrix.Translation((x, y, z)) @ Matrix.Rotation(spin, 4, "Y") @ Matrix.Translation((0, 0, -0.5))
    for o in group:
        o.data.transform(T)
        o.name = o.name if o.name.startswith(name) else f"{name}{o.name}"
    parts += group
PAINTED_ON.update(main_painted)

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_jester", parts)
