#!/usr/bin/env python3
"""Render the slime pool: one hero tile per species (models/pool/slime_<id>.py), grouped by tier.

    python tools/slime_pool_sheet.py --out sheets/pool/slime_pool.png [--res 512] [--samples 96] [--only a,b]
GPU: set KIT_GPU=OPTIX (or CUDA). BLENDER must point at blender.exe when it is not on PATH.
"""
import argparse, json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIERS = {1: ("Common", (170, 220, 170)), 2: ("Uncommon", (90, 200, 255)), 3: ("Rare", (90, 130, 255)),
         4: ("Epic", (190, 100, 255)), 5: ("Legendary", (255, 190, 40)), 6: ("Mythic", (255, 80, 110)),
         7: ("Secret", (255, 255, 255))}


def font(size, bold=False):
    for f in (("arialbd.ttf" if bold else "arial.ttf"), ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf")):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def render(e, a, tmp):
    model = os.path.join(KIT, "models", "pool", f"slime_{e['id']}.py")
    if not os.path.exists(model):
        return None
    env = dict(os.environ, SLIME_PREVIEW="1")
    cmd = [sys.executable, os.path.join(KIT, "iterate.py"), model, "--no-export", "--no-ref", "--name", e["id"],
           "--out", tmp, "--views", a.view, "--res", str(a.res), "--samples", str(a.samples), "--look", a.look]
    r = subprocess.run(cmd, cwd=KIT, env=env, capture_output=True, text=True)
    if r.returncode:
        print(e["id"], "FAILED\n", r.stdout[-2000:], r.stderr[-2000:])
        return None
    line = r.stdout.strip().splitlines()[0] if r.stdout.strip() else ""
    tris = line.split(" tris")[0].split()[-1] if " tris" in line else "?"
    sheet = Image.open(os.path.join(tmp, f"{e['id']}{'_roblox' if a.look == 'roblox' else ''}_sheet.png"))
    tile = sheet.crop((4, 34, 4 + a.res, 34 + a.res))
    return tile, tris


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="sheets/pool/slime_pool.png")
    p.add_argument("--res", type=int, default=512)
    p.add_argument("--samples", type=int, default=96)
    p.add_argument("--view", default="4", help="kit view index (4 = hero)")
    p.add_argument("--look", default="default", choices=["default", "roblox"])
    p.add_argument("--cols", type=int, default=6)
    p.add_argument("--only", default="")
    p.add_argument("--tiles", default="", help="also save each tile here as <id>.png")
    p.add_argument("--roster", default="roster.json", help="models/pool/<file>: roster.json or hybrids.json")
    p.add_argument("--title", default="Steal a Slime: new slime pool")
    a = p.parse_args()
    roster = json.load(open(os.path.join(KIT, "models", "pool", a.roster), encoding="utf-8"))
    if a.only:
        keep = a.only.split(",")
        roster = [e for e in roster if e["id"] in keep]
    tmp = os.path.join(KIT, "out", "_pool_sheet")
    os.makedirs(tmp, exist_ok=True)
    with ThreadPoolExecutor(4) as ex:
        res = list(ex.map(lambda e: render(e, a, tmp), roster))
    items = [(e, r) for e, r in zip(roster, res) if r]
    if a.tiles:
        os.makedirs(a.tiles, exist_ok=True)
        for e, (t, _) in items:
            t.save(os.path.join(a.tiles, f"{e['id']}.png"))
    s, cols, lab, head = a.res, a.cols, 64, 70
    rows = []  # (tier, items, first row of the tier)
    for tier in sorted({e["tier"] for e, _ in items}):
        group = [it for it in items if it[0]["tier"] == tier]
        for i in range(0, len(group), cols):
            rows.append((tier, group[i:i + cols], i == 0))
    W = s * cols
    H = head + sum((40 if first else 0) + s + lab for _, _, first in rows)
    im = Image.new("RGB", (W, H), (28, 30, 36))
    d = ImageDraw.Draw(im)
    d.text((14, 14), a.title, fill=(245, 245, 245), font=font(34, True))
    y = head
    for tier, group, first in rows:
        tname, tcol = TIERS[tier]
        if first:
            d.text((14, y + 6), tname.upper(), fill=tcol, font=font(26, True))
            y += 40
        for i, (e, (t, tris)) in enumerate(group):
            x = i * s
            im.paste(t, (x, y))
            d.rectangle((x, y + s, x + s - 1, y + s + lab - 1), fill=(38, 40, 48))
            d.rectangle((x, y + s, x + 6, y + s + lab - 1), fill=tcol)
            d.text((x + 16, y + s + 6), e["name"], fill=(250, 250, 250), font=font(26, True))
            sub = f"{tname}  |  {tris} tris"
            if e.get("kind") == "boss":
                sub = f"BOSS  |  {tris} tris"
            elif e.get("parents"):
                sub = f"{tname}  |  " + " + ".join(e["parents"])
            d.text((x + 16, y + s + 38), sub, fill=(170, 170, 180), font=font(16))
        y += s + lab
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    im.save(a.out)
    print("pool sheet ->", a.out, f"({len(items)} slimes)")


if __name__ == "__main__":
    main()
