# §45 Slime ladder: rarity gates, Celestial and Divine, shines, jackpots, the events sign

**Status:** design approved by Merijn (docs/slime-ladder-plan.html, the pacing-sim report). Server-authoritative; the client only reads State and model attributes.

Every stretch of the game has its own rarity to chase: Legendary in the first hours, Mythic to about 18 played hours, Secret to about 45, then Celestial, with Divine as the late jackpot. Weather shines keep even a full plot improvable.

## 45.1 Rarity and egg gates

- `Config.CATCH_REBIRTHS[tier]`: rebirths a player needs to **grab** a wild slime of that rarity from the fountain (Mythic 5, Secret 12, Celestial 18, Divine 25). A Mystery Egg uses its kind's `rebirths` (`Config.MYSTERY_EGG.KINDS`, contract/mystery-egg.md: Speckled open, Shiny 1, Golden 3, Cosmic 6, for grabbing and stealing). `GrabBlock.rebirthsFor(slime)` reads both.
- `Carry.grab` refuses a wild grab with `"Rebirth <n> to grab this"`. Stealing a slime is never gated (a Mystery Egg's own gate also covers stealing).
- The wild model carries `Constants.GRAB_REBIRTHS_ATTRIBUTE` (`GrabRebirths`, nil = open). The client's grab card (`GrabBlock.reason` with `Me.rebirths` from State) shows the same text.
- The Lucky Charm only lifts a slime into a rarity the player may grab; a lucky egg stops at `SECRET_TIER`.

## 45.2 Time guarantees

`Config.GUARANTEE_SECONDS[tier]`: once that long passes on a server without a drop of `tier` or higher, the next fountain drop is at least `tier` (a Legendary every 5 min, a Mythic every 15 min), on top of the count pity (`Spawner.minTier`, `world.lastTierAt`). `Spawner.guaranteeIn(world, tier, now)` is the time left. There is no HUD timer: the events sign shows it (45.7).

## 45.3 Celestial (8) and Divine (9)

- Two rarities above Secret in `Config.RARITIES` (`MAX_TIER` = 9; `SECRET_TIER` stays 7). Every per-tier table has nine entries (`WILD_PRICE_SECONDS`, `MERGE_BREW_SECONDS`, `CATCH_REBIRTHS`, `TIER_SIZE_FLOOR`, `TIER_LIFETIME_MULT`, `PET_PASSIVES.KIND_BY_TIER`). The top-tier looks that were Secret-only apply to tier 7 and up.
- Species (Classic, kind `"spawn"`): Celestial `lunara solaris nebulon`, Divine `aurora goo_oracle kirin`, each with its own kit mesh.

## 45.4 Merges on the ladder

- Rank merge gates (`REBIRTH_TIERS[*].merge`, contract/merge-vat.md §21.9): Common at 0, Uncommon 1, Rare and Epic 3, Legendary 5, Mythic 15, Secret 20. A random merge result is at most `MERGE_MAX_TIER` (Celestial); three Celestials or Divines are refused.
- **Shine recipe** (`Config.SHINE_RECIPE`): three Secrets that share a shine brew a random Divine species (no jump, no assist) from rebirth 25, and the child keeps the shine. Without the shared shine, three Secrets brew a Celestial.

## 45.5 Shines (weather mutations)

- `Genome.Slime.shine: string?`, a `Config.SHINES` id: `Gold` x1.5 (any weather, 3 %), `Diamond` x2 (Snow, 4 %), `Rainbow` x3 (Starfall, 2 %). A wild slime rolls at most one when it spawns (`Spawner.rollShine`, on `world.shineRng` so the fountain's slime sequence never shifts; `world.weather` is the live weather). Eggs, bosses and merges never roll one.
- `Genome.baseIncome` multiplies by it, so prices follow. It travels when stolen. A merge child keeps a shine only when all three parents share it.
- Saved as the optional slime field `shine` (missing = none, no version bump; the old v4-v6 `mutation` field stays stripped). Shown in the menu name ("Gold Bumble": `Genome.displayName`, the rare toast), in the look below and as a sparkle (`server/SlimeShineView`: a `ShineFx` ParticleEmitter on the Body; the model attribute `Constants.SHINE_ATTRIBUTE` = the id).
- **Look.** Each `Config.SHINES` row has `kit` (`gold`, `diamond`, `rainbow`), `material`, `reflectance`, `tint` and `rainbow` (drawn in every colour).
  - Model: the slime wears the recoloured copy of its species kit, `slime_<id>_<kit>` (`MeshAssets.mutationKit`; the same mesh and size as `slime_<id>`, other vertex colours: gold, icy diamond, rainbow bands, dark face kept), in the row's material. Copies are made by `shared/modeling-kit/tools/slime_pool_export.py --mutation all` (`models/_slimepool.py` `mutate`) and uploaded as Models; `tools/slime_mutation_assets.py` writes the `MeshAssets` block from `uploaded.json` (`tests/SlimeMutationKits.spec`). `server/SlimeMesh` fetches a copy the first time a slime needs it; until it arrives the slime wears its species kit and `SlimeMesh.pendingKit` names the copy, so `WorldView` rebuilds it.
  - Sparkles: bigger, on the slime's surface, white glints fading into the shine's colour (a rainbow for `rainbow`), 12-16 a second.
  - Tag (`contract/slime-labels.md`): `LabelName` is the plain name ("Bumble"); the floating tag reads `Constants.SHINE_ATTRIBUTE` and draws the shine on its own pill next to the rarity pill (`SlimeLabel.View.shine`). The pad plank has no pill row and writes "Gold Bumble".

## 45.6 Jackpots

- One jackpot species per top rarity: `jackpot` (Secret), `star_emperor` (Celestial), `goo_god` (Divine). `SlimeRoster.Entry.jackpot = true`, `income` x5. Together the jackpots are `Config.JACKPOT_SHARE` (10 %) of the drops of their rarity (`Genome.pickWeighted`).
- A jackpot spawns from the fountain like its rarity, is never a random merge result, can't be merged (`"jackpot slimes can't be merged"`) and is never asked for by a rebirth.

## 45.7 The Upcoming Events wall

A Hall of Fame board (`Props.leaderboardBoard` with the `phoenix_top_earners_board` mesh, placed by `WorldProps` at `WorldLayout.EVENT_BOARD`: the middle of the lawn between the plot 5 and 6 entrances, right behind the hub spawn, facing the fountain; that lawn holds nothing else), filled by `server/EventBoardView`: a rainbow "UPCOMING EVENTS" bar, then one pale coloured card per event on a light face (`Shared.EventBoard.rows`): the boss (arrival, or "<name> is here!"), Slime Rain (in, or time left), the weather with the shine it allows and when it changes, the guaranteed Legendary and Mythic, and a running admin or weekly event. Each card has an icon (`EventBoardView.ICONS`: an uploaded HUD image or a glyph), an accent colour (`EventBoard.ACCENTS`), a title, a detail line and a "m:ss" countdown. Running events come first, then the soonest; at most `EventBoard.MAX_ROWS`. The server refreshes once a second and rebuilds the cards only when their set or order changes (`EventBoard.layoutKey`).

The Hall of Fame boards share its look: the same frame, a light cream-white face, a gradient title bar in the board's colour and one rounded card per row, the top three on pale gold, silver and bronze cards and the viewer's own row green (`Props.BOARD_PALETTE`, `WorldLeaderboard.rowStyle`).
