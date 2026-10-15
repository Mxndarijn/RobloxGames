# gate_bar rounds (plot kit, 2026-10-15)

| Round | Wall | Tris | What changed and why |
|---|---|---|---|
| r01 quick | 0.9 s | 176 | Stiles + top/bottom rails + 7 recessed planks + front Z brace + orange latch plate and knob on the right. |
| r02 | 2.5 s | 176 | Cycles: black squares at the top corners = stile ends coincident with the Top beam (z-fight). |
| r03 | 2.4 s | 176 | Stiles stop under the Top beam, Top 0.04 deeper: corners clean. |
| r04 | 8.1-8.4 s (6 rounds in parallel; ~2.5 s alone) | 176 | Shared palette (`models/_fence.py`): post/rail/plank darks +12-15% after the first meadow Roblox look (r02/r03 state) showed shadow sides near-black. Final: `out/gate_bar.fbx`, `gate_bar_after.png`. |
| roblox | 9.5 s (parallel) | 176 | `gate_bar_meadow_robloxlook.png`: shadow sides now read brown, not black (the avatar block darkens the same way on that side). |
