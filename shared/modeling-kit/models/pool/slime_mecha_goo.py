# Mecha Goo (Boss): giant mech slime. A top-heavy chrome armour shell with big shoulder pauldrons
# carrying forward-pointing cannons, a red glowing visor with angry eye slits, yellow/black warning
# stripes round the hips, stomping mech feet, green goo oozing out of the seams, and a glass
# cockpit dome on top with a tiny goggled slime pilot giving a thumbs-up grin.
from models._slimepool import *


def shell(name, fn, nu, nv, thick, color):
    """closed thick sheet: fn(s, t) -> point (s, t in 0..1); offset along the sheet normal both ways."""
    bm = bmesh.new()
    P = [[Vector(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]

    def nrm(i, j):
        a = P[min(i + 1, nu)][j] - P[max(i - 1, 0)][j]
        b = P[i][min(j + 1, nv)] - P[i][max(j - 1, 0)]
        return a.cross(b).normalized()
    outer = [[bm.verts.new(P[i][j] + nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    inner = [[bm.verts.new(P[i][j] - nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu + 1)]
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]))
            bm.faces.new((inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j], inner[i][j]))
    for i in range(nu):
        for j in (0, nv):
            bm.faces.new((outer[i][j], inner[i][j], inner[i + 1][j], outer[i + 1][j]))
    for j in range(nv):
        for i in (0, nu):
            bm.faces.new((outer[i][j], outer[i][j + 1], inner[i][j + 1], inner[i][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True)


def proj_sheet(name, half_w, v0, v1, nu, nv, off, th, color, on=("Body",)):
    """big front decal with interior verts (from slime_robo.py): a grid projected along -Y."""
    def fn(s, t):
        t = 0.5 - 0.5 * math.cos(math.pi * t)
        v = v0 + (v1 - v0) * t
        hw = half_w(v)
        u = -hw + 2 * hw * s
        hit = cast(Vector((u, -12, v)), Vector((0, 1, 0)), list(on))
        if hit is None:
            raise ValueError(f"{name}: ({u:.2f}, {v:.2f}) misses")
        loc, n, _ = hit
        if n.y > 0:
            n = -n
        return tuple(loc + n * (off + th / 2))
    return shell(name, fn, nu, nv, th, color)


def ramp(stops, t):
    t = min(1.0, max(0.0, t))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return mix(c0, c1, smoothstep(t0, t1, t))
    return stops[-1][1]


CHROME = [(0.0, hexc("3c4258")), (0.2, hexc("8e9ab4")), (0.4, hexc("eef2fa")), (0.5, hexc("4a5672")),
          (0.66, hexc("7486a8")), (0.85, hexc("e2e9f6")), (1.0, hexc("ffffff"))]
RED, RED_D, RED_L = hexc("ff2a36"), hexc("a8101c"), hexc("ffb0a8")
HAZ_Y, HAZ_K = hexc("ffcc1a"), hexc("22202a")
GOO, GOO_L, GOO_D = hexc("6cff4a"), hexc("d4ffb0"), hexc("2eb83a")
GLASS, GLASS_L = hexc("bff4ff"), hexc("ffffff")
GUN, GUN_D = hexc("4a5068"), hexc("262a38")

H = 2.55


def boxy(a, z):  # rounded-square cross-section
    n = 3.2
    return 1.0 / (abs(math.cos(a)) ** n + abs(math.sin(a)) ** n) ** (1 / n) - 1.0


def paint(a, z, p):
    c = ramp(CHROME, z / H)
    return mix(c, hexc("8a9cc8"), 0.2 * (0.5 + 0.5 * math.sin(a * 2 + 0.6)))


def hazard(a, z):
    if 0.32 <= z <= 0.66:
        k = math.floor((a / math.tau) * 16 + z * 4.0)
        return HAZ_Y if k % 2 == 0 else HAZ_K
    return None


# top-heavy torso: narrow hips, wide chest, flat-ish top where the cockpit sits
b = Body([(0, 1.08), (0.12, 1.22), (0.5, 1.28), (1.1, 1.45), (1.7, 1.62), (2.15, 1.6), (2.42, 1.3), (H, 0.9), (H + 0.02, 0)],
         paint=paint, segs=48, sub=1, bump=lambda a, z: boxy(a, z) * 0.6, sectors=hazard,
         bands=[(0.27, 0.32, HAZ_K), (0.66, 0.71, HAZ_K), (0.405, 0.49, None), (0.575, 0.576, None)], gloss=1.0, shade=0.55)
parts = [b.obj]

# ---- visor: dark band with angry red eye slits + scan glow
VV0, VV1 = 1.55, 2.12


def visor_w(v):
    t = (v - VV0) / (VV1 - VV0)
    return 1.12 + 0.06 * t


parts.append(proj_sheet("VisorRim", lambda v: visor_w(v) + 0.07, VV0 - 0.07, VV1 + 0.07, 10, 4, 0.01, 0.03, GUN))
visor = proj_sheet("Visor", visor_w, VV0, VV1, 12, 5, 0.04, 0.02,
                   lambda p, n: mix(hexc("140c18"), hexc("3a1a2a"), smoothstep(VV0, VV1, p.z)))
parts.append(register(visor, "Visor"))


def vd(name, poly, color, off):
    parts.append(decal(name, poly, color, FRONT, off=off, th=0.01, on=["Visor"]))


EV = 1.83
for sd in (-1, 1):
    u = sd * 0.5
    # angry slanted slit: inner end lower
    sl = [(u - sd * 0.28, EV - 0.02), (u + sd * 0.26, EV + 0.13), (u + sd * 0.24, EV - 0.06), (u - sd * 0.26, EV - 0.14)]
    if sd < 0:
        sl = list(reversed(sl))
    glow = [(u + (x - u) * 1.25, EV + (y - EV) * 1.6) for x, y in sl]
    vd(f"EyeGlow{sd}", glow, RED_D, 0.01)
    vd(f"Eye{sd}", sl, RED, 0.02)
    core = [(u + (x - u) * 0.6, EV + (y - EV) * 0.45 + 0.0) for x, y in sl]
    vd(f"EyeCore{sd}", core, RED_L, 0.03)
vd("Glint", [(-0.95, 2.05), (-0.78, 2.05), (-0.98, 1.62), (-1.06, 1.7)], hexc("5a3a52"), 0.015)

# mouth grille under the visor: a grumpy vent
for k in range(5):
    parts.append(decal(f"Grille{k}", rect(0, 1.32 - k * 0.0, 0.62 - 0.0 * k, 0.05) if False else rect((k - 2) * 0.16, 1.26, 0.08, 0.26),
                       GUN_D, FRONT, off=0.015, th=0.02, on=["Body"]))
parts.append(decal("GrilleFrame", rect(0, 1.26, 0.92, 0.42), GUN, FRONT, off=0.006, th=0.012, on=["Body"]))

# ---- shoulder pauldrons with forward cannons
for sd in (-1, 1):
    sp = Vector((sd * 1.62, 0.05, 2.05))
    parts.append(ball(f"Pauldron{sd}", 0.6, tuple(sp), lambda p, n: mix(RED_D, RED, smoothstep(-0.3, 0.8, n.z)) if n.z < 0.55 else mix(RED, RED_L, 0.35),
                      squash=(1.0, 1.1, 0.78)))
    parts.append(torus(f"PauldronRim{sd}", 0.56, 0.06, tuple(sp + Vector((0, 0, -0.18))), (0, 0, 1), hexc("dfe6f2"), segs=16, rsegs=4))
    # stripes on the pauldron
    for j in (-1, 1):
        parts.append(ball(f"PStud{sd}{j}", 0.07, tuple(sp + Vector((sd * 0.25, j * 0.3, 0.4))), hexc("f0f4fa"), subdiv=1))
    # cannon on top of the pauldron, pointing forward
    cb = sp + Vector((sd * 0.08, 0.35, 0.5))
    parts.append(lathe(f"CannonBody{sd}", [(0, 0.3), (0.55, 0.3), (0.68, 0.25)], lambda p, n: mix(GUN_D, hexc("8a94ac"), smoothstep(-0.4, 0.9, n.z)),
                       pos=tuple(cb), axis=(0, -1, 0), segs=12))
    parts.append(lathe(f"Barrel{sd}", [(0.5, 0.2), (1.55, 0.18), (1.62, 0.25), (1.85, 0.25), (1.85, 0.15), (1.72, 0.14), (1.72, 0)],
                       lambda p, n: mix(hexc("6a7490"), hexc("e8eef8"), smoothstep(-0.3, 1.0, n.z)), pos=tuple(cb), axis=(0, -1, 0), segs=12))
    parts.append(ball(f"Muzzle{sd}", 0.14, tuple(cb + Vector((0, -1.72, 0))), hexc("ffe14a"), squash=(1, 0.4, 1), subdiv=1))
    parts.append(torus(f"BarrelRing{sd}", 0.21, 0.045, tuple(cb + Vector((0, -0.9, 0))), (0, 1, 0), HAZ_Y, segs=12, rsegs=4))
    parts.append(lathe(f"CannonCap{sd}", [(0, 0.3), (0.08, 0.24), (0.14, 0)], GUN, pos=tuple(cb + Vector((0, 0.0, 0))), axis=(0, 1, 0), segs=12))

# ---- stomping mech feet
for sd in (-1, 1):
    fp = Vector((sd * 0.74, -0.55, 0))
    parts.append(lathe(f"Foot{sd}", [(0, 0.55), (0.22, 0.57), (0.36, 0.48), (0.42, 0)], lambda p, n: mix(GUN_D, hexc("9aa6bc"), smoothstep(0.0, 0.4, p.z)),
                       pos=tuple(fp), segs=8, sx=1.0, sy=1.45, spin=math.pi / 8, smooth=False))
    parts.append(box(f"Toe{sd}", (0.78, 0.18, 0.18), tuple(fp + Vector((0, -0.8, 0.09))), HAZ_Y))

# ---- goo oozing through the armour: bulges at the seams + a drip from each side
balls = []
for sd in (-1, 1):
    for yaw, z, r, sc in ((32, 0.76, 0.2, (1.4, 0.6, 0.7)), (36, 0.6, 0.12, (1, 0.8, 1.2)), (37, 0.44, 0.1, (1, 0.8, 1.1)), (37, 0.33, 0.12, (1, 0.9, 1)),
                          (115, 0.76, 0.18, (1.3, 0.6, 0.7)), (118, 0.58, 0.1, (1, 0.8, 1.2)), (118, 0.47, 0.11, (1, 0.9, 1))):
        q = b.point(math.radians(sd * yaw), z, 0.02)
        balls.append((tuple(q), r, sc))
parts.append(goo("GooSeams", balls, lambda p, n: mix(GOO_D, GOO_L, smoothstep(-0.2, 0.9, n.z)), tris=280, resolution=0.05))
# back thrusters with a glowing exhaust
for sd in (-1, 1):
    tp = b.point(math.radians(180 - sd * 28), 1.55, -0.1)
    parts.append(lathe(f"Thruster{sd}", [(0, 0.22), (0.35, 0.24), (0.5, 0.3), (0.5, 0.2)], lambda p, n: mix(GUN_D, hexc("9aa6bc"), smoothstep(-0.3, 1, n.z)),
                       pos=tuple(tp), axis=(0, 0.6, -1), segs=10))
    parts.append(lathe(f"Flame{sd}", [(0.46, 0.2), (0.65, 0.13), (0.9, 0)], lambda p, n, tp=tp: mix(hexc("ffe26a"), hexc("ff6a2a"), smoothstep(tp.z - 0.3, tp.z - 0.75, p.z)),
                       pos=tuple(tp), axis=(0, 0.6, -1), segs=10))

# ---- cockpit: chrome base ring, goo pool, tiny pilot slime, glass suggested by glints + a thin rim
CZ = H - 0.02
parts.append(torus("DomeRing", 0.92, 0.11, (0, 0, CZ + 0.02), (0, 0, 1), lambda p, n: mix(hexc("8a96b0"), WHITE, smoothstep(-0.2, 1, n.z)), segs=28, rsegs=5))
parts.append(lathe("GooPool", [(0, 0.88), (0.08, 0.86), (0.12, 0)], GOO, pos=(0, 0, CZ - 0.02), segs=24))
pilot = lathe("Pilot", [(0, 0.38), (0.05, 0.44), (0.25, 0.46), (0.48, 0.36), (0.66, 0.16), (0.72, 0)], lambda p, n: mix(GOO_D, GOO, smoothstep(CZ, CZ + 0.5, p.z)),
              pos=(0, 0, CZ + 0.06), segs=16, sub=1)
parts.append(register(pilot, "Pilot"))
PV = CZ + 0.4


def pd(name, poly, color, off=0.015, th=0.012):
    parts.append(decal(name, poly, color, FRONT, off=off, th=th, on=["Pilot"]))


# pilot goggles on the forehead strap + big grin
parts.append(torus("Strap", 0.3, 0.04, (0, 0, PV + 0.2), (0, 0, 1), hexc("6a3a20"), segs=14, rsegs=4))
for sd in (-1, 1):
    pd(f"Eye{sd}", oval(sd * 0.15, PV - 0.01, 0.13, 0.17, n=10), INK)
    pd(f"EyeHi{sd}", oval(sd * 0.15 - 0.025, PV + 0.03, 0.05, 0.05, n=6), WHITE, off=0.03, th=0.006)
    parts.append(torus(f"Goggle{sd}", 0.09, 0.03, (sd * 0.13, -0.25, PV + 0.25), (0, -0.6, 1), hexc("c8a040"), segs=8, rsegs=4))
    parts.append(ball(f"GoggleLens{sd}", 0.08, (sd * 0.13, -0.25, PV + 0.255), hexc("8ae8ff"), squash=(1, 1, 0.5), rot=(-0.5, 0, 0), subdiv=1))
pd("Mouth", half_oval(0, PV - 0.12, 0.2, 0.1), MOUTH)
pd("Tongue", oval(0, PV - 0.19, 0.08, 0.04, n=8), TONGUE, off=0.03, th=0.006)
pd("CheekL", oval(-0.26, PV - 0.12, 0.08, 0.04, n=8), CHEEK)
pd("CheekR", oval(0.26, PV - 0.12, 0.08, 0.04, n=8), CHEEK)


# glass dome: thin hemispherical frame (two crossing arches) + curved glint streaks
def arch(name, yaw, r=0.9):
    a = math.radians(yaw)
    pts = []
    for k in range(9):
        t = math.pi * k / 8
        x = math.cos(t) * r
        pts.append((math.cos(a) * x, math.sin(a) * x, CZ + 0.02 + math.sin(t) * r * 0.95))
    return horn(name, pts, [0.035] * len(pts), hexc("dfe8f6"), hexc("ffffff"), segs=5)


parts.append(arch("Arch0", 45))
parts.append(arch("Arch1", 135))


def glint(name, a0, a1, e0, e1, r=0.93):
    def fn(s, t):
        a = math.radians(a0 + (a1 - a0) * s)
        e = math.radians(e0 + (e1 - e0) * t)
        return (math.sin(a) * math.cos(e) * r, -math.cos(a) * math.cos(e) * r, CZ + 0.02 + math.sin(e) * r * 0.95)
    return shell(name, fn, 4, 2, 0.012, lambda p, n: mix(GLASS, GLASS_L, 0.6))


parts.append(glint("Glass0", -60, -25, 20, 70))
parts.append(glint("Glass1", -18, -8, 30, 62))
parts.append(ball("DomeTop", 0.07, (0, 0, CZ + 0.9), RED, subdiv=1))

# ---- armour details: rivets, red chest light, vents on the back, panel seam
for k in range(8):
    yaw = k * 45 + 22.5
    if abs(((yaw + 180) % 360) - 180) < 30:
        continue
    q = b.point(math.radians(yaw), 1.05, 0.0)
    parts.append(ball(f"Rivet{k}", 0.05, tuple(q), hexc("e8eef8"), subdiv=1))
for k in range(3):
    parts.append(decal(f"Vent{k}", rect(0, 1.9 - k * 0.2, 0.9, 0.08), GUN_D, frame_at(180, 0), off=0.01, th=0.015, on=["Body"]))
for k, yaw in enumerate((140, -140)):
    parts.append(decal(f"Seam{k}", rect(0, 1.45, 0.06, 1.4), GUN, frame_at(yaw, 0), off=0.008, th=0.01, on=["Body"], step=0.25))
parts.append(decal("Badge", star(0, 0.95, 0.16, 0.08), HAZ_Y, frame_at(0, 0), off=0.015, th=0.02, on=["Body"]))

if os.environ.get("TRIS_DBG"):
    import re, collections
    cnt = collections.Counter()
    for o in parts:
        cnt[re.sub(r"[-\d]+$", "", o.name.split(".")[0])] += sum(len(pp.vertices) - 2 for pp in o.data.polygons)
    print("TRIS", sorted(cnt.items(), key=lambda kv: -kv[1])[:25])
ship("slime_mecha_goo", parts)
