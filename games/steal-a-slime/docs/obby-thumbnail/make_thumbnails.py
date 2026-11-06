"""Obby thumbnails: python make_thumbnails.py <stills-dir> <out-dir>
<stills-dir> holds A.jpg B.jpg C.jpg, captured in a hidden Studio (see README.md). Uses the store video's caption,
drip border and sparkle drawing (../store-video/render.py), so the look matches the video and the thumbnails."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "store-video"))
import render as R
from PIL import Image

FONT = os.path.join(HERE, "..", "store-video", "fonts", "LilitaOne-Regular.ttf")
CAPTIONS = {
    "beat": [("BEAT", R.YELLOW), ("THE OBBY!", R.MINT)],
    "random": [("RANDOM", R.YELLOW), ("OBBY!", R.MINT)],
    "every30": [[("NEW OBBY", R.YELLOW)], [("EVERY 30 MIN!", R.MINT)]],  # two lines
}
# pick: still, caption, sparkles (x, y, size) near the jumper in the 1920x1080 frame
PICKS = {
    "A": ("A", "beat", [(680, 250, 40), (1260, 320, 30), (1010, 160, 22)]),
    "B": ("B", "every30", [(1700, 230, 40), (1040, 380, 28), (1720, 560, 22)]),
    "C": ("C", "random", [(1320, 300, 38), (720, 420, 26), (1560, 150, 22)]),
}

def compose(still, caption, stars, out):
    frame = R.load_frame(still)
    for x, y, s in stars:
        st = R.sparkle(s)
        frame.alpha_composite(st, (x - st.width // 2, y - st.height // 2))
    frame.alpha_composite(R.drip_border())
    lines = caption if isinstance(caption[0], list) else [caption]
    probes = [R.caption_image(l, FONT, 150, 3) for l in lines]
    size = round(150 * min(1.7, 0.72 * R.W / max(p.width for p in probes)))
    caps = [R.caption_image(l, FONT, size, 3) for l in lines]
    step = round(size * 0.92)
    y = 905 - step * (len(caps) - 1)
    for cap in caps:
        frame.alpha_composite(cap, (R.W // 2 - cap.width // 2, y - cap.height // 2))
        y += step
    frame.convert("RGB").save(out, quality=92)

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for pick, (still, cap, stars) in PICKS.items():
        compose(os.path.join(src, still + ".jpg"), CAPTIONS[cap], stars, os.path.join(dst, f"thumb-{pick}.jpg"))
    for cap in CAPTIONS:  # every caption on the B picture, to compare the wording
        compose(os.path.join(src, "B.jpg"), CAPTIONS[cap], PICKS["B"][2], os.path.join(dst, f"caption-{cap}.jpg"))
    print("done")
