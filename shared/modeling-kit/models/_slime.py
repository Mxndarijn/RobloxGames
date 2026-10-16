# Shared slime builder (not an asset). Gumdrop body = surface of revolution, smooth shaded,
# light vertex colour (MeshPart.Color tints it). Faces and coloured accessories are separate
# meshes built in the same body frame, so they sit on the body with no offset (see SLIMES.md).
#
# Body frame while modelling: studs, bottom centre at the origin, Z up, face towards -Y (kit
# convention, so contact sheets show the face). ship() turns the mesh 180 deg about Z unless
# SLIME_PREVIEW=1, because the game's slimes face Roblox -Z (SlimeLayout: front = -Z) and the
# kit's FBX export maps Blender -Y to Roblox +Z.
import json, math, os
import bmesh, bpy
from mathutils import Vector
from lib import *

D = 3.0  # Config.SLIME_BASE_DIAMETER: body is 3 x 3 x 3 studs at size 1
SEGS = 24
# gumdrop profile (z, r): widest low (sits heavy), soft peak on top
PROFILE = [(0.0, 1.02), (0.05, 1.2), (0.14, 1.34), (0.3, 1.44), (0.52, 1.5), (0.78, 1.5), (1.04, 1.47),
           (1.3, 1.41), (1.56, 1.32), (1.82, 1.2), (2.06, 1.05), (2.3, 0.86), (2.5, 0.66), (2.67, 0.46),
           (2.8, 0.29), (2.9, 0.15), (2.97, 0.05)]
TIP = 3.0

# body values (tinted by MeshPart.Color): darker goo foot, mid body, lighter crown + highlight
FOOT, BODY, CROWN, SHINE = 0.70, 0.86, 0.93, 1.0
INK, WHITE = rgb(32, 24, 42), rgb(255, 255, 255)
MOUTH, TONGUE, CHEEK = rgb(84, 26, 46), rgb(255, 122, 150), rgb(255, 146, 172)


def grey(v):
    return (v, v, v, 1.0)


def radius(z):
    """body radius at height z (piecewise linear in PROFILE; 0 above the tip)."""
    if z <= PROFILE[0][0]:
        return PROFILE[0][1]
    for (z0, r0), (z1, r1) in zip(PROFILE, PROFILE[1:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
    last = PROFILE[-1]
    return max(0.0, last[1] * (TIP - z) / (TIP - last[0]))


def lean(z):
    """the peak leans back (+Y) a little: a gumdrop with attitude. Zero below z 2.2 (face area)."""
    return 0.32 * max(0.0, (z - 2.2) / 0.8) ** 2


def surface(u, v, off=0.0):
    """point on the body front (-Y side) at x=u, z=v, pushed `off` studs out along the normal."""
    r = radius(v)
    y = -math.sqrt(max(r * r - u * u, 1e-6))
    dr = (radius(v + 0.01) - radius(v - 0.01)) / 0.02
    rho = math.hypot(u, y)
    n = Vector((u / rho, y / rho, -dr)).normalized()
    return Vector((u, y + lean(v), v)) + n * off


def _smooth(o, on=True):
    """flag faces smooth (goo) or flat (crisp accessories); a face attribute, so it survives join()."""
    for p in o.data.polygons:
        p.use_smooth = on
    a = o.data.attributes.get("keep_smooth") or o.data.attributes.new("keep_smooth", "INT", "FACE")
    a.data.foreach_set("value", [int(on)] * len(o.data.polygons))
    return o


# ---------------------------------------------------------------- body
DRIP_YAWS = [(68, 0.85), (128, 0.6), (180, 0.95), (232, 0.65), (292, 0.8)]  # deg from front, length


def drip_bulge(a, z):
    """slime_wobble: goo runs down the body as smooth bulges of the body surface itself (merges
    like real goo; separate tubes read as stubby limbs). Peak bulge low down, a 'drop' at the end."""
    out = 0.0
    for yaw, ln in DRIP_YAWS:
        d = math.atan2(math.sin(a - math.radians(yaw - 90)), math.cos(a - math.radians(yaw - 90)))
        z_end = 1.25 - ln
        t = (1.3 - z) / max(1.3 - z_end, 1e-3)  # 0 at the top of the run, 1 at the drop
        if 0 <= t <= 1.25:
            w = 0.16 + 0.08 * min(t, 1)
            amp = 0.06 + 0.16 * min(t, 1) ** 2 * (1 if t <= 1 else max(0, 1 - (t - 1) / 0.25))
            out = max(out, amp * math.exp(-(d / w) ** 2))
    return out


def body(name="Body", skirt=0.0, drip=False):
    """Gumdrop body. skirt > 0 flares the bottom (melting goo, slime_wobble); the face area
    (z > 0.9) is identical for every body, so every face mesh fits every body."""
    bm = bmesh.new()
    prof = list(PROFILE)
    if skirt:
        prof = [(z, r + skirt * max(0.0, 1 - z / 0.9) ** 1.5) for z, r in prof]
    if drip:  # finer rings low down so the bulges are smooth
        prof = sorted(prof + [(z, radius(z) + skirt * max(0.0, 1 - z / 0.9) ** 1.5) for z in (0.66, 0.91)])
    segs = 32 if drip else SEGS
    rings = []
    for z, r in prof:
        rings.append([bm.verts.new((math.cos(a) * (r + (drip_bulge(a, z) if drip else 0)),
                                    math.sin(a) * (r + (drip_bulge(a, z) if drip else 0)) + lean(z), z))
                      for a in (i * math.tau / segs for i in range(segs))])
    tip = bm.verts.new((0, lean(TIP), TIP))
    bot = bm.verts.new((0, 0, 0))
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    for i in range(segs):
        j = (i + 1) % segs
        bm.faces.new((rings[-1][i], rings[-1][j], tip))
        bm.faces.new((rings[0][j], rings[0][i], bot))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    paint_body(bm)
    return _smooth(obj_from_bm(name, bm))


def paint_body(bm, key=Vector((-0.5, -0.62, 0.6))):
    """value-only paint (the tint supplies the hue): darker foot (goo depth / contact shadow),
    lighter crown, a soft key-light highlight blob on the upper front-left + a small rim light."""
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    key = key.normalized()
    rim = Vector((0.75, -0.35, 0.2)).normalized()
    for f in bm.faces:
        for lp in f.loops:
            p = lp.vert.co
            t = p.z / TIP
            v = FOOT + (BODY - FOOT) * min(1.0, t / 0.3) if t < 0.3 else BODY + (CROWN - BODY) * (t - 0.3) / 0.7
            d = (p - Vector((0, 0, 1.25))).normalized()
            h = max(0.0, d.dot(key))
            v += (SHINE - v) * min(1.0, max(0.0, (h - 0.78) / 0.14))  # big soft highlight
            g = max(0.0, d.dot(rim))
            v += (SHINE - v) * 0.6 * min(1.0, max(0.0, (g - 0.9) / 0.06))  # small rim glint
            lp[col] = grey(v)


# ---------------------------------------------------------------- decal shapes (faces)
def decal(name, poly, color, off=0.02, th=0.025):
    """A thin closed slab hugging the body: 2D polygon (u, v) in face-plane studs -> projected
    onto the body front, `off` above the surface, `th` thick. Layer details with bigger off."""
    bm = bmesh.new()
    back = [bm.verts.new(surface(u, v, off)) for u, v in poly]
    front = [bm.verts.new(surface(u, v, off + th)) for u, v in poly]
    n = len(poly)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((back[i], back[j], front[j], front[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    return _smooth(obj_from_bm(name, bm, color), False)


def oval(cu, cv, w, h, n=16, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    pts = []
    for k in range(n):
        a = k * math.tau / n
        x, y = math.cos(a) * w / 2, math.sin(a) * h / 2
        pts.append((cu + x * c - y * s, cv + x * s + y * c))
    return pts


def arc(cu, cv, rad, a0, a1, width, n=10, squash=1.0):
    """thick stroke along a circular arc (degrees, 0 = +u, 90 = up), as one closed polygon."""
    outer, inner = [], []
    for k in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * k / n)
        outer.append((cu + math.cos(a) * (rad + width / 2), cv + math.sin(a) * (rad + width / 2) * squash))
        inner.append((cu + math.cos(a) * (rad - width / 2), cv + math.sin(a) * (rad - width / 2) * squash))
    return outer + list(reversed(inner))


def half_oval(cu, cv, w, h, n=12, up=False):
    """D shape: flat top edge, round bottom (open mouth). up=True flips it."""
    pts = []
    for k in range(n + 1):
        a = math.pi + math.pi * k / n
        y = math.sin(a) * h
        pts.append((cu + math.cos(a) * w / 2, cv + (-y if up else y)))
    return pts


EYE_U, EYE_V = 0.5, 1.62


def eye_open(name, side, w=0.5, h=0.7, look=0.0, lid=0.0, tilt=0.0):
    """big glossy eye: black oval + two catchlights (upper-outer big, lower small).
    lid > 0 cuts the top flat (half-lidded); tilt slants the lid (radians)."""
    u = side * EYE_U + look
    pts = oval(u, EYE_V, w, h, n=12)
    if lid:
        top = EYE_V + h / 2 - lid * h
        pts = [(x, min(y, top + (x - u) * math.tan(tilt) * side)) for x, y in pts]
    out = [decal(name, pts, INK, off=0.015)]
    out.append(decal(name + "Hi", oval(u - 0.08, EYE_V + h * 0.17 - lid * h * 0.6, w * 0.36, h * 0.3, n=10), WHITE, off=0.04, th=0.02))
    out.append(decal(name + "Hi2", oval(u + 0.08, EYE_V - h * 0.22, w * 0.16, w * 0.16, n=8), WHITE, off=0.04, th=0.02))
    return out


def cheeks(name, w=0.3, h=0.15, v=1.3):
    return [decal(f"{name}{s}", oval(s * 0.86, v, w, h, n=10), CHEEK, off=0.012, th=0.015) for s in (-1, 1)]


# expressions -> mapped to the game's eyes/mouth genome in SLIMES.md
def face(expr):
    p = []
    if expr == "default":  # Round eyes + Smile
        for s in (-1, 1):
            p += eye_open(f"Eye{s}", s)
        p.append(decal("Mouth", arc(0, 1.27, 0.17, 200, 340, 0.07), MOUTH))
        p += cheeks("Cheek")
    elif expr == "happy":  # Happy eyes (^ ^) + Open mouth
        for s in (-1, 1):
            p.append(decal(f"Eye{s}", arc(s * EYE_U, EYE_V - 0.08, 0.17, 20, 160, 0.085), INK))
        p.append(decal("Mouth", half_oval(0, 1.3, 0.42, 0.24), MOUTH))
        p.append(decal("Tongue", oval(0, 1.15, 0.2, 0.09), TONGUE, off=0.04, th=0.015))
        p += cheeks("Cheek", 0.34, 0.17, 1.4)
    elif expr == "sleepy":  # Sleepy / content: closed smiling lids + tiny smile
        for s in (-1, 1):
            p.append(decal(f"Eye{s}", arc(s * EYE_U, EYE_V + 0.02, 0.16, 200, 340, 0.075), INK))
            p.append(decal(f"Lash{s}", arc(s * (EYE_U + 0.17), EYE_V - 0.05, 0.06, 250 if s > 0 else 200, 290 if s > 0 else 240, 0.04, n=4), INK))
        p.append(decal("Mouth", arc(0, 1.33, 0.09, 210, 330, 0.05), MOUTH))
        p += cheeks("Cheek", 0.34, 0.16, 1.4)
    elif expr == "surprised":  # Wide eyes + small o mouth
        for s in (-1, 1):
            p += eye_open(f"Eye{s}", s, w=0.56, h=0.76)
            p.append(decal(f"Brow{s}", arc(s * EYE_U, EYE_V + 0.18, 0.2, 60, 120, 0.06, n=6), INK))
        p.append(decal("Mouth", oval(0, 1.22, 0.2, 0.24), MOUTH))
        p.append(decal("MouthIn", oval(0, 1.19, 0.11, 0.1), shade(MOUTH, 0.6), off=0.04, th=0.012))
    elif expr == "mischievous":  # Angry/sly: half-lidded slanted eyes + smirk + one fang
        for s in (-1, 1):
            p += eye_open(f"Eye{s}", s, h=0.64, lid=0.38, tilt=0.35)  # inner corners low: sly, not sad
        p.append(decal("Mouth", arc(0.06, 1.37, 0.24, 215, 320, 0.065), MOUTH))
        p.append(decal("Fang", [(0.13, 1.18), (0.25, 1.205), (0.19, 1.08)], WHITE, off=0.04, th=0.02))
        p += cheeks("Cheek", 0.26, 0.13)
    else:
        raise ValueError(expr)
    return p


EXPRESSIONS = ["default", "happy", "sleepy", "surprised", "mischievous"]


# ---------------------------------------------------------------- goo features (body-tinted)
def ears():
    out = []
    for s in (-1, 1):
        e = blob(f"Ear{s}", 0.5, (s * 0.72, 0.15, 2.45), grey(BODY), subdiv=2, squash=(0.75, 0.5, 1.25), jitter=0, rot=(0, s * -28, 0))
        bm = bmesh.new(); bm.from_mesh(e.data)
        col = bm.loops.layers.color["Col"]
        for f in bm.faces:  # inner ear (front-facing) darker, tip lighter
            for lp in f.loops:
                p = lp.vert.co
                fr = f.normal.y < -0.4 and abs(p.x - s * 0.72 - (p.z - 2.45) * -s * 0.47) < 0.25
                lp[col] = grey(0.62 if fr and p.z > 2.25 else (CROWN if p.z > 2.6 else BODY))
        bm.to_mesh(e.data); bm.free()
        out.append(_smooth(e))
    return out


def horns():
    out = []
    for s in (-1, 1):
        pts = [(s * 0.55, 0.1, 2.18), (s * 0.85, 0.12, 2.55), (s * 1.0, 0.2, 2.95), (s * 0.92, 0.32, 3.3), (s * 0.72, 0.4, 3.5)]
        h = tube(f"Horn{s}", pts, [0.3, 0.24, 0.17, 0.1, 0.03], grey(0.5), segs=8)
        gradient(h, grey(0.46), grey(0.98))  # dark root -> light tip: horn reads in any tint
        out.append(_smooth(h))
    return out


def drips():
    """goo drips + puddle for slime_wobble; kept off the face (yaw 0 +- 55 deg)."""
    out = []
    for k, (a, ln) in enumerate(((68, 0.75), (128, 0.55), (180, 0.85), (232, 0.6), (292, 0.7))):
        a = math.radians(a - 90)  # 0 = front (-Y)
        c, s = math.cos(a), math.sin(a)
        z0 = 1.15 + 0.1 * (k % 2)
        r0 = radius(z0) - 0.05
        mid = 0.62
        rm = radius(mid) + 0.18 - 0.1  # on the skirt, half sunk: goo running down, not limbs
        pts = [(c * r0, s * r0, z0), (c * (radius(z0 - ln * 0.4) + 0.02), s * (radius(z0 - ln * 0.4) + 0.02), z0 - ln * 0.4), (c * rm, s * rm, mid)]
        d = tube(f"Drip{k}", pts, [0.12, 0.14, 0.16], grey(BODY), segs=6)
        gradient(d, grey(FOOT), grey(BODY))
        out.append(_smooth(d))
        b = blob(f"DripEnd{k}", 0.19, (c * (rm - 0.04), s * (rm - 0.04), mid - 0.08), grey(BODY), subdiv=1, jitter=0, squash=(0.9, 0.9, 1.2))
        gradient(b, grey(FOOT), grey(BODY))
        out.append(_smooth(b))
    return out


# ---------------------------------------------------------------- accessories (own colours)
LEAF_D, LEAF_L, STEM = rgb(52, 140, 62), rgb(132, 214, 90), rgb(86, 150, 60)


def leaf_shape(name, length, width, base, ang, tilt, color):
    """flat-ish leaf with a fold (midrib): 2 x n quads, closed by thickness."""
    bm = bmesh.new()
    n = 6
    rows = []
    for k in range(n + 1):
        t = k / n
        w = max(0.02, width * math.sin(math.pi * t) ** 0.8 * (1 - 0.25 * t))  # never 0: closed, manifold ends
        rows.append([(-w, t * length, 0.06 * math.sin(math.pi * t)), (0, t * length, -0.03), (w, t * length, 0.06 * math.sin(math.pi * t))])
    top = [[bm.verts.new((x, y, z + 0.025)) for x, y, z in r] for r in rows]
    bot = [[bm.verts.new((x, y, z - 0.025)) for x, y, z in r] for r in rows]
    for k in range(n):
        for i in range(2):
            bm.faces.new((top[k][i], top[k][i + 1], top[k + 1][i + 1], top[k + 1][i]))
            bm.faces.new((bot[k][i + 1], bot[k][i], bot[k + 1][i], bot[k + 1][i + 1]))
        bm.faces.new((top[k][0], top[k + 1][0], bot[k + 1][0], bot[k][0]))
        bm.faces.new((top[k + 1][2], top[k][2], bot[k][2], bot[k + 1][2]))
    bm.faces.new((top[0][0], bot[0][0], bot[0][1], top[0][1])); bm.faces.new((top[0][1], bot[0][1], bot[0][2], top[0][2]))
    bm.faces.new((top[n][1], bot[n][1], bot[n][0], top[n][0])); bm.faces.new((top[n][2], bot[n][2], bot[n][1], top[n][1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    m = Matrix_rot(ang, tilt)
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(base), verts=bm.verts)
    col = bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for lp in f.loops:
            t = (lp.vert.co - Vector(base)).length / length
            lp[col] = mix(LEAF_D, LEAF_L, min(1, t * 1.2))
    return _smooth(obj_from_bm(name, bm), False)


def Matrix_rot(yaw, tilt):
    from mathutils import Matrix
    return (Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "X"))


def leaf():
    tip = Vector((0, lean(TIP), TIP))
    stem = tube("Stem", [tip + Vector((0, 0, -0.15)), tip + Vector((0.02, 0.0, 0.2)), tip + Vector((0.08, 0.05, 0.42))], [0.07, 0.06, 0.05], STEM, segs=6)
    a = leaf_shape("LeafL", 0.75, 0.24, tip + Vector((0.07, 0.04, 0.38)), 90, 62, LEAF_D)
    b = leaf_shape("LeafR", 0.6, 0.2, tip + Vector((0.07, 0.04, 0.36)), -95, 58, LEAF_D)
    return [_smooth(stem, False), a, b]


GOLD_D, GOLD, GOLD_L = rgb(214, 140, 30), rgb(255, 196, 56), rgb(255, 238, 150)
GEM_R, GEM_B = rgb(255, 72, 110), rgb(80, 196, 255)


def crown():
    """gold crown around the peak: band (open ring) + 5 points with ball tips + gems."""
    z0, zh = 2.28, 0.32
    r0, r1 = radius(z0) + 0.04, radius(z0 + zh) + 0.06
    out = []
    band = cylinder("Band", r0 + 0.05, zh, (0, lean(z0 + 0.1), z0), GOLD, segs=12, r_top=r1 + 0.05, cap=False)
    # give the open band thickness: inner shell
    bm = bmesh.new(); bm.from_mesh(band.data)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.07)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(band.data); bm.free()
    gradient(band, GOLD_D, GOLD_L)
    out.append(band)
    for k in range(5):
        a = math.radians(-90 + k * 72)
        c, s = math.cos(a), math.sin(a)
        base = Vector((c * (r1 + 0.03), s * (r1 + 0.03) + lean(z0 + zh), z0 + zh - 0.04))
        top = base + Vector((c * 0.1, s * 0.1, 0.42))
        p = tube(f"Point{k}", [base, base + (top - base) * 0.6, top], [0.17, 0.1, 0.02], GOLD, segs=4)
        gradient(p, GOLD, GOLD_L)
        out.append(p)
        out.append(blob(f"Ball{k}", 0.075, top + Vector((0, 0, 0.03)), GOLD_L, subdiv=1, jitter=0))
        g = blob(f"Gem{k}", 0.085, Vector((c * (r0 + 0.12), s * (r0 + 0.12) + lean(z0 + 0.16), z0 + 0.16)),
                 GEM_R if k % 2 == 0 else GEM_B, subdiv=1, jitter=0, squash=(1, 1, 1.2))
        out.append(g)
    return [_smooth(o, False) for o in out]


CRY_D, CRY, CRY_L = rgb(120, 170, 255), rgb(176, 226, 255), rgb(244, 250, 255)
CRY_V = rgb(206, 170, 255)


def crystal_prism(name, base, direction, length, rad, color_dark, color_light):
    d = Vector(direction).normalized()
    pts = [Vector(base), Vector(base) + d * length * 0.72, Vector(base) + d * length]
    o = tube(name, pts, [rad, rad, 0.0], color_dark, segs=6)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    col = bm.loops.layers.color["Col"]
    for i, f in enumerate(bm.faces):  # alternate facet values: gem sparkle with flat shading
        for lp in f.loops:
            t = (lp.vert.co - Vector(base)).length / length
            c = mix(color_dark, color_light, min(1, t * 1.1))
            lp[col] = c if i % 2 else mix(c, CRY_L, 0.45)
    bm.to_mesh(o.data); bm.free()
    return _smooth(o, False)


def crystal():
    tip = Vector((0, lean(2.55), 2.55))
    spec = [((0, 0.1, 1), 1.5, 0.27, CRY_D, CRY_L), ((-0.6, 0.15, 0.8), 1.05, 0.2, CRY_V, CRY_L),
            ((0.6, 0.2, 0.75), 1.0, 0.19, CRY_D, CRY_L), ((0.1, 0.7, 0.7), 0.85, 0.17, CRY_V, CRY_L),
            ((-0.3, -0.3, 0.9), 0.6, 0.13, CRY_D, CRY_L)]
    out = []
    for k, (d, ln, r, cd, cl) in enumerate(spec):
        b = tip + Vector((d[0] * 0.3, d[1] * 0.3, -0.2))
        out.append(crystal_prism(f"Crystal{k}", b, d, ln, r, cd, cl))
    return out


# ---------------------------------------------------------------- variants
VARIANTS = {  # name -> (rarity it stands for, body parts builder, accessory builder or None)
    "slime_base": ("Common", lambda: [body()], None),
    "slime_leaf": ("Uncommon", lambda: [body()], leaf),
    "slime_ears": ("Rare", lambda: [body()] + ears(), None),
    "slime_horns": ("Epic", lambda: [body()] + horns(), None),
    "slime_crown": ("Legendary", lambda: [body()], crown),
    "slime_crystal": ("Mythic", lambda: [body()], crystal),
    "slime_wobble": ("mutations", lambda: [body(skirt=0.18, drip=True)], None),
}
RARITY_RGB = {"Common": (170, 220, 170), "Uncommon": (90, 200, 255), "Rare": (60, 110, 255),
              "Epic": (180, 80, 255), "Legendary": (255, 190, 40), "Mythic": (255, 60, 90),
              "mutations": (120, 255, 200)}


# ---------------------------------------------------------------- shipping
BODY_MESHES = ("slime_base", "slime_ears", "slime_horns", "slime_wobble")


def rig_squash(o):
    """Skin the body to a two-bone armature: Root (fixed, at the foot) and Squash (child of Root,
    head at mid height). Weights go 0 at the foot to 1 at the crown, so moving the Squash bone down
    in the SlimeIdleSquish / SlimeHop animations flattens the slime without a per-frame Size write.
    Roblox imports the Armature as Bones under the MeshPart. The armature is exported next to the
    mesh (bl_iterate.py picks up the parent Armature of every exported mesh)."""
    import bpy
    zs = [v.co.z for v in o.data.vertices]
    lo, hi = min(zs), max(zs)
    arm = bpy.data.armatures.new(o.name + "_rig")
    ao = bpy.data.objects.new(o.name + "_rig", arm)
    bpy.context.scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    root = arm.edit_bones.new("Root")
    root.head, root.tail = (0, 0, lo), (0, 0, lo + 0.25 * (hi - lo))
    sq = arm.edit_bones.new("Squash")
    sq.head, sq.tail = (0, 0, lo + 0.5 * (hi - lo)), (0, 0, hi)
    sq.parent = root
    bpy.ops.object.mode_set(mode="OBJECT")
    vg_root, vg_sq = o.vertex_groups.new(name="Root"), o.vertex_groups.new(name="Squash")
    for v in o.data.vertices:
        h = (v.co.z - lo) / max(hi - lo, 1e-6)
        w = min(1.0, max(0.0, h)) ** 1.5  # foot stays put, crown follows the bone fully
        vg_sq.add([v.index], w, "REPLACE")
        vg_root.add([v.index], 1.0 - w, "REPLACE")
    o.parent = ao
    o.modifiers.new("Armature", "ARMATURE").object = ao


def ship(name, parts):
    """finish() + keep smooth flags + turn to face Roblox -Z (unless SLIME_PREVIEW=1) and
    record where this mesh sits relative to the slime's bottom centre (Roblox axes)."""
    preview = os.environ.get("SLIME_PREVIEW") == "1"
    for o in parts:
        if "keep_smooth" not in o.data.attributes:
            _smooth(o, False)
    if not preview:
        for o in parts:
            o.rotation_euler = (0, 0, math.pi)
        bpy.context.view_layer.update()  # matrix_world must include the turn before the bbox below
    # bbox in the body frame before finish() re-centres the mesh
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in parts:
        mw = o.matrix_world
        for v in o.data.vertices:
            w = mw @ v.co
            for i in range(3):
                lo[i], hi[i] = min(lo[i], w[i]), max(hi[i], w[i])
    o = finish(name, parts)
    if name in BODY_MESHES and not preview:
        rig_squash(o)
    a = o.data.attributes["keep_smooth"]
    for p, d in zip(o.data.polygons, a.data):
        p.use_smooth = bool(d.value)
    o.data.attributes.remove(a)
    c = (lo + hi) / 2
    # Blender (x, y, z) -> Roblox (x, z, -y) (kit FBX axes); `preview` meshes are not turned
    info = {"name": name, "roblox_size": [round(hi.x - lo.x, 3), round(hi.z - lo.z, 3), round(hi.y - lo.y, 3)],
            "roblox_center_from_slime_bottom": [round(c.x, 3), round(c.z, 3), round(-c.y, 3)],
            "faces_roblox": "-Z" if not preview else "+Z (preview)"}
    print("SLIME_ATTACH " + json.dumps(info))
    return o
