# ranch_exclusive_shop: the Exclusive Shop, a county-fair PRIZE BOOTH. Third sibling of ranch_item_shop (pink/butter
# market stall) and ranch_upgrade_cabinet (blue/gold cabinet): same wood, same counter (10.4 wide, top z 4.1),
# its own accent pair lilac + warm gold. "Exclusive" is told in ranch words: a round striped fair-tent roof, a giant
# first-prize rosette on top, velvet ropes on gold posts, and the prizes on show. The prizes are the real pet mount
# meshes: the game puts them on the six display spots (DISPLAYS, in the exported mesh frame); this mesh only holds
# the stands, so the mounts can spin and swap. Front faces -Y. Preview with them: models/_exclusive_showcase_preview.py
import math
from lib import *
from models._phoenix_ranch import *
from models._shop_parts import *

LILAC = PALETTE["ranch_lilac"]
LILAC_LO = mix(LILAC, ROOF_D, 0.3)
LILAC_HI = mix(LILAC, CREAM, 0.35)
GOLD = rgb(252, 204, 80)          # warm gold; lows stay orange-warm (LESSONS pvp_knock_glove)
GOLD_LO = rgb(232, 146, 46)
BUTTER_LO = mix(BUTTER, WOOD, 0.3)

W = 10.4
X = W / 2
CY, CD, CH = -1.6, 3.4, 3.6
BY = 2.6                           # back wall y
PZ = 9.4                           # post height (tent rim sits on it)
parts = []
DISPLAYS = []                      # (x, y, z_top, yaw_deg) before the finish() recentre; converted at the end


def tent_paint(o, cx, cy, n, a, b, lo_a, lo_b, z0, z1):
    """Alternating gores round (cx, cy) with a dark-below / light-above gradient."""
    lay = o.data.color_attributes["Col"]
    for p in o.data.polygons:
        c = p.center
        ang = math.atan2(c.y - cy, c.x - cx)
        g = int(((ang + math.pi) / math.tau) * n + 0.5) % 2
        t = min(1.0, max(0.0, (c.z - z0) / (z1 - z0)))
        col = mix(lo_a, a, t) if g else mix(lo_b, b, t)
        for li in p.loop_indices:
            lay.data[li].color = (*col[:3], 1.0)


def lathe(name, prof, pos, segs=16, col=CREAM, sy=1.0):
    import bmesh
    bm = bmesh.new()
    x0, y0, z0 = pos
    rows = []
    for r, z in prof:
        if r < 1e-4:
            rows.append([bm.verts.new((x0, y0, z0 + z))])
        else:
            rows.append([bm.verts.new((x0 + math.cos(i * math.tau / segs + math.pi / segs) * r,
                                       y0 + math.sin(i * math.tau / segs + math.pi / segs) * r * sy, z0 + z)) for i in range(segs)])
    for a, b in zip(rows, rows[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    for row in (rows[0], rows[-1]):
        if len(row) > 2:
            bm.faces.new(row)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(name, bm, col)


# ---- counter: wood planks, lilac band, sanded top (same build as the sibling shops) ----------------------
parts += counter("C", W, CY, CD, CH, WOOD, LILAC_LO, LILAC, shade(mix(WOOD, PLAZA, 0.35), 0.85), mix(WOOD, PLAZA, 0.35))
# gold star medallion on the counter front band
st = [(math.cos(math.radians(90 + i * 36)) * (0.62 if i % 2 == 0 else 0.27), CH - 1.35 + math.sin(math.radians(90 + i * 36)) * (0.62 if i % 2 == 0 else 0.27)) for i in range(10)]
parts.append(gcyl("MedalBack", 0.85, 0.25, (0, CY - CD / 2 - 0.35, CH - 1.35), GOLD_LO, GOLD, segs=12, rot=(90, 0, 0)))
parts.append(prism("MedalStar", st, CY - CD / 2 - 0.62, CY - CD / 2 - 0.42, LILAC_LO, LILAC_HI))

# ---- posts + back wall ----------------------------------------------------------------------------------
for sx in (-1, 1):
    for y in (CY - CD / 2 - 0.1, BY):
        parts.append(bbox(f"Post{sx}{y:.0f}", (0.9, 0.9, PZ), (sx * X, y, PZ / 2), WOOD_LO, WOOD, bev=0.15))
        parts.append(bbox(f"Foot{sx}{y:.0f}", (1.4, 1.4, 0.5), (sx * X, y, 0.25), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))
        parts.append(gcyl(f"PostRing{sx}{y:.0f}", 0.62, 0.35, (sx * X, y, PZ - 1.4), GOLD_LO, GOLD, segs=8))
for k in range(8):
    x = -X + 0.45 + (W - 0.9) * (k + 0.5) / 8
    c = WOOD if k % 2 else mix(WOOD, CREAM, 0.12)
    parts.append(bbox(f"Wall{k}", ((W - 0.9) / 8 - 0.06, 0.5, PZ - 0.2), (x, BY, (PZ - 0.2) / 2), WOOD_LO, c, bev=0))
parts.append(box("WallCore", (W - 1.0, 0.3, PZ - 0.3), (0, BY + 0.1, (PZ - 0.3) / 2), WOOD_LO))

# ---- prize shelf on the back wall: lilac velvet back panel + two gold-edged display steps -------------------
parts.append(bbox("Velvet", (W - 1.6, 0.25, 4.6), (0, BY - 0.35, 6.6), LILAC, mix(LILAC_HI, CREAM, 0.3), bev=0.08))
for k, (z, d) in enumerate(((4.75, 2.4), (7.15, 1.7))):
    parts.append(bbox(f"Shelf{k}", (W - 1.4, d, 0.4), (0, BY - 0.25 - d / 2, z), WOOD_LO, mix(WOOD, PLAZA, 0.35), bev=0.08))
    parts.append(bbox(f"ShelfLip{k}", (W - 1.2, 0.25, 0.35), (0, BY - 0.25 - d - 0.05, z - 0.05), GOLD_LO, GOLD, bev=0.06))
# two spots per shelf; the lower shelf's spots sit outboard of the counter middle (keep the middle clear)
for x in (-2.6, 2.6):
    DISPLAYS.append((x, BY - 1.5, 4.95, 0.0))
for x in (-2.4, 2.4):
    DISPLAYS.append((x, BY - 1.2, 7.35, 0.0))

# ---- round fair-tent roof: lilac / butter gores, concave flare, scalloped valance -------------------------
TX, TY, TR = 0.0, (CY - CD / 2 + BY) / 2, 7.4
prof = [(TR, 0.0), (TR - 0.1, 0.3), (TR * 0.72, 1.4), (TR * 0.45, 2.7), (TR * 0.22, 3.9), (0.35, 4.9), (0.0, 5.05)]
tent = lathe("Tent", prof, (TX, TY, PZ), segs=16, sy=0.78)
tent_paint(tent, TX, TY, 16, LILAC, BUTTER, mix(LILAC_LO, ROOF_D, 0.25), mix(BUTTER_LO, GOLD_LO, 0.5), PZ, PZ + 5)
parts.append(tent)
parts.append(lathe("TentRim", [(TR + 0.15, -0.35), (TR + 0.25, 0.0), (TR + 0.1, 0.3), (TR - 0.3, 0.3), (TR - 0.4, -0.35)], (TX, TY, PZ), segs=16, col=GOLD, sy=0.78))
gradient(parts[-1], GOLD_LO, GOLD)
for k in range(16):                # valance scallops round the rim, facing out
    a = k * math.tau / 16 + math.pi / 16
    px, py = TX + math.cos(a) * (TR + 0.05), TY + math.sin(a) * (TR + 0.05) * 0.78
    col, lo = (LILAC, LILAC_LO) if k % 2 else (BUTTER, BUTTER_LO)
    sc = cylinder(f"Scal{k}", 0.95, 0.22, (px, py, PZ - 0.55), col, segs=10, rot=(90, 0, math.degrees(a) + 90))
    gradient(sc, mix(lo, col, 0.5), col)
    parts.append(sc)
# finial + pennant on the tent peak
parts.append(gcyl("Finial", 0.35, 1.2, (TX, TY, PZ + 4.8), GOLD_LO, GOLD, segs=8))

# ---- giant first-prize rosette on the tent front, the shop's hero icon ----------------------------------
RZ, RYF = PZ + 7.6, TY - 0.2                         # stands on the tent peak, facing front
for k in range(14):                # pleated lilac outer ring
    a = k * math.tau / 14
    p = blob(f"Pleat{k}", 0.78, (math.cos(a) * 2.05, RYF + 0.25, RZ + math.sin(a) * 2.05), LILAC, subdiv=1, squash=(1, 0.45, 1), jitter=0)
    gradient(p, LILAC_LO, LILAC_HI)
    parts.append(p)
parts.append(gcyl("RosetteGold", 1.85, 0.4, (0, RYF + 0.05, RZ), GOLD_LO, GOLD, segs=16, rot=(90, 0, 0)))
parts.append(gcyl("RosetteFace", 1.4, 0.3, (0, RYF - 0.2, RZ), BUTTER_LO, BUTTER, segs=16, rot=(90, 0, 0)))
st = [(math.cos(math.radians(90 + i * 36)) * (1.0 if i % 2 == 0 else 0.42), RZ + math.sin(math.radians(90 + i * 36)) * (1.0 if i % 2 == 0 else 0.42)) for i in range(10)]
parts.append(prism("RosetteStar", st, RYF - 0.55, RYF - 0.3, GOLD_LO, GOLD))
for sx in (-1, 1):                 # two ribbon tails with notched ends hanging over the valance
    tail = [(sx * 0.35, RZ - 1.6), (sx * 1.25, RZ - 1.3), (sx * 1.75, RZ - 3.7), (sx * 1.2, RZ - 3.3), (sx * 0.85, RZ - 3.9)]
    if sx < 0:
        tail = list(reversed(tail))
    parts.append(prism(f"Tail{sx}", tail, RYF + 0.15, RYF + 0.4, LILAC_LO, LILAC))

# ---- sign under the valance (SurfaceGui "EXCLUSIVE" on the face), marquee bulbs round the frame -----------
SZ, SY = PZ + 1.25, TY - TR * 0.78 + 0.85    # planted into the tent slope
parts.append(bbox("SignFrame", (8.6, 0.5, 2.9), (0, SY, SZ), shade(WOOD_D, 0.9), WOOD_D, bev=0.15))
parts.append(bbox("SignFace", (7.6, 0.3, 2.0), (0, SY - 0.22, SZ), LILAC_LO, LILAC, bev=0.06))
for sx in (-1, 1):                 # two wood braces from the sign back into the tent slope
    parts.append(tube(f"Brace{sx}", [(sx * 2.8, SY + 0.2, SZ + 0.9), (sx * 2.6, TY - 2.2, PZ + 3.1)], [0.22, 0.22], WOOD_D, segs=5))
for k in range(9):
    for z in (SZ + 1.22, SZ - 1.22):
        parts.append(blob(f"Bulb{k}{z:.0f}", 0.17, (-3.9 + k * 0.975, SY - 0.32, z), BUTTER, subdiv=1, jitter=0))

# ---- velvet-rope prize podiums either side: wood crate plinth, lilac cushion top, gold ropes to the posts ----
for sx in (-1, 1):
    x, y = sx * (X + 2.6), CY - 0.6
    parts.append(bbox(f"Plinth{sx}", (2.8, 2.8, 2.6), (x, y, 1.3), WOOD_LO, WOOD, bev=0.15))
    for j in range(3):
        parts.append(bbox(f"PlinthPlank{sx}{j}", (0.7, 0.3, 2.2), (x + (j - 1) * 0.85, y - 1.45, 1.3), shade(WOOD, 0.82), mix(WOOD, CREAM, 0.1), bev=0))
    parts.append(bbox(f"PlinthTrim{sx}", (3.1, 3.1, 0.35), (x, y, 2.7), GOLD_LO, GOLD, bev=0.1))
    parts.append(bbox(f"Cushion{sx}", (2.6, 2.6, 0.5), (x, y, 3.1), LILAC_LO, LILAC_HI, bev=0.22))
    DISPLAYS.append((x, y, 3.35, -sx * 20.0))
    # rope posts in front of each podium and a sagging rope to the front post of the booth
    px, py = x + sx * 0.2, CY - CD / 2 - 2.0
    parts.append(gcyl(f"RopePost{sx}", 0.22, 2.6, (px, py, 0.3), GOLD_LO, GOLD, segs=6))
    parts.append(gcyl(f"RopeBase{sx}", 0.55, 0.3, (px, py, 0), GOLD_LO, GOLD, segs=8))
    parts.append(blob(f"RopeKnob{sx}", 0.32, (px, py, 3.0), GOLD, subdiv=1, jitter=0))
    a, b = (px, py, 2.75), (sx * X, CY - CD / 2 - 0.55, 2.75)
    rope = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 2.75 - 0.75 * math.sin(math.pi * t)) for t in (i / 6 for i in range(7))]
    parts.append(tube(f"Rope{sx}", rope, [0.16] * 7, LILAC_LO, segs=5))

# ---- bunting between the front posts, just under the valance ---------------------------------------------
for k in range(7):
    t = (k + 0.5) / 7
    x = -X + W * t
    z = PZ - 1.75 - 0.45 * math.sin(math.pi * t)
    col = (LILAC, BUTTER, PINK)[k % 3]
    parts.append(prism(f"Flag{k}", [(x - 0.42, z + 0.2), (x + 0.42, z + 0.2), (x, z - 0.6)], CY - CD / 2 - 0.65, CY - CD / 2 - 0.5, shade(col, 0.85), col))

# ---- export the display spots in the finished mesh frame ------------------------------------------------
xs, ys, zs = [], [], []
for o in parts:
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        xs.append(w.x); ys.append(w.y); zs.append(w.z)
OFF = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs))
DISPLAYS = [(round(x - OFF[0], 2), round(y - OFF[1], 2), round(z - OFF[2], 2), yaw) for x, y, z, yaw in DISPLAYS]
print("DISPLAYS (mesh frame x, y, z_top, yaw):", DISPLAYS)

finish("ranch_exclusive_shop", parts)
