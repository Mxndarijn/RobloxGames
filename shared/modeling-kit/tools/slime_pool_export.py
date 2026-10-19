#!/usr/bin/env python3
"""Export every species of the slime pool (models/pool/slime_<id>.py) rigged, as the game wears them.

    python tools/slime_pool_export.py [--out out/pool] [--only king,lop] [--meshassets PATH]

Each species is built with SLIME_RIG=1 (bones, models/_slimerig.py) and exported to <out>/slime_<id>.fbx.
The size and bbox centre that ship() prints (SLIME_ATTACH) go to <out>/attach.json. With --meshassets
(games/steal-a-slime/src/shared/MeshAssets.luau) the `size` and `offset` of each species entry are
rewritten from those numbers; asset ids stay (upload.py --update keeps them). Nothing is uploaded.
BLENDER must point at blender.exe when it is not on PATH.
"""
import argparse, glob, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def export(model, out):
    name = os.path.splitext(os.path.basename(model))[0]
    env = dict(os.environ, SLIME_RIG="1")
    env.pop("SLIME_PREVIEW", None)
    cmd = [sys.executable, os.path.join(KIT, "iterate.py"), model, "--no-ref", "--name", name, "--out", out,
           "--views", "0", "--res", "128", "--samples", "4", "-v"]
    r = subprocess.run(cmd, cwd=KIT, env=env, capture_output=True, text=True)
    attach = None
    for line in (r.stdout + r.stderr).splitlines():
        if line.startswith("SLIME_ATTACH "):
            attach = json.loads(line[len("SLIME_ATTACH "):])
    status = (r.stdout.strip().splitlines() or ["?"])[0]
    fbx = os.path.join(out, f"{name}.fbx")
    if r.returncode or attach is None or not os.path.exists(fbx):
        print(f"{name}: FAILED\n{status}\n{r.stderr[-1500:]}")
        return name, None
    print(status)
    return name, attach


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "-0" if s == "-0" else s


def patch_meshassets(path, attach):
    src = open(path, encoding="utf-8", newline="").read()  # keep the file's own line endings
    missing = []
    for name, a in sorted(attach.items()):
        size = "{ " + ", ".join(fmt(v) for v in a["roblox_size"]) + " }"
        off = "{ " + ", ".join(fmt(v) for v in a["roblox_center_from_slime_bottom"]) + " }"
        pat = re.compile(r'(entries\["' + re.escape(name) + r'"\]\s*=\s*\{[^}]*?size\s*=\s*)\{[^}]*\}(\s*,\s*offset\s*=\s*)\{[^}]*\}',
                         re.S)
        src, n = pat.subn(lambda m: m.group(1) + size + m.group(2) + off, src, count=1)
        if n == 0:
            missing.append(name)
    open(path, "w", encoding="utf-8", newline="").write(src)
    if missing:
        print("not in MeshAssets (left alone): " + ", ".join(missing))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="out/pool")
    p.add_argument("--only", default="")
    p.add_argument("--jobs", type=int, default=4)
    p.add_argument("--meshassets", default="")
    a = p.parse_args()
    out = os.path.abspath(os.path.join(KIT, a.out))
    os.makedirs(out, exist_ok=True)
    only = {f"slime_{x}" for x in a.only.split(",") if x}
    models = [m for m in sorted(glob.glob(os.path.join(KIT, "models", "pool", "slime_*.py")))
              if not only or os.path.splitext(os.path.basename(m))[0] in only]
    with ThreadPoolExecutor(a.jobs) as ex:
        results = list(ex.map(lambda m: export(m, out), models))
    attach_path = os.path.join(out, "attach.json")
    attach = json.load(open(attach_path)) if os.path.exists(attach_path) else {}
    attach.update({n: v for n, v in results if v})
    json.dump(attach, open(attach_path, "w"), indent=1, sort_keys=True)
    failed = [n for n, v in results if not v]
    print(f"{len(results) - len(failed)} exported, {len(failed)} failed{': ' + ', '.join(failed) if failed else ''}")
    if a.meshassets:
        patch_meshassets(a.meshassets, {n: attach[n] for n, v in results if v})
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
