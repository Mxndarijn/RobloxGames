# modeling-kit

Headless Blender 4.5 loop for low-poly Roblox props. No GPU, no paid services. Bot rules: `CLAUDE.md`. Lessons: `LESSONS.md`. The process around it: `/workspace/guides/roblox-modeling-process.md`.

```sh
python3 iterate.py models/tree_oak.py --sheet sheets/tree_oak_r01.png   # one round, ~2.5 s
python3 iterate.py models/tree_oak.py --quick                            # clay shape check, ~1.2 s, no FBX
python3 iterate.py models/tree_oak.py --quick --watch                    # re-run on every save
python3 iterate.py models/tree_oak.py --look roblox --no-export          # approx. in-game look, ~3.1 s
python3 iterate.py models/tree_oak.py --quick --turntable                # + 8-angle strip PNG + GIF
python3 iterate.py old.fbx --no-export                                   # render an existing FBX/OBJ/GLB
python3 compare.py out/tree_oak_sheet.png concept.png --tile front       # vs a concept image
python3 upload.py out/tree_oak.fbx [--update ASSET_ID] [--size-check]    # dry run; --go to really send
```

## iterate.py outputs (default `--out out/`)
- `<name>_sheet.png`: 2×2 contact sheet (front, side, back-3/4, top-3/4) with a header (PASS/FAIL) and a footer (tris, size, warnings). The grey block is a 5-stud avatar for scale.
- `<name>.stats.json`: tris, per-mesh stats, `size_studs` as Roblox [X, Y(up), Z], non-manifold edges, materials, pass/fails/warnings, timings.
- `<name>.fbx` + `.obj`: only when the checks pass (and not `--no-export`).
- Exit code 0 = pass, 2 = budget fail, 1 = script/Blender error (the traceback is printed).

- `--quick`: `<name>_quick_sheet.png` + `<name>_quick.stats.json` (Workbench clay, cavity, outline; never exports).
- `--look roblox`: `<name>_roblox_sheet.png` + `<name>_roblox.stats.json` (see CLAUDE.md for what it models and what it doesn't).
- `--turntable [N]`: `<stem>_turntable.png` (strip, front first) and `<stem>_turntable.gif` (N=8 by default, fixed distance).
- `--watch`: runs once, then again whenever the model file or `lib/*.py` changes (polls every 0.2 s; Ctrl-C stops; `--watch-rounds N` stops after N re-runs).

Flags: `--engine cycles|workbench|eevee`, `--res 256`, `--samples 16`, `--views 0,1,2,3`, `--no-ref`, `--bench N`, `-v`.

## Scale convention
**1 Blender unit = 1 stud**, the same as v17 `make_meshes.py`, with the same FBX export settings (`FBX_SCALE_UNITS`, -Z forward, Y up). Verified in Roblox: v17 `pad_trim` was modelled 9.4 BU wide and `uploaded.json` records `meshSize` 9.4. (Roblox's physics docs use 1 stud = 0.28 m; `lib.studs(m)` converts when a reference is in metres, but don't model in metres.)

## Timings (2026-10-15, 8-core CPU, Blender 4.5.14, tree_oak 1404 tris)
Second measurement, after adding the modes (`--bench`, wall per round):
| Mode | Wall per round |
|---|---|
| `--quick` (Workbench clay, 256 px, no FBX) | **1.29 / 1.10 / 1.16 / 1.10 / 1.19 s, mean 1.17 s** (Blender start ~0.9 s, 4 renders ~0.5 s; the first render pays the GL init) |
| `--quick --watch`, save → new sheet | 1.1–1.5 s (plus up to 0.2 s polling) |
| `--quick --turntable` (4 views + 8 angles + GIF) | 1.86 / 1.72 / 1.79 s, mean 1.79 s |
| default Cycles (`--no-export`) | 2.55 / 2.28 / 2.71 s, mean 2.51 s |
| `--look roblox` (Cycles) | 3.22 / 2.96 / 3.16 s, mean 3.11 s |
| `--look roblox --turntable` | 8.5–8.6 s (8 extra Cycles renders ~4.8 s) |

First measurement (before the modes):
| Setting | Wall per round | Notes |
|---|---|---|
| Cycles CPU, 256 px tiles, 16 spp + OIDN (default) | **2.45 / 2.53 / 2.83 s, mean 2.60 s** (`--bench 3`) | Blender start ~0.9 s, model 0.1 s, 4 renders ~1.8 s (0.4–0.5 each), FBX+OBJ <0.1 s, compose <0.1 s |
| Cycles, 8 spp | 2.1 s | slightly noisier; not worth it |
| Cycles, 512 px, 24 spp | 9.3 s | final detail check |
| Workbench (`--engine workbench`) | 2.2 s | software GL; first render 1.3 s (GL init); vertex colours look darker; shapes only |
| EEVEE (`--engine eevee`) | ~31 s per render | software GL shader compile; avoid without a GPU |

The 5–15 s target is met with about 2× margin, so no profiling was needed. Speed comes from: one Blender process per round, one camera moved through 4 views, persistent data on (BVH reused), no adaptive sampling, 3 bounces, OIDN, `--factory-startup`.
