# World border v3 pieces (17 meshes, 2026-10-16, archer)

One mesh per piece, so WorldBorder can mix and scatter them. Built from `models/_border_v3.py`
(conifer, round_tree, rail fence, backdrop hill) on top of `_border.py` / `_border_chunk.py` / `_rocks.py`.
Previews: `border_v3_preview_{trees,hedges_rocks,fences_hills}.png` (`--look roblox --ground 120,196,108`).

| round | what | result |
|---|---|---|
| r01 | trees (5), hedges (3), rocks (4), fences (2), hills (3) | all PASS, 0 non-manifold, 196-1564 tris |
| r02 | hills were witch hats on a dark plate: wider/lower humps, foot colour = ground, crest light | hills read as soft mounds |
| r02 | stepped hedge: orange trellis post stuck out like a pole; replaced by blooms | cleaner |
| r02 | oak trunk too long and orange (lollipop): shorter, trunk gradient dark; spire taller | reads as a tree |

Tris are below the 500 prop target on purpose: border pieces are seen from 20+ studs away and a slot
costs nothing per triangle at that size; the hills (1.3-1.6k) carry the most.

## Round 2 (placement review): five denser pieces
The first scattered ring (single trees, 15-25 stud fences) rendered as sparse specks next to the old
continuous band. Added, still one mesh each: `fence_long` (51 studs, 8 bays, open field gate),
`hedge_xl` (41 studs, three heights), `grove_pine` (6 firs), `grove_mixed` (2 oaks + 2 firs + bush),
`grove_rocky` (2 firs, oak, rock heap, spire, goo seep). Preview: `border_v3_preview_groves_long.png`.
