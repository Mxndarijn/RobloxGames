# gate_frame rounds (plot kit, 2026-10-15)

| Round | Wall | Tris | What changed and why |
|---|---|---|---|
| r01 quick | 1.1 s | 308 | Posts 1.0 at +-4.5 (clear 8.0), tie beam underside 9.0 (the brief's 4.5 total height would block the 5-stud avatar and the carried slime), lintel + roof cap, knee braces above 7.4, fence stubs to x=+-7 so the piece is 2 segments. Looked spindly, roof cap too flat. |
| r02 | 2.6 s | 308 | Posts 1.2 (centres +-4.6, outer 10.4, clear still 8.0), bigger feet, roof cap 2.3 deep x 1.1 tall. Terracotta roof matches the cottage roof; reads as the entrance from every view. |
| r04 | 8.1-8.4 s (6 rounds in parallel; ~2.5 s alone) | 308 | Shared palette (`models/_fence.py`): post/rail/plank darks +12-15% after the first meadow Roblox look (r02/r03 state) showed shadow sides near-black. (Superseded by r05.) |
| roblox | 9.5 s (parallel) | 308 | `gate_frame_meadow_robloxlook.png`: shadow sides now read brown, not black (the avatar block darkens the same way on that side). |
| r05 | 2.3 s | 308 | Clearance check on the exported OBJ: the post feet stuck 0.18 into the opening (clear 7.65 at the ground). Feet now grow outward only, so the opening is 8.0 from the ground up to 7.2; above that only the knee-brace tips reach in (clear 7.87). Final: `out/gate_frame.fbx`, `gate_frame_after.png`; Roblox look re-run (2.6 s). |
