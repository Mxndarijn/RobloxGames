# obby_island_crystal: small, deep floating islet with a big pink crystal cluster and a long rock tail. ~30 x 30 x 40
# studs native. Backdrop decor (ObbyBackdrop.luau); the small filler between the bigger islands.
from lib import *
from models._obby_backdrop import *

R, SEED = 13, 37
parts, out, topz, lobe, drip_at = island_body(R, SEED, depth=1.9, segs=22, drips=6, tip_shift=(0.2, 0.05), spikes=2)
parts += goo_drips(R, out, drip_at, lobe, 0, GOO["pink"], SEED, n=2)
parts += crystal_cluster("Crys", (0.5, 0.5, topz(0.5, 0.5) - 0.6), 14, GOO["pink"], SEED, n=5)
x, y = spot(R, out, 4.0, 0.62)
parts += crystal_cluster("CrysB", (x, y, topz(x, y) - 0.4), 6, rgb(200, 160, 255), SEED + 2, n=3)
x, y = spot(R, out, 1.6, 0.6)
parts += mushroom("Mush", (x, y, topz(x, y)), 3.4, 2.4, GOO["cyan"], SEED)
parts += tufts("Tuft", R, out, topz, SEED, n=6)
ship("obby_island_crystal", parts)
