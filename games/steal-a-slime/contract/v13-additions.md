# 8. v13 additions (2026-10-15, Phoenix)

**Status:** contract first. Names in this section are frozen. The server implements them in the v13 commits that follow; until then a field may be missing, so clients should treat new fields as optional (`state.upgrades or {}`). Where this section and §1-§7 disagree, this section wins.

## 8.1 Request actions (new)

| Action | Args | Effect / `message` on failure |
|---|---|---|
| `"BuyUpgrade"` | `upgradeId: string` (one of `Config.UPGRADES[i].id`: `"Income"`, `"CarrySpeed"`, `"OfflineCap"`, `"Luck"`) | Buys the next level for `Upgrades.cost(id, level)`. Fails with `"unknown upgrade"`, `"locked: reach <n> rebirths"`, `"already maxed"` or `"not enough cash"`. Permanent: saved, kept on rebirth. Rate limit 0.5 s. Notify `"<Name> level <n>!"` (`"good"`, `"Cash"`). |

Goals and Slimedex rewards are **paid automatically** (no claim action). Nothing else is added; every v12 action keeps its name and args.

## 8.2 `State` fields (new; §5.1 fields are unchanged)

```luau
{
	walkSpeed: number,             -- server WalkSpeed while NOT carrying (16, or 22 with the Speed Coil)
	incomeMultiplier: number,      -- total income multiplier: rebirth x upgrade x rank x dex (>= rebirthMultiplier)
	rebirthTitle: string,          -- current rank title, e.g. "Slime Rookie"
	rebirthTiers: { { rebirths: number, title: string, text: string, unlocked: boolean } },  -- every rank, ascending
	nextRebirthTier: { rebirths: number, title: string, text: string }?,                     -- nil at the top rank
	upgrades: { {                  -- Config.UPGRADES order
		id: string, name: string, text: string,  -- text = what the next level does, e.g. "+10% income"
		level: number, maxLevel: number,
		price: number?,            -- nil = maxed or locked
		requires: number,          -- rebirths needed
		unlocked: boolean,
	} },
	goals: { {                     -- Config.GOALS order; chains of stages
		id: string, title: string, -- title of the CURRENT stage, e.g. "Catch 10 slimes"
		stat: string, progress: number,
		stage: number, stages: number,  -- stage = stages already paid (0..stages)
		target: number?, reward: number?, -- current stage; nil when done
		done: boolean,
	} },
	dexRewards: { { count: number, reward: number, bonus: number, claimed: boolean } }, -- Config.DEX_MILESTONES
	dexBonus: number,              -- income bonus from paid dex milestones (0.05 = +5 %)
	stats: { caught: number, merges: number, locks: number, sold: number,
	         stolen: number, earned: number, rebirths: number },
	tutorialStepId: string?,       -- TutorialProgress.STEPS[tutorialStep]; nil = finished
	boss: { active: boolean, endsAt: number? },  -- Boss Slime in the world (wild or carried); endsAt = expiry (server time)
}
```

Every field above is in every snapshot (the server never leaves one out); only the `?` fields can be nil. `boss` changes (spawn, expiry, catch, a dropped boss's new expiry) push State to everyone, like `rain`.

`carrying.walkSpeed` now starts from `walkSpeed` (the Speed Coil also helps while carrying) and the CarrySpeed upgrade shrinks the slowdown.

## 8.3 Tutorial (replaces the §2 list)

`TutorialProgress.STEPS = { "Grab", "Deposit", "Lock", "BuyPad", "Merge", "Steal", "Rebirth" }` (7 steps). `"BuyPad"` (new, step 4) finishes on a successful `Request("BuyPad")` or `BuyPadPrompt`. Indices after 3 shift by one: **Jolt** adds a step 4 to `src/ui/Tutorial.STEPS` (suggested: title "Buy a pad", body "More pads = more slimes. Walk to the glowing pad on your plot and buy it.") and **Archer** shifts the arrow targets: 1 Crater, 2 own `HomeZone`, 3 own `LockButton`, **4 own plot's pad carrying `BuyPadPrompt`**, 5 own `MergeVat`, 6 another owned plot's `Base`, 7 none. Prefer keying on `State.tutorialStepId` / Player attribute `TutorialStepId` (names, stable) over the number. Save migration: a stored `tutorialStep` of 4..6 (old Merge/Steal/Rebirth) maps to 5..7; 0 stays done.

## 8.4 Instance attributes (new)

| Where | Attribute (Constants name) | Type / meaning |
|---|---|---|
| Player | `TutorialStepId` (`TUTORIAL_STEP_ID_ATTRIBUTE`) | `string?`, same as `State.tutorialStepId` |
| Player | `TargetWalkSpeed` (`WALK_SPEED_ATTRIBUTE`) | `number`, the WalkSpeed the server enforces right now (coil and carry included) |
| Player | `RebirthTitle` (`REBIRTH_TITLE_ATTRIBUTE`) | `string`, rank title (for name tags) |
| `Plot_<i>` | `Locked` (`PLOT_LOCKED_ATTRIBUTE`) | `boolean`, true while `LockUntil > now` (flips on expiry, not only on purchase) |
| `Plot_<i>` | `LockCost` (`PLOT_LOCK_COST_ATTRIBUTE`) | `number`, owner's current lock price (0 = free plot) |
| `Plot_<i>` | `PadsUnlocked` (`PLOT_PADS_UNLOCKED_ATTRIBUTE`) | `number`, owner's unlocked pads (0 = free plot) |
| `Plot_<i>` | `NextPadCost` (`PLOT_NEXT_PAD_COST_ATTRIBUTE`) | `number?`, nil when maxed or free |
| `Pad_<j>` | `Unlocked` (`PAD_UNLOCKED_ATTRIBUTE`) | `boolean`, `j <= PadsUnlocked` (false on a free plot) |
| `Plot_<i>` | `OwnerUserId`, `LockUntil`, `Rebirths` (§5.2) | set by the server on every reconcile (`WorldView.updatePlots`); Archer's PlotDecor reads them with `Locked`. Wild slime models carry `Tier` (factory), `State = "Wild"` and `RareSpawn` (below), which PlotVisuals/RareSpawn read. |
| `Plot_<i>` | `DexCount` (`PLOT_DEX_COUNT_ATTRIBUTE`) | `number`, owner's discovered Slimedex entries (0 = free plot) |
| `Plot_<i>` | `DexTotal` (`PLOT_DEX_TOTAL_ATTRIBUTE`) | `number`, always 1152 (= `State.dexTotal`) |
| `Plot_<i>` | `DexTierMask` (`PLOT_DEX_TIER_MASK_ATTRIBUTE`) | `number`, optional for readers: bit k-1 set when the owner has discovered any tier-k slime (0 = free plot) |
| `Plot_<i>` | `PlotPrice` (`PLOT_PRICE_ATTRIBUTE`) | `number?`, reserved for paid plots; **never set in v13** (plots are free), so readers show no price |
| slime model (server SlimeMesh) | `Species` (`SPECIES_ATTRIBUTE`) | `string?`, the SlimeRoster id of a typed slime (v28); nil for untyped / older slimes. Its colour and material come from `Shared.SlimeLooks` (unmutated slimes only: a mutation material wins). |
| wild slime model | `RareSpawn` (`RARE_ATTRIBUTE`) | `number?`, the tier, only on wild Legendary+ (tier >= `RARE_ANNOUNCE_TIER`) drops |
| wild slime model | `Riding` (`RIDING_ATTRIBUTE`) | `true` while the slime rides the fountain slide (emerge to landing / lane entry), else `nil`; the pc-watcher ring_slimes probe skips these |
| wild slime model | `DespawnAt` (`DESPAWN_AT_ATTRIBUTE`) | `number?`, server time the slime is removed (= its expiry). Set only for the last `Config.DESPAWN_TELEGRAPH_SECONDS` (5) while uncarried, and only with `FEATURES.DespawnTelegraph`; nil otherwise. Clients count down `DespawnAt - workspace:GetServerTimeNow()` (`Shared.DespawnTelegraph`). The server still removes only at expiry, never earlier. Flag off = silent removal as before. The client countdown + shrink never fade, blink or highlight the slime (v30 C8). |
| `Pad_<j>` | `Habitat` / `HabitatFrom` / `HabitatAt` (`HABITAT_ATTRIBUTE` / `HABITAT_FROM_ATTRIBUTE` / `HABITAT_AT_ATTRIBUTE`) | `string` / `string` / `number` (server time): current habitat id, the one before it, when it changed. Only with `FEATURES.Habitats`; never set when off. |
| `workspace` | `RareSpawnId` / `RareSpawnTier` / `RareSpawnAt` (`RARE_SPAWN_ID_ATTRIBUTE` / `RARE_SPAWN_TIER_ATTRIBUTE` / `RARE_SPAWN_AT_ATTRIBUTE`) | `string` / `number` / `number` (server time) of the latest rare drop; set together on each one (effects key on `RareSpawnAt` changing) |
| owner-only `ProximityPrompt` | `ShowOnlyToUserId` (`PROMPT_OWNER_ATTRIBUTE`) | `number?`, the plot owner. **Clients other than that user keep the prompt disabled locally** (same rule as `HideFromUserId`, inverted; Jolt's PromptHide). nil (free plot) = prompt is also server-disabled. The server refuses non-owners anyway (Notify `"This is <name>'s base"`). |

## 8.5 Plot prompts (replace §2 "Owner-only prompts")

All three carry `ShowOnlyToUserId = owner`, are `Enabled = false` on a free plot, `RequiresLineOfSight = false`, `HoldDuration = 0`. Names are in `Constants`.

| Prompt (Constants) | Parent | KeyCode | ActionText | ObjectText |
|---|---|---|---|---|
| `LockPrompt` (`LOCK_PROMPT_NAME`) | `LockButton` | E | `"Lock base $<cost>"` while open, `"Extend lock $<cost>"` while locked, `"Lock is maxed"` at `LOCK_MAX_REMAINING` | `"<name>'s base: OPEN"` or `"<name>'s base: LOCKED m:ss"` (updated every reconcile) |
| `BuyPadPrompt` (`BUY_PAD_PROMPT_NAME`) | the lowest locked `Pad_<j>`; moved as pads unlock; parked (disabled) on the last pad when all are unlocked | E | `"Buy pad $<cost>"` | `"Pad <j> of <PADS_MAX>"` |
| `MergePrompt` (`MERGE_PROMPT_NAME`) | `MergeVat` | E | `"Auto-merge"` | `"Merge vat"` |

`LockPrompt` = `Request("Lock")`, `BuyPadPrompt` = `Request("BuyPad")`, `MergePrompt` = `Merge.findPair` + `Request("Merge")`. Results are Notifies.

## 8.6 Notify sound names (added to §3)

`"Rare"`: a Legendary+ wild drop (everyone, `"good"`: `"A LEGENDARY <name> spilled from the fountain!"`, Mythic: `"A MYTHIC <name> spilled from the fountain!!"`; mutations use their display name). `"Goal"`: a goal stage or dex milestone paid (`"good"`: `"Goal complete: <title>! +$<n>"`, `"Slimedex <count>: +$<n> and +<pct>% income!"`). **Sound IDs are stand-ins:** Jolt's `src/ui/Sounds` maps `"Rare"` and `"Goal"` to placeholder catalog sounds (Rare reuses Rain `12222200`, Goal reuses Cash `12222140`) until real ones are picked. A new rebirth rank sends `"New rank: <title>! <text>"` (`"good"`, `"Rebirth"`), and a Luck upgrade proc sends `"Lucky! Your <old> slime became <rarity>!"` (`"good"`, `"Cash"`).

## 8.7 Rarity curve

- `Config.RARITIES[i].weight` = 52, 28, 13, 5.2, 1.45, 0.35 (was 60, 25, 10, 4, 0.9, 0.1).
- **Pity** (per server, `world.pity`): after `PITY_EPIC` (30) drops in a row without an Epic+, the next drop is at least Epic; after `PITY_LEGENDARY` (300) without a Legendary+, at least Legendary. Rain luck stacks.
- Legendary+ (`RARE_ANNOUNCE_TIER` = 5) wild drops (fountain or rain, not the Boss Slime, which has its own toast) get the `RareSpawn` attribute, update the workspace `RareSpawn*` attributes and send the `"Rare"` Notify to everyone.

## 8.8 Progression

- **Rebirth cost:** `REBIRTH_BASE_COST x REBIRTH_COST_GROWTH^min(r, REBIRTH_LATE_FROM) x REBIRTH_COST_GROWTH_LATE^max(0, r - REBIRTH_LATE_FROM)` with 5000 / 3 / 5 / 2 (unchanged up to rebirth 5, then x2 per rebirth).
- **Ranks** (`Config.REBIRTH_TIERS`, reached at rebirth count; perks don't stack, the best unlocked value wins):

| Rebirths | Title | Perk |
|---|---|---|
| 0 | Slime Rookie | |
| 1 | Goo Getter | unlocks the CarrySpeed upgrade |
| 3 | Slime Wrangler | unlocks the OfflineCap upgrade |
| 5 | Blob Baron | unlocks the Luck upgrade |
| 6 | Goo Tycoon | keep 2 slimes on rebirth |
| 7 | Jelly Magnate | +10 % income |
| 8 | Ooze Overlord | +30 s locks |
| 10 | Slime Sovereign | keep 3 slimes, +25 % income |
| 12 | Gel Emperor | +60 s locks |
| 15 | Gelatinous Legend | keep 4 slimes, +50 % income |
| 20 | Mythic Monarch | +100 % income |
| 30 | Slime Deity | keep 5 slimes, +200 % income |

  Rebirth keeps the favourite first, then the best slimes by income, up to the rank's keep count (not busy ones).
- **Upgrades** (`Config.UPGRADES`, `src/shared/Upgrades.luau`; price of level n+1 = `base x growth^n`):

| id | Name | Per level | Max | base / growth | Needs rebirths |
|---|---|---|---|---|---|
| `Income` | Slime Snacks | +10 % income | 10 | 2 000 / 2.5 | 0 |
| `CarrySpeed` | Strong Arms | -15 % carry slowdown | 4 | 5 000 / 3 | 1 |
| `OfflineCap` | Night Shift | +1 h offline income cap | 4 | 20 000 / 3 | 3 |
| `Luck` | Lucky Charm | +4 % chance a wild slime you bring home is one rarity higher | 5 | 100 000 / 3 | 5 |

- **Income multiplier** = `rebirthMultiplier x (1 + 0.1 x Income level) x (1 + rank income bonus) x (1 + dexBonus)`. `SlimeView.income` and `incomePerSec` include it; sell prices don't.
- **Goals** (`Config.GOALS`, `src/shared/Goals.luau`; titles are singular for a target of 1: "Catch 1 slime"): stage targets / base rewards; the paid reward is `base x rebirthMultiplier` at the time it's paid. Checked every second and on join, so old saves get past stages retroactively.

| id | Title | Stat | Targets | Base rewards |
|---|---|---|---|---|
| `Catch` | Catch <n> slimes | caught | 1, 10, 50, 200, 1000 | 50, 500, 5K, 50K, 500K |
| `Merge` | Merge <n> times | merges | 1, 10, 50, 250 | 200, 2K, 25K, 250K |
| `Steal` | Steal <n> slimes | stolen | 1, 10, 50, 200 | 300, 3K, 30K, 300K |
| `Lock` | Lock your base <n> times | locks | 1, 25, 100 | 100, 2.5K, 25K |
| `Pads` | Unlock <n> pads | pads | 5, 6, 7, 8 | 200, 1K, 5K, 20K |
| `Earn` | Earn $<n> in total | earned | 10K, 1M, 100M, 10B | 1K, 50K, 2M, 100M |
| `Rebirth` | Rebirth <n> times | rebirths | 1, 3, 6, 10, 20 | 2K, 20K, 500K, 5M, 100M |

  Stats: `caught` (wild slimes deposited), `merges`, `locks` (locks bought), `sold`, `stolen` (= `totalStolen`), `earned` (= `totalEarned`), `rebirths`, `pads` (= `padsUnlocked`).
- **Slimedex rewards** (`Config.DEX_MILESTONES`, `src/shared/Collection.luau`): at 10 / 25 / 50 / 100 / 200 / 400 / 720 discovered: cash 500 / 2.5K / 10K / 50K / 250K / 1.5M / 10M (x rebirthMultiplier) and a permanent income bonus +2 / +3 / +5 / +5 / +10 / +15 / +25 %.

## 8.8a Rebirth needs a slime (v29)

Rebirth number N also needs one owned slime (`data.slimes`, i.e. on a pad) of the
`Config.REBIRTH_SLIMES[N]` species (a SlimeRoster id; a level without an entry uses the
last entry below it). The cash cost stays. `Progression.canRebirth` rejects with
`need a <Species Name>` when it is missing. The slime is **not consumed**: the normal
rebirth wipe and keeper rule apply, so it only survives as a keeper. State gains
`rebirthSlime: { id, name, tier, color, owned }?` (nil at `MAX_REBIRTHS`); `canRebirth`
already includes the slime check.

## 8.9 DataStore schema v3 (superseded by v4, §8.9a)

Same store and key. v3 = v2 plus:

```luau
upgrades = { Income = n, CarrySpeed = n, OfflineCap = n, Luck = n },  -- levels, missing = 0
stats = { caught = n, merges = n, locks = n, sold = n },
goals = { [goalId] = stagesPaid },
dexRewards = n,                                                       -- dex milestones paid (0..#DEX_MILESTONES)
```

Migration (`SaveData.migrate`, pure, tested with a v12-shaped save): v1 -> v2 as before; v2 (or a version-less v2 shape) -> v3 adds zero upgrades / stats / goals / dexRewards, seeds `stats.caught = max(#slimes, dex count)`, and remaps `tutorialStep` 4..6 -> 5..7 (§8.3). Unknown or newer versions are read field by field with the v3 sanitizer. Everything is clamped (levels to `maxLevel`, stages to `#targets`).


## 8.9a DataStore schema v4: stacking mutations (`Config.SAVE_VERSION = 4`)

Same store and key; no key or field is renamed. v4 = v3 plus `slimes[i].mutations = { name, ... }` (at most `Config.MAX_MUTATIONS`; a fused combo from `Config.COMBOS` is stored by its combo name). The single `mutation` field is still written (the strongest entry, "None" when empty): v3 readers, visuals and dex keys use it.

`SaveData.migrateV3` (v1/v2/v3 -> v4) is pure, returns a copy and is idempotent: `mutations = {}` for "None" / missing, else `{ mutation }`; a slime that already has a list is untouched. Value is the product of the list (a single entry = the v3 value). A version above 4 is never rewritten by the migration; `Genome.sanitize` reads both fields. `FEATURES.MutationStacking` (default on) only controls new rolls (stack chance `STACK_MUTATION_CHANCE`, combo fusing, merge carry-over); migration and loading always run. The Dex counts a stacked slime under its primary mutation (`DEX_TOTAL` adds `#COMBOS` with the flag on).


## 8.9b DataStore schema v5: weather mutations (`Config.SAVE_VERSION = 5`)

No field changes. `SaveData.migrateV4` (v4 -> v5, pure, idempotent) drops duplicate / "None" / non-string entries from each slime's `mutations` and rebuilds a missing list from `mutation`; clean slimes pass through untouched. New mutation ids `Wet`, `Frozen` and combos `Sleet`, `Comet` are added; no id or key is renamed. `FEATURES.WeatherMutations` (default on) gates only the roll bonus from `Config.WEATHER[id].mutation / chanceBonus` (WEATHER.md); loading never depends on it.

## 8.9c DataStore schema v6: settings, plotSkin, stealLog (`Config.SAVE_VERSION = 6`)

- **New field:** `settings = { musicVolume: number 0..1, sfxVolume: number 0..1, muted: boolean }` (`Shared.AudioSettings`; volumes rounded to 0.01; defaults `Config.AUDIO.DEFAULT_MUSIC_VOLUME` / `DEFAULT_SFX_VOLUME`, not muted). Missing or junk fields load as their default.
- **Migration:** `SaveData.migrateV5` (v5 -> v6, pure, idempotent) normalises three fields that were unversioned before: `plotSkin` (a known skin id is kept, else `"classic"`; unlock is still checked on load), `stealLog` (`StealAlert.clean`, capped at `LOG_CAP` 12, junk -> empty) and `settings` (`AudioSettings.clean`). It never looks at a feature flag: with `PlotSkins`, `StealAlerts` or `Audio` off the field is kept, saved again and simply unused.
- **Remote:** `Request("SetAudioSettings", musicVolume: number, sfxVolume: number, muted: boolean)`, rate limit 0.5 s. Wrong types and non-finite numbers are `"bad argument"`; numbers are clamped to 0..1. With `FEATURES.Audio` off it is refused (`"audio settings are off"`) and the save is not touched.
- **State:** `settings?` (same shape), only with `FEATURES.Audio` on.

## 8.10 Speed Coil (replaces the §2 bullet)

Owning the coil makes the server enforce WalkSpeed `SPEED_COIL_WALK_SPEED` (22) when not carrying and `22 x (1 - slowdown)` while carrying (was: ignored while carrying). The server always enforces its target (Player attribute `TargetWalkSpeed`), every 0.1 s and on every `CharacterAdded`, instead of only overwriting speeds it recognised. The `SpeedCoil` tool still sits in the Backpack (cosmetic; `ToolTip` "Speed Coil: always on").

## 8.11 Dropped slimes

A dropped wild slime is snapped to the first **collidable** surface under the drop point: raycast from 4 studs above the carrier's root straight down (`RespectCanCollide = true`, excluding characters and slime models), so it lands on the ground, a plot base or a ramp, never on a head, canopy or invisible trigger. No hit within 200 studs: it goes back to its fountain landing spot. It falls there over 0.3 s and stays anchored (§4). The Lune harness checks it (`tools/livetest`).

## 8.12 Test hooks (server-only, never live)

`src/server/TestHooks.luau` lets scripted sessions grant cash and skip time on a live `world`. **Guard:** (1) it is not wired to any remote, prompt or chat command, so no client can reach it; only server code that already runs with full authority (a Luau Execution task, Lune tests) can call it; (2) `TestHooks.enable(world)` refuses (returns false, every hook then errors) unless `workspace.DataStoreMode == "Memory"`, and the publish checks (`scripts/check-place`, `tests/PlaceSafety.spec`) already fail any place that sets that attribute; (3) `tests/TestHooks.spec` fails if any `src/` file other than TestHooks and its spec references it.
