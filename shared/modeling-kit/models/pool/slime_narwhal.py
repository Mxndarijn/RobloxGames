# Narwhal (Legendary, Frost & Sea): pale blue whale slime. Soft ice-blue goo with a cream belly
# sweeping up under the grin and darker mottled spots on the back; a long ivory spiral horn from
# the forehead, little flippers at the sides, whale flukes standing up behind, and a small water
# spout over the blowhole. Proud, happy face: sparkly eyes looking up at its own horn.
from models._slimepool import *

BL_D, BL, BL_L = hexc("7cc2fc"), hexc("9edcff"), hexc("d2f0ff")
BELLY = hexc("f4fbff")
SPOT = hexc("62a8f0")
IV_D, IV, IV_L = hexc("c4e4ff"), hexc("fff8e8"), hexc("ffffff")  # groove ice blue, ridge ivory  # ivory horn
FIN_D, FIN = hexc("6cb4f6"), hexc("8cd0ff")
SPRAY, SPRAY_L = hexc("ccf4ff"), hexc("f8feff")
KEY = Vector((-0.4, -0.6, 0.7)).normalized()


def belly_z(a):
    return 0.3 + 0.95 * max(0.0, math.cos(a * 0.95)) ** 1.5


def paint(a, z, p):
    c = mix(BL_D, BL, smoothstep(0.0, 1.2, z))
    c = mix(c, BL_L, 0.45 * smoothstep(1.8, 2.8, z))
    return mix(c, BELLY, smoothstep(belly_z(a) + 0.14, belly_z(a) - 0.14, z))


# slightly long front-to-back (a whale), head leaning forward a touch
b = Body([(0, 1.1), (0.15, 1.42), (0.55, 1.55), (1.15, 1.5), (1.8, 1.24), (2.35, 0.86), (2.7, 0.4), (2.82, 0)],
         paint=paint, segs=40, sub=2, sy=1.1, gloss=0.6, lean=lambda z: -0.06 * (z / 2.8) ** 2)
parts = [b.obj]
H = b.H

# mottled spots on the back and upper sides (narwhal pattern), clear of the face
spec = []
for k, (yaw, z, w) in enumerate([(180, 2.2, 0.32), (150, 1.75, 0.26), (-150, 1.8, 0.28), (125, 2.3, 0.2), (-122, 2.25, 0.22),
                                 (165, 1.2, 0.22), (-170, 1.35, 0.25), (105, 1.55, 0.18), (-105, 1.6, 0.2), (140, 2.6, 0.16),
                                 (-140, 2.55, 0.15), (180, 2.65, 0.18)]):
    spec.append((yaw, z, w, w * 0.8, 20 * k))
parts += spots(b, spec, SPOT, n=10)

# ---- spiral horn: lathe cone with a 4-start twist painted and bumped in, on the forehead
HB = b.point(0, 2.45, -0.12)  # base, sunk into the forehead
HD = Vector((0.0, -0.42, 1.0)).normalized()
HL, HR = 2.0, 0.2
seg, rings = 10, 22
bm = bmesh.new()
rows = []
for i in range(rings + 1):
    t = i / rings
    r = HR * (1 - t) ** 0.85 + 0.012
    row = []
    for k in range(seg):
        ang = k * math.tau / seg
        tw = math.sin(2 * (ang - t * 7.5 * math.tau / 2))  # 2 grooves, ~7 half turns
        rr = r * (1 + 0.14 * tw)
        q = HD.to_track_quat("Z", "Y")
        row.append(bm.verts.new(HB + q @ Vector((math.cos(ang) * rr, math.sin(ang) * rr, t * HL))))
    rows.append(row)
for a_, b_ in zip(rows, rows[1:]):
    for k in range(seg):
        bm.faces.new((a_[k], a_[(k + 1) % seg], b_[(k + 1) % seg], b_[k]))
tip = bm.verts.new(HB + HD * (HL + 0.06))
for k in range(seg):
    bm.faces.new((rows[-1][k], rows[-1][(k + 1) % seg], tip))
bm.faces.new(list(reversed(rows[0])))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
horn_o = obj_from_bm("Horn", bm, None)


def horn_col(p, n):
    rel = p - HB
    t = max(0.0, min(1.0, rel.dot(HD) / HL))
    q = HD.to_track_quat("Z", "Y").inverted()
    lp = q @ rel
    ang = math.atan2(lp.y, lp.x)
    tw = math.sin(2 * (ang - t * 7.5 * math.tau / 2))
    c = mix(IV_D, IV, smoothstep(-0.6, 0.4, tw))
    c = mix(c, IV_L, 0.5 * smoothstep(0.2, 0.9, n.dot(KEY)))
    return c


paint_fn(horn_o, horn_col)
parts.append(keep(horn_o, True))

# ---- flippers (Fin*) low on the sides, swept back and down
FL = [(0, -0.24), (0.35, -0.32), (0.72, -0.24), (0.88, 0.0), (0.7, 0.18), (0.32, 0.26), (0, 0.22)]
for sd in (-1, 1):
    root = b.point(math.radians(sd * 84), 0.78, -0.1)
    X = Vector((sd * 0.85, 0.45, -0.3)).normalized()
    Y = Vector((0, 1, 0))
    Y = (Y - X * Y.dot(X)).normalized()
    parts.append(puffy_slab(f"Fin{sd}", FL, 0.17, root, X, Y, along(FIN, FIN_D, root, root + X * 0.85)))

# ---- tail flukes (Tail*) standing up behind, a little stalk from the back
tb = b.point(math.pi, 0.55, -0.15)
stalk = [tb, tb + Vector((0, 0.42, 0.1)), tb + Vector((0, 0.72, 0.42)), tb + Vector((0, 0.86, 0.8))]
parts.append(horn("TailStalk", [tuple(q) for q in stalk], [0.36, 0.26, 0.17, 0.12], BL_D, BL, segs=10))
tc = stalk[-1]
for sd in (-1, 1):
    fluke = [(0, -0.14), (0.45, -0.22), (0.95, -0.1), (1.18, 0.24), (0.86, 0.12), (0.45, 0.16), (0, 0.16)]
    X = Vector((sd * 0.8, 0.3, 0.62)).normalized()
    Y = Vector((0, 0.35, 1))
    Y = (Y - X * Y.dot(X)).normalized()
    parts.append(puffy_slab(f"Tail{sd}", fluke, 0.14, tc, X, Y, along(BL, FIN_D, tc, tc + X * 1.15), rows=2))

# ---- blowhole spout: a short column of droplets fanning out above the back of the head
sb = b.point(math.pi, H - 0.3, 0.0)
parts.append(decal("Blowhole", oval(0, 0, 0.2, 0.1, n=10), SPOT, Frame(sb + Vector((0, 0, 0)), (1, 0, 0), (0, 1, 0), (0, 0.3, 1)), on=["Body"]))
bk = Vector((-0.4, -0.7, 0.6)).normalized()
drops = [(0, 0.05, 0.3, 0.15), (0, 0.0, 0.66, 0.14), (-0.3, 0.05, 0.98, 0.13), (0.3, 0.02, 1.0, 0.13), (-0.58, 0.12, 0.86, 0.1),
         (0.6, 0.1, 0.84, 0.1), (0, -0.02, 1.12, 0.15)]
for k, (x, y, z, r) in enumerate(drops):
    c = sb + Vector((x, y, z))
    parts.append(ball(f"Spray{k}", r, c, lambda p, n: mix(SPRAY, SPRAY_L, 0.35 + 0.65 * max(0.0, n.dot(bk))), subdiv=2))

# ---- face: sparkly eyes looking up, open happy smile, rosy cheeks
f = Face(b, eye_v=1.55, eye_u=0.5, mouth_v=1.08)
f.eyes("sparkle", w=0.4, h=0.52, iris=hexc("3a8cff"), look=(0, 0.03))
f.mouth("open", w=1.0)
f.cheeks(color=hexc("ff9ec0"), w=0.28, h=0.13)
parts += f.parts

if os.environ.get("SLIME_DBG"):
    exec(open(os.environ["SLIME_DBG"]).read()); dbg(parts)
ship("slime_narwhal", parts)
