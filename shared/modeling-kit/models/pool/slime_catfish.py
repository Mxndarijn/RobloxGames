# Catfish (hybrid, tier 4: whiskers + chomp + pengoo): cat-shark. Orange tabby top with bold
# stripes, Pengoo's white heart bib as the belly, Whiskers' pointy ears AND Chomp's swept dorsal
# fin, long drooping whisker barbels, a striped crescent tail fin, flipper pecs, sly fanged grin.
from models._slimepool import *


# ---- local helper (copied from slime_pengoo.py): big decal that follows the curve
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
    return separate(keep(o, False), frame, on, off=off)


OR, OR_D, OR_L = hexc("ff8a1e"), hexc("c8461a"), hexc("ffb45a")
BELLY, PINK, GREEN, TEAL = hexc("fbfdff"), hexc("ff9fb8"), hexc("6fe8c8"), hexc("2a6fd0")


def paint(a, z, p):
    return mix(OR, OR_L, 0.45 * smoothstep(1.3, 2.6, z))


b = Body([(0, 1.12), (0.15, 1.42), (0.55, 1.58), (1.15, 1.5), (1.8, 1.2), (2.3, 0.74), (2.62, 0.25), (2.72, 0)],
         paint=paint, sx=1.04, sy=1.06, segs=40, sub=3, gloss=0.55,
         lean=lambda z: 0.1 * max(0.0, (z - 1.5) / 1.2) ** 2)
parts = [b.obj]

# Pengoo's heart bib, white belly reaching up into the grin
right = [(0.0, 1.5), (0.22, 1.66), (0.5, 1.68), (0.74, 1.52), (0.88, 1.25), (0.98, 0.9), (0.96, 0.55),
         (0.8, 0.34), (0.45, 0.24), (0.0, 0.22)]
right = catmull(right, 4)
bib = right + [(-u, v) for u, v in reversed(right[1:-1])]
parts.append(register(grid_decal("Bib", list(reversed(bib)), BELLY, FRONT, off=0.012, th=0.01, on=["Body"], cell=0.15), "Bib"))  # the face sits on the bib, not under it

# tabby stripes over the back and flanks
for yaw in (78, 108, 140, 180, 220, 252, 282):
    w = 0.28 if abs(yaw - 180) < 50 else 0.22
    poly = [(-w, 0.75), (-w * 0.3, 0.8), (w * 0.3, 0.8), (w, 0.75), (0.04, -0.55), (-0.04, -0.55)]
    parts.append(decal(f"Stripe{yaw}", poly, OR_D, frame_at(yaw, 1.75, tilt=22), off=0.01, th=0.015, on=["Body"], step=0.22))
for k, (u, rot, ln) in enumerate(((-0.24, 14, 0.3), (0.0, 0, 0.38), (0.24, -14, 0.3))):
    top = 2.42 if k == 1 else 2.35
    poly = [(-0.08, 0), (0.08, 0), (0.02, -ln), (-0.02, -ln)]
    c, sn = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    poly = [(u + x * c - y * sn, top + x * sn + y * c) for x, y in poly]
    parts.append(decal(f"M{k}", poly, OR_D, FRONT, off=0.01, th=0.015, on=["Body"]))

# cat ears (pink inner), tilted out
for sd in (-1, 1):
    t = math.radians(-sd * 24)
    X = (math.cos(t), 0, math.sin(t))
    Y = (-math.sin(t), 0, math.cos(t))
    parts.append(puffy_slab(f"Ear{sd}", [(-0.38, 0), (0.38, 0), (0.07, 0.82), (-0.04, 0.82)], 0.24,
                            (sd * 0.82, -0.12, 1.98), X, Y, zgrad(OR, OR_D, 2.1, 2.8)))
    parts.append(puffy_slab(f"EarIn{sd}", [(-0.24, 0.1), (0.24, 0.1), (0.03, 0.64)], 0.08,
                            (sd * 0.82, -0.26, 2.0), X, Y, PINK))

# shark dorsal fin with a bite notch, behind the ears
fin = [(-0.6, 0), (0.55, 0), (0.62, 0.32), (0.75, 0.45), (0.62, 0.6), (0.66, 0.85), (0.88, 1.35),
       (0.6, 1.3), (0.12, 0.95), (-0.32, 0.5)]
parts.append(puffy_slab("Fin", fin, 0.3, (0, 0.55, 2.2), (0, 1, 0), (0, 0, 1), zgrad(OR_D, OR, 2.3, 3.3)))

# crescent tail fin, orange with dark tips
tail = [(0, -0.3), (0.6, -0.6), (1.15, -0.95), (0.85, -0.3), (0.72, 0), (1.0, 0.6), (1.3, 1.25),
        (0.65, 0.68), (0, 0.32)]
parts.append(puffy_slab("Tail", tail, 0.22, (0, 1.35, 0.62), (0, 1, 0.25), (0, -0.25, 1),
                        along(OR, OR_D, (0, 1.4, 0.6), (0, 2.3, 0.6))))

# Pengoo-style flipper pecs
for sd in (-1, 1):
    pec = [(0, -0.24), (0.55, -0.42), (0.98, -0.62), (0.58, -0.05), (0.15, 0.22)]
    parts.append(puffy_slab(f"Pec{sd}", pec, 0.16, (sd * 1.45, -0.2, 0.55), (sd, 0.2, -0.4), (0, 1, 0),
                            zgrad(OR_D, OR, 0.0, 0.7)))

# whisker barbels: long drooping catfish feelers from the muzzle, curling at the tip
for sd in (-1, 1):
    p0 = Vector((sd * 0.36, -1.52, 1.2))
    pts = [p0 + Vector((-sd * 0.12, 0.12, 0)), p0, p0 + Vector((sd * 0.4, -0.12, 0.08)), p0 + Vector((sd * 0.85, -0.12, 0.05)),
           p0 + Vector((sd * 1.2, -0.02, -0.15)), p0 + Vector((sd * 1.38, 0.05, -0.45)), p0 + Vector((sd * 1.32, 0.05, -0.68)),
           p0 + Vector((sd * 1.18, 0.02, -0.74))]
    parts.append(horn(f"Barbel{sd}", pts, [0.12, 0.11, 0.095, 0.08, 0.068, 0.058, 0.05, 0.045], OR_D, hexc("ffd9a0"), segs=6))

f = Face(b, eye_v=1.66, mouth_v=1.12, eye_u=0.52, on=["Body", "Bib"])
f.eyes("sly", w=0.5, h=0.64, iris=GREEN)
f.nose(color=PINK, w=0.2, h=0.13, v=1.36)
# sly lopsided grin with two fangs
mv = 1.12
W = 0.4
top = [(W * (k / 8 - 1), mv + 0.12 * (k / 8 - 1) ** 2 + 0.03 * (k / 8 - 1)) for k in range(17)]
bot = [(W * (k / 8 - 1), mv + 0.12 * (k / 8 - 1) ** 2 + 0.03 * (k / 8 - 1) - 0.2 * (1 - (k / 8 - 1) ** 2)) for k in range(15, 0, -1)]
f.d("Mouth", top + bot, MOUTH)
for sd in (-1, 1):
    f.d(f"Fang{sd}", [(sd * 0.09, mv + 0.005), (sd * 0.22, mv + 0.03), (sd * 0.15, mv - 0.14)], WHITE, off=0.04, th=0.012)
f.cheeks(color=hexc("ff8fa8"), u=0.92, v=1.3)
parts += f.parts
ship("slime_catfish", parts)
