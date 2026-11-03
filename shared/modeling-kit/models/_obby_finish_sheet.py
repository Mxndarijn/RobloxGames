# Host side of the obby finish preview (not an asset): renders models/_obby_finish_scene.py in Blender, applies the
# game's BaseGrade like iterate.py --look roblox, and lays the six views out as one sheet.
#   python models/_obby_finish_sheet.py models/obby_finish_a.py --sheet sheets/obby_finish_a_scene_r01.png
import argparse, json, os, subprocess, sys, time

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, KIT)
from iterate import grade  # noqa: E402

LABELS = ["approach 95 studs (runner FOV)", "approach 60 studs", "runner cam, 20 studs out", "close 3/4",
          "from behind / side", "top"]

ap = argparse.ArgumentParser()
ap.add_argument("model")
ap.add_argument("--sheet", required=True)
ap.add_argument("--res", default="640x360")
ap.add_argument("--samples", type=int, default=12)
ap.add_argument("--blender", default=os.environ.get("BLENDER", "blender"))
a = ap.parse_args()

stem = os.path.splitext(os.path.basename(a.model))[0]
tiles = os.path.join(KIT, "out", ".tiles", "finish_scene")
t0 = time.time()
cmd = [a.blender, "-b", "--factory-startup", "--python-exit-code", "1", "-P",
       os.path.join(KIT, "models", "_obby_finish_scene.py"), "--", "--model", os.path.abspath(a.model),
       "--out", tiles, "--res", a.res, "--samples", str(a.samples)]
p = subprocess.run(cmd, capture_output=True, text=True)
if p.returncode:
    print(p.stdout[-3000:], p.stderr[-3000:])
    sys.exit("scene render failed")
for line in p.stdout.splitlines():
    if line.startswith("FINISH "):
        print(line)

from PIL import Image, ImageDraw  # noqa: E402

w, h = (int(v) for v in a.res.split("x"))
st = {}
sp = os.path.join(KIT, "out", stem + ".stats.json")
if os.path.exists(sp):
    st = json.load(open(sp))
head = 30
sheet = Image.new("RGB", (w * 3, h * 2 + head), (28, 30, 34))
d = ImageDraw.Draw(sheet)
d.text((8, 9), f"{stem}  in place on the 24 x 12 finish slab (yellow), Roblox look approx.  tris {st.get('tris', '?')}"
               f"  size {st.get('size_studs', '?')}", fill=(255, 255, 255))
for i, lab in enumerate(LABELS):
    path = os.path.join(tiles, f"{stem}_scene{i}.png")
    grade(path)
    im = Image.open(path).convert("RGB")
    x, y = (i % 3) * w, head + (i // 3) * h
    sheet.paste(im, (x, y))
    d.rectangle((x, y, x + 8 + 6 * len(lab), y + 16), fill=(0, 0, 0))
    d.text((x + 4, y + 3), lab, fill=(255, 255, 255))
os.makedirs(os.path.dirname(os.path.abspath(a.sheet)), exist_ok=True)
sheet.save(a.sheet)
print(f"scene sheet {a.sheet}  wall {time.time() - t0:.1f}s")
