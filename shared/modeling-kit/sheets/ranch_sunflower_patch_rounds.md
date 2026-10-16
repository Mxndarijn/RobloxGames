# ranch_sunflower_patch rounds (archer, 2026-10-16)

Raised plank bed with 5 sunflowers (4.6-7.4 studs) for plaza/farm edges: bevelled plank border +
corner posts, soil slab, each flower = closed petal slab (butter) + domed seed centre + green back
cup on a curved stem with 2 slab leaves; red watering can on the front-right dribbling metaball goo
(lib/goo.py) into a puddle, grass tufts. All sheets: `--look roblox --ground 120,196,108` in
`sheets/ranch_sunflower_patch/` (`_r04_front512.png` = 512 px front close-up).

| Round | Wall | Tris | nm | What changed / why |
|---|---|---|---|---|
| r01 | 3.4 s | 2100 | 0 | First pass. Reads as a sunflower bed at once; tallest head over the avatar. Problems: 16-point star heads read as spiky sawblades; petals mustard/brown (lows mixed toward wood); over 2000 tris. |
| r02 | 3.2 s | 2040 | 0 | 12 petals with 2-vert rounded tips, lows toward roof instead of wood, soil mounds dropped (hidden). 512 px close-up: tips read as **cog teeth**, leaves edge-on from the front (flat side pointing up), still mustard. |
| r03 | 3.0 s | 2072 | 0 | Pointed oval petals (shoulder, tip, shoulder, valley; 10 per head), petal ramp BUTTER -> mix(BUTTER, CREAM, 0.45), smaller seed centre, leaf normal leaned toward -Y, cap strips dropped. Petals now read; leaves read as flat green parallelograms (signs). |
| r04 | 3.1 s | 2074 | 0 | 6-vert pointed oval leaves drooping (out + 0.5 down), normal (0, -0.55, 1). Leaves read. Left heads still dull: they were yawed away from the kit sun (front-left). |
| r05 | 3.0 s (+3.6 s turntable) | 1954 | 0 | All heads yawed toward front-left (-8..-28 deg), 9 petals, stems 4-seg, cups 6-seg, can 8-seg, goo 180. Heads bright from 0-45-315 deg, green cups from the back. Final. |

Final: 1954 tris, 8.72 x 8.76 x 6.10 (W x H x D), nm 0, 1 mesh, FBX 57 KB.
