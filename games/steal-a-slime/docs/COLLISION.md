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
  many parts it costs. Not done here.
- The slide block: walk the whole outline at the mouth, under the posts and beside the upper laps;
  nobody gets onto the top (11 studs above the ride line) and nobody is stuck in a corner.
- `tools/pipeline/pc-watcher/luau/slide_walk.luau` was written for the old walkable floor (balls
  dropped on `SlideFloor<i>`); with the fill on top they land on its top face. Adjust the shot.

## The ground (bugs #13-15)

The inner ground is voxel Terrain (`GroundTerrain`, flat at y = 0): Terrain collides by itself, so it has no mesh,
`MeshAssets.COLLISION` entry or collider part. The invisible `Map.Ground` part under it stays as the void-safety floor.

## Conversions (bug #11 part 1)

`MeshAssets.COLLISION` is the single list; one reason per mesh sits next to its line there. Summary:

| Fidelity | Meshes |
|---|---|
| `Box` | `slime_fountain_emerge` (bug #10, main), `ranch_fence_20`, `phoenix_fence_segment`, `phoenix_corner_post` (the plot fence), `ranch_plaza_signpost`, `phoenix_plaza_podium_1..3`, `ranch_crate`, `ranch_crate_goo`, `ranch_feed_trough`, `ranch_hay_bale`, `ranch_bench`, `ranch_compost_bin`, `ranch_flower_planter`, `ranch_goo_sign`, `ranch_hitching_post`, `ranch_mailbox`, `ranch_picnic_table`, `ranch_tool_rack`, `ranch_wagon`, `ranch_water_trough` |
| `Hull` | `merge_vat`, `ranch_shop_stand` (already), `ranch_barrel`, `ranch_barrel_stack`, `ranch_birdhouse`, `ranch_campfire`, `ranch_feed_sacks`, `ranch_goo_bucket`, `ranch_goo_hive`, `ranch_log_pile`, `ranch_milk_churn`, `ranch_rain_barrel`, `ranch_scarecrow`, `ranch_shed`, `ranch_slime_coop`, `ranch_water_pump`, `ranch_weathervane`, `ranch_well`, `ranch_wheelbarrow`, `ranch_windmill` |
| `PreciseConvexDecomposition` | `ranch_fence_stile` (steps), `ranch_barn_loft` (loft over an open floor). Both marked "PCD: Phoenix Studio check" |
| none (decor) | `slime_fountain` (tower, hand colliders stay), `phoenix_gate` (a Box/Hull would close the 14-stud opening; its GatePost stand-ins keep the posts; PCD is the later mesh route), `phoenix_pad_crate` (the Pad part is the surface), `phoenix_top_earners_board` (Model with its own Collider), `ranch_landing_ring`, `ranch_goo_drain`, `ranch_horseshoe_pit`, `ranch_lantern_post`, `ranch_pumpkin_patch`, `ranch_sunflower_patch`, `ranch_border_*`, `giant_*`, `habitat_*`, `plot_skin_*`, `fountain_tier_*`, `rain_magnet`, every slime kit mesh, `slime_lane` |

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
- **PCD walkability.** Walk a character up and over `ranch_fence_stile` and under / onto `ranch_barn_loft`; check the generated
  collision exists at all for the scaled mesh (the engine may fall back to a coarser one), and the physics step cost.
- **Stand-on surfaces and fall-through.** Stand on the three podiums (rigs from `PodiumRigs`), crates, wagon, picnic table, shed
  roof ledge: no fall-through, no float above the visual top, no stuck feet in a Hull's filled concavity.
- **Fence.** Walk the whole fence line of one plot, corner to gate: no gap at joints, corners or the gate stubs; the gate opening
  stays open; if a `Box` mesh fails to generate, the placeholder box (same footprint) is the fallback.
- **Pass-through and clearance.** The walk-through `ranch_*` decor (patches, pit, border, habitats) stays passable.
- Shots `183-bug11-hull-stand`, `184-bug11-box-stand`, `185-bug11-pcd-stand` (`luau/mesh_stand`) drop and push balls at these
  meshes; they do not replace a Studio walk with a real character.
