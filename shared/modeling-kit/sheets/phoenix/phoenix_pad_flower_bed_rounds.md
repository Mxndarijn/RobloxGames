# phoenix_pad_flower_bed rounds (2026-10-16, phoenix)
Slot spec (existing pads): footprint 7.8-7.96, tops 1.0 (hay) / 1.85 (goo) / 2.6 (crate) / 3.0 (stool). Target: ~7.8 wide, flat top 2.4.

| round | wall | tris | size W x H x D | change / why |
|---|---|---|---|---|
| r01 | 3.6 s | 1524 | 7.98 x 2.64 x 7.98 | octagon plank planter (8 boards + corner posts), soil, lathe stump (bark, ring-banded plaza top r 2.3 at z 2.4), 10 leaf+bloom+eye clusters. Reads as a flower bed; posts push the bbox to 7.98, blooms poke over the stump top. |
| r02 | 2.8 s | 1524 | 7.65 x 2.54 x 7.61 | apothem -0.1, bigger blooms. Posts sank into the boards (lost the corner rhythm), eyes still over 2.4. |
| r03 | 2.5 s | 1524 | 7.70 x 2.40 x 7.70 | apothem 3.75 + posts at r 3.72 (proud again), blooms lowered: top exactly 2.4. |
| r04 | 3.2 s | 1524 | 7.70 x 2.40 x 7.70 | first `--look roblox --ground 120,196,108`: stump bark and planter boards the same orange, low contrast. |
| r05 | 3.0 s | 1268 | 7.79 x 2.40 x 7.79 | darker bark gradient (wood_dark -> 45 % wood) vs the planter; post bevels dropped (-256 tris, unseen). Final. |

Final: `out/phoenix_pad_flower_bed.fbx`, `phoenix_pad_flower_bed_after_robloxlook.png` (+ turntable in out/). Lineup with slimes: `phoenix_pads_lineup.png`.
