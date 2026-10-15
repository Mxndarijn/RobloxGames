"""Colours and materials. Roblox shows FBX vertex colours on a MeshPart, so the kit
paints one colour attribute "Col" per part (corner domain, linear floats) and gives
the mesh a single material that displays it (the material itself is ignored by Roblox)."""
import bpy


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(r, g, b):
    """0-255 sRGB, as you would pick it in Studio -> RGBA tuple stored in "Col".
    The FBX exporter is called with colors_type="SRGB", so values stay as picked."""
    return (r / 255, g / 255, b / 255, 1.0)


def hexc(h):
    h = h.lstrip("#")
    return rgb(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def shade(col, k):
    """Multiply brightness (k<1 darker, k>1 lighter), clamped."""
    return tuple(min(1.0, c * k) for c in col[:3]) + (1.0,)


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3)) + (1.0,)


# Bright, saturated "slime game" palette (matches the v17 world, pushed a bit brighter).
PALETTE = {
    "bark": rgb(120, 78, 50),
    "bark_dark": rgb(86, 56, 38),
    "leaf": rgb(86, 170, 64),
    "leaf_light": rgb(138, 206, 80),
    "leaf_dark": rgb(56, 124, 54),
    "pine": rgb(46, 112, 74),
    "rock": rgb(140, 128, 116),
    "slate": rgb(104, 100, 98),
    "blossom": rgb(246, 160, 190),
    "slime": rgb(90, 220, 120),
    "lava": rgb(255, 140, 50),
    "wood": rgb(150, 100, 60),
    # Volcanic Meadow theme
    "meadow": rgb(98, 160, 70),
    "path_sand": rgb(214, 186, 138),
    "basalt": rgb(58, 52, 56),
    "basalt_hi": rgb(84, 76, 80),
    "lava_crack": rgb(255, 96, 24),
    "stone_warm": rgb(150, 138, 120),
    # Slime Ranch theme (THEME.md)
    "ranch_field": rgb(120, 196, 108),
    "ranch_field_light": rgb(156, 216, 124),
    "ranch_field_dark": rgb(88, 160, 92),
    "ranch_path": rgb(226, 196, 146),
    "ranch_plaza": rgb(214, 176, 124),  # warmer sand/wood for big floors (cream banned on big surfaces)
    "ranch_cream": rgb(248, 236, 212),
    "ranch_wood": rgb(196, 138, 86),
    "ranch_wood_dark": rgb(158, 108, 68),
    "ranch_roof": rgb(214, 92, 84),
    "ranch_roof_dark": rgb(176, 70, 70),
    "ranch_goo": rgb(110, 226, 170),
    "ranch_goo_hi": rgb(196, 250, 220),
    "ranch_pink": rgb(250, 150, 182),
    "ranch_lilac": rgb(196, 166, 232),
    "ranch_butter": rgb(252, 216, 110),
    "ranch_metal": rgb(168, 148, 110),
}


def paint_bm(bm, color):
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    for f in bm.faces:
        for loop in f.loops:
            loop[layer] = color


def gradient_bm(bm, bottom, top, z0=None, z1=None, faces=None):
    """Vertical colour gradient per face (flat look, cheap fake AO under canopies)."""
    layer = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
    faces = list(faces if faces is not None else bm.faces)
    zs = [v.co.z for f in faces for v in f.verts]
    z0 = min(zs) if z0 is None else z0
    z1 = max(zs) if z1 is None else z1
    span = max(z1 - z0, 1e-6)
    for f in faces:
        t = min(1.0, max(0.0, (f.calc_center_median().z - z0) / span))
        c = mix(bottom, top, t)
        for loop in f.loops:
            loop[layer] = c


def vcol_material(name="vcol"):
    """Material that renders the "Col" attribute (what Roblox will show)."""
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.8
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def flat_material(name, color, roughness=0.8):
    """Plain coloured material, for previews only. Roblox does NOT reliably carry FBX
    material colours; prefer vertex colours (paint_bm) for anything you will ship."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = color
    return mat
