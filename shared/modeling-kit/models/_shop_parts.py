# Shared helpers for the two world shops (ranch_item_shop, ranch_upgrade_cabinet). Not an asset.
import math
import bmesh
from lib import *
from models._phoenix_ranch import *

LILAC = PALETTE["ranch_lilac"]
METAL = PALETTE["ranch_metal"]
GOO_HI = PALETTE["ranch_goo_hi"]
WOOD_LO = mix(WOOD_D, WOOD, 0.5)


def prism(name, pts, y0, y1, lo, hi):
    """Flat polygon in the XZ plane (pts = [(x, z), ...], counter-clockwise seen from -Y) extruded from y0 to y1."""
    bm = bmesh.new()
    front = [bm.verts.new((x, y0, z)) for x, z in pts]
    back = [bm.verts.new((x, y1, z)) for x, z in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(pts)
    for k in range(n):
        bm.faces.new((front[k], back[k], back[(k + 1) % n], front[(k + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(name, bm, hi)
    gradient(o, lo, hi)
    return o


def gcyl(name, r, h, pos, lo, hi, segs=8, rot=(0, 0, 0), r_top=None):
    o = cylinder(name, r, h, pos, hi, segs=segs, rot=rot, r_top=r_top)
    gradient(o, lo, hi)
    return o


def counter(prefix, w, cy, cd, ch, plank_hi, band_lo, band_hi, top_lo, top_hi, np_=9):
    """Plank counter: core, vertical front planks, coloured band, top."""
    out = [bbox(prefix + "Core", (w - 0.6, cd, ch), (0, cy, ch / 2), WOOD_LO, WOOD, bev=0.1)]
    x0 = -w / 2
    for k in range(np_):
        x = x0 + 0.3 + (w - 0.6) * (k + 0.5) / np_
        c = plank_hi if k % 2 else mix(plank_hi, CREAM, 0.12)
        h = ch - 0.6 + 0.08 * ((k * 5) % 3 - 1)
        out.append(bbox(f"{prefix}Plank{k}", ((w - 0.6) / np_ - 0.08, 0.4, h), (x, cy - cd / 2 - 0.1, h / 2 + 0.1), shade(c, 0.8), c, bev=0))
    out.append(bbox(prefix + "Band", (w - 0.4, 0.5, 0.6), (0, cy - cd / 2 - 0.2, ch - 0.25), band_lo, band_hi, bev=0.1))
    out.append(bbox(prefix + "Top", (w + 0.6, cd + 0.6, 0.5), (0, cy, ch + 0.25), top_lo, top_hi, bev=0.15))
    return out


# ---- shared colours + small pieces -----------------------------------------------------------------------
LILAC_LO = mix(LILAC, ROOF_D, 0.3)
METAL_LO = shade(METAL, 0.8)
BUTTER_LO = mix(BUTTER, WOOD, 0.3)
PLAZA = PALETTE["ranch_plaza"]
INNER = mix(WOOD, PLAZA, 0.5)


def dumbbell(prefix, x, y, z, s, col):
    out = [gcyl(prefix + "Bar", 0.13 * s, 2.0 * s, (x - 1.0 * s, y, z), METAL_LO, METAL, segs=6, rot=(0, 90, 0))]
    for d in (-1, 1):
        out.append(gcyl(f"{prefix}W{d}", 0.55 * s, 0.4 * s, (x + d * 0.75 * s - 0.2 * s, y, z), shade(col, 0.85), col, segs=10, rot=(0, 90, 0)))
    return out


# ---- blue + gold Upgrade Shop palette (warm sky blue, never a cold blue-grey) ----------------------------
BLUE = rgb(86, 158, 232)
BLUE_D = rgb(62, 122, 200)
BLUE_HI = rgb(150, 198, 246)
GOLD = rgb(248, 198, 70)
GOLD_D = rgb(206, 148, 50)


TOP_WOOD = mix(WOOD, PLAZA, 0.35)   # sanded counter top, a step lighter than the planks


def blue_counter(prefix, w, cy, cd, ch):
    """Wood counter with a blue band and a light wood top."""
    return counter(prefix, w, cy, cd, ch, WOOD, BLUE_D, BLUE, shade(TOP_WOOD, 0.85), TOP_WOOD)


def blue_sign(prefix, y, z, w=7.0, h=1.6):
    """Dark wood frame, blue face (the SurfaceGui text goes on the face)."""
    return [bbox(prefix + "Frame", (w + 0.8, 0.4, h + 0.6), (0, y, z), shade(WOOD_D, 0.9), WOOD_D, bev=0.12),
            bbox(prefix + "Face", (w, 0.3, h), (0, y - 0.2, z), BLUE_D, BLUE, bev=0.06)]


# ---- the six upgrades as display props (facing -Y, standing on z, about 2 studs tall at s=1) -------------
COOKIE = rgb(214, 160, 96)
CHOC = rgb(150, 100, 64)
LEAF = PALETTE["ranch_field"]
LEAF_HI = PALETTE["ranch_field_light"]
MAG_RED = ROOF


def up_cookie(p, x, y, z, s=1.0):
    """Slime Snacks: a big chocolate-chip cookie standing upright on a little stand."""
    out = [gcyl(p + "Disc", 0.95 * s, 0.4 * s, (x, y + 0.2 * s, z + 1.05 * s), shade(COOKIE, 0.85), COOKIE, segs=12, rot=(90, 0, 0))]
    for k, (dx, dz) in enumerate(((-0.4, 0.3), (0.35, 0.45), (0.05, -0.1), (-0.3, -0.45), (0.45, -0.3))):
        out.append(blob(f"{p}Chip{k}", 0.16 * s, (x + dx * s, y - 0.22 * s, z + (1.05 + dz) * s), CHOC, subdiv=1, squash=(1, 0.6, 1), jitter=0))
    out.append(bbox(p + "Stand", (0.5 * s, 0.6 * s, 0.25 * s), (x, y + 0.1 * s, z + 0.12 * s), GOLD_D, GOLD, bev=0.04))
    return out


def up_dumbbell(p, x, y, z, s=1.0, col=None):
    """Strong Arms: a dumbbell on a little cradle."""
    out = dumbbell(p, x, y, z + 0.7 * s, 1.1 * s, col or BLUE)
    out.append(bbox(p + "Cradle", (1.0 * s, 0.6 * s, 0.35 * s), (x, y, z + 0.18 * s), GOLD_D, GOLD, bev=0.04))
    return out


def _crescent(cx, cz, R):
    pts = []
    ox, ir = 0.42 * R, 0.82 * R
    n = 20
    outer = []
    for i in range(n * 2):
        a = math.radians(i * 360 / (n * 2))
        px, pz = math.cos(a) * R, math.sin(a) * R
        if (px - ox) ** 2 + pz ** 2 > ir * ir:
            outer.append((a, px, pz))
    outer.sort(key=lambda t: (t[0] - math.pi / 2) % (2 * math.pi))   # from the top round the left side to the bottom
    inner = []
    for i in range(n * 2):
        a = math.radians(i * 360 / (n * 2))
        px, pz = ox + math.cos(a) * ir, math.sin(a) * ir
        if px * px + pz * pz < R * R:
            inner.append((a, px, pz))
    inner.sort(key=lambda t: -((t[0] - math.pi / 2) % (2 * math.pi)))
    for _, px, pz in outer:
        pts.append((cx + px, cz + pz))
    for _, px, pz in inner:
        pts.append((cx + px, cz + pz))
    return pts


def up_moon(p, x, y, z, s=1.0):
    """Night Shift: a gold crescent moon with a little star, on a stand."""
    R = 1.0 * s
    pts = _crescent(x, z + 1.15 * s, R)
    out = [prism(p + "Moon", pts, y - 0.2 * s, y + 0.2 * s, GOLD_D, GOLD)]
    st = [(x + 0.75 * s + math.cos(math.radians(90 + i * 36)) * (0.32 if i % 2 == 0 else 0.13) * s,
           z + 1.55 * s + math.sin(math.radians(90 + i * 36)) * (0.32 if i % 2 == 0 else 0.13) * s) for i in range(10)]
    out.append(prism(p + "Star", st, y - 0.12 * s, y + 0.12 * s, BLUE_HI, CREAM))
    out.append(bbox(p + "Stand", (0.35 * s, 0.35 * s, 0.4 * s), (x - 0.55 * s, y, z + 0.2 * s), BLUE_D, BLUE, bev=0.03))
    return out


def up_clover(p, x, y, z, s=1.0):
    """Lucky Charm: a four-leaf clover on a short stem."""
    cz = z + 1.25 * s
    out = [tube(p + "Stem", [(x, y, z + 0.1 * s), (x + 0.1 * s, y, z + 0.6 * s), (x, y, cz)], [0.1 * s] * 3, shade(LEAF, 0.8), segs=5)]
    for k in range(4):
        a = math.radians(45 + k * 90)
        for d in (-1, 1):                # each leaf = two lobes = a heart
            b = a + d * math.radians(24)
            out.append(gcyl(f"{p}L{k}{d}", 0.36 * s, 0.2 * s, (x + math.cos(b) * 0.5 * s, y + 0.05 * s, cz + math.sin(b) * 0.5 * s),
                            shade(LEAF if k % 2 else LEAF_HI, 0.9), LEAF if k % 2 else LEAF_HI, segs=8, rot=(90, 0, 0)))
    out.append(blob(p + "Mid", 0.18 * s, (x, y - 0.12 * s, cz), LEAF_HI, subdiv=1, squash=(1, 0.5, 1), jitter=0))
    out.append(gcyl(p + "Pot", 0.4 * s, 0.35 * s, (x, y, z), GOLD_D, GOLD, segs=8))
    return out


def up_magnet(p, x, y, z, s=1.0):
    """Rain Magnet: a red horseshoe magnet, metal tips, with a small rain cloud above it."""
    R = 0.6 * s
    cz = z + 0.75 * s
    pts = [(x + math.cos(math.radians(180 + i * 18)) * R, y, cz + math.sin(math.radians(180 + i * 18)) * R) for i in range(11)]
    pts = [(x - R, y, cz + 0.6 * s)] + pts + [(x + R, y, cz + 0.6 * s)]
    out = [tube(p + "U", pts, [0.24 * s] * len(pts), MAG_RED, segs=6)]
    for d in (-1, 1):
        out.append(gcyl(f"{p}Tip{d}", 0.27 * s, 0.35 * s, (x + d * R, y, cz + 0.6 * s), shade(CREAM, 0.85), CREAM, segs=6))
    for k, (dx, dz, r) in enumerate(((-0.35, 0, 0.38), (0.05, 0.15, 0.48), (0.45, 0, 0.36))):
        out.append(blob(f"{p}Cloud{k}", r * s, (x + dx * s, y, cz + 1.75 * s + dz * s), CREAM, subdiv=2, jitter=0))
    for k, dx in enumerate((-0.3, 0.3)):
        out.append(blob(f"{p}Drop{k}", 0.12 * s, (x + dx * s, y - 0.1 * s, cz + 1.25 * s), BLUE, subdiv=1, squash=(1, 1, 1.5), jitter=0))
    return out


def up_lock(p, x, y, z, s=1.0):
    """Longer locks: a blue padlock with a gold clock face on the front."""
    out = [bbox(p + "Body", (1.4 * s, 0.7 * s, 1.1 * s), (x, y, z + 0.55 * s), BLUE_D, BLUE, bev=0.14 * s)]
    out.append(tube(p + "Shackle", [(x - 0.45 * s, y, z + 1.05 * s), (x - 0.45 * s, y, z + 1.55 * s), (x, y, z + 1.95 * s),
                                     (x + 0.45 * s, y, z + 1.55 * s), (x + 0.45 * s, y, z + 1.05 * s)], [0.14 * s] * 5, GOLD, segs=6))
    out.append(gcyl(p + "Clock", 0.45 * s, 0.15 * s, (x, y - 0.32 * s, z + 0.55 * s), GOLD_D, GOLD, segs=12, rot=(90, 0, 0)))
    out.append(gcyl(p + "Face", 0.35 * s, 0.1 * s, (x, y - 0.44 * s, z + 0.55 * s), CREAM, CREAM, segs=12, rot=(90, 0, 0)))
    out.append(box(p + "HandA", (0.06 * s, 0.05 * s, 0.28 * s), (x, y - 0.56 * s, z + 0.67 * s), WOOD_D))
    out.append(box(p + "HandB", (0.22 * s, 0.05 * s, 0.06 * s), (x + 0.1 * s, y - 0.56 * s, z + 0.55 * s), WOOD_D))
    return out


UPGRADE_PROPS = (up_cookie, up_dumbbell, up_moon, up_clover, up_magnet, up_lock)


def level_pips(p, x, y, z, n=3, lit=2):
    """A row of gold level pips (lit) and blue ones (not yet)."""
    out = []
    for k in range(n):
        out.append(blob(f"{p}Pip{k}", 0.13, (x + (k - (n - 1) / 2) * 0.34, y, z), GOLD if k < lit else BLUE_D, subdiv=1, squash=(1, 0.5, 1), jitter=0))
    return out


def scallops(p, x0, x1, y, z, n, cols=None, r=None):
    """A row of half-round scallops hanging along x at (y, z)."""
    cols = cols or (GOLD, BLUE)
    w = (x1 - x0) / n
    out = []
    for k in range(n):
        c = cols[k % len(cols)]
        sc = cylinder(f"{p}{k}", r or w / 2 - 0.02, 0.25, (x0 + w * (k + 0.5), y + 0.12, z), c, segs=8, rot=(90, 0, 0))
        gradient(sc, shade(c, 0.85), c)
        out.append(sc)
    return out
