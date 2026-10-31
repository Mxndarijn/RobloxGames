# obby_island_grove: floating goo island for the obby world backdrop (ObbyBackdrop.luau). ~42 x 42 x 40 studs native,
# scaled 0.6-1.4x per slot. Goo-green cap dripping over the rim, lilac rock belly to a point with hanging spurs,
# two goo trees, a pink mushroom pair, rocks and grass tufts. Decor only (no collision). Origin bottom centre.
from lib import *
from models._obby_backdrop import *

R, SEED = 20, 11
parts, out, topz, lobe, drip_at = island_body(R, SEED, tip_shift=(0.12, -0.08))
parts += goo_drips(R, out, drip_at, lobe, 0, GRASS_GOO, SEED, n=3)
x, y = spot(R, out, 2.2, 0.45)
parts += tree("TreeA", (x, y, topz(x, y)), 17, SEED)
x, y = spot(R, out, 3.6, 0.6)
parts += tree("TreeB", (x, y, topz(x, y)), 12, SEED + 5, canopy=BLOSSOM, canopy_hi=BLOSSOM_HI)
x, y = spot(R, out, 5.4, 0.42)
parts += mushroom("MushA", (x, y, topz(x, y)), 7.5, 4.8, GOO["pink"], SEED)
x, y = spot(R, out, 5.9, 0.7)
parts += mushroom("MushB", (x, y, topz(x, y)), 4.6, 3.0, GOO["butter"], SEED + 1)
parts += rocks("Rock", R, out, topz, SEED, n=3)
parts += tufts("Tuft", R, out, topz, SEED, n=9)
ship("obby_island_grove", parts)
