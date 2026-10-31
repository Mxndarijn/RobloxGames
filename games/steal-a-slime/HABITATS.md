# Slime habitats (spec)

**Status:** three-layer habitats (frame, theme, signature prop); `Config.FEATURES.Habitats` is the only place the flag is set. **Owners:** data + pad state Phoenix (`src/shared`, `src/server`), habitat FX Archer (`src/visuals`).

The pad never changes. When a slime sits on a pad, that slime's habitat rises out of the cork stand's dish in about 1 s, in three layers round the slime. While a thief carries the slime off (or it bounces home) the habitat stays: only the slime leaves. When the pad empties (steal completed, sold, merged, owner leaves) it sinks away and the bare pad is left. Swapping one slime for another crossfades the two habitats on the same pad.

| Layer | What | Mesh |
|---|---|---|
| Frame | the ring round the slime, one per rarity tier: Wood, Painted Wood, Stone, Copper, Gold, Silver and Gems, Shadow (Secret), Starry Glass (Celestial), White Gold (Divine) | `habitat_frame_<tier>` |
| Glow lip | Secret, Celestial and Divine only: a thin ring inside the frame, Neon in the frame's glow colour; Secret's cycles through the rainbow | `habitat_frame_glow` (white, tinted by the client) |
| Theme | props on the back and sides of the rim that set the place, shared by the slimes of that theme | `habitat_theme_<id>` |
| Signature prop | one small prop on the front of the rim (the walkway side), only that species has it | `habitat_prop_<species>` |

## Data: `src/shared/Habitats.luau` (pure)

- **Habitat ids** name all three layers: `<theme>.<tier>` or `<theme>.<tier>.<species>` (`reef.5.captain_goo`). Never saved. `base` = the bare pad. `Habitats.resolve` turns anything that doesn't parse (unknown theme, tier or species) into `base`.
- **Lookup:** `Habitats.forSlime(slime)`: the species' theme (`SPECIES_THEME`, every roster species), the slime's own rarity tier for the frame, the species for the prop. A slime without a species gets `TIER_THEME[tier]` and no prop.
- **17 themes:** Barnyard, Sweet Treats, Flower Garden, Mushroom Forest, Lily Pond, Royal Court, Arcane Grotto, Ember Rocks, Ice Floe, Ocean Reef, Sky Isle, Starry Space, Tech Lab, Dojo, Spooky, Treasure Vault, Party Stage. Which species is in which theme: `SPECIES_THEME` (the proposal with every pair: `docs/habitat-proposal.html`).
- `Habitats.layers(id)` lists what to draw in rise order (frame, glow, theme, prop), each with its uploaded mesh (`overlayMesh`: meshId, native size, drop, bbox offset) or nil while not uploaded. `Habitats.MESHES` is every layer mesh (MeshSwap publishes a template for each uploaded one).
- **Where the layers go:** frame, glow and theme centred on the dish, turned by `FRONT_YAW` so the kit front (-Y) faces the walkway; the prop at `PROP_RADIUS` on the front of the rim. A theme keeps its front clear, so its bbox isn't centred: its MeshAssets entry carries `offset` (bbox centre from the dish centre, kit `out/<name>.deck.json`) and the client moves it back.

## Mesh rules (kit, `shared/modeling-kit/models/`)

- z=0 = the dish rim (`WorldLayout.PAD_DECK.y`). Nothing rises inside the mat circle (radius `PAD_DECK.matHalf`), so the slime is never buried.
- **Frame:** a closed ring, radius 2.6 to 3.75, top <= 0.3 (detail <= 0.45). Helpers `_habitat_frame.py`.
- **Glow:** radius 2.48 to 2.6, 0.32 high, white.
- **Theme:** props on the rim band only, nothing above 0.3 within 45 degrees of the front, tallest at the back (<= 2.8). `overlay_finish` (`_habitat_overlay.py`) maps the square-authored layout onto the round dish and writes the deck offset.
- **Prop:** a normal kit prop standing on z=0, front -Y, at most 1.9 wide, 1.15 deep and 1.4 tall so the slime stays in view.
- Check a whole habitat on the stand before uploading: `HABITAT_COMBO=<theme>:<tier>:<species> python iterate.py models/_habitat_combo.py --no-export --look roblox`.

## Server owns pad state: `src/server/HabitatPads.luau` (pure) + `WorldView.updatePlots`

- Each view tick the server works out every pad's target: the slime whose `pad` is that pad gives `forSlime(slime)` (one id for all three layers), also while it is carried off or escaping home; anything else is `base`. Free plots are all `base`.
- On a change it stamps the pad and `WorldView` writes three attributes on `Pad_<j>` (`Constants.HABITAT_*`): `Habitat` (id), `HabitatFrom` (previous id), `HabitatAt` (server time of the change). Nothing is saved and no remote is added.
- The server never waits for the animation: gameplay (income, steal prompt, pad top height) is unchanged.

## Client animates: `src/visuals/client/HabitatFx.luau`

- One local look per habitat id per pad (folder `workspace.ClientHabitats`, CanCollide / CanQuery / CanTouch off), resting on the dish. The pad and its Stand are never hidden or recoloured.
- Each look has a weight 0..1 that moves toward 1 (current `Habitat`) or 0 (any other) at `1 / TRANSFORM_SECONDS` (1 s), with a sparkle burst in the theme's colours when a change starts (a leave puffs in the old habitat's colours). Weights live in `Habitats.stepWeights` (pure, Lune-tested).
- Each layer mesh is a clone of the server's MeshPart template in `ReplicatedStorage.HabitatMeshes` (`Constants.HABITAT_MESHES`, `MeshSwap.publishHabitatTemplates`): a MeshPart keeps the kit's vertex colours, a script-made FileMesh SpecialMesh draws them white.
- Until a layer's template arrives (or with no meshId) the frame is an octagon of strips in the tier colour and the theme three blocks in its colours; the glow lip and the signature prop show nothing. Looks rebuild when a template lands.

## Animation feel: `src/shared/HabitatMorph.luau` (pure) + `Config.HABITAT_ANIM`

- **Rise:** frame, glow and theme meshes grow in height only (easeOutBack overshoot while rising), so their footprint never sweeps over the slime; the signature prop pops up whole. Piece `i` of `n` (frame first, prop last) starts at weight `STAGGER * (i-1)/(n-1)`; the last piece up is the first to go.
- **Puff:** the sparkle emitter, `BURST_FULL` particles (`BURST_SIMPLE` at mid distance).
- **Quality:** `HabitatMorph.quality` -> `snap` (LocalPlayer attribute `ReducedMotion` = true, camera beyond `SNAP_BEYOND` studs, or `MAX_ANIMATING` pads already morphing): the change shows its final state at once, no puff; `simple` (beyond half of `SNAP_BEYOND`): plain ease, small puff; else `full`.
- **Late joiners** snap to the final state (`initialWeights`); settled weights equal the static habitat exactly.
- Proof: `tests/HabitatMorph.spec`, `tests/HabitatsLive.spec` (enter / leave / interrupt, pad untouched, no leftover parts, layer meshes on the deck, prop on the front rim).

## Edge cases

- **Steal mid-transform:** the server flips the pad straight to `base` (`HabitatFrom` = the half-grown habitat). The client sinks the half-grown habitat from where it was.
- **Rapid swap** (slimes swapped / merged within 1 s): only the latest `Habitat` is a target; every older habitat sinks to 0 while the new one rises.
- **Join in progress / pad streams in:** the first time a client sees a pad it snaps to the final state (`Habitats.initialWeights`), no animation or FX.
- **Owner leaves / plot freed:** every pad of that plot goes `base`.
- **Flag off:** the server never sets the attributes and `HabitatFx` never starts, so no parts, folders or attributes exist (tests: `Habitats.spec`, `LiveBoot.spec`).
