#!/usr/bin/env python3
"""models-v2 deliverables: <name>_before_after.png per model and all_models_v2_overview.png.

    python3 tools/compose_v2.py --dest /workspace/roblox/modeling-kit/sheets/v2 --overview /tmp/ov/overview_sheet.png
"""
import argparse, os
from PIL import Image, ImageDraw, ImageFont

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = ["pad_trim", "plot_building", "rock_a", "rock_b", "rock_c", "tree_oak", "tree_pine", "tree_blossom", "volcano"]


def font(n, bold=False):
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf", n)
    except OSError:
        return ImageFont.load_default()


def before_after(name, dest):
    sh = os.path.join(KIT, "sheets")
    pairs = [("BEFORE (v17)", f"{name}_before.png"), ("AFTER (v2)", f"{name}_after.png"),
             ("AFTER, --look roblox", f"{name}_after_robloxlook.png")]
    ims = [(t, Image.open(os.path.join(sh, f)).convert("RGB")) for t, f in pairs if os.path.exists(os.path.join(sh, f))]
    W = sum(i.width for _, i in ims) + 10 * (len(ims) - 1)
    H = max(i.height for _, i in ims) + 34
    out = Image.new("RGB", (W, H), (34, 36, 40))
    d = ImageDraw.Draw(out)
    x = 0
    for t, i in ims:
        d.text((x + 8, 6), t, fill=(255, 220, 120) if "BEFORE" in t else (140, 230, 140), font=font(20, True))
        out.paste(i, (x, 34))
        x += i.width + 10
    out.save(os.path.join(dest, f"{name}_before_after.png"))


def overview(dest, ov_sheet):
    sh = os.path.join(KIT, "sheets")
    tiles = []
    for n in MODELS + ["slime_base", "slime_leaf", "slime_ears", "slime_horns", "slime_crown", "slime_crystal", "slime_wobble"]:
        s = Image.open(os.path.join(sh, f"{n}_after.png")).convert("RGB")
        tiles.append((n, s.crop((4, 34, 260, 290))))
    cols = 8
    rows = (len(tiles) + cols - 1) // cols
    ov = Image.open(ov_sheet).convert("RGB")
    t = ov.crop((4, 34, 904, 934)), ov.crop((908, 34, 1808, 934))
    W = 256 * cols
    scale = W / 1800
    ts = [i.resize((int(900 * scale), int(900 * scale))) for i in t]
    H = 50 + ts[0].height + 40 + rows * (256 + 30)
    out = Image.new("RGB", (W, H), (34, 36, 40))
    d = ImageDraw.Draw(out)
    d.text((10, 8), "Steal a Slime models v2 (modeling kit). Top: props at true scale with the 5-stud avatar block "
                    "(slime = 3 studs). Bottom: every new model, front view, avatar block in each tile.",
           fill=(235, 235, 235), font=font(18))
    out.paste(ts[0], (0, 50))
    out.paste(ts[1], (ts[0].width, 50))
    y0 = 50 + ts[0].height + 40
    for k, (n, im) in enumerate(tiles):
        x, y = (k % cols) * 256, y0 + (k // cols) * (256 + 30)
        out.paste(im, (x, y))
        d.text((x + 6, y + 258), n, fill=(240, 240, 240), font=font(16, True))
    out.save(os.path.join(dest, "all_models_v2_overview.png"))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--dest", required=True)
    p.add_argument("--overview", required=True)
    a = p.parse_args()
    os.makedirs(a.dest, exist_ok=True)
    for n in MODELS:
        before_after(n, a.dest)
    overview(a.dest, a.overview)
    print("->", a.dest)
