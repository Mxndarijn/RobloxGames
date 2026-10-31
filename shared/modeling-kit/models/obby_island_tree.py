# obby_island_tree: landmark floating island for the far backdrop (ObbyBackdrop.luau): a giant blossom goo tree,
# two slime huts, a goo waterfall, crystals and mushrooms on a wide cap over a deep rock belly. ~90 x 90 x 110 studs
# native; placed a few times far out, scaled 1-1.6x.
from lib import *
from models._obby_backdrop import *

R, SEED = 42, 51
parts, out, topz, lobe, drip_at = island_body(R, SEED, depth=1.3, segs=34, drips=11, tip_shift=(0.1, 0.15), spikes=4)
parts += goo_drips(R, out, drip_at, lobe, 0, GRASS_GOO, SEED, n=5)
parts += tree("Giant", (2, 3, topz(2, 3)), 52, SEED, canopy=BLOSSOM, canopy_hi=BLOSSOM_HI)
for i, (a, f, s, roof) in enumerate([(0.9, 0.62, 14, GOO["pink"]), (2.6, 0.66, 12, GOO["cyan"])]):
    x, y = spot(R, out, a, f)
    parts += slime_house(f"Hut{i}", (x, y, topz(x, y) - 0.3), s, rgb(250, 228, 240), roof, SEED + i, yaw=a + 1.57)
parts += waterfall("Fall", R, out, 4.2, topz(*spot(R, out, 4.2, 0.95)), GOO["pink"], length=1.1)
x, y = spot(R, out, 5.3, 0.6)
parts += crystal_cluster("Crys", (x, y, topz(x, y) - 0.6), 15, GOO["cyan"], SEED, n=5)
for i, a in enumerate((3.4, 5.9)):
    x, y = spot(R, out, a, 0.7)
    parts += mushroom(f"Mush{i}", (x, y, topz(x, y)), 8, 5, GOO["butter"] if i else GOO["pink"], SEED + i)
parts += tree("TreeS", (*spot(R, out, 3.0, 0.4), topz(*spot(R, out, 3.0, 0.4))), 16, SEED + 9)
parts += rocks("Rock", R, out, topz, SEED, n=4)
parts += tufts("Tuft", R, out, topz, SEED, n=14)
ship("obby_island_tree", parts)
