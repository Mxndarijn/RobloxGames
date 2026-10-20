# pvp_goo_trap_2 "Sticky Trap": tier-2 goo trap, a domed pool of goo held in an octagonal wooden frame
# (8 chunky planks, brass corner plates), goo spilling over the rim in three drips that end in ground puddles.
# Shown lying on the ground AND held in hand. Lies on z = 0, ~3.6 studs wide, ~0.8 tall.
import random
from models._pvp import *

N = 8
R_MID, THICK, H = 1.32, 0.40, 0.50          # plank centre radius, plank thickness, plank height
R_OUT = R_MID + THICK / 2
G_LO, G_MID, G_TOP = rgb(40, 162, 126), rgb(72, 218, 170), rgb(156, 248, 214)
rnd = random.Random(7)
parts = []

# --- wooden frame: 8 planks round an octagon, slight hand-made height/tilt wobble
side = 2 * R_MID * math.tan(math.pi / N) + 0.10
for k in range(N):
    a = (k + 0.5) * math.tau / N
    h = H + rnd.uniform(-0.04, 0.05)
    tone = 0.0 if k % 2 == 0 else 0.25
    lo = mix(mix(WOOD_D, WOOD, 0.55), WOOD_D, tone * 0.4)
    hi = mix(mix(WOOD, CREAM, 0.15), WOOD, tone)
    parts.append(rbox(f"Plank{k}", (THICK, side, h), (R_MID * math.cos(a), R_MID * math.sin(a), h / 2), lo, hi,
                      bev=0.07, rot=(0, rnd.uniform(-2.5, 2.5), math.degrees(a))))
    # brass corner plate on the outer face at the joint
    c = k * math.tau / N
    rc = R_OUT / math.cos(math.pi / N) - 0.02
    parts.append(rbox(f"Plate{k}", (0.10, 0.34, 0.30), (rc * math.cos(c), rc * math.sin(c), 0.27), BRASS, BRASS_HI,
                      bev=0, rot=(0, 0, math.degrees(c))))


# --- goo pool: dome whose edge hides inside the planks, top bulging above the rim
def pool_r(a):
    return R_MID - 0.02


ROWS = [(0.0, 0.70), (0.35, 0.68), (0.62, 0.62), (0.82, 0.55), (0.95, 0.47), (1.0, 0.30), (1.0, 0.12)]


def goo_col(i, th, c):
    if i < 0:
        return G_LO
    t = min(1.0, max(0.0, (c.z - 0.45) / 0.25))
    return mix(mix(G_LO, G_MID, 0.6), mix(G_MID, G_TOP, 0.55), t)


pool = splat("Pool", pool_r, ROWS, segs=24, color_fn=goo_col)
parts.append(mark_smooth(pool))

# --- spills over the rim (metaballs): lip lens on the plank top, run down the outer face, fat drop, puddle
balls = []
for a, length in [(math.radians(-62), 1.0), (math.radians(68), 0.7), (math.radians(196), 0.85)]:
    rad, tan = Vector((math.cos(a), math.sin(a), 0)), Vector((-math.sin(a), math.cos(a), 0))
    q = frame_quat(rad, tan, Vector((0, 0, 1)))
    balls.append(Ball(rad * (R_MID - 0.05) + Vector((0, 0, H + 0.02)), (0.34, 0.30, 0.10), rot=q))   # lip over the top
    balls.append(Ball(rad * (R_OUT - 0.02) + Vector((0, 0, H - 0.04)), (0.10, 0.24, 0.10), rot=q))   # roll over the edge
    balls.append(Ball(rad * (R_OUT + 0.02) + Vector((0, 0, 0.30)), (0.07, 0.15, 0.16), rot=q))      # run (neck)
    balls.append(Ball(rad * (R_OUT + 0.07) + Vector((0, 0, 0.12)), (0.13, 0.17, 0.13), rot=q))      # fat drop
    balls.append(Ball(rad * (R_OUT + 0.08 + 0.18 * length) + Vector((0, 0, 0.0)),
                      (0.18 + 0.12 * length, 0.24, 0.06), rot=q))                                     # ground puddle
spill = metaball_mesh("Spill", balls, resolution=0.05, tris=300, smooth=1, clamp_z=0.0)
paint_goo(spill, lambda co, n: col(mix(mix(G_LO, G_MID, 0.6), mix(G_MID, G_TOP, 0.35), min(1.0, max(0.0, co.z / 0.55)))))
parts.append(spill)

# --- bubbles on the pool
for k, (x, y, r) in enumerate([(-0.30, 0.20, 0.26), (0.38, -0.25, 0.20), (0.25, 0.55, 0.14)]):
    z = 0.70 - 0.15 * (x * x + y * y)
    parts.append(mark_smooth(bubble(f"Bubble{k}", r, (x, y, z + r * 0.15), mix(G_MID, G_TOP, 0.55), mix(G_TOP, CREAM, 0.3))))

ship("pvp_goo_trap_2", parts)
