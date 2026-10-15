# Shared builder for phoenix_plaza_podium_1/2/3: stepped Slime Ranch trophy podiums for the
# global top-player leaderboard. Flat ranch_plaza top (clear for an avatar + nameplate), wood
# plank column, barn-red band, brass corner caps + rank numeral on a red front plaque (-Y).
from lib import *
from models._phoenix_ranch import *
PLAZA, METAL = P["ranch_plaza"], P["ranch_metal"]
RED_LO = mix(ROOF_D, ROOF, 0.5)
SEGS = {1: "bc", 2: "abged", 3: "abgcd"}  # 7-segment digits

def numeral(prefix, n, cx, y, cz, h, mirror=False):
    w, t = h * 0.6, h * 0.21
    out = []
    S = {"a": (0, h / 2, 1), "g": (0, 0, 1), "d": (0, -h / 2, 1),
         "b": (w / 2, h / 4, 0), "c": (w / 2, -h / 4, 0), "e": (-w / 2, -h / 4, 0), "f": (-w / 2, h / 4, 0)}
    if n == 1:  # one bar + flag + foot (two overlapping verticals z-fight dark)
        for nm, size, pos in (("I", (t * 1.15, 0.35, h + t), (0, 0, 0)), ("F", (w * 0.45, 0.31, t * 0.8), (-w * 0.2, 0, h * 0.36)),
                              ("B", (w * 0.8, 0.31, t * 0.8), (0, 0, -h / 2))):
            out.append(bbox(prefix + nm, size, (cx + pos[0] * (-1 if mirror else 1), y - (0.04 if nm == "I" else 0), cz + pos[2]),
                            shade(BUTTER, 0.92), BUTTER, bev=0))
        return out
    for s in SEGS[n]:
        dx, dz, horiz = S[s]
        if mirror:
            dx = -dx
        size = (w + t, 0.35, t) if horiz else (t, 0.35, h / 2 + t)
        out.append(bbox(f"{prefix}{s}", size, (cx + dx, y - (0.04 if horiz else 0), cz + dz), shade(BUTTER, 0.92), BUTTER, bev=0))
    return out

def podium(rank, H, W):
    """H = top surface height, W = column width. Returns parts."""
    parts, base_h = [], 0.8
    # base plinth (wider) + step
    parts.append(bbox("Base", (W + 2.4, W + 2.4, 0.45), (0, 0, 0.225), shade(WOOD_D, 0.9), WOOD_D, bev=0.15))
    parts.append(bbox("Step", (W + 1.3, W + 1.3, 0.5), (0, 0, 0.55), shade(PLAZA, 0.85), shade(PLAZA, 0.95), bev=0.12))
    col_h = H - base_h - 0.7
    # solid core + plank bands
    parts.append(bbox("Core", (W - 0.2, W - 0.2, col_h), (0, 0, base_h + col_h / 2), shade(WOOD, 0.8), WOOD, bev=0))
    n = max(3, round(col_h / 1.3))
    bh = col_h / n
    for i in range(n):
        c = WOOD if i % 2 else shade(WOOD, 0.93)
        parts.append(bbox(f"Pl{i}", (W, W, bh - 0.12), (0, 0, base_h + bh * (i + 0.5)), shade(c, 0.9), c, bev=0.08))
    # corner posts with brass caps
    for k, (sx, sy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        x, y = sx * W / 2, sy * W / 2
        parts.append(bbox(f"Post{k}", (0.9, 0.9, col_h + 0.2), (x, y, base_h + col_h / 2), mix(WOOD_D, WOOD, 0.4), WOOD_D, bev=0.12))
        parts.append(bbox(f"Cap{k}", (1.15, 1.15, 0.3), (x, y, base_h + col_h + 0.2), shade(METAL, 0.85), METAL, bev=0.08))
    # barn-red band under the top
    parts.append(bbox("Band", (W + 0.4, W + 0.4, 0.8), (0, 0, H - 0.85), RED_LO, ROOF, bev=0.1))
    # flat top slab, brass rim
    parts.append(bbox("Rim", (W + 1.5, W + 1.5, 0.3), (0, 0, H - 0.3), shade(METAL, 0.85), METAL, bev=0.08))
    parts.append(bbox("Top", (W + 1.1, W + 1.1, 0.35), (0, 0, H - 0.05), shade(PLAZA, 0.92), PLAZA, bev=0.1))
    # front plaque + numeral + brass star above
    fy = -W / 2 - 0.15
    ph = min(3.4, H - 1.3 - base_h - 0.15)
    pz = base_h + 0.1 + ph / 2 + max(0, (H - 1.3 - base_h - 0.15 - ph) / 2)
    parts.append(bbox("Plaque", (ph * 0.95, 0.3, ph), (0, fy, pz), RED_LO, ROOF, bev=0.1))
    parts.append(bbox("PlaqueRim", (ph * 0.95 + 0.35, 0.2, ph + 0.35), (0, fy + 0.1, pz), shade(METAL, 0.85), METAL, bev=0.06))
    parts += numeral("N", rank, 0, fy - 0.2, pz, ph * 0.72)
    # back plaque too (readable from the ring path either side)
    parts.append(bbox("PlaqueB", (ph * 0.95, 0.3, ph), (0, -fy, pz), RED_LO, ROOF, bev=0.1))
    parts += numeral("NB", rank, 0, -fy + 0.2, pz, ph * 0.72, mirror=True)
    # small goo drips from the top edge on two corners
    for k, (x, y) in enumerate(((-W * 0.3, -W / 2 - 0.3), (W * 0.35, W / 2 + 0.3))):
        parts.append(blob(f"Drip{k}", 0.3, (x, y * 1.08, H - 0.8), GOO, subdiv=2, squash=(0.8, 0.5, 1.8), jitter=0.03, seed=k + rank))
    parts.append(blob("Puddle", 1.2, (W / 2 + 0.6, -W / 2 - 0.6, 0.05), GOO, subdiv=2, squash=(1.3, 1, 0.1), jitter=0.03, seed=rank))
        # brass star above each plaque
    import bmesh, math
    for j, yy in enumerate((-W / 2 - 0.3, W / 2 + 0.6)):
        bm = bmesh.new(); rs = 0.5
        vs = [bm.verts.new((math.sin(math.pi * i / 5) * (rs if i % 2 == 0 else rs * 0.45), yy - 0.15,
                            math.cos(math.pi * i / 5) * (rs if i % 2 == 0 else rs * 0.45))) for i in range(10)]
        f = bm.faces.new(vs); ext = bmesh.ops.extrude_face_region(bm, geom=[f])
        bmesh.ops.translate(bm, verts=[v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)], vec=(0, 0.3, 0))
        bmesh.ops.triangulate(bm, faces=bm.faces); bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        st = obj_from_bm(f"Star{j}", bm, METAL); st.location = (0, 0, H - 0.85)
        gradient(st, shade(METAL, 0.95), shade(METAL, 1.2)); parts.append(st)
    print(f"podium {rank}: top z={H} flat top {W + 1.1:.1f} wide")
    return parts
