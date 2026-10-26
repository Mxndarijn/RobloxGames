# Base concept (design sketch, not an asset): THE SEASHELL SPIRAL.
# An upright spiral seashell, pastel pink and cream with a pearly inside. Floor 1 is the shell's wide mouth room
# (8 pads round the wall, door in the flared aperture at -Y, merge vat and lock button either side inside). From the
# back of that room ONE continuous helix floor winds up round a hollow pearl column, 16 studs per turn, like a
# parking garage: each turn is a floor, and its 8 pads stand on small flat bays off the sloping lane, so you walk
# past every slime on the way up. The helix ends on a flat landing in the apex chamber; the mascot sits on the tip.
# Lock: a giant clam that snaps shut over the doorway (shown open, its halves folded back beside the door).
# Owner exit: the pearl drop, a hatch on the top landing into the hollow centre column that drops you into a goo
# pool on floor 1 (owner-only prompt, like today's drop tube; lands inside, so the locked door still holds thieves).
# Env: FLOORS, CUT (see _base_concept_common).
import math

import bmesh

from lib import blob, cylinder, mix, obj_from_bm, rgb, shade, tube
from models._base_concept_common import *

SHELL_PINK = rgb(250, 170, 186)
SHELL_CREAM = rgb(252, 232, 206)
SHELL_DEEP = rgb(222, 120, 150)
PEARL = rgb(236, 226, 246)
NACRE = rgb(250, 214, 226)
RAMP = rgb(120, 200, 236)      # the climb, bright so it reads in the cut-away
BAY = rgb(252, 222, 150)
SAND = rgb(240, 214, 160)

COL_R = 3.2                    # hollow pearl column (the owner's drop)
TURN_PAD_R = [16.0, 14.5, 13.0]  # pad ring radius on helix turn t (floors 2..4)
BAY_OUT = 3.4                  # bay/ramp edge beyond the pad ring
START = 90.0                   # the helix starts at the back of the mouth room and winds counter-clockwise
F1_PAD_R = 25.5
SEGS = 40


def helix_z(a):
    """Walking height of the helix at `a` degrees travelled from START."""
    return 1.0 + FLOOR_H * a / 360.0


def ramp_outer(a):
    t = min(max(a / 360.0, 0.0), 2.999)
    i = int(t)
    u = t - i
    r0 = TURN_PAD_R[i] + BAY_OUT
    r1 = TURN_PAD_R[min(i + 1, 2)] + BAY_OUT
    return r0 + (r1 - r0) * u


def helix(name, a0, a1, col, thick=0.9, step=7.5, flat=None):
    """Helix ramp from a0 to a1 degrees travelled, inner edge on the column, outer edge per ramp_outer.
    flat = height to hold (a level landing) instead of climbing."""
    bm = bmesh.new()
    n = max(int((a1 - a0) / step), 1)
    rows = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        z = helix_z(a) if flat is None else flat
        ang = START + a
        row = []
        for r in (COL_R, ramp_outer(a) if flat is None else ramp_outer(min(a, 1079))):
            x, y = polar(r, ang)
            row.append(bm.verts.new((x, y, z)))
            row.append(bm.verts.new((x, y, z - thick)))
        rows.append(row)
    for i in range(n):
        a, b = rows[i], rows[i + 1]
        bm.faces.new((a[0], a[2], b[2], b[0]))
        bm.faces.new((a[1], b[1], b[3], a[3]))
        bm.faces.new((a[0], b[0], b[1], a[1]))
        bm.faces.new((a[2], a[3], b[3], b[2]))
    bm.faces.new((rows[0][0], rows[0][1], rows[0][3], rows[0][2]))
    bm.faces.new((rows[-1][0], rows[-1][2], rows[-1][3], rows[-1][1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return add(obj_from_bm(name, bm, col), shade(col, 0.8), col)


BASE = [(0, 30.5), (17, 23.5), (33, 20.5), (49, 18.0), (62, 12.0)]
BULGE = 3.0


def spiral_frac(ang):
    """0..1 round the shell from the back (START): the whorls climb one floor per turn, like the helix inside."""
    return ((ang - START) % 360) / 360.0


def shell_radius(z, ang, z_top):
    """Inner radius at height z and angle ang: a tapering cone with one bulging whorl per 16 studs, the whorls (and
    the suture between them) rising round the shell in a spiral. Above z_top it closes into the apex."""
    zz = min(z, z_top)
    for (z0, r0), (z1, r1) in zip(BASE, BASE[1:]):
        if zz <= z1:
            base = r0 + (r1 - r0) * (zz - z0) / (z1 - z0)
            break
    else:
        base = BASE[-1][1]
    zp = z - 1.0 - FLOOR_H * spiral_frac(ang)
    fade = min(max((z_top - z) / 6.0, 0.0), 1.0)  # whorls fade out into the apex
    return base + BULGE * abs(math.sin(math.pi * zp / FLOOR_H)) ** 0.5 * fade


def suture_z(ang, k):
    return 1.0 + FLOOR_H * (k + spiral_frac(ang))


def shell_surface(z_top, apex_h):
    """The shell: a thick surface of revolution with spiral whorls, closing into a pointed apex. Thin growth lines and
    a deeper pink toward each suture are painted per face. The door opening is left out at -90."""
    k = int(z_top / 1.4)
    zs = [z_top * i / k for i in range(k + 1)]
    apex = [z_top + apex_h * i / 8 for i in range(1, 9)]
    r_top = BASE[-1][1] if z_top >= 60 else shell_radius(z_top, 0, 999) - 3
    bm = bmesh.new()
    layer = bm.loops.layers.color.new("Col")
    grid_o, grid_i = [], []
    rows = []
    for z in zs + apex:
        ro, ri = [], []
        for kk in range(SEGS):
            ang = kk * 360 / SEGS
            if z <= z_top:
                r = shell_radius(z, ang, z_top)
                if z_top < 60:
                    r = min(r, r_top + (shell_radius(z, ang, 999) - r_top) * 1.0)
            else:
                r = r_top * (1 - (z - z_top) / apex_h) ** 0.75 + 0.5
            x, y = polar(1.0, ang)
            ro.append(bm.verts.new((x * (r + 1.2), y * (r + 1.2), z)))
            ri.append(bm.verts.new((x * r, y * r, z)))
        grid_o.append(ro)
        grid_i.append(ri)
        rows.append(z)
    for j in range(len(rows) - 1):
        z = (rows[j] + rows[j + 1]) / 2
        for kk in range(SEGS):
            ang = (kk + 0.5) * 360 / SEGS
            if abs(((ang + 90 + 180) % 360) - 180) < 14 and z < 13.0:
                continue  # the door
            k2 = (kk + 1) % SEGS
            zp = (z - 1.0 - FLOOR_H * spiral_frac(ang)) % FLOOR_H / FLOOR_H  # 0 at a suture, 1 at the next
            # spiral bands that run with the whorl: a deep band under each suture, a pink band mid-whorl
            if zp > 0.86 or zp < 0.06:
                col_o = SHELL_DEEP
            elif 0.42 < zp < 0.6:
                col_o = SHELL_PINK
            else:
                col_o = SHELL_CREAM
            if z > z_top:
                col_o = mix(SHELL_CREAM, SHELL_PINK, (z - z_top) / apex_h)
            col_o = mix(shade(col_o, 0.86), col_o, min(z / 30.0, 1.0))
            fo = bm.faces.new((grid_o[j][kk], grid_o[j][k2], grid_o[j + 1][k2], grid_o[j + 1][kk]))
            fi = bm.faces.new((grid_i[j][kk], grid_i[j + 1][kk], grid_i[j + 1][k2], grid_i[j][k2]))
            for f, c in ((fo, col_o), (fi, NACRE)):
                for lp in f.loops:
                    lp[layer] = c
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm("Shell", bm)


def clam_half(name, s, x, y, z, r=6.0):
    """One half of the clam lock, folded open beside the door: a scalloped fan of ribs from a hinge at the bottom."""
    n = 7
    for k in range(n):
        t = math.radians(10 + k * 160 / (n - 1))
        tip = (x + r * math.cos(t), y, z + r * math.sin(t))
        col = mix(LILAC, SHELL_CREAM, 0.15 if k % 2 else 0.55)
        add(tube(f"{name}{k}", [(x, y, z), tip], [0.35, 1.25], col, segs=8), shade(col, 0.8), col)


n_turns = max(FLOORS - 1, 0)
# The shell stands as high as the floors that stand, plus the apex chamber over the top landing.
z_top = [17.0, 33.0, 49.0, 62.0][FLOORS - 1]

plot_foot(moat=True, door_r=33.0)
disc("SandFloor", 31.5, 0.4, (0, 0, 0.7), SAND, segs=48)

# Shell + suture ridge with knobs (shell, so the cut-away opens it).
S(shell_surface(z_top, 15.0))
# The suture: one continuous spiral ridge with knobs, winding up the outside from the door to the apex.
pts = []
for a in range(0, int(360 * 4) + 1, 10):
    ang = START + a
    zz = 1.0 + FLOOR_H * a / 360.0
    if zz < 9 or zz > z_top - 1:
        continue
    pts.append((*polar(shell_radius(zz, ang, z_top) + 1.5, ang), zz))
if len(pts) > 1:
    S(tube("Suture", pts, [1.1] * len(pts), SHELL_DEEP, segs=6, twist_free=True), shade(SHELL_DEEP, 0.9), SHELL_DEEP)
    # conch spikes along the ridge, pointing out and up
    for i in range(2, len(pts), 3):
        x, y, zz = pts[i]
        d = math.hypot(x, y)
        ux, uy = x / d, y / d
        S(tube(f"Spike{i}", [(x, y, zz), (x + ux * 4.0, y + uy * 4.0, zz + 2.4)], [1.4, 0.2], SHELL_CREAM, segs=6),
          shade(SHELL_CREAM, 0.85), SHELL_CREAM)

# The flared aperture lip round the door (a fat pearly rim), and the clam lock folded open beside it.
lip = []
for a in range(-100, 281, 20):
    t = math.radians(a)
    lip.append((6.2 * math.cos(t), -32.0 - 1.5 * abs(math.sin(t)), 6.6 + 6.2 * math.sin(t)))
S(tube("Lip", [p for p in lip if p[2] > 0.6], [1.6] * len([p for p in lip if p[2] > 0.6]), SHELL_PINK, segs=8),
  shade(SHELL_PINK, 0.85), mix(SHELL_PINK, SHELL_CREAM, 0.4))
# the flared lip: a wide pearly collar round the aperture
for a in range(-60, 241, 30):
    t = math.radians(a)
    S(blob(f"Flare{a}", 2.6, (8.6 * math.cos(t), -33.2, 6.6 + 8.0 * math.sin(t)), mix(SHELL_PINK, NACRE, 0.4),
           subdiv=2, squash=(1.2, 0.6, 1.2), jitter=0))
for s_ in (-1, 1):
    clam_half(f"Clam{s_}", s_, s_ * 15.0, -34.0, 1.0, r=5.5)
    disc(f"ClamHinge{s_}", 1.2, 1.2, (s_ * 15.0, -34.0, 0.8), SHELL_DEEP, segs=10)

# Floor 1 (the mouth room): 8 pads round the wall, the front by the door free for the vat and lock button.
z1 = top(1)
for k in range(8):
    a = -90 + 60 + k * 240 / 7
    x, y = polar(F1_PAD_R, a)
    stand(f"Pad1_{k}", x, y, z1, trim=SHELL_PINK)
vx, vy = polar(23.0, -60)
vat(vx, vy, z1)
lx, ly = polar(23.0, -120)
lock_button(lx, ly, z1)
avatar(0, -12.5, 1.0)
avatar(4, -40, 1.0, rgb(230, 120, 90))

# The pearl column (hollow: the owner's drop), with a goo pool at its foot on floor 1.
col_h = helix_z(360 * n_turns) + 4 if n_turns else 6
add(cylinder("Column", COL_R, col_h, (0, 0, 0.8), PEARL, segs=20), shade(PEARL, 0.8), PEARL)
for k in range(int(col_h // 6)):
    add(cylinder(f"ColBand{k}", COL_R + 0.25, 0.6, (0, 0, 3 + k * 6), NACRE, segs=20))
disc("DropPool", COL_R + 1.5, 0.5, (0, 0, 0.9), GOO, segs=20)

# The helix: one continuous ramp, 16 studs per turn, with flat pad bays on its outer side.
if n_turns:
    helix("Helix", 0, 360 * n_turns, RAMP)
    # rail on the outer edge between bays (brass, low) and the bays
    for t in range(n_turns):
        f = t + 2
        for k in range(8):
            a = t * 360 + 22.5 + k * 45
            ang = START + a
            pr = TURN_PAD_R[t]
            x, y = polar(pr, ang)
            zb = helix_z(a) + 0.35
            # flat bay plate under the pad: level, its uphill side flush with the lane
            add(cylinder(f"Bay{f}_{k}", 3.9, 0.6, (x, y, zb - 0.6), BAY, segs=16), shade(BAY, 0.85), BAY)
            stand(f"Pad{f}_{k}", x, y, zb, trim=SHELL_PINK)
        for k in range(8):
            a = t * 360 + k * 45
            ang = START + a
            x, y = polar(ramp_outer(a) - 0.3, ang)
            add(cylinder(f"RailPost{t}_{k}", 0.25, 2.6, (x, y, helix_z(a)), METAL, segs=6))
    # top landing in the apex chamber (flat, 120 degrees) + the owner's drop hatch on the column
    a_end = 360 * n_turns
    helix("Landing", a_end, a_end + 120, RAMP, flat=helix_z(a_end))
    disc("DropHatch", COL_R + 0.6, 0.4, (0, 0, helix_z(a_end) + 0.05), GOO, segs=20)

# Cap: the apex tip with the mascot, crowned on the full shell.
z_apex = z_top + 15.0
add(cylinder("TipPearl", 1.8, 1.0, (0, 0, z_apex - 0.4), PEARL, segs=12), shade(PEARL, 0.85), PEARL)
mascot(0, 0, z_apex + 0.4, s=3.4 + 0.5 * FLOORS, crown=FLOORS == 4)

ship("_base_shell_scene", turn=-25)
