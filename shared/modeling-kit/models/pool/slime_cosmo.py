# Cosmo (Mythic): a tiny galaxy. Navy -> violet goo with magenta/cyan nebula clouds and star speckles,
# a tilted banded planet ring, starstruck eyes, a cratered moon orbiting with a dotted trail.
from models._slimepool import *

NAVY, VIOLET, MAG, CY = hexc("101a5c"), hexc("5a2ac0"), hexc("ff4fd2"), hexc("38d6ff")
STAR, STAR_Y = hexc("ffffff"), hexc("fff2a0")
RING = [hexc("ffd27a"), hexc("ff9a5a"), hexc("fff0c8"), hexc("c890ff"), hexc("ffb0e0")]
MOON, MOON_D = hexc("f4ecd0"), hexc("c8bea0")


def paint(a, z, p):
    c = mix(NAVY, VIOLET, smoothstep(0.2, 2.9, z))
    q = Vector((p.x * 0.9, p.y * 0.9, p.z * 0.9 + 3.0))
    n1 = noise.noise(q * 1.1 + Vector((0, 0, a * 0.3)))
    n2 = noise.noise(q * 1.4 + Vector((5.2, 1.3, 0)))
    c = mix(c, MAG, 0.75 * smoothstep(0.12, 0.5, n1))
    c = mix(c, CY, 0.6 * smoothstep(0.2, 0.55, n2))
    return c


b = Body([(0, 1.05), (0.12, 1.32), (0.5, 1.5), (1.1, 1.52), (1.75, 1.36), (2.35, 1.0), (2.8, 0.48), (3.0, 0)],
         paint=paint, segs=40, sub=2, gloss=0.9)
parts = [b.obj]

# ---- star speckles all round (low-poly 4-point sparkles + dots), skipping the face area
import random
rng = random.Random(7)
k = 0
for i in range(40):
    yaw = rng.uniform(-180, 180)
    z = rng.uniform(0.35, 2.75)
    if abs(yaw) < 55 and 0.75 < z < 2.25:
        continue
    r = rng.uniform(0.05, 0.13)
    c = STAR if rng.random() < 0.7 else STAR_Y
    shape = star(0, 0, r, r * 0.32, n=4, rot=rng.uniform(0, 45)) if r > 0.085 else oval(0, 0, r * 0.8, r * 0.8, n=6)
    parts.append(decal(f"Star{k}", shape, c, frame_at(yaw, z), off=0.01, th=0.012, on=["Body"], step=0))
    k += 1


# ---- tilted planet ring: one closed annulus, crisp colour bands per face (shared verts)
def banded_ring(name, radii, h, center, normal, cols, segs=40):
    q = Vector(normal).normalized().to_track_quat("Z", "Y")
    C = Vector(center)
    bm = bmesh.new()
    sec = [(r, -h) for r in radii] + [(r, h) for r in reversed(radii)]
    m = len(sec)
    rings = []
    for i in range(segs):
        a = i * math.tau / segs
        rings.append([bm.verts.new(C + q @ Vector((math.cos(a) * r, math.sin(a) * r, z))) for r, z in sec])
    fc = []
    for i in range(segs):
        A, B = rings[i], rings[(i + 1) % segs]
        for j in range(m):
            k2 = (j + 1) % m
            bm.faces.new((A[j], B[j], B[k2], A[k2]))
            band = j if j < len(radii) - 1 else (m - 2 - j if j < m - 1 else 0)
            fc.append(cols[max(0, min(len(cols) - 1, band))])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    for f, c in zip(bm.faces, fc):
        for lp in f.loops:
            lp[col] = c
    o = obj_from_bm(name, bm, None)
    return keep(o, False)


RC = Vector((0, 0, 1.32))
RN = Vector((0.25, -0.36, 1.0))
R0, R1 = 1.9, 2.62
radii = [R0 + (R1 - R0) * i / len(RING) for i in range(len(RING) + 1)]
parts.append(banded_ring("Ring", radii, 0.04, tuple(RC), tuple(RN), RING, segs=40))

# ---- moon with craters + dotted orbit trail, little sparkles floating round the top
MC = Vector((-1.7, -0.5, 3.2))
moon = ball("Moon", 0.46, tuple(MC), lambda p, n: mix(MOON_D, MOON, smoothstep(MC.z - 0.4, MC.z + 0.3, p.z)), subdiv=3)
parts.append(register(moon))
for j, (du, dv, w) in enumerate(((-0.27, 0.16, 0.13), (0.24, 0.22, 0.1), (0.3, -0.12, 0.08), (-0.2, -0.26, 0.08))):
    parts.append(decal(f"Crater{j}", oval(MC.x + du, MC.z + dv, w, w, n=10), hexc("a89c80"), frame_at(0, 0, cy=MC.y), off=0.005, th=0.01, on=["Moon"], step=0))
mf = frame_at(0, 0, cy=MC.y)
for sd in (-1, 1):
    parts.append(decal(f"MoonEye{sd}", arc(MC.x + sd * 0.12, MC.z + 0.04, 0.06, 200, 340, 0.035, n=6), INK, mf, off=0.01, th=0.01, on=["Moon"], step=0))
    parts.append(decal(f"MoonCheek{sd}", oval(MC.x + sd * 0.2, MC.z - 0.06, 0.08, 0.045, n=8), CHEEK, mf, off=0.008, th=0.008, on=["Moon"], step=0))
parts.append(decal("MoonMouth", arc(MC.x, MC.z - 0.04, 0.04, 200, 340, 0.025, n=5), MOUTH, mf, off=0.01, th=0.01, on=["Moon"], step=0))
for j in range(7):
    t = j / 7
    a = math.radians(150 - t * 95)
    p = Vector((math.cos(a) * 2.0, -0.6 - 0.3 * t, 2.55 + 0.7 * math.sin(a) * 0.9))
    if (p - MC).length < 0.55:
        continue
    parts.append(ball(f"Trail{j}", 0.06 - 0.005 * j, tuple(p), mix(STAR_Y, MAG, t), subdiv=1))
for j, (pos, r, rot) in enumerate((((1.45, -0.5, 3.0), 0.22, 0), ((1.85, 0.3, 2.4), 0.14, 20), ((-0.9, 0.6, 3.35), 0.16, 10))):
    sp = star(0, 0, r, r * 0.3, n=4, rot=rot)
    parts.append(puffy_slab(f"Spark{j}", sp, 0.07, pos, (1, 0, 0), (0, 0, 1), STAR_Y, rows=2))

# ---- starstruck face
f = Face(b, eye_v=1.58, eye_u=0.52, mouth_v=1.1, s=1.1)
f.eyes("star", color=hexc("ffe14a"))
f.mouth("open", w=1.25)
f.cheeks(color=hexc("ff7ad8"), w=0.28, h=0.13)
parts += f.parts

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_cosmo", parts)
