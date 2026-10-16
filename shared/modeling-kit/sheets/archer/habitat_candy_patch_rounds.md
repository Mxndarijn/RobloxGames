# habitat_candy_patch rounds (archer, 2026-10-16)

Target 7.8 x 4.5 x 7.8 (W x H x D), biscuit seat flat at z=2.4, gumdrops + two lollipops at the rim.
All rounds `--look roblox --ground 120,196,108`; `fit()` (models/_habitat.py) snaps the bbox to the exact target and prints FIT/SEAT.

| Round | Wall | Tris | Size | nm | Change / why |
|---|---|---|---|---|---|
| r01 | 3.0 s | 2092 | 7.8 x 4.5 x 7.8 | 0 | Pink sugar-soil lathe mound (rim 2.4, dip 2.15) + scalloped biscuit (top 2.4) with docking dots + 10 lathe gumdrops + 2 lollipops (disc faces -Y) at the back rim. Gumdrops read as jars, lollipop as a pinwheel, over budget. |
| r02 | 2.8 s | 1952 | 7.8 x 4.5 x 7.8 | 0 | Squat dome gumdrops, bigger discs / shorter sticks, fewer biscuit/mound columns, 5 docking dots. Biscuit columns no longer matched the scallop count (uneven). |
| r03 | 3.0 s | 2052 | 7.8 x 4.5 x 7.8 | 0 | Biscuit segs = 2 x scallops; lollipop disc 5 face rings with a per-ring stripe offset -> reads as a swirl. 52 over budget. |
| r04 | 3.3 s | 1860 | 7.8 x 4.5 x 7.8 | 0 | Mound 16 columns, gumdrop base row dropped (sunk cone base). Gumdrops sank to half-domes. |
| r05 | 3.1 s | 1860 | 7.8 x 4.5 x 7.8 | 0 | Gumdrops +0.15. Final. SEAT: biscuit top at 2.4 (r ~2.1, 4.2 across), 0 verts above the seat within r 1.6. |

Final: `out/habitat_candy_patch.fbx`, `out/habitat_candy_patch_roblox_sheet.png`, turntable checked (`habitat_candy_patch_after_robloxlook.png`).
