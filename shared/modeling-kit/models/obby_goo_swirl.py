# obby_goo_swirl: the vortex inside the Obby's Goo Ring (steal-a-slime). A disc in the XZ plane (front -Y) whose
# front sinks into a shallow funnel, painted with three spiral arms (deep violet -> lavender) round a pink-white core.
# The game turns the MeshPart round its Y axis (visuals/client/ObbyFx), so the arms read as a swirling portal.
# Radius 4.6 at the yard ring's size: the rim tucks into the ring's tube (inner edge ~4.4).
import math
import bmesh, bpy
from lib import *
from mathutils import Vector

RS = 4.6  # disc radius
DEPTH = 0.9  # funnel depth at the centre (front face sinks back towards +Y)
THICK = 0.12  # rim thickness
NA, NR = 72, 16  # angular and radial rows
ARMS = 3
WIND = 1.15  # turns each arm winds from rim to core

EDGE = hexc("#2A1670")
DEEP = hexc("#4B2DB8")
ARM = hexc("#CDB8FF")
CORE = hexc("#FFE6F4")
PINK = hexc("#F08CD0")


def front_y(rho):
    """front face depth at radius fraction rho (0 centre, 1 rim): a soft funnel."""
    return -THICK / 2 + DEPTH * (1 - rho) ** 1.8


def colour(theta, rho):
    # spiral band: 0..1, 1 on an arm's centre line
    phase = ARMS * theta + WIND * math.tau * (1 - rho)
    band = 0.5 + 0.5 * math.cos(phase)
    band = band ** 3.2  # thin bright arms on a deep field
    c = mix(DEEP, ARM, band * (0.35 + 0.65 * rho ** 0.4))
    c = mix(c, EDGE, max(0.0, (rho - 0.8) / 0.2) * 0.85)  # dark rim, it meets the ring's shaded inside
    core = max(0.0, 1 - rho / 0.28)
    c = mix(c, mix(PINK, CORE, core), core ** 0.8)
    return c


bm = bmesh.new()
front = [[None] * NA for _ in range(NR + 1)]
back = [[None] * NA for _ in range(NR + 1)]
rhos = [(i / NR) ** 0.85 for i in range(NR + 1)]  # rows denser towards the rim, where the arms wind tight
for i, rho in enumerate(rhos):
    for j in range(NA):
        th = j / NA * math.tau
        x, z = RS * rho * math.cos(th), RS * rho * math.sin(th)
        if i == 0 and j > 0:
            front[i][j] = front[0][0]
            back[i][j] = back[0][0]
            continue
        front[i][j] = bm.verts.new((x, front_y(rho), z))
        back[i][j] = bm.verts.new((x, THICK / 2 + 0.25 * (1 - rho) ** 2, z))  # the back bulges a little, never meets the front
bm.verts.ensure_lookup_table()
col = bm.loops.layers.color.new("Col")


def face(vs, back_side):
    vs = [v for k, v in enumerate(vs) if v not in vs[:k]]
    if len(vs) < 3:
        return
    f = bm.faces.new(vs if back_side else list(reversed(vs)))
    f.smooth = True
    for lp in f.loops:
        co = lp.vert.co
        rho = min(1.0, math.hypot(co.x, co.z) / RS)
        th = math.atan2(co.z, co.x)
        c = colour(th if not back_side else -th, rho)
        lp[col] = (c[0], c[1], c[2], 1.0)


for i in range(NR):
    for j in range(NA):
        k = (j + 1) % NA
        face([front[i][j], front[i][k], front[i + 1][k], front[i + 1][j]], False)
        face([back[i][j], back[i + 1][j], back[i + 1][k], back[i][k]], True)
for j in range(NA):  # rim
    k = (j + 1) % NA
    face([front[NR][j], front[NR][k], back[NR][k], back[NR][j]], False)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Swirl")
bm.to_mesh(me)
bm.free()
o = bpy.data.objects.new("Swirl", me)
bpy.context.scene.collection.objects.link(o)
sm = me.attributes.new("keep_smooth", "INT", "FACE")
for k in range(len(me.polygons)):
    sm.data[k].value = 1
# stand it on z=0 for the sheet (the game places it by its centre)
o.location.z = RS
finish("obby_goo_swirl", [o])
