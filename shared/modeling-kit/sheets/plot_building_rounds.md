# plot_building rounds (2026-10-15)
Before: v17 plot_building, 244 tris, 27.0 x 17.18 x 14.57 studs (box house, flat roof slabs).
Kept the game's anchor points (Detail.luau): front wall y=-5.5, clear wall for the sign at z 8.3, windows at x=+-7.5 with sills at 4.0 for the flower boxes, door at x 0.

| round | wall | tris | size (studs) | change / why |
|---|---|---|---|---|
| r01 | 3.1 s | 980 | 27.2 x 17.2 x 15.16 | timber-framed cottage: stone foundation, gables, arched door + step, framed windows with shutters, shingle courses, ridge, chimney. Roof slabs rotated the wrong way (V shape). |
| r02 | 3.0 s | 980 | same | roof rotation sign fixed. Reads as a cottage; fascia only showed as white blobs at the corners. |
| r03 | 2.8 s | 1004 | 27.45 x 17.2 x 15.48 | fascia -> white bargeboards along the gable edges (storybook outline). |
| r04 | 2.5 s | 1004 | 27.45 x 17.2 x 14.92 | eave depth 7.28 -> 7.0 to stay near the old depth. Tint preview (`models/_tinted.py`, three plot accents mixed 37% to white): the walls take the plot colour, red roof stays readable. Final. |

Roblox look + turntable: 7.9 s. Tinted previews: `sheets/plot_building_tinted_robloxlook.png`.
