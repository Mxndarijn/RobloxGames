# habitat_theme_spooky: Spooky theme props on the rim (Boo, Pumpking, Nightwing), cute rather than scary. No frame
# ring (the frame mesh supplies it). Back: a bare twisty tree with curly branch tips; back-sides and sides: chubby
# rounded gravestones (one leaning) on little soil mounds; left: a tiny lit candle; soft purple fog puffs low all
# round the rim (the ones at the front stay under 0.3 and keep the bbox centred).
import math
from mathutils import Matrix
from lib import *
from models._habitat import frame_obj
from models._habitat_overlay import *

BARK_LO, BARK_HI = rgb(124, 96, 140), rgb(176, 142, 186)  # purple-brown, lifted for the Roblox look
GRAVE_LO, GRAVE_HI = rgb(150, 160, 196), rgb(214, 222, 242)
MARK = rgb(116, 116, 168)
SOIL_LO, SOIL_HI = rgb(150, 118, 132), rgb(178, 146, 156)
FOG_LO, FOG_HI = rgb(150, 96, 236), rgb(212, 176, 255)
WAX, FLAME, FLAME_HI = rgb(250, 240, 220), rgb(255, 150, 50), rgb(255, 230, 110)
GRASS = rgb(130, 190, 120)
GHOST_LO, GHOST, GHOST_HI = rgb(220, 222, 245), rgb(244, 244, 255), rgb(255, 255, 255)
EYE = rgb(80, 70, 110)
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


def fog(n, r, x=0.0, y=0.0, z=0.06, sx=1.5, sy=1.0, sz=0.5):
    b = blob(f"Fog{n}", r, (x, y, z), None, seed=60 + n, subdiv=2, squash=(sx, sy, sz), jitter=0.06, lumps=0.25, lump_scale=1.5)
    gradient(b, FOG_LO, FOG_HI)
    on_deck([b])
    return b


def tree():
    """Bare twisty tree: a wavy tapering trunk, root flare, three branches ending in curls."""
    out = []

    def limb(name, pts, r0, r1):
        n = len(pts)
        t = tube(name, pts, [r0 + (r1 - r0) * i / (n - 1) for i in range(n)], None, segs=6, twist_free=True)
        gradient(t, BARK_LO, BARK_HI, z0=0, z1=2.7)
        out.append(t)

    limb("Trunk", [(0, 0.05, 0), (0.08, 0.05, 0.5), (-0.06, 0.02, 1.05), (0.04, 0.0, 1.55), (0.0, 0.0, 1.95)], 0.34, 0.15)
    for i, a in enumerate((0, 120, 240)):  # root flare
        aa = math.radians(a + 30)
        limb(f"Root{i}", [(0.02 * math.cos(aa), 0.05 + 0.02 * math.sin(aa), 0.3), (0.38 * math.cos(aa), 0.05 + 0.28 * math.sin(aa), 0.05)], 0.17, 0.09)

    def curl(cx, cz, s, r, start, sweep=300):
        return [(cx + s * r * math.cos(math.radians(start + s * k * sweep / 6)), 0.0, cz + r * math.sin(math.radians(start + s * k * sweep / 6)))
                for k in range(7)]

    # wide, mostly sideways branches (upward fingers read as a hand)
    limb("BranchL", [(-0.04, 0.02, 1.3), (-0.26, -0.02, 1.55), (-0.4, -0.02, 1.62)] + curl(-0.44, 1.74, -1, 0.11, -90)[1:], 0.15, 0.06)
    limb("BranchR", [(0.03, 0.0, 1.7), (0.26, 0.0, 1.98), (0.4, 0.0, 2.04)] + curl(0.44, 2.16, 1, 0.1, -90)[1:], 0.13, 0.055)
    limb("TwigL", [(-0.26, -0.02, 1.55), (-0.3, 0.0, 1.85), (-0.22, 0.0, 2.05)], 0.07, 0.04)
    limb("BranchT", [(0.0, 0.0, 1.9), (-0.08, 0.0, 2.3), (0.02, 0.0, 2.56)] + curl(0.12, 2.6, -1, 0.1, 180)[1:], 0.12, 0.045)
    out.append(fog(0, 0.28, 0.1, -0.2, 0.05, 1.4, 1.0, 0.5))
    return out


def grave(n, h, w, lean=0):
    """Chubby rounded gravestone with a raised cross on the -Y face, on a soil mound with grass tufts."""
    out = []
    m = Matrix.Rotation(math.radians(lean), 4, "Y")
    body = box(f"Stone{n}", (w, 0.24, h - w / 2), (0, 0, (h - w / 2) / 2))
    top = cylinder(f"Arch{n}", w / 2, 0.24, (0, 0.12, h - w / 2), None, segs=12, rot=(90, 0, 0))
    for p in (body, top):
        gradient(p, GRAVE_LO, GRAVE_HI, z0=0, z1=h)
        out.append(frame_obj(p, m))
    cz = h - w / 2 - 0.05
    out.append(frame_obj(box(f"CrossV{n}", (0.08, 0.05, w * 0.6), (0, -0.13, cz), MARK), m))
    out.append(frame_obj(box(f"CrossH{n}", (w * 0.4, 0.05, 0.08), (0, -0.13, cz + w * 0.08), MARK), m))
    mound = blob(f"Mound{n}", 0.4, (0, -0.06, 0.0), None, seed=n, subdiv=1, squash=(1.2, 1.0, 0.45), jitter=0.08)
    gradient(mound, SOIL_LO, SOIL_HI)
    on_deck([mound])
    out.append(mound)
    for k, s in enumerate((-1, 1)):
        out.append(cone(f"Tuft{n}{k}", 0.08, 0.22, (s * (w / 2 + 0.06), -0.12, 0.08), GRASS, segs=4))
    return out


def ghost():
    """Little cute ghost floating over a fog puff: a round body with a wavy skirt, two eyes and a smile hole."""
    out = [fog(90, 0.3, 0, 0, 0.05, 1.5, 1.1, 0.5)]
    body = lathe_ghost()
    out.append(body)
    for s in (-1, 1):
        out.append(blob(f"Eye{s}", 0.07, (s * 0.12, -0.3, 1.18), EYE, subdiv=1, jitter=0, squash=(0.8, 0.5, 1.2)))
    out.append(blob("Mouth", 0.06, (0, -0.31, 1.03), EYE, subdiv=1, jitter=0, squash=(1.2, 0.5, 0.8)))
    for s in (-1, 1):
        out.append(blob(f"Arm{s}", 0.1, (s * 0.33, -0.05, 0.98), GHOST, subdiv=1, jitter=0, squash=(1.4, 0.8, 0.8), rot=(0, s * 30, 0)))
    return out


def lathe_ghost():
    from models._habitat import lathe
    prof = [(0.0, 0.55), (0.3, 0.6), (0.34, 0.85), (0.32, 1.1), (0.24, 1.3), (0.0, 1.38)]
    def col(i, k, z):
        return GHOST_LO if i == 0 else (GHOST if i < 3 else GHOST_HI)
    g = lathe("Ghost", prof, segs=10, color_fn=col)
    for v in g.data.vertices:  # wavy skirt: bottom ring dips on every other vertex
        if abs(v.co.z - 0.6) < 1e-4:
            a = math.atan2(v.co.y, v.co.x)
            v.co.z -= 0.08 * (1 + math.cos(5 * a))
    return g


def candle():
    """Tiny candle on a dish with a two-tone flame."""
    out = [cylinder("Dish", 0.24, 0.06, (0, 0, 0), GRAVE_HI, segs=6)]
    out.append(cylinder("Wax", 0.11, 0.42, (0, 0, 0.06), WAX, segs=6))
    out.append(blob("Drip", 0.06, (0.09, -0.04, 0.4), WAX, subdiv=1, jitter=0))
    out.append(cylinder("Wick", 0.015, 0.06, (0, 0, 0.48), MARK, segs=4))
    out.append(cone("Flame", 0.08, 0.26, (0, 0, 0.5), FLAME, segs=6))
    out.append(cone("FlameHi", 0.05, 0.16, (0, -0.02, 0.52), FLAME_HI, segs=6))
    return out


put(tree(), 3.25, 90)
put(ghost(), 3.25, 117)
put(grave(0, 1.55, 0.78), 3.25, 42)
put(grave(1, 1.2, 0.66, lean=-8), 3.25, 142)
put(grave(2, 0.95, 0.6, lean=10), 3.25, 6)
put(grave(3, 0.85, 0.56, lean=-6), 3.25, 176)
put([frame_obj(o, Matrix.Scale(1.3, 4)) for o in candle()], 3.3, 210)
put([frame_obj(o, Matrix.Scale(1.3, 4)) for o in candle()], 3.35, -28)
for i, (deg, r) in enumerate(((24, 0.3), (64, 0.3), (160, 0.3), (194, 0.28))):  # fog clusters between the props
    put([fog(10 + i, r * 1.2, 0.0, 0.0, sx=1.5, sy=0.95, sz=0.6)], 3.35, deg)
for i, deg in enumerate((-62, -90, -118)):  # low fog at the front (under 0.3): bbox balance
    put([fog(30 + i, 0.26, sx=1.8, sz=0.45)], 3.42, deg)

o = overlay_finish("habitat_theme_spooky", parts)
if not PREVIEW:
    front = [v for v in o.data.vertices if v.co.z > 0.3 and v.co.y < 0 and abs(math.degrees(math.atan2(v.co.x, -v.co.y))) < 45]
    print(f"FRONT verts_over_0.3={len(front)}")
