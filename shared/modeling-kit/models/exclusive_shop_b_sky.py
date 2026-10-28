# Exclusive shop concept B, "Sky Throne": the shop sits on a big fluffy cloud. A rainbow arch spans the
# counter, a gold star crowns it, small exclusive clouds hover round it on gold rings. Front faces -Y.
import math
import random
from lib import *
from models._phoenix_ranch import *
from models._exclusive_parts import *

parts = []
R = random.Random(7)
W, CY, CD = 10.4, -1.2, 3.6

# the base cloud: a ring of big puffs round a flat top deck (deck at z ~2.2)
DZ = 2.2
parts.append(gcyl("CloudCore", 7.2, DZ, (0, 0.2, 0), CLOUD_LO, CLOUD, segs=16, r_top=7.6))
for k in range(16):
    a = k * math.tau / 16 + R.uniform(-0.1, 0.1)
    rr = R.uniform(1.6, 2.3)
    p = blob(f"Puff{k}", rr, (math.cos(a) * 7.4, 0.2 + math.sin(a) * 6.0, DZ - 0.6 + R.uniform(-0.3, 0.3)), CLOUD, subdiv=2, jitter=0, squash=(1, 1, 0.8))
    gradient(p, CLOUD_LO, CLOUD, 0, DZ + 1.2)
    parts.append(p)
for k in range(8):   # under-puffs so the cloud has a soft belly
    a = k * math.tau / 8 + 0.2
    p = blob(f"Belly{k}", R.uniform(1.6, 2.0), (math.cos(a) * 4.5, 0.2 + math.sin(a) * 3.6, 0.9), CLOUD_LO, subdiv=2, jitter=0, squash=(1, 1, 0.7))
    gradient(p, shade(CLOUD_LO, 0.9), CLOUD)
    parts.append(p)
parts.append(gcyl("Deck", 6.6, 0.35, (0, 0.2, DZ), CLOUD, WHITE, segs=16))
parts.append(gcyl("DeckGold", 6.75, 0.2, (0, 0.2, DZ + 0.3), GOLD_LO, GOLD, segs=16))

# counter: white + gold, with sky-blue panels
B = DZ + 0.5
CH = B + 3.1
parts.append(bbox("Counter", (W, CD, CH - B), (0, CY, (B + CH) / 2), shade(WHITE, 0.85), WHITE, bev=0.2))
for k in range(5):
    x = -W / 2 + W * (k + 0.5) / 5
    parts.append(bbox(f"Panel{k}", (W / 5 - 0.6, 0.3, CH - B - 0.9), (x, CY - CD / 2 - 0.1, (B + CH) / 2), rgb(90, 160, 240), rgb(150, 210, 255), bev=0.06))
    parts.append(star(f"PStar{k}", x, CY - CD / 2 - 0.3, (B + CH) / 2, 0.45, 0.15, GOLD_LO, GOLD_HI))
parts.append(bbox("CounterTop", (W + 0.6, CD + 0.6, 0.5), (0, CY, CH + 0.25), GOLD_LO, GOLD_HI, bev=0.15))

# throne-like back: tall white panel with gold rim and a sunburst
BY = 2.6
back = [(-5.6, B), (5.6, B), (5.6, B + 8.0), (4.2, B + 10.0), (2.0, B + 11.2), (0, B + 11.6), (-2.0, B + 11.2), (-4.2, B + 10.0), (-5.6, B + 8.0)]
parts.append(prism("BackGold", back, BY - 0.3, BY + 0.6, GOLD_LO, GOLD))
inset = [(x * 0.88, B + (z - B) * 0.92 + 0.3) for x, z in back]
parts.append(prism("BackFace", inset, BY - 0.45, BY - 0.3, rgb(120, 180, 250), rgb(200, 230, 255)))
for k in range(9):   # sunburst rays behind the counter
    a = math.radians(15 + k * 18.75)
    cx, cz = 0, B + 4.6
    ray = [(cx + math.cos(a - 0.09) * 1.2, cz + math.sin(a - 0.09) * 1.2), (cx + math.cos(a) * 5.0, cz + math.sin(a) * 5.0),
           (cx + math.cos(a + 0.09) * 1.2, cz + math.sin(a + 0.09) * 1.2)]
    parts.append(prism(f"Ray{k}", ray, BY - 0.6, BY - 0.5, GOLD, GOLD_HI))
parts.append(gcyl("Sun", 1.4, 0.3, (0, BY - 0.6, B + 4.6), GOLD_LO, GOLD_HI, segs=14, rot=(90, 0, 0)))

# rainbow arch over the counter: 6 bands, each a tube along a half circle
AY = 1.4
for i, col in enumerate(RAINBOW):
    rr = 8.0 - i * 0.5
    pts = [(math.cos(math.radians(a)) * rr, AY, B - 0.6 + math.sin(math.radians(a)) * rr * 0.95) for a in range(0, 181, 10)]
    t = tube(f"Bow{i}", pts, [0.27] * len(pts), col, segs=6)
    parts.append(t)
# cloud feet where the rainbow lands
for sx in (-1, 1):
    parts += puffs(f"BowFoot{sx}", sx * 6.7, AY, B - 0.7, 1.35, CLOUD_LO, WHITE, seed=11 + sx)

# sign hung under the arch top (SurfaceGui "EXCLUSIVE")
parts += sign_board("Sign", AY - 0.5, B + 8.6, 6.2, 1.4, face_lo=PURPLE_D, face=PURPLE)
# big gold star on top of the arch, with sparkles
parts.append(star("TopStar", 0, BY - 0.2, B + 12.6, 1.9, 0.7, GOLD_LO, GOLD_HI))
parts.append(gem("TopGem", 0.45, (0, BY - 0.65, B + 12.6), GEM_PINK, rot=(90, 0, 0)))
for k, (x, z, s) in enumerate(((-3.0, 11.6, 0.6), (3.2, 12.2, 0.5), (4.8, 9.6, 0.4), (-5.2, 9.8, 0.45))):
    parts.append(sparkle(f"Spark{k}", x * 1.3, AY - 0.6, B + z, s))

# hovering exclusive pet clouds on gold rings (left / right), each on a gold post
for sx, (lo, hi) in ((-1, (rgb(232, 150, 210), rgb(255, 210, 236))), (1, (rgb(150, 130, 240), rgb(214, 200, 255)))):
    x, y = sx * 7.6, -3.6
    parts.append(gcyl(f"Stick{sx}", 0.18, 3.0, (x, y, DZ + 0.4), GOLD_LO, GOLD, segs=6))
    parts += puffs(f"Pet{sx}", x, y, DZ + 3.2, 0.95, lo, hi, seed=20 + sx)
    ring = [(x + math.cos(k * math.tau / 12) * 1.8, y + math.sin(k * math.tau / 12) * 1.8, DZ + 3.6) for k in range(13)]
    parts.append(tube(f"Ring{sx}", ring, [0.12] * 13, GOLD_HI, segs=5))

# on the counter: a gold display cushion with a cloud egg
T = CH + 0.5
parts.append(bbox("Cushion", (2.0, 1.5, 0.5), (0, CY, T + 0.25), PURPLE_D, PURPLE_HI, bev=0.2))
egg = blob("Egg", 0.75, (0, CY, T + 1.4), WHITE, subdiv=2, squash=(1, 1, 1.3), jitter=0)
gradient(egg, rgb(170, 210, 255), WHITE)
parts.append(egg)
for k, (dx, col) in enumerate(((-3.3, GEM_CYAN), (-2.6, GEM_PINK), (2.8, GEM_GREEN), (3.5, PURPLE_HI))):
    parts.append(gem(f"CGem{k}", 0.4, (dx, CY - 0.3 + (k % 2) * 0.5, T + 0.4), col))

finish("exclusive_shop_b_sky", parts)
