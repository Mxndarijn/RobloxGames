# pvp_goo_trap_3 "Mega Trap": tier-3 goo trap, the biggest: a thick pewter ring with brass bolts and a crown of
# rounded cartoony teeth leaning inward, holding a domed pool of glowing purple goo with bubbles; two purple
# spills over the rim. Shown lying on the ground AND held in hand. Lies on z = 0, ~3.9 studs wide, ~1 tall.
from models._pvp import *

R_RING, R_TUBE, SQ = 1.52, 0.32, 1.15        # ring radius, tube radius, vertical squash
RING_Z = R_TUBE * SQ - 0.02                    # tube centre height (bottom just under z=0, flattened later)
P_LO, P_MID, P_TOP = rgb(132, 62, 214), rgb(172, 98, 252), rgb(222, 176, 255)   # live purple goo (gameplay)
TOOTH, TOOTH_HI = rgb(232, 238, 248), rgb(250, 252, 255)
MET_LO, MET_MID, MET_HI = rgb(152, 142, 134), rgb(178, 170, 160), rgb(220, 214, 204)   # warm iron grey (not cold blue-grey): low band + bright top band = metal sheen
parts = []

# --- iron ring (squashed torus), banded light/mid/dark round the tube
ring = torus("Ring", R_RING, R_TUBE, Matrix.Translation((0, 0, RING_Z)) @ Matrix.Diagonal((1, 1, SQ, 1)),
             segs=20, rsegs=6, color_fn=lambda k, j, c: MET_HI if j == 1 else (MET_MID if j in (0, 2) else MET_LO))
parts.append(ring)

# --- brass bolts round the outer face
for k in range(6):
    a = (k + 0.5) * math.tau / 6
    r = R_RING + R_TUBE - 0.02
    parts.append(blob(f"Bolt{k}", 0.11, (r * math.cos(a), r * math.sin(a), RING_Z), BRASS_HI, subdiv=1,
                      squash=(1, 1, 1), jitter=0.0))

# --- teeth: rounded cones on the ring top, leaning inward
NT = 10
for k in range(NT):
    a = k * math.tau / NT
    base = Vector(((R_RING - 0.04) * math.cos(a), (R_RING - 0.04) * math.sin(a), RING_Z + R_TUBE * SQ - 0.12))
    # lean inward 22 deg: rotate about the tangent axis
    M = (Matrix.Translation(base) @ Matrix.Rotation(a, 4, "Z") @ Matrix.Rotation(math.radians(-22), 4, "Y"))
    prof = [(0.21, 0.0), (0.15, 0.32), (0.07, 0.50), (0.0, 0.55)]
    parts.append(lathe(f"Tooth{k}", prof, M, segs=5,
                       color_fn=lambda i, kk, z: TOOTH_HI if z > 0.3 else TOOTH))


# --- glowing purple pool: edge hidden inside the ring tube, dome above the teeth bases
def pool_r(a):
    return R_RING - 0.05


ROWS = [(0.0, 0.86), (0.35, 0.84), (0.62, 0.78), (0.82, 0.69), (0.95, 0.58), (1.0, 0.40), (1.0, 0.15)]


def goo_col(i, th, c):
    if i < 0:
        return P_LO
    t = min(1.0, max(0.0, (c.z - 0.55) / 0.31))
    return mix(mix(P_LO, P_MID, 0.5), mix(P_MID, P_TOP, 0.45), t)


parts.append(mark_smooth(splat("Pool", pool_r, ROWS, segs=24, color_fn=goo_col)))

# --- two spills over the rim (metaballs), between teeth
balls = []
top_z = RING_Z + R_TUBE * SQ
for a, length in [(math.radians(-75), 1.0), (math.radians(135), 0.8)]:
    rad, tan = Vector((math.cos(a), math.sin(a), 0)), Vector((-math.sin(a), math.cos(a), 0))
    q = frame_quat(rad, tan, Vector((0, 0, 1)))
    balls.append(Ball(rad * (R_RING - 0.05) + Vector((0, 0, top_z - 0.02)), (0.32, 0.26, 0.10), rot=q))
    balls.append(Ball(rad * (R_RING + R_TUBE - 0.06) + Vector((0, 0, RING_Z + 0.12)), (0.10, 0.18, 0.14), rot=q))
    balls.append(Ball(rad * (R_RING + R_TUBE + 0.02) + Vector((0, 0, 0.12)), (0.13, 0.16, 0.12), rot=q))
    balls.append(Ball(rad * (R_RING + R_TUBE + 0.06 + 0.15 * length), (0.16 + 0.10 * length, 0.22, 0.05), rot=q))
spill = metaball_mesh("Spill", balls, resolution=0.05, tris=220, smooth=1, clamp_z=0.0)
paint_goo(spill, lambda co, n: col(mix(mix(P_LO, P_MID, 0.6), mix(P_MID, P_TOP, 0.3), min(1.0, max(0.0, co.z / top_z)))))
parts.append(spill)

# --- bubbles
for k, (x, y, r) in enumerate([(-0.25, 0.15, 0.32), (0.45, -0.25, 0.22), (0.15, 0.62, 0.16)]):
    z = 0.86 - 0.12 * (x * x + y * y)
    parts.append(mark_smooth(bubble(f"Bubble{k}", r, (x, y, z + r * 0.12), mix(P_MID, P_TOP, 0.5), mix(P_TOP, CREAM, 0.3))))

# flatten the ring bottom onto the ground (everything below z = 0 -> 0); the ring keeps a flat foot,
# then squash the whole trap to 0.83 in z so it lands at the 1-stud height cap (teeth/bubbles reached 1.21)
for o in parts:
    for v in o.data.vertices:
        v.co.z = max(v.co.z, 0.0) * 0.83
ship("pvp_goo_trap_3", parts)
