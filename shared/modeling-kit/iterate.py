#!/usr/bin/env python3
"""One modeling round: build a model in headless Blender, render a 4-view contact
sheet, check Roblox budgets, export FBX if it passes.

    python3 iterate.py models/tree_oak.py                  # -> out/tree_oak_sheet.png, .stats.json, .fbx
    python3 iterate.py models/tree_oak.py --sheet sheets/tree_oak_r03.png
    python3 iterate.py meshes/old.fbx --no-export          # render an existing FBX/OBJ/GLB
    python3 iterate.py models/x.py --engine workbench      # fallback renderer (slower here, no GPU)
    python3 iterate.py models/x.py --bench 3               # time 3 rounds
    python3 iterate.py models/x.py --quick                 # ~1.3 s clay shape sheet (Workbench, no FBX)
    python3 iterate.py models/x.py --quick --watch         # re-run whenever the model or lib/ changes
    python3 iterate.py models/x.py --look roblox           # Cycles, approximates the game's in-game look
    python3 iterate.py models/x.py --turntable             # + 8-angle strip PNG and GIF

A model script is plain bpy run inside Blender with the kit root on sys.path
(`from lib import *`). It starts from an empty scene and must leave its mesh
object(s) in the scene; use lib.finish() to make one shipping mesh.
"""
import argparse, json, os, shutil, subprocess, sys, time

KIT = os.path.dirname(os.path.abspath(__file__))
RUNNER = os.path.join(KIT, "kit", "bl_iterate.py")
LABELS = ["front", "side", "back-3/4", "top-3/4"]
# steal-a-slime Lighting.BaseGrade (ColorCorrectionEffect), applied to --look roblox tiles.
GRADE = {"brightness": 0.02, "contrast": 0.12, "saturation": 0.15, "tint": (1.0, 0.9686, 0.9216)}


def grade(path):
    """Approximate Roblox ColorCorrection on an sRGB tile (Roblox's exact formula isn't public)."""
    import numpy as np
    from PIL import Image

    c = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255
    c = c + GRADE["brightness"]
    c = (c - 0.5) * (1 + GRADE["contrast"]) + 0.5
    lum = (c * np.array([0.299, 0.587, 0.114], dtype=np.float32)).sum(-1, keepdims=True)
    c = lum + (c - lum) * (1 + GRADE["saturation"])
    c = c * np.array(GRADE["tint"], dtype=np.float32)
    Image.fromarray((np.clip(c, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)


def turntable(stats, out_dir, stem, res):
    """N angles -> one strip PNG (front first) and a looping GIF."""
    from PIL import Image, ImageDraw

    n = min(res, 192)
    tiles = [Image.open(t["path"]).convert("RGB").resize((n, n), Image.LANCZOS) for t in stats["turntable"]]
    strip = Image.new("RGB", (n * len(tiles), n), (34, 36, 40))
    for k, (im, t) in enumerate(zip(tiles, stats["turntable"])):
        strip.paste(im, (k * n, 0))
        d = ImageDraw.Draw(strip)
        d.rectangle((k * n, 0, k * n + 8 + 7 * len(t["view"]), 16), fill=(0, 0, 0))
        d.text((k * n + 4, 3), t["view"], fill=(255, 255, 255))
    png = os.path.join(out_dir, stem + "_turntable.png")
    gif = os.path.join(out_dir, stem + "_turntable.gif")
    strip.save(png, compress_level=1)
    tiles[0].save(gif, save_all=True, append_images=tiles[1:], duration=250, loop=0)
    return png, gif


def compose(stats, sheet_path, res):
    from PIL import Image, ImageDraw, ImageFont

    head, foot, pad = 30, 40, 4
    W = 2 * res + 3 * pad
    H = head + 2 * res + 3 * pad + foot
    img = Image.new("RGB", (W, H), (34, 36, 40))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.load_default(size=15)
        small = ImageFont.load_default(size=12)
    except TypeError:  # Pillow < 10.1
        font = small = ImageFont.load_default()
    ok = stats["pass"]
    mode = "  QUICK: clay shape only, no FBX" if stats["mode"] == "quick" else ""
    if stats["look"] == "roblox":
        mode = "  look: roblox (approx. in-game)"
    d.text((pad + 2, 7), stats["name"] + mode, fill=(240, 240, 240), font=font)
    badge = "PASS" if ok else "FAIL"
    d.text((W - 60, 7), badge, fill=(110, 220, 120) if ok else (255, 90, 90), font=font)
    for k, t in enumerate(stats["tiles"]):
        x = pad + (k % 2) * (res + pad)
        y = head + pad + (k // 2) * (res + pad)
        img.paste(Image.open(t["path"]).convert("RGB").resize((res, res)), (x, y))
        d.rectangle((x, y, x + 8 + 7 * len(t["view"]), y + 18), fill=(0, 0, 0))
        d.text((x + 4, y + 2), t["view"], fill=(255, 255, 255), font=small)
    sx, sy, sz = stats["size_studs"]
    line1 = f"{stats['tris']} tris  {sx:g} x {sy:g} x {sz:g} studs (W x H x D)  meshes {stats['mesh_count']}  non-manifold {stats['non_manifold_edges']}"
    probs = stats["fails"] + stats["warnings"]
    line2 = ("; ".join(probs) if probs else "no warnings") + "  | grey block = 5-stud avatar"
    yb = H - foot + 4
    d.text((pad + 2, yb), line1, fill=(220, 220, 220), font=small)
    d.text((pad + 2, yb + 17), line2[:110], fill=(255, 200, 120) if probs else (160, 200, 160), font=small)
    os.makedirs(os.path.dirname(os.path.abspath(sheet_path)), exist_ok=True)
    img.save(sheet_path, optimize=False, compress_level=1)


class RoundError(Exception):
    pass


def run_once(a):
    name = a.name or os.path.splitext(os.path.basename(a.model))[0]
    tag = "quick" if a.quick else ("roblox" if a.look == "roblox" else "")
    stem = name + (f"_{tag}" if tag else "")  # modes never overwrite the default round's files
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    stats_path = os.path.join(out, stem + ".stats.json")
    if os.path.exists(stats_path):
        os.remove(stats_path)
    cmd = [a.blender, "-b", "--factory-startup", "--python-exit-code", "1", "-P", RUNNER, "--",
           "--model", os.path.abspath(a.model), "--out", out, "--name", name,
           "--engine", a.engine, "--res", str(a.res), "--samples", str(a.samples), "--views", a.views,
           "--look", a.look, "--tag", tag, "--turntable", str(a.turntable)]
    if a.quick:
        cmd.append("--quick")
    if a.no_export:
        cmd.append("--no-export")
    if a.no_ref:
        cmd.append("--no-ref")
    if a.ground:
        cmd += ["--ground", a.ground]
    t0 = time.time()
    p = subprocess.run(cmd, capture_output=True, text=True)
    t_blender = time.time() - t0
    if p.returncode != 0 or not os.path.exists(stats_path):
        sys.stderr.write(p.stdout[-4000:] + p.stderr[-4000:])
        raise RoundError(f"iterate: blender failed (exit {p.returncode}); model script error above")
    if a.verbose:
        sys.stderr.write(p.stdout)
    stats = json.load(open(stats_path))
    sheet = os.path.join(out, stem + "_sheet.png")
    t = time.time()
    if a.look == "roblox" and not a.quick:
        for tl in stats["tiles"] + stats["turntable"]:
            grade(tl["path"])
    if stats["tiles"]:
        compose(stats, sheet, a.res)
        if a.sheet:
            os.makedirs(os.path.dirname(os.path.abspath(a.sheet)), exist_ok=True)
            shutil.copyfile(sheet, a.sheet)
    if stats["turntable"]:
        stats["turntable_png"], stats["turntable_gif"] = turntable(stats, out, stem, a.res)
    t_compose = time.time() - t
    wall = time.time() - t0
    stats["sheet"] = sheet if stats["tiles"] else None
    stats["timings"] = {"wall_s": round(wall, 2), "blender_process_s": round(t_blender, 2), "compose_s": round(t_compose, 3),
                        **stats["timings_blender"]}
    with open(stats_path, "w") as f:
        json.dump(stats, f, indent=2)
    tb = stats["timings_blender"]
    rs = tb.get("render_s", [])
    sx, sy, sz = stats["size_studs"]
    fb = f"fbx {stats['fbx_bytes'] // 1024}KB" if stats["fbx"] else (
        "no fbx (--quick)" if a.quick else "no fbx (--no-export)" if a.no_export else "NO FBX")
    print(f"{name}: {'PASS' if stats['pass'] else 'FAIL'} {stats['tris']} tris  {sx:g}x{sy:g}x{sz:g} studs  nm={stats['non_manifold_edges']}"
          f"  meshes={stats['mesh_count']}  {fb}  warn={len(stats['warnings'])}"
          f"  | wall {wall:.1f}s (blender {t_blender:.1f}: model {tb['model_s']:.2f} render {sum(rs):.1f}={'+'.join(f'{x:.1f}' for x in rs)})"
          f"  -> {os.path.relpath(a.sheet or sheet)}")
    if stats["turntable"]:
        tt = tb.get("turntable_s", [])
        print(f"  turntable {len(tt)} views {sum(tt):.1f}s -> {os.path.relpath(stats['turntable_png'])},"
              f" {os.path.relpath(stats['turntable_gif'])}")
    for m in stats["fails"]:
        print("  FAIL:", m)
    for m in stats["warnings"]:
        print("  warn:", m)
    return stats


def watched_files(model):
    files = [os.path.abspath(model)]
    if model.endswith(".py"):  # model scripts import lib/
        lib = os.path.join(KIT, "lib")
        files += [os.path.join(lib, f) for f in sorted(os.listdir(lib)) if f.endswith(".py")]
    return files


def snapshot(files):
    return {f: os.stat(f).st_mtime_ns for f in files if os.path.exists(f)}


def watch(a, poll=0.2):
    """Run once, then again after every save; prints save -> result latency."""
    files = watched_files(a.model)
    seen, reruns = snapshot(files), 0
    print(f"watch: {os.path.relpath(a.model)} + {len(files) - 1} lib files; Ctrl-C to stop", flush=True)
    changed_at = time.time()
    try:
        while True:
            try:
                run_once(a)
            except RoundError as e:  # keep watching: the next save may fix it
                print(e)
            print(f"watch: result {time.time() - changed_at:.1f}s after the change; waiting", flush=True)
            if a.watch_rounds and reruns >= a.watch_rounds:
                return 0
            while snapshot(files) == seen:
                time.sleep(poll)
            changed_at = time.time()
            time.sleep(0.05)  # let the editor finish writing
            seen = snapshot(files)
            reruns += 1
    except KeyboardInterrupt:
        return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", help="models/<name>.py (bpy script) or an .fbx/.obj/.glb to render")
    ap.add_argument("--out", default=os.path.join(KIT, "out"), help="output dir (default: kit/out)")
    ap.add_argument("--name", help="asset name (default: model file stem)")
    ap.add_argument("--sheet", help="also copy the contact sheet here (e.g. sheets/x_r01.png)")
    ap.add_argument("--engine", default="cycles", choices=["cycles", "workbench", "eevee"],
                    help="cycles (default, fastest on CPU); workbench/eevee are fallbacks (software GL: slower here)")
    ap.add_argument("--res", type=int, default=256, help="pixels per tile (default 256)")
    ap.add_argument("--samples", type=int, default=16, help="render samples (default 16, OIDN denoised)")
    ap.add_argument("--views", default="0,1,2,3", help="view indices to render (0 front,1 side,2 back-3/4,3 top-3/4)")
    ap.add_argument("--no-export", action="store_true", help="never write FBX/OBJ")
    ap.add_argument("--no-ref", action="store_true", help="hide the 5-stud avatar block")
    ap.add_argument("--quick", action="store_true",
                    help="shape-only clay sheet: Workbench + cavity + outline, no FBX, ~1.3 s")
    ap.add_argument("--watch", action="store_true", help="re-run when the model file or lib/*.py changes (Ctrl-C stops)")
    ap.add_argument("--watch-rounds", type=int, default=0, help="with --watch: stop after N re-runs (for bots/tests)")
    ap.add_argument("--look", default="default", choices=["default", "roblox"],
                    help="roblox: approximate the game's in-game look (Cycles; CLAUDE.md lists what still differs)")
    ap.add_argument("--turntable", type=int, nargs="?", const=8, default=0,
                    help="also render N angles (default 8) -> <name>_turntable.png strip + .gif")
    ap.add_argument("--ground", default="", metavar="R,G,B",
                    help="ground plane colour, sRGB 0-255 (e.g. 98,160,70 meadow); default dark grey")
    ap.add_argument("--bench", type=int, default=0, help="run N rounds and print wall-time stats")
    ap.add_argument("--blender", default=os.environ.get("BLENDER", "blender"))
    ap.add_argument("-v", "--verbose", action="store_true", help="show Blender output")
    a = ap.parse_args()
    if a.quick and a.look == "roblox":
        ap.error("--quick is shape-only clay; use --look roblox without --quick")
    if a.ground:
        try:
            g = [int(v) for v in a.ground.split(",")]
            assert len(g) == 3 and all(0 <= v <= 255 for v in g)
        except (ValueError, AssertionError):
            ap.error("--ground wants R,G,B with each 0-255, e.g. 98,160,70")
        a.ground = ",".join(map(str, g))
    if a.watch:
        sys.exit(watch(a))
    if not a.bench:
        try:
            st = run_once(a)
        except RoundError as e:
            sys.exit(str(e))
        sys.exit(0 if st["pass"] else 2)
    walls = [run_once(a)["timings"]["wall_s"] for _ in range(a.bench)]
    print(f"bench {a.bench} rounds: " + ", ".join(f"{w:.2f}s" for w in walls) + f"  mean {sum(walls) / len(walls):.2f}s")


if __name__ == "__main__":
    main()
