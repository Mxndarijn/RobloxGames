#!/usr/bin/env python3
"""Render the slime lineup: every body variant (tinted with its rarity colour, with its
accessory and a face) and every face expression, one front tile each, composed with labels.

    python3 tools/slime_lineup.py --out sheets/slimes_lineup.png [--look roblox] [--res 320]
"""
import argparse, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VARIANTS = [("slime_base", "Common", "default"), ("slime_leaf", "Uncommon", "happy"), ("slime_ears", "Rare", "surprised"),
            ("slime_horns", "Epic", "mischievous"), ("slime_crown", "Legendary", "happy"),
            ("slime_crystal", "Mythic", "default"), ("slime_wobble", "mutation (Glow)", "sleepy")]
FACES = ["default", "happy", "sleepy", "surprised", "mischievous"]
FACE_TINTS = [(90, 220, 120), (255, 120, 170), (120, 150, 255), (255, 170, 60), (190, 90, 255)]  # genome-like colours


def render(tag, variant, face, tint, a, tmp):
    env = dict(os.environ, SLIME_PREVIEW="1", SLIME_VARIANT=variant, SLIME_FACE=face,
               SLIME_TINT=",".join(map(str, tint)) if tint else "")
    if not tint:
        env.pop("SLIME_TINT")
    cmd = [sys.executable, os.path.join(KIT, "iterate.py"), os.path.join(KIT, "models/_slime_preview.py"), "--no-export",
           "--name", tag, "--out", tmp, "--views", a.views, "--res", str(a.res), "--look", a.look]
    if tag not in ("v0", "f0"):
        cmd.append("--no-ref")
    r = subprocess.run(cmd, cwd=KIT, env=env, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    suffix = "_roblox" if a.look == "roblox" else ""
    tile = os.path.join(tmp, f"{tag}{suffix}_tiles", "front.png")
    if not os.path.exists(tile):  # fall back to cropping the sheet
        sheet = Image.open(os.path.join(tmp, f"{tag}{suffix}_sheet.png"))
        return sheet.crop((4, 34, 4 + a.res, 34 + a.res))
    return Image.open(tile)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="sheets/slimes_lineup.png")
    p.add_argument("--look", default="default", choices=["default", "roblox"])
    p.add_argument("--res", type=int, default=320)
    p.add_argument("--views", default="0")
    a = p.parse_args()
    tmp = "/tmp/slime_lineup_" + a.look
    os.makedirs(tmp, exist_ok=True)
    jobs = [(f"v{i}", v, f, None) for i, (v, r, f) in enumerate(VARIANTS)]
    jobs += [(f"f{i}", "slime_base", f, FACE_TINTS[i]) for i, f in enumerate(FACES)]
    with ThreadPoolExecutor(4) as ex:
        tiles = list(ex.map(lambda j: render(*j, a, tmp), jobs))
    vt, ft = tiles[:len(VARIANTS)], tiles[len(VARIANTS):]
    s = a.res
    W = s * len(VARIANTS)
    H = 60 + s + 46 + 40 + s + 46
    im = Image.new("RGB", (W, H), (34, 36, 40))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 18)
        big = ImageFont.truetype("DejaVuSans-Bold.ttf", 22)
    except OSError:
        font = big = ImageFont.load_default()
    d.text((10, 8), f"Steal a Slime: new slime meshes (look: {a.look}). Bodies tinted with the rarity colour "
                    f"(MeshPart.Color x vertex colour); faces + accessories untinted.", fill=(235, 235, 235), font=font)
    d.text((10, 34), "Variants (rarity -> mesh), first tile has the 5-stud avatar block", fill=(160, 200, 255), font=font)
    for i, (t, (v, r, f)) in enumerate(zip(vt, VARIANTS)):
        im.paste(t.resize((s, s)), (i * s, 60))
        d.text((i * s + 8, 60 + s + 4), v, fill=(240, 240, 240), font=big)
        d.text((i * s + 8, 60 + s + 28), f"{r} / face {f}", fill=(190, 190, 190), font=font)
    y = 60 + s + 46 + 40
    d.text((10, y - 30), "Face expressions (separate meshes, fit every body), on slime_base with genome-like colours",
           fill=(160, 200, 255), font=font)
    for i, (t, f) in enumerate(zip(ft, FACES)):
        im.paste(t.resize((s, s)), (i * s, y))
        d.text((i * s + 8, y + s + 4), f"slime_face_{f}", fill=(240, 240, 240), font=big)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    im.save(a.out)
    print("lineup ->", a.out)


if __name__ == "__main__":
    main()
