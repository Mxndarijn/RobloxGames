# wall_low rounds (plot kit, 2026-10-15)

| Round | Wall | Tris | What changed and why |
|---|---|---|---|
| r01 quick | 0.9 s | 192 | Two staggered courses of chipped warm-stone blocks (vertex jitter, 12 tris each), wooden sill + top rail, short capped end posts. 2.7 tall. |
| r02 | 2.5 s | 192 | Cycles: stone reads warm against the wood, not blue. No change. |
| r04 | 8.1-8.4 s (6 rounds in parallel; ~2.5 s alone) | 192 | Shared palette (`models/_fence.py`): post/rail/plank darks +12-15% after the first meadow Roblox look (r02/r03 state) showed shadow sides near-black. Final: `out/wall_low.fbx`, `wall_low_after.png`. |
| roblox | 9.5 s (parallel) | 192 | `wall_low_meadow_robloxlook.png`: shadow sides now read brown, not black (the avatar block darkens the same way on that side). |
