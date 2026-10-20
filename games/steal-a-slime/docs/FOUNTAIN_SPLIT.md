# Fountain split (FEATURES.FountainSplit, draft, default off)

Option (a) of Merijn's fountain collision choice: the `slime_fountain` mesh cut into 5 meshes, the tower pieces each a
`PreciseConvexDecomposition` (PCD) collision mesh. Options (b) (hand-placed boxes, what ships) and (c) (one low-poly collision
mesh) are not touched. With the flag OFF nothing changes: no piece is loaded, preloaded or placed.

## The pieces

`shared/modeling-kit/models/slime_fountain_split.py` imports the shipped `out/slime_fountain.fbx` and partitions its faces (no
re-meshing, no new faces or caps, custom normals and vertex colours kept; checked corner by corner, also after the FBX round trip).
Tower pieces are cut by face-centroid height at the silo profile rings (z 30.0 eave, 31.3 dome, 35.9 basin floor); the metaball goo
crown is one connected mesh that runs down the staves, so its faces are banded the same way (a cut through a drip leaves two open
edges with coincident vertices, no gap shows). Numbers: `out/fountain_split.json`, `out/fountain_split_<piece>.stats.json`.

| piece | what | tris | collision |
|---|---|---|---|
| `fountain_split_basin` | rim, basin floor and goo crown above z 35.9 | 766 | PCD |
| `fountain_split_dome` | red dome shoulder (z 31.3..35.9) + its goo collar | 1157 | PCD |
| `fountain_split_eave` | eave underside and edge (z 30..31.3) | 291 | PCD |
| `fountain_split_silo` | plinth, trim, staves, hoops below z 30 + the goo drips there | 1960 | PCD |
| `fountain_split_slide` | trough, slide goo, supports | 2180 | PCD with `FEATURES.SlidePCD` (else decor) |

Sum 6354 = the whole mesh. `FEATURES.SlidePCD` makes the slide piece PCD too (walls, posts, braces become real collision) and
MeshSwap retires the `SlideColliders` Post / Brace boxes (145 -> 132); the floor slabs (the walk surface), rails and `Skirt` stay (the
slide is walkable, COLLISION.md). Each piece's `offset` (MeshAssets) is its bbox centre minus the whole mesh's bbox centre in the slot's axes
(Roblox X, Y, Z = kit x, kit z, -kit y, rotated with the slot; `IMPORT_YAW` turns only the mesh). Piece asset / mesh ids: `MeshAssets`,
`shared/modeling-kit/uploaded.json`.

The silo is plain staves all round: `models/slime_fountain.py` has no door (a red plank door near the foot read as a paint
glitch), so the whole mesh and the silo piece draw the same staves and the split needs no colour fixes.

The cut pieces are open surfaces (no caps, to keep the face set identical). Whether Roblox's PCD handles them as well as it
handles the closed whole mesh is exactly what the ball-drop test measures.

## What the flag does

`MeshSwap.swapFountainSplit` (fountain slot `FountainMesh` only): all 5 meshes are created first (`CreateMeshPartAsync`, tower pieces
with `CollisionFidelity = PreciseConvexDecomposition`, `RenderFidelity = Precise`), placed at slot centre + offset with the same fit
and `IMPORT_YAW` as the single mesh, children of the slot named after the piece. Only then the stand-ins and the hand-placed
`MeshCollider` parts (BasinCollider, TrimCollider, SiloCollider, TopCollider<i>) go non-colliding (they stay in the map, switched
off, so the part count does not drop). If any piece fails (no id, CreateMeshPartAsync error) nothing is placed and the single mesh
and the colliders behave exactly as without the flag, every `SlideColliders` box included. With the pieces placed and `SlidePCD` on,
`MeshSwap.apply` ends by retiring the boxes the slide mesh replaces; `Fill`, `JointFill`, the roof wedges and `Skirt` stay.

`MeshAssets.COLLISION` also lists the 4 PCD pieces and the slide (a global table; the slide is only asked for with `SlidePCD`); `tests/MeshCollision.spec` counts them only with the flag
on. With the flag off no piece MeshPart exists, so the client preloads none. Not in `FeatureOverride.FLAGS` on purpose: the
pc-watcher sets those at boot for a whole run, which would flip the fountain for every shot; use the experiment shot below.

## Budgets (tools/pr-gate)

| | flag off (= main) | flag on |
|---|---|---|
| runtime parts (fail > 2500) | 1987 | 1991 |
| unique meshes (fail > 120) | 95 | 99 |
| MeshParts (soft 500) | 401 | 405 |
| world triangles (fail > 500000) | 313,044 | 313,044 |

## What Phoenix runs (pc-watcher, Studio; flag stays OFF)

Branch `archer/fountain-split` (the commit, once pushed). A full run, because `pc-watcher/**` changed:
`python watcher.py once --sha <branch tip sha> --kind full` (the usual way to test a branch sha). Shots that matter (ids):

1. `22-fountain-top-walk`: baseline, the full HARD grid against the hand-placed colliders (`shots[..].fountain_walk`).
2. `191-fountain-split-drop`: (a) `fountain_walk` with `"fountain_split": true`, the same full HARD grid (24 azimuths x r every 0.5 x
   feet / character balls x at rest / rolling inward) against the 4 PCD pieces instead of the hand-placed tower colliders
   (restored after; SlideColliders stay). ADVISORY: a violation is a note, not a failed run. (b) the same shot's `bug_probe`
   (extra probe of bug 11) runs the reduced 4-variant drop.
3. `170-bug11-mesh-collision`: the same 4-variant drop (`colliders`, `mesh_pcd`, `mesh_hull`, `split_pcd`), plus the audit.

Result fields to compare (report JSON, `shots` list entry by shot id):
- `fountain_walk` of 22 vs 191: `ok`, `samples`, `worst_clearance` (min ball-centre height above the visual top, must stay >= 0.4),
  `violations` (strings: "sank" / "fell through"), and for 191 `split` = `"experiment"`.
- `report.bugs` (id 11, twice: shot 170 and shot 191): `detail.experiment.variants.<variant>` = `{balls, sank, fell, parts_saved,
  tower_parts_saved}` for `colliders`, `mesh_pcd`, `mesh_hull`, `split_pcd` (`split_pcd.pieces` = 4, `.source` = `experiment`).
  Pass for split: `sank` 0 and `fell` 0 (as `colliders`); `parts_saved` = tower colliders - 4.
- Time: the drop probe budget went from 20 to 28 s (5 mesh creations, 4 grids); the shot timeouts are 50 s / 60 s.

To see the real flag-on path in Studio (pieces placed by MeshSwap, colliders off, then walk it): set `FountainSplit = true` in
`Config.FEATURES` on a scratch checkout; then shot 191 reports `split` = `"flag"` (the pieces measured as they are) and `22` is
skipped with a note (its top colliders are off by design).

## Renders (no Studio)

`lune run tools/render/export --fountain-split` writes `scene_fountain_split.json`; render views `31_fountain_eye` and
`32_fountain_aerial` of it and of `scene.json` and diff (`render_world.py ... --views 31,32 --res 1280x720 --samples 64`).
`--seed N` gives the noise floor of an A/B pair.
