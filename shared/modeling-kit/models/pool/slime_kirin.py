# Kirin (Divine, tier 9): a divine qilin slime. Pearly white body with a soft gold-blush foot and
# patches of gold scales on the back and flanks, one elegant ridged golden horn, a flowing cloud mane
# of mint and teal puffs from the brow down the back to a cloud tail, small deer ears, long golden
# whisker barbels, and little cloud puffs round its foot as if it walks on clouds. Gentle noble
# face: calm teal eyes with lashes, a small smile.
from models._slimepool import *

PEARL, PEARL_B, PEARL_P = hexc("fffdf8"), hexc("e4f2ff"), hexc("fff0f4")
FOOT = hexc("ffd98a")
SC_D, SC, SC_L = hexc("f2b440"), hexc("ffd04a"), hexc("fff4b0")
MINT_D, MINT, MINT_L = hexc("3ccfba"), hexc("86f2da"), hexc("e2fff7")
CLOUD, CLOUD_D = hexc("ffffff"), hexc("cfeff0")
IRIS = hexc("2bbfb0")
INKK = hexc("2a2440")


def paint(a, z, p):
    c = mix(FOOT, PEARL, smoothstep(0.15, 0.95, z))
    n1 = noise.noise(Vector((p.x * 0.8, p.y * 0.8, p.z * 0.8 + 3.0)))
    c = mix(c, PEARL_B, 0.5 * smoothstep(0.1, 0.5, n1))
    n2 = noise.noise(Vector((p.x * 0.7 + 5.1, p.y * 0.7, p.z * 0.7)))
    c = mix(c, PEARL_P, 0.5 * smoothstep(0.1, 0.5, n2))
    return c


H = 3.0
b = Body([(0, 1.02), (0.13, 1.34), (0.5, 1.5), (1.1, 1.48), (1.8, 1.24), (2.45, 0.85), (2.85, 0.4), (H, 0)],
         paint=paint, segs=48, sub=2, gloss=0.9, lean=lambda z: 0.1 * max(0.0, (z - 2.2) / 0.8) ** 2)
parts = [b.obj]

# ---------------------------------------------------------------- gold scale patches (rows of scallops)
k = 0


# grid decal from slime_abyss.py: wide decals that follow the curved body
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
    return separate(keep(o, False), frame, on, off=off)



def scale_col(fr, rad=0.21):
    """fish-scale pattern in the frame's (u, v): staggered circles, lower rows overlap the upper ones;
    each scale light at its top, dark gold at its rim."""
    dv = rad * 1.05
    du = rad * 1.75

    def fn(p, n):
        d = p - fr.O
        u, v = d.dot(fr.U), d.dot(fr.V)
        best = None
        j0 = math.floor(-v / dv) - 1
        for j in range(j0 + 3, j0 - 1, -1):  # bottom rows first: they lie on top
            cv = -j * dv
            off = du / 2 if j % 2 else 0.0
            cu = round((u - off) / du) * du + off
            for cc in (cu - du, cu, cu + du):
                rr = math.hypot(u - cc, (v - cv) * 1.1)
                if rr < rad and (v <= cv + 0.25 * rad):
                    best = rr / rad if best is None else best
            if best is not None:
                break
        t = 1.0 if best is None else best
        c = mix(SC_L, SC, smoothstep(0.1, 0.7, t))
        return mix(c, SC_D, smoothstep(0.72, 0.95, t))
    return fn


def scale_patch(name, yaw, z, w, h, seed):
    fr = frame_at(yaw, z)
    return pdecal(name, blotch(seed, w, h, n=16, wobble=0.22), scale_col(fr), frame=fr, off=0.015, th=0.02, step=0.17, passes=2)


for sd in (-1, 1):
    parts.append(scale_patch(f"Scales{sd}", sd * 108, 1.3, 1.1, 0.9, 2 + sd))
parts.append(scale_patch("ScalesBack", 180, 1.9, 1.25, 1.0, 7))

# ---------------------------------------------------------------- golden horn (single, ridged, swept back)
hb = b.point(0, 2.62, -0.05)
hp = [hb, hb + Vector((0, 0.02, 0.45)), hb + Vector((0, 0.18, 0.95)), hb + Vector((0, 0.45, 1.35)), hb + Vector((0, 0.7, 1.55))]
parts.append(horn("Horn", hp, [0.2, 0.16, 0.12, 0.07, 0.015], SC, SC_L, segs=8))
for j, t in enumerate((0.18, 0.4, 0.62)):
    i = t * (len(hp) - 1)
    i0 = int(i)
    q = hp[i0].lerp(hp[i0 + 1], i - i0)
    d = (hp[i0 + 1] - hp[i0]).normalized()
    parts.append(torus(f"HornRing{j}", 0.17 - 0.04 * j, 0.035, tuple(q), tuple(d), SC_D, segs=12, rsegs=4))


# ---------------------------------------------------------------- cloud mane: mint/teal puffs from the brow down the back
def puff(name, c, r, squash=(1, 1, 1), dark=MINT_D, mid=MINT, light=MINT_L):
    C = Vector(c)
    return ball(name, r, tuple(C), lambda p, n: mix(mix(dark, mid, smoothstep(-0.7, 0.1, n.z)), light, 0.8 * smoothstep(0.3, 1.0, n.z)),
                squash=squash, subdiv=2)


mane = []
for j in range(9):
    t = j / 8
    ang = math.radians(-12 + t * 120)  # from just behind the horn over the crown and down the back
    zc = 1.45 + math.cos(ang) * 1.55
    yc = 0.15 + math.sin(ang) * 1.45
    r = 0.42 - 0.1 * t
    r = r * (1.0 if j % 2 else 0.85)
    parts.append(puff(f"Mane{j}", (0, yc + 0.04 * math.sin(j * 2.0), zc), r, (1.2, 1.0, 0.95)))
    if j in (1, 3, 5, 7):
        for sd in (-1, 1):
            parts.append(puff(f"Mane{j}{sd}", (sd * 0.4, yc + 0.08, zc - 0.16), r * 0.68, dark=MINT, mid=MINT_L, light=CLOUD))
# forelock curl falling beside the horn
parts.append(puff("ManeFore", (0.28, -0.55, H - 0.05), 0.24))
parts.append(puff("ManeFore2", (-0.3, -0.5, H - 0.1), 0.2))
# cloud tail at the back
for j, (c, r) in enumerate([((0, 1.6, 0.85), 0.34), ((0.15, 1.95, 1.05), 0.3), ((0.1, 2.15, 1.38), 0.26), ((-0.05, 2.1, 1.68), 0.2)]):
    parts.append(puff(f"Tail{j}", c, r))

# ---------------------------------------------------------------- ears (small deer ears beside the horn)
for sd in (-1, 1):
    ear = [(-0.2, 0), (0.2, 0), (0.12, 0.3), (0.0, 0.55), (-0.1, 0.3)]
    X, Y = (1, 0, -sd * 0.6), (sd * 0.85, 0.1, 0.55)
    base = b.point(math.radians(sd * 52), 2.45, -0.05)
    parts.append(puffy_slab(f"Ear{sd}", ear, 0.14, tuple(base), X, Y, PEARL))
    parts.append(puffy_slab(f"EarIn{sd}", [(-0.11, 0.06), (0.11, 0.06), (0.06, 0.26), (0.0, 0.42), (-0.06, 0.26)], 0.08,
                            tuple(Vector(base) + Vector((0, -0.07, 0))), X, Y, hexc("ffb8cc")))

# ---------------------------------------------------------------- cloud puffs round the foot
# clouds it stands on: flat-bottomed clusters under the foot rim, bumps on top, plus two drifting wisps
CL = [(-40, 1.35, 0.12, 1.0), (35, 1.4, 0.12, 1.05), (100, 1.35, 0.12, 0.95), (155, 1.3, 0.12, 0.9), (-100, 1.4, 0.12, 1.0),
      (-160, 1.3, 0.12, 0.9), (-2.2, 2.25, 1.0, 0.6), (2.05, 2.3, 2.6, 0.5)]
for j, (yaw, r, z, s_) in enumerate(CL):
    if j < 6:
        a = math.radians(yaw)
        C = Vector((math.sin(a) * r, -math.cos(a) * r, z))
    else:  # drifting wisp beside the body (yaw = x, r = y... given directly)
        a = 0.0
        C = Vector((yaw, -0.2 if j == 6 else 0.9, r - 0.5))
    tng = Vector((math.cos(a), math.sin(a), 0))
    rad = Vector((math.sin(a), -math.cos(a), 0)) * (1 if j < 6 else 0)
    balls = [(C + rad * 0.12, 0.42 * s_, (1.35, 1.1, 0.7)), (C + tng * 0.36 * s_ + rad * 0.1, 0.3 * s_, (1.1, 1.0, 0.85)),
             (C - tng * 0.36 * s_ + rad * 0.1, 0.3 * s_, (1.1, 1.0, 0.85)), (C + Vector((0, 0, 0.16 * s_)) + tng * 0.1 * s_ + rad * 0.14, 0.3 * s_)]
    o = goo(f"Cloud{j}", balls, lambda p, n: mix(MINT_L, CLOUD, smoothstep(-0.5, 0.4, n.z)), tris=130, resolution=0.06)
    if j < 6:  # flat bottom at the ground
        for v in o.data.vertices:
            v.co.z = max(v.co.z, 0.0)
    parts.append(o)

# ---------------------------------------------------------------- the floating divine pearl it guards, gold twinkles
key = Vector((-0.35, -0.75, 0.55)).normalized()
PC = Vector((1.75, -0.55, 3.35))
parts.append(ball("Pearl", 0.3, tuple(PC), lambda p, n: mix(hexc("bff5ea"), WHITE, 0.2 + 0.8 * max(0.0, n.dot(key)) ** 0.8), subdiv=2))
parts.append(torus("PearlRing", 0.44, 0.04, tuple(PC), (0.3, -0.35, 1), lambda p, n: mix(GOLD, GOLD_L, 0.5 + 0.5 * n.z), segs=20, rsegs=4))
for j, (x, y, z, r) in enumerate([(-1.6, -0.5, 3.4, 0.17), (-2.0, 0.2, 2.6, 0.12), (2.3, -0.2, 2.6, 0.12)]):
    parts.append(slab(f"Twinkle{j}", star(0, 0, r, r * 0.3, n=4), 0.05, (x, y, z), (1, 0, 0), (0, 0.2, 1), SC_L))

# ---------------------------------------------------------------- gentle noble face
f = Face(b, eye_u=0.5, eye_v=1.58, mouth_v=1.15, ink=INKK)
for sd in (-1, 1):
    f._eye_round(sd, 0.44, 0.56, lid=0.12, tilt=-0.12, iris=IRIS)
f.mouth("cat", w=0.9)
f.cheeks(color=hexc("ffb0c8"), w=0.28, h=0.13)
parts += f.parts
# golden whisker barbels flowing from beside the mouth
for sd in (-1, 1):
    w0 = b.point(math.radians(sd * 28), 1.22, 0.0)
    pts = [w0, w0 + Vector((sd * 0.35, -0.12, -0.05)), w0 + Vector((sd * 0.7, -0.08, -0.25)), w0 + Vector((sd * 0.95, 0.05, -0.2)),
           w0 + Vector((sd * 1.12, 0.15, -0.05))]
    parts.append(horn(f"Whisker{sd}", pts, [0.05, 0.045, 0.035, 0.025, 0.012], SC, SC_L, segs=5))

ship("slime_kirin", parts)
