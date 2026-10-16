# World border set rounds (gojo, 2026-10-16)

Five pieces for the steal-a-slime map edge (`WorldBorder.luau` places them seeded-random around the
r292 wall ring). Shared helpers in `models/_border.py` (tuft, flower, fir, heightfield). All rounds
`--look roblox --ground 120,196,108`. Combined sheet + top-down plan: `sheets/gojo/ranch_border_set.png`
(`tools/border_sheet.py`).

| Model | Round | Wall | Tris | nm | What changed / why |
|---|---|---|---|---|---|
| ranch_hedge_segment | r01 | 4.1 s | 1640 | 0 | Core box + two staggered puff rows + light crown row + blooms. Foot tufts read as legs (caterpillar). |
| ranch_hedge_segment | r02 | 2.8 s | 1604 | 0 | Tufts dropped, bottom puffs lowered. Core still showed as a flat box between puffs. |
| ranch_hedge_segment | r03 | 3.0 s | 1604 | 0 | Core shrunk behind the puffs; blooms pulled onto the puff surface. Side view: blooms still floated ~1 stud. |
| ranch_hedge_segment | r04 | 3.1 s | 1604 | 0 | Blooms 0.3 further in. Final: 12.75 x 5.21 x 4.12. |
| ranch_rail_fence | r01 | 2.7 s | 388 | 0 | 2 posts + 2 rails overhanging +X for tiling: the overhang read as unfinished, thin. |
| ranch_rail_fence | r02 | 2.8 s | 728 | 0 | 3 posts (both ends + off-centre), rails per bay, rope lashings, goo dollop. Final: 11.97 x 4.83 x 1.65. |
| ranch_pine_cluster | r01 | 2.7 s | 624 | 0 | 3 firs (16 / 12 / 8.6) in ranch greens + bush + tufts. Good on round 1. Final: 14.18 x 16.43 x 10.24. |
| ranch_border_hill | r01 | 3.0 s | 1754 | 0 | Square-grid heightfield: pyramid peak, square slab rim, per-face goo pond = pixel cross. |
| ranch_border_hill | r02 | 2.6 s | 2082 | 0 | Grid cut to an ellipse + per-vertex paint: stepped (staircase) rim from the deleted faces. |
| ranch_border_hill | r03 | 2.9 s | 1658 | 0 | Polar grid (30 x 10 rings): smooth elliptical rim; goo puddle as a flat blob at the foot. Final: 29 x 9.01 x 17.30. |
| ranch_border_rocks | r01 | 2.7 s | 628 | 0 | 4 hull stones + 2 pebbles, moss, goo seep puddle, tufts. Shadow side brown. |
| ranch_border_rocks | r02 | 2.8 s | 628 | 0 | Sandstone +7 % value. Final: 12.73 x 6.13 x 7.81. |
