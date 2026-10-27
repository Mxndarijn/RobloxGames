# Abyss (Secret, Frost & Sea): a deep-sea anglerfish slime. Very dark navy-to-black body lit by
# bioluminescent cyan spots, back chevrons and a cyan rim glow; a long curved antenna stalk from
# the head ends in a big glowing cyan-white lure orb hanging in front of the face; a wide grin
# full of jagged white teeth, big glowing eyes, ragged glowing fins on the sides, a frilled back
# fin, and a few glowing bubbles floating round it. Contrast comes from the glow, the lure and the
# teeth, not from the body colour.
from models._slimepool import *

TOP, MID, BELLY = hexc("0b1440"), hexc("152c70"), hexc("2350a8")
CY_D, CY, CY_L = hexc("00a8d8"), hexc("2ff0ff"), hexc("c8ffff")
EYE_W = hexc("eafff8")
GUM, MOUTH_IN, TONGUE_A = hexc("4a0a30"), hexc("6a1040"), hexc("d83a7a")
TEETH, TEETH_D = hexc("ffffff"), hexc("d8e4f0")
FIN_D = hexc("1a3a88")


def paint(a, z, p):
    ad = abs(math.degrees(a))
    c = mix(MID, TOP, smoothstep(1.2, 2.7, z))
    c = mix(c, BELLY, 0.7 * smoothstep(70, 20, ad) * smoothstep(1.6, 0.6, z))  # lighter belly under the grin
    side = smoothstep(60, 88, ad) * smoothstep(135, 105, ad) * smoothstep(2.7, 2.0, z)
    c = mix(c, CY_D, 0.55 * side)  # rim glow on the silhouette seen from the front
    c = mix(c, CY, 0.65 * smoothstep(0.32, 0.0, z))  # glowing foot
    return c


def chevrons(a, z):
    """crisp glowing chevron stripes over the back (per face)"""
    ad = math.degrees(a) % 360 - 180  # 0 = straight back
    if abs(ad) > 75 or z < 0.55 or z > 2.55:
        return None
    for k in range(4):
        zc = 0.85 + k * 0.5 + abs(ad) * 0.006
        if abs(z - zc) < 0.075:
            return CY
    return None


b = Body([(0, 1.15), (0.14, 1.5), (0.6, 1.7), (1.3, 1.64), (1.95, 1.4), (2.45, 0.98), (2.8, 0.45), (2.92, 0)],
         paint=paint, segs=48, sub=3, sy=0.94, gloss=0.6, shade=0.7)
parts = [b.obj]
H = b.H


# ---------------------------------------------------------------- grid decal (big decals that hug a curved body)
def pdecal(name, poly, color, frame=FRONT, off=0.02, th=0.025, on=("Body",), step=0.14, passes=1):
    """like decal(), but the cap is triangulated and subdivided before projection, so wide
    decals (the grin, eye rings) follow the curved body instead of sinking into it."""
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
    for fc in bm.faces:  # cap faces towards the viewer
        if fc.normal.dot(frame.D) < 0:
            fc.normal_flip()
    bm.normal_update()
    old = list(bm.verts)
    res = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces) + list(bm.edges) + list(bm.verts))
    new = [g for g in res["geom"] if isinstance(g, bmesh.types.BMVert)]
    # extruded copies keep the original order: pair them by position
    lookup = {tuple(round(c, 6) for c in v.co): nrm[v] for v in old}
    for v in new:
        v.co += lookup[tuple(round(c, 6) for c in v.co)] * th
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, None if callable(color) else color)
    if callable(color):
        paint_fn(o, color)
    return keep(o, False)


# ---------------------------------------------------------------- glowing spots: lateral lines + head freckles
spec = []
for sd in (-1, 1):
    for k, yaw in enumerate(range(62, 136, 14)):
        spec.append((sd * yaw, 1.32 + 0.06 * math.sin(k * 1.7), 0.17 - 0.012 * k))
    for k, yaw in enumerate(range(74, 130, 18)):
        spec.append((sd * yaw, 0.72, 0.12))
    spec += [(sd * 42, 2.38, 0.12), (sd * 70, 2.2, 0.15), (sd * 28, 2.62, 0.09)]
parts += spots(b, spec, CY_L, n=8)
# glowing chevrons down the back (grid decals: smooth edges, unlike per-face sectors)
for k, z in enumerate((0.95, 1.45, 1.95)):
    w = 1.25 - 0.18 * k
    chev = [(-w, 0.28), (0, -0.02), (w, 0.28), (w, 0.42), (0, 0.12), (-w, 0.42)]
    parts.append(pdecal(f"Chevron{k}", chev, CY, frame=frame_at(180, z), off=0.012, th=0.015, step=0.2, passes=0))

# ---------------------------------------------------------------- face: big glowing eyes
EV, EU = 1.82, 0.58
for sd in (-1, 1):
    u = sd * EU
    parts.append(pdecal(f"EyeGlow{sd}", oval(u, EV, 0.78, 0.74, n=20), CY, off=0.012, th=0.012, step=0.25))
    parts.append(pdecal(f"Eye{sd}", oval(u, EV, 0.6, 0.57, n=18), lambda p, n: mix(EYE_W, CY_L, 0.5), off=0.026, th=0.012, step=0.25))
    parts.append(decal(f"Pupil{sd}", oval(u - sd * 0.05, EV + 0.06, 0.2, 0.3, n=12), TOP, FRONT, off=0.04, th=0.012, on=["Body"]))
    parts.append(decal(f"EyeHi{sd}", oval(u - 0.12, EV + 0.14, 0.11, 0.09, n=8), WHITE, FRONT, off=0.055, th=0.01, on=["Body"]))
    # mean brow ridge: dark wedge over the inner top of each eye
    parts.append(decal(f"Brow{sd}", [(u - sd * 0.38, EV + 0.2), (u + sd * 0.18, EV + 0.44), (u + sd * 0.36, EV + 0.38),
                                     (u - sd * 0.1, EV + 0.18)], TOP, FRONT, off=0.05, th=0.02, on=["Body"]))

# ---------------------------------------------------------------- wide grin with jagged teeth
MV, MW = 0.98, 0.92  # mouth centre height, half width


def mtop(u):
    return MV + 0.1 + 0.26 * (u / MW) ** 2


def mbot(u):
    return MV - 0.36 * (1 - (u / MW) ** 2) ** 0.8 + 0.26 * (u / MW) ** 2 + 0.1 * (u / MW) ** 2


NM = 24
top = [(-MW + 2 * MW * k / NM, mtop(-MW + 2 * MW * k / NM)) for k in range(NM + 1)]
bot = [(MW - 2 * MW * k / NM, mbot(MW - 2 * MW * k / NM)) for k in range(1, NM)]
parts.append(pdecal("Mouth", top + bot, lambda p, n: mix(GUM, MOUTH_IN, smoothstep(1.2, 0.7, p.z)), off=0.015, th=0.02, step=0.1))
parts.append(pdecal("Tongue", oval(0.12, MV - 0.18, 0.62, 0.2, n=14), TONGUE_A, off=0.03, th=0.01))
# top row: long jagged fangs pointing down, uneven
for k, (u, L, w) in enumerate([(-0.78, 0.13, 0.13), (-0.6, 0.2, 0.16), (-0.4, 0.28, 0.17), (-0.2, 0.18, 0.14), (0.0, 0.3, 0.17),
                               (0.2, 0.2, 0.15), (0.4, 0.27, 0.17), (0.6, 0.18, 0.15), (0.77, 0.12, 0.12)]):
    v0 = mtop(u) + 0.015
    lean = 0.03 * math.sin(k * 2.3)
    parts.append(decal(f"ToothT{k}", [(u - w / 2, v0), (u + w / 2, v0), (u + lean, v0 - L)],
                       lambda p, n: mix(TEETH, TEETH_D, 0.4), FRONT, off=0.045, th=0.02, on=["Body"], step=0.1))
# bottom row: shorter teeth pointing up
for k, (u, L, w) in enumerate([(-0.62, 0.12, 0.13), (-0.38, 0.2, 0.15), (-0.12, 0.15, 0.14), (0.13, 0.22, 0.15), (0.38, 0.14, 0.14),
                               (0.6, 0.18, 0.13)]):
    v0 = mbot(u) - 0.015
    parts.append(decal(f"ToothB{k}", [(u + w / 2, v0), (u - w / 2, v0), (u + 0.02, v0 + L)],
                       lambda p, n: mix(TEETH, TEETH_D, 0.4), FRONT, off=0.045, th=0.02, on=["Body"], step=0.1))

# ---------------------------------------------------------------- antenna stalk + lure
stalk = [(0, 0.2, H - 0.12), (0, 0.15, H + 0.35), (0, -0.25, H + 0.9), (0, -0.9, H + 1.12), (0, -1.5, H + 0.88),
         (0, -1.9, H + 0.55), (0, -1.98, H + 0.2)]
sp = [Vector(q) for q in catmull([(q[1], q[2]) for q in stalk], 4)]
sp = [Vector((0, q[0], q[1])) for q in sp]
N = len(sp)
st = tube("Stalk", sp, [0.13 - 0.07 * (k / (N - 1)) for k in range(N)], None, segs=8, twist_free=True)
L = [0.0]
for p0, p1 in zip(sp, sp[1:]):
    L.append(L[-1] + (p1 - p0).length)


def stalk_col(p, n):
    best = min(range(N), key=lambda i: (sp[i] - p).length)
    t = L[best] / L[-1]
    c = mix(MID, FIN_D, t)
    return mix(c, CY, smoothstep(0.7, 1.0, t))


paint_fn(st, stalk_col)
parts.append(keep(st, True))
# glowing rings along the stalk
for k, t in enumerate((0.35, 0.55, 0.72)):
    i = int(t * (N - 1))
    d = (sp[min(i + 1, N - 1)] - sp[i - 1]).normalized()
    parts.append(torus(f"StalkRing{k}", 0.1 - 0.02 * k, 0.03, sp[i], d, CY, segs=10, rsegs=4))

LURE = Vector((0, -2.0, H - 0.2))
key = Vector((-0.35, -0.75, 0.55)).normalized()
parts.append(lathe("LureCap", [(0, 0.09), (0.12, 0.13), (0.2, 0.0)], FIN_D, pos=LURE + Vector((0, 0, 0.42)), axis=(0, 0, -1), segs=8))
parts.append(ball("Lure", 0.4, LURE, lambda p, n: mix(CY, WHITE, 0.25 + 0.75 * max(0.0, n.dot(key)) ** 0.7), subdiv=3))
for k, a in enumerate(math.radians(d) for d in (5, 62, 118, 175)):  # glow sparks above the lure, clear of the eyes
    parts.append(slab(f"LureSpark{k}", star(0, 0, 0.13, 0.04, n=4), 0.03, LURE + Vector((math.cos(a) * 0.66, -0.05, math.sin(a) * 0.66)),
                      (1, 0, 0), (0, 0, 1), CY_L))


# ---------------------------------------------------------------- ragged pectoral fins
def fin_col(root, out_dir, Lf):
    def fn(p, n):
        t = max(0.0, (p - root).dot(out_dir)) / Lf
        return mix(FIN_D, CY, smoothstep(0.35, 1.0, t))
    return fn


FIN = [(0, -0.38), (0.5, -0.5), (1.15, -0.3), (0.88, -0.1), (1.2, 0.08), (0.85, 0.2), (1.05, 0.42), (0.6, 0.38), (0.3, 0.5), (0, 0.32)]
for sd in (-1, 1):
    root = b.point(math.radians(sd * 92), 1.1, -0.12)
    X = Vector((sd * 1, 0.35, 0.25)).normalized()
    Y = Vector((0, 0.55, 1)).normalized()
    poly = [(x, y) for x, y in FIN]
    parts.append(slab(f"Fin{sd}", poly, 0.07, root, X, Y, fin_col(root, X, 1.15)))
    # fin rays: darker spines
    for j, (x, y) in enumerate([(1.15, -0.3), (1.2, 0.08), (1.05, 0.42)]):
        tip = root + X * x * 0.92 + Y * y * 0.92
        base = root + X * 0.2 + Y * y * 0.3
        parts.append(tube(f"FinRay{sd}{j}", [base, tip], [0.035, 0.018], CY_L, segs=4))

# ---------------------------------------------------------------- frilled back fin (in the YZ plane)
base = []
for k in range(15):
    z = 0.75 + (H - 0.55 - 0.75) * k / 14
    q = b.point(math.pi, z, -0.12)
    base.append((q.y, q.z))
outer = []
for k in range(15):
    y, z = base[k]
    q0 = base[max(k - 1, 0)]
    q1 = base[min(k + 1, 14)]
    ty, tz = q1[0] - q0[0], q1[1] - q0[1]
    ln = math.hypot(ty, tz)
    ny, nz = tz / ln, -ty / ln  # outward (back/up)
    if ny < 0:
        ny, nz = -ny, -nz
    t = k / 14
    h = (0.45 + 0.6 * math.sin(math.pi * min(1.0, t * 1.1))) * (1.0 if k % 2 == 0 else 0.5)
    outer.append((y + ny * h, z + nz * h))
frill = [(y, z) for y, z in base] + list(reversed(outer))


def frill_col(p, n):
    d = min(math.hypot(p.y - y, p.z - z) for y, z in base)
    return mix(FIN_D, CY, smoothstep(0.2, 0.85, d))


parts.append(slab("FinBack", frill, 0.07, (0, 0, 0), (0, 1, 0), (0, 0, 1), frill_col))

# ---------------------------------------------------------------- glowing bubbles
for k, (x, y, z, r) in enumerate([(-1.95, -0.5, 2.45, 0.19), (-2.2, 0.15, 1.65, 0.11), (2.0, -0.7, 2.75, 0.22), (2.25, 0.25, 1.85, 0.12),
                                  (1.45, -1.25, 3.35, 0.1), (-1.25, 0.9, 3.2, 0.13)]):
    c = Vector((x, y, z))
    parts.append(ball(f"Bubble{k}", r, c, lambda p, n: mix(CY, CY_L, 0.3 + 0.7 * max(0.0, n.dot(key))), subdiv=2))
    parts.append(ball(f"BubbleHi{k}", r * 0.28, c + Vector((-0.4, -0.55, 0.55)).normalized() * r * 0.82, WHITE, subdiv=1))

ship("slime_abyss", parts)
