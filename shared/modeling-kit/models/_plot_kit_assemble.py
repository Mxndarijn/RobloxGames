# Preview (not an asset): the plot fence/gate kit assembled on one 56 x 56 plot, for
# sheets/plot-kit/assembled_plot_meadow_robloxlook.png. Loads the shipped FBXs from out/.
#   python3 iterate.py models/_plot_kit_assemble.py --look roblox --ground 98,160,70 --no-export \
#       --no-ref --views 4,0,3,2 --res 512 --sheet sheets/plot-kit/assembled_plot_meadow_robloxlook.png
# Drawn in kit space: entrance (Roblox local -Z) toward the front camera (-Y), pickets face outward.
# Plot base top at z = 1 (WorldLayout Base 56 x 1 x 56); pads at padOffset (x -18..18, 4 and 17 from
# the centre towards the back); cottage behind the back fence. Plot accent = PLOT_COLORS[3] (gold).
import math, os
import bpy
from lib import box, rgb, mix, vcol_material

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S, SEG, BASE_TOP = 56, 7.0, 1.0
H = S / 2
ACCENT = rgb(240, 186, 82)
_cache = {}


def place(name, x, y, z=BASE_TOP, yaw=0.0):
    """Instance a shipped FBX (linked mesh data) at (x, y, z) turned yaw degrees about Z."""
    if name not in _cache:
        bpy.ops.import_scene.fbx(filepath=os.path.join(KIT, "out", name + ".fbx"))
        o = bpy.context.selected_objects[0]
        ca = o.data.color_attributes
        mat = vcol_material("asm_" + name)
        mat.node_tree.nodes["Color Attribute"].layer_name = ca[0].name
        o.data.materials.clear()
        o.data.materials.append(mat)
        bpy.context.view_layer.update()
        _cache[name] = o
        o.location = (x, y, z)
        o.rotation_euler = (o.rotation_euler.x, o.rotation_euler.y, math.radians(yaw))
        return o
    src = _cache[name]
    o = src.copy()
    bpy.context.scene.collection.objects.link(o)
    o.location = (x, y, z)
    o.rotation_euler = (src.rotation_euler.x, src.rotation_euler.y, math.radians(yaw))
    return o


# plot base + pads (plain parts, as WorldLayout builds them)
box("Base", (S, S, 1.0), (0, 0, 0.5), mix(ACCENT, rgb(150, 140, 128), 0.55))
for j in range(8):
    col, row = j % 4, j // 4
    px, py = (col - 1.5) * 12, 4 + row * 13
    place("pad_trim", px, py)
    box(f"Pad{j}", (8, 8, 0.6), (px, py, BASE_TOP + 1.8 + 0.3), ACCENT)

# fence: segments centred between joints; outward = local -Y
mids = [-H + SEG * (i + 0.5) for i in range(8)]
for m in mids:
    place("fence_straight", m, H, yaw=180)    # back
    place("fence_straight", -H, m, yaw=-90)   # left
    place("fence_straight", H, m, yaw=90)     # right
for m in mids[:3] + mids[5:]:
    place("fence_straight", m, -H)            # front wings (3 + 3)
place("gate_frame", 0, -H)                    # covers the middle two segments (14 studs)
for cx in (-H, H):
    for cy in (-H, H):
        place("fence_corner", cx, cy)
# gate_bar swung open into the plot about a hinge at the left jamb (x = -3.8)
place("gate_bar", -3.8, -H + 3.8, yaw=90)
# sign_board on the meadow, right of the path, facing the arrivals
place("sign_board", 11.5, -H - 4.0, z=0.0)
# cottage behind the back fence, door towards the plot
place("plot_building", 0, H + 10.5, z=0.0)
