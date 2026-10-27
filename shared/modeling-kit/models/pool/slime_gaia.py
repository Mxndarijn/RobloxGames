# Gaia (Secret, Garden): the earth-mother spirit slime. Body graded rich soil-brown at the foot
# through leaf green to a glowing spring green crown, two leafy vines spiralling round it, a
# floating halo of blooming flowers (pink, white, yellow) above the head, a tilted ring of leaves
# and petals orbiting it, serene closed eyes with a gentle smile and a glowing seed on the forehead.
from models._slimepool import *

SOIL, SOIL_L = hexc("8a5630"), hexc("a8703c")
LEAF_D, LEAF, LEAF_L = hexc("3cb556"), hexc("48d672"), hexc("9cf27a")
BLADE_D, BLADE_L = hexc("8ad21e"), hexc("dcff5a")  # vine/orbit leaves: yellow-green against the emerald body
SPRING, GLOW = hexc("c4ff6e"), hexc("f2ffc0")
VINE_D, VINE = hexc("4a8a22"), hexc("8ccf34")
PINK, PINK_L = hexc("ff6fae"), hexc("ffc2de")
PWHITE, PWHITE_D = hexc("ffffff"), hexc("f0dcff")
YEL, YEL_L = hexc("ffcf2e"), hexc("fff27a")
CORE, CORE_O = hexc("ffe14a"), hexc("ff9a2e")
SEED, SEED_L = hexc("5cff2a"), hexc("fcffa0")
INKG = hexc("2a3a18")


def paint(a, z, p):
    c = mix(SOIL, SOIL_L, smoothstep(0.0, 0.6, z))
    c = mix(c, LEAF_D, smoothstep(0.62, 1.0, z))
    c = mix(c, LEAF, smoothstep(1.0, 1.7, z))
    c = mix(c, LEAF_L, smoothstep(1.7, 2.35, z))
    c = mix(c, SPRING, smoothstep(2.2, 2.65, z))
    c = mix(c, GLOW, 0.6 * smoothstep(2.6, 3.0, z))
    # soft mossy mottling in the soil/leaf transition
    n = noise.noise(Vector((p.x * 2.2, p.y * 2.2, p.z * 2.2 + 4.0)))
    c = mix(c, LEAF_D, 0.35 * smoothstep(0.1, 0.45, n) * smoothstep(0.45, 0.75, z) * smoothstep(1.35, 0.95, z))
    return c


b = Body([(0, 1.05), (0.14, 1.38), (0.5, 1.56), (1.15, 1.54), (1.8, 1.3), (2.4, 0.92), (2.8, 0.45), (3.0, 0)],
         paint=paint, segs=48, sub=3, gloss=0.8)
parts = [b.obj]
H = b.H


def leaf_poly(L, w, n=5):
    """pointed leaf, base at (0, 0), tip at (0, L)"""
    right = [(w * math.sin(math.pi * k / n) ** 0.8, L * k / n) for k in range(1, n)]
    left = [(-x, y) for x, y in reversed(right)]
    return [(0, 0)] + right + [(0, L)] + left


def flower_poly(r_out, r_in, petals=5, n=30, rot=0.0):
    pts = []
    for k in range(n):
        t = k * math.tau / n + rot
        r = r_in + (r_out - r_in) * abs(math.cos(petals * (t - rot) / 2)) ** 0.6
        pts.append((math.cos(t) * r, math.sin(t) * r))
    return pts


def flower(name, pos, normal, r, col, col_l, core=CORE, rot=0.0):
    """5-petal bloom facing `normal`: petal slab (light centre) + domed core"""
    n = Vector(normal).normalized()
    X = n.cross(Vector((0, 0, 1)))
    if X.length < 1e-3:
        X = Vector((1, 0, 0))
    X.normalize()
    Y = n.cross(X).normalized()
    P = Vector(pos)
    out = [slab(f"{name}P", flower_poly(r, r * 0.42, rot=rot), r * 0.22, P, X, Y,
                lambda p, nn, P=P: mix(col_l, col, smoothstep(r * 0.25, r * 0.9, (p - P).length)), smooth=False)]
    out.append(ball(f"{name}C", r * 0.32, P + n * r * 0.12, lambda p, nn: mix(core, CORE_O, 0.5 - 0.5 * nn.dot(n)), squash=(1, 1, 0.7),
                    rot=tuple(math.degrees(v) for v in n.to_track_quat("Z", "Y").to_euler()), subdiv=1))
    return out


def leaf(name, base, direction, up, L, w, c0=BLADE_D, c1=BLADE_L):
    d = Vector(direction).normalized()
    u = Vector(up)
    side = d.cross(u).normalized()
    B = Vector(base)
    return slab(name, leaf_poly(L, w), 0.05, B, side, d, along(c0, c1, B, B + d * L), smooth=False)


# ---- vines spiralling round the body (kept off the face), leaves along them
def vine(name, specs, r0=0.075, r1=0.035, leaves=()):
    pts = []
    N = 26
    for k in range(N):
        t = k / (N - 1)
        yaw = specs[0][0] + (specs[1][0] - specs[0][0]) * t
        z = specs[0][1] + (specs[1][1] - specs[0][1]) * t
        pts.append(b.point(math.radians(yaw), z, 0.03))
    radii = [r0 + (r1 - r0) * k / (N - 1) for k in range(N)]
    o = tube(name, pts, radii, None, segs=6, twist_free=True)
    paint_fn(o, lambda p, n: mix(VINE_D, VINE, smoothstep(0, H, p.z)))
    out = [keep(o, True)]
    for j, (t, sd, L) in enumerate(leaves):
        i = int(t * (N - 1))
        p = pts[i]
        tng = (pts[min(i + 1, N - 1)] - pts[max(i - 1, 0)]).normalized()
        outv = Vector((p.x, p.y, 0)).normalized()
        d = (tng * 0.35 + tng.cross(outv) * sd + outv * 0.55).normalized()
        out.append(leaf(f"{name}L{j}", p, d, outv, L, L * 0.38))
    return out


parts += vine("VineA", [(-40, 0.18), (-235, 2.55)], leaves=[(0.16, 1, 0.5), (0.36, -1, 0.55), (0.56, 1, 0.5), (0.76, -1, 0.45), (0.95, 1, 0.42)])
parts += vine("VineB", [(45, 0.2), (215, 2.2)], leaves=[(0.2, -1, 0.5), (0.42, 1, 0.55), (0.64, -1, 0.5), (0.86, 1, 0.45)])
# little blooms where the vines start (on the foot, front)
parts += flower("FootF0", b.point(math.radians(-40), 0.35, 0.12), b.point(math.radians(-40), 0.35, 1) - b.point(math.radians(-40), 0.35, 0), 0.26, PINK, PINK_L)
parts += flower("FootF1", b.point(math.radians(45), 0.38, 0.12), b.point(math.radians(45), 0.38, 1) - b.point(math.radians(45), 0.38, 0), 0.22, YEL, YEL_L, core=CORE_O)

# ---- floating flower halo above the head
HC = Vector((0, 0.1, H + 0.72))
HR = 1.05
hn = Vector((0, -0.32, 1)).normalized()
parts.append(torus("HaloVine", HR, 0.09, HC, hn, lambda p, n: mix(VINE_D, VINE, 0.5 + 0.5 * n.z), segs=32, rsegs=6))
hq = hn.to_track_quat("Z", "Y")
NFL = 8
cols = [(PINK, PINK_L), (PWHITE_D, PWHITE), (YEL, YEL_L)]
for k in range(NFL):
    a = k * math.tau / NFL - math.pi / 2
    rad = hq @ Vector((math.cos(a), math.sin(a), 0))
    p = HC + rad * HR
    c, cl = cols[k % 3]
    r = 0.47 if k % 2 == 0 else 0.4
    nrm = (rad * 0.7 + hn).normalized()
    parts += flower(f"Halo{k}", p + nrm * 0.05, nrm, r, c, cl, rot=k * 0.7)
    # a leaf pair between flowers, pointing outward
    a2 = a + math.tau / NFL / 2
    rad2 = hq @ Vector((math.cos(a2), math.sin(a2), 0))
    p2 = HC + rad2 * HR
    parts.append(leaf(f"HaloLf{k}", p2, (rad2 + hn * 0.25).normalized(), hn, 0.6, 0.24, BLADE_D, BLADE_L))

# ---- sprout growing from the crown (inside the halo)
top = Vector((0, 0.02, H - 0.05))
stem_pts = [top, top + Vector((0, 0.02, 0.22)), top + Vector((0.04, 0.0, 0.42))]
parts.append(horn("Sprout", stem_pts, [0.07, 0.06, 0.045], VINE, LEAF_L, segs=6))
for sd in (-1, 1):
    parts.append(leaf(f"SproutLf{sd}", stem_pts[-1], Vector((sd * 1, -0.1, 0.55)), Vector((0, -0.3, 1)), 0.62, 0.27, LEAF, SPRING))

# ---- glowing seed on the forehead, two tiny leaves as its setting
sp = b.point(0, 2.28, 0.0)
sn = (b.point(0, 2.28, 1) - sp).normalized()
sax = (sn * 0.35 + Vector((0, 0, 1))).normalized()
parts.append(lathe("Seed", [(0, 0), (0.06, 0.14), (0.2, 0.2), (0.38, 0.12), (0.55, 0)],
                   lambda p, n: mix(SEED, SEED_L, smoothstep(-0.2, 0.8, n.dot(Vector((-0.3, -0.7, 0.6))))),
                   pos=sp + sn * 0.08 - sax * 0.1, axis=sax, segs=10, smooth=True))
for sd in (-1, 1):
    parts.append(leaf(f"SeedLf{sd}", sp + sn * 0.05 + Vector((sd * 0.06, 0, -0.08)), Vector((sd * 1, 0, 0.35)), sn, 0.4, 0.16, BLADE_D, BLADE_L))

# ---- orbiting ring of leaves and petals (tilted)
OC = Vector((0, 0, 1.35))
tilt = math.radians(16)
ORX, ORY = 2.35, 1.95


def orbit(t):
    x, y = math.cos(t) * ORX, math.sin(t) * ORY
    return OC + Vector((x, y * math.cos(tilt), y * math.sin(tilt) - x * 0.1))


NO = 10
for k in range(NO):
    t = k * math.tau / NO + 0.2
    p = orbit(t)
    tng = (orbit(t + 0.01) - orbit(t - 0.01)).normalized()
    radial = Vector((p.x, p.y, 0)).normalized()
    up = (Vector((0, 0, 1)) + radial * 0.4).normalized()
    if k % 3 == 0:  # pink petal
        parts.append(slab(f"OrbP{k}", oval(0, 0, 0.4, 0.64, n=12), 0.05, p, tng, up,
                          lambda q, n, p=p: mix(PINK_L, PINK, smoothstep(0, 0.3, (q - p).length)), smooth=False))
    elif k % 3 == 1:  # leaf
        parts.append(leaf(f"OrbL{k}", p - tng * 0.25, (tng + up * 0.3).normalized(), up, 0.8, 0.3, BLADE_D, BLADE_L))
    else:  # white petal
        parts.append(slab(f"OrbW{k}", oval(0, 0, 0.36, 0.58, n=12), 0.05, p, tng, up,
                          lambda q, n, p=p: mix(PWHITE, PWHITE_D, smoothstep(0, 0.28, (q - p).length)), smooth=False))
    # pollen sparkle trailing each piece
    parts.append(ball(f"Pollen{k}", 0.08, orbit(t - 0.2), GLOW, subdiv=1))

# ---- face: serene closed eyes, gentle smile, rosy cheeks
f = Face(b, eye_u=0.5, eye_v=1.58, mouth_v=1.18, ink=INKG, mouth_col=hexc("6a2a3a"))
f.eyes("sleepy", w=0.5)
f.mouth("smile", w=1.15)
f.cheeks(color=hexc("ff9ab8"))
parts += f.parts
ship("slime_gaia", parts)
