# Slime economy rework: spawns, rarity, recipes, bosses, Dex

Status: **design, not implemented.** Nothing in `src/` changes with this doc. It is the plan for moving the game onto the new slime pool (`shared/modeling-kit/models/pool`: 32 spawning species in `roster.json`, 15 merge-only hybrids and 3 bosses in `hybrids.json`, notes in `POOL.md`). Shared names below (ids, Request actions, State fields, save fields) are proposals: they go into a `contract/slime-pool.md` file first (CONTRACT.md rule), then the code.

The numbers come from the simulation in [economy-sim/](economy-sim/): `slime_economy_sim.py` (Python 3, standard library only) and its output `results.md`. §7 states every assumption it makes.

**The short version**

| Area | Proposal |
|---|---|
| Spawns | Keep `SPAWN_INTERVAL` 4 s and the 18-slime wild cap. New weights **52 / 28 / 13 / 5.2 / 1.2 / 0.2 / 0.05**: only Legendary, Mythic and Secret get rarer, because the pool has 3 / 4 / 3 species there instead of 4 / 3 / 2 and merges already feed the top. |
| Unlocks | 15 species from the start (the full ladder: at least one per tier), then 4 at 3 rebirths, 5 at 6, 8 at 10, through the existing `FountainTiers` families. The rebirth pace sets the Dex pace. |
| Merge vat | Recipes first: a fixed set of three species gives a fixed hybrid. Anything else falls back to a random spawning species of the next tier. Random merges stop at Mythic (Secret is never a random craft), +2 jumps stop at Legendary, and 35 % of random results are a species you haven't found yet. |
| Recipes | All three inputs one tier, hybrid one tier up (the vat rule stays "same rarity"). Hybrids show in the Dex as silhouettes; each input reveals itself once you have found that species. |
| Bosses | A giant boss every 20 min: a team fight (fill its goo meter with hits), then a carry race where it can be slapped loose and stolen. The depositor gets the boss slime on an unstealable trophy stand; every helper gets a free egg. |
| Top layer | **No eighth tier.** Make Mythic and Secret feel special with size, aura, a longer parade, and louder announcements. Bosses and the Secret-tier hybrid are the "beyond Secret" chase. |
| Dex | Species Dex (50 entries), one per species, with a milestone ladder that pays cash and permanent income. |
| Saves | `SAVE_VERSION` 7: every saved slime gets a new species through a fixed legacy map, the new Dex is seeded from owned slimes, and old ids stay loadable forever. |

Sim headline (proposed rules, active player, 6-player mixed server, medians of 24 runs): first Mythic **0.9 h**, first Secret **3.4 h**, all 32 spawning species **21.5 h**, all 15 hybrids **23.5 h**, full 50-entry Dex **30 h** (p90 38.5 h). A casual player needs **47 h** for the full Dex. Details in §7.3.

---

## 1. Spawn rate, rarity and unlocks

### 1.1 What happens today

- `SPAWN_INTERVAL` 4 s, so 900 rolls per hour. But `Spawner` **skips** a roll while 18 wilds are alive (`Fountain.canSpawn`), and a slime nobody grabs lives `WILD_LIFETIME` 115 s. An untouched plaza holds 115 / 4 ≈ 29 slimes, so the cap binds: an empty or quiet server gets about 18 / 115 s ≈ 560 spawns per hour. On a busy server (players grab most slimes within seconds) it is about 840 per hour (sim). That is fine: quiet servers drop fewer slimes, but there are also fewer players sharing them. **No change proposed;** in the sim a 2-player server (666 spawns/h) keeps pace with a full 8-player one (895/h) because there is less competition.
- Weights 52 / 28 / 13 / 5.2 / 1.45 / 0.35 / 0.1, `luck` multiplies tiers 3+, server pity (Epic after 30 dry drops, Legendary after 300), Slime Rain for 3 min every hour (normal 4 s spawns, cap x2, luck x5).
- The merge vat turns three of one tier into one of the next (20 % two tiers, never a jump into Secret; Mythic x3 does give a Secret). With today's odds and vat (sim scenario `today_rules`), the merge cascade and stealing, not the fountain, decide how fast a player reaches the top tiers. An active player who merges everything sees a first Mythic after 0.6 h and a first Secret after 1.4 h. That is too fast for "1 in 1000" tiers.

### 1.2 New weights

| Tier | Species (all families) | Weight today | **Proposed** | Spawns / server h (900) | Per species / h, full pool |
|---|---:|---:|---:|---:|---:|
| Common | 6 | 52 | **52** | 470 | 78 |
| Uncommon | 5 | 28 | **28** | 253 | 51 |
| Rare | 5 | 13 | **13** | 117 | 23 |
| Epic | 6 | 5.2 | **5.2** | 47 | 7.8 |
| Legendary | 3 | 1.45 | **1.2** | 10.8 | 3.6 |
| Mythic | 4 | 0.35 | **0.2** | 1.8 | 0.45 |
| Secret | 3 | 0.1 | **0.05** | 0.45 | 0.15 |

(Spawns per hour use the 99.65 weight total and 900 rolls; Slime Rain, boss showers and luck add more at the top.)

Why only the top three change: Common to Epic are what players catch and merge all the time. The sim shows their times are set by rebirth unlocks, not by the odds. Legendary loses one species (3 instead of 4), so each Legendary species gets *more* common at the old weight. Mythic gains a species and Secret one more, and both now come mostly from merges and bosses. Lowering them, together with the merge caps below, moves an active player's first Mythic from 0.6 h to 0.9 h and the first Secret from 1.4 h to 3.4 h (sim medians). The weights alone do little: merges and steals feed the top tiers more than the fountain does.

**Merge caps** (`TripleMerge`, in the same PR as the weights):

- A +2 jump may land on Legendary at most (today: up to Mythic). Rare x3 can still jump to Legendary; Epic x3 cannot jump to Mythic.
- A random merge never makes a Secret. Mythic x3 gives a Mythic (a random Mythic species, assist below). Secret comes from the fountain, Slime Rain, boss showers and the Nightwing recipe.
- **Merge assist:** 35 % of random results come from the species of that tier you have not found yet (when there are any). It costs nothing to build (the server knows the player's Dex), it hides inside "random", and it cuts the long tail of the last missing species.

### 1.3 Families: which species open when

The existing `FountainTiers` machinery stays: a family opens at a rank, the server's fountain tier is the best rank on the server, and you can only catch a family slime once your own rank has opened it (`FountainTiers.catchBlock`). A stolen one is fine, and so is a merge result from your own unlocked pool. The family ids `orchard`, `frost` and `starlight` stay (they are in Config and in code); only their display names and members change.

| Family (id) | Display name | Opens at | Common | Uncommon | Rare | Epic | Legendary | Mythic | Secret |
|---|---|---|---|---|---|---|---|---|---|
| Classic (none) | Meadow | start | gummy, mochi, bubbles, pebble | bumble, mushie, froggo | whiskers, lop, moo | blaze, octo | king | cosmo | midas |
| `orchard` | Garden | 3 rebirths (Slime Wrangler) | sprig*, cheddar | prickles, flan | | | | | |
| `frost` | Frost & Sea | 6 rebirths (Goo Tycoon) | | | chomp, pengoo | frostbite, zap | ninja | | |
| `starlight` | Starlight | 10 rebirths (Slime Sovereign) | | | | imp, drako | robo | seraph, amethyst, prism | eclipse, boo |

Counts: 15 / +4 / +5 / +8 = 32. A new player has the whole ladder from minute one: at least one species per tier, and the Classic merge recipes (soda, moo_shroom, dragon_king) are craftable. Each rank adds species where the player is by then: cheap ones at rank 3, mid tiers at 6, and the showy top at 10.

\* **Id clash:** the new pool's Common `sprout` has the same id as the old Uncommon `sprout` that is in live saves. The new pool has not shipped, so rename the new species' id to **`sprig`** (display name "Sprig", file `slime_sprout.py` can stay). Never give an old id a new meaning.

Drop rule change: today 30 % of drops are a family slime (`FAMILY_DROP_CHANCE`, weighted 5/3/2) and the rest are Classic. With families that fill different tiers, that rule would make the Starlight Mythics rarer than Cosmo for no reason. Proposal: **roll the tier, then pick uniformly among the species of that tier in every open family** (drop `FAMILY_DROP_CHANCE` and the family weights). `FountainTiers.luck` (family drops get extra luck) goes too, since the tier is rolled before the species.

`REBIRTH_SLIMES` (each rebirth needs one slime of a given species on a pad) points at old ids and needs a new list. Proposal, each entry catchable at that rank:

| Rebirth # | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 15 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| species | bumble | froggo | lop | moo | blaze | octo | king | ninja | cosmo | dragon_king (hybrid: king x3) | midas | eclipse |

Rebirth 10 asking for a hybrid teaches recipes right before Starlight opens.

---

## 2. Merge recipes

### 2.1 Rules

- The vat rule stays: three slimes of **one** tier. A recipe is a **multiset of three species of one tier T**, and its hybrid is tier T + 1. Order doesn't matter, and duplicates are allowed (moo + moo + lop).
- Recipe first: if the three species form a recipe, the result is that hybrid. There is no jump and no species roll. Size and traits follow the normal `TripleMerge` rules.
- Otherwise the result is the random fallback: a spawning species of T + 1 (or T + 2 on a jump) from the player's unlocked pool, with the assist from §1.2. Hybrids and bosses are never a random result.
- A recipe hits **whether or not the player knows it**: experimenting finds recipes.
- Inputs with no species (pre-v28 slimes are given one in the save migration, so this only covers bad data) never hit a recipe.
- Tier-7 inputs behave as today: the result stays Secret. There are no Secret-input recipes.
- Hybrids are normal slimes of their tier afterwards: they earn, sell, can be stolen and can go into a random merge.

The art's suggested parents mix tiers (for example Sushi = mochi + chomp + sprout). Mixed-tier recipes would mean the vat must accept mixed tiers, and refusing mixed non-recipes would leak recipes for free. So the recipes below keep to one tier and keep the most recognisable parent features. That is decision 3 in §8.

### 2.2 The 15 recipes

| Hybrid (id) | Tier | Recipe (tier of inputs) | Ingredients open at | Dex hint line |
|---|---|---|---|---|
| Soda Pop (`soda`) | Uncommon | bubbles + gummy + mochi (Common) | start | "Fizzy, chewy and soft: three Commons walk into a vat." |
| Rocky Road (`rocky_road`) | Uncommon | cheddar + mochi + pebble (Common) | 3 | "A scoop of rock, cheese and rice cake." |
| Bloom (`bloom`) | Rare | bumble + mushie + prickles (Uncommon) | 3 | "A bee, a mushroom and a cactus flower." |
| Honey Toad (`honey_toad`) | Rare | bumble + flan + froggo (Uncommon) | 3 | "Something sticky landed on a frog." |
| Truffle (`truffle`) | Rare | flan + flan + mushie (Uncommon) | 3 | "Double caramel on a mushroom." |
| Moo-shroom (`moo_shroom`) | Epic | lop + moo + moo (Rare) | start | "Two cows and a bunny went into the woods." |
| Snow Bunny (`snow_bunny`) | Epic | lop + lop + pengoo (Rare) | 6 | "Two bunnies and a friend from the cold." |
| Catfish (`catfish`) | Epic | chomp + pengoo + whiskers (Rare) | 6 | "A cat, a shark and the penguin that brought them together." |
| Sushi (`sushi`) | Epic | chomp + chomp + pengoo (Rare) | 6 | "A penguin's favourite dinner, twice." |
| Steampuff (`steam`) | Legendary | blaze + frostbite + zap (Epic) | 6 | "Fire, ice and a storm." |
| Kraken (`kraken`) | Legendary | octo + octo + zap (Epic) | 6 | "Two octopuses in a thunderstorm." |
| Thunderbee (`thunderbee`) | Legendary | imp + zap + zap (Epic) | 10 | "Double lightning and a little devil." |
| Dragon King (`dragon_king`) | Mythic | king + king + king (Legendary) | start | "Three crowns make a dragon." |
| Cyber Ninja (`cyber_ninja`) | Mythic | ninja + ninja + robo (Legendary) | 10 | "Two shadows and a machine." |
| Nightwing (`nightwing`) | Secret | cosmo + seraph + seraph (Mythic) | 10 | "Two angels fell into the stars." |

Per tier: Uncommon 2, Rare 3, Epic 4, Legendary 3, Mythic 2, Secret 1. No two recipes share an input set (the sim asserts it). Nightwing is the only way to *craft* a Secret.

Hybrid ids are new and permanent. None clashes with an old roster id.

**Differences from `hybrids.json`** (for the models): one tier changes. **Sushi moves from Rare (3) to Epic (4)**, because Rare has no fish-like Uncommon inputs. All other tiers stay. Because of the one-tier rule, these recipes don't use every suggested parent, so a model may want to lean on the parents that remain: Bloom (no sprout), Truffle (no pebble), Moo-shroom (no mushie, sprout), Snow Bunny (no frostbite, mochi), Sushi (no mochi, sprout), Kraken (no chomp), Thunderbee (no bumble), Dragon King (no drako, blaze), Cyber Ninja (no zap), Nightwing (no imp, eclipse). Soda, Rocky Road, Honey Toad, Catfish and Steampuff use their suggested parents exactly.

### 2.3 Discovery, Dex hints and silhouettes

| Dex state | What the hybrid's Dex card shows |
|---|---|
| Not found, no ingredient found | Black silhouette of the hybrid (its real mesh, flat black), tier colour frame, name "???", a "Merge-only" badge, three "?" ingredient slots. |
| Some ingredients found | Each slot whose species you have in the Dex shows that species' icon (x2 / x3 for repeats). |
| All ingredients found ("known") | Name and hint line shown, all three slots shown. The merge menu can now name this recipe (below). |
| Crafted | Full-colour card, like any species. |

- All 15 silhouettes are visible from the first Dex visit. That is the hook: players see a fish-cat silhouette and go looking.
- The hint line only shows once the recipe is known, so it confirms more than it reveals. A variant: show it from the start as a riddle. That is up to the Dex/UI owner and changes nothing server-side.
- **Server toast** on every craft: "<player> brewed a Steampuff!" (the existing `Rare` sound for Legendary+). It shows the hybrid, not the recipe.
- **Merge menu** (the other session's UI): when the three picked slimes form a recipe the player **knows**, the preview says "Recipe: Soda Pop". When they form a recipe the player doesn't know yet, the preview looks like any random merge ("Uncommon, random species"), so the surprise stays and the menu can't be used to probe recipes for free. Auto-merge never uses up the last copies of a known, uncrafted recipe's ingredients unless it completes that recipe, and it crafts known recipes first.

### 2.4 Recipe lookup: the pure function

A new pure module `src/shared/MergeRecipes.luau` (Lune-safe, no Roblox APIs), which `TripleMerge` and the merge menu both call. Proposed shape:

```lua
--!strict
export type Recipe = { id: string, inputs: { string }, tier: number } -- id = hybrid species id; inputs sorted
export type Input = { tier: number, species: string? }
export type Ctx = {
	unlocked: (speciesId: string) -> boolean, -- FountainTiers rank check for this player
	found: { [string]: boolean }?, -- the player's species Dex (for the assist pool and "known")
}
export type Outcome =
	{ kind: "recipe", recipe: Recipe, tier: number } -- tier = recipe.tier
	| {
		kind: "random",
		tier: number, -- T + 1 (capped at Config.MERGE_MAX_TIER, Mythic)
		jumpTier: number?, -- T + 2 when allowed (<= Config.MERGE_JUMP_MAX_TIER, Legendary)
		jumpChance: number,
		pool: { string }, -- spawning species of `tier` the player has unlocked, sorted
		assistPool: { string }, -- pool minus `found`
		assistChance: number, -- Config.MERGE_ASSIST_CHANCE when assistPool is non-empty, else 0
	}
	| { kind: "refused", reason: string } -- "need three slimes" | "slimes must be the same rarity"

MergeRecipes.RECIPES: { Recipe } -- frozen
MergeRecipes.key(species: { string }): string -- sorted ids joined by "+": the lookup key
MergeRecipes.find(species: { string? }): Recipe? -- exact multiset match, nil if any id is nil
MergeRecipes.resolve(inputs: { Input }, ctx: Ctx): Outcome
MergeRecipes.isKnown(recipe: Recipe, found: { [string]: boolean }): boolean -- every input species found
MergeRecipes.hint(recipe: Recipe, found): { revealed: { string? }, known: boolean, crafted: boolean } -- for Dex cards
```

`resolve` in words:

1. Not exactly three inputs, or not one tier: `refused` (same reasons `TripleMerge.canMerge` gives today).
2. Tier T < 7 and `find(species)` hits: `recipe`.
3. T = 7: `random` with `tier = 7`, no jump, pool = the unlocked Secret species (the existing "stays Secret" path).
4. Otherwise: `random` with `tier = min(T + 1, MERGE_MAX_TIER)` and the jump only when `T + 2 <= MERGE_JUMP_MAX_TIER`. The pool comes from `SlimeRoster.forTier` over the unlocked families, never hybrids or bosses.

`resolve` draws no random numbers. `TripleMerge.merge` rolls from the outcome in a fixed order: jump, assist, species, then the trait draws. It always draws the jump and species numbers, even on a recipe hit, so one seed stays one result whatever the inputs. The menu calls `resolve` for its preview and shows "Recipe: X" only when `isKnown`. It never sees the roll.

Config additions (names for the contract): `MERGE_MAX_TIER = 6`, `MERGE_JUMP_MAX_TIER = 5`, `MERGE_ASSIST_CHANCE = 0.35`. `TRIPLE_MERGE_JUMP_CHANCE` (0.2) stays.

---

## 3. Boss slimes: the world event

Today `FEATURES.BossSlime` drops a free, max-size Epic+ wild slime every 15 min. Whoever grabs it first keeps it. The new boss is an event the whole server joins.

| Step | What happens |
|---|---|
| Schedule | First boss 8 min after server start, then every **20 min** (`BOSS_INTERVAL` 1200). It skips (moves 5 min later) if Slime Rain is running or due within 3 min. A 60 s heads-up toast and fountain rumble come first. |
| Which boss | Rotation Goozilla, Queen Jelly, Goozilla, Queen Jelly, **Mecha Goo**. Mecha Goo (Secret tier) only comes on a server whose fountain is Starlight (tier 4); otherwise that slot is Goozilla. The boss is tier 6 (Goozilla, Queen Jelly) or 7 (Mecha Goo), shown 1.5x a MAX_SIZE slime, wandering the plaza inside the parade lane near the boss spot. |
| 1. Fight (max 90 s) | The boss sits in the plaza with a **goo meter**. Bat hits and slaps on it fill the meter, 1 point per hit per player, at most one hit per 0.4 s. The meter needs **25 x players on the server** points, so it takes about the same time on any server. With nobody hitting it drains 2 %/s. Every 25 % the boss sheds 2 wild slimes (luck x3). The server keeps each player's contribution. |
| 2. Haul (max 90 s) | When the meter is full the boss pops down to carry size. The top contributor may grab it for the first 5 s, then anyone can. The carrier walks at the boss carry slow (`Config.BOSS.CARRY_SLOW`, as slow as carrying the rarest slime) and can't use the Speed Coil. A slap makes the carrier **drop it on the spot** (not "escape home": it has no home yet), and anyone can grab it again. That is the steal moment. |
| Win | The player who brings it home gets the **boss slime**: species `goozilla` / `queen_jelly` / `mecha_goo`, MAX_SIZE. It goes on a **trophy stand** inside the plot, beside the Dex board: no pad needed, it earns income, and it **can't be stolen or merged** (one per boss species). |
| Everyone who helped | Every player with at least 10 % of the top contribution gets a free egg (`MysteryEgg.spawnForEvent`, which exists already) and a toast. |
| Fail | Meter not full in 90 s, or nobody brings it home in 90 s: the boss bursts into 6 wild slimes (luck x3) and sinks into the drain. |

Why this shape: the fight is teamwork that a solo player on a quiet server can still finish (the meter scales with players). The haul is the game's own "steal" verb. The trophy can't be robbed afterwards, because losing a 3-minute team prize to a random steal later feels bad when the next boss is 20 min away. Frequency: 3 bosses an hour, so on a 6-player server each player wins one about every 2 h and helps in all of them. Mecha Goo comes once every 100 min on Starlight servers.

Sim (proposed): all 3 boss species take a median 25 h, because Mecha Goo needs a Starlight fountain, which an active player reaches at about 17 h. On a server where a veteran keeps the fountain at Starlight it is 8 h.

Contract items: `BossFight` pure module (meter, contributions, phase, deadlines), `State.boss` grows `{ kind, phase, meter, endsAt, yourShare }`, the trophy stand as `data.trophies` (save v7), the haul uses `Carry` with `boss = true`. Bosses don't enter the wild cap, and boss slimes are never a random merge result.

---

## 4. A "mythical" layer above Secret?

**Recommendation: no new tier. Make Mythic and Secret feel special instead.**

A tier 8 touches `Config.RARITIES` and `MAX_TIER`, which runs through income, escape times, carry slow, merge odds, pity, Dex totals, plot-skin sets, pet passives, the UI rarity colours and many specs. The game already has a "Mythic" tier; a "Mythical" one above Secret would confuse more than it adds. At 0.05 the Secret tier already appears about once per 4 server hours. The chase above Secret already exists: the bosses (Mecha Goo is a Secret-tier boss) and Nightwing (a Secret you can only craft).

What changes for Mythic (tier 6) and Secret (tier 7):

| | Mythic | Secret |
|---|---|---|
| Size | minimum 1.2 (MAX_SIZE stays the cap) | minimum 1.4 |
| Look | coloured aura (Neon outline in the tier colour) and the rarity billboard in a gradient | aura plus orbiting sparkles, a light beam from the fountain while it is wild |
| Parade | lives 1.5x `WILD_LIFETIME`, hops slower | lives 2x |
| Spawn | everyone gets a toast and minimap ping (`RARE_ANNOUNCE_TIER` 5 stays) | a server-wide 2 s "fountain eruption" (camera shake, sky tint), toast with the species name |
| Catch / craft | server toast "<player> caught Cosmo!" | the same, plus an optional cross-server "global feed" line later (MessagingService, its own PR) |
| On the plot | a pedestal glow under the pad | a pedestal glow plus a small particle column |

All of this is visuals and Notify text (Archer and Jolt), plus two Config numbers (size floors, lifetime multipliers) on the server. None of it touches saves.

---

## 5. Dex and save migration

### 5.1 The new Dex

With baked species meshes, pattern and eyes no longer show (POOL.md), so the Dex counts what players can see:

- **Species entries: 50** (32 spawning + 15 hybrids + 3 bosses). One per species, set the first time you own one (catch, steal, merge, recipe, boss, egg).

Dex milestones (`DEX_MILESTONES`). Cash x rebirth multiplier. The income bonuses add up to 0.45:

| Count | Cash | Income bonus |
|---:|---:|---:|
| 8 | 1 000 | 0.02 |
| 15 (the whole start pool) | 5 000 | 0.03 |
| 20 | 25 000 | 0.05 |
| 32 | 250 000 | 0.10 |
| 40 | 1.5 M | 0.10 |
| 50 | 10 M | 0.15 |

Tier sets (all species of one tier found) keep driving the plot skins (`PLOT_SKINS[i].set` with `threshold` 0.75 reads the species Dex instead of `Collection.tierMask`). Badges with `dexPercent` read the species count over 50.

### 5.2 Old roster ids: save-safe migration (`SAVE_VERSION` 7)

Rules: a saved id is never renamed or reused with a new meaning. `SlimeRoster` keeps a frozen `LEGACY` map (old id -> new id) **forever**, so a v6 save loaded in a year still maps. All mappings keep the slime's tier, so income, sell value and merges are unchanged by the migration.

| Old id (tier) | New id | Old id (tier) | New id |
|---|---|---|---|
| pudding (1) | cheddar | bunny_puff (3) | lop |
| clover (1) | sprig | caramel_kitty (3) | whiskers |
| oatmeal (1) | mochi | moo_goo (3) | moo |
| radish (1) | gummy | piglet (3) | chomp |
| puddle (1) | bubbles | cocoa_pup (3) | pengoo |
| haystack (1) | pebble | billy_gum (4) | octo |
| sprout (2) | prickles | rodeo_ram (4) | drako |
| carrot (2) | flan | licorice_bull (4) | zap |
| berry (2) | mushie | toffee_buck (4) | blaze |
| minty (2) | froggo | sour_apple (4) | imp |
| pumpkin (2) | bumble | honey_queen (5) | king |
| tulip (2) | mushie | harvest_king (5) | king |
| rock_candy (6) | amethyst | blue_ribbon (5) | robo |
| dewdrop_spirit (6) | seraph | marshmallow_duke (5) | ninja |
| gumdrop_titan (6) | cosmo | golden_goose_goo (7) | midas |
| moonmilk (7) | eclipse | | |
| **orchard:** apple_pop (1) | sprig | **frost:** vanilla_scoop (1) | mochi |
| pear_drop (2) | prickles | mint_chip (2) | froggo |
| peach_fuzz (3) | whiskers | sherbet_bunny (3) | lop |
| plum_stag (4) | octo | icicle_ibex (4) | frostbite |
| cherry_baron (5) | king | snowcone_duke (5) | ninja |
| citrine_quince (6) | prism | glacier_gem (6) | seraph |
| **starlight:** stardust_blob (1) | bubbles | nebula_sprout (2) | mushie |
| comet_kitty (3) | whiskers | meteor_ram (4) | drako |
| aurora_queen (5) | robo | supernova_titan (6) | cosmo |

`SaveData.migrateV6` (makes v7):

1. Every slime: `species` = `LEGACY[species]` if it is an old id. If it has **no** species (pre-v28 and pair-vat slimes), pick one by a stable hash of the slime id among the Meadow species of its tier. `name` = the new display name. Tier, size, mutations and growth are untouched.
2. `data.found` (`{ [speciesId]: true }`) is seeded from the migrated slimes. Old players start the new Dex with what they own.
3. The old `data.dex` and `data.dexRewards` are not read; the Dex is seeded from owned slimes and the species ladder pays from there.
4. `data.trophies` (new, boss species -> slime) starts empty. `data.newDexRewards` counts paid new milestones.
5. `Genome.sanitize` maps legacy ids on every load (not only in the migration). Steal logs, favourites and pet ids hold slime ids, not species, so they need nothing.

Tests (`tests/SaveMigrationV7.spec.luau`): a real v6 table with old Classic, family, Secret and nil-species slimes migrates to the mapped species with the same tier; old `sprout` becomes `prickles` (tier 2) and never `sprig`; the income bonus is kept; the round trip in `SaveData.spec`.

---

## 6. Implementation plan (PR-sized)

Each step is one PR on its own `feat/...` branch from `main`, with the contract change committed first where shared names change. Steps 2 and 3 can run in parallel after 1. The merge-menu session only needs step 3's `MergeRecipes`.

| # | PR | Owner | Contents | Tests |
|---|---|---|---|---|
| 1 | `docs(steal-a-slime): slime pool contract` | Phoenix | `contract/slime-pool.md` + index line: species ids (incl. `sprig`), families, recipes, `MergeRecipes` API, Config names, save v7 fields, `State.dex` shape, boss State. Rename `sprout` -> `sprig` in `models/pool/roster.json`. | Contract.spec additions. |
| 2 | `feat(steal-a-slime): new slime roster behind FEATURES.SlimePool` | Phoenix (+Archer looks) | `SlimeRoster` entries with `kind` (spawn / hybrid / boss) and `LEGACY`, `SlimeLooks` for the new meshes, `Genome.rollSpecies` (spawning only, uniform over open families), `FountainTiers` (new members and display names, drop `FAMILY_DROP_CHANCE` and family luck), `REBIRTH_SLIMES`. Flag off = today's roster. **Needs the 32 meshes uploaded (Merijn's OK)**, so the flag stays off until then. | Roster, FountainTiers, Genome specs. Flag on and off in `test-flags`. |
| 3 | `feat(steal-a-slime): merge recipes` | Phoenix | `MergeRecipes.luau` (pure), `TripleMerge` uses `resolve` (recipe hit, `MERGE_MAX_TIER`, `MERGE_JUMP_MAX_TIER`, assist), recipe toast. Hand `resolve` / `isKnown` to the merge-menu session. | `MergeRecipes.spec` (every recipe hits in any order, no shared keys, mixed tier refused, nil species never hits, pool excludes hybrids, bosses and locked families), `TripleMerge.spec` seed-stability. |
| 4 | `feat(steal-a-slime): save v7 and species Dex` | Phoenix, then Jolt for the UI | `SaveData.migrateV6`, `data.found` / `trophies` / `speciesRewards`, `Collection` species ladder, `State.dex` = species + hints, PlotSkins and Badges on the new counts. Jolt: Dex cards with silhouettes, and ingredient slots. | `SaveMigrationV7.spec`, SaveData round trip, Collection, Snapshot, UI Dex spec. |
| 5 | `feat(steal-a-slime): new rarity odds and top-tier presentation` | Phoenix + Archer | Config weights, size floors, lifetime multipliers for 6/7, announcements; Archer: auras, beam, eruption, pedestal glow. | Contract "Config matches the design", Spawner and Fountain specs. Studio playtest for the visuals. |
| 6 | `feat(steal-a-slime): boss fight` | Phoenix + Archer + Jolt | `BossFight` (pure: meter, contributions, phases, deadlines), Spawner schedule and rotation, haul via `Carry`, trophy stand, eggs for helpers, `State.boss` fields, boss meter UI, giant boss visuals. Replaces today's `BossSlime` branch, so that flag's old path is deleted. | `BossFight.spec` (meter scales with players, drain, fail paths, top contributor priority, slap drop), Carry spec, livetest session with 2 stand-in players. |
| 7 | `refactor(steal-a-slime): retire the pair merge` | Phoenix | Delete `Merge.luau`'s pair path (`Request("Merge")`) once `MergeVat3` expires. | Delete its specs. |
| 8 | `feat(steal-a-slime): progression telemetry` | Phoenix | AnalyticsService funnel events (rebirth n, first of tier, species count, recipe crafted), **no DataStore**, to check the sim's rebirth-pace assumption after launch. | Spec on the pure event builder. |

Steps 2 to 5 should go live together, on one release with `SlimePool` on: the new Dex makes no sense on the old roster. Step 6 can follow a release later.

---

## 7. Simulation

### 7.1 Model

`economy-sim/slime_economy_sim.py` steps one server second by second for 60 played hours, 24 seeds per scenario:

- **Fountain:** a roll every 4 s while fewer than 18 wilds are alive (36 in Rain), lifetime 115 s, the scenario's weights, `luck` x5 for tiers 3+ during Rain, server pity (Epic 30 / Legendary 300), Slime Rain 3 min every hour from minute 5. Species are uniform over the tier's species in the families the fountain has opened.
- **Players:** "you" plus the other players (fixed ranks, a mixed server). Each one walks to the plaza (10 s), grabs the best slime they may catch (tier first; a species they lack counts as about two tiers more; "you" also chase the ingredients of the one known recipe you are working on) and carries it home (14 s + 1.5 s per tier). All times are divided by an **activity** factor (0.6 = 40 % of the time goes to locking, defending, shopping, AFK). Cash is not modelled: every wild is assumed affordable.
- **Merges:** after every deposit, known recipes first, then any three spare slimes of one tier (keeping a known recipe's ingredients). 8 pads; extras are sold, lowest first. Merge results follow §2: recipe hit, else random with the scenario's jump, caps and assist. Other players merge too, without recipes or assist.
- **Stealing:** each player makes `steals_per_hour` successful steals (Poisson). The victim is random, the slime is their best one half the time and otherwise random. Trophies can't be stolen. A steal also counts for the Dex.
- **Rebirths:** "you" rebirth at fixed played hours (assumption below). A rebirth keeps your best slime and wipes the rest. The Dex is kept.
- **Boss:** every 20 min from minute 8, rotation as in §3. Each player has an equal chance to win (the fight and haul are not simulated in detail). It sheds 6 lucky wilds.

### 7.2 Assumptions (the ones that matter most first)

| Assumption | Value | Why / risk |
|---|---|---|
| Rebirth pace (active) | rebirth 1 at 0.5 h, 3 at 2.2 h, 6 at 7 h, 10 at 17 h, 15 at 36 h of play | **This sets the whole Dex pace**, because families open by rank. Not measured: step 8 adds telemetry. `casual` doubles it. |
| Players per server | 6 (`full_server`: 8, `quiet_server`: 2) | MaxPlayers 8, average fill unknown. |
| Other players' ranks | 0, 1, 3, 5, 8 (fountain reaches Frost at 6) | A mixed server. `veteran_server` puts a 12-rebirth player on it all session. |
| Activity | 0.6 (`casual` 0.35) | About 70 catches per hour for an active player, about 9 % of all spawns. |
| Steals | 2 successful per hour (`casual` 0.5) | Steal success isn't measured yet. |
| Merge behaviour | merges every three spares at once | Real players keep some slimes for income, which makes merge-fed tiers a bit slower. |
| Cash | never a limit | Wild prices are 20 s of the slime's income, and the sim ignores pad and lock costs. |

### 7.3 Results

Medians (p90 in brackets) in played hours, 24 runs of 60 h each. `>60` = not reached in 60 h.

| Goal | proposed | today_rules | no_assist | casual | full_server (8) | veteran_server | quiet_server (2) | no_rank_gate |
|---|---|---|---|---|---|---|---|---|
| Server spawns / h | 840 | 839 | 840 | 710 | 895 | 847 | 666 | 841 |
| Your catches / h | 74 | 74 | 74 | 43 | 76 | 76 | 73 | 73 |
| First Legendary | 0.1 (0.3) | 0.2 (0.4) | 0.2 (0.3) | 0.3 (0.5) | 0.3 (0.7) | 0.2 (0.5) | 0.1 (0.1) | 0.1 (0.1) |
| First Mythic | 0.9 (3.8) | 0.6 (1.7) | 1.0 (4.1) | 1.7 (7.9) | 2.0 (7.1) | 1.1 (2.8) | 0.8 (2.7) | 0.1 (0.5) |
| First Secret | 3.4 (8.4) | 1.4 (3.4) | 3.1 (6.0) | 8.2 (15.1) | 5.0 (10.0) | 5.3 (18.3) | 1.5 (6.2) | 2.6 (6.8) |
| All 5 Rare | 7.1 (7.1) | 7.1 (7.1) | 7.1 (7.1) | 14.2 (14.2) | 7.1 (7.1) | 7.1 (7.1) | 7.1 (7.1) | 0.3 (0.6) |
| All 4 Mythic | 18.1 (20.3) | 18.1 (20.1) | 18.6 (21.5) | 35.5 (37.8) | 18.3 (20.8) | 18.0 (19.6) | 18.3 (20.8) | 2.1 (7.1) |
| All 3 Secret | 21.5 (33.1) | 19.1 (21.1) | 24.1 (30.6) | 39.9 (55.1) | 22.4 (47.4) | 23.7 (57.9) | 26.5 (40.2) | 12.2 (26.6) |
| **All 32 spawning** | **21.5 (33.1)** | 19.9 (21.1) | 24.1 (30.6) | 40.8 (55.1) | 22.4 (47.4) | 23.7 (57.9) | 26.5 (40.2) | 12.2 (26.6) |
| First hybrid | 0.1 (0.2) | 0.1 (0.2) | 0.1 (0.2) | 0.3 (0.3) | 0.1 (0.2) | 0.1 (0.2) | 0.1 (0.2) | 0.2 (0.4) |
| All 15 hybrids | 23.5 (37.1) | 24.8 (36.5) | 25.1 (36.0) | 43.0 (48.5) | 22.1 (33.2) | 26.7 (58.7) | 23.6 (30.1) | 26.4 (36.6) |
| All 3 bosses | 24.8 (29.8) | 26.5 (33.1) | 24.8 (38.1) | 38.1 (54.8) | 16.5 (36.1) | 8.1 (16.1) | 19.8 (23.1) | 12.5 (27.8) |
| **Full Dex (50)** | **30.1 (38.5)** | 28.1 (38.1) | 28.8 (43.1) | 47.3 (57.1) | 32.0 (52.0) | 29.7 (>60) | 28.3 (40.2) | 32.4 (36.8) |

What the numbers say:

1. **The rebirth gate sets the Dex pace.** Every tier finishes right after the family that completes it opens: Rare at rank 6 (7 h), Epic, Legendary and Mythic at rank 10 (17-18 h). With every family open from the start (`no_rank_gate`), all 32 spawning species take 12 h instead of 21.5 h. So the rebirth-pace assumption in §7.2 matters more than any spawn weight, and step 8's telemetry is what will confirm the 20-40 h estimate.
2. **The top tiers are fed by merges and steals, not by the fountain.** An active player makes about 74 catches an hour (9 % of all spawns) but gets their first Mythic mostly from merging or stealing. The new weights and caps make the first Secret a goal of about 3-4 h instead of 1.4 h, without slowing the full Dex much (30 h vs 28 h). The full set of Secrets still waits for Starlight.
3. **The merge assist is a small help.** It brings the last Secret 2.6 h sooner at the median. It is cheap, so it stays in the proposal, but it is optional (decision 2).
4. **Recipes work as a mid-game track.** The first hybrid comes within minutes (Soda Pop from three Meadow Commons). All 15 take about as long as the spawning Dex, because the late ones need Starlight ingredients and three Legendaries or Mythics of specific species.
5. **Server size matters less than expected.** A full 8-player server delays the top tiers (first Mythic 2 h) but not the Dex. A 2-player server gets fewer spawns (the 18 cap binds: 666/h) and still keeps pace, because there is less competition. A veteran on the server makes bosses much faster (Mecha Goo needs a Starlight fountain) and dilutes your drops a little.
6. **Casual players** (35 % activity, half the rebirth pace) need about 47 h for the full Dex. Their first Secret takes about 8 h, which is long but fine for a 1-in-2000 tier.

Full tables, including per-species medians and how each species was first found (wild / merge / steal / recipe / boss): [economy-sim/results.md](economy-sim/results.md).

---

## 8. Decisions for Merijn

1. **Rebirth pace = Dex pace.** Families open at 3 / 6 / 10 rebirths with 15 / 4 / 5 / 8 species. With the assumed pace (rank 10 at about 17 played hours) the full Dex takes about 30 h for an active player and 47 h for a casual one. Is that the length you want, and do you know the real rebirth pace? If rank 10 really takes 40 h, move Starlight's top species down to rank 8 or open fewer at 10.
2. **Make the top rarer, and how.** The proposal: Legendary / Mythic / Secret weights 1.45 / 0.35 / 0.1 -> 1.2 / 0.2 / 0.05; no +2 jump into Mythic; **no random merge into Secret** (Mythic x3 gives a Mythic); a 35 % merge assist toward missing species. Players will feel this as a nerf of the vat. The alternative is today's odds (first Secret at 1.4 h).
3. **Recipes: one tier only.** All three inputs are one tier, and the hybrid is one tier up. The vat and menu rules stay simple and recipes can't be probed for free, but some recipes differ from the art's suggested parents (Sushi = chomp + chomp + pengoo, Dragon King = king x3). The alternative is mixed-tier recipes, which need a new vat rule and a recipe book.
4. **Boss shape.** The proposal: every 20 min, a team meter fight, then a slap-able carry race, then an unstealable trophy, and a free egg for every helper. That replaces today's "first grab wins" boss. Do you want the trophy unstealable, and is 20 min the right pace (3 per hour, beside the hourly Slime Rain)?
5. **No eighth tier.** Keep Mythic and Secret as the top and make them feel special (size floors, aura, longer parade, eruption on a Secret spawn). The Dex counts the 50 species.
