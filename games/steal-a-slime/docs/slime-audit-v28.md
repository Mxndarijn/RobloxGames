# Slime audit v28 (TODO 15)

Date: 2026-10-16. Scope: every `SlimeRoster` type (29 spawnable in tiers 1-6, plus 2 Secret). Checked against `src/shared/MeshAssets.luau`, `Config.SLIME_MESH_ASSET_ID`, `src/visuals/shared/SlimeLayout.luau` (body material) and the slime animation controller `src/visuals/client/init.client.luau` (`step`). Guarded by `tests/SlimeLooks.spec.luau`.

## What was there before this audit

- **Mesh:** every slime uses one shared package mesh (`Config.SLIME_MESH_ASSET_ID` = 103340234939607, loaded by server `SlimeMesh`; procedural ball fallback). That id is real, not a placeholder. None of the per-type kit meshes (`slime_base`, `slime_acc_leaf`, `slime_ears`, `slime_horns`, `slime_acc_crown`, `slime_acc_crystal`, `slime_wobble`) is in `MeshAssets` or `shared/modeling-kit/uploaded.json`. The FBX files exist in `shared/modeling-kit/out/`. No texture ids: slimes are coloured parts, there is no TextureID to check.
- **Colour / material:** a typed slime got its name from the roster but a **random** colour, and its material came only from its mutation (SmoothPlastic when unmutated). No type had a colour or material entry. This was the gap.
- **Animations:** slimes are not rigs and there are no AnimationIds. The visuals client plays procedural states on every `Slime`-tagged model, whatever the type: **idle** = bob (`sin(t*3)`, 0.08 x Size) on Pad / Wild, **wobble** = tilt (`sin(t*2.2)`, 0.04 rad) on Pad / Wild plus a fast wriggle while Carried, **move** = hop (`|sin(t*7)|`, 1.6 x Size) while Escaping. So all three states are wired and played for every type, by the procedural fallback.

## Fixed in this PR

- `src/shared/SlimeLooks.luau` (new): colour, Enum.Material name and kit mesh name for every roster id, plus `SlimeLooks.anim(id, "idle" | "wobble" | "move")`. It resolves to the procedural profile, using the same numbers as the controller.
- `Genome.generate`: a typed wild spawn now wears its type's colour. The random colour roll is still drawn, so the rest of the genome stays seed-stable. Saves are unchanged: `color` is already saved per slime, and no save id changed.
- `SlimeMesh.build` (server): sets the `Species` attribute (`Constants.SPECIES_ATTRIBUTE`, CONTRACT §8.4) and, on unmutated typed slimes, the type material on `Body` and `Mesh`. A mutation material still wins.
- `tests/SlimeLooks.spec.luau`: iterates the roster and asserts a colour, a valid material, a kit name and resolvable idle / wobble / move for each type. It also checks that the controller source really plays those states with those numbers, and covers the colour and Species wiring.

## Table

Mesh = intended kit mesh and whether it is uploaded (all types render with the shared package today). Material = SlimeLooks body colour and material (unmutated). proc = procedural fallback played by VisualsClient.

| type | tier | mesh | texture / material | idle | wobble | move | status |
|---|---|---|---|---|---|---|---|
| pudding (Pudding Slime) | 1 | slime_base ❌ not uploaded | rgb(240,196,92) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| clover (Clover Slime) | 1 | slime_base ❌ not uploaded | rgb(108,196,92) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| oatmeal (Oatmeal Slime) | 1 | slime_base ❌ not uploaded | rgb(222,200,160) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| radish (Radish Slime) | 1 | slime_base ❌ not uploaded | rgb(236,110,150) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| puddle (Puddle Slime) | 1 | slime_base ❌ not uploaded | rgb(96,168,236) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| haystack (Haystack Slime) | 1 | slime_base ❌ not uploaded | rgb(230,196,80) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| sprout (Sprout Slime) | 2 | slime_acc_leaf ❌ not uploaded | rgb(120,220,96) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| carrot (Carrot Slime) | 2 | slime_acc_leaf ❌ not uploaded | rgb(244,140,48) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| berry (Berry Slime) | 2 | slime_acc_leaf ❌ not uploaded | rgb(214,48,84) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| minty (Minty Slime) | 2 | slime_acc_leaf ❌ not uploaded | rgb(150,236,200) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| pumpkin (Pumpkin Slime) | 2 | slime_acc_leaf ❌ not uploaded | rgb(236,128,36) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| tulip (Tulip Slime) | 2 | slime_acc_leaf ❌ not uploaded | rgb(246,140,180) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| bunny_puff (Bunny Puff) | 3 | slime_ears ❌ not uploaded | rgb(250,214,220) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| caramel_kitty (Caramel Kitty) | 3 | slime_ears ❌ not uploaded | rgb(206,140,70) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| moo_goo (Moo Goo) | 3 | slime_ears ❌ not uploaded | rgb(245,245,240) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| piglet (Piglet Slime) | 3 | slime_ears ❌ not uploaded | rgb(248,170,186) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| cocoa_pup (Cocoa Pup) | 3 | slime_ears ❌ not uploaded | rgb(132,86,58) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| billy_gum (Billy Gum) | 4 | slime_horns ❌ not uploaded | rgb(250,130,196) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| rodeo_ram (Rodeo Ram) | 4 | slime_horns ❌ not uploaded | rgb(240,228,204) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| licorice_bull (Licorice Bull) | 4 | slime_horns ❌ not uploaded | rgb(40,34,40) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| toffee_buck (Toffee Buck) | 4 | slime_horns ❌ not uploaded | rgb(170,108,52) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| sour_apple (Sour Apple Imp) | 4 | slime_horns ❌ not uploaded | rgb(160,230,60) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| honey_queen (Honey Queen) | 5 | slime_acc_crown ❌ not uploaded | rgb(246,176,40) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| harvest_king (Harvest King) | 5 | slime_acc_crown ❌ not uploaded | rgb(228,196,104) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| blue_ribbon (Blue Ribbon) | 5 | slime_acc_crown ❌ not uploaded | rgb(52,100,220) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| marshmallow_duke (Marshmallow Duke) | 5 | slime_acc_crown ❌ not uploaded | rgb(252,248,244) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| rock_candy (Rock Candy) | 6 | slime_acc_crystal ❌ not uploaded | rgb(200,168,240) Glass | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| dewdrop_spirit (Dewdrop Spirit) | 6 | slime_acc_crystal ❌ not uploaded | rgb(120,230,236) Glass | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| gumdrop_titan (Gumdrop Titan) | 6 | slime_acc_crystal ❌ not uploaded | rgb(220,30,60) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| golden_goose_goo (Golden Goose Goo) | S | slime_wobble ❌ not uploaded | rgb(255,200,60) Foil | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |
| moonmilk (Moonmilk) | S | slime_ears ❌ not uploaded | rgb(36,44,110) SmoothPlastic | ✅ proc | ✅ proc | ✅ proc | PARTIAL: mesh LEFT |

**Status:** 31 / 31 types have colour, material, idle, wobble and move. 0 / 31 have their own kit mesh. All of them are PARTIAL because the kit meshes are LEFT.

## LEFT (needs art, uploads or another owner)

1. **Upload kit meshes** `slime_base`, `slime_acc_leaf`, `slime_ears`, `slime_horns`, `slime_acc_crown`, `slime_acc_crystal`, `slime_wobble` (FBX in `shared/modeling-kit/out/`). Then add them to `MeshAssets` and make `SlimeMesh` pick the template by `SlimeLooks.get(species).kit` instead of the single package. This needs an Open Cloud upload, so it is not done here.
2. **Real animations (optional):** only if wanted beyond the procedural states. Slimes would need a rig and uploaded AnimationIds; then `SlimeLooks.anim` returns `source = "Animation"` (the test already requires a real `rbxassetid` for that case).
3. **Archer (src/visuals):** `SlimeLayout.bodyLook` could read `SlimeLooks.get(slime.species).material`, so ViewportFrame previews and follow pets (built client-side with ModelFactory) show Glass / Foil types like the server models do. The colour already flows through `slime.color`.
4. **Secret types** (`golden_goose_goo`, `moonmilk`) have looks but never spawn: there is no Secret rarity in `Config.RARITIES`.
