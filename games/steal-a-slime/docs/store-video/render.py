"""Assembles the store-page video from captured frame folders, in the thumbnails' caption style.

    python render.py <clips-dir> <out-dir> [--font LilitaOne-Regular.ttf]

<clips-dir> holds one folder of f0000.jpg... frames per shot (s1 s2 s3 s4 s6), captured at 30 fps (capture/).
Writes three cuts (README.md): captions, captions + slime-drip border and sparkles, and no captions.
Captions are drawn with Pillow straight onto each frame: two-tone vertical gradients, a thick dark outline, a dark
extrusion below, a slight tilt and a pop-in bounce. Needs Pillow and ffmpeg.
"""

import argparse
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 30

# Gradients (top colour, bottom colour), sampled from the thumbnails.
YELLOW = ((255, 236, 92), (247, 160, 22))
MINT = ((196, 255, 228), (52, 196, 150))
PINK = ((255, 170, 206), (236, 74, 136))
OUTLINE = (14, 44, 40)
EXTRUDE = (8, 26, 23)

# shot, first frame, last frame, caption parts [(text, gradient)], caption kind, sparkle spots (x, y, size) in 1080p
SHOTS = [
    ("s2", 8, 95, [("CATCH", YELLOW), ("WILD SLIMES!", MINT)], "caption", [(820, 250, 26), (1120, 320, 20)]),
    ("s1", 0, 107, [("STEAL", YELLOW), ("RARE SLIMES!", MINT)], "caption", [(1180, 300, 34), (1360, 230, 24), (1240, 470, 20)]),
    ("s3", 0, 107, [("BUILD", YELLOW), ("YOUR BASE!", MINT)], "caption", [(420, 260, 30), (1500, 200, 26), (980, 160, 20)]),
    ("s4", 0, 107, [("MERGE 3", YELLOW), ("= RARER!", MINT)], "caption", [(880, 220, 28), (1080, 300, 22)]),
    ("s6", 0, 125, [("STEAL", YELLOW), ("A SLIME!", MINT)], "title", [(620, 330, 30), (1330, 300, 26), (1450, 520, 20)]),
]

CAPTION_DELAY = 0.12  # s after the cut before a caption pops in
POP = 0.32  # s of the scale bounce
OUT = 0.12  # s of shrink before the next cut


def gradient(size, top, bottom):
    w, h = size
    col = Image.new("RGB", (1, h))
    for y in range(h):
        u = y / max(1, h - 1)
        col.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * u) for i in range(3)))
    return col.resize((w, h))


def caption_image(parts, font_path, size, tilt):
    """One caption as an RGBA image: per-word gradient fill, thick outline, dark extrusion, slight tilt."""
    font = ImageFont.truetype(font_path, size)
    stroke = max(6, round(size * 0.085))
    depth = max(6, round(size * 0.09))
    gap = round(size * 0.22)
    # measure each part
    boxes = [font.getbbox(text, stroke_width=stroke) for text, _ in parts]
    widths = [b[2] - b[0] for b in boxes]
    top = min(b[1] for b in boxes)
    bottom = max(b[3] for b in boxes)
    pad = stroke + depth + 20
    cw = sum(widths) + gap * (len(parts) - 1) + pad * 2
    ch = bottom - top + pad * 2
    fill_mask = Image.new("L", (cw, ch), 0)
    outline_mask = Image.new("L", (cw, ch), 0)
    fills = Image.new("RGB", (cw, ch), 0)
    x = pad
    for (text, grad), b, w in zip(parts, boxes, widths):
        ox, oy = x - b[0], pad - top
        m = Image.new("L", (cw, ch), 0)
        ImageDraw.Draw(m).text((ox, oy), text, font=font, fill=255)
        ImageDraw.Draw(outline_mask).text((ox, oy), text, font=font, fill=255, stroke_width=stroke, stroke_fill=255)
        glyph_top = oy + font.getbbox(text)[1]
        glyph_h = font.getbbox(text)[3] - font.getbbox(text)[1]
        g = Image.new("RGB", (cw, ch), 0)
        g.paste(gradient((w, glyph_h), grad[0], grad[1]), (x, glyph_top))
        fills.paste(g, (0, 0), m)
        fill_mask.paste(255, (0, 0), m)
        x += w + gap
    out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    # soft drop shadow, then the extrusion (the outline shape stepped down), then outline, then fill
    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (0, 0), outline_mask.filter(ImageFilter.GaussianBlur(size * 0.06)))
    out.alpha_composite(shadow, (round(depth * 0.4), round(depth * 1.4)))
    for d in range(depth, 0, -1):
        layer = Image.new("RGBA", (cw, ch), EXTRUDE + (255,))
        layer.putalpha(outline_mask)
        out.alpha_composite(layer, (round(d * 0.25), d))
    layer = Image.new("RGBA", (cw, ch), OUTLINE + (255,))
    layer.putalpha(outline_mask)
    out.alpha_composite(layer)
    fill = fills.convert("RGBA")
    fill.putalpha(fill_mask)
    out.alpha_composite(fill)
    # a thin light rim on the upper edge of the letters (the thumbnails' glossy top)
    rim = fill_mask.filter(ImageFilter.MaxFilter(3))
    shifted = Image.new("L", (cw, ch), 0)
    shifted.paste(fill_mask, (0, 3))
    rim_only = Image.composite(Image.new("L", (cw, ch), 0), rim, shifted)
    hl = Image.new("RGBA", (cw, ch), (255, 255, 255, 110))
    hl.putalpha(rim_only.point(lambda v: v * 110 // 255))
    out.alpha_composite(hl)
    return out.rotate(tilt, resample=Image.BICUBIC, expand=True)


def pop_scale(t, dur):
    """Scale of a caption t seconds into its shot: 0 -> overshoot -> 1, and a quick shrink before the cut."""
    u = t - CAPTION_DELAY
    if u < 0:
        return 0.0
    if u < POP:
        p = u / POP
        # easeOutBack
        c1 = 1.9
        c3 = c1 + 1
        return 1 + c3 * (p - 1) ** 3 + c1 * (p - 1) ** 2
    left = dur - t
    if left < OUT:
        return max(0.0, left / OUT) ** 0.7
    return 1.0


def drip_border(seed=7):
    """Mint slime drips hanging from the top edge, like the thumbnails: a wavy band and round-ended drips."""
    rng = random.Random(seed)
    k = 2  # drawn at 2x for smooth edges
    hh = 190
    mask = Image.new("L", (W * k, hh * k), 0)
    d = ImageDraw.Draw(mask)
    band = 30
    pts = [(0, 0)]
    for x in range(0, W * k + 40, 40):
        y = (band + 6 * math.sin(x / (k * 140.0)) + 4 * math.sin(x / (k * 47.0) + 1.3)) * k
        pts.append((x, y))
    pts.append((W * k, 0))
    d.polygon(pts, fill=255)
    x = rng.randint(10, 40) * k
    while x < W * k:
        w = rng.randint(24, 34) * k
        length = rng.choice([34, 56, 80, 104, 128, 46, 70]) * k
        top = band * k - 8 * k
        d.rectangle((x, top, x + w, top + length), fill=255)
        r = w * 0.62
        cx, cy = x + w / 2, top + length
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
        x += w + rng.randint(46, 120) * k
    mask = mask.resize((W, hh), Image.LANCZOS)
    outline = mask.filter(ImageFilter.MaxFilter(11))
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dark = Image.new("RGBA", (W, hh), OUTLINE + (255,))
    dark.putalpha(outline)
    fill = gradient((W, hh), (196, 255, 232), (66, 206, 160)).convert("RGBA")
    fill.putalpha(mask)
    img.alpha_composite(dark, (0, 0))
    img.alpha_composite(fill, (0, 0))
    shine = mask.point(lambda v: v * 70 // 255)
    hl = Image.new("RGBA", (W, hh), (255, 255, 255, 255))
    hl.putalpha(Image.composite(shine, Image.new("L", (W, hh), 0), gradient((W, hh), (255, 255, 255), (0, 0, 0)).convert("L").point(lambda v: 255 if v > 205 else 0)))
    img.alpha_composite(hl, (0, 0))
    return img


def sparkle(size):
    """A white four-point star with a soft glow."""
    s = size * 4
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    c = s / 2
    r, k = s * 0.48, s * 0.09
    pts = [(c, c - r), (c + k, c - k), (c + r, c), (c + k, c + k), (c, c + r), (c - k, c + k), (c - r, c), (c - k, c - k)]
    d.polygon(pts, fill=255)
    glow = m.filter(ImageFilter.GaussianBlur(s * 0.06))
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    g = Image.new("RGBA", (s, s), (255, 255, 255, 255))
    g.putalpha(glow.point(lambda v: v * 120 // 255))
    out.alpha_composite(g)
    st = Image.new("RGBA", (s, s), (255, 255, 255, 255))
    st.putalpha(m)
    out.alpha_composite(st)
    return out


def load_frame(path):
    im = Image.open(path).convert("RGB")
    scale = max(W / im.width, H / im.height)
    nw, nh = math.ceil(im.width * scale), math.ceil(im.height * scale)
    im = im.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - W) // 2, (nh - H) // 2
    im = im.crop((left, top, left + W, top + H))
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))  # undo the capture's JPEG softness
    return im.convert("RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("clips")
    ap.add_argument("out")
    ap.add_argument("--font", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts", "LilitaOne-Regular.ttf"))
    ap.add_argument("--only", default="", help="comma list of variants: caption,deco,clean")
    ap.add_argument("--sample", default="", help="write only these output frame numbers as PNGs (comma list)")
    a = ap.parse_args()
    variants = [v for v in (a.only.split(",") if a.only else ["caption", "deco", "clean"])]
    sample = {int(x) for x in a.sample.split(",") if x}
    os.makedirs(a.out, exist_ok=True)

    caps = {}
    for name, _, _, parts, kind, _ in SHOTS:
        base, tilt = (150, 3) if kind == "title" else (118, 2.5)
        probe = caption_image(parts, a.font, base, tilt)
        target = 0.74 if kind == "title" else 0.70  # share of the frame width, as on the thumbnails
        size = round(base * min(1.6, target * W / probe.width))
        caps[name] = caption_image(parts, a.font, size, tilt)
    border = drip_border()
    star_cache = {}

    names = {
        "caption": "steal-a-slime-store-video-draft.mp4",
        "deco": "steal-a-slime-store-video-draft-deco.mp4",
        "clean": "steal-a-slime-store-video-draft-nocaptions.mp4",
    }
    for variant in variants:
        tmp = tempfile.mkdtemp()
        n = 0
        for name, first, last, parts, kind, stars in SHOTS:
            dur = (last - first + 1) / FPS
            cap = caps[name]
            for k in range(first, last + 1):
                if sample and n not in sample:
                    n += 1
                    continue
                t = (k - first) / FPS
                frame = load_frame(os.path.join(a.clips, name, "f%04d.jpg" % k))
                if variant == "deco":
                    for i, (sx, sy, ss) in enumerate(stars):
                        tw = 0.55 + 0.45 * math.sin(t * 5.5 + i * 2.1)
                        size = max(4, round(ss * tw))
                        if size not in star_cache:
                            star_cache[size] = sparkle(size)
                        st = star_cache[size]
                        frame.alpha_composite(st, (sx - st.width // 2, sy - st.height // 2))
                    frame.alpha_composite(border)
                if variant != "clean":
                    sc = pop_scale(t, dur)
                    if sc > 0.01:
                        cw, ch = max(1, round(cap.width * sc)), max(1, round(cap.height * sc))
                        im = cap.resize((cw, ch), Image.BICUBIC)
                        cy = 520 if kind == "title" else 915
                        frame.alpha_composite(im, (W // 2 - cw // 2, cy - ch // 2))
                rgb = frame.convert("RGB")
                if sample:
                    rgb.save(os.path.join(a.out, "sample-%s-%04d.png" % (variant, n)))
                else:
                    rgb.save(os.path.join(tmp, "f%04d.png" % n), compress_level=1)
                n += 1
        if not sample:
            dst = os.path.join(a.out, names[variant])
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%04d.png"),
                            "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                            dst], check=True)
            print("wrote", dst, n, "frames")
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
