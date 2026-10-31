# habitat_theme_tech: Tech Lab theme props on the rim (Robo, Cyber Ninja, Mecha Goo). No frame ring (the frame mesh
# supplies it). Back: a console with a glowing cyan screen and an antenna; back-sides: two server towers with rows of
# blinking lights; sides: coiled cables on riveted floor plates; front-sides: small beacon boxes; low plates and
# bolts round the front keep the bbox centred and the front arc clear for the signature prop.
import math
from mathutils import Matrix
from lib import *
from models._habitat import frame_obj
from models._habitat_overlay import *

BODY_LO, BODY_HI = rgb(122, 142, 188), rgb(184, 200, 232)  # blue steel bodies (value step from the pale dish)
STEEL_LO, STEEL, STEEL_HI = rgb(150, 160, 180), rgb(184, 194, 212), rgb(228, 234, 244)
DARK = rgb(70, 82, 118)  # screen bezel / panels: a dark field makes the lights pop
CYAN, CYAN_HI = rgb(60, 220, 255), rgb(200, 252, 255)
LIGHTS = [rgb(90, 255, 140), rgb(255, 84, 96), rgb(255, 220, 60), rgb(60, 220, 255)]
CABLE_A, CABLE_B = rgb(255, 190, 40), rgb(255, 92, 150)
parts = []


def sq(r, deg):
    """Square-layout point that round_up lands on radius r, direction deg."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    m = max(abs(c), abs(s))
    return r * c / m, r * s / m


def put(objs, r, deg, yaw=None):
    """Move parts built round the origin (local -Y = toward the slime) to (r, deg) on the rim."""
    x, y = sq(r, deg)
    m = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(deg - 90 if yaw is None else yaw), 4, "Z")
    for o in objs:
        frame_obj(o, m)
    parts.extend(objs)
    return objs


def plate(n, w, d, rivets=True):
    """Riveted floor plate (z 0..0.1) centred on the origin."""
    out = [box(f"Plate{n}", (w, d, 0.1), (0, 0, 0.05))]
    gradient(out[0], STEEL_LO, STEEL)
    if rivets:
        for i, (sx, sy) in enumerate(((-1, -1), (1, -1), (1, 1), (-1, 1))):
            out.append(cylinder(f"Rivet{n}{i}", 0.06, 0.05, (sx * (w / 2 - 0.12), sy * (d / 2 - 0.12), 0.1), STEEL_HI, segs=5))
    return out


def console():
    """Console desk + big tilted screen with a glowing cyan face (toward -Y) + antenna with a red bulb."""
    out = plate("C", 1.1, 0.5, rivets=False)
    desk = box("Desk", (1.04, 0.46, 0.7), (0, 0.0, 0.45))
    gradient(desk, BODY_LO, BODY_HI)
    out.append(desk)
    out.append(box("Keys", (0.9, 0.18, 0.08), (0, -0.12, 0.82), DARK))
    for i in range(4):
        out.append(box(f"Key{i}", (0.15, 0.13, 0.07), (-0.3 + i * 0.2, -0.12, 0.88), LIGHTS[i]))
    tilt = Matrix.Translation((0, 0.1, 0.8)) @ Matrix.Rotation(math.radians(-6), 4, "X")
    bezel = frame_obj(box("Bezel", (1.24, 0.16, 1.18), (0, 0, 0.62)), tilt)
    gradient(bezel, DARK, shade(DARK, 1.3))
    out.append(bezel)
    out.append(frame_obj(box("Screen", (1.08, 0.06, 0.98), (0, -0.09, 0.64), CYAN), tilt))
    for i, (w, x, z) in enumerate(((0.7, -0.12, 0.96), (0.48, -0.23, 0.78), (0.76, -0.08, 0.6))):  # scan lines
        out.append(frame_obj(box(f"Scan{i}", (w, 0.04, 0.09), (x, -0.13, z), CYAN_HI), tilt))
    out.append(frame_obj(box("Blip", (0.2, 0.04, 0.2), (0.3, -0.13, 0.36), CYAN_HI), tilt))
    out.append(frame_obj(box("Blip2", (0.2, 0.04, 0.2), (-0.04, -0.13, 0.36), LIGHTS[0]), tilt))
    out.append(frame_obj(cylinder("Mast", 0.05, 0.62, (0.44, 0.04, 1.2), STEEL_HI, segs=5), tilt))
    out.append(frame_obj(blob("Bulb", 0.15, (0.44, 0.04, 1.88), LIGHTS[1], subdiv=1, jitter=0), tilt))
    return out


def server(n, h):
    """Server tower with rows of blinking lights on the -Y face and a cyan stripe on top."""
    out = plate(f"S{n}", 0.95, 0.85)
    b = box(f"Server{n}", (0.74, 0.62, h), (0, 0, 0.1 + h / 2))
    gradient(b, BODY_LO, BODY_HI)
    out.append(b)
    out.append(box(f"Cap{n}", (0.82, 0.7, 0.12), (0, 0, 0.1 + h + 0.06), STEEL_HI))
    out.append(box(f"Stripe{n}", (0.84, 0.72, 0.06), (0, 0, 0.1 + h - 0.08), CYAN))
    out.append(box(f"Panel{n}", (0.6, 0.06, h - 0.4), (0, -0.32, 0.1 + h / 2 - 0.06), DARK))
    rows = int((h - 0.55) / 0.26) + 1
    for r in range(rows):
        for c in range(3):
            col = LIGHTS[(r * 2 + c + n) % 4]
            out.append(box(f"Led{n}{r}{c}", (0.13, 0.06, 0.11), (-0.18 + c * 0.18, -0.36, 0.42 + r * 0.26), col))
    return out


def coil(n, col, turns=2.4, r=0.34):
    """Coiled cable lying on a plate: a flat helix tube plus a loose end with a plug."""
    out = plate(f"K{n}", 0.88, 0.88)
    pts, rad = [], []
    steps = int(turns * 9)
    for i in range(steps + 1):
        a = i / steps * turns * math.tau
        pts.append((r * math.cos(a), r * math.sin(a), 0.22 + 0.15 * i / steps * turns))
        rad.append(0.11)
    pts += [(r + 0.04, -0.12, 0.3), (r + 0.02, -0.34, 0.18)]
    rad += [0.1, 0.1]
    out.append(tube(f"Coil{n}", pts, rad, col, segs=5, twist_free=True))
    out.append(cylinder(f"Plug{n}", 0.11, 0.2, (r + 0.02, -0.36, 0.18), STEEL_HI, segs=5, rot=(90, 0, 0)))
    return out


def beacon(n, col):
    """Small box with a glowing dome light."""
    out = [box(f"Beacon{n}", (0.6, 0.6, 0.42), (0, 0, 0.21))]
    gradient(out[0], BODY_LO, BODY_HI)
    out.append(cylinder(f"BRing{n}", 0.2, 0.07, (0, 0, 0.42), DARK, segs=6))
    out.append(blob(f"BDome{n}", 0.19, (0, 0, 0.5), col, subdiv=1, jitter=0, squash=(1, 1, 0.95)))
    return out


put(console(), 3.25, 90)
put(server(0, 1.9), 3.25, 40)
put(server(1, 1.55), 3.25, 140)
put(coil(0, CABLE_A), 3.25, -6)
put(coil(1, CABLE_B, turns=2.0), 3.25, 186)
put(beacon(0, LIGHTS[0]), 3.3, -36)
put(beacon(1, LIGHTS[3]), 3.3, 216)
for i, deg in enumerate((-78, -102)):  # low plates at the front: bbox balance, under 0.3
    put(plate(f"F{i}", 0.75, 0.6), 3.32, deg)
for i, deg in enumerate((65, 115, 14, 166)):  # bolts between the props
    put([cylinder(f"Bolt{i}", 0.15, 0.12, (0, 0, 0), STEEL_HI, segs=6),
         cylinder(f"BoltC{i}", 0.08, 0.06, (0, 0, 0.12), CYAN, segs=6)], 3.6, deg)

o = overlay_finish("habitat_theme_tech", parts)
if not PREVIEW:
    front = [v for v in o.data.vertices if v.co.z > 0.3 and v.co.y < 0 and abs(math.degrees(math.atan2(v.co.x, -v.co.y))) < 45]
    print(f"FRONT verts_over_0.3={len(front)}")
