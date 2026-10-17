#!/usr/bin/env python3
"""Assert on rhr's layout + hit map of the HUD models rhr_hud.luau wrote.

Usage: rhr_check.py OUT_DIR [RHR_BIN]

One `rhr batch` call lays out and hit-tests every case in OUT_DIR/manifest.json
at its viewport (58 px top bar). Per button (the nav tiles with their labels, the status
icons, Slap) it asserts, on rhr's rects in screen px:
  on-screen    inside the viewport and below the top bar
  unoccluded   rhr's click at the button's centre lands on the button, and no
               other click-capturing node rhr draws above it (zOrder)
               overlaps any part of it
  not squashed rendered w/h within ASPECT_TOLERANCE of the design w/h
  touch size   min(w, h) >= 44 px (Layout.MIN_TOUCH)
Per box (the money cluster, an open status tooltip) it asserts it is on screen below the top bar.
Exit 1 on any failure, 2 when rhr itself fails. KNOWN lists findings the
gate tolerates; each must still occur, so fixing one forces its removal.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

EPS = 0.51  # rhr rects are within ~0.5 px of the rounded UDim offsets
ASPECT_TOLERANCE = 0.03
MIN_TOUCH = 44

# Findings the gate tolerates (none now: the portrait nav no longer runs into the tutorial card).
KNOWN: list[str] = []


def main() -> int:
    out = Path(sys.argv[1])
    rhr = sys.argv[2] if len(sys.argv) > 2 else "rhr"
    manifest = json.loads((out / "manifest.json").read_text())
    top = manifest["topbar"]

    args = [rhr, "batch"]
    for i, case in enumerate(manifest["cases"]):
        vp = f"{case['viewport'][0]}x{case['viewport'][1]}"
        if i:
            args.append("+")
        args += ["layout", case["file"], "--viewport", vp, "+", "hitmap", case["file"], "--viewport", vp]
    proc = subprocess.run(args, capture_output=True, text=True)
    try:
        batch = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(f"  rhr batch failed (exit {proc.returncode}):\n{proc.stderr[-2000:]}")
        return 2
    results = batch["results"]
    if len(results) != 2 * len(manifest["cases"]):
        print(f"  rhr batch returned {len(results)} results for {len(manifest['cases'])} cases")
        return 2

    problems = []
    checked = 0
    for i, case in enumerate(manifest["cases"]):
        layout, hitmap = results[2 * i], results[2 * i + 1]
        for r in (layout, hitmap):
            if r.get("exitCode") != 0 or not isinstance(r.get("stdout"), dict):
                print(f"  rhr failed on {case['name']}: {str(r.get('stderr'))[-800:]}")
                return 2
        rects = layout["stdout"]["rects"]
        tests = hitmap["stdout"].get("hitTests", [])
        nodes = {n["path"]: n for n in hitmap["stdout"].get("nodes", [])}
        vw, vh = case["viewport"]
        for b in case["buttons"]:
            path, (dw, dh) = b["path"], b["design"]
            checked += 1
            r = rects.get(path)
            tag = f"[{case['name']}] {path.removeprefix('SlimeUI/Root/')}"
            if r is None:
                problems.append(f"{tag}: rhr drew no such element")
                continue
            box = f"{{x={r['x']:.1f} y={r['y']:.1f} w={r['w']:.1f} h={r['h']:.1f}}}"
            if r["x"] < -EPS or r["y"] < top - EPS or r["x"] + r["w"] > vw + EPS or r["y"] + r["h"] > vh + EPS:
                problems.append(f"{tag} {box} is off the {vw}x{vh} screen (top bar {top})")
            if r["h"] <= 0 or abs((r["w"] / r["h"]) / (dw / dh) - 1) > ASPECT_TOLERANCE:
                problems.append(f"{tag} {box} is squashed vs design {dw}x{dh}")
            if min(r["w"], r["h"]) + EPS < MIN_TOUCH:
                problems.append(f"{tag} {box} is under {MIN_TOUCH} px")
            cx, cy = r["x"] + r["w"] / 2, r["y"] + r["h"] / 2
            hit = min(
                (t for t in tests if abs(t["point"]["x"] - cx) <= r["w"] / 2 and abs(t["point"]["y"] - cy) <= r["h"] / 2),
                key=lambda t: abs(t["point"]["x"] - cx) + abs(t["point"]["y"] - cy),
                default=None,
            )
            if hit is None:
                problems.append(f"{tag} {box}: no hit test inside it (hidden or zero size)")
            elif hit.get("target") != path:
                problems.append(f"{tag} {box} is covered: a click at its centre goes to {hit.get('target')}")
            me = nodes.get(path)
            for other in nodes.values():
                o = other["rect"]
                if (
                    me is None
                    or other["path"] == path
                    or other["path"].startswith(path + "/")
                    or path.startswith(other["path"] + "/")
                    or not (other.get("capturesClicks") and other.get("visible"))
                    or other.get("zOrder", 0) <= me.get("zOrder", 0)
                ):
                    continue
                ix = min(r["x"] + r["w"], o["x"] + o["w"]) - max(r["x"], o["x"])
                iy = min(r["y"] + r["h"], o["y"] + o["h"]) - max(r["y"], o["y"])
                if ix > EPS and iy > EPS:
                    problems.append(f"{tag} {box} is covered by {other['path']}")

    for case in manifest["cases"]:
        layout = results[2 * manifest["cases"].index(case)]["stdout"]["rects"]
        vw, vh = case["viewport"]
        for box in case.get("boxes", []):
            checked += 1
            r = layout.get(f"SlimeUI/Root/{box['path']}")
            tag = f"[{case['name']}] {box['path']}"
            if r is None:
                problems.append(f"{tag}: rhr drew no such element")
            elif r["x"] < -EPS or r["y"] < top - EPS or r["x"] + r["w"] > vw + EPS or r["y"] + r["h"] > vh + EPS:
                problems.append(f"{tag} is off the {vw}x{vh} screen (top bar {top})")

    known = [p for p in problems if any(re.match(k, p) for k in KNOWN)]
    new = [p for p in problems if p not in known]
    for p in new:
        print(f"  {p}")
    for p in known:
        print(f"  known: {p}")
    stale = [k for k in KNOWN if not any(re.match(k, p) for p in known)]
    for k in stale:
        print(f"  KNOWN entry no longer occurs (fixed? remove it from rhr_check.py): {k}")
    print(
        f"  rhr: {len(manifest['cases'])} cases, {checked} button checks, "
        f"{len(new)} problems, {len(known)} known"
    )
    return 1 if new or stale else 0


if __name__ == "__main__":
    sys.exit(main())
