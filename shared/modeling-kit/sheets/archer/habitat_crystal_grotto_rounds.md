# habitat_crystal_grotto rounds (archer, 2026-10-16)

Target 7.8 x 5.0 x 7.8 (W x H x D), seat flat at z=2.4, crystals on the rim only (seat column clear to 5.0).
All rounds `--look roblox --ground 120,196,108`; `fit()` (models/_habitat.py) snaps the bbox to the exact target and prints FIT/SEAT.

| Round | Wall | Tris | Size | nm | Change / why |
|---|---|---|---|---|---|
| r01 | 2.9 s | 812 | 7.8 x 5 x 7.8 | 0 | Lathe rock bowl (rim ~3.0, floor groove 2.3) + 16-gon stone seat slab (top 2.4, r 2.0) + 6 rim boulders + 6 hex-crystal clusters. Read as a smooth orange tub; crystals small. |
| r02 | 2.8 s | 848 | 7.8 x 5 x 7.8 | 0 | Sloped flank with more rows, per-vertex wobble (r > 2.4 only, floor/seat untouched), per-face stone shade, sandstone lows/highs less orange, crystals taller + chunkier, boulders bigger. Reads as rock. |
| r03 | 2.8 s | 914 | 7.8 x 5 x 7.8 | 0 | Crystal girth +15 %, 4th small shard on the three lilac clusters, aqua lightened (r02 went teal-grey). Final. SEAT: 16 flat faces at 2.4, r 2.03, 0 verts above the seat within r 1.6. |

Final: `out/habitat_crystal_grotto.fbx`, `out/habitat_crystal_grotto_roblox_sheet.png`, turntable checked (`habitat_crystal_grotto_after_robloxlook.png`).
