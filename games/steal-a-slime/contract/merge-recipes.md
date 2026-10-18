# §34 Merge recipes, merge caps and the merge assist

Design: `docs/SLIME-ECONOMY.md` §1.2 (caps, assist) and §2 (recipes). Builds on the 3-slime vat (§21) and the hybrid
kind in the roster (§30). No save change: "found" is read from what the save already holds.

- **Recipes (`Shared.MergeRecipes`, pure).** A recipe is a multiset of three spawning species of one tier T; its result
  is a hybrid (`SlimeRoster` kind `"hybrid"`) of tier T + 1. Order doesn't matter and repeats count. The 15 recipes:

  | Hybrid | Tier | Inputs |
  |---|---|---|
  | `soda` | 2 | bubbles gummy mochi |
  | `rocky_road` | 2 | cheddar mochi pebble |
  | `bloom` | 3 | bumble mushie prickles |
  | `honey_toad` | 3 | bumble flan froggo |
  | `truffle` | 3 | flan flan mushie |
  | `moo_shroom` | 4 | lop moo moo |
  | `snow_bunny` | 4 | lop lop pengoo |
  | `catfish` | 4 | chomp pengoo whiskers |
  | `sushi` | 4 | chomp chomp pengoo |
  | `steam` | 5 | blaze frostbite zap |
  | `kraken` | 5 | octo octo zap |
  | `thunderbee` | 5 | imp zap zap |
  | `dragon_king` | 6 | king king king |
  | `cyber_ninja` | 6 | ninja ninja robo |
  | `nightwing` | 7 | cosmo seraph seraph |

  No two recipes share an input set. A recipe hits whether or not the player knows it. Inputs with a nil species never
  hit; tier-7 inputs never hit.
- **API.**
  - `MergeRecipes.RECIPES: { Recipe }`, `Recipe = { id, inputs (sorted), tier, hint }` (frozen; `id` = hybrid id).
  - `MergeRecipes.key(species) -> string`, `MergeRecipes.find(species) -> Recipe?` (exact multiset, nil if any is nil).
  - `MergeRecipes.recipeFor(hybridId) -> Recipe?`, `MergeRecipes.hint(hybridId) -> string?` (the Dex hint line).
  - `MergeRecipes.isKnown(recipe, found) -> boolean`: every input species found (for Dex cards).
  - `MergeRecipes.isDiscovered(hybridId, found) -> boolean`: the hybrid itself was found.
  - `MergeRecipes.foundOf(slimes, found?) -> { [id]: true }`: species of the owned slimes plus a saved `found` set.
    Server: `data.slimes` and `data.found` (`{ [speciesId]: true }`, the species Dex). Client: the slimes in
    `State.slimes` and the `State.dex.entries` with `found == true` (by `id`). Without the species Dex, owned
    slimes are what counts.
  - `MergeRecipes.unlockedFor(rebirths) -> (Entry) -> boolean`: Classic always, a family once the player's rank opened
    it (`FountainTiers.catchBlock`).
  - `MergeRecipes.pool(tier, ctx) -> (pool, assistPool)`: the unlocked spawning species of `tier` (ids, roster order),
    and those not in `ctx.found`. Never hybrids, bosses or event Secrets.
  - `MergeRecipes.resolve(inputs: { { tier, species? } }, ctx: { unlocked, found? }) -> Outcome`, drawing no randomness:
    `{ kind = "refused", reason }` (not three, or not one tier), `{ kind = "recipe", recipe, tier }`, or
    `{ kind = "random", tier, jumpTier?, jumpChance, pool, assistPool, assistChance }`.
- **Caps (`Config`).** A random merge gives tier `min(T + 1, MERGE_MAX_TIER)` (6, Mythic): Mythic x3 gives a Mythic, a
  random merge never makes a Secret. Tier-7 inputs stay tier 7 (unlocked Secret spawn species, fresh mutation). The +2
  jump (`TRIPLE_MERGE_JUMP_CHANCE`) only when `T + 2 <= MERGE_JUMP_MAX_TIER` (5, Legendary).
- **Assist.** `MERGE_ASSIST_CHANCE` (0.35) of random results come from `assistPool` when it is not empty.
- **`TripleMerge.merge(slimes, rng, id, mutationBonus?, ctx?)`.** Draw order: jump, assist, species, fresh mutation
  (2 draws), three trait picks, stacking. Jump, assist and species are drawn on every merge, recipe or not, so one seed
  gives one result. A recipe hit gives the hybrid at the recipe tier (no jump); mutations, size and traits as usual.
  `ctx` defaults to Classic only, nothing found. `TripleMerge.apply` builds `ctx` from the save (`rebirths`, `foundOf`).
  `TripleMerge.odds(tier)` follows the caps.
- **Toast.** On a recipe hit the merging player gets Notify `"You discovered <Hybrid>!"` the first time (hybrid not
  found before the merge), `"You brewed a <Hybrid>!"` after that (`"good"`, sound `Rare`).
- **Merge menu preview (`MergePreview`).** Three picks that hit a recipe whose hybrid the player has **discovered**
  (`isDiscovered`) preview as that hybrid: title its name, tier the recipe tier, no jump line. Any other load, an
  undiscovered recipe hit included, previews exactly as a random merge ("Random <Rarity> slime" with the random odds),
  so the menu never tells a recipe apart before it was crafted. `isKnown` is not used here: the player owns the three
  picks, so their species are always found and `isKnown` would leak every recipe.
