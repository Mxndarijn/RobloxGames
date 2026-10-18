# Froggo (Uncommon): happy frog. Wide squat body, big eyes up on two bumps, pale belly, a huge
# smile with the tongue hanging out, dark back spots, haunches and toe-y front feet.
from models._slimepool import *

G, G_D, G_L = hexc("3fcc3a"), hexc("1f8a36"), hexc("8ef05a")
SPOT = hexc("17702e")
BELLY, BELLY_D = hexc("f4ffbe"), hexc("d8f08a")
IRIS = hexc("ffc21a")


def paint(a, z, p):
    c = mix(G_D, G, smoothstep(0.0, 0.9, z))
    c = mix(c, G_L, 0.18 * smoothstep(1.4, 2.4, z))
    f = smoothstep(1.05, 0.6, abs(a)) * smoothstep(1.55, 1.15, z)
    return mix(c, mix(BELLY_D, BELLY, smoothstep(0.1, 1.0, z)), f)


def ddecal(name, poly, color, frame=FRONT, off=0.02, th=0.025, on=None, rings=4):
    """decal() with a subdivided cap: concentric rings toward the centroid are projected too, so a
    wide decal on a tight curve (the eye bumps) hugs the surface instead of sinking into it."""
    poly = list(poly)
    cu = sum(p[0] for p in poly) / len(poly)
    cv = sum(p[1] for p in poly) / len(poly)
    bm = bmesh.new()

    def proj(u, v, extra):
        o = frame.O + frame.U * u + frame.V * v + frame.D * 12
        hit = cast(o, -frame.D, on)
        if hit is None:
            raise ValueError(f"ddecal {name}: ({u:.2f}, {v:.2f}) misses")
        loc, n, _ = hit
        if n.dot(frame.D) < 0:
            n = -n
        n = (n * 0.6 + frame.D * 0.4).normalized()
        return bm.verts.new(loc + n * extra)

    layers = []
    for extra in (off, off + th):
        rl = []
        for r in range(rings):
            f = 1 - r / rings
            rl.append([proj(cu + (u - cu) * f, cv + (v - cv) * f, extra) for u, v in poly])
        layers.append((rl, proj(cu, cv, extra)))
    k = len(poly)
    for li, (rl, c) in enumerate(layers):
        flip = li == 0
        for a, b2 in zip(rl, rl[1:]):
            for i in range(k):
                j = (i + 1) % k
                q = (a[i], a[j], b2[j], b2[i])
                bm.faces.new(tuple(reversed(q)) if flip else q)
        for i in range(k):
            tri = (rl[-1][i], rl[-1][(i + 1) % k], c)
            bm.faces.new(tuple(reversed(tri)) if flip else tri)
    back, front = layers[0][0][0], layers[1][0][0]
    for i in range(k):
        j = (i + 1) % k
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, color)
    return keep(o, False)


b = Body([(0, 1.18), (0.12, 1.46), (0.45, 1.6), (1.05, 1.53), (1.65, 1.27), (2.07, 0.82), (2.34, 0.3), (2.42, 0)],
         paint=paint, segs=34, sub=2, sx=1.1, sy=0.95, gloss=0.5)
parts = [b.obj]

# eye bumps + eyes projected onto them
EZ, EU = 2.1, 0.72
for sd in (-1, 1):
    nm = f"Bump{'L' if sd < 0 else 'R'}"
    sphere = [(-0.56 * math.cos(k * math.pi / 9), 0.56 * math.sin(k * math.pi / 9)) for k in range(10)]
    bump = lathe(nm, sphere, along(G, G_L, (0, 0, EZ - 0.4), (0, 0, EZ + 0.5)), pos=(sd * EU, -0.28, EZ), axis=(0, -1, 0.35), segs=16)
    register(bump)
    parts.append(bump)
    u, v = sd * EU, EZ + 0.02
    parts.append(ddecal(f"EyeW{sd}", oval(u, v, 0.8, 0.8, n=16), WHITE, off=0.01, th=0.02, on=[nm], rings=2))
    parts.append(ddecal(f"Eye{sd}", oval(u + sd * 0.03, v - 0.03, 0.56, 0.6, n=14), INK, off=0.035, th=0.012, on=[nm], rings=2))
    parts.append(ddecal(f"EyeHi{sd}", oval(u - 0.08, v + 0.1, 0.2, 0.17, n=8), WHITE, off=0.055, th=0.01, on=[nm], rings=1))
    parts.append(ddecal(f"EyeHi2{sd}", oval(u + 0.12, v - 0.14, 0.08, 0.08, n=6), WHITE, off=0.055, th=0.01, on=[nm], rings=1))

# haunches (back legs) and front feet with toes
for sd in (-1, 1):
    parts.append(ball(f"Haunch{sd}", 0.6, (sd * 1.42, 0.35, 0.5), along(G_D, G, (0, 0, 0.0), (0, 0, 1.1)), squash=(0.75, 1.25, 0.85), rot=(0, 0, sd * 0.3)))
    fx = sd * 0.85
    parts.append(ball(f"Foot{sd}", 0.36, (fx, -1.18, 0.12), G_D, squash=(1.2, 1.0, 0.42)))
    for k, dx in enumerate((-0.26, 0.0, 0.26)):
        parts.append(ball(f"Toe{sd}{k}", 0.12, (fx + dx, -1.5 + abs(dx) * 0.4, 0.1), G, squash=(1, 1, 0.75), subdiv=1))

# dark spots on the back and sides
parts += spots(b, [(140, 1.0, 0.42), (175, 1.6, 0.32), (-150, 1.25, 0.38), (115, 1.55, 0.24), (-115, 0.85, 0.3), (160, 0.55, 0.26), (-170, 1.9, 0.22)], SPOT, n=8)

# huge smile with the tongue out
f = Face(b, eye_v=EZ, mouth_v=1.05)
MV = 1.16
f.d("Mouth", arc(0, MV + 0.62, 0.95, 222, 318, 0.085, n=12), MOUTH)
f.d("Tongue", half_oval(0.12, MV - 0.01, 0.42, 0.5, n=12), TONGUE, off=0.035, th=0.015)
f.d("TongueLine", rect(0.12, MV - 0.24, 0.035, 0.3), shade(TONGUE, 0.72), off=0.055, th=0.008)
f.cheeks(u=0.95, v=1.3, w=0.36, h=0.18)
f.d("Nostril-1", oval(-0.13, 1.6, 0.07, 0.05, n=6), G_D)
f.d("Nostril1", oval(0.13, 1.6, 0.07, 0.05, n=6), G_D)
parts += f.parts
ship("slime_froggo", parts)
