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

## models-v2 (2026-10-15: rocks, trees, pad_trim, plot_building, volcano, slimes)

- [rocks] Stylised rock = **convex hull** of ~22 Fibonacci-sphere points + 2-4 random tilted **planar chisel cuts** (`bmesh.ops.bisect_plane` clear_outer + `contextual_create`). Paint per face by normal: light up-facets, mid sides, darker foot, moss only on normal.z > 0.66. Even 34-point hulls read as potatoes. (`models/_rocks.py`)
- [rocks] Bury ~75% of the lower hemisphere (cut at z=0) so the widest point is near the ground; otherwise rocks look balanced on a narrow foot.
- [all] The Roblox look turns every shadow side ~2x darker than the studio sheet. Dark albedos (basalt 100, bark_dark 86, leaf_dark 124 green) go near-black: start darks at value >= ~115 and lift +15-20% after the first `--look roblox` check. Every model this batch needed it.
- [tree_pine] Fir tiers: cone skirts whose rim alternates long drooping tips and short notches (6-8 tips) + **per-corner** colour (tips light, notches/core dark, underside darkest). Per-corner colours interpolate across flat faces, which gives branch depth for free.
- [tree_oak] The first kit oak was 10-45% bigger than the slot it fills. Always render the old mesh and match `size_studs` within 10% before polishing; scale an existing model with `o.scale` per part before `finish()` (parts from lib builders have their origin at the world origin).
- [pad_trim] Read how the game uses a mesh before modelling it: Detail.luau stretches pad_trim Y to `PAD_TRIM_HEIGHT / native height`, so modelling it at the real 1.8 studs is drawn 1:1 instead of a 0.3 slab x6. Meshes placed 64x per map (pads) deserve a tight tri budget.
- [plot_building] Keep the game's anchor points (sign board, flower boxes, door) where `Detail.luau` puts its extra parts; note them in the script header. Check bmesh/`box(rot=...)` rotation signs on the first sheet (the roof came out as a V).
- [tint] `models/_tinted.py` multiplies a model's `Col` by `TINT_RGB` to preview what MeshPart.Color does (the cottage and pad_trim are tinted in game). Light walls take the plot colour; a red roof stays red. Design tinted meshes in **values**, not hues.
- [volcano] A closed **surface of revolution** with per-vertex lava paint (gullies indented, never proud) gives "nothing sticks out" by construction and 0 non-manifold edges (v3 had 238). Detail features only show if a vertex ring lands on them: strata bands thinner than the ring spacing vanished; shade whole rings instead (terrace ledges).
- [slimes] **Organic shapes are reachable when they are analytic**: a gumdrop body as a surface of revolution (24 segs x 17 rings, smooth shaded) looks good. Combining separate primitives is where it breaks: goo drips as tubes/blobs read as stubby limbs in every attempt; displacing the body surface itself along the drip lines reads as melting goo. Anything that has to *merge* (drips, fused blobs, limbs) needs a surface function, metaballs + remesh, or a generator/sculpt.
- [slimes] Smooth vs flat in one mesh: `finish()`/`cleanup()` set every face flat. Store the wanted flag on an INT face attribute (survives `join` + bmesh), re-apply `use_smooth` after `finish()`, then remove the attribute. Smooth faces export as smooth normals with the kit's FBX settings.
- [slimes] **Vertex colour x MeshPart.Color (assumed multiply, NOT verified in Studio):** the game's tinting design depends on it (cottage, pad_trim, SlimeMesh sets mesh.Color = genome colour). Consequences: tinted meshes can't hold white or any other hue (highlights, eye whites, cheeks go body-coloured); only value survives. So: bodies light grey with value-only paint (foot 0.70, body 0.86, crown 0.93, highlight 1.0), and faces/coloured accessories as **separate MeshParts with Color = white**. Verify at Phoenix's Studio gate before anything else.
- [slimes] Decals that hug a body: project 2D (u, v) polygons onto the analytic surface along its normal, give them thickness (closed slab, 0 non-manifold), layer details with a bigger offset (pupil 0.015, catchlight 0.04). One body function = faces fit every variant.
- [kit gotcha] The kit's FBX axes map Blender -Y to Roblox **+Z**. Props are fine (Detail.luau turns the cottage 180), but slimes face Roblox -Z (SlimeLayout), so slime meshes are turned 180 deg in `ship()`. After setting `rotation_euler`, call `bpy.context.view_layer.update()` before reading `matrix_world`, or bbox/offsets are computed unrotated (mine came out mirrored in Z). Verify orientation on the exported OBJ, not the sheet.
- [kit] One-view renders for lineups: `--views 0 --res 320 --no-ref`, 4 iterate.py processes in parallel: 12 tiles in ~9 s on 8 cores (`tools/slime_lineup.py`).
- [theme, dropped] Volcanic Meadow (now `THEME_volcanic_meadow_dropped.md`) before modelling. Audit every mesh on meadow ground: `--look roblox --no-export --ground 98,160,70`; grey-ground sheets hide blue/muddy greys and washed-out pastels. Darks below ~115 value still go black on the shadow side.

## Slime Ranch (2026-10-15 onward)

Theme: `THEME.md`. Every bot appends one entry per model; Archer curates.
Format: `- [model/YYYY-MM-DD/bot] lesson` — one concrete, reusable sentence or two (what worked, what didn't, a lib gotcha, a number).

- [theme/2026-10-15/archer] Judge every model on `--look roblox --ground 120,196,108` (ranch_field); colours go to `PALETTE["ranch_*"]`.
- [ranch_feed_trough/2026-10-15/gojo] Goo fill = `create_grid` + `extrude_face_region` (closed slab, 0 non-manifold), top verts dipped toward the centre. Colour the goo_hi rim by **distance to the walls** (`max(|u|^8, |v|^4)`), not by height: with a shallow dip a height ramp turns the whole surface pale.
- [ranch_feed_trough/2026-10-15/gojo] A cream-painted top plank on wood walls gives the value contrast plain wood lacks; flared walls add depth (2.5 -> 2.66), so shrink D to stay on size.
- [ranch_crate/2026-10-15/gojo] Stackable = full-footprint deck planks on top and bottom with posts *between* them, and every side detail (label bands, emblems) kept inside the post line. Size check must read exactly 3 x 3 x 3. Variants share a builder (`models/_ranch_crate.py`) and get colours passed in.
- [ranch_crate_goo/2026-10-15/gojo] Red painted slats go maroon on the roblox-look shadow side: start red lows at mix(roof_dark, roof, 0.5), not roof_dark.
- [ranch_hay_bale/2026-10-15/gojo] Hay texture for cheap: `bisect_plane` the bevelled box every half flake along X, push the seam rings in (~0.09) toward the long axis, and alternate flake value (x0.95). Straw as cones reads as spikes, and squashed blobs on the front or ends read as face features (eyes, mouth, leaves): keep loose straw on top only.
- [ranch_hay_bale/2026-10-15/gojo] Butter yellow goes olive-brown on the roblox-look shadow side whatever the albedo lift; that is the lighting (the avatar block goes as dark), so don't chase it past a lift of the low end.
- [ranch_shed/2026-10-15/gojo] The plot_building recipe (slab roof rotated about the ridge axis, shingle course strips, barge boards along the slope, gable prisms) carried over cleanly: good on round 1. Side-wall windows under ~2 studs with a cross read as dice; 2.4 x 2.0 frame with a 0.3 cross reads as a window.
- [ranch_shed/2026-10-15/gojo] iterate.py prints size as **W x H x D**, not x y z: 10.55 x 9.33 x 8.55 means 9.33 tall. Lifting the lows past mix(wood_dark, wood, 0.4) barely changes the roblox-look shadow side; spend the value on the lit-side contrast (cream trim vs wood vs red) instead.
