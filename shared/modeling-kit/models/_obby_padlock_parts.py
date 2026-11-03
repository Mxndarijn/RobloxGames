# Shared helpers for the obby padlock options (obby_padlock_a/b/c), not an asset.
# The old lock (ObbyParts addLocks, MARK.lock*/shackle*) is a 2.2 wide x 1.8 tall body that runs THROUGH the 1-stud
# gate (depth 1.7: 0.35 proud of each face), a keyhole on both faces, and on each face a thin half-ring shackle
# (outer r 0.85, inner 0.55, legs 1.3 into the body) whose arch centre sits 0.35 over the body top, 1.0 once open.
# Whole lock: 2.2 x 3.0 x 1.7 (W x H x D). Shut: body (70,60,90), shackle (215,215,230); open: both gold (255,205,60).
#
# Each option ships TWO meshes so the game can animate them: the body and the shackle (both faces' arches in one mesh).
# Both are modelled value-only (light greys) because MeshPart.Color multiplies vertex colours (verified, LESSONS
# kit/2026-10-26): the game sets body.Color = SHUT_BODY / GOLD and shackle.Color = STEEL / GOLD, the keyhole stays
# dark on both. Kit axes: X along the gate face, Y = the runner's line (through the gate), Z up; the gate's mid-plane
# is y = 0, its faces at y = +-0.5.
#
#   PADLOCK_PIECE=body    python iterate.py models/obby_padlock_a.py --name obby_padlock_a_body     -> body FBX
#   PADLOCK_PIECE=shackle python iterate.py models/obby_padlock_a.py --name obby_padlock_a_shackle  -> shackle FBX
#   python iterate.py models/obby_padlock_a.py --no-export   (default: preview, shut + open on a gate slice, tinted)
import math
import os
import bmesh
import bpy
from mathutils import Vector, Matrix, Euler
from lib import *
from lib.shapes import obj_from_bm, _place

GATE_HALF = 0.5  # the gate is 1 stud thick
PROUD = 0.35  # body face past the gate face (old MARK.lockProud)
DEPTH = 2 * (GATE_HALF + PROUD)  # 1.7
FACE_Y = GATE_HALF + PROUD / 2  # each face's shackle plane (old: inside the proud slab)
GAP = 3.0  # lock spacing on a gate (old MARK.lockGap)

# Tints the game would set as MeshPart.Color (preview only; the meshes are value-only).
SHUT_BODY = (92, 80, 138)  # old (70,60,90), lifted per LESSONS (Roblox light crushes darks)
STEEL = (215, 215, 230)  # old shut shackle
GOLD = (255, 205, 60)  # ObbyFx.LOCK_FULL
GATE = (150, 90, 220)  # the gate slab behind (preview only)
WHITE = (255, 255, 255)


def tc(v, tint=WHITE):
    """A value (0-1 grey) times a tint: what the game shows for vertex colour v under MeshPart.Color = tint."""
    return rgb(*(min(255.0, v * c) for c in tint))


def piece():
    return os.environ.get("PADLOCK_PIECE", "preview")


def place(objs, dx=0.0, dz=0.0, rot_y=0.0, pivot=(0.0, 0.0)):
    """Move pieces (rot_y degrees round the runner's line, about pivot (x, z)), then shift by dx, dz."""
    m = Matrix.Translation((dx + pivot[0], 0, dz + pivot[1])) @ Matrix.Rotation(math.radians(rot_y), 4, "Y") \
        @ Matrix.Translation((-pivot[0], 0, -pivot[1]))
    for o in objs:
        o.data.transform(m)
    return objs


def rbox(name, size, pos, lo, hi, bev=0.25, segs=2, z0=None, z1=None):
    """Rounded box with a vertical gradient (dark bottom -> light top)."""
    o = box(name, size, pos, hi)
    bevel(o, bev, segments=segs, angle=30)
    gradient(o, lo, hi, z0, z1)
    return o


def shackle_u(name, rc, bar, zc, y, leg_l, leg_r, lo, hi, segs=10, arc=10):
    """One U shackle in the plane y: a half-circle arch (centre radius rc, round bar radius `bar`) centred at
    (0, y, zc), its legs straight down leg_l / leg_r below the arch centre. Coloured lo (leg feet) -> hi (arch top)."""
    pts = [(-rc, y, zc - leg_l)]
    pts += [(-rc, y, zc - leg_l * t) for t in (0.66, 0.33)]
    for k in range(arc + 1):
        a = math.pi - k * math.pi / arc
        pts.append((rc * math.cos(a), y, zc + rc * math.sin(a)))
    pts += [(rc, y, zc - leg_r * t) for t in (0.33, 0.66)]
    pts.append((rc, y, zc - leg_r))
    o = tube(name, pts, [bar] * len(pts), segs=segs, twist_free=True)
    gradient(o, lo, hi, zc - max(leg_l, leg_r), zc + rc + bar)
    return o


def keyhole(name, y, zc, r, slot_w, slot_h, col, sink=0.1, depth=0.12, segs=14):
    """A keyhole on a face at |y| (sign = which face): a round hole over a tapering slot, as a thin dark slab that
    stands `depth - sink` proud of the face (a dark inlay reads better than a real hole at 256 px and in game)."""
    s = 1 if y > 0 else -1
    yc = y + s * (depth / 2 - sink)
    # cylinder() stands on its base along local +Z; rot -90 about X turns +Z into +Y
    hole = cylinder(name + "Hole", r, depth, (0, yc - depth / 2, zc), col, segs=segs, rot=(-90, 0, 0))
    bm = bmesh.new()
    w0, w1 = slot_w * 0.7, slot_w  # narrow at the circle, wider at the foot
    zt, zb = zc, zc - r * 0.3 - slot_h
    pts = [(-w0 / 2, zt), (w0 / 2, zt), (w1 / 2, zb), (-w1 / 2, zb)]
    front = [bm.verts.new((x, yc - depth / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, yc + depth / 2, z)) for x, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for k in range(4):
        bm.faces.new((front[k], back[k], back[(k + 1) % 4], front[(k + 1) % 4]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    slot = obj_from_bm(name + "Slot", bm, col)
    return [hole, slot]


def gate_slice(width=7.4, z0=0.0, z1=5.0):
    """A slice of the purple gate (preview only)."""
    o = box("GateSlice", (width, 2 * GATE_HALF, z1 - z0), (0, 0, (z0 + z1) / 2), tc(1.0, GATE))
    return o


def assemble(name, build, open_pose, body_z=1.2, show_gate=True):
    """build(tint_body, tint_shackle) -> (body_parts, shackle_parts), built with the body standing on z = 0 and the
    shackle shut. open_pose(shackle_parts) moves the shackle to its open pose (in place).
    PADLOCK_PIECE=body / shackle -> that one piece, value-only (white tint), finished for export.
    preview -> shut (left) and open (right) side by side, GAP apart like on a gate, tinted, on a gate slice."""
    p = piece()
    if p in ("body", "shackle"):
        body, sh = build(WHITE, WHITE)
        keep, drop = (body, sh) if p == "body" else (sh, body)
        for o in drop:
            bpy.data.objects.remove(o)
        return finish(name, keep)
    state = os.environ.get("PADLOCK_STATE", "both")  # both | shut | open (one lock alone: a close-up sheet)
    parts = []
    if state in ("both", "shut"):
        b0, s0 = build(SHUT_BODY, STEEL)
        place(b0 + s0, dx=-GAP / 2 if state == "both" else 0.0, dz=body_z)
        parts += b0 + s0
    if state in ("both", "open"):
        b1, s1 = build(GOLD, GOLD)
        open_pose(s1)
        place(b1 + s1, dx=GAP / 2 if state == "both" else 0.0, dz=body_z)
        parts += b1 + s1
    if show_gate and os.environ.get("PADLOCK_GATE", "1") != "0":
        parts.append(gate_slice(z1=body_z + 3.6))
    return finish(name, parts)

