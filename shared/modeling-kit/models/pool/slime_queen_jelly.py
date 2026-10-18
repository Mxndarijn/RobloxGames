# Queen Jelly (Boss): giant jellyfish queen. A tall domed pink-violet bell floating on long wavy
# ribbon tentacles (tips touch the floor), a ruffled frill skirt round the rim, frilly oral arms in
# the middle, a pearl tiara, glowing spots, and a haughty half-lidded face looking down her nose.
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


def ring_shell(name, fn, nu, nv, thick, color):
    """like shell() but closed around s (s=0 == s=1): a ring band, no seam edges."""
    bm = bmesh.new()
    P = [[Vector(fn(i / nu, j / nv)) for j in range(nv + 1)] for i in range(nu)]

    def nrm(i, j):
        a = P[(i + 1) % nu][j] - P[(i - 1) % nu][j]
        b = P[i][min(j + 1, nv)] - P[i][max(j - 1, 0)]
        return a.cross(b).normalized()
    outer = [[bm.verts.new(P[i][j] + nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu)]
    inner = [[bm.verts.new(P[i][j] - nrm(i, j) * thick / 2) for j in range(nv + 1)] for i in range(nu)]
    for i in range(nu):
        k = (i + 1) % nu
        for j in range(nv):
            bm.faces.new((outer[i][j], outer[k][j], outer[k][j + 1], outer[i][j + 1]))
            bm.faces.new((inner[i][j + 1], inner[k][j + 1], inner[k][j], inner[i][j]))
        for j in (0, nv):
            bm.faces.new((outer[i][j], inner[i][j], inner[k][j], outer[k][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, True)


VIO, VIO_D, PINK, PINK_L = hexc("a24cf0"), hexc("6a24c0"), hexc("ff6ac8"), hexc("ffc4ec")
FRILL, FRILL_D = hexc("ffd0f2"), hexc("ff86d4")
GLOWC = hexc("8ef6ff")
PEARL, PEARL_D = hexc("fffaff"), hexc("e6d4f0")
TENT_A, TENT_B = hexc("ff7ad4"), hexc("c49cff")

Z0 = 1.5  # bell rim height (tentacles below)


def paint(a, z, p):
    t = (z - Z0) / 2.6
    c = mix(PINK, VIO, smoothstep(0.15, 0.85, t))
    c = mix(c, VIO_D, 0.35 * smoothstep(0.75, 1.0, t))
    c = mix(c, PINK_L, 0.35 * smoothstep(0.25, 0.0, t))
    # radial jellyfish stripes from the crown, full length on the back, only up top on the face side
    st = smoothstep(0.86, 0.97, math.cos(a * 8))
    reach = 0.55 if abs(a) < math.radians(70) else 0.1
    st *= smoothstep(reach - 0.05, reach + 0.12, t)
    return mix(c, hexc("ffb4f0"), 0.7 * st)


b = Body([(Z0, 1.25), (Z0 + 0.06, 1.55), (Z0 + 0.3, 1.68), (Z0 + 0.9, 1.64), (Z0 + 1.55, 1.4), (Z0 + 2.05, 1.0),
          (Z0 + 2.38, 0.55), (Z0 + 2.5, 0)], paint=paint, segs=36, sub=2, gloss=0.9)
parts = [b.obj]
H = b.H

# ---- ruffled frill skirt round the rim
def skirt(s, t):
    a = s * math.tau
    r = b.radius(Z0 + 0.12) + 0.02 + 0.32 * t
    z = Z0 + 0.14 - 0.42 * t + 0.1 * math.sin(a * 10) * t
    r += 0.06 * math.cos(a * 10) * t
    return (math.sin(a) * r, -math.cos(a) * r, z)


parts.append(ring_shell("Skirt", skirt, 60, 2, 0.06, lambda p, n: mix(FRILL, FRILL_D, smoothstep(Z0 + 0.1, Z0 - 0.3, p.z))))
parts.append(torus("SkirtRim", b.radius(Z0 + 0.12) + 0.02, 0.07, (0, 0, Z0 + 0.13), (0, 0, 1), PINK_L, segs=36, rsegs=4))

# ---- long ribbon tentacles: hang from under the rim down to the floor, wavy, curling out at the tip
def ribbon(name, yaw, r0, length, w0, phase, c0, c1, waves=2.0):
    a0 = math.radians(yaw)
    d = Vector((math.sin(a0), -math.cos(a0), 0))
    tan = Vector((math.cos(a0), math.sin(a0), 0))

    def path(t):
        z = Z0 - 0.05 - (Z0 - 0.05) * smoothstep(0.0, 0.8, t)
        r = r0 + 0.2 * t + 1.0 * smoothstep(0.6, 1.0, t)
        sway = 0.22 * math.sin(t * math.pi * waves + phase) * min(1.0, t * 3)
        return d * r + tan * sway + Vector((0, 0, max(0.03, z)))

    def fn(s, t):
        w = w0 * (1 - 0.55 * t)
        tw = 0.35 * math.sin(t * math.pi * 2 + phase)  # gentle twist, stays a flat ribbon
        side = tan * math.cos(tw) + d * math.sin(tw)
        q = path(t) + side * (s - 0.5) * w
        if t > 0.75:  # lying on the floor: flatten the ribbon down
            q = path(t) + (tan * (s - 0.5) * w)
        return tuple(q)
    return shell(name, fn, 1, 16, 0.04, lambda p, n: mix(c0, c1, smoothstep(Z0, 0.0, p.z)))


for k in range(8):
    yaw = k * 45 + 22.5
    parts.append(ribbon(f"Ribbon{k}", yaw, 1.1, Z0, 0.3, k * 1.3, TENT_A, TENT_B if k % 2 else hexc("8ad8ff")))

# frilly oral arms in the middle: wider, wavier, paler
for k in range(4):
    yaw = k * 90 + 45
    a0 = math.radians(yaw)
    d = Vector((math.sin(a0), -math.cos(a0), 0))
    tan = Vector((math.cos(a0), math.sin(a0), 0))

    def fn(s, t, d=d, tan=tan, k=k):
        z = Z0 - 0.02 - (Z0 - 0.1) * t
        r = 0.4 + 0.35 * t
        w = 0.34 * (1 - 0.5 * t)
        frill = 0.07 * math.sin(t * 22) * (abs(s - 0.5) * 2)
        p = d * r + Vector((0, 0, max(0.06, z)))
        return tuple(p + tan * (s - 0.5) * w + d * frill)
    parts.append(shell(f"Tent{k}", fn, 1, 12, 0.05, lambda p, n: mix(FRILL, PINK, smoothstep(Z0, 0.1, p.z))))

# ---- glowing spots on the bell
for k in range(10):
    yaw = k * 36 + 18
    z = Z0 + 0.5 + (0.12 if k % 2 else 0.0)
    if abs(((yaw + 180) % 360) - 180) < 30:
        continue
    parts.append(decal(f"Glow{k}", oval(0, 0, 0.3, 0.3, n=12), GLOWC, frame_at(yaw, z), off=0.01, th=0.012, on=["Body"]))
    parts.append(decal(f"GlowC{k}", oval(-0.03, 0.03, 0.12, 0.12, n=8), WHITE, frame_at(yaw, z), off=0.03, th=0.008, on=["Body"]))

# ---- pearl tiara: gold band round the crown of the bell, pearl spires rising to a big pink pearl
TZ = H - 0.62
tr = b.radius(TZ)
parts.append(torus("TiaraBand", tr + 0.02, 0.07, (0, 0, TZ), (0, 0, 1), lambda p, n: mix(GOLD, GOLD_L, 0.5 + 0.5 * n.z), segs=32, rsegs=4))
for k in range(-4, 5):
    a = math.radians(k * 18)
    d = Vector((math.sin(a), -math.cos(a), 0))
    h = 0.8 - 0.13 * abs(k)
    base = Vector((0, 0, TZ)) + d * (tr + 0.04)
    tip = base + Vector((0, 0, h)) + d * 0.06
    if k != 0:
        parts.append(lathe(f"TiaraSpire{k}", [(0, 0.05), (h * 0.9, 0.025), (h, 0)], along(GOLD, GOLD_L, base, tip), pos=tuple(base),
                           axis=tuple(tip - base), segs=6))
        parts.append(ball(f"Pearl{k}", 0.11 - 0.012 * abs(k), tuple(tip + Vector((0, 0, 0.04))), lambda p, n: mix(PEARL_D, PEARL, 0.5 + 0.5 * n.z), subdiv=1))
    parts.append(ball(f"PearlB{k}", 0.055, tuple(base + d * 0.05), PEARL, subdiv=1))
# centre: big heart-ish pink pearl in a gold setting
cb = Vector((0, 0, TZ)) + Vector((0, -1, 0)) * (tr + 0.06)
parts.append(lathe("TiaraArch", [(0, 0.08), (0.7, 0.05), (0.85, 0)], GOLD, pos=tuple(cb), axis=(0, -0.15, 1), segs=8))
parts.append(ball("PearlBig", 0.26, tuple(cb + Vector((0, -0.12, 0.98))), lambda p, n: mix(hexc("ff9ad8"), PEARL, smoothstep(-0.2, 0.9, n.z)), subdiv=2))
parts.append(torus("PearlSet", 0.26, 0.045, tuple(cb + Vector((0, -0.12, 0.98))), (0, 1, 0.1), GOLD, segs=16, rsegs=4))

# ---- haughty face: heavy half-lids looking down, long lashes, one arched brow, tiny smug pout
EV, MV = Z0 + 1.15, Z0 + 0.62
f = Face(b, eye_v=EV, mouth_v=MV, eye_u=0.5, s=1.05)
for sd in (-1, 1):
    u = sd * 0.5
    eye = oval(u, EV, 0.54, 0.64, n=18)
    top = EV + 0.02
    eye = [(x, min(y, top + (x - u) * 0.12 * sd)) for x, y in eye]
    f.d(f"Eye{sd}", eye, INK, off=0.014)
    iris = oval(u, EV - 0.12, 0.4, 0.36, n=14)
    iris = [(x, min(y, top - 0.03 + (x - u) * 0.12 * sd)) for x, y in iris]
    f.d(f"Iris{sd}", iris, hexc("ff4ab8"), off=0.03, th=0.01)
    f.d(f"Pupil{sd}", oval(u, EV - 0.14, 0.14, 0.14, n=10), INK, off=0.04, th=0.008)
    f.d(f"EyeHi{sd}", oval(u - 0.08, EV - 0.08, 0.08, 0.06, n=8), WHITE, off=0.05, th=0.008)
    # heavy lid line + three long lashes flicking out
    f.d(f"Lid{sd}", rect(u, top + 0.01, 0.62, 0.08, math.radians(7 * sd)), INK, off=0.02)
    for j in range(2):
        f.d(f"Lash{sd}{j}", rect(u + sd * (0.32 + 0.06 * j), top + 0.07 + 0.05 * j, 0.05, 0.17, math.radians(-sd * (40 + 22 * j))), INK, off=0.02)
f.d("BrowL", arc(-0.5, EV + 0.22, 0.24, 55, 125, 0.06, n=8), INK)
f.d("BrowR", arc(0.5, EV + 0.36, 0.26, 45, 135, 0.06, n=8), INK)
f.mouth("smirk", w=0.75)
f.cheeks(color=hexc("ff7ab8"), w=0.28, h=0.13)
f.d("Mole", oval(0.36, MV - 0.02, 0.06, 0.06, n=8), hexc("6a2a8a"), off=0.02)
parts += f.parts

if os.environ.get("TRIS_DBG"):
    import re, collections
    cnt = collections.Counter()
    for o in parts:
        cnt[re.sub(r"[-\d]+$", "", o.name.split(".")[0])] += sum(len(pp.vertices) - 2 for pp in o.data.polygons)
    print("TRIS", sorted(cnt.items(), key=lambda kv: -kv[1])[:25])
ship("slime_queen_jelly", parts)
