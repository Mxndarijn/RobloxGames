# §36 Species Dex: one entry per species and a milestone ladder

The SlimeDex counts species (design `docs/SLIME-ECONOMY.md` §2.3, §5.1). Dex keys are species ids only. A save
without the Dex fields starts it empty and is re-seeded from the slimes it owns on load.

## 36.1 Entries (`Shared.SpeciesDex`, pure)

- **Entries: 53.** Every `SlimeRoster` species of kind `"spawn"` (32), `"hybrid"` (15) and `"boss"` (6), in roster
  order (`SpeciesDex.ENTRIES`, `SpeciesDex.TOTAL = 53`). The 7 `"event"` Secrets are **bonus entries**
  (`SpeciesDex.BONUS`): they show on the Dex and count in `bonusFound`, never in `found` / `total` or a milestone.
- **Found.** `data.found[species] = true` the first time the player owns a slime of that species, from any source:
  catch (Carry), steal, merge (recipe or random), a Mystery Egg hatch, consumables / appraisal, a boss win.
  All of them go through `PlayerData.discover(data, slime)` (`PlayerData.addSlime` calls it). A system that credits a
  species without `addSlime` (a boss win) must call `PlayerData.discover` itself. Loading a save calls it for
  every owned slime, so owned species are always found.
- `SpeciesDex.count(data)`, `bonusCount(data)`, `tierCount(data, tier)` /
  `tierSize(tier)` (entries of one tier among the 53), `tierMask(data)` (bit k-1 = a found entry of tier k).

## 36.2 Save (`data.found`, `data.speciesRewards`)

| Field | Saved as | Meaning |
|---|---|---|
| `found` | sorted list of species ids | entries and bonus entries found; unknown ids dropped on load |
| `speciesRewards` | number | species-ladder milestones paid (0..#ladder) |

A save without these fields loads them empty / 0; unknown species ids are dropped.

## 36.3 Milestones (`Config.DEX_MILESTONES`, `Shared.Collection`)

`Config.DEX_MILESTONES = { species = { ... } }`, a list of `{ count, reward, bonus }` in
ascending `count`. Cash is `reward x Economy.rebirthMultiplier(rebirths)` at the moment it is paid; the income bonus
is permanent (`Perks.dexBonus` = the sum of paid milestones). The ladder adds up to +45 % income. Its top milestone
is 50 species, a few short of the full Dex (53).

| Count | Cash | Income |
|---:|---:|---:|
| 8 | 1 000 | +2 % |
| 15 | 5 000 | +3 % |
| 20 | 25 000 | +5 % |
| 32 | 250 000 | +10 % |
| 40 | 1.5 M | +10 % |
| 50 | 10 M | +15 % |

`Collection.check(data)` pays every reached, unpaid milestone and returns
`{ { count, reward, bonus } }`; `Milestones` toasts them ("SlimeDex 15 species: ..."). Bonus entries never count.

**Rebased on the new counts.**
- Plot skins (§15): a skin unlocks at `threshold` of its own slimes found (a family, or a species list).
  `PlotSkinView.owned / total / needed` count those slimes.
- Badges: `dexPercent` = `found x 100 >= value x 53`; `tier` = a found entry of that tier.
- Plot attributes: none any more. `DexCount`, `DexTotal` and `DexTierMask` went with the plot SlimeDex board (goo jar tower remodel, 2026-10-21); `SpeciesDex.tierMask` still feeds the badges.

## 36.4 State

`State.dex: DexView`. `dexRewards` and `dexBonus` carry the species ladder.

```luau
DexView = {
	found: number, total: number,             -- entries among the 53
	bonusFound: number, bonusTotal: number,   -- event Secrets owned / 7
	entries: { DexEntryView },                -- the 53, then the 7 bonus entries, roster order
}
DexEntryView = {
	id: string, tier: number, kind: "spawn" | "hybrid" | "boss" | "event",
	found: boolean,
	name: string?,          -- nil = the client shows "???" (see below)
	hint: string?,          -- the card's hint line
	ingredients: { string }?, -- hybrids: 3 slots, the species id when that ingredient is found, "" when not
}
DexRewardView = { count: number, reward: number, bonus: number, claimed: boolean }
```

What the server reveals (it never sends a name or ingredient the player has not earned):

| Kind | `name` | `hint` | `ingredients` |
|---|---|---|---|
| spawn | when found | nil | nil |
| hybrid | when found, or when every ingredient is found ("known") | always: the recipe's hint line (`MergeRecipes.hint`, §35), as a riddle | each slot's species once that species is found |
| boss | when found | `"Defeat the boss event"` | nil |
| event | when found, or while it is the featured Secret | `"Featured Secret: week of <d Mon>"` (this week's start while featured, else the next week it is featured, `EventSecrets` §34) when found or featured; `"???"` otherwise | nil |

## 36.5 Client

The SlimeDex panel (Nav key `Dex`) shows: the species count and percent (`found / total`), a bar,
the next milestone with its reward, then one card per entry grouped by rarity (tier header rows), the
bonus entries last. A found card shows the species mesh (`ctx.buildSlime` with the species, ViewportFrame) in full
colour and its name; an unfound card shows the same mesh as a flat black
silhouette, the name "???", and for hybrids a "Merge-only" badge, the hint and three ingredient slots. Cards sit in
a grid whose column count follows the panel width (one column on a narrow phone). Plot-skin cards stay above.
