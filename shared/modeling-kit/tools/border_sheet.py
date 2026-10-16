#!/usr/bin/env python3
"""Combined sheet for the world-border chunks: the eight ranch_border_chunk_a..h roblox-look sheets
+ a top-down plan of the seeded placement (out/border_pieces.json, dumped from steal-a-slime
WorldBorder.pieces() with lune + @lune/serde). Mirrored ("_m") slots are drawn with a white tick
on their +X end. (The earlier five-piece set sheet, sheets/gojo/ranch_border_set.png, came from
the previous version of this tool.)

    python3 tools/border_sheet.py   ->  sheets/gojo/ranch_border_chunks_set.png
"""
import json, math, os
from PIL import Image, ImageDraw

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = [f"ranch_border_chunk_{c}" for c in "abcdefgh"]
COLOURS = {"HedgeFence": (60, 120, 60), "HillRocks": (156, 216, 124), "FenceMound": (196, 138, 86),
           "PineGrove": (30, 90, 60), "HedgeHill": (110, 170, 80), "Outcrop": (200, 182, 150),
           "SteppedFence": (150, 104, 68), "CornerGrove": (20, 70, 50), "Accent": (214, 92, 84)}
WALL_RADIUS = 292


def plan(data, size):
    img = Image.new("RGB", (size, size), (34, 36, 40))
    dr = ImageDraw.Draw(img)
    s = (size - 40) / 660

    def P(x, z):
        return (size / 2 + x * s, size / 2 + 20 - z * s)

    dr.rectangle([P(-320, 320), P(320, -320)], fill=(120, 196, 108))
    for p in sorted(data["pieces"], key=lambda p: p["row"] == "front"):
        sx, _, sz = p["size"]
        a = math.radians(p["yaw"])
        c, sn = math.cos(a), math.sin(a)
        pts = []
        for lx, lz in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2)):
            pts.append(P(p["pos"][0] + c * lx + sn * lz, p["pos"][2] - sn * lx + c * lz))
        dr.polygon(pts, fill=COLOURS[p["kind"]], outline=(20, 20, 20))
        if p.get("mirrored"):
            dr.line([pts[1], pts[2]], fill=(255, 255, 255), width=2)
    r = WALL_RADIUS
    dr.ellipse([P(-r, r), P(r, -r)], outline=(255, 255, 255))
    dr.text((6, 4), f"top-down plan, {len(data['pieces'])} slots; white = wall ring r{r}", fill=(240, 240, 240))
    y = 18
    for k, col in COLOURS.items():
        dr.rectangle([6, y, 16, y + 10], fill=col)
        dr.text((20, y - 1), k, fill=(240, 240, 240))
        y += 14
    return img


def main():
    tiles = [Image.open(os.path.join(KIT, "out", f"{n}_roblox_sheet.png")).convert("RGB") for n in NAMES]
    w, h = tiles[0].size
    data = json.load(open(os.path.join(KIT, "out", "border_pieces.json")))
    tiles.append(plan(data, h).resize((w, h)))
    sheet = Image.new("RGB", (w * 3, h * 3), (34, 36, 40))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 3) * w, (i // 3) * h))
    out = os.path.join(KIT, "sheets", "gojo", "ranch_border_chunks_set.png")
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main()
