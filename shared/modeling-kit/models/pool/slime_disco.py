# Disco (Secret): a mirror-ball party slime. The body is a real mirror-ball grid of flat-shaded
# square tiles over dark grout (fewer tiles per ring towards the top, like a real disco ball):
# silver with scattered pink, cyan, gold and purple reflection tiles and white sparkle tiles.
# Star-shaped shades, big DJ headphones, a groovy open grin, floating music notes and sparkles.
import hashlib
from models._slimepool import *

GROUT = hexc("1c1830")
SILVER_D, SILVER, SILVER_L = hexc("7c8296"), hexc("c4cad8"), hexc("f4f6ff")
REFL = [hexc("ff4fd8"), hexc("36e6ff"), hexc("ffd23a"), hexc("a66bff")]
SHADE_F, SHADE_L = hexc("ff3fb4"), hexc("2a1a40")
PH_D, PH, PH_RIM = hexc("221c30"), hexc("3a3150"), hexc("36e6ff")
NOTE_C = [hexc("ff4fd8"), hexc("36e6ff"), hexc("ffd23a")]
PROFILE = [(0.0, 1.1), (0.3, 1.45), (1.2, 1.64), (2.2, 1.38), (2.85, 0.75), (3.1, 0.0)]
TILE = 0.3    # tile pitch (studs)
TILE_H = 0.05  # tile height above the grout core


def h01(*k):
    return int(hashlib.md5(repr(k).encode()).hexdigest()[:8], 16) / 0xFFFFFFFF


def set_face_col(bm, f, c):
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for lp in f.loops:
        lp[col] = c


prof = catmull(PROFILE, 8)


def R(z):
    for (z0, r0), (z1, r1) in zip(prof, prof[1:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-9)
    return prof[-1][1] if z > prof[-1][0] else prof[0][1]


def P(a, z, extra=0.0):
    r = R(z) + extra
    return Vector((math.sin(a) * r, -math.cos(a) * r, z))


# rings at equal arc length along the profile so tiles come out square
arc = [0.0]
for (z0, r0), (z1, r1) in zip(prof, prof[1:]):
    arc.append(arc[-1] + math.hypot(z1 - z0, r1 - r0))
L = arc[-1]


def z_at(s):
    for k in range(len(arc) - 1):
        if arc[k] <= s <= arc[k + 1]:
            t = (s - arc[k]) / max(arc[k + 1] - arc[k], 1e-9)
            return prof[k][0] + (prof[k + 1][0] - prof[k][0]) * t
    return prof[-1][0]


# grout core (dark, smooth enough) and the outer surface for decals
core = lathe("Body", catmull(PROFILE, 2), GROUT, segs=20, smooth=True)
outer = lathe("Outer", [(z, r + TILE_H + 0.005) if r > 0 else (z, r) for z, r in prof], GROUT, segs=40, smooth=True)
register(outer, "Outer")
bpy.data.objects.remove(outer)

parts = [core]

# tiles: ring by ring, tile count per ring from the ring's circumference
bm = bmesh.new()
s0 = 0.22  # skip the very bottom (sits on the floor) - start a little up the foot
nrings = int((L - s0) / TILE)
ds = (L - s0) / nrings
gap = 0.04
light = Vector((-0.4, -0.55, 0.75)).normalized()
for k in range(nrings):
    sa, sb = s0 + k * ds + gap / 2, s0 + (k + 1) * ds - gap / 2
    za, zb = z_at(sa), z_at(sb)
    rm = R((za + zb) / 2)
    if rm < 0.12:
        continue
    n = max(4, int(round(math.tau * rm / TILE)))
    rot = h01("ring", k) * math.tau
    da = math.tau / n
    ga = gap / max(rm, 0.2)
    for i in range(n):
        a0, a1 = rot + i * da + ga / 2, rot + (i + 1) * da - ga / 2
        base = [P(a0, za), P(a1, za), P(a1, zb), P(a0, zb)]
        nrm = ((base[1] - base[0]).cross(base[3] - base[0])).normalized()
        cen = sum(base, Vector()) / 4
        if nrm.dot(cen - Vector((0, 0, cen.z))) < 0 and nrm.z < 0.99:
            nrm = -nrm
        hi = [bm.verts.new(p + nrm * TILE_H) for p in base]
        apex = bm.verts.new(cen - nrm * 0.12)  # closed pyramid: 6 tris per tile, apex hidden in the core
        # colour: silver mirror that reflects the room, some coloured reflection tiles, sparkles
        hsh = h01("t", k, i)
        up = max(0.0, nrm.dot(light))
        c = mix(SILVER_D, SILVER_L, min(1.0, 0.1 + 0.6 * h01("v", k, i) + 0.5 * up))
        if hsh < 0.17:
            c = mix(REFL[int(h01("c", k, i) * len(REFL))], WHITE, 0.12 * up)
        elif hsh > 0.94:
            c = WHITE
        if cen.z < 0.45:
            c = shade(c, 0.8)
        ft = bm.faces.new(hi)
        set_face_col(bm, ft, c)
        for j in range(4):
            jj = (j + 1) % 4
            f = bm.faces.new((hi[jj], hi[j], apex))
            set_face_col(bm, f, shade(c, 0.6))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.triangulate(bm, faces=bm.faces)
parts.append(keep(obj_from_bm("Tiles", bm), False))


# ---------------------------------------------------------------- face
def ddecal(name, poly, color, frame=FRONT, off=0.02, th=0.025, on=None, rings=4):
    """decal with a subdivided cap (copied from slime_froggo.py) so wide decals hug the curve."""
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


EV, MV = 1.72, 1.05
# groovy open grin: wide D mouth, white top teeth, pink tongue
mw, mh = 1.0, 0.5
parts.append(ddecal("Mouth", half_oval(0, MV + 0.12, mw, mh, n=16), hexc("5a0f3a"), on=["Outer"], off=0.0, th=0.03))
parts.append(ddecal("Teeth", [(-0.43, MV + 0.115), (0.43, MV + 0.115), (0.38, MV + 0.0), (-0.38, MV + 0.0)], WHITE, on=["Outer"], off=0.03, th=0.012, rings=2))
parts.append(ddecal("Tongue", half_oval(0, MV - 0.2, 0.44, 0.15, n=12), hexc("ff6aa0"), on=["Outer"], off=0.03, th=0.012, rings=2))

# star-shaped shades: two pink star frames with dark star lenses, a bridge and glints
yf = -R(EV) - TILE_H - 0.1
for sd in (-1, 1):
    O = Vector((sd * 0.56, yf + 0.1, EV))
    X = Vector((math.cos(math.radians(18 * sd)), math.sin(math.radians(18 * sd)), 0))
    Z = Vector((0, 0, 1))
    parts.append(slab(f"ShadeF{sd}", star(0, 0, 0.52, 0.27, rot=90), 0.07, O, X, Z, SHADE_F))
    parts.append(slab(f"ShadeL{sd}", star(0, 0, 0.4, 0.2, rot=90), 0.05, O - X.cross(Z) * 0.04, X, Z, SHADE_L))
    parts.append(slab(f"ShadeG{sd}", rect(-0.08, 0.06, 0.06, 0.26, math.radians(-35)), 0.02, O - X.cross(Z) * 0.07, X, Z, WHITE))
parts.append(slab("ShadeBridge", rect(0, 0, 0.36, 0.08), 0.06, (0, yf - 0.02, EV + 0.08), (1, 0, 0), (0, 0, 1), SHADE_F))

# DJ headphones: band over the top, big cups with neon rims on both sides
CZ = 1.85
band = []
for k in range(13):
    t = math.pi * k / 12
    band.append((math.cos(t) * (R(CZ) + 0.3), 0.15, CZ + 0.25 + math.sin(t) * (3.1 - CZ + 0.05)))
parts.append(horn("PhoneBand", band, [0.11] * 13, PH, PH, segs=8))
for sd in (-1, 1):
    x0 = sd * (R(CZ) - 0.05)
    parts.append(lathe(f"PhoneCup{sd}", [(0, 0.62), (0.32, 0.6), (0.42, 0.45), (0.44, 0.0)], PH_D,
                       pos=(x0, 0.15, CZ), axis=(sd, 0, 0), segs=20, smooth=True))
    parts.append(torus(f"PhoneRim{sd}", 0.52, 0.06, (x0 + sd * 0.33, 0.15, CZ), (1, 0, 0), PH_RIM, segs=24, rsegs=6))
    parts.append(lathe(f"PhoneCap{sd}", [(0, 0.3), (0.04, 0.3), (0.05, 0.0)], SHADE_F, pos=(x0 + sd * 0.42, 0.15, CZ), axis=(sd, 0, 0), segs=16, smooth=False))


# floating music notes (flat slabs) and sparkles
def note_poly():
    head = oval(0, 0, 0.3, 0.22, n=12, rot=math.radians(25))
    return head


for k, (pos, yaw, c, dbl) in enumerate((((-2.2, -0.4, 2.9), 25, NOTE_C[0], False), ((2.25, -0.5, 3.2), -25, NOTE_C[1], True),
                                         ((-2.45, 0.3, 1.2), 35, NOTE_C[2], True))):
    O = Vector(pos)
    X = Vector((math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0))
    Z = Vector((0, 0, 1))
    heads = [(0.0, 0.0)] + ([(0.42, 0.12)] if dbl else [])
    for j, (hx, hy) in enumerate(heads):
        parts.append(slab(f"NoteH{k}{j}", oval(hx, hy, 0.3, 0.22, n=12, rot=math.radians(25)), 0.08, O, X, Z, c))
        parts.append(slab(f"NoteS{k}{j}", rect(hx + 0.12, hy + 0.32, 0.055, 0.66), 0.06, O, X, Z, c))
    if dbl:
        parts.append(slab(f"NoteB{k}", [(0.09, 0.6), (0.57, 0.72), (0.57, 0.6), (0.09, 0.48)], 0.06, O, X, Z, c))
    else:
        parts.append(slab(f"NoteF{k}", [(0.09, 0.66), (0.15, 0.66), (0.38, 0.4), (0.33, 0.36), (0.15, 0.5), (0.09, 0.5)], 0.06, O, X, Z, c))

for k, (pos, r) in enumerate((((1.75, -1.1, 0.7), 0.24), ((-1.2, -1.35, 3.0), 0.2), ((1.3, -0.6, 3.45), 0.16), ((-1.9, -0.9, 0.5), 0.15))):
    parts.append(slab(f"Spark{k}", star(0, 0, r, r * 0.28, n=4), 0.05, pos, (1, 0, 0), (0, 0, 1), WHITE if k % 2 == 0 else hexc("fff38a")))

# mirror twinkles: big 4-point glints sitting proud on the ball where it catches the light
for k, (yaw, z, r) in enumerate(((-35, 2.55, 0.3), (-62, 1.25, 0.22), (40, 2.85, 0.2), (150, 2.2, 0.26))):
    a = math.radians(yaw)
    p = P(a, z, TILE_H + 0.06)
    nrm = Vector((math.sin(a), -math.cos(a), 0.35)).normalized()
    X = Vector((math.cos(a), math.sin(a), 0))
    Yv = nrm.cross(X)
    parts.append(slab(f"Twinkle{k}", star(0, 0, r, r * 0.22, n=4, rot=45 if k % 2 else 0), 0.03, p, X, Yv, WHITE))

ship("slime_disco", parts)
