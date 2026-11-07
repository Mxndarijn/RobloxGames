"""NEW badge test: python make_new_badge.py <out-dir>
Draws three NEW badge styles (A tag, B burst, C caption) on top of the finished ad images in this folder."""
import math, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "store-video"))
import render as R
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = os.path.join(HERE, "..", "store-video", "fonts", "LilitaOne-Regular.ttf")
RED = (232, 44, 60)
WHITE = (255, 255, 255)
ADS = ["night", "crowd", "egg"]


def shadowed(img, blur=10, off=(6, 12), alpha=140):
    pad = blur * 3
    out = Image.new("RGBA", (img.width + pad * 2 + off[0], img.height + pad * 2 + off[1]), (0, 0, 0, 0))
    sh = Image.new("RGBA", img.size, (0, 0, 0, alpha))
    sh.putalpha(img.getchannel("A").point(lambda v: v * alpha // 255))
    out.alpha_composite(sh, (pad + off[0], pad + off[1]))
    out = out.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(img, (pad, pad))
    return out, pad


def badge_tag():
    """A: red rounded tag, white NEW!, dark outline, tilted."""
    font = ImageFont.truetype(FONT, 120)
    text = "NEW!"
    b = font.getbbox(text, stroke_width=8)
    tw, th = b[2] - b[0], b[3] - b[1]
    w, h = tw + 90, th + 60
    img = Image.new("RGBA", (w + 20, h + 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((10, 10, 10 + w, 10 + h), radius=36, fill=R.OUTLINE + (255,))
    d.rounded_rectangle((20, 20, w, h), radius=28, fill=RED + (255,))
    d.rounded_rectangle((32, 28, w - 12, 20 + h * 0.42), radius=22, fill=(255, 110, 120, 90))
    d.text((10 + (w - tw) // 2 - b[0], 10 + (h - th) // 2 - b[1]), text, font=font, fill=WHITE,
           stroke_width=8, stroke_fill=R.OUTLINE)
    return img.rotate(8, resample=Image.BICUBIC, expand=True)


def badge_burst():
    """B: yellow starburst, red NEW! in the middle."""
    s, n = 360, 16
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2

    def star(r_out, r_in):
        pts = []
        for i in range(n * 2):
            r = r_out if i % 2 == 0 else r_in
            a = math.pi * i / n - math.pi / 2
            pts.append((c + r * math.cos(a), c + r * math.sin(a)))
        return pts
    d.polygon(star(c - 4, c * 0.78), fill=R.OUTLINE + (255,))
    d.polygon(star(c - 16, c * 0.72), fill=(247, 160, 22, 255))
    d.ellipse((c * 0.36, c * 0.36, s - c * 0.36, s - c * 0.36), fill=(255, 226, 70, 255))
    font = ImageFont.truetype(FONT, 104)
    b = font.getbbox("NEW!", stroke_width=7)
    d.text((c - (b[2] + b[0]) / 2, c - (b[3] + b[1]) / 2), "NEW!", font=font, fill=RED,
           stroke_width=7, stroke_fill=WHITE)
    return img.rotate(-12, resample=Image.BICUBIC, expand=True)


def badge_caption():
    """C: NEW! in the game's caption style (pink gradient), small, above the main caption."""
    return R.caption_image([("NEW!", R.PINK)], FONT, 150, 6)


def apply(ad, style):
    frame = Image.open(os.path.join(HERE, f"ad-{ad}.jpg")).convert("RGBA")
    if style == "A":
        img, pad = shadowed(badge_tag())
        frame.alpha_composite(img, (70 - pad, 120 - pad))
    elif style == "B":
        img, pad = shadowed(badge_burst())
        frame.alpha_composite(img, (R.W - img.width + pad - 60, 110 - pad))
    else:
        img = badge_caption()
        frame.alpha_composite(img, (R.W // 2 - img.width // 2 - 450, 745 - img.height // 2))
    return frame.convert("RGB")


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for ad in ADS:
        for style in "ABC":
            apply(ad, style).save(os.path.join(out, f"new-{style}-{ad}.jpg"), quality=92)
    print("done")
