"""Ad images: python make_ads.py <stills-dir> <out-dir>
<stills-dir> holds the raw 2092x1153 hidden-Studio stills named below (README.md). Uses the store video's caption,
drip border and sparkle drawing (../store-video/render.py, Lilita One), so the ads match the game's thumbnails."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "store-video"))
import render as R
from PIL import Image

FONT = os.path.join(HERE, "..", "store-video", "fonts", "LilitaOne-Regular.ttf")
Y, M = R.YELLOW, R.MINT
# One caption on every ad, as on the game's main thumbnail (Merijn: "It should all be like Steal a Slime with
# different backgrounds"); what changes is the scene and the hero slime.
CAPTION = [[("STEAL", Y), ("A SLIME!", M)]]
# name: (sparkles (x, y, size) in the 1920x1080 frame, square crop centre x, brightness lift)
ADS = {
    "thief": ([(1200, 140, 38), (720, 250, 26), (1420, 360, 20)], 1000, 1.0),
    "divine": ([(860, 150, 38), (300, 420, 26), (1240, 300, 22)], 780, 1.0),
    "rainbow": ([(1500, 230, 40), (560, 300, 26), (1180, 120, 22)], 1000, 1.0),
    "boss": ([(860, 220, 40), (1320, 150, 26), (560, 320, 22)], 1020, 1.0),
    "night": ([(1250, 180, 40), (420, 250, 26), (980, 110, 22)], 820, 1.25),
    "obby": ([(1700, 230, 38), (640, 330, 26), (1520, 130, 22)], 1000, 1.0),
    "crowd": ([(700, 160, 36), (1420, 220, 26), (1060, 110, 20)], 960, 1.0),
    "egg": ([(1080, 330, 38), (700, 230, 24), (1260, 160, 20)], 880, 1.0),
}
SQUARES = ["thief", "divine", "night"]

def caption_layer(lines, width, frac, centre_y):
    probes = [R.caption_image(l, FONT, 150, 3) for l in lines]
    size = round(150 * min(1.7, frac * width / max(p.width for p in probes)))
    caps = [R.caption_image(l, FONT, size, 3) for l in lines]
    step = round(size * 0.92)
    y = centre_y - step * (len(caps) - 1)
    out = []
    for cap in caps:
        out.append((cap, (width // 2 - cap.width // 2, y - cap.height // 2)))
        y += step
    return out

def base(still, stars, lift=1.0):
    frame = R.load_frame(still)
    if lift != 1.0:
        from PIL import ImageEnhance
        frame = ImageEnhance.Brightness(frame.convert("RGB")).enhance(lift).convert("RGBA")
    for x, y, s in stars:
        st = R.sparkle(s)
        frame.alpha_composite(st, (x - st.width // 2, y - st.height // 2))
    return frame

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    drips = R.drip_border()
    for name, (stars, cx, lift) in ADS.items():
        lines = CAPTION
        frame = base(os.path.join(src, name + ".jpg"), stars, lift)
        wide = frame.copy()
        wide.alpha_composite(drips)
        for cap, pos in caption_layer(lines, R.W, 0.72, 905):
            wide.alpha_composite(cap, pos)
        wide.convert("RGB").save(os.path.join(dst, f"ad-{name}.jpg"), quality=92)
        if name in SQUARES:
            left = max(0, min(R.W - R.H, cx - R.H // 2))
            sq = frame.crop((left, 0, left + R.H, R.H))
            sq.alpha_composite(drips.crop((0, 0, R.H, R.H)))
            for cap, pos in caption_layer(lines, R.H, 0.86, 900):
                sq.alpha_composite(cap, pos)
            sq.convert("RGB").save(os.path.join(dst, f"ad-{name}-square.jpg"), quality=92)
    print("done")
