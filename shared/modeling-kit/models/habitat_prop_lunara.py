# habitat_prop_lunara: a crescent-moon swing hanging by two ropes from a small night-blue A-frame.
import math
from mathutils import Vector
from models._habitat_prop5 import *

MOON, MOON_HI = rgb(250, 214, 110), rgb(255, 244, 190)
FRAME, FRAME_HI = rgb(110, 118, 210), rgb(150, 160, 240)
ROPE = rgb(238, 226, 200)
STAR = rgb(255, 236, 140)
W2, TOP = 0.74, 1.22
parts = []
for sx in (-1, 1):
    for sy in (-1, 1):
        parts.append(tube(f"Leg{sx}{sy}", [(sx * 0.8, sy * 0.36, 0), (sx * W2, 0, TOP)], [0.06, 0.05], FRAME, segs=6))
parts.append(gradient(tube("Bar", [(-W2 - 0.05, 0, TOP), (W2 + 0.05, 0, TOP)], [0.065, 0.065], FRAME_HI, segs=6), FRAME, FRAME_HI))
for sx in (-1, 1):
    parts.append(blob(f"Knob{sx}", 0.09, (sx * (W2 + 0.08), 0, TOP), STAR, subdiv=1, jitter=0))
# crescent seat, horns up, hanging low between the legs
CZ = 0.5
pts = crescent_pts(0.46, 0.4, 0.22, n=12, cz=CZ)
parts.append(slab("Moon", pts, 0.34, MOON, hi=MOON_HI))
for sx in (-1, 1):
    hx = sx * 0.37
    parts.append(rod(f"Rope{sx}", (hx, 0, CZ + 0.24), (hx, 0, TOP), 0.022, ROPE, segs=4))
# tiny star on the moon's face
parts.append(slab("Star", star_pts(5, 0.11, 0.05, cx=0.0, cz=CZ - 0.24), 0.05, STAR, (0, -0.19, 0)))
ship("habitat_prop_lunara", parts)
