# fence_corner rounds (plot kit, 2026-10-15)

| Round | Wall | Tris | What changed and why |
|---|---|---|---|
| r01 quick | 1.1 s | 42 | 0.9 post + foot collar + cap slab + 4-sided pyramid; 1.1 wide so it swallows the 0.7 fence posts at a corner. |
| r02 | 2.4 s | 42 | Cycles: OK, plain but it is a post. |
| r04 | 8.1-8.4 s (6 rounds in parallel; ~2.5 s alone) | 42 | Shared palette (`models/_fence.py`): post/rail/plank darks +12-15% after the first meadow Roblox look (r02/r03 state) showed shadow sides near-black. Final: `out/fence_corner.fbx`, `fence_corner_after.png`. |
| roblox | 9.5 s (parallel) | 42 | `fence_corner_meadow_robloxlook.png`: shadow sides now read brown, not black (the avatar block darkens the same way on that side). |
