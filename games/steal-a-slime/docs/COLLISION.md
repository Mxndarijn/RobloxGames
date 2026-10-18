# Collision: what to use where

Short rules for bots that add or change meshes and colliders. Anything marked **Studio check** is
from Roblox docs / memory and has not been measured in this game.

## The four fidelities (`MeshPart.CollisionFidelity`)

| Fidelity | Shape | Cost | Use for |
|---|---|---|---|
| `Box` | the mesh's bounding box | cheapest | crates, signs, anything box-like; pure decor you still want to bump |
| `Hull` | one convex hull round the mesh | cheap | blobs and piles (slimes, rocks, bushes) that nobody should stand inside. Fills any dent or gap |
| `Default` | a coarse convex decomposition | between Hull and PCD | medium concave things where a hull is too fat. Exact behaviour: **Studio check** |
| `PreciseConvexDecomposition` | many convex pieces, close to the mesh | most expensive: more pieces, slower physics and more memory | only when the exact surface matters (stairs, a walkable arch). Never for big or many parts |

Cheapest of all is no collision: `CanCollide = false`, `CanQuery = false`, `CanTouch = false` for
pure decor. Every mesh MeshSwap places starts that way.

## Where the property must be set so it sticks

- **Runtime meshes (this repo's world):** the kit's FBX files are uploaded as Models, the server
  makes the MeshPart with `AssetService:CreateMeshPartAsync(meshId, options)` (`server/MeshSwap`).
  `options` takes `CollisionFidelity`, `RenderFidelity` and `FluidFidelity`. A game script cannot
  write `MeshPart.CollisionFidelity` (or `RenderFidelity`) afterwards: it throws. So the fidelity
  has to go in the options.
- **Our way:** `MeshAssets.COLLISION` maps a mesh name to a fidelity. `MeshSwap` passes it to
  `CreateMeshPartAsync`, caches one template per mesh id and fidelity, and sets `CanCollide = true`
  for exactly those meshes. Clones keep the collision made on the template.
  To make a mesh solid: add one line to `MeshAssets.COLLISION`, extend `tests/MeshCollision.spec`.
- **Rojo-built parts** (`.model.json`, `.rbxmx`): the property is written in the file and sticks.
  The Blender / modeling-kit FBX route has no collision setting of its own: the fidelity is chosen
  at import (Studio importer / Model upload) or, for us, at `CreateMeshPartAsync`.
- Collision is **computed once, at import or creation**. Changing the fidelity of an existing
  MeshPart does nothing without a re-import (Studio plugin), so decide before upload.
- `Part`, `WedgePart` etc. have no fidelity; only MeshPart and UnionOperation do.

## Hull / Box do not eject overlaps; uneven hulls are not standable

A solid mesh only resolves contacts: a character whose root already overlaps it stays inside, so
bug #10's pile needs a server eject (`server/StackGuard`, same idea as `PlotLockGuard`). A Hull of a
lumpy pile has a concave-looking, uneven top that a character slides off or sinks into; for a solid
pile use `Box` (flat top, no extra part) or, if the box is too fat, one thin invisible anchored cap
Part. The emerge stack uses `Box`: it sits above the slide block and the ride is non-colliding.

## Players solid, slimes not: the slide

The fountain slide is part of the one `slime_fountain` MeshPart, which cannot be split into slide
and silo, so real mesh collision cannot say "slime yes, player no" for the slide alone. It also
would be wrong: a precise slide collision makes the trough walkable, which is the bug (#9).
So the slide keeps hand-placed collision (`shared/SlideColliders`), but as a **solid block** (a
floor slab plus a fill up to `FILL` = 11 studs above the ride line, more than a jump) so nobody can
enter or climb it. Wild slimes ride it anchored with `CanCollide = false` (`FountainRide`): they
pass through the block, so no collision group is needed.

The fill's roof is a ridge, not a flat top (bug #9 follow-up): `server/FountainColliders` keeps each `Fill` box (ride line up `FILL` = 11 studs, full width) and puts a roof of two
frictionless `WedgePart`s ON TOP of it (`SlideFill<i>L` / `R`, eaves at `FILL`, ridge at `FILL + half * tan(RIDGE_ANGLE)`, faces = `RIDGE_ANGLE` = 60 deg, `SlideColliders.ridge` / `wedge`). A Humanoid
climbs up to 89 deg (`MaxSlopeAngle`), so `server/SlideTopWatch` (pure maths: `shared/SlideTopGuard`, 5 Hz from
`WorldView.enforceLocks`, behind `FEATURES.SlideCollision`) also moves a character that stays on a roof for 0.3 s to the
ground beside the slide, away from the fountain. No kill part, no mesh collision. **Studio check**: the wedge's tall face
is its +Z side (the build assumes it; `SlideColliders.wedge` + the SlideTopGuard spec compute the face normal from that); the `bug9-slide-top-drop` shot drops the player on the ridge to prove it.

If a future feature needs physical slimes on the slide while players stay out, use a collision
group instead of a block: `PhysicsService:RegisterCollisionGroup("Slimes")` and `"Players"`, then
`CollisionGroupSetCollidable("Slimes", "Players", false)` and set `BasePart.CollisionGroup` on the
parts (character parts need it too, on spawn). Groups only filter part against part; the block
still needs its own collider. Max 32 groups. **Studio check** the character parts and
`CanCollide` interplay before relying on it.

## Rule of thumb

1. Decor: `CanCollide/CanQuery/CanTouch = false`. No fidelity option needed.
2. Players must not stand inside it, and it is roughly blobby: `Hull`.
3. It is a box: `Box`.
4. Players must walk on the exact surface: `PreciseConvexDecomposition`, one small mesh at a time,
   then check part count and physics step time in Studio's perf view.
5. A shape the mesh cannot give (a hollow, a slide that must stay closed, a world edge): a few
   invisible anchored Parts, `CanQuery = false`, `CanTouch = false`. Keep them few: they count in
   the runtime part budget (<= 2500, warn at 2400; `tools/pr-gate/runtime_budget.sh`).
6. Replace a hand-placed collider with mesh collision only after a Studio walk test: a mesh whose
   collision generation fails or is coarse (**Studio check**: PCD limits on large meshes) leaves a
   hole in the world. The silo's Basin / Trim / Silo / Top colliders stay for that reason.

## Open Studio checks

- `slime_fountain_emerge` as `Box` (bug #10): jump onto the pile and stand on its flat top; a character
  spawned inside is moved above the top by `server/StackGuard` (via `WorldView.enforceLocks`).
- `merge_vat` as `Hull` (bug #16, every plot's vat, `MeshSwap.swapPlotVats`): bump into the cauldron and the
  funnel spouts from all sides; nobody walks inside, the MergePrompt still triggers from the hull's edge.
- Whether `PreciseConvexDecomposition` on `slime_fountain` could retire the silo colliders and how
  many parts it costs. Draft behind `FEATURES.FountainSplit` (default off): the mesh cut into basin / dome / eave / silo (PCD) and
  slide (decor) pieces, `docs/FOUNTAIN_SPLIT.md`; needs the ball-drop result (pc-watcher shot 191) and a Studio walk.
- The slide block: walk the whole outline at the mouth, under the posts and beside the upper laps;
  nobody gets onto the top (11 studs above the ride line) and nobody is stuck in a corner.
- `tools/pipeline/pc-watcher/luau/slide_walk.luau` was written for the old walkable floor (balls
  dropped on `SlideFloor<i>`); with the fill on top they land on its top face. Adjust the shot.

## The ground (bugs #13-15)

The inner ground is voxel Terrain (`GroundTerrain`, flat at y = 0): Terrain collides by itself, so it has no mesh,
`MeshAssets.COLLISION` entry or collider part. The invisible `Map.Ground` part under it stays as the void-safety floor.

## The floor (B11, concept c3)

The visible floor is parts and two baked meshes on top of that terrain (`visuals/shared/FloorLayout`): the sand yard (`Map.Field`),
the boardwalk and plaza deck (`Map.Paths`) and the lawns (`Map.Lawns`). The terrain stays the walk surface, so **nothing in it
collides except the eight `GateRamp` blocks**: every floor part is `CanCollide/CanQuery/CanTouch = false`, at most 0.21 studs above
`FloorLayout.FLOOR_Y` (the ONE height constant). `ranch_floor_deck` and `ranch_floor_paths` are decor in `MeshAssets.COLLISION`
(`tests/MeshCollision.spec`). A gate ramp is the one place a lip is real: the plot Base floor top is `WorldLayout.PLOT_FLOOR_TOP`
(1), so a solid 11.7 degree plank climbs r 96..100 from the plank top to it, flush at both ends (`tests/FloorLayout.spec`).
`server/FloorTerrain.server` swaps the voxel Grass under the floor for Sand (a `Terrain.Decoration` tuft would poke through every
floor part); it needs no call site and touches no terrain-height file.

## Conversions (bug #11 part 1)

`MeshAssets.COLLISION` is the single list; one reason per mesh sits next to its line there. Summary:

| Fidelity | Meshes |
|---|---|
| `Box` | `slime_fountain_emerge` (bug #10, main), `ranch_fence_20`, `phoenix_fence_segment`, `phoenix_corner_post` (the plot fence), `ranch_plaza_signpost`, `phoenix_plaza_podium_1..3`, `ranch_crate`, `ranch_crate_goo`, `ranch_feed_trough`, `ranch_hay_bale`, `ranch_bench`, `ranch_compost_bin`, `ranch_flower_planter`, `ranch_goo_sign`, `ranch_hitching_post`, `ranch_mailbox`, `ranch_picnic_table`, `ranch_tool_rack`, `ranch_wagon`, `ranch_water_trough`, `ranch_barrel`, `ranch_well`, `ranch_fence_stile` (v196 follow-up) |
| `Hull` | `merge_vat`, `ranch_shop_stand` (already), `ranch_barrel_stack`, `ranch_birdhouse`, `ranch_campfire`, `ranch_feed_sacks`, `ranch_goo_bucket`, `ranch_goo_hive`, `ranch_log_pile`, `ranch_milk_churn`, `ranch_rain_barrel`, `ranch_scarecrow`, `ranch_shed`, `ranch_slime_coop`, `ranch_water_pump`, `ranch_weathervane`, `ranch_wheelbarrow`, `ranch_windmill` |
| `PreciseConvexDecomposition` | `ranch_barn_loft` (loft over an open floor), marked "PCD: Phoenix Studio check" |
| none (decor) | `slime_fountain` (tower, hand colliders stay), `phoenix_gate` (a Box/Hull would close the 14-stud opening; its GatePost stand-ins keep the posts; PCD is the later mesh route), `phoenix_pad_crate` (the Pad part is the surface), `phoenix_top_earners_board` (Model with its own Collider), `ranch_landing_ring` and `ranch_goo_drain` (decor meshes, solid through the thin `PlazaColliders` parts, see the last section), `ranch_horseshoe_pit`, `ranch_lantern_post`, `ranch_pumpkin_patch`, `ranch_sunflower_patch`, `ranch_border_*`, `giant_*`, `habitat_*`, `plot_skin_*`, `fountain_tier_*`, `rain_magnet`, every slime kit mesh, `slime_lane` |

`tests/MeshCollision.spec` makes every mesh name either solid or decor-with-a-reason.

What changed besides the list:

- **Slot boxes.** A WorldLayout slot is a primitive box that used to stay as an invisible collider under its mesh. Now a decor
  ranch prop slot never collides, and a Part slot whose mesh has a fidelity turns its box off once the mesh is placed
  (`MeshSwap.swap`): the mesh is the collider. While the mesh loads (or fails) the box still collides.
- **Plot fence.** The five invisible `Wall*` blocks per plot (40 parts for 8 plots) are removed. The fence panels (`ranch_fence_20`
  20 x 8.2 x 1.64, `phoenix_fence_segment` 10 x 8.2 x 1.64 beside the gate, `phoenix_corner_post` at the gate stub) are `Box` and
  carry `FenceCollider`; their slot boxes collide until the mesh lands. The spec walks every old wall's centre line in 0.25 steps
  and requires a Box slot at each point, at least as tall as the wall and starting at its base, with the gate opening still open.
- Left alone on purpose: `slime_fountain` and its Basin / Trim / Silo / Top colliders, `SlideColliders`, `FountainColliders`,
  the World Border wall ring, the Leaderboard board's `Collider`.

### What Studio must confirm

- **Shapes vs visuals.** `Box` bbox against the visual for the podiums, signpost, wagon, tool rack, hitching post and bench
  (a bbox corner can stick out past a bevel); `Hull` against the visual for the scarecrow, weathervane, birdhouse, windmill, well
  (hull fills under roofs and between arms) and the shed / coop gables.
- **PCD walkability.** Walk a character under / onto `ranch_barn_loft` (the stile is Box since the v196 follow-up); check the generated
  collision exists at all for the scaled mesh (the engine may fall back to a coarser one), and the physics step cost.
- **Stand-on surfaces and fall-through.** Stand on the three podiums (rigs from `PodiumRigs`), crates, wagon, picnic table, shed
  roof ledge: no fall-through, no float above the visual top, no stuck feet in a Hull's filled concavity.
- **Fence.** Walk the whole fence line of one plot, corner to gate: no gap at joints, corners or the gate stubs; the gate opening
  stays open; if a `Box` mesh fails to generate, the placeholder box (same footprint) is the fallback.
- **Pass-through and clearance.** The walk-through `ranch_*` decor (patches, pit, border, habitats) stays passable.
- Shots `183-bug11-hull-stand`, `184-bug11-box-stand`, `185-bug11-pcd-stand` (`luau/mesh_stand`) drop and push balls at these
  meshes; they do not replace a Studio walk with a real character.

### v196 follow-up (shots 183-185)

On v196 (a7a68f3) `luau/mesh_stand` reported the barrel, well, crate and stile as "walked through". Every one of them had
CanCollide on and its fidelity applied (the probe reads `CollisionFidelity` off the placed MeshPart) and the stand ball rested on
top of each, so collision existed. The fails came from the probe: it forced 30 studs/s with free vertical motion and judged only
which side of the centre the ball ended on, so the 4-stud ball rode over the 3-4 stud barrel, crate and stile treads, and slid
round the round Hull of the barrel and well. Fixes: the barrel, well and stile are `Box` now (flat faces a walker stops against;
the stile is a block players jump onto, so `ranch_barn_loft` is the only PCD), and the probe drives at walking speed (16) with
upward velocity clamped and FAILs only when the ball's core overlaps the mesh's collision geometry (`GetPartsInPart`).

## B9: every prop has an explicit collision choice (`tests/PropCollision`)

`tests/PropCollision.luau` (test data only, it does not ship) is the machine-readable inventory of every collidable or solid-looking prop, both halves (Jolt: the
shared world; Gojo: plot-level props; the per-plot mailbox slot is "ambiguous"): one entry per kind with its mesh, count, owner,
the collision choice (a `MeshAssets.COLLISION` fidelity, `colliders` or `off`) and a reason. `tests/PropCollision.spec` keeps it
honest against `MeshAssets.COLLISION`, `WorldLayout.build()` (every placed mesh is listed, the rest are `UNPLACED` with a reason) and
the booted world (instance counts, a collidable part per non-"off" entry, the mesh fidelity MeshSwap actually asks for, no spawn or
other prop's centre inside a solid). The play probe `tools/pipeline/pc-watcher/luau/b9_prop_walk` (shot 223 `b9-prop-walk`) reads the
same list: it walks an R15 dummy into each prop from +-X / +-Z and fails Jolt's (and already-collidable Gojo) props that the
dummy ends inside or passes through. `tests/PropWalk.spec` is the same walk-in check as a spec that also runs in the cloud tests
(`tools/pipeline/cloud-test.sh`, no Studio): in both runtimes it builds a collision volume per blocking entry from `WorldLayout.build()`
(slot bbox for Box / Hull / PCD, the part boxes for colliders), walks a 2 x 5 x 1 character box at 16 studs/s in 1/60 s steps from
+-X / +-Z and asserts the first blocked step is at the face, and that no spawn, walk-path waypoint, slide exit, shop front or other
prop's ground position lies in a volume; in the cloud it also makes each fidelity mesh with `CreateMeshPartAsync` and `Blockcast`s the
same box at it (and at the collider parts). Nothing in the probe or the spec relies on the plot lock ejecting anyone (the lock is a
one-way barrier). To add a prop, append an entry; neither the spec nor the probe needs an edit.

What B9 found and changed on Jolt's half (the 92 Jolt kinds were all reviewed; almost everything was already solid
after #11 / #16 / #10):

- **Top Earners board.** The Model's invisible `Collider` was 15 x 17 x 1.6 under a 20.6 x 19.5 x 4.1 skin (`phoenix_top_earners_board`),
  so 2.8 studs on each side of the board were walkable. `MeshSwap.swap` now widens the `Collider` of a skinned Model that
  has one to the skin's width and height (depth and front stay, the skin is flush with them). The mesh stays out of `MeshAssets.COLLISION` because the same mesh is each plot's SlimeDex skin (Gojo's,
  stays decor).
- **Trees, rocks, hills, hedges, fences of the border (72 pieces, 30 giant trees, the 30-tree ring):** all `CanCollide = false` and
  that is right: every piece sits behind the 48-block wall ring (`WorldBorder.RADIUS` 292, 80 studs tall, inner face at r 292; the
  nearest piece footprint starts at r >= 290, which is a round hill's empty bounding-box corner). Players cannot reach them, so no
  trunk collider or hull is added (zero parts). `PropCollision.spec` re-computes every piece's footprint from `WorldBorder.pieces()`
  and fails if one comes inside r 289. The one border piece that already collides (the windmill accent) keeps its Hull.
- **World decor, signs, podiums, shop stands, vat, barn, loft, windmill, wagons, barrels, crates, stiles:** unchanged, already `Box` /
  `Hull` / `PreciseConvexDecomposition` (see Conversions above). The decor boulders (45) and mushrooms (15) are primitives that
  collide on their own.
- **Fountain tower (22 colliders), slide colliders (257, 270 since the supports), StackGuard:** untouched, only inventoried.

Left off on purpose (reason per kind in `PropCollision`): meadow grass, flowers and half-sunk pebbles (ground cover), the
sunflower / pumpkin patches and horseshoe pit (COLLISION.md: patches stay passable), the ritual circle's flat markings, the
slime ride stand-ins and the fountain's hidden stand-ins, the parade lane strip. `ranch_landing_ring` and `ranch_goo_drain` were
left off as decisions for Merijn; he decided they are solid, see the last section (hand colliders, not a mesh fidelity).

## Plot-level audit (B9)

Every plot mesh slot has a decided collision (`tests/MeshCollision.spec` "B9: plot-level collision"): fence panels, fence
segments and the gate-side corner post are `Box`; `merge_vat` is `Hull`; no PCD on a plot. `phoenix_gate` stays decor (a Box would
close the 14-stud opening): its `GatePostL` / `GatePostR` stand-ins keep collision after the mesh lands. `phoenix_pad_crate`
is decor: `Pad_<j>` (8 x 2.4 x 8) is the solid, steppable surface. `phoenix_top_earners_board` is shared with the world board
(own Collider), so the plot's `DexMesh` slot box (canCollide on, canQuery / canTouch off) is the dex board's collider.
Client-toggled cosmetics (LockBarrier panels, LockSign, RebirthDecor, habitats, skins, rain magnet) stay non-colliding: hidden
colliders would be invisible walls, and the Pad / PlotLockGuard already cover those areas.

## B9 follow-up: the landing ring and the goo drain are solid (Merijn: nobody walks through any object)

Both meshes stay decor in `MeshAssets.COLLISION` (the slot boxes are 10 studs deep and 3.1 tall, a `Box` or `Hull` would be
an invisible wall round the fountain and a corner-heavy block on the slide exit). The solids are thin invisible Parts,
`server/PlazaColliders` under `Map.Plaza.PlazaColliders`, from `WorldLayout.plazaColliders()` (runtime, so the 1400 layout
parts budget is not spent; +25 runtime parts, 2349 to 2374). `PropCollision`: `landing_ring` and `goo_drain` are
`colliders`, found through the mesh slot plus `also`.

- **Ring (22 parts).** One 12 x 1.3 x 1.7 box per tile on the real stones (kit `ranch_landing_ring`: r 34..35.7, 1.25 +- 0.08 tall,
  three stones per tile) and one 0.8 x 2.6 x 0.8 post for the wood stake at the tile's -X end (kit angle -9.4 deg; kit x is world x,
  FBX axes -Z forward / Y up). The curb is a **step-over, top 1.3 studs (limit 1.5)**: a Humanoid steps up to its hip height
  (~2) without jumping, and a landed player at the curb is never stuck. The ring is not closed anyway: the seven gap tiles
  (yaw 310..90, tiles 16, 17, 18, 1..5) have no collider, so the slide mouth and the lane start are open ground. Only the stakes
  are taller than a step, and they are thin posts a walker goes round.
- **Drain (3 parts).** `DrainCurb` is one 1.22-tall, 8.8-wide disc over the curb ring and the funnel (kit curb 1.0 + 0.22 warning
  tiles), a step-over; `DrainPost` (0.7 x 4.2) and `DrainPlaque` (2.6 x 1.9 x 0.35) stand on the fountain side. The lane ends one
  slime radius outside the curb (`ParadeLane.DRAIN`, lipRadius 4.4) and the lead-in from the slide mouth turns west (-X) long before the drain, so the exit and the lane never meet the post.
- **Slimes.** Wild slimes never collide (`SlimeMesh` CanCollide false, CFrame-stepped by `ParadeView` / `FountainRide`), so the lane,
  the hop onto the lip and the sink do not touch these parts.
- **Tests.** `tests/PropWalk.spec` "landing exit" (both runtimes: solid, gap, step heights, BFS and straight walks out of the slide
  mouth and the landing area to r > 46.8, the slime paths clear of the volumes) and, in the cloud, Blockcast against the real
  collider Parts.
- **Studio check.** The curb steps: walk radially over a tile at 16 studs/s without a jump or a stall; the stake side (mirrored
  stake = an invisible post 12 studs off); the drain disc against the funnel visual; no player stands in the plaque.
