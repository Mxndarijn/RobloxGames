# obby_island_village: floating goo island with a slime hut, a goo waterfall pouring off the rim, a crystal cluster and
# mushrooms. ~46 x 46 x 50 studs native (the waterfall hangs below the cap). Backdrop decor (ObbyBackdrop.luau).
from lib import *
from models._obby_backdrop import *

R, SEED = 21, 23
parts, out, topz, lobe, drip_at = island_body(R, SEED, depth=1.25, tip_shift=(-0.1, 0.1), spikes=2)
parts += goo_drips(R, out, drip_at, lobe, 0, GRASS_GOO, SEED, n=2)
x, y = spot(R, out, 1.3, 0.3)
parts += slime_house("Hut", (x, y, topz(x, y) - 0.3), 15, rgb(250, 214, 236), GOO["pink"], SEED, yaw=0.6)
parts += waterfall("Fall", R, out, 4.4, topz(*spot(R, out, 4.4, 0.95)), GOO["cyan"], length=1.25)
x, y = spot(R, out, 3.0, 0.62)
parts += crystal_cluster("Crys", (x, y, topz(x, y) - 0.5), 9, GOO["cyan"], SEED)
x, y = spot(R, out, 5.6, 0.55)
parts += mushroom("MushA", (x, y, topz(x, y)), 5.5, 3.4, GOO["butter"], SEED)
x, y = spot(R, out, 0.2, 0.72)
parts += tree("Tree", (x, y, topz(x, y)), 11, SEED + 3)
parts += rocks("Rock", R, out, topz, SEED, n=2)
parts += tufts("Tuft", R, out, topz, SEED, n=8)
ship("obby_island_village", parts)
