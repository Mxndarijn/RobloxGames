# v28: assets that would need uploading (nothing uploaded)

v28 item 2 ("SlimeDex images look awful") ships **without any new upload**.
The repo has no uploaded slime image / decal IDs (only meshes in
`src/shared/MeshAssets.luau`), so each SlimeDex row now shows a
**ViewportFrame render of the real slime model**: `Visuals.ModelFactory.build`
(the same builder as the in-world slimes) fed a display genome from
`SlimeDex.genome(row)`. If that fails, the row falls back to the
SlimePreview blob, then to the colour swatch. Undiscovered tiers render the
tier's model as a dark silhouette with a "?".

Pre-rendered thumbnails would be cheaper than live viewports (the Dex caps
live viewports at `SlimePreview.MAX_LIVE`; rows past that get the swatch).
If Merijn wants them, upload these and fill `SlimeDex.IMAGES` in
`src/ui/SlimeDex.luau` (key -> `"rbxassetid://<id>"`). `SlimeDex.image` already
prefers an exact dex key, then `"<tier>:<mutation>"`, so the per-tier/mutation
set below covers every row.

| File (PNG, 256x256, transparent background, slime front 3/4 view) | `SlimeDex.IMAGES` key |
|---|---|
| `dex_<tier>_None.png` for tier 1..6 | `"<tier>:None"` |
| `dex_<tier>_<Mutation>.png` for every `Config.MUTATIONS` id, tier 1..6 | `"<tier>:<Mutation>"` |
| `dex_locked.png` (dark silhouette, optional) | not keyed: locked rows keep the viewport silhouette |

Menu icons (v28 item 1) use emoji text, so they need no upload either.
Possible later polish: a 64x64 icon set (shop items, nav, Guide) as
ImageLabels in place of emoji.
