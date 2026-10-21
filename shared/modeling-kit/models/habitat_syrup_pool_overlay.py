# habitat_syrup_pool_overlay: syrup dressing for the cork stand pad: a glossy amber syrup ring on the dish with
# drips running over the rim and down the dish's sloping side onto the cork body (to DROP below the deck), a pancake stack with a
# butter pat at the front left, a honey pot with a dipper at the back right, and syrup bubbles on the other corners.
# The drips put the mesh bottom below the deck: finish() moves that bottom to z=0, so the game must lift the
# overlay by the printed DROP. deck_check() prints the deck-relative bbox before finish (the helper's check runs
# after the shift).
import math
from mathutils import Vector
from lib import *
from lib.goo import Ball, metaball_mesh, paint_goo, frame_quat
from models._habitat_overlay import *
from models._phoenix_pad import lathe
from models._phoenix_ranch import WOOD, WOOD_D, BUTTER, CREAM, bbox

SYR, SYR_HI, SYR_D = rgb(236, 150, 40), rgb(255, 205, 100), rgb(216, 128, 42)
CAKE, CAKE_D = rgb(240, 188, 108), rgb(208, 146, 78)
parts = [frame("Syrup", shade(SYR, 1.08), SYR_D, seed=3, wobble=0.1)]

# drips: lip lens on the frame's outer edge -> chain down the stand's side -> fat drop. 2 per side, mirrored
# positions on opposite sides so the bbox stays centred. Authored square: round_up puts each "out" distance on the
# circle of that radius. The dish slopes in from the rim (r 3.75 at the deck) to the cork body (r 3.0, 0.45 below),
# so a drip hugs that slope, then runs straight down the body.
DISH, BODY, SLOPE = D["padDeck"]["half"], D["padDeck"]["half"] - 0.75, 0.45


def side_r(z):
    """The stand's radius at deck-relative height z (<= 0), plus the drip's own thickness."""
    return max(BODY, DISH + z * (DISH - BODY) / SLOPE) + 0.08


DRIPS = [(-1.6, 0.85), (1.1, 0.55)]  # (along-edge offset, length below the deck)
balls = []
for side in range(4):
    a = side * math.pi / 2
    out = Vector((math.cos(a - math.pi / 2), math.sin(a - math.pi / 2), 0))  # -Y, +X, +Y, -X
    lat = Vector((-out.y, out.x, 0))
    q = frame_quat(lat, Vector((0, 0, 1)), out)  # lens: wide along lat, tall in z, thin outward
    for k, (t, ln) in enumerate(DRIPS):
        t = t if side % 2 == 0 else -t
        base = lat * t
        balls.append(Ball(base + out * 3.55 + Vector((0, 0, 0.14)), (0.55, 0.22, 0.1),
                          rot=frame_quat(lat, out, Vector((0, 0, 1)))))
        balls.append(Ball(base + out * side_r(0.0) + Vector((0, 0, 0.0)), (0.32, 0.22, 0.1), rot=q))
        n = 3
        for j in range(1, n + 1):
            z = -ln * j / (n + 1)
            balls.append(Ball(base + out * side_r(z) + Vector((0, 0, z)), (0.22 - 0.03 * j, 0.2, 0.065), rot=q))
        balls.append(Ball(base + out * (side_r(-ln) + 0.01) + Vector((0, 0, -ln)), (0.17, 0.19, 0.09), rot=q))
drip = metaball_mesh("Drips", balls, resolution=0.07, tris=280)
paint_goo(drip, lambda co, n: mix(SYR, SYR_HI, max(0.0, min(1.0, 0.35 + 0.65 * n.z))), smooth=False)
parts.append(drip)

# pancake stack (front left corner): 4 cakes, a syrup glaze that runs down the front, butter pat on top
px, py, CR = -BAND - 0.02, -BAND - 0.02, 0.64
offs = [(0, 0), (0.04, -0.03), (-0.03, 0.03), (0.02, 0.02), (-0.02, -0.02)]
for i, (dx, dy) in enumerate(offs):
    c = cylinder(f"Cake{i}", CR - 0.04 * (i % 2), 0.2, (px + dx, py + dy, 0.12 + i * 0.21), CAKE, segs=10)
    gradient(c, CAKE_D, shade(CAKE, 1.05))
    parts.append(c)
TOP = 0.12 + 5 * 0.21
gl = [Ball((px, py, TOP), (CR - 0.12, CR - 0.12, 0.07))]
for k, ang in enumerate((-60, -20, -120)):  # drips down the front-facing side of the stack
    a = math.radians(ang)
    d = Vector((math.cos(a), math.sin(a), 0))
    q = frame_quat(Vector((-d.y, d.x, 0)), Vector((0, 0, 1)), d)
    ln = (0.45, 0.3, 0.6)[k]
    for j in range(3):
        gl.append(Ball(Vector((px, py, TOP - 0.05 - ln * j / 2)) + d * (CR - 0.02), (0.12 - 0.015 * j, 0.15, 0.06), rot=q))
    gl.append(Ball(Vector((px, py, TOP - 0.05 - ln)) + d * CR, (0.1, 0.12, 0.08), rot=q))
glaze = metaball_mesh("Glaze", gl, resolution=0.05, tris=140)
paint_goo(glaze, lambda co, n: mix(SYR, SYR_HI, max(0.0, min(1.0, 0.3 + 0.7 * n.z))), smooth=False)
parts.append(glaze)
parts.append(bbox("Butter", (0.48, 0.48, 0.26), (px + 0.05, py + 0.02, TOP + 0.14), shade(BUTTER, 0.95), shade(BUTTER, 1.1), bev=0.06, rot=(0, 0, 25)))

# honey pot + dipper (back right corner)
hx, hy = BAND + 0.05, BAND + 0.05
POT = [(0, 0.08), (0.42, 0.08), (0.6, 0.35), (0.62, 0.62), (0.5, 0.92), (0.44, 1.0), (0.52, 1.08), (0.5, 1.16), (0.36, 1.12), (0, 1.12)]
parts.append(lathe("Pot", POT, segs=10, pos=(hx, hy, 0),
                   color_fn=lambda i, k, z: SYR_HI if i >= 7 else (CREAM if i == 5 or i == 6 else mix(SYR_D, SYR, min(1, z / 0.9)))))
parts.append(tube("Handle", [(hx - 0.05, hy, 0.9), (hx - 0.22, hy - 0.05, 1.7), (hx - 0.38, hy - 0.1, 2.3)], [0.13, 0.12, 0.14], WOOD, segs=6))
parts.append(blob("Knob", 0.19, (hx - 0.39, hy - 0.1, 2.36), shade(WOOD, 1.12), subdiv=1, jitter=0))
for j in range(4):  # grooved dipper head poking out of the pot mouth
    parts.append(cylinder(f"Dip{j}", 0.32 - 0.08 * (j % 2), 0.12, (hx - 0.06 - 0.02 * j, hy - 0.01 * j, 1.12 + j * 0.12),
                          SYR_HI if j % 2 else shade(WOOD, 1.1), segs=8))
pd = [Ball((hx, hy, 1.14), (0.46, 0.46, 0.06))]  # syrup over the pot lip, one run down the front
a = math.radians(-135)
d = Vector((math.cos(a), math.sin(a), 0))
q = frame_quat(Vector((-d.y, d.x, 0)), Vector((0, 0, 1)), d)
for j, (z, r) in enumerate(((1.0, 0.5), (0.8, 0.6), (0.6, 0.62), (0.45, 0.6))):
    pd.append(Ball(Vector((hx, hy, z)) + d * (r + 0.02), (0.13 - 0.01 * j, 0.14, 0.06), rot=q))
pd.append(Ball(Vector((hx, hy, 0.38)) + d * 0.62, (0.12, 0.13, 0.09), rot=q))
potg = metaball_mesh("PotGoo", pd, resolution=0.05, tris=110)
paint_goo(potg, lambda co, n: mix(SYR, SYR_HI, max(0.0, min(1.0, 0.3 + 0.7 * n.z))), smooth=False)
parts.append(potg)

# syrup bubble clusters on the other two corners
for i, (s, t) in enumerate(((1, -1), (-1, 1))):
    x, y = s * BAND, t * BAND
    parts.append(blob(f"Bub{i}a", 0.46, (x, y, 0.22), SYR_HI, subdiv=2, squash=(1, 1, 0.75), jitter=0.02, seed=i))
    parts.append(blob(f"Bub{i}b", 0.28, (x - s * 0.4, y + t * 0.25, 0.25), SYR_HI, subdiv=1, squash=(1, 1, 0.8), jitter=0.02, seed=i + 4))
    parts.append(blob(f"Bub{i}c", 0.2, (x + s * 0.15, y - t * 0.45, 0.2), shade(SYR_HI, 1.04), subdiv=1, squash=(1, 1, 0.8), jitter=0, seed=i + 8))


overlay_finish("habitat_syrup_pool_overlay", parts, drop=1.06)  # drips run down the stand's side
