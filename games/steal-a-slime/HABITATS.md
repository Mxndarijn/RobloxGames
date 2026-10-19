# Slime habitats (spec)

**Status:** overlays; `Config.FEATURES.Habitats` is the only place the flag is set. **Owners:** data + pad state Phoenix (`src/shared`, `src/server`), habitat FX Archer (`src/visuals`).

The pad never changes. When a slime sits on a pad, that slime's habitat **overlay** rises out of the crate deck in about 1 s (a themed frame round the mat plus rim props round the slime). When the pad empties (slime stolen, carried off, sold, merged, owner leaves) the overlay sinks away and the bare crate pad is left. Swapping one slime for another crossfades the two overlays on the same pad.

## Data: `src/shared/Habitats.luau` (pure)

- **Habitat ids** are plain strings, never saved. `base` = the bare pad (the `WorldLayout.PAD_MESH` crate stand, no overlay).
- **Lookup:** `Habitats.forSlime(slime)`: the per-type table (`TYPE`, by `SlimeRoster` id) wins, then the family of the slime's tier (`FAMILY_BY_TIER` -> `FAMILY`), else `base`. Merged / pre-v28 slimes have no `species`, so they fall back to their tier's family.
- **Overlays are kit meshes** `habitat_<id>_overlay` (`shared/modeling-kit/models/habitat_<id>_overlay.py`, helpers `models/_habitat_overlay.py`; ids in `MeshAssets`, `uploaded.json`). `Habitats.overlayMesh(id)` gives the meshId, native size and `drop` (studs it hangs below the deck, for drips over the crate edge; usually 0).

| Habitat | Overlay | Used by |
|---|---|---|
| `base` | none (bare crate) | empty pad, flag off |
| `hay_nest` | straw frame, hay tufts, straws, an egg | family field (Common); `midas` |
| `mushroom_ring` | `habitat_mushroom_ring_overlay` | `mushie`, `boo` |
| `flower_bed` | `habitat_flower_bed_overlay` | family sprout (Uncommon); `sprout`, `prickles` |
| `barn_crate` | `habitat_barn_crate_overlay` | family critter (Rare) |
| `rodeo_barrel` | `habitat_rodeo_barrel_overlay` | `moo` |
| `syrup_pool` | `habitat_syrup_pool_overlay` | `flan`, `bubbles`, `froggo`, `chomp`, `octo` |
| `show_stool` | `habitat_show_stool_overlay` | family royal (Legendary) |
| `candy_patch` | `habitat_candy_patch_overlay` | family horned (Epic); `cheddar` |
| `crystal_grotto` | `habitat_crystal_grotto_overlay` | family crystal (Mythic), family secret |

## Overlay mesh rules (kit)

- z=0 = the crate deck (`WorldLayout.PAD_DECK.y` above the stand bottom). Frame + rim props only: no mound, bowl or seat.
- Props stay on the rim band between the mat (`PAD_DECK.matHalf`) and the deck edge (`PAD_DECK.half`); nothing rises above the frame inside the mat square, so the slime is never buried. The model script prints `OVERLAY ... over_mat=0`.
- Bbox centred on the pad (a MeshPart's origin is its bbox centre), footprint <= 7.9, 0.5-2.8 studs above the deck (`tests/Habitats.spec`).
- Sheets are judged with the crate drawn under the overlay: `HABITAT_PREVIEW=1 python iterate.py models/<name>.py --no-export`.

## Server owns pad state: `src/server/HabitatPads.luau` (pure) + `WorldView.updatePlots`

- Each view tick the server works out every pad's target: the slime whose `pad` is that pad and whose Scene state is `Pad` (not carried, not escaping) gives `forSlime(slime)`; anything else is `base`. Free plots are all `base`.
- On a change it stamps the pad and `WorldView` writes three attributes on `Pad_<j>` (`Constants.HABITAT_*`): `Habitat` (id), `HabitatFrom` (previous id), `HabitatAt` (server time of the change). Nothing is saved and no remote is added.
- The server never waits for the animation: gameplay (income, steal prompt, pad top height) is unchanged.

## Client animates: `src/visuals/client/HabitatFx.luau`

- One local overlay per habitat per pad (folder `workspace.ClientHabitats`, CanCollide / CanQuery / CanTouch off), resting on the deck. The pad and its Stand are never hidden or recoloured.
- Each overlay has a weight 0..1 that moves toward 1 (current `Habitat`) or 0 (any other) at `1 / TRANSFORM_SECONDS` (1 s): the overlay rises out of the deck and fades in, with a sparkle burst when a change starts; leaving is the same tween backwards. Weights live in `Habitats.stepWeights` (pure, Lune-tested).
- The mesh is a clone of the server's MeshPart template in `ReplicatedStorage.HabitatMeshes` (`Constants.HABITAT_MESHES`, `MeshSwap.publishHabitatTemplates`): a MeshPart keeps the kit's vertex colours, a script-made FileMesh SpecialMesh draws them white.
- Until a template arrives (or with no meshId) the overlay is placeholder primitives in `Habitats` colours (four frame strips and four corner props); looks rebuild as the mesh when the template lands.

## Animation feel: `src/shared/HabitatMorph.luau` (pure) + `Config.HABITAT_ANIM`

- **Rise:** the overlay mesh grows in height only (easeOutBack overshoot while rising), so its footprint never sweeps over the slime. Placeholder prop `i` of `n` starts at weight `STAGGER * (i-1)/(n-1)`; the last prop up is the first to go.
- **Puff:** the sparkle emitter, `BURST_FULL` particles (`BURST_SIMPLE` at mid distance).
- **Quality:** `HabitatMorph.quality` -> `snap` (LocalPlayer attribute `ReducedMotion` = true, camera beyond `SNAP_BEYOND` studs, or `MAX_ANIMATING` pads already morphing): the change shows its final state at once, no puff; `simple` (beyond half of `SNAP_BEYOND`): plain ease, small puff; else `full`.
- **Late joiners** snap to the final state (`initialWeights`); settled weights equal the static overlay exactly.
- Proof: `tests/HabitatMorph.spec`, `tests/HabitatsLive.spec` (enter / leave / interrupt, pad untouched, no leftover parts, overlay mesh on the deck).

## Edge cases

- **Steal mid-transform:** the server flips the pad straight to `base` (`HabitatFrom` = the half-grown habitat). The client sinks the half-grown overlay from where it was.
- **Rapid swap** (slimes swapped / merged within 1 s): only the latest `Habitat` is a target; every older overlay sinks to 0 while the new one rises.
- **Join in progress / pad streams in:** the first time a client sees a pad it snaps to the final state (`Habitats.initialWeights`), no animation or FX.
- **Owner leaves / plot freed:** every pad of that plot goes `base`.
- **Flag off:** the server never sets the attributes and `HabitatFx` never starts, so no parts, folders or attributes exist (tests: `Habitats.spec`, `LiveBoot.spec`).
