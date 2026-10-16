# v28 living slimes (TODO #17): rig and animations

The idle life ships in two forms, both client-only and chosen per slime by `src/ui/SlimeLifeRunner.client.luau`:

- **Animated (new):** the slime rig plus four uploaded animations. Used when the slime has its Animator and `MeshAssets.ANIMATIONS` has all four ids.
- **Procedural (kept as fallback):** `src/ui/SlimeLife.luau` (LifeRoot welds, skin Size squash). Runs when an id is missing, the slime has no Animator or loading a track fails.

Both share the LOD: nearest `SlimeLife.MAX_ACTIVE` (16) slimes within 80 studs and on screen (`Candidate.onScreen`).

## What exists

- **Rig** (`src/visuals/shared/SlimeRig.luau`, called by `ModelFactory.build`): Motor6Ds `FaceRoot` and `SkinRoot` from `Body`, an `AnimationController` + `Animator`. Eyes and mouth are welded to FaceRoot, every other decoration and the mesh look (`SlimeMesh` Mesh / Accessory) to SkinRoot. Body stays anchored, the PrimaryPart and the prompt target.
- **Mesh:** the four kit body meshes (`slime_base`, `slime_ears`, `slime_horns`, `slime_wobble`) now export with a `Root` + `Squash` armature (`models/_slime.py rig_squash`; FBX in `shared/modeling-kit/out`). **Not re-uploaded:** the skinned import is untested in Studio, so the live mesh ids still point at the unskinned meshes.
- **Animations** (`animations/*.rbxmx`, made by `tools/gen_slime_animations.py`): `SlimeIdleSquish` (2.5 s loop), `SlimeHop` (0.75 s), `SlimeLookLeft` / `SlimeLookRight` (0.4 s). Uploaded through the Open Cloud Assets API (assetType `Animation`, `.rbxmx`); ids in `shared/modeling-kit/uploaded.json` and `MeshAssets.ANIMATIONS`. `SlimeBlink` is not made: the eyes are separate parts without a lid.
- **Pets:** `PetRig.stripLife` also removes the Animator, resets Motor6D transforms and drops the sparkle.

## Studio checks still needed (nobody ran Studio)

1. Do the animations load and play? They were written by a script, not saved from Studio (the docs warn that such .rbxm may not work). Play one on a slime (`tools/pipeline/pc-watcher` shots `17-anim-*`).
2. Does an Animator on the anchored slime move FaceRoot / SkinRoot (Motor6D `Transform`) while VisualsClient's per-frame `PivotTo` runs, with no drift or jitter, at 16 rigs on a phone?
3. Skinned mesh: upload the new FBX with `upload.py --update`, check that LoadAsset + `CreateMeshPartAsync` keep the Bones, then the `Squash` pose in the animations (a Motor6D chain `SkinRoot > Mesh` may be needed for the Animator to find the Bone).
4. Animation ownership: the asset must be playable by the experience's owner (uploaded under user 1040646178).
