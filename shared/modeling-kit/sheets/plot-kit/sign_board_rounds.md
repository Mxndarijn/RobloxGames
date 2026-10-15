# sign_board rounds (plot kit, 2026-10-15)

| Round | Wall | Tris | What changed and why |
|---|---|---|---|
| r01 quick | 1.0 s | 144 | Two capped posts, 6 x 3.5 board = one flat light face + frame, diagonal braces under the board. The braces read as splayed legs. |
| r02 | 2.4 s | 132 | Braces removed, drip-cap board on top instead. Black dots at the frame corners (coincident H/V frame ends). |
| r03 | 2.6 s | 132 | Vertical frame pieces now sit between the horizontal ones: clean. |
| r04 | 8.1-8.4 s (6 rounds in parallel; ~2.5 s alone) | 132 | Shared palette (`models/_fence.py`): post/rail/plank darks +12-15% after the first meadow Roblox look (r02/r03 state) showed shadow sides near-black. Final: `out/sign_board.fbx`, `sign_board_after.png`. |
| roblox | 9.5 s (parallel) | 132 | `sign_board_meadow_robloxlook.png`: shadow sides now read brown, not black (the avatar block darkens the same way on that side). |
