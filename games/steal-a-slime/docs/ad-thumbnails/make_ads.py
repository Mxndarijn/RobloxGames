"""Ad images: python make_ads.py <stills-dir> <out-dir>
<stills-dir> holds the raw 2092x1153 hidden-Studio stills named below (README.md). Uses the store video's caption,
drip border and sparkle drawing (../store-video/render.py, Lilita One), so the ads match the game's thumbnails."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "store-video"))
import render as R
from PIL import Image

FONT = os.path.join(HERE, "..", "store-video", "fonts", "LilitaOne-Regular.ttf")
Y, M, P = R.YELLOW, R.MINT, R.PINK
# name: (caption lines, sparkles (x, y, size) in the 1920x1080 frame, square crop centre x[, caption centre y])
ADS = {
    "boss": ([[("BEAT", P), ("THE BOSS!", M)]], [(860, 220, 40), (1320, 150, 26), (560, 320, 22)], 1020),
    "thief": ([[("CATCH", P), ("THE THIEF!", M)]], [(1200, 140, 38), (720, 250, 26), (1420, 360, 20)], 1000),
    "divine": ([[("FIND A", Y), ("DIVINE!", M)]], [(860, 150, 38), (300, 420, 26), (1240, 300, 22)], 780),
    "rainbow": ([[("RAINBOW", Y), ("SLIMES!", M)]], [(1500, 230, 40), (560, 300, 26), (1180, 120, 22)], 1000),
    "rich": ([[("GET", Y), ("RICH!", M)]], [(560, 420, 40), (1300, 470, 28), (700, 640, 22)], 860, 255),
    "egg": ([[("HATCH", Y), ("EGGS!", M)]], [(1080, 330, 38), (700, 230, 24), (1260, 160, 20)], 880),
    "claw": ([[("SLIME", Y), ("CLAW!", M)]], [(1300, 200, 36), (620, 260, 24), (1100, 120, 20)], 960),
}
SQUARES = ["boss", "thief", "divine"]

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

def base(still, stars):
    frame = R.load_frame(still)
    for x, y, s in stars:
        st = R.sparkle(s)
        frame.alpha_composite(st, (x - st.width // 2, y - st.height // 2))
    return frame

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    drips = R.drip_border()
    for name, spec in ADS.items():
        lines, stars, cx = spec[:3]
        cy = spec[3] if len(spec) > 3 else 905
        frame = base(os.path.join(src, name + ".jpg"), stars)
        wide = frame.copy()
        wide.alpha_composite(drips)
        for cap, pos in caption_layer(lines, R.W, 0.72 if cy > 600 else 0.55, cy):
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
