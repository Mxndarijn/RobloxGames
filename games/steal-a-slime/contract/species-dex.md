# §36 Species Dex: one entry per species, mutation stamps, a new milestone ladder

The SlimeDex counts species and mutation stamps (design `docs/SLIME-ECONOMY.md` §2.3, §5.1, §5.2). The old
combination Dex (`Genome.dexKey`, tier : mutation : pattern : eyes, 1152 keys) is retired with its save fields, its
State fields and its milestone ladder. There are no live saves, so there is no migration: an old save simply starts
the new Dex empty and is re-seeded from the slimes it owns on load.

## 36.1 Entries and stamps (`Shared.SpeciesDex`, pure)

- **Entries: 50.** Every `SlimeRoster` species of kind `"spawn"` (32), `"hybrid"` (15) and `"boss"` (3), in roster
  order (`SpeciesDex.ENTRIES`, `SpeciesDex.TOTAL = 50`). The 7 `"event"` Secrets are **bonus entries**
  (`SpeciesDex.BONUS`): they show on the Dex and count in `bonusFound`, never in `found` / `total` or a milestone.
- **Found.** `data.found[species] = true` the first time the player owns a slime of that species, from any source:
  catch (Carry), steal, merge (pair or triple, recipe or random), Mystery Egg, consumables / appraisal, a boss trophy.
  All of them go through `PlayerData.discover(data, slime)` (`PlayerData.addSlime` calls it). A system that gives a
  slime without `addSlime` (the boss trophy stand) must call `PlayerData.discover` itself. Loading a save calls it for
  every owned slime, so owned species are always found.
- **Stamps.** Key `"<species>:<Mutation>"` with the slime's primary mutation (`Genome.primaryMutation`), e.g.
  `"moo:Gold"`, `"eclipse:Eclipse"`, `"soda:None"`. Set by the same `discover` call.
  - **Core stamps: 47 x 8 = 376** (`SpeciesDex.STAMP_TOTAL`): spawn and hybrid species, each with `None` + the 7
    `Config.MUTATIONS` (Glow, Lava, Galaxy, Rainbow, Gold, Crystal, Eclipse).
  - **Gold stamps** (bonus, outside the 376): a spawn or hybrid species with a combo or weather primary mutation
    (`Config.COMBOS`, `WEATHER_MUTATIONS`, `WEATHER_COMBOS`: Solar, Nebula, Aurora, Royal, Wet, Frozen, Sleet, Comet).
  - Bosses and event Secrets get no stamps.
- `SpeciesDex.count(data)`, `stampCount(data)`, `goldCount(data)`, `bonusCount(data)`, `tierCount(data, tier)` /
  `tierSize(tier)` (entries of one tier among the 50), `tierMask(data)` (bit k-1 = a found entry of tier k).

## 36.2 Save (`data.found`, `data.stamps`, `data.speciesRewards`, `data.stampRewards`)

| Field | Saved as | Meaning |
|---|---|---|
| `found` | sorted list of species ids | entries and bonus entries found; unknown ids dropped on load |
| `stamps` | sorted list of stamp keys | core and gold stamps; keys whose species or mutation is unknown, or whose species has no stamps, are dropped |
| `speciesRewards` | number | species-ladder milestones paid (0..#ladder) |
| `stampRewards` | number | stamp-ladder milestones paid (0..#ladder) |

`data.dex` and `data.dexRewards` are removed (not read, not written). The fields are added without a
`SAVE_VERSION` bump (like `consumables`): a save without them loads them empty / 0.

## 36.3 Milestones (`Config.DEX_MILESTONES`, `Shared.Collection`)

`Config.DEX_MILESTONES = { species = { ... }, stamps = { ... } }`, each a list of `{ count, reward, bonus }` in
ascending `count`. Cash is `reward x Economy.rebirthMultiplier(rebirths)` at the moment it is paid; the income bonus
is permanent (`Perks.dexBonus` = the sum of paid milestones of both ladders). Both ladders add up to +65 % income.

| Ladder | Count | Cash | Income |
|---|---:|---:|---:|
| species | 8 | 1 000 | +2 % |
| species | 15 | 5 000 | +3 % |
| species | 20 | 25 000 | +5 % |
| species | 32 | 250 000 | +10 % |
| species | 40 | 1.5 M | +10 % |
| species | 50 | 10 M | +15 % |
| stamps | 50 | 10 000 | +3 % |
| stamps | 100 | 100 000 | +5 % |
| stamps | 200 | 1 M | +5 % |
| stamps | 376 | 25 M | +7 % |

`Collection.check(data)` pays every reached, unpaid milestone of both ladders (species first) and returns
`{ { ladder, count, reward, bonus } }`; `Milestones` toasts them ("SlimeDex 15 species: ...", "SlimeDex 50 stamps:
..."). Bonus entries and gold stamps never count.

**Rebased on the new counts.**
- Plot skins (§15): a skin's `set` tier unlocks at `threshold` of that tier's entries found
  (`SpeciesDex.tierCount / tierSize`). `PlotSkinView.owned / total / needed` count entries.
- Badges: `dexPercent` = `found x 100 >= value x 50`; `tier` = a found entry of that tier.
- Plot attributes: `DexCount` = found (0..50), `DexTotal` = 50, `DexTierMask` = `SpeciesDex.tierMask`.

## 36.4 State

`State.dex: DexView` replaces `dex: { string }` and `dexTotal`. `dexRewards` and `dexBonus` stay, with the new ladder.

```luau
DexView = {
	found: number, total: number,             -- entries among the 50
	stamps: number, stampTotal: number,       -- core stamps among the 376
	gold: number,                             -- gold bonus stamps
	bonusFound: number, bonusTotal: number,   -- event Secrets owned / 7
	entries: { DexEntryView },                -- the 50, then the 7 bonus entries, roster order
}
DexEntryView = {
	id: string, tier: number, kind: "spawn" | "hybrid" | "boss" | "event",
	found: boolean,
	name: string?,          -- nil = the client shows "???" (see below)
	hint: string?,          -- the card's hint line
	ingredients: { string }?, -- hybrids: 3 slots, the species id when that ingredient is found, "" when not
	stamps: { string },     -- core mutations stamped ("None", "Glow", ...), Config order; {} for bosses / events
	gold: { string },       -- gold stamp mutations, sorted
}
DexRewardView = { ladder: "species" | "stamps", count: number, reward: number, bonus: number, claimed: boolean }
```

What the server reveals (it never sends a name or ingredient the player has not earned):

| Kind | `name` | `hint` | `ingredients` |
|---|---|---|---|
| spawn | when found | nil | nil |
| hybrid | when found, or when every ingredient is found ("known") | always: the recipe's hint line (`MergeRecipes.hint`, §35), as a riddle | each slot's species once that species is found |
| boss | when found | `"Defeat the boss event"` | nil |
| event | when found, or while it is the featured Secret | `"Featured Secret: week of <d Mon>"` (this week's start while featured, else the next week it is featured, `EventSecrets` §34) when found or featured; `"???"` otherwise | nil |

## 36.5 Client

The SlimeDex panel (Nav key `Dex`) shows: the species count and percent (`found / total`), a bar, the stamp count,
the next milestone of each ladder with its reward, then one card per entry grouped by rarity (tier header rows), the
bonus entries last. A found card shows the species mesh (`ctx.buildSlime` with the species, ViewportFrame) in full
colour, its name and its stamp row (8 dots, gold dots after); an unfound card shows the same mesh as a flat black
silhouette, the name "???", and for hybrids a "Merge-only" badge, the hint and three ingredient slots. Cards sit in
a grid whose column count follows the panel width (one column on a narrow phone). Plot-skin cards stay above.
