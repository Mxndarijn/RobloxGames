# Shared builders for the Steal a Slime obby world backdrop (games/steal-a-slime/src/visuals/client/ObbyBackdrop.luau):
# floating goo islands (goo-green grass cap that drips over the rim, faceted lilac rock belly tapering to a point, props
# on top), soft cumulus clouds and the cloud-sea banks. Decor seen from 75-1000 studs away, so props are chunky and
# the tris go to the silhouette. One mesh = one MeshPart; the game reuses each mesh with varied scale, yaw and a
# light MeshPart.Color tint (it multiplies the vertex colours), so the colours here are the brightest variant.
import math
import random

import bmesh
import bpy
from mathutils import Vector, noise

from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo

GRASS = rgb(116, 206, 112)
GRASS_HI = rgb(156, 228, 128)
GRASS_GOO = rgb(84, 190, 118)  # the drips over the rim
ROCK = [rgb(186, 156, 220), rgb(160, 130, 206), rgb(140, 114, 192), rgb(124, 100, 180)]
ROCK_TIP = rgb(118, 96, 172)
GOO = {"pink": rgb(255, 122, 190), "cyan": rgb(104, 210, 248), "butter": rgb(255, 204, 92), "mint": rgb(110, 226, 170)}
STEM, WOOD, WOOD_DARK = rgb(246, 232, 212), rgb(184, 128, 92), rgb(150, 100, 76)
LEAF, LEAF_HI = rgb(110, 196, 132), rgb(160, 228, 150)
BLOSSOM, BLOSSOM_HI = rgb(246, 150, 196), rgb(255, 196, 224)
CLOUD_TOP, CLOUD_MID, CLOUD_BELLY = rgb(255, 250, 255), rgb(244, 228, 250), rgb(206, 186, 236)


def _col_layer(bm):
    return bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")


def outline_fn(seed, wobble=0.13):
    r = random.Random(seed)
    p = [r.random() * math.tau for _ in range(3)]
    return lambda a: 1 + wobble * math.sin(3 * a + p[0]) + wobble * 0.55 * math.sin(5 * a + p[1]) + wobble * 0.3 * math.sin(8 * a + p[2])


def revolve(name, R, outline, profile, segs, color_fn, lump=0.0, seed=0, drip=None, smooth=False):
    """Closed surface of revolution. profile: [(f, z)] top to bottom, f = radius factor (0 = pole). Vertex at angle a:
    radius R * outline(a) * f. drip(a, i) -> extra z per ring i (negative = hangs down). color_fn(i, a, co) -> RGBA per
    corner. lump: Perlin radial wobble (fraction of R), 0 at the poles."""
    bm = bmesh.new()
    rings = []
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for i, (f, z) in enumerate(profile):
        if f <= 0:
            rings.append([bm.verts.new((0, 0, z))])
            continue
        ring = []
        for k in range(segs):
            a = k * math.tau / segs
            rr = R * outline(a) * f
            co = Vector((math.cos(a) * rr, math.sin(a) * rr, z + (drip(a, i) if drip else 0)))
            if lump:
                n = noise.noise(co / (R * 0.45) + off)
                co.x += math.cos(a) * n * lump * R
                co.y += math.sin(a) * n * lump * R
            ring.append(bm.verts.new(co))
        rings.append(ring)
    for ra, rb in zip(rings, rings[1:]):
        if len(ra) == 1:
            for k in range(segs):
                bm.faces.new((ra[0], rb[(k + 1) % segs], rb[k]))
        elif len(rb) == 1:
            for k in range(segs):
                bm.faces.new((ra[k], ra[(k + 1) % segs], rb[0]))
        else:
            for k in range(segs):
                bm.faces.new((ra[k], ra[(k + 1) % segs], rb[(k + 1) % segs], rb[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    col = _col_layer(bm)
    index = {}
    for i, ring in enumerate(rings):
        for v in ring:
            index[v] = i
    for fc in bm.faces:
        for lp in fc.loops:
            co = lp.vert.co
            lp[col] = color_fn(index[lp.vert], math.atan2(co.y, co.x) % math.tau, co)
    o = obj_from_bm(name, bm, smooth=smooth)
    _flag_smooth(o, smooth)
    return o


def _flag_smooth(o, smooth):
    me = o.data
    attr = me.attributes.get("keep_smooth") or me.attributes.new("keep_smooth", "INT", "FACE")
    for i in range(len(me.polygons)):
        attr.data[i].value = int(smooth)


def ship(name, parts):
    """finish() + put the smooth flags back (finish flat-shades everything)."""
    for p in parts:
        if "keep_smooth" not in p.data.attributes:
            _flag_smooth(p, False)
    o = finish(name, parts)
    me = o.data
    attr = me.attributes.get("keep_smooth")
    if attr:
        for i, p in enumerate(me.polygons):
            p.use_smooth = bool(attr.data[i].value)
        me.attributes.remove(attr)
    return o


# ---------------------------------------------------------------------------------------------------------------- island


def island_body(R, seed, depth=1.35, segs=26, drips=8, drip_len=0.3, top_z=0.0, tip_shift=(0.0, 0.0), spikes=3):
    """Grass cap (domed, overhanging rim, goo lobes dripping over the edge) + faceted rock belly to a point.
    Returns (parts, outline, top height fn). The grass top sits at about z = top_z + 0.06 R."""
    rnd = random.Random(seed)
    out = outline_fn(seed)
    dome = 0.07 * R
    drip_at = sorted(rnd.random() * math.tau for _ in range(drips))
    drip_amt = [drip_len * R * (0.5 + rnd.random()) for _ in drip_at]

    def lobe(a):
        best = 0.0
        for da, amt in zip(drip_at, drip_amt):
            d = abs((a - da + math.pi) % math.tau - math.pi)
            w = max(0.0, 1 - d / 0.22)
            best = max(best, amt * w * w * (3 - 2 * w))
        return best

    t = top_z
    grass_profile = [(0, t + dome), (0.35, t + dome * 0.85), (0.7, t + dome * 0.45), (0.96, t), (1.04, t - 0.04 * R),
                     (1.03, t - 0.12 * R), (0.97, t - 0.16 * R), (0.6, t - 0.19 * R), (0, t - 0.21 * R)]

    def grass_drip(a, i):
        return -lobe(a) * (1.0 if i == 6 else 0.55 if i == 5 else 0.0)

    def grass_col(i, a, co):
        if i <= 2:
            return mix(GRASS_HI, GRASS, i / 2 * 0.8 + 0.2 * noise.noise(co * 0.3))
        if i == 3:
            return GRASS
        return mix(GRASS, GRASS_GOO, min(1, (i - 3) / 2))

    grass = revolve("Grass", R, out, grass_profile, segs, grass_col, lump=0.02, seed=seed, drip=grass_drip)

    D = depth * R
    rock_profile = [(0.99, t - 0.08 * R), (0.93, t - 0.2 * R), (0.8, t - 0.34 * D), (0.62, t - 0.5 * D),
                    (0.44, t - 0.64 * D), (0.27, t - 0.78 * D), (0.12, t - 0.9 * D), (0, t - D)]
    sx, sy = tip_shift

    def rock_col(i, a, co):
        if i >= len(rock_profile) - 2:
            return ROCK_TIP
        band = ROCK[min(i // 2, 3)]
        return shade(band, 1.0 + 0.08 * noise.noise(co * 0.25 + Vector((seed, 0, 0))))

    rock = revolve("Rock", R, out, rock_profile, segs - 6, rock_col, lump=0.09, seed=seed + 7)
    me = rock.data
    for v in me.vertices:  # bend the point off-centre so the belly isn't a perfect cone
        k = max(0.0, (t - 0.2 * R - v.co.z) / D)
        v.co.x += sx * R * k * k
        v.co.y += sy * R * k * k
    parts = [grass, rock]
    for s in range(spikes):  # smaller hanging rock spurs round the belly
        a = rnd.random() * math.tau
        rr = R * out(a) * (0.55 + 0.1 * rnd.random())
        h = D * (0.35 + 0.2 * rnd.random())
        z0 = t - 0.3 * D
        spur = cylinder(f"Spur{s}", R * (0.16 + 0.06 * rnd.random()), h, pos=(math.cos(a) * rr, math.sin(a) * rr, z0 - h), segs=6,
                        r_top=None, jitter=0.12, seed=seed + s)
        _taper_down(spur, z0 - h, z0)
        gradient(spur, ROCK_TIP, ROCK[1])
        parts.append(spur)
    return parts, out, (lambda x, y: t + dome * (1 - min(1, math.hypot(x, y) / R) ** 2) * 0.95), lobe, drip_at


def _taper_down(o, z_lo, z_hi):
    """Pinch a standing cylinder's bottom ring to a point (a hanging spur)."""
    for v in o.data.vertices:
        if v.co.z < (z_lo + z_hi) / 2:
            c = Vector((sum(w.co.x for w in o.data.vertices), sum(w.co.y for w in o.data.vertices), 0)) / len(o.data.vertices)
            v.co.x, v.co.y = c.x, c.y
    o.data.update()
    cleanup(o, merge=1e-3)


def goo_drips(R, out, drip_at, lobe, top_z, color, seed, n=4, depth=1.35):
    """Long goo strands hanging off the rim under the biggest lobes, each with a drop below."""
    rnd = random.Random(seed)
    parts = []
    for j, a in enumerate(drip_at[:n]):
        rr = R * out(a) * 0.98
        z0 = top_z - 0.1 * R - lobe(a)
        L = R * (0.25 + 0.3 * rnd.random())
        pts = [(math.cos(a) * rr, math.sin(a) * rr, z0 + 0.05 * R), (math.cos(a) * rr * 1.01, math.sin(a) * rr * 1.01, z0 - L * 0.5),
               (math.cos(a) * rr * 0.99, math.sin(a) * rr * 0.99, z0 - L)]
        w = R * 0.05
        strand = tube(f"Strand{j}", pts, [w, w * 0.6, w * 0.35], color=color, segs=6)
        parts.append(strand)
        drop = blob(f"Drop{j}", w * 1.1, pos=(pts[2][0], pts[2][1], pts[2][2] - w * 1.6), color=color, subdiv=2, squash=(1, 1, 1.35),
                    jitter=0.02)
        parts.append(drop)
    return parts


def mushroom(name, pos, h, cap_r, cap, seed, spots=True):
    x, y, z = pos
    rnd = random.Random(seed)
    stem = cylinder(name + "Stem", cap_r * 0.28, h, pos=(x, y, z - 0.2), color=STEM, segs=7, r_top=cap_r * 0.22)
    gradient(stem, shade(STEM, 0.86), STEM)
    c = blob(name + "Cap", cap_r, pos=(x, y, z + h), subdiv=2, squash=(1, 1, 0.62), jitter=0.03, seed=seed)
    for v in c.data.vertices:  # flatten the underside: a dome, not a ball
        v.co.z = max(v.co.z, z + h - cap_r * 0.12)
    c.data.update()
    gradient(c, shade(cap, 0.8), cap)
    parts = [stem, c]
    if spots:
        for s in range(4):
            a = rnd.random() * math.tau
            el = 0.5 + 0.35 * rnd.random()
            sp = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el) * 0.62)) * cap_r
            parts.append(blob(name + f"Spot{s}", cap_r * 0.16, pos=(x + sp.x, y + sp.y, z + h + sp.z), color=rgb(255, 250, 244),
                              subdiv=1, squash=(1, 1, 0.5), jitter=0.0))
    return parts


def crystal(name, pos, h, r, color, tilt=(0, 0), seed=0):
    """Hex prism with a pointed top, tilted (degrees about x, y), light tip over a deeper base."""
    x, y, z = pos
    body = cylinder(name + "B", r, h * 0.72, pos=(0, 0, -h * 0.12), segs=6)
    tip = cone(name + "T", r, h * 0.4, pos=(0, 0, h * 0.6), segs=6)
    parts = []
    for o in (body, tip):
        o.rotation_euler = (math.radians(tilt[0]), math.radians(tilt[1]), random.Random(seed).random())
        o.location = (x, y, z)
        apply_transforms(o)
        gradient(o, shade(color, 0.72), mix(color, rgb(255, 255, 255), 0.45))
        parts.append(o)
    return parts


def crystal_cluster(name, pos, h, color, seed, n=4):
    rnd = random.Random(seed)
    parts = crystal(name + "0", pos, h, h * 0.16, color, (0, 0), seed)
    for i in range(1, n):
        a = rnd.random() * math.tau
        tilt = 22 + 14 * rnd.random()
        hh = h * (0.45 + 0.3 * rnd.random())
        d = h * 0.14
        parts += crystal(name + str(i), (pos[0] + math.cos(a) * d, pos[1] + math.sin(a) * d, pos[2]), hh, hh * 0.18, color,
                         (-math.sin(a) * tilt, math.cos(a) * tilt), seed + i)
    return parts


def tree(name, pos, h, seed, canopy=LEAF, canopy_hi=LEAF_HI):
    """Lollipop goo tree: curved trunk, three-tier puff canopy."""
    x, y, z = pos
    rnd = random.Random(seed)
    lean = (rnd.random() - 0.5) * h * 0.15
    trunk = tube(name + "Trunk", [(x, y, z - 0.3), (x + lean * 0.4, y, z + h * 0.35), (x + lean, y + lean * 0.3, z + h * 0.62)],
                 [h * 0.085, h * 0.055, h * 0.045], segs=6)
    gradient(trunk, WOOD_DARK, WOOD)
    cx, cy, cz = x + lean, y + lean * 0.3, z + h * 0.72
    parts = [trunk]
    puffs = [(0, 0, 0, 0.3), (0.2, 0.08, -0.06, 0.22), (-0.18, -0.1, -0.05, 0.22), (0.04, -0.2, 0.0, 0.2), (-0.05, 0.16, 0.12, 0.2),
             (0.02, 0.0, 0.2, 0.19)]
    for i, (px, py, pz, pr) in enumerate(puffs):
        p = blob(name + f"Puff{i}", pr * h * (0.9 + 0.2 * rnd.random()), pos=(cx + px * h, cy + py * h, cz + pz * h), subdiv=2,
                 jitter=0.05, seed=seed + i)
        gradient(p, shade(canopy, 0.82), canopy_hi)
        parts.append(p)
    return parts


def slime_house(name, pos, s, body, roof, seed, yaw=0.0):
    """Gumdrop slime hut: dome body, goo roof cap dripping over, round door and window, chimney. s = height."""
    x, y, z = pos
    parts = []
    dome = blob(name + "Dome", s * 0.55, pos=(0, 0, 0), subdiv=3, squash=(1, 1, 1.05), jitter=0.0)
    for v in dome.data.vertices:
        v.co.z = max(v.co.z, -s * 0.02)
    gradient(dome, shade(body, 0.86), body)
    cap = blob(name + "Roof", s * 0.6, pos=(0, 0, s * 0.18), subdiv=2, squash=(1, 1, 0.82), jitter=0.02, seed=seed)
    for v in cap.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        floor = s * (0.3 - 0.12 * max(0.0, math.sin(4 * a + seed)) ** 3)
        v.co.z = max(v.co.z, floor)
    gradient(cap, shade(roof, 0.82), mix(roof, rgb(255, 255, 255), 0.25))
    door = cylinder(name + "Door", s * 0.16, s * 0.1, pos=(0, -s * 0.5, s * 0.14), rot=(90, 0, 0), color=WOOD_DARK, segs=10)
    door2 = box(name + "DoorLow", (s * 0.32, s * 0.1, s * 0.16), pos=(0, -s * 0.5 + s * 0.05, s * 0.08), color=WOOD_DARK)
    win = cylinder(name + "Win", s * 0.09, s * 0.08, pos=(s * 0.3, -s * 0.44, s * 0.32), rot=(90, 0, 30), color=rgb(255, 226, 140),
                   segs=8)
    chim = cylinder(name + "Chim", s * 0.07, s * 0.28, pos=(-s * 0.22, s * 0.12, s * 0.5), color=WOOD, segs=6)
    for o in (dome, cap, door, door2, win, chim):
        o.rotation_euler = (0, 0, yaw)
        o.location = (x, y, z)
        apply_transforms(o)
        parts.append(o)
    return parts


def rocks(name, R, out, topz, seed, n=3):
    rnd = random.Random(seed)
    parts = []
    for i in range(n):
        a = rnd.random() * math.tau
        rr = R * out(a) * (0.55 + 0.3 * rnd.random())
        x, y = math.cos(a) * rr, math.sin(a) * rr
        size = R * (0.06 + 0.05 * rnd.random())
        b = blob(name + str(i), size, pos=(x, y, topz(x, y) + size * 0.3), subdiv=1, squash=(1.2, 1, 0.8), jitter=0.18, seed=seed + i)
        gradient(b, ROCK[2], ROCK[0])
        parts.append(b)
    return parts


def tufts(name, R, out, topz, seed, n=10):
    """Little grass cones in clumps of three: breaks up the flat cap."""
    rnd = random.Random(seed)
    parts = []
    for i in range(n):
        a = rnd.random() * math.tau
        rr = R * out(a) * (0.25 + 0.65 * rnd.random())
        x, y = math.cos(a) * rr, math.sin(a) * rr
        for j in range(3):
            dx, dy = (rnd.random() - 0.5) * R * 0.05, (rnd.random() - 0.5) * R * 0.05
            h = R * (0.05 + 0.04 * rnd.random())
            c = cone(name + f"{i}_{j}", R * 0.018, h, pos=(x + dx, y + dy, topz(x, y) - 0.1), segs=4)
            gradient(c, GRASS, GRASS_HI)
            parts.append(c)
    return parts


def waterfall(name, R, out, a, top_z, color, length=1.3):
    """A ribbon of goo pouring off the rim at angle a: arcs out and falls, widening, into a puff of splash."""
    rr = R * out(a) * 0.97
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    bm = bmesh.new()
    rows = []
    n = 9
    L = length * R
    for i in range(n + 1):
        t = i / n
        d = rr + R * 0.28 * math.sin(t * math.pi * 0.5)  # out over the edge, then straight down
        z = top_z + 0.02 * R - L * t ** 1.4
        w = R * (0.1 + 0.08 * t)
        th = R * 0.03
        cx, cy = ux * d, uy * d
        rows.append([bm.verts.new((cx + px * w * sx + ux * th * so, cy + py * w * sx + uy * th * so, z)) for sx, so in
                     ((-1, -1), (1, -1), (1, 1), (-1, 1))])
    for ra, rb in zip(rows, rows[1:]):
        for k in range(4):
            bm.faces.new((ra[k], ra[(k + 1) % 4], rb[(k + 1) % 4], rb[k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    gradient_bm(bm, mix(color, rgb(255, 255, 255), 0.35), color)
    o = obj_from_bm(name, bm)
    end = Vector((ux * (rr + R * 0.28), uy * (rr + R * 0.28), top_z + 0.02 * R - L))
    parts = [o]
    for i in range(4):  # splash
        ang = i * math.tau / 4
        parts.append(blob(name + f"Splash{i}", R * (0.09 + 0.02 * i), pos=(end.x + math.cos(ang) * R * 0.1, end.y + math.sin(ang) * R * 0.1,
                                                                             end.z + R * 0.02 * i), color=mix(color, rgb(255, 255, 255), 0.6),
                          subdiv=2, jitter=0.05, seed=i))
    # the pool it pours from: a goo puddle on the cap at the rim
    pool = blob(name + "Pool", R * 0.16, pos=(ux * rr * 0.86, uy * rr * 0.86, top_z + 0.01 * R), color=color, subdiv=2,
                squash=(1.3, 1.3, 0.18), jitter=0.02)
    parts.append(pool)
    return parts


def spot(R, out, a, f):
    rr = R * out(a) * f
    return math.cos(a) * rr, math.sin(a) * rr


# ---------------------------------------------------------------------------------------------------------------- clouds


def cloud(name, puffs, res, tris, belly=CLOUD_BELLY, flat=0.35):
    """Soft cumulus from metaball puffs [(x, y, z, r or (rx, ry, rz))]: one smooth pass, a flattened belly, lilac shade
    underneath fading to white on top."""
    balls = [Ball((x, y, z), s if isinstance(s, tuple) else (s, s, s)) for x, y, z, s in puffs]
    o = metaball_mesh(name, balls, resolution=res, tris=tris, smooth=1)
    me = o.data
    zs = [v.co.z for v in me.vertices]
    lo, hi = min(zs), max(zs)
    cut = lo + (hi - lo) * flat * 0.4
    for v in me.vertices:  # soft-flatten the underside
        if v.co.z < cut:
            v.co.z = cut - (cut - v.co.z) * 0.25
    me.update()
    zs = [v.co.z for v in me.vertices]
    lo, hi = min(zs), max(zs)

    def col(co, n):
        t = min(1.0, max(0.0, (co.z - lo) / (hi - lo)))
        c = mix(CLOUD_MID, CLOUD_TOP, min(1, t * 1.4))
        return mix(c, belly, max(0.0, -n.z) * (1 - t) * 0.9)

    paint_goo(o, col)
    return o


def cloud_puffs(name, puffs, floor=None, belly=CLOUD_BELLY, seed=0):
    """Stylised cumulus from separate smooth puffs [(x, y, z, r, subdiv)] that overlap (closed shells, no booleans):
    the outline stays scalloped, unlike fused metaballs. Every puff is flattened at `floor` (a flat cloud belly) and
    painted by world height (white top, lilac-pink lower) plus a lilac shade on down-facing sides."""
    lo = floor if floor is not None else min(z - r * 0.4 for _, _, z, r, _ in puffs)
    hi = max(z + r for _, _, z, r, _ in puffs)
    parts = []
    for i, (x, y, z, r, sub) in enumerate(puffs):
        b = blob(f"{name}{i}", r, pos=(x, y, z), subdiv=sub, jitter=0.0, lumps=0.05, lump_scale=1.5, seed=seed + i)
        for v in b.data.vertices:
            v.co.z = max(v.co.z, lo)
        b.data.update()

        def col(co, n):
            t = min(1.0, max(0.0, (co.z - lo) / (hi - lo)))
            c = mix(CLOUD_MID, CLOUD_TOP, min(1.0, t * 1.6))
            return mix(c, belly, max(0.0, -n.z) * 0.85 + (1 - min(1.0, t * 3)) * 0.35)

        paint_goo(b, col)
        parts.append(b)
    return parts
