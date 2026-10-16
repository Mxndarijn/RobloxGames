# Shared helpers for the world-border v3 piece set (ranch_border_pine_*, _oak_round, _sapling_trio,
# _hedge_*, _rock_*, _fence_*, _hill_*): single, low-poly pieces that WorldBorder.luau scatters in
# layers (fence/hedge inner, trees and rocks mid, hills outer). Not a model: no finish().
import math, random
import bmesh
from mathutils import Vector
from lib import *
from models._border import FIELD, FIELD_L, FIELD_D, WOOD, WOOD_D, PINK, LILAC, BUTTER, CREAM, GOO, GOO_HI, tuft, flower, _tier
from models._border_chunk import lowpoly, lift, mound, hedge_run, pines, bush, tufts, goo_puddle, SAND, MOSS, WOOD_LO
from models._rocks import stone, pebble

FIR_D = mix(FIELD_D, rgb(70, 136, 96), 0.5)
FIR_M = FIELD_D
FIR_L = mix(FIELD, FIELD_L, 0.5)


def conifer(prefix, x, y, H, R, tiers=4, tips=6, spread=0.33, shape=0.68, trunk=1.0, dark=FIR_D, mid=FIR_M, light=FIR_L):
    """Fir: trunk tube + `tiers` cone skirts. spread = base radius / H, shape = how much the skirts
    narrow towards the crown (small = column, large = steeple)."""
    tr = (0.22 * H / 10 + 0.3) * trunk
    parts = [tube(f"{prefix}Trunk", [(x, y, -0.15), (x, y, H * 0.25), (x, y, H * 0.55)], [tr * 1.6, tr, tr * 0.7], WOOD, segs=6, seed=R)]
    gradient(parts[-1], WOOD_D, WOOD)
    for i in range(tiers):
        t = i / max(1, tiers - 1)
        r = H * spread * (1 - shape * t)
        z = H * (0.18 + 0.64 * t)
        h = H * (0.27 - 0.06 * t) * (1.0 if tiers > 3 else 1.25)
        parts.append(_tier(f"{prefix}Tier{i}", x, y, r, h, z, max(4, tips - i // 2), 0.4 + 0.2 * (1 - t), i * 0.37 + R.uniform(0, 1), R,
                           mix(dark, mid, t * 0.5), mix(mid, light, 0.45 + 0.55 * t)))
    return parts


def round_tree(prefix, x, y, H, R, crown=4.6, trunk=0.8, lean=0.0, n=5, leaf=FIELD, leaf_d=FIELD_D, leaf_l=FIELD_L):
    """Round-crowned tree: flared trunk, ring of uneven puffs and a crown puff (tree_oak recipe, low-poly)."""
    parts = [tube(f"{prefix}Trunk", [(x, y, -0.15), (x + lean * 0.2, y, H * 0.35), (x + lean, y, H * 0.78)], [trunk * 1.5, trunk * 0.95, trunk * 0.7],
                  WOOD, segs=6, seed=R, jitter=0.05)]
    gradient(parts[-1], shade(WOOD_D, 0.92), mix(WOOD, WOOD_D, 0.45))
    cz = H - crown * 0.55
    cx = x + lean
    core = blob(f"{prefix}Core", crown * 0.85, (cx, y, cz), seed=R.randint(0, 99), subdiv=2, squash=(1.05, 1.0, 0.85), jitter=0.04)
    gradient(lowpoly(core, 0.7), shade(leaf_d, 0.9), leaf)
    parts.append(core)
    for k in range(n):
        a = k * math.tau / n + R.uniform(-0.3, 0.3)
        d = crown * R.uniform(0.62, 0.85)
        r = crown * R.uniform(0.5, 0.68)
        o = blob(f"{prefix}Puff{k}", r, (cx + math.cos(a) * d, y + math.sin(a) * d, cz - crown * 0.12 + R.uniform(-0.4, 0.5)),
                 seed=R.randint(0, 99), subdiv=2, squash=(1, 1, 0.85), jitter=0.06)
        gradient(lowpoly(o, 0.65), leaf_d, leaf)
        parts.append(o)
    top = blob(f"{prefix}Top", crown * 0.58, (cx + R.uniform(-0.4, 0.4), y + R.uniform(-0.3, 0.3), cz + crown * 0.5), seed=R.randint(0, 99), subdiv=2,
               squash=(1, 1, 0.85), jitter=0.05)
    gradient(lowpoly(top, 0.65), leaf, leaf_l)
    parts.append(top)
    return parts


def fence_posts_rails(prefix, xs, y, R, lean=None, rails=(1.6, 3.1), skip=(), post_h=4.3, rail_drop=None):
    """Rail fence over post x positions `xs`. lean = {post index: degrees leaning to -Y}; skip = bay
    indices with no rails (the gap of a broken fence); rail_drop = {(bay, rail): z at the far end}."""
    lean = lean or {}
    rail_drop = rail_drop or {}
    parts = []
    for k, x in enumerate(xs):
        h = post_h + R.uniform(-0.25, 0.25)
        p = cylinder(f"{prefix}Post{k}", 0.62, h, (x, y, -0.1), WOOD, segs=6, r_top=0.52, jitter=0.04, seed=R.randint(0, 99), rot=(lean.get(k, 0), R.uniform(-2, 2), 0))
        gradient(p, WOOD_D, WOOD)
        parts.append(p)
        la = math.radians(lean.get(k, 0))
        parts.append(cylinder(f"{prefix}Cap{k}", 0.56, 0.24, (x, y - math.sin(la) * (h - 0.08), math.cos(la) * (h - 0.08)),
                              mix(WOOD, CREAM, 0.35), segs=6, r_top=0.38, rot=(lean.get(k, 0), 0, 0)))
    for b in range(len(xs) - 1):
        if b in skip:
            continue
        xa, xb = xs[b], xs[b + 1]
        for k, z in enumerate(rails):
            zb = rail_drop.get((b, k), z)
            ln = math.hypot(xb - xa, zb - z) + 0.5
            ang = math.degrees(math.atan2(zb - z, xb - xa))
            rail = cylinder(f"{prefix}Rail{b}_{k}", 0.36, ln, (xa - 0.25, y - 0.12 * (-1) ** k, z), WOOD, segs=6, rot=(0, 90 - ang, 0), jitter=0.05, seed=R.randint(0, 99))
            gradient(rail, WOOD_LO, mix(WOOD, CREAM, 0.15), z0=min(z, zb) - 0.4, z1=max(z, zb) + 0.4)
            parts.append(rail)
    return parts


def hill(name, cx, cy, sx, sy, H, R, humps, trees=(), rocks=(), tufts_n=6, NS=26, NR=7, tint=None):
    """Grassy backdrop hill: mound() + low-poly firs/stones standing on it + tufts on the map-side slope."""
    o, hz = mound(name, cx, cy, sx, sy, H, R, humps=humps, NS=NS, NR=NR)
    gradient(o, mix(FIELD, FIELD_D, 0.3), mix(FIELD, FIELD_L, 0.75))  # foot matches the ground, crest catches the sun
    parts = [o]
    for k, (x, y, hh) in enumerate(trees):
        parts += pines(f"{name}Fir{k}", [(x, y, hh)], R, tips=6, tiers=4, hz=hz)
    for k, (x, y, size) in enumerate(rocks):
        parts.append(stone(f"{name}Rock{k}", size, (x, y, max(0.0, hz(x, y)) - 0.35), seed=R.randint(0, 999), base=shade(SAND, R.uniform(0.94, 1.03)), moss=MOSS, moss_from=0.62, cuts=2, n=16))
    for k in range(tufts_n):
        x, y = cx + R.uniform(-sx * 0.3, sx * 0.3), cy - R.uniform(0.0, sy * 0.28)
        z = hz(x, y)
        if z < 0.4:
            continue
        parts += tuft(f"{name}Tuft{k}", (x, y, z), R, h=1.1, blades=3)
    return parts
