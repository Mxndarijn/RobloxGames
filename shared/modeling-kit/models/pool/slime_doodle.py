# Doodle (Secret): a slime that looks DRAWN ON PAPER. Paper-white body, thick black ink outline
# around every part (inverted hulls: a slightly bigger copy with flipped normals, which Roblox
# culls single-sided so only the rim shows), blue crayon hatching on its shadow side, a yellow
# pencil stuck in its head, a cartoon sweat drop and jiggle lines, a marker-drawn face.
from models._slimepool import *

INKO = rgb(16, 14, 22)
PAPER = hexc("fffdf5")
CRAYON = hexc("2f78ff")
BLUSH = hexc("ff6f9a")
PENCIL, PENCIL_D = hexc("ffc81e"), hexc("f0a400")
WOOD, LEAD = hexc("f6cf98"), hexc("3a3640")
FERRULE, FERRULE_D = hexc("d6dbe4"), hexc("9aa2b2")
ERASER = hexc("ff8fae")
DROP, DROP_L = hexc("62c8ff"), hexc("d8f3ff")

HULL_ATTR = "ink_hull"


def hull(o, t=0.06, smooth=None):
    """inverted-hull outline: copy of o pushed out t along the vertex normals, painted ink and
    tagged; its faces get flipped after ship() (finish() recalcs normals outward)."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.transform(o.matrix_world)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * t
    h = obj_from_bm(o.name + "Ink", bm, INKO)
    a = h.data.attributes.new(HULL_ATTR, "INT", "FACE")
    a.data.foreach_set("value", [1] * len(h.data.polygons))
    sm = all(p.use_smooth for p in o.data.polygons) if smooth is None else smooth
    return keep(h, sm)


def inked(o, t=0.06, smooth=None):
    return [o, hull(o, t, smooth)]


def flip_hulls(o):
    """after ship(): turn the tagged hull faces inside out, drop the tag."""
    a = o.data.attributes.get(HULL_ATTR)
    if a is None:
        return
    flags = [d.value for d in a.data]
    bm = bmesh.new(); bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.reverse_faces(bm, faces=[bm.faces[i] for i, f in enumerate(flags) if f])
    bm.to_mesh(o.data); bm.free()
    o.data.update()  # the tag stays for the preview material (the FBX exporter ignores it)


def cull_backfaces_in_preview(o):
    """Cycles renders both sides; Roblox MeshParts are single-sided (DoubleSided off). Make the
    preview match: back faces -> transparent. Render-only, the FBX carries no material."""
    if os.environ.get("DOODLE_DOUBLE") == "1":
        return
    for mat in o.data.materials:
        nt = mat.node_tree
        out = nt.nodes["Material Output"]
        bsdf = nt.nodes["Principled BSDF"]
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mx = nt.nodes.new("ShaderNodeMixShader")
        # Cycles also traces light from INSIDE the hull, where its flipped faces face the body and
        # block every light ray (the body went black); a rasterizer has no such rays, so the hull
        # only exists for camera rays here.
        tag = nt.nodes.new("ShaderNodeAttribute"); tag.attribute_name = HULL_ATTR
        lp = nt.nodes.new("ShaderNodeLightPath")
        notcam = nt.nodes.new("ShaderNodeMath"); notcam.operation = "SUBTRACT"
        notcam.inputs[0].default_value = 1.0
        nt.links.new(lp.outputs["Is Camera Ray"], notcam.inputs[1])
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
        nt.links.new(tag.outputs["Fac"], mul.inputs[0]); nt.links.new(notcam.outputs[0], mul.inputs[1])
        mxv = nt.nodes.new("ShaderNodeMath"); mxv.operation = "MAXIMUM"
        nt.links.new(geo.outputs["Backfacing"], mxv.inputs[0]); nt.links.new(mul.outputs[0], mxv.inputs[1])
        nt.links.new(mxv.outputs[0], mx.inputs["Fac"])
        nt.links.new(bsdf.outputs["BSDF"], mx.inputs[1])
        nt.links.new(tr.outputs["BSDF"], mx.inputs[2])
        nt.links.new(mx.outputs["Shader"], out.inputs["Surface"])


def paint_faces(o, fn):
    """crisp per-face colour from the face centre: fn(centre) -> rgba."""
    bm = bmesh.new(); bm.from_mesh(o.data)
    col = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        c = fn(f.calc_center_median())
        for lp in f.loops:
            lp[col] = c
    bm.to_mesh(o.data); bm.free()
    return o


# ---------------------------------------------------------------- body: paper, hand-drawn wobble
b = Body([(0, 1.18), (0.12, 1.44), (0.45, 1.58), (1.0, 1.52), (1.7, 1.24), (2.3, 0.8), (2.7, 0.32), (2.84, 0)],
         color=PAPER, segs=36, sub=3, shade=0.25, gloss=0.0,
         bump=lambda a, z: 0.03 * math.sin(3 * a + 1.3 + z) + 0.015 * math.sin(7 * a),
         lean=lambda z: 0.12 * max(0.0, (z - 1.8) / 1.0) ** 2)
parts = inked(b.obj, 0.075)

# ---------------------------------------------------------------- crayon hatching (shadow side)
k = 0
for yaw in range(-40, -200, -24):
    rows = (0.5, 1.05, 1.6) if yaw < -70 else (0.5, 1.0)
    for z in rows:
        fr = frame_at(yaw, z)
        for du in (-0.24, 0.0, 0.24):
            ln = 0.62 - 0.12 * abs(du) * 4
            parts.append(decal(f"Hatch{k}", rect(du, 0, 0.07, ln, math.radians(38)), CRAYON, fr,
                               off=0.012, th=0.012, on=["Body"], step=0.22))
            k += 1

# cross-hatch on the darkest part (low back-left)
for yaw in range(-110, -200, -30):
    fr = frame_at(yaw, 0.55)
    for du in (-0.2, 0.05):
        parts.append(decal(f"Hatch{k}", rect(du, 0, 0.06, 0.5, math.radians(-40)), CRAYON, fr,
                           off=0.016, th=0.012, on=["Body"], step=0.22))
        k += 1

# ---------------------------------------------------------------- pencil stuck in the head
pd = Vector((0.42, 0.18, 1.0)).normalized()
pbase = Vector((0.3, 0.08, 2.15))
pprof = [(0, 0), (0.1, 0.035), (0.38, 0.15), (0.38, 0.165), (1.5, 0.165), (1.5, 0.175), (1.78, 0.175),
         (1.78, 0.16), (2.02, 0.16), (2.08, 0.11), (2.1, 0)]
pencil = lathe("Pencil", pprof, PENCIL, pos=pbase, axis=pd, segs=6, smooth=False)


def pcol(c):
    t = (c - pbase).dot(pd)
    if t < 0.12:
        return LEAD
    if t < 0.37:
        return WOOD
    if t < 1.5:
        return PENCIL
    if t < 1.79:
        return FERRULE if int((t - 1.5) / 0.07) % 2 == 0 else FERRULE_D
    return ERASER


paint_faces(pencil, pcol)
parts += inked(pencil, 0.045, smooth=False)

# ---------------------------------------------------------------- sweat drop + jiggle lines
dd = Vector((0.35, 0, 1)).normalized()
drop = lathe("Drop", [(0, 0), (0.06, 0.13), (0.17, 0.18), (0.3, 0.13), (0.45, 0.05), (0.55, 0)],
             DROP, pos=(-1.62, 0.0, 2.2), axis=dd, segs=12, sub=0)
parts += inked(drop, 0.04)
parts.append(ball("DropHi", 0.05, (-1.7, -0.17, 2.37), DROP_L, squash=(1, 0.6, 1.5)))

for sd in (-1, 1):
    for j, (rad, dv) in enumerate(((0.32, 0.0), (0.5, 0.05))):
        a0, a1 = (140, 220) if sd < 0 else (-40, 40)
        poly = arc(0, 0, rad, a0, a1, 0.07, n=8)
        cx = sd * (1.55 + 0.1)
        X = Vector((1, sd * 0.75, 0)).normalized()  # plane faces front + its own side
        parts.append(slab(f"Jiggle{sd}{j}", poly, 0.06, (cx, -0.35, 0.75 + dv), X, (0, 0, 1), INKO))

# hand-drawn sparkles: yellow crayon stars with ink rims
STAR = hexc("ffd83a")
for j, (pos, r, rot) in enumerate((((-1.3, -0.45, 3.0), 0.26, 80), ((1.55, 0.1, 2.0), 0.18, 100), ((-1.7, 0.3, 1.55), 0.15, 95))):
    st = slab(f"Star{j}", star(0, 0, r, r * 0.48, n=5, rot=rot), 0.07, pos, (1, -0.45 if pos[0] < 0 else 0.45, 0), (0, 0, 1), STAR)
    parts += inked(st, 0.035, smooth=False)

# ---------------------------------------------------------------- marker face
f = Face(b, eye_u=0.45, eye_v=1.62, mouth_v=1.12, ink=INKO)
for sd in (-1, 1):
    u = sd * 0.45
    f.d(f"Eye{sd}", oval(u, 1.62, 0.3, 0.52, n=16), INKO, off=0.015)
    f.d(f"EyeHi{sd}", oval(u - 0.05, 1.74, 0.11, 0.15, n=10), WHITE, off=0.04, th=0.012)
    for j in range(3):
        f.d(f"Blush{sd}{j}", rect(sd * 0.82 + (j - 1) * 0.1, 1.28, 0.045, 0.2, math.radians(-25)), BLUSH, off=0.018, th=0.012)
f.d("Mouth", half_oval(0, 1.2, 0.62, 0.34, n=14), INKO, off=0.015)
f.d("Tongue", oval(0.04, 0.98, 0.26, 0.11), hexc("ff5a7a"), off=0.035, th=0.012)
f.d("Brow1", arc(0.47, 1.86, 0.2, 50, 130, 0.06, n=6), INKO, off=0.02)
f.d("Brow-1", rect(-0.45, 2.0, 0.34, 0.06, math.radians(8)), INKO, off=0.02)
parts += f.parts

o = ship("slime_doodle", parts)
flip_hulls(o)
cull_backfaces_in_preview(o)
