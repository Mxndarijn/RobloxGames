"""Render the 57 item icons (512x512 RGBA, transparent background) with ONE shared rig.

    blender -b --factory-startup --python shared/modeling-kit/tools/icons/render_icons.py -- --out <dir> [--only id,id] [--samples 40]

Every icon: orthographic camera at the same 3/4 angle (recipe may override `view`), the same
camera-relative key (top-left) + fill + ambient, Cycles CPU, transparent film. The subject is
centred and scaled to FILL of the frame (the outline pass then adds a thin soft dark rim).
Recipes live in recipes.py (one function per id); outline.py post-processes the raw renders.
"""
import math, os, subprocess, sys, time
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import helpers as H  # noqa: E402
import recipes  # noqa: E402

RES = 512
FILL = 0.80  # subject (without the outline) fills this share of the larger frame axis
YAW, PITCH = 32.0, 24.0  # default 3/4 view: from front-left, slightly above


def argv():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = {"out": os.path.join(H.KIT, "out", "icons"), "only": None, "samples": 40, "raw": "/tmp/icons_raw"}
    i = 0
    while i < len(a):
        k = a[i].lstrip("-")
        o[k] = a[i + 1]
        i += 2
    o["samples"] = int(o["samples"])
    o["only"] = o["only"].split(",") if o["only"] else None
    return o


def world_points(objs):
    pts = []
    for o in H.meshes_of(objs):
        mw = o.matrix_world
        pts += [mw @ v.co for v in o.data.vertices]
    return pts


def rig(objs, yaw, pitch, fill, samples, shift=(0.0, 0.0)):
    sc = bpy.context.scene
    y, p = math.radians(yaw), math.radians(pitch)
    to_cam = Vector((-math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))
    fwd = -to_cam
    right = fwd.cross(Vector((0, 0, 1))).normalized()
    up = right.cross(fwd).normalized()
    pts = world_points(objs)
    xs = [q.dot(right) for q in pts]
    ys = [q.dot(up) for q in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    cz = sum(q.dot(fwd) for q in pts) / len(pts)
    center = right * cx + up * cy + fwd * cz
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = span / fill
    cam.clip_start, cam.clip_end = 0.1, 500
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    co.location = center + to_cam * 60 + right * shift[0] * cam.ortho_scale + up * shift[1] * cam.ortho_scale
    co.rotation_euler = (-fwd).to_track_quat("Z", "Y").to_euler()
    sc.camera = co

    def sun(name, strength, direction_to_light, color, angle):
        l = bpy.data.lights.new(name, "SUN")
        l.energy, l.color, l.angle = strength, color, math.radians(angle)
        lo = bpy.data.objects.new(name, l)
        sc.collection.objects.link(lo)
        lo.rotation_euler = (-direction_to_light.normalized()).to_track_quat("-Z", "Y").to_euler()
        return lo

    # soft top-left key (relative to the camera), cool fill from the right, low rim from behind
    key = (-right * 0.55 + up * 0.75 + to_cam * 0.62)
    sun("key", 3.4, key, (1.0, 0.96, 0.9), 22)
    sun("fill", 0.8, (right * 0.8 + up * 0.15 + to_cam * 0.5), (0.85, 0.92, 1.0), 40)
    sun("rim", 0.9, (right * 0.4 + up * 0.5 - to_cam * 0.9), (1.0, 1.0, 1.0), 30)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.95, 0.96, 1.0, 1)
    bg.inputs["Strength"].default_value = 0.62
    sc.world = w

    sc.render.engine = "CYCLES"
    c = sc.cycles
    c.device = "CPU"
    c.samples = samples
    c.use_denoising = True
    c.max_bounces = 2
    c.diffuse_bounces = 1
    c.glossy_bounces = 1
    c.transmission_bounces = 0
    c.use_adaptive_sampling = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.render.filter_size = 1.0
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.15
    sc.render.threads = int(os.environ.get("ICON_THREADS", "4"))


def glass_material(clear=False):
    """Semi-transparent tinted glass for lenses / flasks / nets (objects named Glass*; GlassClear* is
    a much fainter pane so a slime behind it keeps its full colour)."""
    name = "icon_glass_clear" if clear else "icon_glass"
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Alpha"].default_value = 0.14 if clear else 0.38
    b.inputs["Roughness"].default_value = 0.15
    return m


def prep_materials(objs):
    for o in H.meshes_of(objs):
        if "Col" not in o.data.color_attributes:
            H.paint(o, H.C["grey"])
        o.data.color_attributes.active_color = o.data.color_attributes["Col"]
        o.data.materials.clear()
        o.data.materials.append(glass_material(o.name.startswith("GlassClear")) if o.name.startswith("Glass") else H.vcol_material("icon_vcol"))


def main():
    o = argv()
    ids = o["only"] or list(recipes.ORDER)
    os.makedirs(o["raw"], exist_ok=True)
    t0 = time.time()
    done = []
    for n, icon_id in enumerate(ids):
        t1 = time.time()
        reset_scene()
        rec = recipes.REGISTRY[icon_id]
        objs = rec["fn"]()
        keep = set()

        def mark(o):
            keep.add(o)
            for c in o.children:
                mark(c)
        for ob in objs:
            mark(ob)
        for ob in list(bpy.data.objects):  # recipes may build scratch parts they do not return
            if ob not in keep:
                bpy.data.objects.remove(ob)
        bpy.context.view_layer.update()
        prep_materials(objs)
        yaw, pitch = rec.get("view", (YAW, PITCH))
        rig(objs, yaw, pitch, rec.get("fill", FILL), o["samples"])
        bpy.context.scene.render.filepath = os.path.join(o["raw"], icon_id + ".png")
        bpy.ops.render.render(write_still=True)
        done.append(icon_id)
        print(f"[{n + 1}/{len(ids)}] {icon_id} {time.time() - t1:.1f}s", flush=True)
    print(f"rendered {len(done)} in {time.time() - t0:.0f}s", flush=True)
    r = subprocess.run([sys.executable if False else "python3", os.path.join(HERE, "outline.py"), o["raw"], o["out"], ",".join(done)])
    if r.returncode:
        sys.exit("outline failed")


def reset_scene():
    H.reset_scene()
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.curves):
        for b in list(blk):
            blk.remove(b)


if __name__ == "__main__":
    main()
