# §32 Slime odds: rarity weights, the family drop rule, Mythic and Secret presentation

Owner: Phoenix (server, shared), Archer (visuals). Design: `docs/SLIME-ECONOMY.md` §1.2 (weights), §1.3 (drop rule),
§4 (presentation). Merge caps (§1.2 "Merge caps") are `TripleMerge`'s and not part of this file. No save change.

## Rarity weights

`Config.RARITIES[i].weight`, Common to Secret: **52 / 28 / 13 / 5.2 / 1.2 / 0.2 / 0.05**. Luck (`Genome.rollTier`)
still multiplies tiers >= 3; pity (`PITY_EPIC`, `PITY_LEGENDARY`) is unchanged.

## Drop rule

A fountain drop rolls the **tier first**, then picks **uniformly** among the spawning species (`kind == "spawn"`) of that
tier in Classic plus every family open on the server (`FountainTiers.pool(world.fountainTier)`). A family that has no
species at the tier adds none; Classic has at least one at every tier, so the pool is never empty.

- Removed: `Config.FAMILY_DROP_CHANCE`, `FountainTiers.roll`, `FountainTiers.luck`, `Family.weight`, `Family.luck`.
  Families give no extra luck: the tier is rolled before the species.
- Kept: the catch gate `FountainTiers.catchBlock` / `Carry.familyBlock` (your own rank must have opened the family; a
  stolen slime or a merge result is never gated).
- `FEATURES.FountainTiers` off: no families, Classic species only.
- Family display names (`FountainTiers.FAMILIES[i].name`, ids unchanged): `orchard` **Garden**, `frost` **Frost & Sea**,
  `starlight` **Starlight**; Classic is **Meadow**. Fountain looks: Meadow / Garden / Frost & Sea / Starlight Fountain.

### API (shared, pure)

```luau
Genome.speciesPool(tier: number, families: { string }?, extra: { SlimeRoster.Entry }?): { SlimeRoster.Entry }
Genome.rollSpecies(tier: number, roll: number, families: { string }?, extra: { SlimeRoster.Entry }?): SlimeRoster.Entry?
Fountain.roll(rng, id, raining, minTier?, luckMult?, mutationMult?, weeklyMutation?, weeklyBonus?,
	families: { string }?, extraSpecies: { SlimeRoster.Entry }?): Fountain.Drop
```

- `speciesPool` order: Classic, then each id of `families` in the given order, then the `extra` entries whose `tier`
  equals `tier` (any other tier is skipped, so a caller may pass `extra` for every roll). nil / empty `families` =
  Classic only. `rollSpecies` picks `pool[floor(roll * #pool) + 1]`; nil only for a tier outside 1..`MAX_TIER`.
- `Genome.GenerateOptions.families` / `.extraSpecies` feed `rollSpecies` (they replace the single `family`).
- Hook for event Secrets: the featured event Secret goes in `extraSpecies` (a `kind == "event"` entry of tier 7), so
  it joins the tier-7 pool uniformly with the open Secrets. `Spawner.familyPool(world)` gives the open families.
- `Genome.rollSpecies(tier, roll)` with no families stays Classic only (callers that pass nothing are unchanged).

## Mythic (tier 6) and Secret (tier 7) presentation

| | Config | Mythic | Secret |
|---|---|---|---|
| Size floor | `Config.TIER_SIZE_FLOOR[tier]` | 1.2 | 1.4 |
| Wild lifetime | `Config.TIER_LIFETIME_MULT[tier]` x `WILD_LIFETIME` | x1.5 | x2 |

- **Size floor** (`Genome.sizeFloor(tier)`, 0 for other tiers): `Genome.generate` raises a rolled size to the floor
  (`MAX_SIZE` stays the cap). Applies to every generated slime of that tier (fountain, rain, eggs).
- **Lifetime** (`Fountain.wildLifetime(slime)`): fountain spawns and a dropped carry (`Carry.release`) live
  `WILD_LIFETIME x TIER_LIFETIME_MULT[tier]` (1 for other tiers); the boss leaves only through the boss event (§33). The parade walk is
  a function of the lifetime (`ParadeLane`), so a longer life walks the lane slower.
- **Spawn announce** (unchanged rule, `RARE_ANNOUNCE_TIER` 5): every player gets the Notify
  `Spawner.rareText` ("A MYTHIC Cosmo spilled from the fountain!!", the species name in it), sound `"Rare"`, or
  `"Secret"` for tier 7, plus the workspace `RareSpawnId` / `RareSpawnTier` / `RareSpawnAt` attributes. There is no
  minimap in the game: the wild slime's `RareSpawn` marker (beam, glow, sparkles) is the world ping.
- **Catch toast**: depositing a wild slime of tier >= 6 (`Carry.CATCH_ANNOUNCE_TIER`) notifies every player
  `Carry.catchText`: `"<player> caught <Species>!"` (the slime's name), kind `"info"`, no sound (a `"Rare"` sound
  would read as a new drop in `RareAnnounce`).
- **Looks (client, `src/visuals`, attributes only):**
  - Aura: `SlimeLayout` tier >= 6 Neon aura in the tier colour (already on the model).
  - `RareSpawn.TIERS[7]`: the Mythic marker plus `orbit` = 3 Neon motes circling the slime.
  - Fountain beam: while any wild Secret is replicated, one Neon beam (`TopTierFx.FOUNTAIN_BEAM`, under
    `RareSpawn.MAX_BEAM_HEIGHT`) stands on the fountain crown.
  - Eruption: when `RareSpawnTier` becomes 7 with a fresh `RareSpawnAt`, every client plays
    `TopTierFx.ERUPTION_SECONDS` (2 s) of camera shake and a sky tint (`Lighting.SecretBurstTint`, a
    `ColorCorrectionEffect`) plus one fountain splash burst; the shake binds to render step only while it runs.
  - Pedestal glow: a slime with `State == "Pad"` and `Tier >= 6` gets a Neon disc and soft light under it
    (`TopTierFx.pedestal(tier)`); Secret adds a small sparkle column.
  - All of it is culled beyond `PlotVisuals.MAX_FX_DISTANCE`, runs in `PlotVisuals`' existing frame loop and adds no
    `RenderStepped` / `Heartbeat` connect.
