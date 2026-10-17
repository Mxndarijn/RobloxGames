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

## Players solid, slimes not: the slide

The fountain slide is part of the one `slime_fountain` MeshPart, which cannot be split into slide
and silo, so real mesh collision cannot say "slime yes, player no" for the slide alone. It also
would be wrong: a precise slide collision makes the trough walkable, which is the bug (#9).
So the slide keeps hand-placed collision (`shared/SlideColliders`), but as a **solid block** (a
floor slab plus a fill up to `FILL` = 11 studs above the ride line, more than a jump) so nobody can
enter or climb it. Wild slimes ride it anchored with `CanCollide = false` (`FountainRide`): they
pass through the block, so no collision group is needed.

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

- `slime_fountain_emerge` as `Hull`: walk and jump over the pile at the fountain top; nobody
  stands in a gap or gets launched out (the hull is convex, depenetration pushes out).
- `merge_vat` as `Hull` (bug #16, every plot's vat, `MeshSwap.swapPlotVats`): bump into the cauldron and the
  funnel spouts from all sides; nobody walks inside, the MergePrompt still triggers from the hull's edge.
- Whether `PreciseConvexDecomposition` on `slime_fountain` could retire the silo colliders and how
  many parts it costs. Not done here.
- The slide block: walk the whole outline at the mouth, under the posts and beside the upper laps;
  nobody gets onto the top (11 studs above the ride line) and nobody is stuck in a corner.
- `tools/pipeline/pc-watcher/luau/slide_walk.luau` was written for the old walkable floor (balls
  dropped on `SlideFloor<i>`); with the fill on top they land on its top face. Adjust the shot.
