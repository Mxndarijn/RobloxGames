#!/usr/bin/env python3
"""Animation preview for a pool slime: skinned rig + idle breathing, blink, hop and accessory
motion, rendered to a GIF (and MP4 when ffmpeg is on PATH).

    python tools/slime_anim.py gummy [bumble ...] [--res 384] [--samples 32] [--out out/_anim]
Env: BLENDER (blender.exe path), KIT_GPU=OPTIX for the GPU.
"""
import argparse, glob, os, shutil, subprocess, sys
from PIL import Image

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("ids", nargs="+")
    p.add_argument("--res", type=int, default=384)
    p.add_argument("--samples", type=int, default=32)
    p.add_argument("--frames", type=int, default=84)
    p.add_argument("--fps", type=int, default=24)
    p.add_argument("--view", default="hero")
    p.add_argument("--out", default=os.path.join(KIT, "out", "_anim"))
    a = p.parse_args()
    blender = os.environ.get("BLENDER", "blender")
    for sid in a.ids:
        d = os.path.join(a.out, sid)
        shutil.rmtree(d, ignore_errors=True)
        cmd = [blender, "-b", "--factory-startup", "--python-exit-code", "1", "-P", os.path.join(KIT, "kit", "bl_slime_anim.py"), "--",
               "--model", os.path.join("models", "pool", f"slime_{sid}.py"), "--out", d, "--res", str(a.res),
               "--samples", str(a.samples), "--frames", str(a.frames), "--fps", str(a.fps), "--view", a.view]
        r = subprocess.run(cmd, cwd=KIT, capture_output=True, text=True)
        if r.returncode:
            sys.exit(r.stdout[-3000:] + r.stderr[-3000:])
        frames = sorted(glob.glob(os.path.join(d, "frame_*.png")))
        ims = [Image.open(f).convert("RGB") for f in frames]
        gif = os.path.join(a.out, f"{sid}_anim.gif")
        ims[0].save(gif, save_all=True, append_images=ims[1:], duration=int(1000 / a.fps), loop=0, optimize=True)
        if shutil.which("ffmpeg"):
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(a.fps), "-i", os.path.join(d, "frame_%04d.png"),
                            "-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", os.path.join(a.out, f"{sid}_anim.mp4")])
        print(sid, "->", gif)


if __name__ == "__main__":
    main()
