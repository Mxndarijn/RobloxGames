# ranch_exclusive_carousel: the Exclusive Shop as a county-fair CAROUSEL. The exclusive pet mounts ride the wooden poles
# where the horses would be (the game places the real mount meshes on CAROUSEL_SPOTS and spins + bobs them), a gold
# trophy slime with a crown stands on the top, light bulbs ring the canopy and the centre drum. A ticket counter in
# front (10.4 wide, top z 4.1, like the other shops) holds the prompts and the sign. Front faces -Y.
# In-game split (later): the canopy/drum/platform part spins, the ticket counter stays; this concept is one mesh.
import math
import os
import bmesh
import bpy
from mathutils import Matrix, Vector
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import prism, gcyl, counter

LILAC = PALETTE["ranch_lilac"]
PLUM = LILAC                         # theme pass: palette ranch_lilac (was an off-palette plum)
PLUM_LO = mix(LILAC, ROOF_D, 0.3)    # lilac low, same recipe as the sibling shops
GOO = PALETTE["ranch_goo"]
GOO_HI = PALETTE["ranch_goo_hi"]
GOO_LO = mix(GOO, rgb(70, 170, 130), 0.5)
PLANK = mix(WOOD, CREAM, 0.12)
LILAC_HI = mix(LILAC, CREAM, 0.3)
GOLD = rgb(252, 204, 80)
GOLD_LO = rgb(232, 146, 46)
GOLD_HI = rgb(255, 236, 160)
BUTTER_LO = mix(BUTTER, GOLD_LO, 0.45)
RED = ROOF
PLAZA = PALETTE["ranch_plaza"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)

parts = []
SPOTS = []
CX, CYc = 0.0, 1.8                   # carousel centre (behind the ticket counter)
PR = 8.6                             # platform radius
PZ = 1.3                             # platform top
CZ = 10.6                            # canopy rim height
N = 8                                # poles / riders


def lathe(name, prof, pos, segs=24, col=CREAM, phase=0.0):
    bm = bmesh.new()
    x0, y0, z0 = pos
    rows = []
    for r, z in prof:
        if r < 1e-4:
            rows.append([bm.verts.new((x0, y0, z0 + z))])
        else:
            rows.append([bm.verts.new((x0 + math.cos(i * math.tau / segs + phase) * r, y0 + math.sin(i * math.tau / segs + phase) * r, z0 + z)) for i in range(segs)])
    for a, b in zip(rows, rows[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    for row in (rows[0], rows[-1]):
        if len(row) > 2:
            bm.faces.new(row)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


def paint(o, fn):
    lay = o.data.color_attributes["Col"]
    for p in o.data.polygons:
        col = fn(p.center, p.normal)
        for li in p.loop_indices:
            lay.data[li].color = (*col[:3], 1.0)


def gores(n, a, b, lo_a, lo_b, z0, z1):
    def fn(c, nrm):
        ang = math.atan2(c.y - CYc, c.x - CX)
        g = int(((ang + math.pi) / math.tau) * n) % 2
        t = min(1.0, max(0.0, (c.z - z0) / (z1 - z0)))
        return mix(lo_a, a, t) if g else mix(lo_b, b, t)
    return fn


def bulb(name, pos, r=0.2):
    return blob(name, r, pos, mix(BUTTER, CREAM, 0.4), subdiv=1, jitter=0)


# ---- platform: wood deck on a gold-trimmed lilac skirt, two steps at the front -----------------------------
skirt = lathe("Skirt", [(PR, 0), (PR, PZ - 0.35), (0, PZ - 0.35)], (CX, CYc, 0), segs=24, col=WOOD)
paint(skirt, gores(24, WOOD, PLANK, WOOD_LO, shade(PLANK, 0.85), 0, PZ))
parts.append(skirt)
parts.append(lathe("SkirtTrim", [(PR + 0.25, PZ - 0.5), (PR + 0.25, PZ - 0.2), (0, PZ - 0.2)], (CX, CYc, 0), segs=24, col=LILAC))
gradient(parts[-1], PLUM_LO, LILAC)
deck = lathe("Deck", [(PR - 0.1, PZ - 0.25), (PR - 0.1, PZ), (0, PZ)], (CX, CYc, 0), segs=24, col=PLAZA)
paint(deck, lambda c, n: mix(PLAZA, WOOD, 0.35) if int((math.atan2(c.y - CYc, c.x - CX) + math.pi) / math.tau * 24) % 2 else PLAZA)
parts.append(deck)
for k in range(0):                   # (skirt bulbs dropped for budget)
    a = k * math.tau / 12 + math.pi / 12
    parts.append(bulb(f"SkirtBulb{k}", (CX + math.cos(a) * (PR + 0.1), CYc + math.sin(a) * (PR + 0.1), PZ * 0.45), 0.22))

# ---- centre drum: plum column with cream-framed mirror panels and gold bands ------------------------------
DR = 2.4
drum = lathe("Drum", [(DR, PZ), (DR, CZ - 0.2), (0, CZ - 0.2)], (CX, CYc, 0), segs=12, col=WOOD)
paint(drum, gores(12, WOOD, PLANK, WOOD_LO, shade(PLANK, 0.88), PZ, CZ))
parts.append(drum)
for k in range(6):
    a = k * math.tau / 6 + math.pi / 12
    px, py = CX + math.cos(a) * (DR + 0.05), CYc + math.sin(a) * (DR + 0.05)
    yaw = math.degrees(a) + 90
    parts.append(bbox(f"PanelFrame{k}", (1.5, 0.2, 3.6), (px, py, PZ + 4.3), shade(CREAM, 0.85), CREAM, bev=0.06, rot=(0, 0, yaw)))
    parts.append(bbox(f"Panel{k}", (1.1, 0.2, 3.1), (px + math.cos(a) * 0.08, py + math.sin(a) * 0.08, PZ + 4.3), LILAC, mix(LILAC_HI, CREAM, 0.5), bev=0, rot=(0, 0, yaw)))
for z in (PZ + 1.6, PZ + 7.0):
    parts.append(lathe(f"DrumBand{z:.0f}", [(DR + 0.25, z - 0.3), (DR + 0.25, z + 0.3), (0, z + 0.3)], (CX, CYc, 0), segs=12, col=WOOD_D))
    gradient(parts[-1], shade(WOOD_D, 0.9), WOOD_D)
    for k in range(0):
        a = k * math.tau / 6
        parts.append(bulb(f"DrumBulb{z:.0f}{k}", (CX + math.cos(a) * (DR + 0.35), CYc + math.sin(a) * (DR + 0.35), z), 0.17))

# ---- poles with riders: twisted-gold poles; the mounts bob on them (alternate heights) ----------------------
RR = 6.1
for k in range(N):
    a = -math.pi / 2 + (k + 0.5) * math.tau / N
    px, py = CX + math.cos(a) * RR, CYc + math.sin(a) * RR
    parts.append(gcyl(f"Pole{k}", 0.24, CZ - PZ, (px, py, PZ), WOOD_LO, mix(WOOD, PLANK, 0.5), segs=6))
    for j in range(2):               # twist collars read as a barley-twist pole
        parts.append(gcyl(f"Collar{k}{j}", 0.3, 0.22, (px, py, PZ + 1.2 + j * 5.6), GOLD_LO, GOLD, segs=6))
    zt = PZ + (2.4 if k % 2 else 3.6)
    parts.append(gcyl(f"Saddle{k}", 0.55, 0.3, (px, py, zt - 0.3), GOLD_LO, GOLD, segs=6))
    SPOTS.append((px, py, zt, math.degrees(a) + 180.0))  # rider faces along the turning direction (tangent): yaw set in-game

# ---- canopy: plum / butter striped cone with a deep scalloped valance, bulbs round the rim -----------------
CR = PR + 0.6
can = lathe("Canopy", [(CR, 0), (CR - 0.2, 0.35), (CR * 0.62, 2.0), (CR * 0.34, 3.4), (CR * 0.14, 4.4), (0.5, 5.0), (0.0, 5.15)], (CX, CYc, CZ), segs=24, col=PLUM)
paint(can, gores(24, PLUM, BUTTER, PLUM_LO, BUTTER_LO, CZ - 1, CZ + 7))
parts.append(can)
parts.append(lathe("RimRoll", [(CR + 0.35, -0.4), (CR + 0.45, 0.1), (CR + 0.2, 0.4), (CR - 0.4, 0.4), (CR - 0.5, -0.4)], (CX, CYc, CZ), segs=24, col=GOLD))
gradient(parts[-1], GOLD_LO, GOLD)
for k in range(24):
    a = (k + 0.5) * math.tau / 24
    px, py = CX + math.cos(a) * (CR + 0.15), CYc + math.sin(a) * (CR + 0.15)
    col, lo = ((LILAC, PLUM_LO), (BUTTER, BUTTER_LO), (PINK, mix(PINK, ROOF, 0.35)))[k % 3]
    sc = cylinder(f"Val{k}", 1.05, 0.22, (px, py, CZ - 0.75), col, segs=6, rot=(90, 0, math.degrees(a) + 90))
    gradient(sc, mix(lo, col, 0.4), col)
    parts.append(sc)
    if k % 3 != 2:
        parts.append(bulb(f"RimBulb{k}", (CX + math.cos(a + math.pi / 24) * (CR + 0.5), CYc + math.sin(a + math.pi / 24) * (CR + 0.5), CZ + 0.05), 0.24))


def goo_ring(name, cx, cy, z0, Rr, n=48, seed=4, drip=(0.7, 2.0), thick=0.55):
    """Closed goo band poured over a round edge at radius Rr / height z0, with tapered drips hanging down."""
    import random
    rnd = random.Random(seed)
    tips = {}
    k = 0
    while k < n:
        tips[k] = rnd.uniform(*drip)
        k += rnd.choice((5, 6, 6, 7))
    d = [0.0] * n
    for i in range(n):
        for t, L in tips.items():
            gap = min((i - t) % n, (t - i) % n)
            d[i] = max(d[i], L * (1.0, 0.8, 0.3)[gap] if gap < 3 else 0.0)   # U-shaped, round-tipped drips
    loop = lambda di: [(Rr - thick, 0.62), (Rr + 0.3, 0.48), (Rr + 0.55, 0.05), (Rr + 0.58, -0.25 - di),
                       (Rr + 0.2, -0.32 - di * 0.92), (Rr - thick, 0.2)]
    bm = bmesh.new()
    rings = []
    for i in range(n):
        a = i * math.tau / n
        rings.append([bm.verts.new((cx + math.cos(a) * r, cy + math.sin(a) * r, z0 + z)) for r, z in loop(d[i])])
    m = len(rings[0])
    for i in range(n):
        A, B = rings[i], rings[(i + 1) % n]
        for j in range(m):
            jj = (j + 1) % m
            bm.faces.new((A[j], A[jj], B[jj], B[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, GOO)
    paint(o, lambda c, nrm: mix(GOO, GOO_HI, 0.55) if nrm.z > 0.8 else (GOO if c.z > z0 - 0.2 else mix(GOO_LO, GOO, min(1, max(0, (c.z - z0 + 2.2) / 2.0)))))
    return o


parts.append(goo_ring("CanopyGoo", CX, CYc, CZ, CR, n=72, seed=4))

# pennant ring round the canopy shoulder
for k in range(8):
    a = k * math.tau / 8
    r = CR * 0.34
    px, py, pz = CX + math.cos(a) * r, CYc + math.sin(a) * r, CZ + 3.4
    parts.append(gcyl(f"FlagPole{k}", 0.09, 1.7, (px, py, pz), WOOD_LO, WOOD, segs=4))
    col = (RED, BUTTER, LILAC_HI, BUTTER)[k % 4]
    fl = prism(f"Flag{k}", [(0, 0.0), (0, 0.7), (1.1, 0.35)], -0.06, 0.06, shade(col, 0.85), col)
    fl.data.transform(Matrix.Translation((px, py, pz + 0.95)) @ Matrix.Rotation(a + math.pi / 2, 4, "Z"))
    parts.append(fl)

# ---- topper: gold plinth + the game's own slime as a gold trophy, wearing the crown accessory ----------------
TZ = CZ + 5.0
parts.append(gcyl("TopPlinth", 1.5, 0.7, (CX, CYc, TZ - 0.1), GOLD_LO, GOLD, segs=12, r_top=1.25))
parts.append(gcyl("TopPlinth2", 1.0, 0.4, (CX, CYc, TZ + 0.6), PLUM_LO, PLUM, segs=12))
parts.append(goo_ring("TopGoo", CX, CYc, TZ + 0.45, 1.25, n=40, seed=9, drip=(0.3, 0.8), thick=1.1))
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out")


def _load(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(OUT, name + ".fbx"), axis_forward="-Z", axis_up="Y")
    got = []
    for o in set(bpy.data.objects) - before:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
            continue
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.parent = None
        bpy.context.view_layer.update()
        o.data.transform(o.matrix_world)
        o.matrix_world.identity()
        o.vertex_groups.clear()
        if o.data.shape_keys:
            o.shape_key_clear()
        o.data.materials.clear()
        if "Col" not in o.data.color_attributes:
            for ca in list(o.data.color_attributes):
                ca.name = "Col"
                break
        if "Col" not in o.data.color_attributes:
            o.data.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        for extra in [c for c in o.data.color_attributes if c.name != "Col"]:
            o.data.color_attributes.remove(extra)
        got.append(o)
    return got


def import_fbx(names, scale, pos, col_fns):
    """Import several FBXs that share one frame (body + face decal); fit them by the FIRST one's bbox.
    col_fns[i] = None keeps that mesh's own vertex colours."""
    groups = [_load(n) for n in names]
    vs = [v.co.copy() for o in groups[0] for v in o.data.vertices]
    span = max(max(v.x for v in vs) - min(v.x for v in vs), max(v.z for v in vs) - min(v.z for v in vs))
    k = scale / span
    cx = (min(v.x for v in vs) + max(v.x for v in vs)) / 2
    cy = (min(v.y for v in vs) + max(v.y for v in vs)) / 2
    z0 = min(v.z for v in vs)
    out = []
    for objs, fn in zip(groups, col_fns):
        for o in objs:
            o.data.transform(Matrix.Translation(pos) @ Matrix.Scale(k, 4) @ Matrix.Translation((-cx, -cy, -z0)))
            if fn:
                paint(o, fn)
            out.append(o)
    return out


L = Vector((-0.45, -0.65, 0.6)).normalized()


def gold_shine(c, n):
    d = n.dot(L)
    SG, SG_LO, SG_HI = rgb(244, 168, 36), rgb(214, 116, 30), rgb(255, 222, 110)   # deep trophy gold (big surface)
    base = mix(SG_LO, SG, min(1, max(0, (c.z - TZ - 0.4) / 2.6)))
    return mix(base, SG_HI, 0.75) if d > 0.8 else (mix(base, SG_LO, 0.5) if d < -0.1 else base)


slime = import_fbx(["slime_base"], 3.8, (CX, CYc, TZ + 1.0), [gold_shine])
for o in slime:
    decimate(o, 0.55)
parts += slime
sz = max((v.co.z for o in slime for v in o.data.vertices))
from mathutils.bvhtree import BVHTree
_bm = bmesh.new()
for o in slime:
    _bm.from_mesh(o.data)
_tree = BVHTree.FromBMesh(_bm)


def on_face(dx, dz, lift=0.05):
    hit = _tree.ray_cast(Vector((CX + dx, CYc - 20, TZ + 1.0 + dz)), Vector((0, 1, 0)))
    loc, nrm = hit[0], hit[1]
    return loc + nrm * lift, nrm


EYE = rgb(70, 46, 40)
for sx in (-1, 1):
    pos, nrm = on_face(sx * 0.62, 1.35)
    e = blob(f"Eye{sx}", 0.3, tuple(pos), EYE, subdiv=2, squash=(0.8, 0.35, 1.15), jitter=0)
    parts.append(e)
    hp, _ = on_face(sx * 0.62 - 0.08, 1.5, 0.2)
    parts.append(blob(f"EyeHi{sx}", 0.1, tuple(hp), CREAM, subdiv=1, squash=(1, 0.5, 1), jitter=0))
    bp, _ = on_face(sx * 1.05, 0.95, 0.03)
    parts.append(blob(f"Blush{sx}", 0.24, tuple(bp), mix(PINK, GOLD, 0.25), subdiv=1, squash=(1.3, 0.3, 0.75), jitter=0))
smile = []
for i in range(7):
    t = (i / 6) * 2 - 1
    sp, _ = on_face(t * 0.42, 0.95 - 0.22 * (1 - t * t), 0.04)
    smile.append(tuple(sp))
parts.append(tube("Smile", smile, [0.08] * 7, EYE, segs=5))
parts += import_fbx(["slime_acc_crown"], 2.1, (CX, CYc - 0.15, sz - 0.45), [None])   # keeps its own gold + gems

# marquee crest on the canopy front (SurfaceGui "EXCLUSIVE" on the face), leaning back with the cone
SZ = 1.1
arch = [(-4.6, SZ - 1.1), (4.6, SZ - 1.1), (4.6, SZ + 0.7)] +        [(math.cos(math.radians(a)) * 4.6, SZ + 0.7 + math.sin(math.radians(a)) * 1.3) for a in range(15, 166, 15)] + [(-4.6, SZ + 0.7)]
inner = [(x * 0.9, SZ + (z - SZ) * 0.78) for x, z in arch]
LEAN = Matrix.Translation((CX, CYc - CR + 0.9, CZ - 0.1)) @ Matrix.Rotation(math.radians(-28), 4, "X")
for nm, pts, y0, y1, lo, hi in (("SignBoard", arch, -0.25, 0.25, GOLD_LO, GOLD), ("SignFace", inner, -0.45, -0.2, PLUM, mix(PLUM, LILAC, 0.5))):
    o = prism(nm, pts, y0, y1, lo, hi)
    o.data.transform(LEAN)
    gradient(o, lo, hi)
    parts.append(o)
for k in range(11):
    a = math.radians(10 + k * 16)
    b = blob(f"SignBulb{k}", 0.22, (math.cos(a) * 4.78, -0.35, SZ + 0.7 + math.sin(a) * 1.45), mix(BUTTER, CREAM, 0.4), subdiv=1, jitter=0)
    b.data.transform(LEAN)
    parts.append(b)
# ---- ticket kiosk at the front-right, angled to the plaza (counter top z 4.1 like the other shops; prompts here)
# It stands off the platform so the riders stay in view from the front.
KW, CD, CH = 6.4, 3.0, 3.6
kiosk = counter("K", KW, 0.0, CD, CH, WOOD, PLUM_LO, PLUM, shade(mix(WOOD, PLAZA, 0.35), 0.85), mix(WOOD, PLAZA, 0.35), np_=6)
st = [(math.cos(math.radians(90 + i * 36)) * (0.7 if i % 2 == 0 else 0.3), CH - 1.35 + math.sin(math.radians(90 + i * 36)) * (0.7 if i % 2 == 0 else 0.3)) for i in range(10)]
kiosk.append(gcyl("Medal", 0.9, 0.25, (0, -CD / 2 - 0.35, CH - 1.35), GOLD_LO, GOLD, segs=12, rot=(90, 0, 0)))
kiosk.append(prism("MedalStar", st, -CD / 2 - 0.62, -CD / 2 - 0.42, PLUM_LO, LILAC_HI))
for sx in (-1, 1):                    # two candy-striped posts + a little scalloped awning
    kiosk.append(gcyl(f"KPost{sx}", 0.4, 7.4, (sx * (KW / 2 - 0.2), CD / 2 - 0.3, 0), WOOD_LO, WOOD, segs=8))
    kiosk.append(blob(f"KKnob{sx}", 0.45, (sx * (KW / 2 - 0.2), CD / 2 - 0.3, 7.6), GOLD, subdiv=2, jitter=0))
for k in range(5):
    x = -KW / 2 + KW * (k + 0.5) / 5
    col, lo = (PLUM, PLUM_LO) if k % 2 else (BUTTER, BUTTER_LO)
    kiosk.append(bbox(f"KAwn{k}", (KW / 5 + 0.02, 3.6, 0.3), (x, -0.2, 6.9), lo, col, bev=0, rot=(14, 0, 0)))
    sc = cylinder(f"KScal{k}", KW / 10 - 0.02, 0.22, (x, -2.0, 6.15), col, segs=8, rot=(90, 0, 0))
    gradient(sc, mix(lo, col, 0.4), col)
    kiosk.append(sc)
KM = Matrix.Translation((9.4, -6.4, 0)) @ Matrix.Rotation(math.radians(32), 4, "Z")
for o in kiosk:
    o.data.transform(KM)
parts += kiosk

# ---- velvet queue rope on the left, framing the walk-up to the riders --------------------------------------
posts = [(-8.6, -6.2), (-5.4, -8.2), (-2.2, -9.0)]
for k, (px, py) in enumerate(posts):
    parts.append(gcyl(f"RopePost{k}", 0.22, 2.6, (px, py, 0.3), GOLD_LO, GOLD, segs=6))
    parts.append(gcyl(f"RopeBase{k}", 0.55, 0.3, (px, py, 0), GOLD_LO, GOLD, segs=8))
    parts.append(blob(f"RopeKnob{k}", 0.32, (px, py, 3.0), GOLD, subdiv=1, jitter=0))
for k in range(len(posts) - 1):
    (ax, ay), (bx, by) = posts[k], posts[k + 1]
    rope = [(ax + (bx - ax) * t, ay + (by - ay) * t, 2.7 - 0.7 * math.sin(math.pi * t)) for t in (i / 6 for i in range(7))]
    parts.append(tube(f"Rope{k}", rope, [0.16] * 7, RED, segs=5))

# ---- display spots in the finished mesh frame ---------------------------------------------------------------
xs, ys, zs = [], [], []
for o in parts:
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        xs.append(w.x); ys.append(w.y); zs.append(w.z)
OFF = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs))
CAROUSEL_CENTRE = (round(CX - OFF[0], 2), round(CYc - OFF[1], 2), round(PZ - OFF[2], 2))
CAROUSEL_SPOTS = [(round(x - OFF[0], 2), round(y - OFF[1], 2), round(z - OFF[2], 2), round(yaw, 1)) for x, y, z, yaw in SPOTS]
print("CAROUSEL_CENTRE", CAROUSEL_CENTRE, "SPOTS", CAROUSEL_SPOTS)

# ---- split for the game: a spinning part (deck, drum, poles, saddles) and a static part (everything else) ------
# CAROUSEL_PART=spin|static picks one (models/ranch_exclusive_carousel_spin.py / _static.py); empty = the whole look.
import json

SPIN_PREFIXES = ("Deck", "Drum", "Panel", "Pole", "Collar", "Saddle")


def is_spin(o):
    return o.name.split(".")[0].startswith(SPIN_PREFIXES)


def bottom_centre(objs):
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return ((min(v.x for v in vs) + max(v.x for v in vs)) / 2, (min(v.y for v in vs) + max(v.y for v in vs)) / 2, min(v.z for v in vs))


PART = os.environ.get("CAROUSEL_PART", "")
spin_parts = [o for o in parts if is_spin(o)]
static_parts = [o for o in parts if not is_spin(o)]
if PART:
    so, po = bottom_centre(static_parts), bottom_centre(spin_parts)
    rel = lambda p, o: [round(p[0] - o[0], 3), round(p[1] - o[1], 3), round(p[2] - o[2], 3)]
    layout = {
        "note": "Blender frame, studs: x right, y back (front faces -y), z up. Roblox: X = x, Y = z, Z = -y.",
        "static_origin_to_spin_origin": rel(po, so),
        "spin_axis_in_spin_frame": rel((CX, CYc, po[2]), po),
        "riders_in_spin_frame": [rel((x, y, z), po) for x, y, z, _ in SPOTS],
        "kiosk_counter_top_in_static_frame": rel((9.4, -6.4, CH + 0.5), so),
        "kiosk_yaw_deg": 32,
        "platform_radius": PR,
        "deck_top_in_static_frame": round(PZ - so[2], 3),
    }
    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out", "ranch_exclusive_carousel_layout.json")
    with open(out, "w", newline="") as f:
        json.dump(layout, f, indent=1)
    print("LAYOUT", json.dumps(layout))
    keep = spin_parts if PART == "spin" else static_parts
    for o in parts:
        if o not in keep:
            bpy.data.objects.remove(o)
    parts = keep
_t = {}
for o in parts:
    key = "".join(ch for ch in o.name.split(".")[0] if not ch.isdigit() and ch not in "-")
    _t[key] = _t.get(key, 0) + sum(len(pp.vertices) - 2 for pp in o.data.polygons)
print("TRIS BY PART", sorted(_t.items(), key=lambda kv: -kv[1])[:12])
finish("ranch_exclusive_carousel" + (("_" + PART) if PART else ""), parts)
