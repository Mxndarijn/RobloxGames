# Prism (Mythic): rainbow unicorn slime riding its own cloud. Rainbow bands, a twisted gold/pearl
# horn, a flowing pastel mane and tail, big sparkly anime eyes, a delighted open smile.
from models._slimepool import *

RAINBOW = [hexc("a978ff"), hexc("5ab8ff"), hexc("4fe3a0"), hexc("ffe14d"), hexc("ffa64d"), hexc("ff6b9a")]
MANE = [hexc("ff7cc8"), hexc("fff0fa"), hexc("b994ff"), hexc("fff0fa"), hexc("8fdcff")]
CLOUD, CLOUD_D = hexc("ffffff"), hexc("d9d4ff")
Z0 = 0.5  # body sits on the cloud


def rainbow(a, z, p):
    t = min(0.999, max(0.0, (z - Z0) / 2.45)) * (len(RAINBOW) - 1)
    i = int(t)
    return mix(RAINBOW[i], RAINBOW[i + 1], smoothstep(0.25, 0.75, t - i))


b = Body([(Z0, 1.05), (Z0 + 0.15, 1.35), (Z0 + 0.5, 1.5), (Z0 + 1.1, 1.45), (Z0 + 1.8, 1.12), (Z0 + 2.35, 0.6), (Z0 + 2.6, 0)],
         paint=rainbow, lean=lambda z: 0.15 * max(0.0, (z - 2.0) / 1.1) ** 2)
parts = [b.obj]
H = b.H

# the cloud: a ring of puffs under and around the body
puffs = [((0, 0, 0.32), 0.55, (2.4, 2.2, 0.75))]
for k in range(9):
    a = k * math.tau / 9 + 0.2
    r = 1.45 + 0.12 * math.sin(k * 2.3)
    puffs.append(((math.cos(a) * r, math.sin(a) * r * 0.95, 0.38 + 0.05 * math.cos(k * 1.7)), 0.45 + 0.08 * math.sin(k * 1.3)))
parts.append(goo("Cloud", puffs, lambda p, n: mix(CLOUD_D, CLOUD, smoothstep(0.1, 0.6, p.z)), tris=650, resolution=0.1))


def twisted_horn(name, base, axis, length, r0, segs=6, rings=10, c_a=GOLD_L, c_b=WHITE):
    """spiral unicorn horn: each ring is turned one step, faces striped by (seg - ring) -> spiral bands"""
    d = Vector(axis).normalized()
    q = d.to_track_quat("Z", "Y")
    bm = bmesh.new()
    R = []
    for j in range(rings):
        t = j / rings
        rr = r0 * (1 - t) ** 0.9
        R.append([bm.verts.new(Vector(base) + q @ Vector((math.cos(k * math.tau / segs + j * math.tau / segs * 0.5) * rr,
                                                           math.sin(k * math.tau / segs + j * math.tau / segs * 0.5) * rr, t * length)))
                  for k in range(segs)])
    tip = bm.verts.new(Vector(base) + q @ Vector((0, 0, length)))
    fc = []
    for j in range(rings - 1):
        for k in range(segs):
            fc.append((bm.faces.new((R[j][k], R[j][(k + 1) % segs], R[j + 1][(k + 1) % segs], R[j + 1][k])), (k - j // 2) % segs < segs // 2))
    for k in range(segs):
        fc.append((bm.faces.new((R[-1][k], R[-1][(k + 1) % segs], tip)), True))
    fc.append((bm.faces.new(list(reversed(R[0]))), True))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    for f, stripe in fc:
        for lp in f.loops:
            lp[col] = c_a if stripe else c_b
    return keep(obj_from_bm(name, bm), False)


hb = (0, -0.62, H - 0.42)
parts.append(twisted_horn("Horn", hb, (0, -0.42, 1), 1.65, 0.3, rings=12))
# ears either side of the horn
for sd in (-1, 1):
    ear = [(-0.26, 0), (0.26, 0), (0.12, 0.42), (0.02, 0.72), (-0.12, 0.4)]
    X, Y = (1, 0, -sd * 0.35), (sd * 0.55, 0.05, 1)
    parts.append(puffy_slab(f"Ear{sd}", ear, 0.16, (sd * 0.95, -0.05, H - 0.75), X, Y, hexc("fff4fb")))
    parts.append(puffy_slab(f"EarIn{sd}", [(-0.14, 0.08), (0.14, 0.08), (0.06, 0.38), (0.01, 0.55), (-0.07, 0.36)], 0.1, (sd * 0.95, -0.11, H - 0.75), X, Y, hexc("ff8fc6")))

# mane: a row of pastel locks from the forelock over the crown and down the back
mane = []
locks = []
for k in range(9):
    t = k / 8
    ang = math.radians(8 + t * 135)  # angle in the yz plane from the top
    zc = Z0 + 1.35 + math.cos(ang) * 1.38
    yc = math.sin(ang) * 1.32 + 0.12
    r = 0.4 - 0.12 * t
    locks.append(((0, yc, zc), r, MANE[k % len(MANE)]))
    mane.append(((0, yc, zc), r, (1.35, 1.0, 1.0)))
    for sd in (-1, 1):
        mane.append(((sd * 0.28, yc + 0.05, zc - 0.08), r * 0.75))
        locks.append(((sd * 0.28, yc + 0.05, zc - 0.08), r * 0.75, MANE[(k + 2) % len(MANE)]))


def nearest_col(L):
    def fn(p, n):
        return min(L, key=lambda e: (p - Vector(e[0])).length - e[1])[2]
    return fn


parts.append(goo("Mane", mane, nearest_col(locks), tris=740, resolution=0.09))
# tail: three curls at the back, near the cloud
tail = [((0, 1.55, 0.95), 0.3, MANE[0]), ((0.1, 1.85, 1.15), 0.26, MANE[1]), ((0.2, 2.0, 1.45), 0.22, MANE[2]), ((0.12, 1.95, 1.72), 0.18, MANE[3])]
parts.append(goo("Tail", [(c, r) for c, r, _ in tail], nearest_col(tail), tris=400, resolution=0.08))

# sparkle stars around the cloud
for k, (x, y, z, s, rot) in enumerate([(-1.9, -0.6, 1.4, 0.26, 0.3), (1.95, -0.3, 2.2, 0.2, -0.2), (-1.5, 0.4, 2.7, 0.17, 0.5), (1.7, 0.6, 0.95, 0.18, 0.1)]):
    parts.append(slab(f"Star{k}", star(0, 0, s, s * 0.45), 0.08, (x, y, z), (math.cos(rot) * 0.8, 0.6 * (1 if x < 0 else -1), math.sin(rot)), (-math.sin(rot), 0, math.cos(rot)), GOLD))

f = Face(b, eye_u=0.52, eye_v=Z0 + 1.35, mouth_v=Z0 + 0.82)
f.eyes("sparkle", w=0.44, h=0.56, iris=hexc("ff6fcf")).mouth("open", w=0.9).cheeks(color=hexc("ff8fbf"))
parts += f.parts
ship("slime_prism", parts)
