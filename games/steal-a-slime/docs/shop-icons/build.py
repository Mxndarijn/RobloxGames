#!/usr/bin/env python3
"""Roblox store icons for Steal a Slime: one 512x512 PNG per Game Pass and Developer Product.

    python games/steal-a-slime/docs/shop-icons/build.py            # compose out/<style>/<key>.png + review.html

Sources: src/<icon id>.png, transparent renders from the modeling kit's icon rig
(shared/modeling-kit/tools/icons, recipes in recipes_store.py and the in-game recipes). Re-render them with:

    blender -b --factory-startup --python shared/modeling-kit/tools/icons/render_icons.py -- \
        --out games/steal-a-slime/docs/shop-icons/src --only <ids from `build.py --ids`>

Every key in src/shared/ExclusiveIds.luau gets an icon. Gift_<item> products reuse <item>'s picture with one gift badge.
Styles (Merijn picks one, house rule 2): A clean cut-out, B plum stage, C gold medal. out/ is gitignored; upload.py
reads out/<style>/.
"""
import json, math, os, re, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
SRC, OUT = os.path.join(HERE, "src"), os.path.join(HERE, "out")
RES = 512
STYLES = ("A", "B", "C")
GIFT_ICON = "Gift"

# GooPalette (src/shared/GooPalette.luau)
PLUM, GOLD, GOLD_DEEP, GOLD_HI, BG, BG_DEEP, MINT = (150, 104, 206), (255, 210, 63), (224, 168, 18), (255, 244, 194), (12, 52, 54), (7, 36, 38), (108, 242, 194)

FIXED = {
    "StarterBundle": "Bundle_starter", "BoutiqueBundle": "Bundle_boutique", "SkyBundle": "Bundle_sky",
    "SlimeRain": "Event_rain", "WeatherTotem": "Consumable_WeatherTotem",
}
PREFIX = {"Seat_": "PetSeat_", "Skin_": "PlotSkin_", "Base_": "PlotBase_", "Trail_": "Store_Trail_",
          "Hat_": "Hat_", "LockStyle_": "LockStyle_", "BatSkin_": "BatSkin_"}
RETIRED = {"Fanfare_confetti": 49, "Fanfare_goo_splash": 49, "Fanfare_heart_pop": 79, "Fanfare_starburst": 79}
# Deposit fanfares left the game but their products (and Gift_ copies) still exist on Roblox, on sale: they get icons
# too. Ids from tools/monetization/created_ids.json, since ExclusiveIds no longer lists them.


def icon_for(key):
    if key in FIXED:
        return FIXED[key]
    for p, q in PREFIX.items():
        if key.startswith(p):
            return q + key[len(p):]
    return "Store_" + key


def items():
    """[{key, kind, id, name, robux, icon, gift}] for every pass and product, passes first."""
    s = open(os.path.join(GAME, "src", "shared", "ExclusiveIds.luau"), encoding="utf-8").read()
    prod_block, rest = s.split("passes = ", 1)
    pass_block = rest.split("subscriptions", 1)[0]
    sys.path.insert(0, os.path.join(GAME, "tools", "monetization"))
    cwd = os.getcwd()
    os.chdir(os.path.join(GAME, "tools", "monetization"))
    try:
        from create_products import catalogue
        from create_passes import PASSES
        names = {k: (n, r) for k, n, _, r in catalogue()}
    finally:
        os.chdir(cwd)
    pnames = {k: (n, r) for k, n, _, r in PASSES}
    out = []
    for k, i in re.findall(r"(\w+) = (\d+),", pass_block):
        out.append({"key": k, "kind": "pass", "id": int(i), "name": pnames[k][0], "robux": pnames[k][1],
                    "icon": "Store_" + k, "gift": False})
    for k, i in sorted(re.findall(r"(\w+) = (\d+),", prod_block)):
        gift = k.startswith("Gift_")
        base = k[5:] if gift else k
        n, r = names.get(k, (k, 0))
        out.append({"key": k, "kind": "product", "id": int(i), "name": n, "robux": r, "icon": icon_for(base), "gift": gift})
    created = json.load(open(os.path.join(GAME, "tools", "monetization", "created_ids.json")))
    for base, robux in sorted(RETIRED.items()):
        title = base[len("Fanfare_"):].replace("_", " ").title() + " fanfare"
        for gift in (False, True):
            k = ("Gift_" if gift else "") + base
            out.append({"key": k, "kind": "product", "id": int(created["product:" + k]), "robux": robux, "gift": gift,
                        "name": ("Gift: " if gift else "") + title, "icon": "Store_" + base, "retired": True})
    return out


def fit(im, radius):
    """Centre the subject and scale it so every visible pixel lies within `radius` of the middle."""
    a = im.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    box = a.getbbox()
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    px = a.load()
    far = 1.0
    for y in range(box[1], box[3], 2):
        for x in range(box[0], box[2], 2):
            if px[x, y]:
                far = max(far, math.hypot(x - cx, y - cy))
    k = min(radius / far, 1.15)
    sub = im.crop(box)
    sub = sub.resize((max(1, round(sub.width * k)), max(1, round(sub.height * k))), Image.LANCZOS)
    out = Image.new("RGBA", (RES, RES), (0, 0, 0, 0))
    out.alpha_composite(sub, (round(RES / 2 - sub.width / 2), round(RES / 2 - sub.height / 2)))
    return out


def radial(inner, outer, r0=0.0, r1=1.0, size=RES):
    """Radial gradient image (RGBA), inner colour in the middle, outer at the corners' circle radius."""
    g = Image.new("L", (size, size))
    px = g.load()
    c = (size - 1) / 2
    rmax = size / 2
    for y in range(size):
        for x in range(size):
            t = (math.hypot(x - c, y - c) / rmax - r0) / (r1 - r0)
            px[x, y] = int(255 * min(1, max(0, t)))
    a = Image.new("RGBA", (size, size), inner + (255,))
    b = Image.new("RGBA", (size, size), outer + (255,))
    return Image.composite(b, a, g)


def circle_mask(r, size=RES, aa=4):
    big = Image.new("L", (size * aa, size * aa), 0)
    c = size * aa / 2
    ImageDraw.Draw(big).ellipse((c - r * aa, c - r * aa, c + r * aa, c + r * aa), fill=255)
    return big.resize((size, size), Image.LANCZOS)


def soft_shadow(im, offset=(0, 10), blur=10, alpha=0.35):
    a = im.getchannel("A").filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha))
    sh = Image.new("RGBA", im.size, (20, 8, 30, 0))
    sh.putalpha(a)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(sh, offset)
    return out


_cache = {}


def backdrop(style):
    if style in _cache:
        return _cache[style]
    if style == "A":
        bg = Image.new("RGBA", (RES, RES), (0, 0, 0, 0))
    elif style == "B":  # the Exclusive shop's plum stage, full bleed (Roblox rounds or circles it itself)
        bg = radial(tuple(min(255, int(c * 1.35)) for c in PLUM), tuple(int(c * 0.55) for c in PLUM), 0.0, 1.35)
        glow = radial((255, 255, 255), PLUM, 0.0, 0.7)
        glow.putalpha(radial((90,) * 3, (0,) * 3, 0.0, 0.75).getchannel("R"))
        bg.alpha_composite(glow)
    else:  # gold medal: gold rim, deep goo-teal face, transparent corners
        bg = Image.new("RGBA", (RES, RES), (0, 0, 0, 0))
        rim = radial(GOLD_HI, GOLD_DEEP, 0.55, 1.0)
        bg.paste(rim, (0, 0), circle_mask(250))
        face = radial((40, 110, 108), BG_DEEP, 0.0, 0.95)
        bg.paste(face, (0, 0), circle_mask(222))
        ring = Image.new("RGBA", (RES, RES), MINT + (255,))
        ring.putalpha(ImageChops.subtract(circle_mask(222), circle_mask(214)).point(lambda v: int(v * 0.5)))
        bg.alpha_composite(ring)
    _cache[style] = bg
    return bg


def gift_badge(src, size):
    b = Image.open(os.path.join(src, GIFT_ICON + ".png")).convert("RGBA")
    return b.resize((size, size), Image.LANCZOS)


def compose(it, style, src=SRC):
    im = Image.open(os.path.join(src, it["icon"] + ".png")).convert("RGBA")
    radius = 200 if style == "C" else 236
    if it["gift"]:
        radius -= 14
    subject = fit(im, radius)
    out = backdrop(style).copy()
    if style != "A":
        out.alpha_composite(soft_shadow(subject))
    out.alpha_composite(subject)
    if it["gift"]:
        size = 176 if style != "C" else 160
        pos = (RES - size - 6, RES - size - 6) if style != "C" else (RES - size - 54, RES - size - 54)
        out.alpha_composite(gift_badge(src, size), pos)
    return out


def main():
    if "--ids" in sys.argv:
        print(",".join(sorted({i["icon"] for i in items()} | {GIFT_ICON})))
        return
    its = items()
    missing = sorted({i["icon"] for i in its if not os.path.exists(os.path.join(SRC, i["icon"] + ".png"))})
    if missing:
        sys.exit("missing renders in src/: " + ", ".join(missing))
    for st in STYLES:
        os.makedirs(os.path.join(OUT, st), exist_ok=True)
        for it in its:
            compose(it, st).save(os.path.join(OUT, st, it["key"] + ".png"), optimize=True)
        print(f"style {st}: {len(its)} icons -> out/{st}/")
    json.dump(its, open(os.path.join(HERE, "manifest.json"), "w", newline="\n"), indent=1)
    import review
    review.write(its, os.path.join(HERE, "review.html"))
    print("review.html written")


if __name__ == "__main__":
    main()
