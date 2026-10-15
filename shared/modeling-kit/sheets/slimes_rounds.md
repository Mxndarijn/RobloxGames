# slimes rounds (2026-10-15)
Before: Luau-placed parts (SlimeLayout.luau: Ball body d = 3 studs x size, eyes/mouth/gloss/drips as small
Balls and Blocks, tier accents). No mesh to render, so there is no before sheet; the lineup is the after.
Design: models/SLIMES.md. Round times: one slime 2.2-2.9 s, full 12-tile lineup 9 s (4 Blenders in parallel).

| round | wall | tris | change / why |
|---|---|---|---|
| r01 (`slime_base_r01`) | 2.6 s | 1388 (body+face) | gumdrop surface of revolution (28 segs), lean-back peak, value paint (dark goo foot, light crown, highlight blob), decal face projected on the analytic surface. Cute already; face too small for the look, too many tris. |
| r02 (`slime_base_r02`) | 2.6 s | 1204 | eyes +25% and wider, 24 segs, lighter decal polygons. 512 px close-up: clean, reads. |
| lineup r01 (`slimes_lineup_r01`) | 8.9 s | - | all 7 variants + 5 faces tinted. Crystal too small/hidden, wobble tube-drips look like stubby arms, mischievous eyes read sad (lid slant inverted). |
| lineup r02 (`slimes_lineup_r02`) | ~9 s | - | lid slant flipped (sly), bigger crystal cluster, drips hug the body. Roblox look lineup: tints stay saturated, faces crisp. Drips still read as limbs, wobble 1920 tris. |
| wobble r04 | 2.3 s | 1472 | 5 flatter drips, cheaper bulbs: still nubs. Separate shapes can't merge into goo (this is the organic limit). |
| wobble r05 (`slime_wobble_r05`) | 2.7 s | 1612 (with face) | drips as smooth bulges of the body surface itself (32 segs + 2 extra rings low down): reads as melting goo. |
| final | 2.1-2.5 s each | see SLIMES.md | crown band 20 -> 12 segs, eyes 14 -> 12 verts, leaf ends never zero-width (was 4 non-manifold edges), bbox computed after the 180 deg turn (offsets were mirrored in Z). Verified on the OBJ that faces point Roblox -Z. |

Roblox look + turntable (slime_base + happy face, green tint): 6.3 s.
