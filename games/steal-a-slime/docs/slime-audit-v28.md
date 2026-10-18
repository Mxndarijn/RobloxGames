# Slime audit v28 (TODO 15)

Date: 2026-10-16. Scope: every `SlimeRoster` type (29 spawnable in tiers 1-6, plus 2 Secret). Checked against `src/shared/MeshAssets.luau`, `Config.SLIME_MESH_ASSET_ID`, `src/visuals/shared/SlimeLayout.luau` (body material) and the slime animation controller `src/visuals/client/init.client.luau` (`step`). Guarded by `tests/SlimeLooks.spec.luau`.

## What was there before this audit

- **Mesh:** every slime uses one shared package mesh (`Config.SLIME_MESH_ASSET_ID` = 103340234939607, loaded by server `SlimeMesh`; procedural ball fallback). That id is real, not a placeholder. None of the per-type kit meshes (`slime_base`, `slime_acc_leaf`, `slime_ears`, `slime_horns`, `slime_acc_crown`, `slime_acc_crystal`, `slime_wobble`) is in `MeshAssets` or `shared/modeling-kit/uploaded.json`. The FBX files exist in `shared/modeling-kit/out/`. No texture ids: slimes are coloured parts, there is no TextureID to check.
- **Colour / material:** a typed slime got its name from the roster but a **random** colour, and its material was always SmoothPlastic. No type had a colour or material entry. This was the gap.
- **Animations:** slimes are not rigs and there are no AnimationIds. The visuals client plays procedural states on every `Slime`-tagged model, whatever the type: **idle** = bob (`sin(t*3)`, 0.08 x Size) on Pad / Wild, **wobble** = tilt (`sin(t*2.2)`, 0.04 rad) on Pad / Wild plus a fast wriggle while Carried, **move** = hop (`|sin(t*7)|`, 1.6 x Size) while Escaping. So all three states are wired and played for every type, by the procedural fallback.

## Fixed in this PR

- `src/shared/SlimeLooks.luau` (new): colour, Enum.Material name and kit mesh name for every roster id, plus `SlimeLooks.anim(id, "idle" | "wobble" | "move")`. It resolves to the procedural profile, using the same numbers as the controller.
- `Genome.generate`: a typed wild spawn now wears its type's colour. The random colour roll is still drawn, so the rest of the genome stays seed-stable. Saves are unchanged: `color` is already saved per slime, and no save id changed.
- `SlimeMesh.build` (server): sets the `Species` attribute (`Constants.SPECIES_ATTRIBUTE`, CONTRACT §8.4) and the type material on `Body` and `Mesh`.
- `tests/SlimeLooks.spec.luau`: iterates the roster and asserts a colour, a valid material, a kit name and resolvable idle / wobble / move for each type. It also checks that the controller source really plays those states with those numbers, and covers the colour and Species wiring.

## Table

Mesh = kit mesh and whether it is uploaded (v28 slime meshes; `slime_base` / `slime_ears` / `slime_horns` / `slime_wobble` are the body, `slime_acc_*` sit on a `slime_base` body; the shared package is the fallback). Material = SlimeLooks body colour and material (unmutated). proc = procedural fallback played by VisualsClient.

| type | tier | mesh | texture / material | idle | wobble | move | status |
|---|---|---|---|---|---|---|---|
| pudding (Pudding Slime) | 1 | slime_base ✅ uploaded | rgb(240,196,92) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| clover (Clover Slime) | 1 | slime_base ✅ uploaded | rgb(108,196,92) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| oatmeal (Oatmeal Slime) | 1 | slime_base ✅ uploaded | rgb(222,200,160) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| radish (Radish Slime) | 1 | slime_base ✅ uploaded | rgb(236,110,150) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| puddle (Puddle Slime) | 1 | slime_base ✅ uploaded | rgb(96,168,236) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| haystack (Haystack Slime) | 1 | slime_base ✅ uploaded | rgb(230,196,80) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| sprout (Sprout Slime) | 2 | slime_acc_leaf ✅ uploaded | rgb(120,220,96) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| carrot (Carrot Slime) | 2 | slime_acc_leaf ✅ uploaded | rgb(244,140,48) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| berry (Berry Slime) | 2 | slime_acc_leaf ✅ uploaded | rgb(214,48,84) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| minty (Minty Slime) | 2 | slime_acc_leaf ✅ uploaded | rgb(150,236,200) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| pumpkin (Pumpkin Slime) | 2 | slime_acc_leaf ✅ uploaded | rgb(236,128,36) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| tulip (Tulip Slime) | 2 | slime_acc_leaf ✅ uploaded | rgb(246,140,180) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| bunny_puff (Bunny Puff) | 3 | slime_ears ✅ uploaded | rgb(250,214,220) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| caramel_kitty (Caramel Kitty) | 3 | slime_ears ✅ uploaded | rgb(206,140,70) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| moo_goo (Moo Goo) | 3 | slime_ears ✅ uploaded | rgb(245,245,240) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| piglet (Piglet Slime) | 3 | slime_ears ✅ uploaded | rgb(248,170,186) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| cocoa_pup (Cocoa Pup) | 3 | slime_ears ✅ uploaded | rgb(132,86,58) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| billy_gum (Billy Gum) | 4 | slime_horns ✅ uploaded | rgb(250,130,196) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| rodeo_ram (Rodeo Ram) | 4 | slime_horns ✅ uploaded | rgb(240,228,204) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| licorice_bull (Licorice Bull) | 4 | slime_horns ✅ uploaded | rgb(40,34,40) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| toffee_buck (Toffee Buck) | 4 | slime_horns ✅ uploaded | rgb(170,108,52) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| sour_apple (Sour Apple Imp) | 4 | slime_horns ✅ uploaded | rgb(160,230,60) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| honey_queen (Honey Queen) | 5 | slime_acc_crown ✅ uploaded | rgb(246,176,40) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| harvest_king (Harvest King) | 5 | slime_acc_crown ✅ uploaded | rgb(228,196,104) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| blue_ribbon (Blue Ribbon) | 5 | slime_acc_crown ✅ uploaded | rgb(52,100,220) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| marshmallow_duke (Marshmallow Duke) | 5 | slime_acc_crown ✅ uploaded | rgb(252,248,244) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| rock_candy (Rock Candy) | 6 | slime_acc_crystal ✅ uploaded | rgb(200,168,240) Glass | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| dewdrop_spirit (Dewdrop Spirit) | 6 | slime_acc_crystal ✅ uploaded | rgb(120,230,236) Glass | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| gumdrop_titan (Gumdrop Titan) | 6 | slime_acc_crystal ✅ uploaded | rgb(220,30,60) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| golden_goose_goo (Golden Goose Goo) | S | slime_wobble ✅ uploaded | rgb(255,200,60) Foil | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |
| moonmilk (Moonmilk) | S | slime_ears ✅ uploaded | rgb(36,44,110) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | DONE (mesh) |

**Status:** 31 / 31 types have colour, material, idle, wobble and move, and 31 / 31 have their own kit mesh, uploaded and wired in server `SlimeMesh` (DONE for the mesh). Only the real-animation, client-preview and Secret-spawn items below remain.

## Done: kit meshes (v28 slime meshes)

- The 7 kit meshes are uploaded (`shared/modeling-kit/uploaded.json`) and in `MeshAssets` (assetId, meshId, native size).
- `SlimeMesh.load` fetches each kit by assetId next to the shared package (in parallel, so server start waits on one load); `SlimeMesh.build` dresses the slime with its type's body kit, fitted uniformly into Body, plus the accessory on top for leaf / crown / crystal types.
- Fallback chain per slime: kit -> shared package mesh -> procedural ball. A failed accessory leaves the body only. Save ids are unchanged.
- Mesh budget: the kits are cloned per slime, not world `MeshAsset` slots, so `WorldLayout.MESH_SLOT_BUDGET` (400) is unchanged (`tests/WorldBudget.spec` asserts no kit is a world slot).
- Accessory colour = body colour (no separate accessory material yet).

## LEFT (needs art, uploads or another owner)

1. **Real animations (optional):** only if wanted beyond the procedural states. Slimes would need a rig and uploaded AnimationIds; then `SlimeLooks.anim` returns `source = "Animation"` (the test already requires a real `rbxassetid` for that case).
2. **Archer (src/visuals):** `SlimeLayout.bodyLook` could read `SlimeLooks.get(slime.species).material`, so ViewportFrame previews and follow pets (built client-side with ModelFactory) show Glass / Foil types like the server models do. The colour already flows through `slime.color`.
3. **Secret types** (`golden_goose_goo`, `moonmilk`) have looks but never spawn: there is no Secret rarity in `Config.RARITIES`.
