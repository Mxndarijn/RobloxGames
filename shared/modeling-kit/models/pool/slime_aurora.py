# Aurora (Divine, tier 9): a dreamy northern-lights slime. A translucent-looking pearly body with
# pastel rainbow bands flowing diagonally across it, three long aurora ribbons (mint at the lower
# edge -> lilac -> pink at the upper edge, like light curtains) spiralling up round it and trailing
# high above the head, a tilted orbit of small floating prism crystals, a white-gold star crest
# floating over the crown, and a dreamy half-lidded smile.
from models._slimepool import *

# pastel bands (cyclic) for the body
BANDS = [hexc("ff9fd0"), hexc("c6a6ff"), hexc("8fcbff"), hexc("8ff0cc"), hexc("fff08a"), hexc("ffb994")]
PEARL = hexc("fffaff")
# aurora curtain colours: lower edge -> upper edge
AUR = [hexc("5cf5c0"), hexc("8ff0ff"), hexc("b9a6ff"), hexc("ff9fe0")]
GOLD_W = hexc("fff4c8")
IRIS_T, IRIS_B = hexc("7a6cff"), hexc("ff8fd8")


def band_col(t):
    t = t % 1.0 * len(BANDS)
    i = int(t)
    return mix(BANDS[i % len(BANDS)], BANDS[(i + 1) % len(BANDS)], smoothstep(0.3, 0.7, t - i))


def paint(a, z, p):
    # diagonal flow: bands run down-left to up-right across the front, with a soft wave
    t = (z * 0.5 + p.x * 0.36 + 0.08 * math.sin(p.y * 2.0 + z * 1.5)) / 1.0
    c = band_col(t)
    # translucent jelly: milky pearl glow in the upper core, brighter rim near the foot (light through it)
    c = mix(c, PEARL, 0.22 * smoothstep(1.8, 3.0, z))
    c = mix(c, PEARL, 0.25 * smoothstep(0.5, 0.0, z))
    return c


H = 3.0
b = Body([(0, 1.05), (0.13, 1.36), (0.5, 1.52), (1.1, 1.5), (1.8, 1.26), (2.45, 0.86), (2.85, 0.4), (H, 0)],
         paint=paint, segs=40, sub=2, gloss=1.0, lean=lambda z: 0.1 * max(0.0, (z - 2.2) / 0.8) ** 2)
parts = [b.obj]


# ---------------------------------------------------------------- aurora ribbons
def ribbon(name, path, width, thick=0.06, n=64, nsec=8):
    """flowing light-curtain ribbon: lens cross-section swept along path(s) -> point, facing out from
    the body axis; width(s) in studs; colour by position across the width (mint low edge -> pink top)."""
    pts = [path(k / (n - 1)) for k in range(n)]
    bm = bmesh.new()
    rings, across = [], []
    for k, p in enumerate(pts):
        tng = (pts[min(k + 1, n - 1)] - pts[max(k - 1, 0)]).normalized()
        out = Vector((p.x, p.y, 0))
        out = out.normalized() if out.length > 1e-4 else Vector((0, 1, 0))
        out = (out - tng * out.dot(tng)).normalized()
        side = Vector((0, 0, 1)) - tng * tng.z  # vertical curtain where the path runs flat (no twist)
        side = side.normalized() if side.length > 0.35 else out.cross(tng).normalized()
        out = tng.cross(side).normalized() * (1 if tng.cross(side).dot(out) > 0 else -1)
        if side.z < 0:
            side = -side
        w = width(k / (n - 1))
        ring = []
        for j in range(nsec):
            th = j * math.tau / nsec
            ring.append(bm.verts.new(p + side * math.cos(th) * w / 2 + out * math.sin(th) * thick / 2))
            across.append(0.5 + 0.5 * math.cos(th))
        rings.append(ring)
    for a, c in zip(rings, rings[1:]):
        for j in range(nsec):
            bm.faces.new((a[j], a[(j + 1) % nsec], c[(j + 1) % nsec], c[j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    idx = {v: i for i, v in enumerate(v for r in rings for v in r)}
    for f in bm.faces:
        for lp in f.loops:
            i = idx[lp.vert]
            s = (i // nsec) / (n - 1)
            u = across[i]
            seg = u * (len(AUR) - 1)
            m = int(min(seg, len(AUR) - 1.001))
            c = mix(AUR[m], AUR[m + 1], seg - m)
            c = mix(c, WHITE, 0.35 * smoothstep(0.75, 1.0, s))  # tips fade to light
            lp[col] = c
    return keep(obj_from_bm(name, bm), True)


def spiral(y0, y1, z0, z1, r0, r1, wave=0.0, phase=0.0, zpow=1.0, flare=0.0):
    def fn(s):
        yaw = math.radians(y0 + (y1 - y0) * s)
        r = r0 + (r1 - r0) * s + wave * math.sin(s * math.tau * 1.5 + phase) + flare * smoothstep(0.6, 1.0, s)
        z = z0 + (z1 - z0) * s ** zpow + 0.18 * math.sin(s * math.tau * 2 + phase)
        return Vector((math.sin(yaw) * r, -math.cos(yaw) * r, z))
    return fn


def taper(wmax, a=0.12, b=0.35):
    return lambda s: wmax * smoothstep(0.0, a, s) * (1 - smoothstep(1 - b, 1.0, s)) * (0.7 + 0.3 * math.sin(s * 11)) + 0.03


def cpath(ctrl, wob=0.0, phase=0.0):
    """smooth path through (yaw deg, r, z) control points (Catmull-Rom), small vertical ripple."""
    P = [ctrl[0]] + list(ctrl) + [ctrl[-1]]
    nseg = len(ctrl) - 1

    def fn(s):
        x = min(nseg - 1e-6, s * nseg)
        i = int(x)
        t = x - i
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        q = [0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in range(3)]
        yaw = math.radians(q[0])
        z = q[2] + wob * math.sin(s * math.tau * 3 + phase)
        return Vector((math.sin(yaw) * q[1], -math.cos(yaw) * q[1], z))
    return fn


RA = [(-30, 1.8, 0.3), (-100, 1.9, 0.9), (-175, 1.85, 1.6), (-250, 1.7, 2.35), (-320, 1.55, 3.1), (-390, 1.6, 3.7),
      (-450, 1.95, 4.05), (-490, 2.3, 4.05)]
parts.append(ribbon("RibbonA", cpath(RA, 0.06), taper(0.6, a=0.1, b=0.3), n=90))
RB = [(-y, r, z + 0.35 * smoothstep(1.0, 3.0, z)) for y, r, z in RA]
parts.append(ribbon("RibbonB", cpath(RB, 0.06, 1.7), taper(0.6, a=0.1, b=0.3), n=90))

# ---------------------------------------------------------------- floating prism motes (tilted orbit)
OC = Vector((0, 0, 1.55))
tilt = math.radians(14)
MOTE = [hexc("ff9fe0"), hexc("8ff0ff"), hexc("b9a6ff"), hexc("5cf5c0"), hexc("fff2a8")]
for k in range(8):
    t = k * math.tau / 8 + 0.4
    x, y = math.cos(t) * 2.35, math.sin(t) * 2.0
    p = OC + Vector((x, y * math.cos(tilt), y * math.sin(tilt) + 0.25 * math.sin(3 * t)))
    c = MOTE[k % len(MOTE)]
    r = 0.13 if k % 2 else 0.17
    parts.append(gem(f"Mote{k}", tuple(p), r, c, h=r * 2.6, segs=5, axis=(0.2 * math.sin(t), 0.1, 1)))

# ---------------------------------------------------------------- white-gold star crest over the crown
CR = Vector((0, 0.1, H + 1.5))
parts.append(slab("Crest", star(0, 0, 0.6, 0.17, n=4), 0.12, CR, (1, 0, 0), (0, 0.25, 1),
                  lambda p, n: mix(GOLD, GOLD_W, smoothstep(0.35, 0.0, (p - CR).length))))
parts.append(slab("CrestB", star(0, 0, 0.36, 0.1, n=4, rot=45), 0.1, CR + Vector((0, -0.03, 0)), (1, 0, 0), (0, 0.25, 1), GOLD_W))

# white-gold twinkles round the crest and the swirl
for k, (x, y, z, r) in enumerate([(-0.75, 0.0, H + 1.75, 0.16), (0.7, 0.1, H + 1.95, 0.13), (0.45, -0.1, H + 1.15, 0.1), (-2.1, -0.4, 3.0, 0.16), (2.15, -0.2, 3.3, 0.14)]):
    parts.append(slab(f"Twinkle{k}", star(0, 0, r, r * 0.3, n=4), 0.05, (x, y, z), (1, 0, 0), (0, 0.2, 1), GOLD_W))

# ---------------------------------------------------------------- dreamy face
f = Face(b, eye_u=0.52, eye_v=1.62, mouth_v=1.18)
for sd in (-1, 1):
    f._eye_round(sd, 0.5, 0.62, lid=0.3, tilt=-0.18, iris=IRIS_T)
f.mouth("smile", w=1.1)
f.cheeks(color=hexc("ff9fcf"), w=0.32, h=0.15)
parts += f.parts

ship("slime_aurora", parts)
