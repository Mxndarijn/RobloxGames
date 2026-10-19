#!/usr/bin/env python3
"""Render the pet mounts: <name>_alone_34.png, <name>_with_pet_34.png and all_mounts_lineup.png
(the colour maps come from tools/pet_mounts_colormap.py).

    python3 tools/pet_mounts_render.py --out renders/pet_mounts [--only leaf,bubble] [--res 900]
"""
import argparse, os, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = ["storm_cloud", "rainbow_cloud", "sunset_cloud", "ice_cloud", "flame_cloud", "leaf", "bubble", "magic_carpet", "ufo", "lily_pad"]


def render(tag, name, pet, a, tmp, view="hero"):
    env = dict(os.environ, PM_NAME=name)
    if view == "side":
        env["PM_TILT"] = "0"  # level scene: the profile along the mount's length
    if pet:
        env["PM_PET"] = "1"
    cmd = [sys.executable, os.path.join(KIT, "iterate.py"), os.path.join(KIT, "models/_pet_mount_scene.py"), "--no-export", "--no-ref",
           "--name", tag, "--out", tmp, "--views", {"hero": "4", "top": "3", "side": "0"}[view], "--res", str(a.res), "--look", "roblox", "--samples", str(a.samples)]
    r = subprocess.run(cmd, cwd=KIT, env=env, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stdout + r.stderr)
    sheet = Image.open(os.path.join(tmp, f"{tag}_roblox_sheet.png")).convert("RGB")
    return sheet.crop((4, 34, 4 + a.res, 34 + a.res))  # the one tile of the sheet


def crop(im, pad=18):
    """trim to the model: drop the backdrop (corner colour), keep a margin."""
    px = im.load()
    w, h = im.size
    bgc = px[2, 2]
    xs, ys = [], []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            c = px[x, y]
            if sum(abs(c[i] - bgc[i]) for i in range(3)) > 40:
                xs.append(x); ys.append(y)
    if not xs:
        return im
    return im.crop((max(0, min(xs) - pad), max(0, min(ys) - pad), min(w, max(xs) + pad), min(h, max(ys) + pad)))


def lineup(out, names, cols=5, tile=520, suffix=""):
    """every mount with its pet side by side (the with-pet renders, centre-cropped, labelled)."""
    from PIL import ImageDraw
    rows = (len(names) + cols - 1) // cols
    im = Image.new("RGB", (cols * tile, rows * (tile + 30)), (236, 238, 244))
    d = ImageDraw.Draw(im)
    for i, n in enumerate(names):
        t = Image.open(os.path.join(out, f"{n}_with_pet_34{suffix}.png")).convert("RGB")
        w, h = t.size
        t = t.crop((int(w * 0.04), int(h * 0.04), int(w * 0.96), int(h * 0.96))).resize((tile, tile))
        x, y = (i % cols) * tile, (i // cols) * (tile + 30)
        im.paste(t, (x, y + 30))
        d.text((x + 10, y + 8), f"pet_mount_{n}", fill=(30, 30, 40))
    im.save(os.path.join(out, f"all_mounts_lineup{suffix}.png"))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--only", default="")
    p.add_argument("--res", type=int, default=900)
    p.add_argument("--samples", type=int, default=48)
    p.add_argument("--view", default="hero", choices=["hero", "top", "side"])
    p.add_argument("--suffix", default="", help="appended to every file name, e.g. _v2")
    p.add_argument("--no-crop", action="store_true")
    p.add_argument("--lineup", action="store_true", help="also compose all_mounts_lineup.png from the with-pet renders")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    names = [n for n in (a.only.split(",") if a.only else NAMES) if os.path.exists(os.path.join(KIT, f"models/pet_mount_{n}.py"))]
    tmp = tempfile.mkdtemp(prefix="pm_render_")
    if a.view == "side":
        jobs = [(f"{n}_side", n, False) for n in names]
    else:
        jobs = [(f"{n}_alone_34", n, False) for n in names] + [(f"{n}_with_pet_34", n, True) for n in names]

    def go(j):
        tag, n, pet = j
        im = render("pm_" + tag, n, pet, a, tmp, a.view)
        if not a.no_crop:
            im = crop(im)
        im.save(os.path.join(a.out, tag + a.suffix + ".png"))
        return tag
    with ThreadPoolExecutor(3) as ex:
        for t in ex.map(go, jobs):
            print("wrote", t)
    if a.lineup:
        lineup(a.out, names, suffix=a.suffix)
        print("wrote all_mounts_lineup")


if __name__ == "__main__":
    main()
