# pet_cloud rounds

| round | wall | tris | size (W x H x D studs) | what changed |
|---|---|---|---|---|
| r01 | 4.8 s | 560 | 3.30 x 1.23 x 2.81 | 7 subdiv-2 puffs (flat core + 6 rim puffs), light blue to white vertical gradient. Too deep (2.81). |
| r02 | 3.2 s | 560 | 3.30 x 1.23 x 2.39 | Pulled the puffs' y spread (x0.82) and squash (x0.9) in: on the 3.2 x 1.2 x 2.4 target. FBX + `--look roblox` check passed, uploaded as a new asset (see uploaded.json). |

Preview renders (cloud x0.9 and a tier-3 slime x0.55 on top, as FollowPets mounts them): `/workspace/roblox/renders/pet_cloud_{alone,with_pet}_*.png`, made with `models/_pet_cloud_scene.py`.

## Cloud v2 (2026-10-19): softer and smoother
| round | wall | tris | size (W x H x D studs) | what changed |
|---|---|---|---|---|
| r03 | 5.1 s | 1800 | 3.47 x 1.16 x 2.61 | New builder: 7 puffs as metaball ellipsoids fused into one skin (lib/goo.py), smooth-flagged, soft-clamped flat top. Smooth but a featureless bun, too big. |
| r04 | 2.8 s | 1800 | 3.30 x 1.19 x 2.40 | Footprint fit (x0.95 / x0.92 on puff x / y). |
| r05 | 3.3 s | 1800 | 3.30 x 1.225 x 2.40 | Top lifted x1.026 to the old 1.225 height. |
| r06 | 3.2 s | 1800 | 3.26 x 1.225 x 2.39 | Puffs pulled apart and the body narrowed so the lobes read; one smooth pass instead of two. |
| r07 | 3.2 s | 1800 | 3.26 x 1.225 x 2.39 | Blue-to-white gradient now ends at 80% height (blue underside shows). Final. Uploaded as version 2 of asset 76853347194916, new mesh id (uploaded.json). |

Smooth check: re-imported out/pet_cloud.fbx: 1800/1800 faces smooth, 0 of 902 vertices carry split normals. Colours are vertex colours (Col), no UVs/textures.
Renders: `/workspace/roblox/renders/pet_mounts/cloud_v2_*.png`.
