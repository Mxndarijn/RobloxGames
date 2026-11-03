# obby_finish_a (option A): a big goo FINISH ARCH over the front of the finish slab (steal-a-slime obby).
# Two lumpy goo pillars stand just outside the 24-stud lane, a goo roll spans their tops with a big checkered banner
# hanging under it (bottom edge 13 studs up), goo drips off the roll's ends, a happy slime sits on top in the middle,
# and a checkered finish line lies flat across the lane under the arch. Slab coordinates (models/_obby_finish_parts).
import math
from mathutils import Vector
from lib import *
from models._obby_finish_parts import *

ARCH_Y = -3.6  # the arch's plane: just in from the slab's front edge (y = -6)
PX = 14.2  # pillar centre x: the pillar's inner face stays outside the lane (|x| >= 12)
TOP = 19.6  # the roll's centre height
parts = []

# -- pillars: lumpy goo lathes from below the slab edge up into the roll, a fat goo foot spilling onto the slab corner
for s in (-1, 1):
    prof = [(0.0, -2.0), (2.3, -2.0)]
    for k in range(9):
        t = k / 8
        z = -1.4 + t * (TOP + 1.4)
        prof.append((1.75 + 0.7 * (1 - t) ** 2 + 0.18 * math.sin(k * 1.9 + s), z))
    prof.append((0.0, TOP + 0.5))
    n = len(prof) - 1
    cols = [mix(GOO_DEEP, GOO, min(1.0, 0.25 + k / n)) for k in range(n)]
    p = lathe(f"Pillar{s}", prof, cols, segs=14, pos=(s * PX, ARCH_Y, 0),
              wobble=lambda i, a, s=s: 1.0 + 0.07 * math.sin(3 * a + i * 1.3 + s))
    parts.append(smooth(p))

# -- feet, the top roll and drips as one metaball goo skin
balls = []
for s in (-1, 1):
    balls.append(Ball((s * (PX - 0.2), ARCH_Y, -0.4), (2.6, 2.4, 1.0)))
    balls.append(Ball((s * (PX - 1.9), ARCH_Y - 0.6, 0.05), (1.4, 1.3, 0.34)))  # spills onto the slab edge
    balls.append(Ball((s * (PX + 0.6), ARCH_Y + 0.9, -0.6), (1.5, 1.4, 0.8)))
for k in range(17):
    t = k / 16
    x = (t - 0.5) * 2 * (PX + 0.4)
    bump = 0.25 * math.sin(k * 2.3)
    balls.append(Ball((x, ARCH_Y, TOP + bump), (1.6, 1.45, 1.35)))
# drips: off the roll's ends (outside the banner) and two short ones in front of the banner's top corners
for x, ln, wd in ((-PX - 1.0, 3.2, 0.55), (-PX + 1.4, 1.6, 0.42), (PX + 1.1, 2.6, 0.5), (PX - 1.5, 2.0, 0.45),
                  (-7.3, 0.9, 0.38), (4.8, 1.2, 0.4), (9.6, 0.7, 0.34)):
    balls += drip_balls((x, ARCH_Y - 0.9, TOP - 0.9), ln, wd)
goo = metaball_mesh("ArchGoo", balls, resolution=0.34, tris=2200)
parts.append(paint_goo(goo, goo_color(z0=-1.5, z1=TOP + 1.0)))

# -- the checkered banner under the roll: 12 x 2 squares of 2 studs, bottom edge at z 13.2, gold trim top and bottom
BW, BH = 24.0, 4.8
BZ = 13.2 + BH / 2
parts.append(checker("Banner", BW, BH, 10, 2, thick=0.36, sub=3, pos=(0, ARCH_Y, BZ),
                     wave=lambda u, v: 0.25 * math.sin(u * math.pi * 3)))
parts.append(bb("TrimLo", (BW + 0.6, 0.6, 0.45), (0, ARCH_Y, 13.2), GOLD_LO, GOLD, bev=0.12))

# -- a happy slime sitting on top of the roll, in the middle (the game's mascot: reads from far away)
n0 = len(parts)
sl = [Ball((0, ARCH_Y, TOP + 2.2), (2.5, 2.1, 1.9)), Ball((0, ARCH_Y, TOP + 1.2), (2.9, 2.4, 1.0))]
slime = metaball_mesh("TopSlime", sl, resolution=0.22, tris=500)
parts.append(paint_goo(slime, goo_color(GOLD_LO, GOLD, GOLD_HI, z0=TOP + 0.5, z1=TOP + 4.0)))  # a gold winner slime
parts += eyes("Eye", (0, ARCH_Y - 1.85, TOP + 2.55), (0, -1, 0), 0.95, r=0.68, pupil=0.4)
parts.append(tube("Smile", [(-0.7, ARCH_Y - 2.22, TOP + 1.75), (-0.35, ARCH_Y - 2.36, TOP + 1.5),
                            (0, ARCH_Y - 2.4, TOP + 1.42), (0.35, ARCH_Y - 2.36, TOP + 1.5),
                            (0.7, ARCH_Y - 2.22, TOP + 1.75)], [0.12, 0.15, 0.16, 0.15, 0.12], INK, segs=6))
# a crown on the slime: the winner
crown = [(-1.1, 0), (1.1, 0), (1.25, 1.1), (0.62, 0.55), (0, 1.35), (-0.62, 0.55), (-1.25, 1.1)]
parts.append(slab("Crown", crown, 0.5, VIOLET, pos=(0, ARCH_Y - 0.3, TOP + 3.85), back=VIOLET_LO))
for k, x in enumerate((-1.25, 0.0, 1.25)):
    parts.append(ball(f"Gem{k}", 0.26, (x, ARCH_Y - 0.55, TOP + 3.85 + (1.35 if x == 0 else 1.1)), CYAN, CYAN_HI, subdiv=1))
# scale the slime and its crown up about its seat on the roll so it reads from down the course
from mathutils import Matrix
seat = Vector((0, ARCH_Y, TOP + 0.6))
M = Matrix.Translation(seat) @ Matrix.Scale(1.4, 4) @ Matrix.Translation(-seat)
for o in parts[n0:]:
    o.data.transform(M)

# -- the finish line: a flat checkered strip across the lane under the arch (decor, 0.08 thick, on the slab top)
parts.append(checker("Line", 24.0, 2.4, 16, 2, thick=0.08, pos=(0, ARCH_Y, 0.06), rot=(90, 0, 0)))

report("obby_finish_a", parts)
finish_smooth("obby_finish_a", parts)
