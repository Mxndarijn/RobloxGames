# Exclusive shop concept C, "Crystal Spire": a dark violet stone shrine split open by giant glowing crystals.
# Two crystal towers flank the counter, a huge pink gem floats over the top inside a gold ring. Front faces -Y.
import math
import random
from lib import *
from models._phoenix_ranch import *
from models._exclusive_parts import *

parts = []
R = random.Random(5)
W, CY, CD, CH = 10.4, -1.2, 3.6, 3.6
STONE = rgb(92, 70, 140)
STONE_LO = rgb(58, 42, 100)
STONE_HI = rgb(130, 104, 180)
CRYS = rgb(150, 90, 255)
CRYS_HI = rgb(205, 165, 255)


def crystal(name, base, length, r, lean=(0, 0), col=CRYS, segs=6):
    """Hex prism + pointed tip, leaned by (deg about X, deg about Y), facet shaded."""
    prof = [(r * 0.85, 0), (r, length * 0.12), (r, length * 0.72), (0.0, length)]
    o = lathe(name, prof, (0, 0, 0), segs=segs, col=col)
    o.rotation_euler = (math.radians(lean[0]), math.radians(lean[1]), R.uniform(0, 1))
    o.location = base
    bpy.context.view_layer.update()
    o.data.transform(o.matrix_world)
    o.matrix_world.identity()
    facet(o, col, lo=0.7, hi=1.3)
    return o


import bpy

# rocky octagon base, two tiers
parts.append(gcyl("Base", 8.2, 0.9, (0, 0.4, 0), STONE_LO, STONE, segs=8))
parts.append(gcyl("BaseTrim", 7.9, 0.25, (0, 0.4, 0.9), GOLD_LO, GOLD, segs=8))
parts.append(gcyl("Base2", 7.3, 0.4, (0, 0.6, 1.1), STONE, STONE_HI, segs=8))
B = 1.5
# front steps
parts.append(bbox("Step1", (6.0, 1.5, 0.5), (0, -7.6, 0.25), STONE_LO, STONE_HI, bev=0.1))

# counter: stone with crystal inlays
parts.append(bbox("Counter", (W, CD, CH + 0.5 - B), (0, CY, B + (CH + 0.5 - B) / 2), STONE_LO, STONE, bev=0.2))
for k in range(3):
    x = (k - 1) * 3.2
    parts.append(gem(f"Inlay{k}", 0.6, (x, CY - CD / 2 - 0.15, B + 1.3), (GEM_CYAN, GEM_PINK, GEM_CYAN)[k], h=1.4, rot=(90, 0, 0)))
    parts.append(bbox(f"InlayFrame{k}", (1.6, 0.25, 1.9), (x, CY - CD / 2 + 0.05, B + 1.3), GOLD_LO, GOLD, bev=0.08))
parts.append(bbox("CounterTop", (W + 0.6, CD + 0.6, 0.5), (0, CY, CH + 0.75), GOLD_LO, GOLD_HI, bev=0.15))

# back shrine wall: stepped stone with a pointed arch window
BY = 2.6
wall = [(-5.6, B), (5.6, B), (5.6, B + 7.5), (4.0, B + 8.4), (2.0, B + 10.6), (0, B + 12.0), (-2.0, B + 10.6), (-4.0, B + 8.4), (-5.6, B + 7.5)]
parts.append(prism("Wall", wall, BY - 0.4, BY + 0.8, STONE_LO, STONE))
rim = [(x * 1.06, B + (z - B) * 1.03) for x, z in wall]
parts.append(prism("WallRim", rim, BY + 0.1, BY + 0.6, GOLD_LO, GOLD))
win = [(-2.0, B + 4.4), (2.0, B + 4.4), (2.0, B + 7.4), (0, B + 9.4), (-2.0, B + 7.4)]
parts.append(prism("Window", win, BY - 0.6, BY - 0.45, CRYS, CRYS_HI))
winf = [(-2.5, B + 4.0), (2.5, B + 4.0), (2.5, B + 7.6), (0, B + 10.0), (-2.5, B + 7.6)]
parts.append(prism("WindowFrame", winf, BY - 0.5, BY - 0.42, GOLD_LO, GOLD))

# crystal towers: one tall cluster each side, plus small shards on the base
for sx in (-1, 1):
    x0 = sx * 6.6
    parts.append(crystal(f"TowerMain{sx}", (x0, 0.6, B - 0.2), 11.5, 1.25, lean=(0, sx * 6), col=CRYS))
    parts.append(crystal(f"TowerB{sx}", (x0 + sx * 1.0, -0.6, B - 0.2), 7.0, 0.9, lean=(-10, sx * 22), col=rgb(140, 100, 240)))
    parts.append(crystal(f"TowerC{sx}", (x0 - sx * 0.5, 1.8, B - 0.2), 8.2, 0.85, lean=(14, sx * 12), col=CRYS_HI))
    parts.append(crystal(f"TowerD{sx}", (x0 + sx * 0.3, -1.6, B - 0.2), 4.4, 0.65, lean=(-22, sx * 30), col=GEM_CYAN))
    parts.append(gcyl(f"TowerRing{sx}", 1.6, 0.4, (x0, 0.6, B + 4.2), GOLD_LO, GOLD, segs=8))
    parts.append(gcyl(f"TowerRing2{sx}", 1.4, 0.35, (x0, 0.6, B + 7.0), GOLD_LO, GOLD_HI, segs=8))
for k in range(10):
    a = R.uniform(0, math.tau)
    rr = R.uniform(5.0, 7.0)
    if abs(math.cos(a) * rr) < 4.0 and math.sin(a) < 0:
        continue   # keep the front of the counter clear
    parts.append(crystal(f"Shard{k}", (math.cos(a) * rr, 0.4 + math.sin(a) * rr * 0.85, B - 0.3), R.uniform(1.2, 2.4), R.uniform(0.3, 0.5),
                         lean=(R.uniform(-25, 25), R.uniform(-25, 25)), col=(CRYS, GEM_CYAN, GEM_PINK, CRYS_HI)[k % 4]))

# floating mega gem over the shrine with a gold orbit ring + tilted second ring
GZ = B + 14.4
parts.append(gem("MegaGem", 2.5, (0, BY, GZ), GEM_PINK, h=4.4, segs=8))
for k, tilt in enumerate((0, 28)):
    ring = []
    for i in range(17):
        a = i * math.tau / 16
        x, y, z = math.cos(a) * 3.6, math.sin(a) * 3.6, 0.0
        t = math.radians(tilt)
        ring.append((x, BY + y * math.cos(t) - z * math.sin(t), GZ - 0.2 + y * math.sin(t) + z * math.cos(t)))
    parts.append(tube(f"Orbit{k}", ring, [0.14] * 17, (GOLD_HI, GOLD)[k], segs=5))
for k in range(4):
    a = k * math.tau / 4 + 0.4
    parts.append(gem(f"Moon{k}", 0.3, (math.cos(a) * 3.6, BY + math.sin(a) * 3.6, GZ - 0.2), (GEM_CYAN, GOLD_HI)[k % 2]))

# sign on the wall above the counter (SurfaceGui "EXCLUSIVE")
parts += sign_board("Sign", BY - 0.75, B + 11.3, 5.0, 1.2, face_lo=VIOLET_DEEP, face=PURPLE_D)

# braziers either side of the steps with crystal flames
for sx in (-1, 1):
    x = sx * 4.2
    parts.append(gcyl(f"Bra{sx}", 0.5, 2.2, (x, -6.5, 0.9), STONE_LO, STONE_HI, segs=6))
    parts.append(gcyl(f"BraBowl{sx}", 0.9, 0.6, (x, -6.5, 3.1), GOLD_LO, GOLD, segs=8, r_top=1.1))
    parts.append(crystal(f"Flame{sx}", (x, -6.5, 3.5), 1.6, 0.45, col=GEM_CYAN))

# on the counter: crystal ball on a gold stand + a pet cloud in a crystal cage
T = CH + 1.0
parts.append(gcyl("BallStand", 0.6, 0.5, (0, CY, T), GOLD_LO, GOLD, segs=8, r_top=0.4))
orb = blob("Orb", 0.9, (0, CY, T + 1.3), GEM_CYAN, subdiv=2, jitter=0)
gradient(orb, rgb(70, 150, 230), rgb(200, 250, 255))
parts.append(orb)
parts += puffs("Pet", -3.2, CY, T, 0.7, rgb(200, 170, 250), rgb(240, 230, 255), seed=4)
parts += puffs("Pet2", 3.2, CY, T, 0.7, rgb(240, 160, 210), rgb(255, 225, 240), seed=9)

finish("exclusive_shop_c_crystal", parts)
