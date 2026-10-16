# Slime habitats (spec)

**Status:** every type has its own uploaded mesh; `Config.FEATURES.Habitats = true`. **Date:** 2026-10-16. **Owners:** data + pad state Phoenix (`src/shared`, `src/server`), habitat FX Archer (`src/visuals`). Written by Jolt.

When a slime sits on a pad, the pad turns into that slime's habitat in about 1 s (tween + FX). When the pad empties (slime stolen, carried off, sold, merged, owner leaves) it turns back into the base pad.

## Data: `src/shared/Habitats.luau` (pure)

- **Habitat ids** are plain strings, never saved. `base` = the pad as built today (its `WorldLayout.PAD_MESHES` stand plus the kit's `pad_trim` plinth).
- **Lookup:** `Habitats.forSlime(slime)`: the per-type table (`TYPE`, by `SlimeRoster` id) wins, then the family of the slime's tier (`FAMILY_BY_TIER` -> `FAMILY`), else `base`. Merged / pre-v28 slimes have no `species`, so they fall back to their tier's family.
- **Looks are per-type kit meshes** (`shared/modeling-kit/models/habitat_<id>.py`, ids in `MeshAssets`, `uploaded.json`): 7.8 wide, 3.6-5.0 tall, seat 2.4 (FOUNTAIN_SIZES.md). `base` keeps the pad stand + `pad_trim`.

| Habitat | Kit look | Seat | Used by |
|---|---|---|---|
| `base` | pad's own stand + `pad_trim` | (pad) | empty pad, flag off |
| `hay_nest` | `habitat_hay_nest` | 2.4 | family field (Common); `golden_goose_goo` |
| `mushroom_ring` | `habitat_mushroom_ring` | 2.4 | `clover`, `moonmilk` |
| `flower_bed` | `habitat_flower_bed` | 2.4 | family sprout (Uncommon) |
| `barn_crate` | `habitat_barn_crate` | 2.4 | family critter (Rare) |
| `rodeo_barrel` | `habitat_rodeo_barrel` | 2.4 | `rodeo_ram` |
| `syrup_pool` | `habitat_syrup_pool` | 2.4 | `pudding`, `puddle`, `honey_queen` |
| `show_stool` | `habitat_show_stool` | 2.4 | family royal (Legendary) |
| `candy_patch` | `habitat_candy_patch` | 2.4 | family horned (Epic); `gumdrop_titan` |
| `crystal_grotto` | `habitat_crystal_grotto` | 2.4 | family crystal (Mythic), family secret |

## Server owns pad state: `src/server/HabitatPads.luau` (pure) + `WorldView.updatePlots`

- Each view tick the server works out every pad's target: the slime whose `pad` is that pad and whose Scene state is `Pad` (not carried, not escaping) gives `forSlime(slime)`; anything else is `base`. Free plots are all `base`.
- On a change it stamps the pad and `WorldView` writes three attributes on `Pad_<j>` (`Constants.HABITAT_*`): `Habitat` (id), `HabitatFrom` (previous id), `HabitatAt` (server time of the change). Nothing is saved and no remote is added.
- The server never waits for the animation: gameplay (income, steal prompt, pad top height) is unchanged. The pad part keeps its size; a habitat look is placed so its seat sits on the pad top.

## Client animates: `src/visuals/client/HabitatFx.luau`

- One local look per habitat per pad (folder `workspace.ClientHabitats`, CanCollide / CanQuery / CanTouch off). Each look has a weight 0..1 that moves toward 1 (current `Habitat`) or 0 (any other) at `1 / TRANSFORM_SECONDS` (1 s): scale + fade, a sparkle burst when a transform starts, and the base stand fades out locally (`LocalTransparencyModifier`) while a habitat shows. Revert is the same tween backwards.
- Weights live in `Habitats.stepWeights` (pure, Lune-tested).

## Edge cases

- **Steal mid-transform:** the server flips the pad straight to `base` (`HabitatFrom` = the half-grown habitat). The client tweens the half-grown look back down from where it was; it ends at `base`.
- **Rapid swap** (slimes swapped / merged within 1 s): only the latest `Habitat` is a target; every older look shrinks to 0. Ends at the latest.
- **Join in progress / pad streams in:** the first time a client sees a pad it snaps to the final state (`Habitats.initialWeights`), no animation or FX.
- **Owner leaves / plot freed:** every pad of that plot goes `base`.
- **Flag off:** the server never sets the attributes and `HabitatFx` never starts, so no parts, folders or attributes exist and behaviour is identical to v27 (tests: `Habitats.spec`, `LiveBoot.spec`).

## Mesh slots Archer must fill (new meshes)

Same slot rules as the pad kit (`models/_phoenix_pad.py`): footprint <= 7.96 x 7.96 (aim 7.8), flat seat for the slime, 1 Blender unit = 1 stud, tight tri budget (up to 64 pads per map).

| Slot | Kit name | Size (W x H x D studs) | Seat | Look |
|---|---|---|---|---|
| `crystal_grotto` | `habitat_crystal_grotto` | 7.8 x 5.0 x 7.8 | 2.4 | rock bowl with a flat stone seat; lilac / aqua crystal clusters on the rim only (keep the seat area clear up to 5.0) |
| `candy_patch` | `habitat_candy_patch` | 7.8 x 4.5 x 7.8 | 2.4 | sugar-soil mound with gumdrops and two lollipops at the rim, flat biscuit seat |

Both models landed (Archer #57, `shared/modeling-kit/out/habitat_*.fbx`) but are **not uploaded**: `MeshAssets` lists them with sizes and no `meshId`. `Habitats.slotMesh(id)` returns the slot's meshId + native size once one is filled in, and `HabitatFx` then draws it (FileMesh SpecialMesh, Y fit so the 2.4 seat meets the pad top); until then both draw primitive placeholders. The seven kit pads are already uploaded; swapping their meshes into `HabitatFx` is a follow-up (MeshSwap is server-side today).

## All habitats uploaded

All nine looks are uploaded (Open Cloud, see `uploaded.json`) and wired in `MeshAssets`; `Habitats.slotMesh` draws them for every id. `tests/Habitats.spec` checks each type maps to a mesh id with a 7.8 footprint and seat 2.4. `tools/pipeline/pc-watcher/shots.json` has a mid-morph and a done shot per habitat (TODO 16).
