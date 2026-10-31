# obby_island_mushroom: landmark floating island (ObbyBackdrop.luau): a giant spotted goo mushroom with a little
# mushroom ring, a butter-goo waterfall and a crystal cluster, over a long two-pointed rock belly. ~80 x 80 x 110 studs
# native; placed far out, scaled 1-1.6x.
from lib import *
from models._obby_backdrop import *

R, SEED = 36, 63
parts, out, topz, lobe, drip_at = island_body(R, SEED, depth=1.6, segs=32, drips=10, tip_shift=(-0.15, 0.05), spikes=5)
parts += goo_drips(R, out, drip_at, lobe, 0, GOO["mint"], SEED, n=5)
parts += mushroom("Giant", (-3, 2, topz(-3, 2)), 34, 22, GOO["pink"], SEED)
for i in range(5):
    a = 0.5 + i * 1.15
    x, y = spot(R, out, a, 0.72)
    parts += mushroom(f"Ring{i}", (x, y, topz(x, y)), 5 + (i % 2) * 2.5, 3.2 + (i % 2) * 1.4, [GOO["cyan"], GOO["butter"]][i % 2], SEED + i)
parts += waterfall("Fall", R, out, 2.0, topz(*spot(R, out, 2.0, 0.95)), GOO["butter"], length=1.2)
x, y = spot(R, out, 4.6, 0.5)
parts += crystal_cluster("Crys", (x, y, topz(x, y) - 0.6), 13, rgb(200, 160, 255), SEED, n=4)
parts += rocks("Rock", R, out, topz, SEED, n=3)
parts += tufts("Tuft", R, out, topz, SEED, n=12)
ship("obby_island_mushroom", parts)
