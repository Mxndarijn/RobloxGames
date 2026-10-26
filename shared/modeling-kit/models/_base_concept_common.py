# Shared helpers for the base concept previews (models/_base_<name>_scene.py). Not assets: design sketches only.
# Same frame as the goo jar tower: 1 BU = 1 stud, Z up, entrance at -Y (plot-local -Z), plot floor radius 40,
# floors 16 studs apart (floor f walks at 1 + 16 (f - 1)), pads 6.4 studs, door/vat/lock on floor 1's front.
# Angles: a point at angle a (degrees) and radius r is (r cos a, r sin a), so -90 is the door side.
#
# Env: FLOORS=1..4 (how many floors stand), CUT=1 (cut-away: the outer shell loses its front half; floors, pads,
# ramps, door, vat and lock stay whole so the inside reads).
#   python iterate.py models/_base_<name>_scene.py --no-export --no-ref --res 512 --views 4,2
#   CUT=1 python iterate.py models/_base_<name>_scene.py --name _base_<name>_cut --no-export --no-ref --res 512 --views 0,3
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

from lib import PALETTE, apply_transforms, blob, box, cylinder, gradient, join, mix, obj_from_bm, rgb, shade, tube, vcol_material

P = PALETTE
FLOORS = int(os.environ.get("FLOORS", "4"))
CUT = os.environ.get("CUT", "0") == "1"
FLOOR_H = 16.0
PLOT_R = 40.0
PAD = 6.4

WOOD, WOOD_D, CREAM = P["ranch_wood"], P["ranch_wood_dark"], P["ranch_cream"]
GOO, GOO_HI, METAL = P["ranch_goo"], P["ranch_goo_hi"], P["ranch_metal"]
PINK, LILAC, BUTTER, ROOF = P["ranch_pink"], P["ranch_lilac"], P["ranch_butter"], P["ranch_roof"]
FIELD, PATH = P["ranch_field"], P["ranch_path"]
RED = rgb(240, 70, 60)
SLIME_COLS = [PINK, LILAC, BUTTER, GOO, rgb(120, 190, 250), rgb(250, 160, 90)]
R = random.Random(7)

shell, contents, glass = [], [], []


def top(f):
    """Walking height of floor f."""
    return 1.0 + (f - 1) * FLOOR_H


def polar(r, a):
    a = math.radians(a)
    return r * math.cos(a), r * math.sin(a)


def add(o, lo=None, hi=None, into=None):
    """Add a part. into: 'shell' (cut in the cut-away), 'glass' (see-through) or None (contents, never cut)."""
    if lo is not None:
        gradient(o, lo, hi)
    {"shell": shell, "glass": glass, None: contents}[into].append(o)
    return o


def S(o, lo=None, hi=None):
    return add(o, lo, hi, "shell")


def part(name, size, pos, col, rot=(0, 0, 0), into=None, k=0.82):
    return add(box(name, size, pos, col, rot=rot), shade(col, k), col, into)


def disc(name, r, h, pos, col, segs=32, r_top=None, into=None, k=0.85):
    return add(cylinder(name, r, h, pos, col, segs=segs, r_top=r_top), shade(col, k), col, into)


def ring_wall(name, r_in, r_out, z0, h, col, segs=32, gap=None, into="shell", k=0.85, a0=0.0):
    """A round wall (annulus extruded). gap = (angle_from, angle_to) left open (a doorway)."""
    bm = bmesh.new()
    n = segs
    for i in range(n):
        a1 = a0 + i * 360 / n
        a2 = a0 + (i + 1) * 360 / n
        mid = (a1 + a2) / 2
        if gap and _in_arc(mid, gap):
            continue
        q = []
        for r in (r_in, r_out):
            for a in (a1, a2):
                x, y = polar(r, a)
                q.append((x, y))
        (ix1, iy1), (ix2, iy2), (ox1, oy1), (ox2, oy2) = q
        vs = [bm.verts.new(p) for p in (
            (ix1, iy1, z0), (ix2, iy2, z0), (ox2, oy2, z0), (ox1, oy1, z0),
            (ix1, iy1, z0 + h), (ix2, iy2, z0 + h), (ox2, oy2, z0 + h), (ox1, oy1, z0 + h))]
        for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            bm.faces.new([vs[j] for j in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, col)
    return add(o, shade(col, k), col, into)


def _in_arc(a, arc):
    a0, a1 = arc
    d = (a - a0) % 360
    return d <= (a1 - a0) % 360


def helix_ramp(name, r_in, r_out, z0, rise, a0, sweep, col, segs=24, thick=0.8, into=None):
    """A smooth spiral ramp: walking surface from z0 at angle a0 up `rise` over `sweep` degrees."""
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        t = i / segs
        a = a0 + sweep * t
        z = z0 + rise * t
        row = []
        for r in (r_in, r_out):
            x, y = polar(r, a)
            row.append(bm.verts.new((x, y, z)))
            row.append(bm.verts.new((x, y, z - thick)))
        rows.append(row)  # in_top, in_bot, out_top, out_bot
    for i in range(segs):
        a, b = rows[i], rows[i + 1]
        bm.faces.new((a[0], a[2], b[2], b[0]))  # top
        bm.faces.new((a[1], b[1], b[3], a[3]))  # bottom
        bm.faces.new((a[0], b[0], b[1], a[1]))  # inner
        bm.faces.new((a[2], a[3], b[3], b[2]))  # outer
    bm.faces.new((rows[0][0], rows[0][1], rows[0][3], rows[0][2]))
    bm.faces.new((rows[-1][0], rows[-1][2], rows[-1][3], rows[-1][1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), shade(col, 0.8), col, into)


def straight_ramp(name, p0, p1, width, col, thick=0.8, into=None):
    """A straight sloped ramp from p0=(x, y, z) to p1, `width` across."""
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    dx, dy = x1 - x0, y1 - y0
    L = math.hypot(dx, dy)
    nx, ny = -dy / L * width / 2, dx / L * width / 2
    bm = bmesh.new()
    v = [bm.verts.new(p) for p in (
        (x0 + nx, y0 + ny, z0), (x0 - nx, y0 - ny, z0), (x1 - nx, y1 - ny, z1), (x1 + nx, y1 + ny, z1),
        (x0 + nx, y0 + ny, z0 - thick), (x0 - nx, y0 - ny, z0 - thick), (x1 - nx, y1 - ny, z1 - thick),
        (x1 + nx, y1 + ny, z1 - thick))]
    for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
        bm.faces.new([v[j] for j in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), shade(col, 0.8), col, into)


def stand(name, x, y, z, trim=LILAC, slime_k=None):
    """A pad: cork pedestal + dish (seat at z + 2.4), with a slime on it unless slime_k is False."""
    cork = rgb(214, 170, 116)
    add(cylinder(name + "Foot", 3.6, 0.5, (x, y, z), shade(cork, 0.85), segs=16), shade(cork, 0.75), shade(cork, 0.85))
    add(cylinder(name + "Body", 3.0, 1.5, (x, y, z + 0.5), cork, segs=16, r_top=2.8), shade(cork, 0.8), cork)
    add(cylinder(name + "Dish", 2.8, 0.4, (x, y, z + 2.0), trim, segs=16, r_top=3.4), shade(trim, 0.9), trim)
    if slime_k is not False:
        k = R.randrange(6) if slime_k is None else slime_k
        slime(x, y, z + 2.4, k)


def slime(x, y, z, k, r=1.7):
    col = SLIME_COLS[k % len(SLIME_COLS)]
    add(blob(f"Slime{x:.1f}_{y:.1f}_{z:.1f}", r, (x, y, z + r * 0.78), col, subdiv=2, squash=(1, 1, 0.78), jitter=0.02),
        shade(col, 0.82), col)


def pad_ring(f, r, n=8, a0=-90 + 22.5, arc=360.0, trim=LILAC, z=None):
    """n pads on a ring of radius r on floor f, spread over `arc` degrees from a0."""
    zz = top(f) if z is None else z
    step = arc / n if arc >= 360 else arc / (n - 1)
    out = []
    for k in range(n):
        x, y = polar(r, a0 + k * step)
        stand(f"Pad{f}_{k}", x, y, zz, trim)
        out.append((x, y))
    return out


def vat(x, y, z=1.0):
    """The merge vat: a fat goo cauldron on legs."""
    add(cylinder("VatBody", 3.4, 3.2, (x, y, z + 0.8), METAL, segs=20, r_top=3.8), shade(METAL, 0.75), METAL)
    add(cylinder("VatRim", 4.0, 0.5, (x, y, z + 4.0), shade(METAL, 1.1), segs=20))
    add(cylinder("VatGoo", 3.6, 0.3, (x, y, z + 4.05), GOO_HI, segs=20))
    for k in range(3):
        bx_, by_ = polar(3.0, k * 120)
        add(cylinder(f"VatLeg{k}", 0.4, 1.0, (x + bx_, y + by_, z), shade(METAL, 0.7), segs=6))


def lock_button(x, y, z=1.0):
    cork = rgb(214, 170, 116)
    add(cylinder("LockPed", 1.6, 3.0, (x, y, z), cork, segs=14), shade(cork, 0.8), cork)
    add(blob("LockBtn", 1.3, (x, y, z + 3.1), RED, subdiv=2, squash=(1, 1, 0.55), jitter=0))


def avatar(x, y, z, col=rgb(90, 140, 230)):
    """A 5-stud player stand-in for scale: legs, body, head."""
    add(box("AvLegs", (1.6, 0.9, 2.0), (x, y, z + 1.0), shade(col, 0.6)))
    add(box("AvBody", (2.0, 1.0, 2.0), (x, y, z + 3.0), col))
    add(box("AvHead", (1.1, 1.1, 1.1), (x, y, z + 4.55), rgb(250, 214, 120)))


def mascot(x, y, z, s=4.0, col=GOO, crown=True):
    """The plot mascot slime on top, crowned."""
    add(blob("Mascot", s, (x, y, z + s * 0.75), col, subdiv=3, squash=(1, 1, 0.8), jitter=0.0), shade(col, 0.75), col)
    for sx in (-1, 1):
        add(blob(f"Eye{sx}", s * 0.18, (x + sx * s * 0.35, y - s * 0.86, z + s * 0.95), rgb(30, 30, 40), subdiv=1, jitter=0))
    if crown:
        add(cylinder("Crown", s * 0.42, s * 0.35, (x, y, z + s * 1.48), BUTTER, segs=8, r_top=s * 0.5), shade(BUTTER, 0.85), BUTTER)


def plot_foot(moat=True, ground=FIELD, moat_col=GOO, bridge_len=8.0, door_r=31.0):
    """The round plot: grass disc r 40, an optional goo moat ring (34.5..38.5), a plank bridge to the door."""
    add(cylinder("PlotDisc", PLOT_R, 0.5, (0, 0, 0.2), ground, segs=64), shade(ground, 0.8), ground)
    if moat:
        ring_wall("Moat", 34.5, 38.5, 0.55, 0.5, moat_col, segs=64, into=None)
        part("Bridge", (10, bridge_len, 0.6), (0, -(door_r + bridge_len / 2), 1.0), WOOD)


def cut(objs):
    """Cut-away: drop everything in front of y = 0 (the camera side) from each object."""
    for o in objs:
        apply_transforms(o)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0.0, 0),
                               plane_no=(0, -1, 0), clear_outer=True)
        bm.to_mesh(o.data)
        bm.free()


def ship(name, turn=-20):
    """Join into a solid mesh (+ a glass mesh if any) for the preview; CUT=1 cuts the shell first."""
    if CUT:
        cut(shell + [g for g in glass])
    mat = vcol_material(name + "_vcol")
    out = []
    for nm, objs, t in ((name, shell + contents, None), (name + "_glass", glass, 0.6)):
        if not objs:
            continue
        o = join(nm, objs)
        apply_transforms(o)
        o.data.materials.clear()
        o.data.materials.append(mat)
        if "Col" in o.data.color_attributes:
            o.data.color_attributes.active_color = o.data.color_attributes["Col"]
        if t:
            o["rbx_transparency"] = t
        o.rotation_euler.z = math.radians(0 if CUT else turn)
        out.append(o)
    bpy.context.view_layer.update()
    return out
