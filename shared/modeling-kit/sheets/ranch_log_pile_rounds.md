# ranch_log_pile rounds (archer, 2026-10-16)

Firewood pile for the plaza/farm: 4/3/2 pyramid of chunky logs running along Y so the ring ends
(bark rim, light heartwood, darker sunk core) face front and back, two stakes per side, chopping
stump with root flares and a pewter-headed axe on +X, metaball goo sap oozing out of two log ends
with a ground puddle (lib/goo.py), wood chips + grass tufts. All sheets: `--look roblox --ground
120,196,108` in `sheets/ranch_log_pile/`.

| Round | Wall | Tris | nm | What changed / why |
|---|---|---|---|---|
| r01 | 2.7 s | 1748 | 0 | First pass. Pile + ring ends read at once. Problems: the goo was one straight lens chain from the top log to the ground = a green column covering the ring ends (the stuck-on tube read again); pile only 3.9 tall vs the 5-stud avatar; axe head too small to read. |
| r02 | 2.8 s | 1728 | 0 | Logs r 0.62 -> 0.7 (4.0 tall, chunkier); goo = short tapering ooze over the top log's lower rim ending in a fat hanging drop + separate ground puddle with splash beads; bigger wedge axe head. Goo now reads as sap, ring ends stay visible. |
| r03 | 2.8 s (+4.7 s turntable) | 1788 | 0 | Second small ooze on a bottom-row end so the goo reads from a distance, goo decimate 300. Turntable: ring ends read front and back, stump/axe from the sides. Final. |

Final: 1788 tris, 10.94 x 4.01 x 6.81 (W x H x D), nm 0, 1 mesh, FBX 54 KB.
