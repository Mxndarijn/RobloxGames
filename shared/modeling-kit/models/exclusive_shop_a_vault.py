# Exclusive shop concept A, "Royal Vault": a purple + gold palace booth. Four gold columns hold a striped
# purple onion dome topped by a big crown; exclusive pet clouds float on pillars either side of a velvet counter.
# Counter top at z 4.1 like the other shops. Front faces -Y.
import math
from lib import *
from models._phoenix_ranch import *
from models._exclusive_parts import *

parts = []
W, CY, CD, CH = 10.4, -1.2, 3.6, 3.6

# raised marble-ish plinth with two gold-edged steps
parts.append(bbox("Plinth", (15.0, 11.0, 0.8), (0, 0.4, 0.4), PURPLE_D, PURPLE, bev=0.15))
parts.append(bbox("PlinthTrim", (15.3, 11.3, 0.25), (0, 0.4, 0.85), GOLD_LO, GOLD, bev=0.08))
parts.append(bbox("Step", (8.0, 1.4, 0.45), (0, -5.6, 0.22), PURPLE_D, PURPLE_HI, bev=0.1))

# counter: velvet purple front with gold panel trims
B = 0.95
parts.append(bbox("Counter", (W, CD, CH - B), (0, CY, B + (CH - B) / 2), PURPLE_D, PURPLE, bev=0.15))
for k in range(4):
    x = -W / 2 + W * (k + 0.5) / 4
    parts.append(bbox(f"Panel{k}", (W / 4 - 0.7, 0.3, CH - B - 0.9), (x, CY - CD / 2 - 0.1, B + (CH - B) / 2), GOLD_LO, GOLD, bev=0.06))
    parts.append(bbox(f"PanelIn{k}", (W / 4 - 1.2, 0.3, CH - B - 1.4), (x, CY - CD / 2 - 0.25, B + (CH - B) / 2), PURPLE_D, PURPLE_HI, bev=0.04))
    parts.append(gem(f"PanelGem{k}", 0.3, (x, CY - CD / 2 - 0.45, B + (CH - B) / 2), (GEM_PINK, GEM_CYAN)[k % 2], rot=(90, 0, 0)))
parts.append(bbox("CounterTop", (W + 0.6, CD + 0.6, 0.5), (0, CY, CH + 0.25), GOLD_LO, GOLD_HI, bev=0.15))

# back wall: deep purple with a gold arch frame
BY = 2.8
parts.append(bbox("BackWall", (W + 1.0, 0.8, 10.0), (0, BY, B + 5.0), VIOLET_DEEP, PURPLE_D, bev=0.12))
arch = [(math.cos(math.radians(a)) * 3.2, 7.4 + math.sin(math.radians(a)) * 3.2) for a in range(0, 181, 15)]
arch_pts = [(3.2, 2.2)] + arch + [(-3.2, 2.2)]
inner = [(math.cos(math.radians(a)) * 2.6, 7.4 + math.sin(math.radians(a)) * 2.6) for a in range(180, -1, -15)]
parts.append(prism("ArchGold", arch_pts + [(-2.6, 2.2)] + inner + [(2.6, 2.2)], BY - 0.55, BY - 0.35, GOLD_LO, GOLD))
parts.append(prism("ArchFill", [(2.6, 2.2)] + [(math.cos(math.radians(a)) * 2.6, 7.4 + math.sin(math.radians(a)) * 2.6) for a in range(0, 181, 15)] + [(-2.6, 2.2)],
                   BY - 0.45, BY - 0.42, PURPLE, PURPLE_HI))
# a big star inside the arch
parts.append(star("ArchStar", 0, BY - 0.7, 7.6, 1.5, 0.3, GOLD_LO, GOLD_HI))

# four gold columns: spiral fluted look = ring bands
X = W / 2 + 0.5
for sx in (-1, 1):
    for k, y in enumerate((CY - CD / 2 - 0.2, BY)):
        x = sx * X
        parts.append(gcyl(f"ColBase{sx}{k}", 0.95, 0.6, (x, y, B), GOLD_LO, GOLD, segs=8))
        parts.append(gcyl(f"Col{sx}{k}", 0.62, 9.2, (x, y, B + 0.6), shade(WHITE, 0.82), WHITE, segs=8))
        for j in range(4):
            parts.append(gcyl(f"ColRing{sx}{k}{j}", 0.72, 0.28, (x, y, B + 1.8 + j * 2.2), GOLD_LO, GOLD, segs=8))
        parts.append(gcyl(f"ColCap{sx}{k}", 0.95, 0.6, (x, y, B + 9.8), GOLD_LO, GOLD_HI, segs=8))

# roof slab + dome
RZ = B + 10.4
parts.append(bbox("Roof", (W + 3.2, 7.2, 1.0), (0, (CY - CD / 2 + BY) / 2, RZ + 0.5), PURPLE_D, PURPLE, bev=0.2))
parts.append(bbox("RoofTrim", (W + 3.5, 7.5, 0.35), (0, (CY - CD / 2 + BY) / 2, RZ + 0.1), GOLD_LO, GOLD, bev=0.1))
# gold scallop row hanging under the front edge
for k in range(9):
    x = -(W + 3.2) / 2 + (W + 3.2) * (k + 0.5) / 9
    sc = cylinder(f"Scal{k}", 0.68, 0.25, (x, CY - CD / 2 - 1.35, RZ - 0.05), GOLD, segs=10, rot=(90, 0, 0))
    gradient(sc, GOLD_LO, GOLD)
    parts.append(sc)
# onion dome: lathe profile, alternating purple / lilac gores via per-face paint
DY = (CY - CD / 2 + BY) / 2
DZ = RZ + 1.0
prof = [(3.0, 0.0), (3.3, 0.6), (3.5, 1.4), (3.4, 2.3), (3.0, 3.2), (2.3, 4.1), (1.4, 4.9), (0.6, 5.6), (0.15, 6.2)]
dome = lathe("Dome", prof, (0, DY, DZ), segs=16, col=PURPLE)
import mathutils
lay = dome.data.color_attributes["Col"]
for p in dome.data.polygons:
    c = p.center
    a = math.atan2(c.y - DY, c.x)
    gore = int(((a + math.pi) / math.tau) * 8) % 2
    t = min(1, max(0, (c.z - DZ) / 6.0))
    col = mix(VIOLET_DEEP, PURPLE, t) if gore else mix(PURPLE_HI, WHITE, t * 0.5)
    for li in p.loop_indices:
        lay.data[li].color = (*col[:3], 1.0)
parts.append(dome)
parts.append(gcyl("DomeRing", 3.15, 0.45, (0, DY, DZ), GOLD_LO, GOLD, segs=16))
parts += crown("Crown", 0, DY, DZ + 6.0, r=1.5, h=1.4)
parts.append(gem("CrownGem", 0.75, (0, DY, DZ + 8.4), GEM_PINK, h=1.6))

# corner finials on the roof: gold orbs with small gems
for sx in (-1, 1):
    for sy, y in ((-1, CY - CD / 2 - 0.6), (1, BY + 0.2)):
        parts.append(gcyl(f"Fin{sx}{sy}", 0.45, 0.8, (sx * (W / 2 + 1.2), y, RZ + 1.0), GOLD_LO, GOLD, segs=6))
        parts.append(blob(f"FinOrb{sx}{sy}", 0.55, (sx * (W / 2 + 1.2), y, RZ + 2.2), GOLD_HI, subdiv=2, jitter=0))

# sign across the roof front (SurfaceGui "EXCLUSIVE" goes on the face)
parts += sign_board("Sign", CY - CD / 2 - 1.1, RZ + 1.7, 7.0, 1.5)

# display pillars with floating exclusive clouds (pink + cyan) and spinning rings
for sx, (lo, hi), ring in ((-1, (rgb(240, 150, 200), rgb(255, 205, 232)), GEM_PINK), (1, (rgb(120, 200, 240), rgb(200, 240, 255)), GEM_CYAN)):
    x = sx * (W / 2 + 2.9)
    parts += pedestal(f"Ped{sx}", x, -3.2, B, r=0.8, h=3.0)
    parts += puffs(f"Cloud{sx}", x, -3.2, B + 3.6, 1.15, lo, hi, seed=3 + sx)
    tor = []
    for k in range(12):
        a = k * math.tau / 12
        tor.append((x + math.cos(a) * 2.1, -3.2 + math.sin(a) * 2.1, B + 4.3 + 0.35 * math.sin(a)))
    tor.append(tor[0])
    parts.append(tube(f"Halo{sx}", tor, [0.12] * len(tor), GOLD_HI, segs=5))
    parts.append(sparkle(f"Spark{sx}", x + sx * 1.3, -3.4, B + 6.1, 0.55))

# goods on the counter: treasure stack of gems + a small velvet cushion with a golden cloud token
T = CH + 0.5
parts.append(bbox("Cushion", (2.2, 1.6, 0.5), (0, CY, T + 0.25), PURPLE_D, PURPLE_HI, bev=0.2))
parts.append(gcyl("Token", 0.75, 0.25, (0, CY - 0.1, T + 1.35), GOLD_LO, GOLD_HI, segs=12, rot=(90, 0, 0)))
parts.append(blob("TokenCloud", 0.35, (0, CY - 0.3, T + 1.35), WHITE, subdiv=1, squash=(1.4, 0.4, 0.9), jitter=0))
for k, (dx, col) in enumerate(((-3.2, GEM_CYAN), (-2.5, GEM_PINK), (2.7, GEM_GREEN), (3.4, GEM_PINK), (-2.85, PURPLE_HI))):
    parts.append(gem(f"CGem{k}", 0.42, (dx, CY - 0.3 + (k % 2) * 0.5, T + 0.4 + (0.6 if k == 4 else 0)), col))

finish("exclusive_shop_a_vault", parts)
