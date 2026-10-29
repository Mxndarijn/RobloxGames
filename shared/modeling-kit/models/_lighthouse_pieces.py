# Lighthouse base (Exclusive): one builder per game mesh piece, plus the slot plan and the skin tints (design only,
# not uploaded). Every builder returns Blender objects at their plot position (kit = plot-local, see
# models/_round_base_layout.py). Tint pieces are painted in value-only greys: the game gives them their colour with
# MeshPart.Color (multiply), so one mesh serves every skin. A few pieces keep fixed colours (lantern, drop exit).
#
# The look (concept models/_base_x_lighthouse_scene.py): a red-and-white striped tower narrowing per floor. Each floor
# is a kerb, a wide glass band and a head band, the stripe colour alternating per floor (stripe_a red / stripe_b
# white). The top floor wears the gallery balcony (the layout's flat roof ring) with a dark railing, the glass lantern
# room with the lamp and a see-through beam, and the red cap with a ball, the mascot on top. The owner's drop exit is
# a zip line: a davit on the gallery at the hatch side (180 deg), a rope down to a bollard by the landing.
import colorsys
import math
import random

import bmesh

from lib import PALETTE, blob, box, cylinder, gradient, mix, obj_from_bm, rgb, shade, tube
from models._base_design_common import FLOOR_H, floor_top, polar
import models._lighthouse_layout as L

P = PALETTE
FLOORS_ALL = 4
KERB_H = 2.6                 # solid kerb at the foot of each floor's wall
HEAD_H = 2.4                 # solid head band under the deck above (it runs on up to the next floor's top)
MULLION_A0 = 11.25           # thin window posts every 22.5 deg, offset so none stands in front of an upper pad
MULLION_W = 0.8
SEGS = 64                    # segments per full circle for the big rings
TINT = {}                    # mesh name -> tint role (None: fixed colours)


def g(v):
    """Value-only grey (a tint piece's paint)."""
    return (v, v, v, 1.0)


def _grad(o, lo, hi):
    gradient(o, lo, hi)
    return o


# ---------------------------------------------------------------- geometry helpers
def annulus(name, r_in, r_out, z0, z1, col, a0=0.0, a1=360.0, segs=SEGS, lo=None, r_in1=None, r_out1=None):
    """A closed ring (or ring sector a0..a1, with end caps) from z0 to z1; r_in1 / r_out1 taper the top."""
    ri1 = r_in if r_in1 is None else r_in1
    ro1 = r_out if r_out1 is None else r_out1
    full = abs((a1 - a0) - 360.0) < 1e-6
    n = max(1, int(math.ceil(segs * (a1 - a0) / 360.0 - 1e-9)))
    m = n if full else n + 1
    bm = bmesh.new()
    quads = []
    for k in range(m):
        a = a0 + (a1 - a0) * k / n
        q = []
        for r, z in ((r_in, z0), (r_out, z0), (ro1, z1), (ri1, z1)):
            x, y = polar(r, a)
            q.append(bm.verts.new((x, y, z)))
        quads.append(q)
    pairs = [(quads[k], quads[(k + 1) % m]) for k in range(n)]
    for a, b in pairs:
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if not full:
        bm.faces.new(quads[0])
        bm.faces.new(list(reversed(quads[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, col)
    return _grad(o, lo or col, col)


def revolve(name, prof, col, segs=SEGS, lo=None):
    """Closed surface of revolution from an (r, z) profile whose first and last points sit on the axis (r = 0)."""
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        if r <= 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(k * math.tau / segs), r * math.sin(k * math.tau / segs), z))
                          for k in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for k in range(segs):
            j = (k + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[j], b[k]))
            elif len(b) == 1:
                bm.faces.new((a[k], a[j], b[0]))
            else:
                bm.faces.new((a[k], a[j], b[j], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, col)
    return _grad(o, lo or col, col)


def radial_box(name, r, a, z, size, col):
    """A box at radius r, angle a, centre height z; size = (radial, along the wall, up)."""
    x, y = polar(r, a)
    return box(name, size, (x, y, z), col, rot=(0, 0, a))


def door_half():
    """Half the floor-1 doorway's angle (the wall gap the layout leaves)."""
    return math.degrees(math.asin(L.DOOR_W / 2 / (L.ROOM_R[0] + L.WALL_T / 2)))


def arcs(f):
    if f == 1:
        h = door_half()
        return [(270 + h, 270 - h + 360)]
    return [(0.0, 360.0)]


def zt_of(f):
    """Top of floor f's wall (the deck above's underside, or the gallery's when f is the top floor)."""
    return floor_top(f) + L.WALL_H


def lantern_base(f):
    """The gallery crown's top: the lantern room stands here (the layout's roof profile end)."""
    return zt_of(f) + 1.2


def apex(f):
    """The cap's apex (the layout's MASCOT_Z)."""
    return lantern_base(f) + L.LANTERN_H + 8.0


# ---------------------------------------------------------------- rooms
def _mullions(f):
    out = []
    for k in range(16):
        a = MULLION_A0 + 22.5 * k
        for a0, a1 in arcs(f):
            if a0 + 2.5 < a < a1 - 2.5 or a0 + 2.5 < a + 360 < a1 - 2.5:
                out.append(a)
                break
    return out


def room(f):
    """Floor f's wall frame: kerb, head band (up to the next floor's top, so the ledge reads as the stripe), a plinth
    and a lip, thin window posts, the centre post, the hatch door at 180 deg (floors 2-4) and the doorway's lintel
    (floor 1). Tint: stripe_a (floors 1, 3) or stripe_b (floors 2, 4)."""
    name = f"lighthouse_room_{f}"
    TINT[name] = "stripe_a" if f % 2 else "stripe_b"
    z = floor_top(f)
    ri, ro = L.ROOM_R[f - 1], L.room_out(f)
    z_top = z + FLOOR_H
    out = []
    for a0, a1 in arcs(f):
        out.append(annulus(f"Kerb{f}", ri, ro, z, z + KERB_H, g(0.95), a0, a1, lo=g(0.84)))
        out.append(annulus(f"Head{f}", ri, ro, z + L.WALL_H - HEAD_H, z_top, g(0.97), a0, a1, lo=g(0.90)))
        out.append(annulus(f"Plinth{f}", ro - 0.1, ro + 0.35, z, z + 0.8, g(0.74), a0, a1))
        out.append(annulus(f"Sill{f}", ro - 0.1, ro + 0.3, z + KERB_H - 0.35, z + KERB_H, g(0.80), a0, a1))
        out.append(annulus(f"Lip{f}", ro - 0.1, ro + 0.4, z_top - 0.7, z_top, g(0.78), a0, a1))
    for a in _mullions(f):
        half = math.degrees(MULLION_W / 2 / ri)
        out.append(annulus(f"Mull{f}_{a:.0f}", ri - 0.05, ro + 0.15, z + KERB_H, z + L.WALL_H - HEAD_H, g(0.42), a - half,
                           a + half, segs=360))
    if f == 1:
        h = door_half()
        out.append(annulus("Lintel", ri, ro, z + L.DOOR_H + 0.4, z_top, g(0.97), 270 - h - 0.5, 270 + h + 0.5,
                           lo=g(0.9)))
        for s in (-1, 1):
            a = 270 + s * (h + 0.9)
            half = math.degrees(0.9 / ri)
            out.append(annulus(f"Jamb{s}", ri - 0.05, ro + 0.25, z + KERB_H, z + L.WALL_H - HEAD_H, g(0.42), a - half,
                               a + half, segs=360))
    else:
        # the hatch door outside the wall at HATCH_A (the DropHatch collider stands on the inside face)
        out.append(radial_box(f"HatchFrame{f}", ro + 0.1, L.HATCH_A, z + 3.7, (0.5, 4.6, 7.4), g(0.42)))
        out.append(radial_box(f"Hatch{f}", ro + 0.3, L.HATCH_A, z + 3.6, (0.4, 3.8, 6.8), g(0.80)))
        x, y = polar(ro + 0.5, L.HATCH_A)
        out.append(cylinder(f"Port{f}", 0.85, 0.25, (x, y, z + 5.2), g(0.38), segs=12, rot=(0, 90, L.HATCH_A)))
        for dz in (1.6, 5.6):
            out.append(radial_box(f"Hinge{f}_{dz}", ro + 0.5, L.HATCH_A + 3.6, z + dz, (0.3, 0.9, 0.5), g(0.42)))
    out.append(cylinder(f"Post{f}", L.POST_R, FLOOR_H, (0, 0, z), g(0.92), segs=16))
    return out


def room_glass(f):
    """Floor f's glass band between the kerb and the head band (a see-through glass slot in the game). Tint: glass."""
    TINT[f"lighthouse_glass_{f}"] = "glass"
    z = floor_top(f)
    ri, ro = L.ROOM_R[f - 1], L.room_out(f)
    return [annulus(f"Glass{f}", ri + 0.35, ro - 0.35, z + KERB_H, z + L.WALL_H - HEAD_H, g(1.0), a0, a1)
            for a0, a1 in arcs(f)]


def deck(f):
    """Floor f's deck ring (the ramp shaft's edge out to the floor below's wall) with radial boards, and the front
    landing where the ramp arrives. Tint: deck."""
    TINT[f"lighthouse_deck_{f}"] = "deck"
    z = floor_top(f)
    R = L.ROOM_R[f - 2] + 0.05
    out = [annulus(f"Deck{f}", L.RAMP_OUT, R, z - L.DECK_T, z, g(0.88), lo=g(0.70)),
           annulus(f"Landing{f}", L.POST_R, L.RAMP_OUT + 0.05, z - L.DECK_T, z, g(0.88),
                   L.ARCH_A - L.LANDING / 2, L.ARCH_A + L.LANDING / 2, segs=72, lo=g(0.70)),
           annulus(f"Edge{f}", L.RAMP_OUT - 0.05, L.RAMP_OUT + 0.5, z, z + 0.12, g(0.62),
                   L.ARCH_A + L.LANDING / 2, L.ARCH_A - L.LANDING / 2 + 360)]
    for k in range(32):
        a = k * 11.25 + 5.6
        out.append(radial_box(f"Board{f}_{k}", (L.RAMP_OUT + R) / 2, a, z + 0.03, (R - L.RAMP_OUT - 1.0, 0.22, 0.08),
                              g(0.70)))
    return out


def ramp():
    """One turn of the centre spiral ramp (built from floor 1; the game moves it up per floor) with a low outer curb
    and tread stripes. Tint: ramp."""
    TINT["lighthouse_ramp"] = "ramp"
    z0 = floor_top(1)
    segs = 40
    bm = bmesh.new()
    rows = []
    for i in range(segs + 1):
        t = i / segs
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        z = z0 + FLOOR_H * t
        row = []
        for r in (L.RAMP_IN, L.RAMP_OUT):
            x, y = polar(r, a)
            row.append(bm.verts.new((x, y, z)))
            row.append(bm.verts.new((x, y, z - L.RAMP_T)))
        rows.append(row)
    for i in range(segs):
        a, b = rows[i], rows[i + 1]
        bm.faces.new((a[0], a[2], b[2], b[0]))
        bm.faces.new((a[1], b[1], b[3], a[3]))
        bm.faces.new((a[0], b[0], b[1], a[1]))
        bm.faces.new((a[2], a[3], b[3], b[2]))
    bm.faces.new((rows[0][0], rows[0][1], rows[0][3], rows[0][2]))
    bm.faces.new((rows[-1][0], rows[-1][2], rows[-1][3], rows[-1][1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    out = [_grad(obj_from_bm("Ramp", bm, g(0.95)), g(0.78), g(0.95))]
    # the curb along the open edge
    pts = []
    for i in range(segs + 1):
        t = i / segs
        x, y = polar(L.RAMP_OUT - 0.3, L.RAMP_A0 + L.RAMP_SWEEP * t)
        pts.append((x, y, z0 + FLOOR_H * t + 0.25))
    out.append(tube("Curb", pts, [0.3] * len(pts), g(0.62), segs=4, twist_free=True))
    for k in range(1, 12):
        t = k / 12
        a = L.RAMP_A0 + L.RAMP_SWEEP * t
        x0, y0 = polar(L.RAMP_IN + 0.4, a)
        x1, y1 = polar(L.RAMP_OUT - 0.7, a)
        z = z0 + FLOOR_H * t + 0.03
        out.append(tube(f"Tread{k}", [(x0, y0, z), (x1, y1, z)], [0.15, 0.15], g(0.72), segs=4))
    return out


# ---------------------------------------------------------------- the top: gallery, lantern, cap
def _wedge(name, r0, r1, a, z0, z1, w, col):
    """A corbel: a triangle in the radial-vertical plane (r0..r1 at the top z1, r0 only at the bottom z0), w wide."""
    bm = bmesh.new()
    tx, ty = -math.sin(math.radians(a)), math.cos(math.radians(a))
    vs = []
    for s in (-w / 2, w / 2):
        for r, z in ((r0, z0), (r1, z1), (r0, z1)):
            x, y = polar(r, a)
            vs.append(bm.verts.new((x + tx * s, y + ty * s, z)))
    bm.faces.new((vs[0], vs[1], vs[2]))
    bm.faces.new((vs[5], vs[4], vs[3]))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((vs[i], vs[3 + i], vs[3 + j], vs[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


def gallery(f):
    """The gallery balcony on top floor f: the flat roof ring (the layout's roof profile) with a dripping lip, corbels
    on the head band (never on the glass) and a dark railing. Tint: gallery."""
    TINT[f"lighthouse_gallery_{f}"] = "gallery"
    zt = zt_of(f)
    rim = L.room_out(f)
    RO = rim + 3.0
    prof = [(0.0, zt + 1.2), (L.LANTERN_R + 1.5, zt + 1.2), (RO, zt + 0.6), (RO + 0.3, zt + 0.55), (RO + 0.3, zt - 0.3),
            (RO - 0.4, zt - 0.55), (rim, zt - 0.55), (rim, zt), (0.0, zt)]
    out = [revolve(f"Gallery{f}", prof, g(0.92), lo=g(0.62))]
    for k in range(24):
        a = k * 15 + 7.5
        out.append(_wedge(f"Corbel{f}_{k}", rim - 0.2, RO - 0.6, a, zt - 2.1, zt - 0.5, 0.8, g(0.70)))
    rr = RO - 0.4
    for k in range(36):
        x, y = polar(rr, k * 10)
        out.append(cylinder(f"Rail{f}_{k}", 0.18, 3.6, (x, y, zt + 0.5), g(0.30), segs=4))
    out.append(annulus(f"RailTop{f}", rr - 0.25, rr + 0.25, zt + 3.8, zt + 4.25, g(0.30)))
    out.append(annulus(f"RailMid{f}", rr - 0.12, rr + 0.12, zt + 2.2, zt + 2.45, g(0.30), segs=48))
    return out


DARK = rgb(62, 64, 76)
WHITE = rgb(244, 242, 236)
LAMP = rgb(255, 224, 120)
BRASS = rgb(236, 188, 84)


def lantern(f=FLOORS_ALL):
    """The lantern room's frame on top floor f's gallery (built for floor 4, moved up/down per top floor): a white
    drum, dark window posts and top ring, and the lamp (a fat yellow lens on a pedestal). Fixed colours."""
    TINT["lighthouse_lantern"] = None
    zb = lantern_base(f)
    R = L.LANTERN_R
    out = [annulus("Drum", R - 0.2, R + 0.6, zb, zb + 2.0, WHITE, lo=shade(WHITE, 0.86), segs=32),
           annulus("DrumLip", R - 0.2, R + 0.8, zb + 1.7, zb + 2.1, shade(WHITE, 0.82), segs=32),
           annulus("TopRing", R - 0.3, R + 0.6, zb + 8.3, zb + 9.0, DARK, segs=32)]
    for k in range(8):
        a = 22.5 + k * 45
        h = math.degrees(0.45 / R)
        out.append(annulus(f"LPost{k}", R - 0.3, R + 0.4, zb + 2.0, zb + 8.3, DARK, a - h, a + h, segs=360))
    out.append(cylinder("Pedestal", 1.3, 2.6, (0, 0, zb), shade(DARK, 1.3), segs=12, r_top=0.9))
    lens = [(0.0, zb + 2.5), (2.6, zb + 2.5), (3.7, zb + 3.8), (3.9, zb + 5.0), (3.7, zb + 6.2), (2.6, zb + 7.4),
            (0.0, zb + 7.6)]
    out.append(revolve("Lens", lens, LAMP, segs=16, lo=shade(LAMP, 0.92)))
    for dz in (3.8, 6.2):
        out.append(annulus(f"LensRing{dz}", 3.6, 3.85, zb + dz - 0.15, zb + dz + 0.15, BRASS, segs=16))
    return out


def lantern_glass(f=FLOORS_ALL):
    """The lantern room's glass (a glass slot). Tint: glass."""
    TINT["lighthouse_lantern_glass"] = "glass"
    zb = lantern_base(f)
    return [annulus("LGlass", L.LANTERN_R - 0.05, L.LANTERN_R + 0.2, zb + 2.0, zb + 8.3, g(1.0), segs=32)]


BEAM_A = (300.0, 120.0)


def beam(f=FLOORS_ALL):
    """Two light beams out of the lamp, over the gallery (a glass slot: see-through warm light). Tint: beam."""
    TINT["lighthouse_beam"] = "beam"
    zc = lantern_base(f) + 5.0
    out = []
    for a in BEAM_A:
        # a round cone of light from the lens out over the gallery (a 10-sided frustum along the beam's axis)
        x0, y0 = polar(2.6, a)
        x1, y1 = polar(25.0, a)
        o = cylinder(f"Beam{a:.0f}", 1.7, 22.4, (0, 0, 0), g(1.0), segs=10, r_top=3.6)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        from mathutils import Matrix, Vector
        m = (Matrix.Translation(Vector((x0, y0, zc))) @ Matrix.Rotation(math.radians(a), 4, "Z")
             @ Matrix.Rotation(math.radians(90), 4, "Y"))
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        bm.to_mesh(o.data)
        bm.free()
        out.append(o)
    return out


def cap(f=FLOORS_ALL):
    """The cap over the lantern (the layout's LanternCap facets, 12 sides) with an eave lip, a dark foot band and a
    ball on the apex where the mascot sits. Tint: cap."""
    TINT["lighthouse_cap"] = "cap"
    zc = lantern_base(f) + L.LANTERN_H
    za = apex(f)
    prof = [(0.0, zc - 0.1), (L.LANTERN_R + 0.4, zc - 0.1), (L.LANTERN_R + 2.0, zc + 0.1), (L.LANTERN_R + 2.0, zc + 0.6),
            (L.LANTERN_R + 1.3, zc + 1.0), (5.0, zc + 5.0), (1.2, za - 0.2), (0.0, za)]
    out = [revolve("Cap", prof, g(0.96), segs=24, lo=g(0.78))]
    out.append(annulus("CapBand", L.LANTERN_R + 0.9, L.LANTERN_R + 1.5, zc + 0.95, zc + 1.45, g(0.42), segs=24,
                       r_in1=L.LANTERN_R + 0.4, r_out1=L.LANTERN_R + 1.0))
    out.append(cylinder("Vent", 1.6, 0.6, (0, 0, za - 0.5), g(0.38), segs=12))
    out.append(blob("Ball", 1.5, (0, 0, za + 0.6), g(0.40), subdiv=2, jitter=0))
    return out


# ---------------------------------------------------------------- the owner's drop exit (a zip line)
ROPE = rgb(222, 190, 132)
WOOD = rgb(176, 122, 78)
RING_RED, RING_WHITE = rgb(226, 72, 64), rgb(248, 244, 236)
ANCHOR = polar(32.8, 204.0)


def _rope_line(f):
    """The rope's points: from the pulley under the davit's tip down to the bollard, with a little sag."""
    zt = zt_of(f)
    RO = L.room_out(f) + 3.0
    x0, y0 = polar(RO + 2.4, L.HATCH_A)
    p0 = (x0, y0, zt + 3.7)
    p1 = (ANCHOR[0], ANCHOR[1], 4.6)
    pts = []
    n = 10
    for i in range(n + 1):
        t = i / n
        sag = 1.6 * 4 * t * (1 - t)
        pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, p0[2] + (p1[2] - p0[2]) * t - sag))
    return pts


def drop(f):
    """Floor f's drop exit look (f = 2..4, shown while f is the top floor): an iron davit on the gallery over the
    hatch, a brass pulley, the rope down to a wooden bollard by the landing at EXIT lands, a trolley with a handle bar
    near the top and a life ring on the bollard. Fixed colours; never collides (the drop is a scripted move)."""
    TINT[f"lighthouse_drop_{f}"] = None
    zt = zt_of(f)
    RO = L.room_out(f) + 3.0
    a = L.HATCH_A

    def at(r, z):
        x, y = polar(r, a)
        return (x, y, z)

    out = [tube(f"Davit{f}", [at(RO - 0.4, zt + 0.5), at(RO - 0.4, zt + 4.2), at(RO + 0.3, zt + 5.4),
                              at(RO + 1.5, zt + 5.8), at(RO + 2.4, zt + 5.3), at(RO + 2.4, zt + 4.7)],
                [0.4, 0.4, 0.36, 0.34, 0.3, 0.3], DARK, segs=6, twist_free=True)]
    out.append(cylinder(f"DavitFoot{f}", 0.8, 0.5, at(RO - 0.4, zt + 0.4), DARK, segs=8))
    pts = _rope_line(f)
    # the pulley: a wheel whose plane holds the rope
    dx, dy = pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]
    yaw = math.degrees(math.atan2(dy, dx))
    px, py, pz = pts[0]
    out.append(cylinder(f"Pulley{f}", 0.9, 0.45, (px, py, pz + 0.7), BRASS, segs=12, rot=(90, 0, yaw)))
    out.append(tube(f"Rope{f}", pts, [0.24] * len(pts), ROPE, segs=5, twist_free=True))
    # trolley + handle bar a little way down the rope
    i = 1
    tx, ty, tz = pts[i]
    out.append(box(f"Trolley{f}", (1.4, 0.7, 0.9), (tx, ty, tz - 0.2), BRASS, rot=(0, 0, yaw)))
    out.append(tube(f"Hanger{f}", [(tx, ty, tz - 0.5), (tx, ty, tz - 3.0)], [0.12, 0.12], DARK, segs=4))
    nx, ny = -math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
    out.append(tube(f"Bar{f}", [(tx - nx * 1.3, ty - ny * 1.3, tz - 3.1), (tx + nx * 1.3, ty + ny * 1.3, tz - 3.1)],
                    [0.22, 0.22], RING_RED, segs=6))
    # bollard and life ring at the bottom
    bx, by = ANCHOR
    out.append(cylinder(f"Bollard{f}", 0.95, 4.0, (bx, by, 0.8), WOOD, segs=10, r_top=0.85))
    out.append(cylinder(f"BollardCap{f}", 1.15, 0.5, (bx, by, 4.6), DARK, segs=10))
    out.append(cylinder(f"Cleat{f}", 0.3, 2.4, (bx, by, 3.6), DARK, segs=6, rot=(0, 90, yaw + 90)))
    # life ring leaning on the bollard's outer side, facing out
    ring_a = 204.0
    cx, cy = polar(32.8 + 1.25, ring_a)
    ux, uy = math.cos(math.radians(ring_a)), math.sin(math.radians(ring_a))
    vx, vy = -uy, ux
    for q in range(4):
        seg = []
        for s in range(5):
            th = math.radians(q * 90 + s * 22.5)
            seg.append((cx + vx * 1.25 * math.cos(th) + ux * 0.25 * math.sin(th) * 0,
                        cy + vy * 1.25 * math.cos(th), 2.3 + 1.25 * math.sin(th)))
        out.append(tube(f"LifeRing{f}_{q}", seg, [0.4] * 5, RING_RED if q % 2 == 0 else RING_WHITE, segs=6,
                        twist_free=True))
    return out


# ---------------------------------------------------------------- floor-1 decor
def rocks():
    """Sea rocks round the foot (r 30.5..33.8), never in front of the door or on the bridge (230..310 deg) and clear
    of the drop landing (188..218 deg). Tint: rock."""
    TINT["lighthouse_rocks"] = "rock"
    rr = random.Random(17)
    out = []
    k = 0
    a = 0.0
    while a < 360.0:
        aa = a % 360
        if not (228 < aa < 312 or 186 < aa < 220):
            s = rr.uniform(1.7, 3.0)
            r = rr.uniform(L.room_out(1) + 1.2 + s * 0.5, 34.2 - s * 0.7)
            x, y = polar(r, aa)
            v = rr.uniform(0.78, 0.95)
            o = blob(f"Rock{k}", s, (x, y, 0.9), g(v), subdiv=2, squash=(1.15, 1.0, 0.62), jitter=0.22, seed=k,
                     rot=(0, 0, rr.uniform(0, 180)))
            out.append(_grad(o, g(v * 0.68), g(v)))
            if k % 3 == 0:
                x2, y2 = polar(r + rr.uniform(-1.0, 0.4), aa + rr.uniform(3.5, 5.5))
                out.append(blob(f"Pebble{k}", s * 0.45, (x2, y2, 1.0), g(v * 0.9), subdiv=1, squash=(1.2, 1, 0.6),
                                jitter=0.2, seed=100 + k))
            k += 1
        a += rr.uniform(11.0, 17.0)
    return out


# ---------------------------------------------------------------- tints per skin
def strong(col, sat=0.62, min_v=0.78):
    """A tint colour from a theme colour: same hue, saturation raised to `sat` (never lowered), value >= min_v."""
    h, s, v = colorsys.rgb_to_hsv(*col[:3])
    return colorsys.hsv_to_rgb(h, max(s, sat), max(v, min_v)) + (1.0,)


# the skin's stripe colour (stripe_a; the cap too): a theme key, or "P:<palette>"
STRIPE_KEY = {"classic": "P:ranch_roof", "garden": "pot", "crystal": "metal", "starlight": "wood", "candy": "goo",
              "mushroom": "goo", "fairground": "wood", "haunted": "goo", "beach": "goo", "space": "wood",
              "winter": "metal"}


def roles(tid):
    """The tint colour per role in skin `tid`."""
    from models._base_design_common import theme

    TH = theme(tid)
    k = STRIPE_KEY[tid]
    base = P[k[2:]] if k.startswith("P:") else TH[k]
    a = base if tid == "classic" else strong(base)
    return {
        "stripe_a": a,
        "stripe_b": TH["cream"],
        "cap": a,
        "gallery": shade(mix(a, rgb(90, 80, 90), 0.35), 0.82),
        "deck": TH["wood"],
        "ramp": mix(TH["cream"], TH["wood"], 0.35),
        "glass": TH["glass"],
        "beam": rgb(255, 238, 170),
        "rock": mix(rgb(176, 168, 158), TH["sand"], 0.25),
    }


# ---------------------------------------------------------------- pieces and the slot plan
PIECES = {}
for _f in range(1, 5):
    PIECES[f"lighthouse_room_{_f}"] = (lambda f: lambda: room(f))(_f)
    PIECES[f"lighthouse_glass_{_f}"] = (lambda f: lambda: room_glass(f))(_f)
    PIECES[f"lighthouse_gallery_{_f}"] = (lambda f: lambda: gallery(f))(_f)
    if _f > 1:
        PIECES[f"lighthouse_deck_{_f}"] = (lambda f: lambda: deck(f))(_f)
        PIECES[f"lighthouse_drop_{_f}"] = (lambda f: lambda: drop(f))(_f)
PIECES.update({
    "lighthouse_ramp": ramp,
    "lighthouse_lantern": lantern,
    "lighthouse_lantern_glass": lantern_glass,
    "lighthouse_beam": beam,
    "lighthouse_cap": cap,
    "lighthouse_rocks": rocks,
})
SHIP = PIECES
MASCOT_SCALE = 3.8
GLASS_MESHES = {"lighthouse_lantern_glass", "lighthouse_beam"} | {f"lighthouse_glass_{f}" for f in range(1, 5)}


def slot_plan():
    """[{floor, name, mesh, up, scale, show, role, glass}]: where each mesh goes (the game's slot plan, the design's
    assembly). up = how far the mesh moves up from where its builder put it."""
    slots = []

    def slot(floor, name, mesh, up=0.0, scale=1.0, show=None, role=None, glass=False):
        slots.append({"floor": floor, "name": name, "mesh": mesh, "up": up, "scale": scale, "show": show, "role": role,
                      "glass": glass})

    for f in range(1, 5):
        last = f == FLOORS_ALL
        top = None if last else "top"
        slot(f, "Room", f"lighthouse_room_{f}", role="stripe_a" if f % 2 else "stripe_b")
        slot(f, "Glass", f"lighthouse_glass_{f}", role="glass", glass=True)
        if f > 1:
            slot(f, "Deck", f"lighthouse_deck_{f}", role="deck")
        if not last:
            slot(f, "RampLook", "lighthouse_ramp", up=floor_top(f) - floor_top(1), show="covered", role="ramp")
        slot(f, "Gallery", f"lighthouse_gallery_{f}", show=top, role="gallery")
        dz = floor_top(f) - floor_top(FLOORS_ALL)
        slot(f, "Lantern", "lighthouse_lantern", up=dz, show=top)
        slot(f, "LanternGlass", "lighthouse_lantern_glass", up=dz, show=top, role="glass", glass=True)
        slot(f, "Beam", "lighthouse_beam", up=dz, show=top, role="beam", glass=True)
        slot(f, "Cap", "lighthouse_cap", up=dz, show=top, role="cap")
        slot(f, "MascotLook", "goo_jar_mascot", up=apex(f) + 1.5, scale=MASCOT_SCALE, show=top)
        if f > 1:
            slot(f, "DropLook", f"lighthouse_drop_{f}", show=top)
    slot(1, "FootDecor", "lighthouse_rocks", role="rock")
    return slots
