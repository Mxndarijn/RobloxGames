# Sphinx (Mythic, Starlight set): a sandstone lion slime in a pharaoh's nemes. The headdress is painted
# on the crown in blue/gold meridian stripes above a gold brow band; its two striped side flaps
# (Ribbon*) hang beside the face and flare out at the chest. Lion paws stretch forward on the
# ground (the classic sphinx pose), a lion tail curls behind, a glowing cyan gem sits on the brow.
# Signature face: calm, knowing half-lidded eyes with kohl wings, a small serene smile and a
# little striped pharaoh beard.
from models._slimepool import *

SAND, SAND_D, SAND_L = hexc("ffe2ae"), hexc("fbd49a"), hexc("fff3d6")
BLUE, BLUE_D = hexc("5c9eff"), hexc("4c8cff")
GOLDN, GOLDN_L = hexc("ffd862"), hexc("ffe68a")
GLOW, GLOW_L = hexc("5cf2ff"), hexc("d8ffff")
KOHL = hexc("1e2a6a")
IRIS = hexc("3aa0ff")

H = 3.0
N_STRIPE = 10  # stripes round the crown


def edge(a):
    """height of the nemes' lower edge: a brow line at the front, dropping behind the cheeks."""
    d = abs(math.degrees(a))
    return 2.12 - 0.95 * smoothstep(38, 80, d) - 0.35 * smoothstep(100, 170, d)


def in_nemes(a, z):
    return z > edge(a)


def stripe_col(a, z):
    k = int(math.floor((a + math.pi) / math.tau * N_STRIPE * 2))
    c = BLUE if k % 2 == 0 else GOLDN
    return mix(c, WHITE, 0.08 * smoothstep(2.3, 3.0, z))


def paint(a, z, p):
    c = mix(SAND_D, SAND, smoothstep(0.1, 1.3, z))
    return mix(c, SAND_L, smoothstep(1.6, 2.4, z))


def sectors(a, z):
    if in_nemes(a, z):
        return stripe_col(a, z)
    return None


SEGS = N_STRIPE * 2 * 2  # two body faces per stripe so the meridian stripes land on face columns
b = Body([(0, 1.05), (0.12, 1.32), (0.5, 1.48), (1.1, 1.46), (1.8, 1.24), (2.45, 0.84), (2.85, 0.4), (H, 0)],
         paint=paint, sectors=sectors, segs=SEGS, sub=2, gloss=0.6,
         bump=lambda a, z: (0.05 * smoothstep(edge(a) - 0.05, edge(a) + 0.15, z) * (1 - smoothstep(2.4, 3.0, z))
                            + 0.09 * math.exp(-((z - 2.05) / 0.32) ** 2) * smoothstep(35, 70, abs(math.degrees(a)))
                            * (1 - smoothstep(110, 150, abs(math.degrees(a))))))
parts = [b.obj]


# ---- gold brow band along the nemes edge, round the front half
pts = [tuple(b.point(math.radians(d), edge(math.radians(d)) + 0.02, 0.05)) for d in range(-84, 86, 8)]
parts.append(horn("Diadem", pts, [0.075] * len(pts), GOLDN, GOLDN_L, segs=6))


# ---- side flaps (Ribbon*): a striped shell hugging the body beside the face, flaring out at the chest
def flap(name, sd, n_rows=9, cols=4):
    z_top, z_bot = 1.95, 0.62
    bm = bmesh.new()
    rows = []
    zs = [z_top + (z_bot - z_top) * i / n_rows for i in range(n_rows + 1)]
    for i, z in enumerate(zs):
        t = i / n_rows
        a0 = math.radians(sd * (44 - 8 * t))  # front edge comes forward as it goes down
        a1 = math.radians(sd * (72 + 4 * t))
        flare = 0.05 + 0.28 * t ** 1.4
        inner, outer = [], []
        for j in range(cols + 1):
            a = a0 + (a1 - a0) * j / cols
            inner.append(bm.verts.new(b.point(a, z, flare)))
            outer.append(bm.verts.new(b.point(a, z, flare + 0.12)))
        rows.append((inner, outer))
    fcol = []
    for i in range(n_rows):
        (i0, o0), (i1, o1) = rows[i], rows[i + 1]
        c = BLUE if i % 2 == 0 else GOLDN
        for j in range(cols):
            bm.faces.new((o0[j], o0[j + 1], o1[j + 1], o1[j])); fcol.append(c)
            bm.faces.new((i0[j + 1], i0[j], i1[j], i1[j + 1])); fcol.append(c)
        for (r0, r1) in ((0, cols),):
            pass
        bm.faces.new((i0[0], o0[0], o1[0], i1[0])); fcol.append(c)
        bm.faces.new((o0[cols], i0[cols], i1[cols], o1[cols])); fcol.append(c)
    for (inn, out), c in ((rows[0], BLUE), (rows[-1], GOLDN)):
        for j in range(cols):
            bm.faces.new((inn[j], inn[j + 1], out[j + 1], out[j])); fcol.append(c)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = bm.loops.layers.color.new("Col")
    for f, c in zip(bm.faces, fcol):
        for lp in f.loops:
            lp[col] = c
    o = obj_from_bm(name, bm)
    return keep(o, False)


parts += [flap("Ribbon-1", -1), flap("Ribbon1", 1)]

# ---- glowing brow gem (uraeus jewel) in a gold setting
gp = b.point(0, edge(0) + 0.22, 0.04)
parts.append(decal("GemSet", oval(0, edge(0) + 0.22, 0.42, 0.5, n=16), GOLDN, FRONT, off=0.03, th=0.04, on=["Body"]))
parts.append(gem("BrowGem", tuple(gp + Vector((0, -0.06, 0))), 0.16, GLOW, axis=(0, -1, 0.2), h=0.2, segs=6))
# uraeus: a little gold cobra rearing up over the gem, hood spread
cob = [tuple(gp + Vector((0, 0.04, 0.2))), tuple(gp + Vector((0, -0.04, 0.34))), tuple(gp + Vector((0, -0.1, 0.46)))]
parts.append(horn("Cobra", cob, [0.1, 0.1, 0.09], GOLDN, GOLDN_L, segs=8))
hc = Vector(cob[-1]) + Vector((0, 0.03, 0.06))
parts.append(puffy_slab("CobraHood", [(0, 0.26), (0.17, 0.16), (0.2, -0.04), (0.1, -0.2), (-0.1, -0.2), (-0.2, -0.04), (-0.17, 0.16)],
                        0.08, tuple(hc), (1, 0, 0), (0, -0.2, 1), zgrad(GOLDN, GOLDN_L, hc.z - 0.2, hc.z + 0.25), rows=2))
parts.append(decal("CobraStripe", rect(0, 0, 0.09, 0.3), BLUE, Frame(hc, (1, 0, 0), (0, -0.2, 1), Vector((0, -1, 0.2))), off=0.01, th=0.015, on=None))

# ---- lion paws stretched forward on the ground (sphinx pose)
for sd in (-1, 1):
    p0 = b.point(math.radians(sd * 22), 0.3, -0.25)
    pts = [tuple(p0), tuple(p0 + Vector((sd * 0.02, -0.45, -0.06))), tuple(p0 + Vector((sd * 0.03, -0.8, -0.08)))]
    parts.append(horn(f"Leg{sd}", pts, [0.3, 0.27, 0.26], SAND_D, SAND, segs=10))
    tip = Vector(pts[-1]) + Vector((0, -0.05, -0.02))
    parts.append(ball(f"Paw{sd}", 0.3, tuple(tip), zgrad(SAND_D, SAND_L, tip.z - 0.3, tip.z + 0.3), squash=(1.05, 1.0, 0.8)))
    for t in (-1, 0, 1):
        parts.append(ball(f"Toe{sd}{t}", 0.1, tuple(tip + Vector((t * 0.15, -0.26 + 0.04 * abs(t), -0.06))), SAND_L, squash=(1, 1, 0.8), subdiv=1))

# ---- lion tail curling up behind, gold-and-blue tuft
ctrl = [(0.0, 1.25, 0.4), (0.35, 1.75, 0.45), (0.65, 2.0, 0.85), (0.7, 1.95, 1.35), (0.6, 1.8, 1.6)]
tp = [(x, y, z) for (x, z), (_, y) in zip(catmull([(c[0], c[2]) for c in ctrl], 3), catmull([(c[0], c[1]) for c in ctrl], 3))]
parts.append(horn("Tail", tp, [0.19 - 0.08 * (i / (len(tp) - 1)) for i in range(len(tp))], SAND_D, SAND, segs=8))
tt = Vector(tp[-1])
parts.append(goo("TailTuft", [(tt + Vector((0, 0, 0.1)), 0.32, (1, 1, 1.2)), (tt + Vector((0.08, -0.04, 0.34)), 0.24)],
                 zgrad(BLUE_D, BLUE, tt.z - 0.2, tt.z + 0.5), resolution=0.07, tris=180))

# ---- serene face: half-lidded eyes with kohl wings, small smile, pharaoh beard
f = Face(b, eye_v=1.62, eye_u=0.5, mouth_v=1.18)
for sd in (-1, 1):  # calm half-lid (gentler than "sly")
    f._eye_round(sd, 0.5, 0.62, lid=0.3, tilt=-0.1, iris=IRIS)
for sd in (-1, 1):
    u = sd * 0.5
    f.d(f"Lash{sd}", [(u + sd * 0.2, 1.66), (u + sd * 0.46, 1.74), (u + sd * 0.44, 1.68), (u + sd * 0.22, 1.58)], KOHL, off=0.02)
f.mouth("smile", w=1.0)
f.cheeks(color=hexc("ffa890"), w=0.26, h=0.12, u=0.88, v=1.32)
parts += f.parts
bt = b.point(0, 0.98, -0.04)
beard = [tuple(bt + Vector((0, -0.04 - 0.03 * k, -0.12 * k))) for k in range(5)]
bo = horn("Beard", beard, [0.11, 0.12, 0.12, 0.11, 0.08], BLUE, BLUE, segs=8)
paint_fn(bo, lambda p, n: GOLDN if int((bt.z - p.z) / 0.09) % 2 else BLUE)
parts.append(bo)

ship("slime_sphinx", parts)
