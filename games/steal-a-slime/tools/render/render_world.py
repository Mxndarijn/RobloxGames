"""Whole-world Blender render of Steal a Slime (headless).

    lune run tools/render/export [--pending]      # writes tools/render/out/scene[_pending].json
    ~/.local/bin/blender -b --factory-startup -P tools/render/render_world.py -- \
        [--scene tools/render/out/scene.json] [--out /workspace/roblox/renders] \
        [--views 01,02,...] [--res 1920x1080] [--samples 128] [--engine cycles|eevee]

Run from games/steal-a-slime. scene.json is the world WorldBuilder builds,
with the uploaded kit meshes fitted the way server/MeshSwap fits them
(tools/render/export.luau); the meshes come from shared/modeling-kit/out/*.fbx.
Roblox (x, y up, z) maps to Blender (x, -z, y), 1 stud = 1 Blender unit.
"""
import argparse
import json
import math
import os
import sys
import time

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
KIT_OUT = os.path.join(GAME, "..", "..", "shared", "modeling-kit", "out")

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--scene", default=os.path.join(HERE, "out", "scene.json"))
ap.add_argument("--out", default="/workspace/roblox/renders")
ap.add_argument("--views", default="")
ap.add_argument("--res", default="1920x1080")
ap.add_argument("--samples", type=int, default=128)
ap.add_argument("--engine", default="cycles")
ap.add_argument("--suffix", default="")
ap.add_argument("--blend", default="")
ap.add_argument("--rename", default="")  # view=file pairs, e.g. 08=border_terrain_along: the file name (no .png, no suffix) of a view
ap.add_argument("--skin", default="")  # plot skin id of the scene (export --skin): names view 10 plot_skin_<id>.png
args = ap.parse_args(argv)

# Roblox -> Blender axes.
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
CI = C.inverted()


def rbx(x, y, z):
    return Vector((x, -z, y))


def cf_matrix(cf):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


# Scene --------------------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
data = json.load(open(args.scene))

# Materials ----------------------------------------------------------------

_mats = {}


def principled(name, color, rough=0.6, metal=0.0, emit=0.0, alpha=1.0, transmission=0.0):
    key = (name, tuple(round(c, 3) for c in color), rough, metal, emit, alpha, transmission)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = [srgb_to_linear(c) for c in color]
    b.inputs["Base Color"].default_value = (*lin, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*lin, 1)
        b.inputs["Emission Strength"].default_value = emit
    if transmission:
        b.inputs["Transmission Weight"].default_value = transmission
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
    _mats[key] = m
    return m


def noise_tinted(name, color, scale=0.15, var=0.18, rough=0.9, bump=0.3):
    """Base colour broken up by two noise octaves (grass, sand, pavement)."""
    key = ("noise", name, tuple(round(c, 3) for c in color))
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = rough
    # World position: object coords on the shared unit cube would stretch.
    tc = nt.nodes.new("ShaderNodeNewGeometry")
    n1 = nt.nodes.new("ShaderNodeTexNoise")
    n1.inputs["Scale"].default_value = scale
    n1.inputs["Detail"].default_value = 6
    n2 = nt.nodes.new("ShaderNodeTexNoise")
    n2.inputs["Scale"].default_value = scale * 18
    n2.inputs["Detail"].default_value = 4
    nt.links.new(tc.outputs["Position"], n1.inputs["Vector"])
    nt.links.new(tc.outputs["Position"], n2.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "FLOAT"
    mix.inputs["Factor"].default_value = 0.35
    nt.links.new(n1.outputs["Fac"], mix.inputs["A"])
    nt.links.new(n2.outputs["Fac"], mix.inputs["B"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    lin = [srgb_to_linear(c) for c in color]
    dark = [c * (1 - var) for c in lin]
    light = [min(1, c * (1 + var)) for c in lin]
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = (*dark, 1)
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = (*light, 1)
    nt.links.new(mix.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    bp = nt.nodes.new("ShaderNodeBump")
    bp.inputs["Strength"].default_value = bump
    nt.links.new(n2.outputs["Fac"], bp.inputs["Height"])
    nt.links.new(bp.outputs["Normal"], b.inputs["Normal"])
    _mats[key] = m
    return m


ROUGH = {"SmoothPlastic": 0.5, "Plastic": 0.6, "Wood": 0.75, "WoodPlanks": 0.75, "Slate": 0.85, "Rock": 0.9,
         "Metal": 0.35, "Pavement": 0.9, "Sand": 0.95, "Grass": 0.95, "Glass": 0.05, "Ice": 0.1}


def part_material(p):
    col, mat = p["color"], p["material"]
    if mat == "Neon":
        return principled("Neon", col, emit=3.0)
    if mat == "Grass":
        return noise_tinted("Grass", col, scale=0.012, var=0.16, bump=0.15)
    if mat in ("Sand", "Pavement"):
        return noise_tinted(mat, col, scale=0.08, var=0.06, bump=0.08)
    if mat == "Glass":
        return principled("Glass", col, rough=0.05, transmission=0.6, alpha=max(0.35, 1 - p["transparency"]))
    return principled(mat, col, rough=ROUGH.get(mat, 0.6), metal=0.6 if mat == "Metal" else 0.0,
                      alpha=1 - p["transparency"])


def vcol_material(layer, tint=None):
    """Vertex colours; `tint` (r, g, b 0..1, sRGB) multiplies them like a MeshPart.Color does."""
    tint = tuple(round(c, 3) for c in tint) if tint else None
    key = ("vcol", layer, tint)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("kit_" + layer + ("_tint" if tint else ""))
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.6
    b.inputs["Specular IOR Level"].default_value = 0.3
    a = nt.nodes.new("ShaderNodeVertexColor")
    a.layer_name = layer
    if tint:
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        mul.inputs["B"].default_value = (*[srgb_to_linear(c) for c in tint], 1)
        nt.links.new(a.outputs["Color"], mul.inputs["A"])
        nt.links.new(mul.outputs["Result"], b.inputs["Base Color"])
    else:
        nt.links.new(a.outputs["Color"], b.inputs["Base Color"])
    _mats[key] = m
    return m


# Primitive meshes (unit size, centred), shared by every part -----------------

def unit_mesh(kind):
    name = "unit_" + kind
    if name in bpy.data.meshes:
        return bpy.data.meshes[name]
    if kind == "Block":
        bpy.ops.mesh.primitive_cube_add(size=1)
    elif kind == "Cylinder":
        # Roblox cylinders run along local X (Blender X too).
        bpy.ops.mesh.primitive_cylinder_add(vertices=256, radius=0.5, depth=1, rotation=(0, math.pi / 2, 0))
        bpy.ops.object.transform_apply(rotation=True)
        # 256 flat sides read as smooth (Roblox cylinders are); smooth shading would blend the end caps
        # into the side and band every wide, low piece such as the goo lane.
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=0.5)
        bpy.ops.object.shade_smooth()
    o = bpy.context.object
    # No bevel: one unit cube is scaled to every part, so a bevel would grow
    # with the part (25 studs on the Ground); Roblox parts are sharp anyway.
    me = o.data
    me.name = name
    me.materials.append(principled("unit", (0.5, 0.5, 0.5)))
    bpy.data.objects.remove(o)
    return me


# Kit meshes: one centred datablock per name, linked into every slot ---------

_kit = {}


def kit_mesh(name):
    if name in _kit:
        return _kit[name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(KIT_OUT, name + ".fbx"))
    objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = o.data
    lo = Vector((min(v.co[i] for v in me.vertices) for i in range(3)))
    hi = Vector((max(v.co[i] for v in me.vertices) for i in range(3)))
    centre = (lo + hi) / 2
    me.transform(Matrix.Translation(-centre))
    dims = hi - lo
    native = (dims.x, dims.z, dims.y)  # Roblox X, Y, Z
    ca = me.color_attributes
    me.materials.clear()
    if len(ca):
        me.materials.append(vcol_material(ca[0].name))
    else:
        me.materials.append(principled("kit_grey", (0.7, 0.7, 0.7)))
    for p in me.polygons:
        p.use_smooth = False
    me.name = "kit_" + name
    for x in [x for x in bpy.data.objects if x not in before]:
        bpy.data.objects.remove(x)
    _kit[name] = (me, native)
    return _kit[name]


coll_world = bpy.data.collections.new("World")
scene.collection.children.link(coll_world)

t0 = time.time()
for p in data["parts"]:
    me = unit_mesh(p["shape"])
    o = bpy.data.objects.new(p["name"][-60:], me)
    sx, sy, sz = p["size"]
    if p["shape"] == "Ball":
        sx = sy = sz = min(p["size"])
    elif p["shape"] == "Cylinder":
        sy = sz = min(sy, sz)
    o.matrix_world = C @ cf_matrix(p["cf"]) @ Matrix.Diagonal((sx, sy, sz, 1)) @ CI
    # The unit mesh is shared: each part carries its own material on the object.
    o.material_slots[0].link = "OBJECT"
    o.material_slots[0].material = part_material(p)
    coll_world.objects.link(o)

missing = set()
for m in data["meshes"]:
    try:
        me, native = kit_mesh(m["mesh"])
    except Exception as e:  # noqa: BLE001
        missing.add((m["mesh"], str(e)[:80]))
        continue
    s = [m["size"][i] / native[i] for i in range(3)]
    o = bpy.data.objects.new(m["mesh"], me)
    o.matrix_world = C @ cf_matrix(m["cf"]) @ Matrix.Diagonal((s[0], s[1], s[2], 1)) @ CI
    if m.get("tint") and me.materials and len(me.color_attributes):
        # Own material slot on the object: the datablock is shared by every slot of this mesh.
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = vcol_material(me.color_attributes[0].name, m["tint"])
    coll_world.objects.link(o)


def build_terrain(t):
    """The border hills (server/BorderTerrainView): the seeded heightfield as a vertex-coloured mesh.

    Vertices sit at the grid cell centres; a face is drawn when any corner is past the Ground edge
    (flat vertices dip 5 cm so they never z-fight the Ground part, which ends at `inner`)."""
    n, step, lo, inner = t["n"], t["step"], t["min"], t["inner"]
    heights, mats = t["heights"], t["materials"]
    pal = {k: tuple(c / 255 for c in v) for k, v in t["colors"].items()}
    by_letter = {"G": pal["Grass"], "L": pal["LeafyGrass"], "R": pal["Rock"]}
    verts, cols = [], []
    for j in range(n):
        z = lo + j * step
        for i in range(n):
            x = lo + i * step
            h = heights[j * n + i]
            verts.append(rbx(x, h if h > 0 else -0.05, z))
            cols.append(by_letter[mats[j * n + i]])

    def far(i, j):
        return max(abs(lo + i * step), abs(lo + j * step)) > inner

    faces = []
    for j in range(n - 1):
        for i in range(n - 1):
            if not (far(i, j) or far(i + 1, j) or far(i, j + 1) or far(i + 1, j + 1)):
                continue
            if not any(heights[(j + dj) * n + i + di] > 0 for dj in (0, 1) for di in (0, 1)):
                continue
            a = j * n + i
            faces.append((a, a + n, a + n + 1, a + 1))
    me = bpy.data.meshes.new("border_terrain")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    for p in me.polygons:
        p.use_smooth = True
    ca = me.color_attributes.new("terrain", "FLOAT_COLOR", "POINT")
    for k, c in enumerate(cols):
        ca.data[k].color = (*(srgb_to_linear(v) for v in c), 1)
    me.materials.append(vcol_material("terrain"))
    o = bpy.data.objects.new("border_terrain", me)
    coll_world.objects.link(o)
    # Normals as Blender flips them: face winding above is +Y (Blender Z) up.
    return len(faces)


if data.get("terrain"):
    tf = build_terrain(data["terrain"])
    print(f"terrain mesh: {tf} faces")

print(f"built {len(data['parts'])} parts, {len(data['meshes'])} meshes in {time.time() - t0:.1f}s; missing {missing}")

# Light and sky ------------------------------------------------------------

SUN_ELEV, SUN_AZ = 42.0, 215.0  # afternoon sun, from the south-west of +Z
world = bpy.data.worlds.new("Sky")
scene.world = world
world.use_nodes = True
nt = world.node_tree
sky = nt.nodes.new("ShaderNodeTexSky")
sky.sky_type = "NISHITA"
sky.sun_elevation = math.radians(SUN_ELEV)
sky.sun_rotation = math.radians(SUN_AZ)
sky.sun_disc = False
sky.air_density = 1.0
sky.dust_density = 1.5
bg = nt.nodes["Background"]
bg.inputs["Strength"].default_value = 0.35
# Below the horizon Nishita goes dark brown; a Roblox skybox stays hazy blue,
# so fade to a haze colour under the horizon.
tc = nt.nodes.new("ShaderNodeTexCoord")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
ramp = nt.nodes.new("ShaderNodeMapRange")
ramp.inputs["From Min"].default_value = -0.02
ramp.inputs["From Max"].default_value = 0.03
nt.links.new(sep.outputs["Z"], ramp.inputs["Value"])
mix = nt.nodes.new("ShaderNodeMix")
mix.data_type = "RGBA"
mix.inputs["B"].default_value = (2.2, 2.6, 3.2, 1)
nt.links.new(ramp.outputs["Result"], mix.inputs["Factor"])
nt.links.new(sky.outputs["Color"], mix.inputs["B"])
mix.inputs["A"].default_value = (2.0, 2.3, 2.7, 1)
nt.links.new(mix.outputs["Result"], bg.inputs["Color"])

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 4.2
sun_data.angle = math.radians(2.5)
sun_data.color = (1.0, 0.95, 0.86)
sun = bpy.data.objects.new("Sun", sun_data)
# Blender sun points along its local -Z; aim it from (elev, az).
sun.rotation_euler = (math.radians(90 - SUN_ELEV), 0, math.radians(SUN_AZ + 90))
scene.collection.objects.link(sun)

# Render settings ------------------------------------------------------------

rx, ry = (int(v) for v in args.res.split("x"))
r = scene.render
r.resolution_x, r.resolution_y, r.resolution_percentage = rx, ry, 100
r.image_settings.file_format = "PNG"
r.film_transparent = False
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.0
if args.engine == "cycles":
    r.engine = "CYCLES"
    cy = scene.cycles
    cy.device = "CPU"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                if any(d.type == kind for d in prefs.devices):
                    for d in prefs.devices:
                        d.use = True
                    cy.device = "GPU"
                    break
            except TypeError:
                continue
    except Exception:  # noqa: BLE001
        pass
    print("cycles device", cy.device)
    cy.samples = args.samples
    cy.use_adaptive_sampling = True
    cy.adaptive_threshold = 0.02
    cy.use_denoising = True
    cy.denoiser = "OPENIMAGEDENOISE"
    cy.max_bounces = 4
    cy.diffuse_bounces = 2
    cy.glossy_bounces = 2
    cy.transmission_bounces = 4
    cy.transparent_max_bounces = 8
    cy.caustics_reflective = cy.caustics_refractive = False
    r.use_persistent_data = True
else:
    r.engine = "BLENDER_EEVEE_NEXT"
    scene.eevee.taa_render_samples = 64
    scene.eevee.use_shadows = True

# Atmosphere (default.project.json: Density 0.28, Haze 1.2): mist pass mixed
# towards the horizon haze in the compositor; off for the top-down view.
HAZE = (0.62, 0.68, 0.78, 1)
scene.view_layers[0].use_pass_mist = True
world.mist_settings.start = 40
world.mist_settings.depth = 1100
world.mist_settings.falloff = "QUADRATIC"
scene.use_nodes = True
cn = scene.node_tree
for n in list(cn.nodes):
    cn.nodes.remove(n)
rl = cn.nodes.new("CompositorNodeRLayers")
amount = cn.nodes.new("CompositorNodeMath")
amount.operation = "MULTIPLY"
amount.inputs[1].default_value = 0.6
cn.links.new(rl.outputs["Mist"], amount.inputs[0])
fog = cn.nodes.new("CompositorNodeMixRGB")
fog.inputs[2].default_value = HAZE
cn.links.new(amount.outputs[0], fog.inputs[0])
cn.links.new(rl.outputs["Image"], fog.inputs[1])
comp = cn.nodes.new("CompositorNodeComposite")
cn.links.new(fog.outputs[0], comp.inputs["Image"])

# Cameras (Roblox coords) ------------------------------------------------------

cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam_data.clip_start = 0.5
cam_data.clip_end = 5000


def look(eye, target, lens=35, ortho=None):
    e, t = rbx(*eye), rbx(*target)
    cam.location = e
    cam.rotation_euler = (t - e).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    else:
        cam_data.type = "PERSP"
        cam_data.lens = lens


plots = data["plots"]
P1 = plots[0]["centre"]  # plot 1 sits on +Z, gate facing the fountain (-Z)
W = data["wallRadius"]
a3 = math.radians(plots[2]["yaw"])


def polar(deg, r, y):
    a = math.radians(deg)
    return (-math.sin(a) * r, y, -math.cos(a) * r)


VIEWS = {
    # straight down, the whole bordered disc
    "01_overview_top": lambda: look((0, 900, 0.01), (0, 0, 0), ortho=2 * W * 1.08),
    # low across the landing ring at the fountain
    "02_plaza_fountain_hero": lambda: look((-38, 9, -58), (0, 17, 0), lens=24),
    # outside plot 1's gate, three-quarter, looking in
    "03_plot_closeup": lambda: look((P1[0] + 46, 34, P1[2] - 78), (P1[0], 2, P1[2] - 4), lens=28),
    # near the edge between two plots, looking out along the border
    "04_world_border": lambda: look(polar(-22.5 + 180, W - 70, 26), polar(-22.5 + 180 + 28, W + 6, 4), lens=26),
    # player eye: across the plaza toward plot 1's gate
    "05_player_eye": lambda: look((-50, 5, 45), (P1[0], 8, P1[2] - 40), lens=26),
    # v29 B5, player eye height (5 studs) on plot 1's spoke path: the ring path
    # crosses ahead, both flush with the ground
    "06_path_eye": lambda: look((2, 5, 58), (-6, 1, 100), lens=30),
    # world border v3: the ring from high up across the plaza, mid height along
    # the edge, and a player's eye (5 studs) looking out at it
    "13_border_terrain_aerial": lambda: look(polar(337.5, 140, 1180), polar(157.5, 20, 0), lens=19),
    "07_border_aerial": lambda: look(polar(337.5, 40, 430), polar(157.5, 170, 0), lens=22),
    "08_border_along": lambda: look(polar(140, 240, 20), polar(178, 300, 6), lens=30),
    "09_border_eye": lambda: look(polar(157.5, 246, 5), polar(172, 300, 7), lens=30),
    # v30 C5: close-up of plot 1's back fence outside the left corner: two panel
    # joints (posts, planks, rail) and the corner where two sides meet
    "10_fence_closeup": lambda: look((P1[0] - 22, 6.5, P1[2] + 62), (P1[0] - 30, 3.5, P1[2] + 39.5), lens=34),
    # v30 C5: gate side of plot 1, from outside: panel, segment and gate post joints
    "11_fence_gate_side": lambda: look((P1[0] + 38, 6.5, P1[2] - 66), (P1[0] + 25, 3.5, P1[2] - 40.5), lens=34),
    # plot skin close-up (plot 1 wears the scene's skin, export --skin): the entrance side, the
    # skin decor beside the gate, the floor through the open front
    "12_plot_skin": lambda: look((P1[0] + 31, 17, P1[2] - 72), (P1[0] + 4, 3, P1[2] - 38), lens=30),
    # v19 fountain tiers (export --fountain-tier N): the whole fountain from the plaza, ring at its
    # foot and the crest over the goo crown; and a low close-up of the ring posts
    "14_fountain_tier": lambda: look((-70, 22, -92), (0, 22, 0), lens=26),
    "15_fountain_tier_ring": lambda: look((-30, 6, -46), (-4, 4, -6), lens=28),
    # v19 merge vat (export default; --cylinder = old primitive): Plot_1's vat from inside the plot, and from above the gate looking down into the plot
    "16_merge_vat": lambda: look((data["vat"][0] + 15, 9, data["vat"][2] - 15), (data["vat"][0], 4, data["vat"][2]), lens=32) if data.get("vat") else None,
    "17_merge_vat_plot": lambda: look((data["vat"][0] + 14, 40, data["vat"][2] - 44), (data["vat"][0] - 6, 2, data["vat"][2] + 6), lens=30) if data.get("vat") else None,
    # v19 Rain Magnet (export --magnet): the magnet beside Plot_1's vat from inside the plot, and from above the gate
    "18_rain_magnet": lambda: look((data["magnet"][0] - 6, 8, data["magnet"][2] - 24), (data["magnet"][0] + 3, 4.5, data["magnet"][2]), lens=30) if data.get("magnet") else None,
    "19_rain_magnet_plot": lambda: look((data["magnet"][0] + 24, 40, data["magnet"][2] - 44), (data["magnet"][0] + 4, 2, data["magnet"][2] + 6), lens=30) if data.get("magnet") else None,
    # slime path (lane + slide exit): overview, low (eye 4) at the slide exit, along the lane, at the landing ring
    "20_slimepath_overview": lambda: look((0, 190, 150), (0, 0, 42), lens=32),
    "21_slimepath_exit": lambda: look((-10, 4, 54), (0, 1.5, 36), lens=28),
    "22_slimepath_along": lambda: slimepath_along(),
    # co-op ritual circle (bug #7): the plaza from high up (old and new site in frame), and a player's eye
    # (5 studs) 24 studs from the circle on the fountain side, looking at it
    "24_ritual_aerial": lambda: look((-150, 150, 36), (-30, 0, 36), lens=24),
    "25_ritual_eye": lambda: ritual_eye(),
    "23_slimepath_ring": lambda: look((46, 4, 56), (24, 2, 28), lens=28),
    # SnowGround v2 (export --snow <level> --snow-phase settle|melt): eye height at the plaza edge looking down spoke 1 over the
    # plaza sand, the spoke and ring paths, plot 1 and the hills behind
    "20_snow_ground": lambda: look((0, 11, 38), (0, 3, 130), lens=22),
    # bug 4 lane close-ups (eye 1.6): a straight stretch, the bend out to r 68, the slide exit
    "27_lane_straight": lambda: look((17.6, 1.6, -55.5), (28.6, 0.3, -48.2), lens=28),
    "28_lane_bend": lambda: look((-68.5, 1.6, 19), (-62, 0.3, 4.5), lens=28),
    "29_lane_exit": lambda: look((-4, 1.6, 33), (-18, 0.3, 39.5), lens=28),
}


def ritual_eye():
    rx, rz, _ = data["ritual"]
    d = math.hypot(rx, rz) or 1
    look((rx - rx / d * 24, 5, rz - rz / d * 24), (rx, 2, rz), lens=30)


def slimepath_along():
    lane = data["lane"]
    a, b = data.get("laneStart") or lane[0], lane[min(6, len(lane) - 1)]
    d = math.hypot(b[0] - a[0], b[1] - a[1]) or 1
    ux, uz = (b[0] - a[0]) / d, (b[1] - a[1]) / d
    look((a[0] - ux * 3, 4, a[1] - uz * 3), (a[0] + ux * 30, 1.5, a[1] + uz * 30), lens=30)


os.makedirs(args.out, exist_ok=True)
want = [v for v in args.views.split(",") if v]
for name, setup in VIEWS.items():
    if want and not any(name.startswith(w) for w in want):
        continue
    setup()
    # ortho_scale spans the frame height for the top view
    top = name.startswith("01")
    cam_data.sensor_fit = "VERTICAL" if top else "AUTO"
    amount.inputs[1].default_value = 0.0 if (top or name.startswith("13")) else 0.6
    renames = dict(kv.split("=") for kv in args.rename.split(",") if kv)
    base = renames.get(name[:2], name)
    r.filepath = os.path.join(args.out, base + args.suffix + ".png")
    if name.startswith("12"):
        r.filepath = os.path.join(args.out, f"plot_skin_{args.skin or 'classic'}{args.suffix}.png")
    t = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"rendered {r.filepath} in {time.time() - t:.1f}s", flush=True)

if args.blend:
    bpy.ops.wm.save_as_mainfile(filepath=args.blend)
