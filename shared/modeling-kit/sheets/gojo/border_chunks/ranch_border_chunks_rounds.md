# World border chunk rounds (gojo, 2026-10-16)

Eight chunk meshes for the steal-a-slime map edge, replacing the per-piece border (228 MeshPart
slots) with ~40 chunk placements (`WorldBorder.luau`, 44 border slots with the 4 ranch accents).
Each chunk combines hedge / log rail fence / firs / mound / sandstone / goo in one mesh, ~53-57
studs wide. Shared low-poly helpers in `models/_border_chunk.py` (hedge_run, fence_run, pines,
mound, rocks, goo_puddle, bush, tufts, ship). Every design also ships a mirrored twin
(`CHUNK_MIRROR=1 ... --name ranch_border_chunk_X_m`): a MeshPart can't take a negative scale.
All rounds `--look roblox --ground 120,196,108 --res 384` (r01 of a: 256 px). Combined sheet + plan:
`sheets/gojo/ranch_border_chunks_set.png` (`tools/border_sheet.py`).

| Model | Round | Wall | Tris | nm | What changed / why |
|---|---|---|---|---|---|
| chunk_a (hedge + fence + firs + rocks) | r01 | 3.3 s | 1912 | 0 | Hedge run, fence with goo dollop, rock clump, 3 firs. Thin for a 53-stud stretch. |
| chunk_a | r02 | ~4 s | 2680 | 0 | + low mound behind the hedge, 5 firs: reads as a solid edge. |
| chunk_a | r03 | 23 s* | 2680 | 0 | Firs stood on the mound (`pines(hz=)`); r02 trunks sank in. Final 53.8 x 18.2 x 18.8. |
| chunk_b (big hill + rocks + hedge) | r01 | 27 s* | 1954 | 0 | Two-hump hill, seep, 4-stone clump, short hedge. Firs buried in the hill. |
| chunk_b | r02 | 23 s* | 2086 | 0 | Firs lifted onto the hill, + a small fir on the left. Final 56.9 x 17.8 x 21.7. |
| chunk_c (long fence + mound + fir stand) | r01 | 27 s* | 2220 | 0 | Fence with one dropped rail + goo, low mound, 4 firs, bushes. |
| chunk_c | r02 | 23 s* | 2220 | 0 | Firs on mound height (no visible change; none stood on it). Final 55.8 x 17.0 x 18.6. |
| chunk_d (pine grove) | r01 | 27 s* | 2074 | 0 | 7 firs in two staggered rows, bushes, 2 rock clumps, hedge stub. Good on round 1. |
| chunk_e (long hedge + tall hill) | r01 | 27 s* | 2868 | 0 | 40-stud hedge, 11-stud hill behind. The fir on the hill was buried to its tip. |
| chunk_e | r02 | 23 s* | 2904 | 0 | Hill fir moved behind the hill crest and lifted. Final 56.4 x 16.5 x 23.8. |
| chunk_f (sandstone outcrop + goo pool) | r01 | 27 s* | 2194 | 0 | 5-stone outcrop, goo pools, hedges both sides, firs + fence stub behind. Good on round 1. |
| chunk_g (stepped fence round a hill) | r01 | 27 s* | 2536 | 0 | Two fence runs (right one set back), hedge plug, hill + firs, rocks. |
| chunk_g | r02 | 23 s* | 2536 | 0 | Hill firs lifted. Final 55.0 x 20.2 x 22.2. |
| chunk_h (deep corner grove) | r01 | 27 s* | 2244 | 0 | 54 x 42 mound with 8 firs, rocks, pond. Firs stumpy (sunk in the mound). |
| chunk_h | r02 | 23 s* | 2244 | 0 | Firs lifted onto the mound: 28 tall, reads from behind the front row. |
| *_m (8 mirrored twins) | r01 | 5-27 s* | same | 0 | X mirrored + faces reversed in `ship()`; colours and normals check out on the roblox look. |

\* 7-8 renders in parallel on the shared box; a lone round is ~3-5 s.
