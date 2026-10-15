# fence_straight rounds (plot kit, 2026-10-15)

| Round | Wall | Tris | What changed and why |
|---|---|---|---|
| r01 quick | 1.4 s | 212 | 2 posts on the joints (x=+-3.5, shared with the neighbour), 2 back rails, 8 dog-ear pickets with +-0.1 height alternation and tiny lean. Silhouette reads as a picket fence; 3.6 tall vs 5-stud avatar. |
| r02 | 2.4 s | 212 | First Cycles round: wood colours read, value contrast caps/posts/pickets OK. No change needed. |
| r04 | 8.1-8.4 s (6 rounds in parallel; ~2.5 s alone) | 212 | Shared palette (`models/_fence.py`): post/rail/plank darks +12-15% after the first meadow Roblox look (r02/r03 state) showed shadow sides near-black. Final: `out/fence_straight.fbx`, `fence_straight_after.png`. |
| roblox | 9.5 s (parallel) | 212 | `fence_straight_meadow_robloxlook.png`: shadow sides now read brown, not black (the avatar block darkens the same way on that side). |
