# parade_lane_arc45 rounds (archer, 2026-10-15)

45-degree segment of the goo-parade lane (centreline r 68, lane r 64.75..71.25). Builder shared with the gate:
`models/_parade_lane.py` (closed sweeps of radial (d, z) profiles, so both ends are the same radial profile).
Close-ups: `models/_parade_lane_detail.py` (tiles a 2nd copy +45 deg, crops a window, drops a 3-stud slime).
Colour rounds are `--look roblox --ground 120,196,108`.

| Round | Wall | Tris | What changed / why |
|---|---|---|---|
| r01 quick | 1.3 s | 1466 | First build: goo slab (15-vert profile, dipped centre 0.20, walls 0.42, 3 whole ripples per segment so the ends match), 2 soft rounded rails (8-vert profile, top 0.88), 4 planks with V-groove seams (the seam ring sits on both ends), 3 stakes off the ends. Shape fine; the full-segment sheet is too small to judge detail, so I added the detail preview. |
| r02 colour | 2.7 s | 1466 | Goo reads (goo_hi only on the meniscus by distance to the walls). Arc/arc joint (`_r02_joint`): seamless, the joint looks like one more plank seam. Rails read as long plain beams (14-stud planks). |
| r03 colour | 2.9 s | 1770 | 6 planks per segment, stronger tint (0.90-1.05) and height jitter (+-0.05, top <= 0.93) per plank, 5 stakes (3 outer, 2 inner). Hand-made rhythm now reads. |
| r04 colour | 3.3 s | 1938 | 6 goo_hi bubbles r 0.2-0.36: specks, invisible at game size, 170 tris wasted. |
| r05 colour | 3.0 s | 1910 | 5 bubbles r 0.3-0.7, 0.09 high: read as soft pale goo spots. Final. |

## Final
- 54.53 x 1.00 x 11.78 studs (W x H x D), 1910 tris, 0 non-manifold, `out/parade_lane_arc45.fbx`.
- `parade_lane_arc45_after.png` (studio), `parade_lane_arc45_after_robloxlook.png` (+ `_turntable.png`).
- Tile joint: end rings identical vertex for vertex (checked numerically); the only render artefact is a hairline where the two coincident goo end caps meet, sub-pixel at game scale.
