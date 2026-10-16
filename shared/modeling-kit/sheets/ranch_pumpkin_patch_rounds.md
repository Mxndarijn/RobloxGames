# ranch_pumpkin_patch rounds (archer, 2026-10-16)

Low mounded soil bed (~6 x 6, closed polar heightfield, superellipse outline) with 4 ribbed pumpkins
(closed lathe, 3 columns per rib with a sunk valley column; orange = mix(butter, roof)), chunky curled
wood_dark stems, wavy vine tubes + slab leaves + spiral tendrils, metaball goo spilled over the big
pumpkin's crown with drips and a foot puddle (lib/goo.py). All sheets: `--look roblox --ground
120,196,108` in `sheets/ranch_pumpkin_patch/`.

| Round | Wall | Tris | nm | What changed / why |
|---|---|---|---|---|
| r01 | 4.9 s | 2748 | 0 | First pass. Reads as a pumpkin patch at once. Problems: goo crown pool (r 0.62) + 12 fat collar lenses + 3 drips = a green lid over the big pumpkin; 2748 tris (vines 3 samples/segment, 5 tendrils x 9 pts, soil 28x5); pumpkin shadow side brown (lows toward roof_dark). |
| r02 | 3.2 s | 2352 | 0 | Goo pool 0.42, 10 thinner collar lenses higher on the shoulder, 2 drips; pumpkin lows mix(orange, roof) not roof_dark; soil 24x4, vines 2 samples/segment, tendrils 7 pts. Goo now reads as a ring band and pumpkins sink into the orange-brown soil. |
| r03 | 3.1 s | 2188 | 0 | Collar height wobbles +-0.06 (sin*cos) so the rim reads as an ooze, not a band; orange mix 0.5; soil darker (wood_dark -> mix 0.4) for value contrast; leaves x1.15-1.4 so green separates the pumpkins; 3 tendrils. |
| r04 | 4.1 s (+3.9 s turntable) | 1938 | 0 | Tris trim: soil 20 sides, drop 5th vine, small pumpkins 5 rows, goo decimate 170. No visible loss. Turntable: pumpkins + goo read from all 8 angles. Final. |

Final: 1938 tris, 6.48 x 2.71 x 6.36 (W x H x D), nm 0, 1 mesh, FBX 56 KB.
