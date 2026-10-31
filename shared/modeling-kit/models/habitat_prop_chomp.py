# habitat_prop_chomp: signature prop for Chomp: an orange-and-white life ring leaning on a short dock post,
# standing on a little plank. Front faces -Y.
import math
from lib import *
from models._habitat_prop4 import *

ORANGE, WHITE = rgb(255, 120, 40), rgb(250, 246, 238)
WOOD, WOOD_D = rgb(196, 138, 86), rgb(150, 100, 64)
ROPE = rgb(236, 210, 150)

parts = []
# plank deck
deck = box("Deck", (1.5, 0.95, 0.12), (0, 0.05, 0.06), WOOD)
bevel(deck, 0.03)
paint(deck, lambda c, n: WOOD if int((c.x + 0.75) / 0.375) % 2 else shade(WOOD, 0.9))
parts.append(deck)
# post behind the ring, with a rope wrap and a round cap
post = cylinder("Post", 0.13, 1.15, (0, 0.3, 0.1), WOOD, segs=8)
gradient(post, WOOD_D, WOOD)
parts += [post, cylinder("Cap", 0.16, 0.08, (0, 0.3, 1.24), WOOD_D, segs=8),
          cylinder("RopeA", 0.155, 0.07, (0, 0.3, 0.98), ROPE, segs=8),
          cylinder("RopeB", 0.155, 0.07, (0, 0.3, 1.08), ROPE, segs=8)]

# the life ring: 4 orange and 4 white sectors, leaning back on the post
R, r, tilt = 0.52, 0.15, 74
ring = torus("Ring", R, r, seg=20, seg2=7)
paint(ring, lambda c, n: ORANGE if int((math.atan2(c.y, c.x) + math.tau + math.pi / 8) / (math.tau / 8)) % 2 == 0 else WHITE)
move(ring, (0, -0.05, 0.12 + R * math.sin(math.radians(tilt)) + r * 0.8), (tilt, 0, 0))
parts.append(ring)
# rope loops on the white bands
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    band = torus(f"Band{k}", r * 1.05, 0.03, seg=8, seg2=4, rot=(90, 0, math.degrees(a)),
                 pos=(math.cos(a) * R, math.sin(a) * R, 0), color=ROPE)
    move(band, (0, -0.05, 0.12 + R * math.sin(math.radians(tilt)) + r * 0.8), (tilt, 0, 0))
    parts.append(band)
prop_finish("habitat_prop_chomp", parts)
