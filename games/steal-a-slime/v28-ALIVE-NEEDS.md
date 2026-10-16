# v28 living slimes (TODO #17): what's still needed

The idle life ships procedurally and client-only (`src/ui/SlimeLife.luau` and `src/ui/SlimeLifeRunner.client.luau`). It needs no animation assets. Nothing was created or uploaded.

## Optional assets (no blocker)

Slimes have no rig, `Humanoid`/`AnimationController` or `Animator`, so an `AnimationId` can't play on them today. Real animations would need all of the following:

- **Rig (Archer, ModelFactory/SlimeLayout):** Motor6Ds from `Body` to a face root and a skin root. Today all decorations use `WeldConstraint`s. Also an `AnimationController` + `Animator` on each slime model.
- **Animations (Archer, upload by whoever holds Open Cloud):** `SlimeIdleSquish` (loop, ~2.5 s), `SlimeHop` (~0.75 s), `SlimeLookLeft`/`SlimeLookRight` (~0.4 s), `SlimeBlink` (only if eyes become one mesh with a lid). Upload them as `Saved` assets only, then add the ids to `Shared.MeshAssets` or Config.
- **Skinned slime mesh:** a squash bone in the kit mesh, so the Mesh look squashes without a per-frame `Size` write.

The procedural version covers squish/bounce, hops, look-around and rarity wobble and sparkle. Rigging would only make these look nicer and cost less.

## Follow-ups for other owners

- **Archer, `FollowPets`:** clone the source slime after removing client-only children named `LifeRoot` (holds `LifeWeld`s and `LifeSparkle`) and `Body.LifeSquash`, and re-enable the disabled `WeldConstraint`s. A pet cloned while its slime is rigged otherwise keeps the frozen pose and the sparkles.
- **Archer, VisualsClient:** blinking is still VisualsClient's job (it blinks every tagged slime). SlimeLife doesn't touch the eyes. Its motion rides on top of VisualsClient's pivot bob/tilt.
- **Studio check (anyone with Studio, not done here):** confirm that `Weld.C0` writes on the anchored slime assembly render smoothly at 16 rigs on a phone. Also confirm that VisualsClient's per-frame `PivotTo` keeps the rigged decorations attached, with no drift or jitter.
