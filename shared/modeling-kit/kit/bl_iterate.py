"""Runs INSIDE Blender (started by iterate.py; don't call directly):

    blender -b --factory-startup -P kit/bl_iterate.py -- --model M --out DIR --name N [...]

One process: reset scene -> build/import the model -> stats -> 4 renders (+ turntable)
-> FBX export. Writes DIR/.tiles/<stem>_<view>.png and DIR/<stem>.stats.json, where
stem = name or name_<tag> (quick/roblox); iterate.py then composes the sheet."""
import argparse, json, math, os, runpy, sys, time

import bmesh, bpy
from mathutils import Vector

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KIT)

# Roblox / kit budgets (see CLAUDE.md "Roblox limits")
TRI_TARGET = (500, 2000)  # props: warn outside
TRI_FAIL = 10000  # per mesh: fail at or above (Roblox hard limit is 20000)
AXIS_FAIL = 2048  # studs per axis (MeshPart max size)
FBX_FAIL = 20 * 1024 * 1024  # Open Cloud upload limit

# --look roblox: the game's own Lighting (steal-a-slime default.project.json, read 2026-10-15):
# Future, Brightness 2.5, ClockTime 14.5, GeographicLatitude 25, ShadowSoftness 0.25,
# ExposureCompensation 0.1, Ambient (0.275,0.282,0.333), OutdoorAmbient (0.490,0.471,0.549),
# ColorShift_Top (1,0.882,0.725). Colours below are those values converted to linear.
RBX = {
    "sun_dir": (-0.45, -0.55, 0.70),  # light travels against this; ~45 deg up (ClockTime 14.5 at lat 25), front-left
    "sun_strength": 2.5,  # Brightness 2.5; Cycles diffuse = albedo*S/pi, so ~0.8x albedo on a face square to the sun
    "sun_color": (1.0, 0.89, 0.76),  # halfway to ColorShift_Top: Roblox tints sunlit faces warm
    "sun_angle": 3.0,  # degrees; ShadowSoftness 0.25 -> fairly crisp shadows
    "ambient": (0.061, 0.064, 0.091),  # Lighting.Ambient: flat, never occluded (added as emission)
    "outdoor": (0.144, 0.124, 0.174),  # OutdoorAmbient - Ambient: the sky part, occluded (world light)
    "sky_bg": (0.57, 0.62, 0.74),  # what the camera sees behind the model (Atmosphere colour, linear)
    "exposure": 0.1,  # ExposureCompensation
    "roughness": 0.55,  # SmoothPlastic-ish
    "specular": 0.2,  # Principled "Specular IOR Level": low highlight
    "ground": (0.26, 0.27, 0.29, 1),
}

VIEWS = [  # (label, direction from target to camera, Blender Z up; model front faces -Y)
    ("front", (0.0, -1.0, 0.12)),
    ("side", (1.0, 0.0, 0.12)),
    ("back-3/4", (0.75, 0.85, 0.45)),
    ("top-3/4", (-0.7, -0.7, 1.15)),
    ("hero", (-0.45, -1.0, 0.32)),  # front-left 3/4, low: lineups and concept renders
]


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--model", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--engine", default="cycles", choices=["cycles", "workbench", "eevee"])
    p.add_argument("--res", type=int, default=256)
    p.add_argument("--samples", type=int, default=16)
    p.add_argument("--no-export", action="store_true")
    p.add_argument("--no-ref", action="store_true")
    p.add_argument("--views", default="0,1,2,3")
    p.add_argument("--quick", action="store_true", help="Workbench clay + cavity + outline (shape only)")
    p.add_argument("--look", default="default", choices=["default", "roblox"])
    p.add_argument("--turntable", type=int, default=0, help="also render N views around the model")
    p.add_argument("--tag", default="", help="suffix for stats/tiles so modes don't overwrite each other")
    p.add_argument("--ground", default="", help="ground plane colour R,G,B (sRGB 0-255); default dark grey")
    return p.parse_args(argv)


# ------------------------------------------------------------------ model
def load_model(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(path)[1].lower()
    if ext == ".py":
        runpy.run_path(path, run_name="__main__")
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path, forward_axis="NEGATIVE_Z", up_axis="Y")
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        sys.exit(f"bl_iterate: unsupported model type {ext}")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.visible_get()]
    if ext != ".py":  # imported: show its vertex colours like the game would
        from lib.color import vcol_material
        for o in meshes:
            ca = o.data.color_attributes
            if len(ca):
                mat = vcol_material("import_vcol_" + ca[0].name)
                mat.node_tree.nodes["Color Attribute"].layer_name = ca[0].name
                o.data.materials.clear()
                o.data.materials.append(mat)
    return meshes


def _vcol_driven(mat):
    """True if the material's colour comes from a colour attribute (what survives in Roblox)."""
    if not mat.use_nodes:
        return False
    return any(n.type in ("VERTEX_COLOR", "ATTRIBUTE") for n in mat.node_tree.nodes)


def _has_vertex_alpha(me):
    ca = me.color_attributes.active_color or (me.color_attributes[0] if len(me.color_attributes) else None)
    if ca is None or not len(ca.data):
        return False
    vals = [0.0] * (len(ca.data) * 4)
    ca.data.foreach_get("color", vals)
    return min(vals[3::4]) < 0.99


def mesh_stats(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    per, lo, hi = [], Vector((1e9,) * 3), Vector((-1e9,) * 3)
    mats = set()
    for o in objs:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        bm = bmesh.new()
        bm.from_mesh(me)
        nm = sum(1 for e in bm.edges if not e.is_manifold)
        tri = sum(len(f.verts) - 2 for f in bm.faces)
        ngons = sum(1 for f in bm.faces if len(f.verts) > 4)
        mw = o.matrix_world
        olo, ohi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
        for v in bm.verts:
            w = mw @ v.co
            for i in range(3):
                olo[i] = min(olo[i], w[i])
                ohi[i] = max(ohi[i], w[i])
        bm.free()
        for i in range(3):
            lo[i], hi[i] = min(lo[i], olo[i]), max(hi[i], ohi[i])
        ms = [m.name for m in o.data.materials if m]
        mats.update(ms)
        slots = o.data.materials
        used = sorted({p.material_index for p in me.polygons})
        used_mats = [slots[i] for i in used if i < len(slots) and slots[i]]
        d = ohi - olo
        per.append({
            "name": o.name,
            "tris": tri,
            "verts": len(me.vertices),
            "ngons": ngons,
            "non_manifold_edges": nm,
            "size_studs": [round(d.x, 3), round(d.z, 3), round(d.y, 3)],
            "materials": ms,
            "color_attributes": [a.name for a in o.data.color_attributes],
            "modifiers": [m.type for m in o.modifiers],
            "materials_used": [m.name for m in used_mats],
            "materials_not_vcol": [m.name for m in used_mats if not _vcol_driven(m)],
            "image_textures": sorted({n.image.name for m in used_mats if m.use_nodes for n in m.node_tree.nodes
                                      if n.type == "TEX_IMAGE" and n.image}),
            "vertex_alpha_below_1": _has_vertex_alpha(o.data),
        })
        ev.to_mesh_clear()
    return per, lo, hi, sorted(mats)


def judge(per, size):
    fails, warns = [], []
    total = sum(m["tris"] for m in per)
    if not per:
        fails.append("no mesh objects")
    for m in per:
        if m["tris"] >= TRI_FAIL:
            fails.append(f"{m['name']}: {m['tris']} tris >= {TRI_FAIL}")
        if m["non_manifold_edges"]:
            warns.append(f"{m['name']}: {m['non_manifold_edges']} non-manifold edges")
        if not m["color_attributes"]:
            warns.append(f"{m['name']}: no vertex colours (will import white/grey)")
        # what won't survive Roblox import: a MeshPart has ONE Material/Color/TextureID/SurfaceAppearance
        if len(m["materials_used"]) > 1:
            warns.append(f"{m['name']}: {len(m['materials_used'])} materials -> Roblox keeps one per MeshPart; "
                         "bake colours into vertex colours (finish())")
        if m["materials_not_vcol"]:
            warns.append(f"{m['name']}: material colour {m['materials_not_vcol']} not from vertex colours; "
                         "Roblox ignores FBX material colours")
        if m["image_textures"]:
            warns.append(f"{m['name']}: image textures {m['image_textures']} are not carried by the kit's FBX upload; "
                         "needs a separate TextureID/SurfaceAppearance")
        if len(m["color_attributes"]) > 1:
            warns.append(f"{m['name']}: {len(m['color_attributes'])} colour attributes; Roblox uses one, keep only 'Col'")
        if m["vertex_alpha_below_1"]:
            warns.append(f"{m['name']}: vertex alpha < 1 is not used as transparency in Roblox (use Part.Transparency)")
    if any(s > AXIS_FAIL for s in size):
        fails.append(f"size {size} > {AXIS_FAIL} studs on an axis")
    if per and not TRI_TARGET[0] <= total <= TRI_TARGET[1]:
        warns.append(f"{total} tris outside prop target {TRI_TARGET[0]}-{TRI_TARGET[1]}")
    if len(per) > 1:
        warns.append(f"{len(per)} mesh objects -> {len(per)} MeshParts; join with lib.finish()")
    return total, fails, warns


# ------------------------------------------------------------------ render rig
def kit_collection():
    c = bpy.data.collections.new("_kit")
    bpy.context.scene.collection.children.link(c)
    return c


def add(col, name, data):
    o = bpy.data.objects.new(name, data)
    col.objects.link(o)
    return o


def plain_mat(name, color, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = color
    return m


def ground_color(spec):
    """'R,G,B' (sRGB 0-255) -> linear RGBA for the ground material; '' -> the default dark grey."""
    if not spec:
        return (0.26, 0.27, 0.29, 1)
    lin = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return tuple(lin(int(v) / 255) for v in spec.split(",")) + (1,)


def build_rig(col, lo, hi, ref, ground=""):
    """Ground plane + optional 5-stud avatar block for scale. Returns framing bbox."""
    size = hi - lo
    ext = max(size.x, size.y, size.z, 1.0)
    me = bpy.data.meshes.new("_ground")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=ext * 6)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(plain_mat("_ground", ground_color(ground)))
    g = add(col, "_ground", me)
    g.location = ((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)
    flo, fhi = lo.copy(), hi.copy()
    if ref:
        # blocky R15-ish stand-in: legs+torso 2x1x3, head 1.2 cube -> ~5 studs
        me = bpy.data.meshes.new("_ref")
        bm = bmesh.new()
        for sx, sy, sz, z in ((2.0, 1.0, 3.6, 1.8), (1.2, 1.2, 1.2, 4.3)):
            r = bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=r["verts"])
            bmesh.ops.translate(bm, vec=(0, 0, z), verts=r["verts"])
        bm.to_mesh(me)
        bm.free()
        me.materials.append(plain_mat("_ref", (0.80, 0.80, 0.84, 1)))
        o = add(col, "_ref", me)
        # back-left corner (-X, +Y): beside the model in all 4 views, never in front of it
        o.location = (lo.x - 1.4, hi.y + 1.2, lo.z)
        flo.x = min(flo.x, lo.x - 2.4)
        fhi.y = max(fhi.y, hi.y + 1.8)
        fhi.z = max(fhi.z, lo.z + 4.9)
    return flo, fhi


def setup_render(a):
    sc = bpy.context.scene
    r = sc.render
    r.resolution_x = r.resolution_y = a.res
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.film_transparent = False
    sc.view_settings.view_transform = "Standard"  # colours as picked, like Studio (no Filmic/AgX curve)
    sc.view_settings.look = "None"
    w = bpy.data.worlds.new("_world")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.58, 0.62, 0.68, 1)
    bg.inputs["Strength"].default_value = 0.55
    sc.world = w
    if a.look == "roblox":
        roblox_world(w)
        sc.view_settings.exposure = RBX["exposure"]
    if a.quick:
        r.engine = "BLENDER_WORKBENCH"
        s = sc.display.shading
        s.light = "STUDIO"
        s.color_type = "SINGLE"  # clay: judge shape, not colour
        s.single_color = (0.80, 0.77, 0.72)
        s.show_shadows = True
        sc.display.shadow_focus = 0.6
        s.show_cavity = True
        s.cavity_type = "BOTH"  # screen-space ridges/valleys + world-space AO-ish
        s.cavity_ridge_factor = s.curvature_ridge_factor = 0.35  # low: flat-shaded facets would all light up
        s.cavity_valley_factor = s.curvature_valley_factor = 1.4
        s.show_object_outline = True
        s.object_outline_color = (0.05, 0.05, 0.06)
        sc.display.render_aa = "8"
        return
    if a.engine == "cycles":
        r.engine = "CYCLES"
        c = sc.cycles
        c.device = "CPU"
        if os.environ.get("KIT_GPU"):  # KIT_GPU=OPTIX|CUDA|HIP|METAL: render on the GPU when one is there
            cp = bpy.context.preferences.addons["cycles"].preferences
            try:
                cp.compute_device_type = os.environ["KIT_GPU"]
                cp.get_devices()
                for dev in cp.devices:
                    dev.use = dev.type != "CPU"
                if any(dev.use for dev in cp.devices):
                    c.device = "GPU"
            except TypeError:
                pass  # unknown backend on this machine: stay on the CPU
        c.samples = a.samples
        c.use_adaptive_sampling = False
        c.use_denoising = True
        c.denoiser = "OPENIMAGEDENOISE"
        c.max_bounces = 3
        c.diffuse_bounces = 0 if a.look == "roblox" else 2  # Roblox has no real light bounce
        c.glossy_bounces = 1
        c.transmission_bounces = 0
        c.transparent_max_bounces = 2
        c.caustics_reflective = c.caustics_refractive = False
        c.use_auto_tile = False
        r.use_persistent_data = True  # BVH/scene kept between the 4 renders
    elif a.engine == "workbench":
        r.engine = "BLENDER_WORKBENCH"
        s = sc.display.shading
        s.light = "STUDIO"
        s.color_type = "VERTEX"
        s.show_shadows = True
        s.show_cavity = True
    else:
        r.engine = "BLENDER_EEVEE_NEXT"
        sc.eevee.taa_render_samples = a.samples


def roblox_world(w):
    """Sky ambient as Roblox OutdoorAmbient (lights the model, occluded like Roblox's
    sky visibility), while the camera sees a pale Atmosphere-coloured sky."""
    nt = w.node_tree
    out, bg = nt.nodes["World Output"], nt.nodes["Background"]
    bg.inputs["Color"].default_value = RBX["outdoor"] + (1,)
    bg.inputs["Strength"].default_value = 1.0
    sky = nt.nodes.new("ShaderNodeBackground")
    sky.inputs["Color"].default_value = RBX["sky_bg"] + (1,)
    lp = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(lp.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(bg.outputs["Background"], mix.inputs[1])
    nt.links.new(sky.outputs["Background"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])


def roblox_material(src, attr_name):
    """SmoothPlastic-ish stand-in: vertex colour (or the material's own colour) ->
    Principled (roughness 0.55, low specular, no subsurface/coat/metal) + flat
    emission = colour x Lighting.Ambient (Roblox's unoccluded ambient term)."""
    m = bpy.data.materials.new("_rbx_" + (src.name if src else "none"))
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    out = nt.nodes["Material Output"]
    if attr_name:
        c = nt.nodes.new("ShaderNodeVertexColor")
        c.layer_name = attr_name
        col = c.outputs["Color"]
    else:
        rgb_node = nt.nodes.new("ShaderNodeRGB")
        rgb_node.outputs[0].default_value = tuple(src.diffuse_color) if src else (0.64, 0.64, 0.64, 1)
        col = rgb_node.outputs[0]
    nt.links.new(col, b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = RBX["roughness"]
    b.inputs["Specular IOR Level"].default_value = RBX["specular"]
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Subsurface Weight"].default_value = 0.0
    b.inputs["Coat Weight"].default_value = 0.0
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(col, mul.inputs["A"])
    mul.inputs["B"].default_value = RBX["ambient"] + (1,)
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(mul.outputs["Result"], em.inputs["Color"])
    add = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(b.outputs["BSDF"], add.inputs[0])
    nt.links.new(em.outputs["Emission"], add.inputs[1])
    nt.links.new(add.outputs["Shader"], out.inputs["Surface"])
    return m


def apply_roblox_materials(objs):
    """Swap in render-only materials; returns a restore() for the FBX export."""
    saved = []
    for o in objs:
        me = o.data
        ca = me.color_attributes.active_color or (me.color_attributes[0] if len(me.color_attributes) else None)
        saved.append((me, [m for m in me.materials]))
        new = [roblox_material(m, ca.name if ca else None) for m in me.materials] or [roblox_material(None, ca.name if ca else None)]
        me.materials.clear()
        for m in new:
            me.materials.append(m)

    def restore():
        for me, mats in saved:
            me.materials.clear()
            for m in mats:
                me.materials.append(m)
    return restore


def sun(col, name, strength, angle):
    l = bpy.data.lights.new(name, "SUN")
    l.energy = strength
    l.angle = math.radians(angle)
    return add(col, name, l)


def aim(o, direction):
    """Point a light/camera along `direction` (its -Z axis)."""
    o.rotation_euler = Vector(direction).normalized().to_track_quat("-Z", "Y").to_euler()


def fit_distance(d, lo, hi, fov):
    """Camera distance along d so the whole bbox fits (exact)."""
    d = Vector(d).normalized()
    c = (lo + hi) / 2
    rinv = (-d).to_track_quat("-Z", "Y").to_matrix().inverted()
    t = math.tan(fov / 2) * 0.92
    need = 0.0
    for x in (lo.x, hi.x):
        for y in (lo.y, hi.y):
            for z in (lo.z, hi.z):
                p = rinv @ (Vector((x, y, z)) - c)  # camera space, looking down -Z
                need = max(need, p.z + abs(p.x) / t, p.z + abs(p.y) / t)
    return need


def frame(cam, d, lo, hi, fov, need=None):
    """Place perspective camera looking along -d; `need` fixes the distance (turntable)."""
    d = Vector(d).normalized()
    c = (lo + hi) / 2
    q = (-d).to_track_quat("-Z", "Y")
    if need is None:
        need = fit_distance(d, lo, hi, fov)
    cam.location = c + d * need
    cam.rotation_euler = q.to_euler()
    cam.data.clip_end = need * 4 + 100
    cam.data.clip_start = max(0.01, need * 0.01)


def main():
    a = args()
    T = {}
    t0 = time.time()
    objs = load_model(os.path.abspath(a.model))
    T["model_s"] = time.time() - t0

    t = time.time()
    per, lo, hi, mats = mesh_stats(objs)
    sz = hi - lo if objs else Vector((0, 0, 0))
    size = [round(sz.x, 3), round(sz.z, 3), round(sz.y, 3)]  # Roblox X, Y(up), Z
    total, fails, warns = judge(per, size)
    T["stats_s"] = time.time() - t

    tiles_dir = os.path.join(a.out, ".tiles")
    os.makedirs(tiles_dir, exist_ok=True)
    tiles, turn = [], []
    stem = a.name + (f"_{a.tag}" if a.tag else "")
    restore = None
    t = time.time()
    if objs:
        col = kit_collection()
        flo, fhi = build_rig(col, lo, hi, not a.no_ref, a.ground)
        setup_render(a)
        cam = add(col, "_cam", bpy.data.cameras.new("_cam"))
        cam.data.lens = 50
        bpy.context.scene.camera = cam
        if a.look == "roblox" and not a.quick:
            restore = apply_roblox_materials(objs)
            s = sun(col, "_sun", RBX["sun_strength"], RBX["sun_angle"])
            s.data.color = RBX["sun_color"]
            aim(s, -Vector(RBX["sun_dir"]))  # fixed in the world, like the game's sun
            key = None
        else:
            key, fill, rim = sun(col, "_key", 3.2, 12), sun(col, "_fill", 1.0, 30), sun(col, "_rim", 2.2, 8)
        T["setup_s"] = time.time() - t
        T["render_s"] = []

        def shoot(d, path, need=None):
            frame(cam, d, flo, fhi, cam.data.angle, need)
            if key:  # camera-relative 3-point light: key upper-left-front, fill right, rim from behind
                dv = Vector(d).normalized()
                side = dv.cross(Vector((0, 0, 1))).normalized()
                aim(key, -(dv + side * 0.9 + Vector((0, 0, 1.2))))
                aim(fill, -(dv - side * 1.2 + Vector((0, 0, 0.2))))
                aim(rim, -(-dv * 1.0 + Vector((0, 0, 0.8))))
            bpy.context.scene.render.filepath = path
            tr = time.time()
            bpy.ops.render.render(write_still=True)
            return round(time.time() - tr, 3)

        for i in [int(v) for v in a.views.split(",") if v != ""]:
            label, d = VIEWS[i]
            path = os.path.join(tiles_dir, f"{stem}_{i}.png")
            T["render_s"].append(shoot(d, path))
            tiles.append({"view": label, "path": path})
        if a.turntable:
            # orbit at a fixed distance and height so the GIF doesn't jump; k=0 is the front
            dirs = [(math.sin(k * math.tau / a.turntable), -math.cos(k * math.tau / a.turntable), 0.35)
                    for k in range(a.turntable)]
            need = max(fit_distance(d, flo, fhi, cam.data.angle) for d in dirs)
            T["turntable_s"] = []
            for k, d in enumerate(dirs):
                path = os.path.join(tiles_dir, f"{stem}_tt{k}.png")
                T["turntable_s"].append(shoot(d, path, need))
                turn.append({"view": f"{round(k * 360 / a.turntable)}deg", "path": path})
    if restore:
        restore()

    fbx = None
    t = time.time()
    if objs and not fails and not a.no_export and not a.quick:
        os.makedirs(a.out, exist_ok=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        # A skinned mesh (models/_slime.py rig_squash) exports with its parent Armature -> Bones in Roblox.
        rigs = [o.parent for o in objs if o.parent and o.parent.type == "ARMATURE"]
        for r in rigs:
            r.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        fbx = os.path.join(a.out, a.name + ".fbx")
        bpy.ops.export_scene.fbx(  # same settings as v17 make_meshes.py (proven in Roblox)
            filepath=fbx, use_selection=True, object_types={"MESH", "ARMATURE"} if rigs else {"MESH"},
            use_mesh_modifiers=True,
            apply_scale_options="FBX_SCALE_UNITS", axis_forward="-Z", axis_up="Y",
            mesh_smooth_type="OFF" if objs[0].get("smooth_normals") else "FACE", colors_type="SRGB", add_leaf_bones=False, bake_anim=False,
        )
        bpy.ops.wm.obj_export(filepath=os.path.join(a.out, a.name + ".obj"), export_selected_objects=True,
                              forward_axis="NEGATIVE_Z", up_axis="Y", export_colors=True, apply_modifiers=True)
        if os.path.getsize(fbx) >= FBX_FAIL:
            fails.append(f"fbx {os.path.getsize(fbx)} B >= 20 MB")
            os.remove(fbx)
            fbx = None
    T["export_s"] = time.time() - t
    T = {k: (round(v, 3) if isinstance(v, float) else v) for k, v in T.items()}

    stats = {
        "name": a.name,
        "model": os.path.abspath(a.model),
        "units": "1 Blender unit = 1 stud; size_studs is Roblox [X, Y(up), Z]",
        "tris": total,
        "meshes": per,
        "mesh_count": len(per),
        "size_studs": size,
        "non_manifold_edges": sum(m["non_manifold_edges"] for m in per),
        "materials": mats,
        "budget": {"tri_target": TRI_TARGET, "tri_fail_per_mesh": TRI_FAIL, "axis_fail_studs": AXIS_FAIL, "fbx_fail_bytes": FBX_FAIL},
        "pass": not fails,
        "fails": fails,
        "warnings": warns,
        "fbx": fbx,
        "fbx_bytes": os.path.getsize(fbx) if fbx else None,
        "engine": "workbench" if a.quick else a.engine,
        "mode": "quick" if a.quick else "full",
        "look": "clay" if a.quick else a.look,
        "res": a.res,
        "samples": a.samples,
        "tiles": tiles,
        "turntable": turn,
        "timings_blender": T,
    }
    with open(os.path.join(a.out, stem + ".stats.json"), "w") as f:
        json.dump(stats, f, indent=2)


try:
    main()
except SystemExit:
    raise
except Exception:
    import traceback
    traceback.print_exc()
    sys.exit(1)
