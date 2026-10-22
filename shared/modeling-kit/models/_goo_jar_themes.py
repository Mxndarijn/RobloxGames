# Goo jar tower themes (not an asset): the palette and the few shape touches each theme gives the tower's kit pieces.
# models/_goo_jar.py reads JAR_THEME (default "classic") and builds every piece in that theme's colours, so all themes
# share one set of builders and one set of game sizes (the game fits each mesh to the same slot box). The ids are the
# game's plot skin ids (Config.PLOT_SKINS, saved in plotSkin): never rename one.
#
# Kept the same in every theme: the lock button's red and the door ring (gameplay signals), the per-plot colour on the
# slime stands' dish, and the eyes. Values follow THEME.md: value >= ~115 on big surfaces, no near-white big surfaces,
# no cold blue-greys, nothing more saturated than the slimes.
from lib import *

P = PALETTE

THEMES = {
    # The tower as built: warm wood and cork, green goo, brass.
    "classic": {
        "name": "Classic Ranch",
        "wood": P["ranch_wood"], "wood_d": P["ranch_wood_dark"], "cream": P["ranch_cream"],
        "goo": P["ranch_goo"], "goo_hi": P["ranch_goo_hi"], "metal": P["ranch_metal"],
        "pink": P["ranch_pink"], "lilac": P["ranch_lilac"], "butter": P["ranch_butter"], "path": P["ranch_path"],
        "glass": rgb(200, 240, 244), "cork": rgb(214, 170, 116), "sand": rgb(232, 214, 178),
        "ground": "120,196,108",
    },
    # Themes come in two kinds: one per slime family (Meadow = classic, Garden, Frost & Sea, Starlight), unlocked by
    # collecting that family's slimes, and two collections across families (Candy, Forest), unlocked by collecting
    # their sweet or woodland slimes. The unlock lists live in the game (Config), not here.
    #
    # Candy (skin id candy): bubblegum goo in a biscuit-and-chocolate jar, mint-and-cream striped ribs (not red: red is the
    # lock's colour), lollipops and gumdrops round the foot, a cherry on the mascot.
    "candy": {
        "name": "Candy",
        "wood": rgb(178, 116, 88), "wood_d": rgb(146, 92, 74), "cream": rgb(252, 240, 236),
        "goo": rgb(246, 146, 192), "goo_hi": rgb(255, 208, 228), "metal": rgb(132, 220, 190),
        "pink": rgb(250, 150, 182), "lilac": rgb(196, 166, 232), "butter": rgb(252, 216, 110), "path": rgb(232, 176, 196),
        "glass": rgb(252, 226, 240), "cork": rgb(238, 194, 136), "sand": rgb(240, 190, 206),
        "stripe": rgb(252, 240, 236), "ground": "236,170,196",
    },
    # Frost & Sea family (skin id crystal, kept so saved skins carry over): icy aqua goo, frosted lilac lids, periwinkle
    # ribs, birch wood, icicles hanging from every lid, ice crystals round the foot, a knitted hat on the mascot.
    "crystal": {
        "name": "Frost & Sea",
        "wood": rgb(214, 192, 176), "wood_d": rgb(172, 150, 146), "cream": rgb(240, 246, 252),
        "goo": rgb(124, 210, 236), "goo_hi": rgb(214, 244, 252), "metal": rgb(150, 164, 226),
        "pink": rgb(236, 160, 200), "lilac": rgb(186, 176, 240), "butter": rgb(250, 226, 150), "path": rgb(178, 204, 232),
        "glass": rgb(214, 240, 255), "cork": rgb(198, 202, 242), "sand": rgb(198, 222, 242),
        "icicles": True, "ground": "206,228,244",
    },
    # Forest (skin id mushroom): glowing spore goo (lilac), mushroom-cap lids, green vines with leaves instead of
    # brass ribs, mossy floor, toadstools round the foot, a toadstool cap on the mascot.
    "mushroom": {
        "name": "Forest",
        "wood": rgb(176, 128, 92), "wood_d": rgb(146, 104, 76), "cream": rgb(246, 236, 214),
        "goo": rgb(184, 150, 236), "goo_hi": rgb(228, 210, 252), "metal": rgb(112, 178, 96),
        "pink": rgb(250, 150, 182), "lilac": rgb(196, 166, 232), "butter": rgb(252, 216, 110), "path": rgb(150, 178, 110),
        "glass": rgb(214, 244, 214), "cork": rgb(206, 150, 110), "sand": rgb(134, 182, 100),
        "leaves": rgb(150, 210, 112), "ground": "120,196,108",
    },
    # Garden family (Sprout, Cheddar, Prickles, Flan): peach juice goo, trimmed hedge lids, a cream garden trellis for
    # ribs dotted with flowers, terracotta door and pots, sunflowers and potted fruit bushes round the foot, a straw sun hat on the mascot.
    "garden": {
        "name": "Garden",
        "wood": P["ranch_wood"], "wood_d": P["ranch_wood_dark"], "cream": P["ranch_cream"],
        "goo": rgb(252, 176, 118), "goo_hi": rgb(255, 222, 190), "metal": rgb(246, 236, 214),
        "pink": rgb(250, 150, 182), "lilac": rgb(196, 166, 232), "butter": rgb(252, 216, 110), "path": rgb(214, 188, 138),
        "glass": rgb(240, 246, 222), "cork": rgb(132, 190, 100), "sand": rgb(222, 198, 150),
        "buds": [rgb(250, 150, 182), rgb(252, 216, 110), rgb(196, 166, 232)], "pot": rgb(222, 140, 102), "ground": "120,196,108",
    },
    # Starlight family (Imp, Drako, Robo, Seraph, Amethyst, Prism, Eclipse, Boo): glowing gold starlight goo, twilight
    # lilac lids and wood (kept light: no near-black night), gold ribs with sparkles, star wands and glow orbs round
    # the foot, a wizard hat on the mascot.
    "starlight": {
        "name": "Starlight",
        "wood": rgb(152, 138, 200), "wood_d": rgb(126, 114, 176), "cream": rgb(246, 242, 255),
        "goo": rgb(250, 212, 118), "goo_hi": rgb(255, 240, 192), "metal": rgb(236, 196, 104),
        "pink": rgb(246, 160, 210), "lilac": rgb(196, 176, 244), "butter": rgb(252, 222, 120), "path": rgb(150, 140, 206),
        "glass": rgb(228, 224, 255), "cork": rgb(136, 128, 208), "sand": rgb(170, 158, 216),
        "buds": [rgb(255, 246, 214), rgb(196, 224, 255)], "ground": "120,196,108",
    },
}
