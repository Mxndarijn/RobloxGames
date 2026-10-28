# Skinned rig for pool slimes (SLIME_RIG=1): bones inside the species mesh so the game can move the
# jelly and the accessories with Bone.Transform (CFrame only: Roblox bones don't scale).
#
#   Root   at the foot: hops, whole-body lean
#   Top    mid-body up: squash (moves down), wobble (tilts); the face and top accessories ride it
#   SideL/SideR/SideF/SideB: push out while Top squashes, so the jelly keeps its volume
#   Eyes   (child of Top): the open eyes; moving it into the body hides them
#   Lids   (child of Top): closed-eye arcs hidden inside the body; moving them out shows them
#          -> blink = Eyes in + Lids out for ~0.12 s. The same trick swaps whole expressions.
#   Wing*/Ear*/Ant*/Tail*/Fin*/Pec*/Tent*: one bone per accessory part, pivot where it meets the body
#
# Weights come from part names (see ROLE_PREFIXES), so species scripts need no rig code.
import math
import bpy
from mathutils import Vector

SECONDARY = ("Wing", "Ear", "Ant", "Tail", "Fin", "Pec", "Tent", "Ribbon", "Band")
PAIRED = ("Wing", "Ear", "Ant", "Fin", "Pec")  # one bone per side: WingBone-1 + Wing-1 move together
FACE = ("Eye", "Iris", "Pupil", "Mouth", "Teeth", "Tongue", "Cheek", "Brow", "Lash", "Nose", "Whisker",
        "Stache", "Lens", "Glint", "Bridge", "Visor", "Tooth", "Fang", "Tear", "Freckle", "Unibrow")
EYES = ("Eye", "Iris", "Pupil")  # EyeHi*, EyeW*, EyeC* start with Eye too
LID_IN = 0.15  # studs the hidden lids sit inside the body


def _role(name):
    if name.startswith("BlinkLid"):
        return "Lids", None
    for p in SECONDARY:
        if name.startswith(p):
            return "sec", p
    if name.startswith(EYES):
        return "Eyes", None
    if name.startswith(FACE):
        return "face", None
    if name.startswith("Body"):
        return "body", None
    return "acc", None


def add_lids(parts):
    """closed-eye arcs (^ shape flipped: content closed lids) hidden behind each round eye."""
    from models import _slimepool as sp
    out = []
    for o in parts:
        if o.name.split(".")[0] not in ("Eye-1", "Eye1"):
            continue
        xs = [v.co.x for v in o.data.vertices]
        zs = [v.co.z for v in o.data.vertices]
        u, v = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
        w = max(xs) - min(xs)
        side = 1 if u > 0 else -1
        try:  # an eye that isn't on the Body front (custom eyes, sockets) gets no lid
            out.append(sp.decal(f"BlinkLid{side}", sp.arc(u, v + 0.02, w * 0.36, 200, 340, 0.08), sp.INK,
                                off=-LID_IN, th=0.03, on=getattr(sp, "FACE_ON", None) or ["Body"]))
        except ValueError:
            pass
    return out


SKIN_GAP = 0.08  # studs: a part with every vertex this close to the Body is a skin patch


def _hugs(o, body_bvh):
    for v in o.data.vertices:
        hit = body_bvh.find_nearest(o.matrix_world @ v.co)
        if hit[0] is None or hit[3] > SKIN_GAP:
            return False
    return True


def tag_parts(parts):
    """store each part's role as vertex groups before finish() joins them (groups survive join).
    Paired accessories share one bone per side; a non-face part that touches an animated part
    (a tail's arrow tip, suckers on a tentacle) joins that part's bone."""
    from mathutils.kdtree import KDTree
    from models import _slimepool as sp
    roles = []
    for o in parts:
        role, kind = _role(o.name)
        key = None
        if role == "sec":
            xs = [v.co.x for v in o.data.vertices]
            cx = (min(xs) + max(xs)) / 2
            key = kind + ("L" if cx > 0.05 else "R" if cx < -0.05 else "C") if kind in PAIRED else o.name.split(".")[0]
        roles.append([o, role, key])
    secs = [(r[2], r[0]) for r in roles if r[1] == "sec"]
    trees = []
    for key, so in secs:
        kd = KDTree(len(so.data.vertices))
        for i, v in enumerate(so.data.vertices):
            kd.insert(v.co, i)
        kd.balance()
        trees.append((key, kd))
    body_bvh = sp.SURFACES.get("Body")
    for r in roles:  # a patch painted onto the skin (bib, emblem, moss) bends with the jelly like the face
        o, role, _ = r
        if role == "acc" and body_bvh and _hugs(o, body_bvh):
            r[1] = "face"
    for r in roles:
        o, role, key = r
        if role != "acc" or not trees:
            continue
        c = sum((v.co for v in o.data.vertices), Vector()) / len(o.data.vertices)
        best = min(((kd.find(c)[2], k) for k, kd in trees), key=lambda t: t[0])
        d_body = (body_bvh.find_nearest(c)[3] if body_bvh else 9.0)
        size = max((v.co - c).length for v in o.data.vertices)
        if best[0] < max(0.25, size * 1.2) and best[0] < d_body:
            r[1], r[2] = "sec", best[1]
    for o, role, key in roles:
        g = o.vertex_groups.new(name=f"S_{key}" if role == "sec" else f"R_{role}")
        g.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    return [(o.name, role, key) for o, role, key in roles]


def _bell(x, c, w):
    return math.exp(-((x - c) / w) ** 2)


def build_rig(o, body_h=None):
    """armature + weights on the finished mesh o (object space = slime frame, bottom centre origin)."""
    me = o.data
    groups = {g.index: g.name for g in o.vertex_groups}
    vg_of = []
    for v in me.vertices:
        vg_of.append(groups[v.groups[0].group] if v.groups else "R_acc")
    body = [v.co for v, g in zip(me.vertices, vg_of) if g == "R_body"]
    H = body_h or max(c.z for c in body)
    R = max(math.hypot(c.x, c.y) for c in body)
    # secondary parts: pivot = the part vertex closest to the body axis at its height
    sec = {}
    for v, g in zip(me.vertices, vg_of):
        if g.startswith("S_"):
            sec.setdefault(g, []).append(v.co.copy())

    arm = bpy.data.armatures.new(o.name + "_rig")
    ao = bpy.data.objects.new(o.name + "_rig", arm)
    bpy.context.scene.collection.objects.link(ao)
    bpy.context.view_layer.objects.active = ao
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.edit_bones

    def bone(name, head, tail, parent=None):
        b = eb.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        if parent:
            b.parent = eb[parent]
        return b

    bone("Root", (0, 0, 0), (0, 0, 0.3 * H))
    bone("Top", (0, 0, 0.45 * H), (0, 0, H), "Root")
    zs = 0.38 * H
    for n, d in (("SideL", (1, 0)), ("SideR", (-1, 0)), ("SideF", (0, -1)), ("SideB", (0, 1))):
        bone(n, (d[0] * R * 0.9, d[1] * R * 0.9, zs), (d[0] * R * 0.9, d[1] * R * 0.9, zs + 0.3), "Root")
    bone("Eyes", (0, -R, 0.55 * H), (0, -R - 0.3, 0.55 * H), "Top")
    bone("Lids", (0, -R, 0.5 * H), (0, -R - 0.3, 0.5 * H), "Top")
    pivots = {}
    for g, pts in sec.items():
        c = sum(pts, Vector()) / len(pts)
        piv = min(pts, key=lambda p: math.hypot(p.x, p.y) + 0.3 * abs(p.z - c.z))
        tail = c if (c - piv).length > 0.05 else piv + Vector((0, 0, 0.3))
        name = g[2:]
        bone(name, piv, tail, "Top" if piv.z > 0.45 * H else "Root")
        pivots[name] = (piv, c)
    bpy.ops.object.mode_set(mode="OBJECT")

    vg = {n: o.vertex_groups.new(name=n) for n in ["Root", "Top", "SideL", "SideR", "SideF", "SideB", "Eyes", "Lids"] + list(pivots)}

    def body_w(p):
        top = 0.15 + 0.85 * min(1.0, max(0.0, (p.z - 0.12 * H) / (0.75 * H)))
        top = top if p.z > 0.02 else 0.0
        w = {"Top": top, "Root": 1 - top}
        rho = math.hypot(p.x, p.y)
        bell = _bell(p.z, zs, 0.35 * H) * min(1.0, rho / max(R, 1e-6)) * 0.55
        for n, (dx, dy) in (("SideL", (1, 0)), ("SideR", (-1, 0)), ("SideF", (0, -1)), ("SideB", (0, 1))):
            k = (p.x * dx + p.y * dy) / max(rho, 1e-6)
            if k > 0:
                w[n] = bell * k * k
        s = sum(w.values())
        # keep the 4 biggest (Roblox: max 4 influences per vertex)
        top4 = sorted(w.items(), key=lambda kv: -kv[1])[:4]
        s = sum(x for _, x in top4)
        return {n: x / s for n, x in top4 if x > 1e-4}

    eye_w = []
    for v, g in zip(me.vertices, vg_of):
        p = v.co
        if g == "R_body" or g == "R_face":
            ws = body_w(p)
        elif g in ("R_Eyes", "R_Lids"):  # ride the jelly like the face; the Top share goes to Eyes/Lids
            ws = body_w(p)
            k = "Eyes" if g == "R_Eyes" else "Lids"
            ws[k] = ws.pop("Top", 0.0)
            eye_w.append(ws[k])
        elif g.startswith("S_"):
            ws = {g[2:]: 1.0}
        else:  # rigid accessory: high ones ride Top, low ones the body weights where they sit
            ws = {"Top": 1.0} if p.z > 0.6 * H else body_w(p)
        for n, x in ws.items():
            vg[n].add([v.index], x, "REPLACE")
    for g in list(o.vertex_groups):
        if g.name.startswith(("R_", "S_")):
            o.vertex_groups.remove(g)
    # blink offsets are scaled by this: the eyes only get this share of an Eyes/Lids move
    ao["eye_share"] = sum(eye_w) / len(eye_w) if eye_w else 1.0
    o.parent = ao
    o.modifiers.new("Armature", "ARMATURE").object = ao
    return ao, {"H": H, "R": R, "pivots": {k: (tuple(a), tuple(b)) for k, (a, b) in pivots.items()}}
