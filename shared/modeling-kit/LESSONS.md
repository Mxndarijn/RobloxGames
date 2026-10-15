# LESSONS (read before modeling; append after each model)

Format: `- [model/date] lesson`. Keep them short and concrete.

## Seed lessons (2026-10-15, from v17 make_meshes.py and the tree_oak remake)

- [kit] **1 Blender unit = 1 stud.** Never model in metres. Proven: pad_trim was built 9.4 BU and imported to Roblox as a 9.4-stud MeshPart. Check scale against the grey 5-stud avatar block in every sheet.
- [kit] bmesh `create_icosphere` subdivisions: 1 = 20 tris (spiky gem), 2 = 80 (puffy low-poly, the default for foliage), 3 = 320 (big hero shapes only). The v17 tree used 20-tri puffs, which is why it looked crude.
- [kit] Colour lives in vertex colours ("Col", one flat colour or gradient per part). Roblox shows FBX vertex colours on MeshParts; FBX material colours are not reliable. Use `lib.finish()` to get one mesh and one vcol material.
- [kit] Judge colour in Cycles sheets only. `--engine workbench` draws vertex colours noticeably darker; use it for shape checks only.
- [kit] Overlapping closed parts (not booleaned) are fine: 0 non-manifold edges, exact per-part colours, cheaper than booleans. Don't merge vertices across parts (`finish(merge=0)`).
- [tree_oak] A per-part **vertical gradient** (dark bottom → light top) does most of the "cartoon" look for free: puffs read as volumes, the canopy underside fakes AO, and a dark trunk base grounds the model.
- [tree_oak] Equal-size puffs in a ring read as a necklace of beads. Hand-place 3 tiers (low wide / mid / crown) with uneven radii (1.7–2.5), heights (±0.5) and distances.
- [tree_oak] Hidden geometry wastes budget: the canopy core is mostly covered, so 80 tris is enough. Spend tris on the silhouette (outer puffs).
- [tree_oak] Trunk flare (base radius about 2× the mid radius) plus 4–5 root tubes sinking just below z=0 grounds a tree. Show 1/3 to 1/2 of the trunk below the canopy, or it reads as a bush.
- [tree_oak] Decor rule (v17 CLAUDE.md): a *collidable* canopy needs its underside ≥ 7 studs up. Ghost decor (the default) can go lower; print the underside height in the model script.
- [kit] 256 px tiles hide subtle colour changes (gradients on thin parts). For a final check, run `--res 512 --samples 24 --no-export --out /tmp/x` once (~9 s).
- [kit] Small props (rocks, mushrooms) can sit under the 500-tri target; that is only a warning. Don't pad tris.
- [kit 2026-10-15] `--quick` (Workbench clay + cavity + outline) is a 1.2 s shape check: use it for silhouette/proportion rounds, then a full Cycles round for colour. Keep the cavity *ridge* low: on flat-shaded low-poly every facet edge lights up and the sheet turns to noise; the *valley* lines (dark seams between puffs) are the useful part.
- [kit 2026-10-15] Workbench used to cost 2.2 s; it now measures 1.2 s on this box. The first Workbench render pays ~0.3 s GL init, the next ones ~0.1 s. Blender start (~0.9 s) is now most of a quick round, so it won't get much faster without a long-running Blender.
- [tree_oak 2026-10-15] `--look roblox` vs the default sheet: the default camera-following 3-point light flatters. Under the game's fixed sun + ambient the low canopy puffs and the shadow side go much darker and the whole thing warmer (`sheets/tree_oak_cycles_vs_robloxlook_front.png`). Before shipping a model, check its darkest colours (`leaf_dark`, `bark_dark`) in the Roblox look; they may need +10-20 % value.
- [kit 2026-10-15] `--look roblox` is not calibrated against Studio yet. Treat it as "probably closer", not truth. When Phoenix's gate yields a real screenshot of a kit mesh, compare it and tune `RBX` in `kit/bl_iterate.py`.
- [kit 2026-10-15] A second material (`flat_material`) on a shipping mesh is silently lost in Roblox, and in `--look roblox` it already shows as the vertex colour. iterate.py now warns about extra materials, material colours, image textures, extra colour attributes and vertex alpha.
