# habitat_prop_reef: signature prop for Reef: a small sunken anchor stuck upright in a sand mound, overgrown with
# bright coral (pink branch coral on the stock, an orange branch on an arm, a yellow brain coral and a purple sea fan
# at its foot). Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

IRON, IRON_D = rgb(104, 182, 196), rgb(96, 160, 184)
SAND, SAND_HI = rgb(236, 200, 134), rgb(255, 230, 172)
PINK, PINK_HI = rgb(255, 92, 150), rgb(255, 150, 190)
ORANGE, YELLOW, YELLOW_D = rgb(255, 150, 50), rgb(255, 224, 80), rgb(244, 182, 50)
FAN, FAN_HI, GREEN = rgb(186, 110, 255), rgb(222, 170, 255), rgb(110, 220, 120)


def branch(name, base, dirs, color, hi, r=0.045):
    """Branch coral: a short trunk with 2-3 forks, tips lighter."""
    out = []
    bx, by, bz = base
    for k, (dx, dz, ln) in enumerate(dirs):
        mid = (bx + dx * ln * 0.5, by - 0.01 * k, bz + dz * ln * 0.55)
        tip = (bx + dx * ln, by - 0.02 * k, bz + dz * ln)
        t = tube(f"{name}{k}", [(bx, by, bz), mid, tip], [r, r * 0.8, r * 0.6], color, segs=5)
        gradient(t, color, hi)
        out.append(t)
        out.append(blob(f"{name}T{k}", r * 0.75, tip, hi, subdiv=1, jitter=0))
    return out


parts = []
sand = blob("Sand", 0.55, (0, 0.05, 0), SAND, subdiv=2, squash=(1.55, 1.0, 0.25), jitter=0.05, seed=7)
gradient(sand, shade(SAND, 0.92), SAND_HI)
parts.append(floor(sand))

# anchor, slightly tilted, crown buried a bit in the sand
anc = []
anc.append(cylinder("Shank", 0.06, 0.92, (0, 0, 0.08), IRON, segs=6))
anc.append(torus("Ring", 0.11, 0.04, seg=10, seg2=4, rot=(90, 0, 0), pos=(0, 0, 1.08), color=IRON))
anc.append(box("Stock", (0.5, 0.09, 0.09), (0, 0, 0.84), IRON_D))
arm = torus("Arm", 0.36, 0.06, seg=12, seg2=5, rot=(90, 0, 0), arc=(math.radians(200), math.radians(340)), color=IRON)
move(arm, (0, 0, 0.5))
anc.append(arm)
for s in (-1, 1):
    a = math.radians(200 if s < 0 else 340)
    tx, tz = math.cos(a) * 0.36, 0.5 + math.sin(a) * 0.36
    anc.append(slab(f"Fluke{s}", [(0, -0.02), (0.11 * s, 0.17), (-0.05 * s, 0.11)][::s], 0.07, pos=(tx, 0, tz), color=IRON_D))
for o in anc:
    move(o, (0.02, 0.02, 0), (0, 10, 0))
    gradient(o, IRON_D, IRON, 0, 1.1)
parts += anc
# coral: pink on the stock (left), orange on the right arm, brain coral + sea fan at the foot
parts += branch("Pink", (-0.12, -0.04, 0.85), [(-0.6, 0.8, 0.34), (-0.1, 1.0, 0.38), (0.4, 0.9, 0.26)], PINK, PINK_HI, r=0.06)
parts += branch("Org", (0.32, -0.04, 0.3), [(0.5, 0.85, 0.38), (0.0, 1.0, 0.3), (-0.4, 0.9, 0.2)], ORANGE, YELLOW, r=0.055)
parts += branch("Pink2", (-0.24, -0.3, 0.05), [(-0.35, 0.95, 0.3), (0.1, 1.0, 0.36), (0.4, 0.9, 0.22)], PINK, PINK_HI, r=0.055)
brain = blob("Brain", 0.2, (-0.5, -0.12, 0.08), YELLOW, subdiv=2, squash=(1.1, 1.0, 0.75), jitter=0.04, seed=3)
paint(brain, lambda c, n: YELLOW if int((c.x * 3 + c.z * 2) * 14) % 2 == 0 else YELLOW_D)
parts.append(brain)
fan_pts = [(0, 0)] + [(0.3 * math.cos(math.radians(a)), 0.36 * math.sin(math.radians(a))) for a in range(20, 170, 15)]
fan = slab("Fan", fan_pts, 0.03, color=FAN)
gradient(fan, FAN, FAN_HI)
move(fan, (0.5, 0.12, 0.06), (0, 0, -20))
parts.append(fan)
for i, (x, y) in enumerate(((0.2, -0.3), (-0.62, 0.15))):  # little green sea grass tufts
    for k in range(3):
        a = (k - 1) * 0.35
        parts.append(cone(f"Grass{i}{k}", 0.035, 0.22, (x, y, 0.05), GREEN, segs=4, rot=(0, math.degrees(a), 0)))
prop_finish("habitat_prop_reef", parts)
