# ranch_hay_bale polish rounds (2026-10-16, archer)

Before: `ranch_hay_bale_before_robloxlook.png` (gojo, 1040 tris). Issue on the roblox look: the end (side view) is one flat brown slab.
Olive shadow side left alone (LESSONS: it is the lighting).

| Round | Wall | Tris | What changed and why |
|---|---|---|---|
| r01 (roblox, 512 px) | 7.6 s | 1072 | Two `inset_individual` per end (sunken ring + pillow core). Read as a picture frame / crate end. |
| r02 (roblox, 512 px) | 8.1 s | 1220 | End face gridded (`subdivide_edges` cuts 5, grid fill), cos bulge + per-face straw stipple. Reads as hay up close, but blotchy. |
| r03 | 2.3 s | 1220 | Softer stipple; in the set view the lit end read as a QR grid. |
| r04 | 3.7 s | 1220 | Stipple cut to +-5 % value: at set distance it still read as a face (eyes/mouth). |
| r05 | 2.5 s | 1220 | No stipple, no jitter: smooth 0.05 bulge + radial gradient (light centre, darker edge/bottom). Reads as a pillowed hay end. Final: 4.10 x 2.62 x 2.56 studs, nm 0. |

Final: `ranch_hay_bale_after.png`, `ranch_hay_bale_after_robloxlook.png` (+ `_turntable.png`), set: `ranch_haybale_trough_set_robloxlook.png`.
