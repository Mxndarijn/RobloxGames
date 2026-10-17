# Steal a Slime: team contract

**Design:** `/workspace/roblox/steal-a-designs.md` §6. **Date:** 2026-10-14, v13 additions 2026-10-15 (§8).

**Owners:**
- **Phoenix:** server gameplay.
- **Archer:** visuals.
- **Jolt:** UI and tests.
- **Shared:** config and types. Changes to shared files go through this contract.

If code and this file disagree, fix one of them in the same change. The tests in `tests/Contract.spec.luau` guard §3 and §6.

## 1. Folder layout and ownership

```
default.project.json          Rojo tree (below)                                 shared
src/shared/      -> ReplicatedStorage.Shared       (ModuleScripts; pure, Lune-safe)
  Config.luau      every tunable, values from the design (§6)                   shared
  Constants.luau   remote / folder / tag / DataStore names                      shared
  Remotes.luau     remote definitions + Request action arg types; setup()/get()  shared
  Types.luau       network payload types (State, SlimeData, ...)                 shared
  Genome, Rng, Merge, Economy, PlayerData, SaveData, SessionLock,
  Steal, Progression, Fountain (legacy alias `Volcano`), Validate, Shop, TutorialProgress, DayNight,
  Perks, Upgrades, Goals, Collection (v13, §8.8), Habitats (FEATURES.Habitats)
                   pure gameplay rules                                          Phoenix
src/server/      -> ServerScriptService.Server     (Script + child ModuleScripts) Phoenix
  init.server.luau thin adapter: Remotes.setup(), Request -> Actions.handle,
                   player lifecycle, Heartbeat loop, autosave, BindToClose
  pure (Lune-safe, unit-tested): World (all live state + outbox), Spawner
  (fountain + Slime Rain), Carry (grab / deposit / drop), StealService (lock,
  steal, escape home, slap), Income (per-second + capped offline), MergeVat,
  Rebirth, Sessions (join / leave), Actions (Request dispatcher), Snapshot
  (State payload + coalescing), Scene (desired slime models), GameLoop,
  DataService (retries + session lock, backend injected), Leaderboard,
  PlotLookup (plot / pad by PlotIndex / PadIndex attribute), SlimeMesh
  (mesh look over ModelFactory, loader + factory injected), Rescue (kill plane),
  PlotPrompts (plot prompt texts / lock + pad attributes, §8.5), Milestones
  (goal + Slimedex payouts, §8.8), TestHooks (test sessions only, §8.12),
  HabitatPads (pad
  habitat state, FEATURES.Habitats), PodiumAvatars (top-3 podium rigs:
  description cache, fallback, debounced refresh; adapter injected)
  Roblox adapters: WorldView (models, prompts, plot attributes, HomeZone,
  WalkSpeed, Speed Coil tool, kill-plane rescue), WorldProps (ShopStand,
  LeaderboardBoard, TutorialNpc, §5.3), FallbackWorld (greybox §5.3 if
  WorldBuilder is missing), PodiumRigs (R15 avatar rigs on Podium_1..3 in
  workspace.PodiumAvatars, BillboardGui NameLabel)
src/visuals/shared/ -> ReplicatedStorage.Visuals   (ModuleScripts)              Archer
  ModelFactory.luau  slimeData -> Model (§4)
  WorldBuilder.luau  WorldBuilder.build(parent) -> Map, Plots (§5.3); layout in WorldLayout
                     (incl. PROP_SPOTS)
  Props.luau         ShopStand / SpeedCoil / TutorialNpc / TutorialArrow / LeaderboardBoard builders
  Effects.luau       Effects.play(kind, target) bursts + emitter / light presets (§5.4)
  MinimapData.luau   minimap points of interest (§2 Extras)
src/visuals/client/ -> StarterPlayerScripts.VisualsClient (LocalScript)         Archer
  jiggle/blink, carried wriggle, escape bounce, Slime Rain particles + tint,
  volcano smoke / embers / eruptions, tutorial arrow (§5.4), follow pets (§2 Extras)
src/visuals/tools/  Archer's Lune map tools (not in the Rojo tree). build-map writes
                    src/visuals/static/*.rbxm, which is NOT mapped: world/ is the only
                    map source in default.project.json                          Archer
src/ui/          -> StarterPlayerScripts.UI         (LocalScript + modules)      Jolt
  HUD, plot/merge/rebirth panels, Slimedex, steal alerts, toasts, leaderboard
tests/           Lune unit tests (not in the Rojo tree)                          Jolt
world/           -> Workspace: Map, Plots, HubSpawn (.rbxmx, generated)          Phoenix
scripts/         Lune build tools (not in the Rojo tree): gen-world, check-place Phoenix
Packages/        -> ReplicatedStorage.Packages (Wally, optional, git-ignored)
```

**Rules:**
- `src/shared` modules require each other with `if script then require(script.Parent.X) else require("./X")`. That lets them run unchanged in Roblox and under Lune. They must not touch Roblox APIs at load time. `Remotes.setup/get` only do so when called.
- Pure `src/server` modules follow the same rule; they reach shared modules with `if script then require(ReplicatedStorage.Shared.X) else require("../shared/X")`.
- The client never decides outcomes. It only calls `Request` and renders `State`.
- Archer's code reads Instance attributes (§5.2) and never fires remotes.
- `UI` and `VisualsClient` are separate LocalScripts under StarterPlayerScripts. They must not sit inside each other, or Rojo would nest them.

## 2. Gameplay summary (what the server implements)

- **Spawner:** a wild slime drops every `SPAWN_INTERVAL`, up to `MAX_WILD_SLIMES` alive (`Fountain.roll`). Each lives for `WILD_LIFETIME`.
  - `FREE_DROP_CHANCE` of drops are free.
  - The rest cost `WILD_PRICE_SECONDS × income`, charged on grab.
  - **Slime Rain:** every `RAIN_INTERVAL` (1 h) for `RAIN_DURATION` (3 min). Spawns are faster, luck is ×3 and mutations are more likely (`Progression.rainStatus`).
- **Carry:** grabbing and stealing use a **ProximityPrompt** (`GrabPrompt`) that the server puts on each slime's `Body`. There is no remote for this.
  - The prompt's `ActionText` is `"Grab"`, `"Buy $<price>"` (`Economy.formatNumber`) or `"Steal"`. `ObjectText` is `Genome.displayName`.
  - Steal prompts (HoldDuration 0.4) are enabled only while the plot is unlocked. They are **hidden from the slime's owner**: the server sets the prompt attribute `HideFromUserId = <owner UserId>` (`Constants.PROMPT_HIDE_ATTRIBUTE`, §5.2) and the client hides it locally. If a client doesn't hide it, triggering it is still refused with "that's your own slime".
  - A wild slime is paid for once: if it's dropped, the next grab is free.
  - While carrying, WalkSpeed = `Steal.walkSpeed`, tools are unequipped, and you can carry 1 slime at a time.
  - Entering your own plot's `HomeZone` deposits the carried slime on a free pad. If the plot is full you keep carrying it (Notify "bad").
  - Dying or respawning while carrying counts as `Drop`; leaving while carrying a stolen slime sends it home.
  - Players spawn on their plot's `Base`. Owner-only prompts (v13 names and texts: §8.5): `LockButton` ("Lock base", same as `Request("Lock")`) and `MergeVat` ("Auto-merge", `Merge.findPair` then `Request("Merge")`).
- **Income:** `Economy.tickIncome` runs every second. On load, the server pays `Economy.offlineIncome`, which is `OFFLINE_RATE` of income, capped at `OFFLINE_CAP_SECONDS`. A slime being carried away pays its owner nothing.
- **Merge:** `Request("Merge", a, b)` takes two slimes of the same tier and gives one slime of tier + 1 (`Merge.apply`).
- **Steal and lock:**
  - On join, the plot is locked for `JOIN_LOCK_SECONDS` (45).
  - `Request("Lock")` buys `60 + 10 × rebirths` s, capped at `LOCK_MAX_REMAINING` (`Steal.buyLock`).
  - Stealing pings the owner (Notify `"bad"` plus `SlimeView.stolenBy`).
  - **Escape home:** each second the slime may wriggle free (`Steal.shouldEscape`). At `escapeAt` it always escapes, after 15–25 s depending on rarity. It also escapes when the carrier is slapped (`Request("Slap")`). An escaped slime bounces back to its pad for 1.5 s (`World.ESCAPE_BOUNCE_SECONDS`, model `State = "Escaping"`). It can't be stolen, sold or merged until it lands.
  - If the thief reaches their own `HomeZone` first, `Steal.complete` moves the slime to the thief.
- **Rebirth:** `Progression.rebirth` wipes cash and slimes but keeps the favourite (or the best slime). It adds +`REBIRTH_MULTIPLIER_STEP` income and +10 s lock.
- **DataStore:**
  - Store `Constants.DATASTORE_NAME`, key `"u_<UserId>"`.
  - The record is `SessionLock` wrapped around `SaveData.serialize`.
  - Autosave every `AUTOSAVE_INTERVAL`, plus on leave and on `BindToClose` (waits up to 25 s for pending saves).
  - Load retries 5 times with `SessionLock.backoff`. In a live server a failed load kicks the player; in Studio they get an unsaved fresh profile.
  - A save retries 3 times. If another server took the session over, this server stops saving that player.
  - Set the workspace attribute `DataStoreMode = "Memory"` to use an in-memory store (no DataStore calls; the leaderboard then ranks this server's players only). Never set it in the published place: `default.project.json` sets no Workspace attributes, and the publish step checks the built file.
  - **Failures are visible:** the server sets the workspace attribute `DataStoreStatus` (`Constants.DATASTORE_STATUS_ATTRIBUTE`) and `warn`s `[Server] DataStoreStatus = ...` on every change to a bad state. Values: `"Ok"` (real DataStore, last load/save succeeded), `"Memory"` (`DataStoreMode = "Memory"`), `"Unavailable"` (`GetDataStore` failed at start; the server fell back to memory and **nothing saves**), `"Error"` (the last load or save hit a DataStore error after retries; goes back to `"Ok"` on the next success).
- **Leaderboard:**
  - `leaderstats` holds IntValues `Cash`, `Rebirths` and `Steals`.
  - A global OrderedDataStore `Constants.LEADERBOARD_STORE` (`"StealASlime_TotalEarned"`, key `"u_<UserId>"`) ranks by `totalEarned`. It's written on every save. It's refreshed every `LEADERBOARD_INTERVAL` and pushed to all clients (§3). A joining player gets the latest board right away. In memory mode the board is also refreshed when someone joins.
- **Shop:** `src/shared/Shop.luau` (pure). The Shop panel's "Lock base" row is the `"Lock"` action; `"BuyLockUpgrade"` and `"BuySpeedCoil"` are the permanent upgrades (§3). Prices and levels are in `State.shop` (§5.1). The lock upgrade adds to `Steal.lockDuration` (so `State.lockDuration` already includes it); the lock is still capped at `LOCK_MAX_REMAINING`.
- **Speed Coil** (v13: also while carrying, always enforced, see §8.10): owning it (`data.speedCoil`) sets WalkSpeed to `SPEED_COIL_WALK_SPEED` whenever you're not carrying (equipped or not). While you own it the server keeps one `SpeedCoil` Tool (`Props.speedCoil()`, a `Handle` Part plus welded decor, unanchored, CanCollide false) in your Backpack or character, re-adding it after respawns. It's cosmetic; carrying still unequips it.
- **Tutorial** (v13: 7 steps with `BuyPad` as step 4, see §8.3): `src/shared/TutorialProgress.luau` (pure). The server owns the step; the client only shows it (`State.tutorialStep`, Player attribute `TutorialStep`). Steps (1-based, same order as the UI's `Tutorial.STEPS`):
  1. `Grab`: grab or buy a wild slime.
  2. `Deposit`: bring any carried slime home onto a pad.
  3. `Lock`: buy a lock (`Request("Lock")` or the LockButton).
  4. `Merge`: merge two slimes.
  5. `Steal`: start a steal or slap a thief.
  6. `Rebirth`: rebirth.
  Doing a step's action finishes that step and every step before it (so a rebirth finishes the tutorial). Doing an *earlier* step's action again does nothing. After step 6 the tutorial is done (`tutorialStep = nil`). New profiles start at 1. Saves made before the field existed start at 1 if they have no slimes and no rebirths, otherwise done. Saved as `tutorialStep` (0 = done) and kept on rebirth.
- **Daily reward:** `Request("Daily")` (`Progression.claimDaily`). `State.daily` says whether it's available, the streak and what the pending claim pays (`day`, `amount`).
- **Effects:** the server plays `Effects.play` bursts on gameplay events (§5.4).
- **Rain heads-up:** `RAIN_WARNING_SECONDS` (60) before each rain everyone gets Notify "Slime Rain in 1 minute! …" (`"info"`).
- **Extras** (each behind `Config.FEATURES.<name>`; `false` turns it fully off):
  - `BossSlime`: from `BOSS_FIRST_AT` after start, every `BOSS_INTERVAL` the fountain drops one **Boss Slime** if none is alive (`Spawner.spawnBoss`): a free wild slime of tier ≥ `BOSS_TIER`, size `MAX_SIZE`, at least `Glow`, living `BOSS_LIFETIME`, ignoring the wild cap. Everyone gets Notify (`"Rain"` sound, `"A BOSS SLIME slid into the plaza: <name>! Grab it first!"`); whoever deposits it triggers a server-wide "<name> caught the Boss Slime!". Its model has attribute `Boss = true` (`Constants.BOSS_ATTRIBUTE`) and its prompt's ObjectText starts with `"BOSS "`. Otherwise it's a normal wild slime (grab, drop, deposit).
  - `FollowPets`: the server sets Player attribute `PetSlimeId` (`Constants.PET_ATTRIBUTE`) to `Progression.keeper(data).id` (favourite, else best slime; nil without slimes). VisualsClient (`FollowPets`) clones that slime's replicated model into a local `workspace.ClientPets` folder at 0.45 scale and has it follow its owner. Client-only, cosmetic.
  - `DayNight`: the server sets `Lighting.ClockTime = DayNight.clockTime(elapsed)` twice a second: one day per `DAY_LENGTH` (12 min), daytime 06:30–17:30 for `DAY_FRACTION` (70 %) of it.
  - `Minimap`: `ReplicatedStorage.Visuals.MinimapData.points()` lists `{ kind, name, x, z, plotIndex? }` for the fountain (`kind = "Fountain"`, map centre), `Plot_i`, the three props and HubSpawn from WorldLayout; `toMap(x, z)` gives 0..1 map coordinates over the 640-stud Ground. Data only (no UI yet).
  - `Audio` (**`false`**, v23): client `ui/SoundController` (pure rules in `ui/AudioLogic`, ids in `Config.AUDIO`). SoundGroups `SFX` and `Music` under SoundService; a registry (`buy`, `collect`, `steal`, `merge`, `rebirth`, `alarm`, `error`, `click`) maps to `Sounds.IDS` names or `rbxasset://` ids, an empty / malformed id plays nothing. Toast and steal-alert sounds route through it. Ambience: a looped day (birds) / night (crickets) pair crossfaded over `AMBIENT_FADE_SECONDS` from `Lighting.ClockTime` (night = outside `DayNight.SUNRISE..SUNSET`), at `AMBIENT_VOLUME`; the ambient asset ids are empty until uploaded (silent). A small "Sound: on/off" button opens a compact panel (bottom-left) with a Mute toggle and two sliders, SFX and Music / Ambience: 5% steps, percent shown, mouse or touch drag, applied live to the attributes / SoundGroups (pure maths in `AudioLogic.snapVolume` / `volumeFromPixel`). Mute / volumes are Player attributes `AudioMuted`, `AudioSfxVolume`, `AudioMusicVolume`, saved per player since save v6 (§8.9c): `State.settings` is applied once on join (`SoundController.load`) and changes are sent back 0.6 s after the last one with `Request("SetAudioSettings", musicVolume, sfxVolume, muted)`. Flag off = Notify sounds play as before, no groups, ambience or button; the request is refused.
  - `SlimeLod` (**`false`**): the procedural motion gets tiers by camera distance and the saved graphics quality (`Config.SLIME_LOD`, `ui/SlimeLod`): near = full motion every frame, mid = squish only, smaller, every `MID_EVERY` frames, far = Transform reset to identity once, then skipped; low quality shrinks the near / mid radii. Selection stays 4x a second, cap 16 and the on-screen check unchanged. Client-only.
  - `SlimeAnimations` (**`false`**, TODO 17): `true` lets the client play the uploaded KeyframeSequences (`MeshAssets.ANIMATIONS`) on a slime's Animator, but only after a probe load of `SlimeIdleSquish` reports `Length > 0`; a failed or slow probe, or a track that never plays, keeps every slime on the procedural motion. `false` (default): rigged slimes are driven in code by `ui/SlimeMotor` (squish, hop, look on the FaceRoot / SkinRoot Motor6D `Transform`), same LOD (nearest 16 within 80 studs, on screen). Client-only; nothing replicates.
  - `Parade` (**`true`**, TODO 16): the goo parade replaces the plain wild despawn. A fresh wild rides the fountain slide onto the head of a goo lane (`Shared.ParadeLane.WAYPOINTS`, laid on the plaza as `Map.Plaza.ParadeLane` by `server/ParadeView`) that loops counter-clockwise round the plaza from just past the goo drain (+Z), dipping inside the hub SpawnLocation and the leaderboard podiums / signpost, and ends at the drain. Its spot is time left: `progress = 1 - (expiresAt - now) / lifetime`; it waits at the entry for `HOP_SECONDS` (the ride), hops along the lane linearly in time left, and in the last `DRAIN_SECONDS` slides over the drain curb and sinks. The server removes it at `expiresAt` as before and emits World event `Drained` (`slimeId`), which plays a goo splash at the drain. Lane slimes stay grabbable / buyable (same `Grab` / `Buy $` prompt; `Carry.grab`); a grabbed slime leaves the lane at once, and a dropped one (`wild.position` set) stays where it lands with a fresh lifetime and poofs there. `wild.angle` / `wild.radius` keep the `Fountain.roll` values (`radius` sets the slime's sideways offset on the lane). Spawn cadence, cap and lifetimes don't change. The ring warning is the `DespawnTelegraph` window (`"leaving! N"`), which opens while the slime is still walking beside the drain. With the flag off, wilds land in the `Fountain.MIN_RADIUS..MAX_RADIUS` band (`Volcano` is a thin alias) as before.
  - `Habitats` (**default `false`**, `HABITATS.md`): a pad whose slime rests on it shows that slime's habitat (`Shared.Habitats.forSlime`: type, then tier family, else `base`); empty / stolen / escaping = `base`. Server state in `HabitatPads` (never saved), written as the `Pad_<j>` attributes below; `VisualsClient.HabitatFx` tweens a local look in `workspace.ClientHabitats` over 1 s. Flag off = no attributes, no parts.
- **Out of MVP scope:** fountain / silo tiers (was "volcano tiers"), 3-slime vat, sticky floor / bouncer upgrades, Robux products.

## 3. Remotes

Every remote lives in the `ReplicatedStorage.Remotes` folder, which the server creates with `Remotes.setup()`. Clients get a remote with `Remotes.get(name)`. Times are **server time** (`workspace:GetServerTimeNow()`).

| Name | Class | Direction | Payload |
|---|---|---|---|
| `Request` | RemoteFunction | client → server | `InvokeServer(action: Action, ...args)` → `RequestResult = { ok: boolean, message: string? }` |
| `State` | RemoteEvent | server → client | `FireClient(player, state: Types.State)` (§5) |
| `Notify` | RemoteEvent | server → client | `FireClient(player, text: string, kind: "info" \| "good" \| "bad", sound: string?, itemId: string?)`. `itemId` (optional) is the UI ItemIcons registry id the toast is about (`"SpeedCoil"`, `"Upgrade_Luck"`, `"PlotSkin_candy"`); absent/unknown ids fall back to the client text heuristic. Global toasts (Slime Rain) use `FireAllClients`. |
| `Leaderboard` | RemoteEvent | server → client | `FireClient/FireAllClients(board: { stat: "TotalEarned", entries: { { rank: number, userId: number, name: string, value: number } } })` |

`Request` actions (from `Remotes.ACTIONS`; rate limits in `Validate.ACTIONS`):

| Action | Args | Effect / `message` on failure |
|---|---|---|
| `"Merge"` | `slimeIdA: string, slimeIdB: string` | Merges two owned, not-busy slimes of the same tier. |
| `"Lock"` | none | Buys or extends the plot lock. Costs `Economy.lockCost(income)`. |
| `"Rebirth"` | none | Rebirths if `Progression.canRebirth`. |
| `"Sell"` | `slimeId: string` | Sells for `Economy.sellPrice`. |
| `"Favorite"` | `slimeId: string?` | Sets the rebirth keeper. `nil` clears it. |
| `"BuyPad"` | none | Unlocks the next pad (`Economy.padCost`). |
| `"Daily"` | none | Claims the daily reward (`Progression.claimDaily`). |
| `"ClaimQuest"` | `slot: number` | Claims daily quest `slot` (1..`DAILY_QUESTS.count`) once finished (`Quests.claim`): cash x rebirth multiplier or an income boost. `State.dailyQuests` has the 3 quests rolled per UTC day (progress = gained since the roll, saved as `quests`; missing = nothing rolled). |
| `"BuyLockUpgrade"` | none | Buys the next lock-time upgrade level for `Shop.lockUpgradeCost(level)`. Each level makes every bought lock last `LOCK_UPGRADE_SECONDS` longer, up to `LOCK_UPGRADE_MAX` levels. Permanent: saved and kept on rebirth. |
| `"BuySpeedCoil"` | none | Buys the Speed Coil once for `SPEED_COIL_PRICE`. While you're not carrying, WalkSpeed is `SPEED_COIL_WALK_SPEED` instead of `BASE_WALK_SPEED`. Permanent: saved and kept on rebirth. |
| `"BuyEgg"` | none | `FEATURES.MysteryEgg`. Buys a Mystery Egg with cash only (`Shared.MysteryEgg.price` = `MYSTERY_EGG_PRICE` x rebirth multiplier). It hatches a slime rolled from `MYSTERY_EGG_DROPS` onto the lowest free pad via `PlayerData.addSlime`; `State.egg.hatched` carries it for the reveal banner. Failures: `"not enough cash"`, `"plot full"` (nothing charged), `"eggs are off"`. Save format unchanged. Events: server-only `Server/MysteryEgg.spawnForEvent(world, userId, count, now)` hatches free eggs, no remote. |
| `"Slap"` | `targetUserId: number` | Slaps a carrier within `SLAP_REACH`. The slime escapes home. |
| `"Drop"` | none | Drops what you're carrying. Wild → falls to the ground; stolen → escapes home. |
| `"Appraise"` | `slimeId: string, kind: "mutation" \| "size"` | `FEATURES.Appraise`: pays `Appraise.cost` (`APPRAISE_COST_FRACTION` = 30% of `Economy.sellPrice`) to reroll that owned, not-busy slime's mutation or size. Only `mutation` / `size` change. Success returns `{ ok = true, appraisal = Types.Appraisal }` (before / after, cost). Fails with `"not your slime"`, `"not enough cash"`, `"slime is busy"`, `"appraise is off"`. `SlimeView.appraiseCost` is nil when the flag is off. |
| `"Sync"` | none | The server re-sends `State` right away. The UI calls it once on start. |

`Notify` sound names: `"Alarm"` (your slime is being stolen), `"Grab"`, `"Stolen"`, `"Escape"`, `"Slap"`, `"Lock"`, `"Unlock"`, `"Merge"`, `"Cash"`, `"Deposit"`, `"Rain"`, `"Rebirth"`, or `nil`. The sound name doubles as the **effect hook**: clients may also play a particle burst or screen effect keyed on it (the world-space bursts themselves are server-played, §5.4). Purchases (pads, shop upgrades) and the daily reward use `"Cash"`; finishing the tutorial sends Notify "Tutorial complete!" (`"good"`, no sound).

**Server rules for `Request`:**
- Validate every argument with `Shared.Validate` and rate-limit per action.
- Never error. Return `{ ok = false, message = "<reason>" }` instead.
- Every successful action changes state, which triggers a `State` push.

## 4. `ModelFactory.build`

```luau
-- ReplicatedStorage.Visuals.ModelFactory
ModelFactory.build(slimeData: Types.SlimeData): Model
```

The `slimeData` shape is `Types.SlimeData`, the same as `Genome.Slime` and the save format:

```luau
{
	id: string,          -- unique, 1..64 chars [%w-_{}]
	name: string,        -- 1..32 chars, e.g. "Globble"
	tier: number,        -- 1..6: Common, Uncommon, Rare, Epic, Legendary, Mythic
	color: { number },   -- { r, g, b } integers 0..255
	size: number,        -- 0.8..2.0, two decimals
	pattern: string,     -- "Plain" | "Spots" | "Stripes" | "Belly"
	eyes: string,        -- "Round" | "Sleepy" | "Angry" | "Happy" | "Cyclops" | "Wide"
	mouth: string,       -- "Smile" | "Open" | "Flat" | "Fang"
	mutation: string,    -- save id: "None" | "Glow" | "Lava" | "Galaxy" | "Rainbow" | "Gold" | "Crystal" | "Eclipse" ("Lava" displays as "Syrup": Config.MUTATIONS[].displayName)
	pad: number?,        -- home pad 1..PADS_MAX on the owner's plot; nil while wild/carried
	species: string?,    -- SlimeRoster id (v28+); nil on older and merged slimes
	growth: number?,     -- 0..1 (FEATURES.GrowingSlimes); nil = 0, old saves load unchanged
}
```

**Roster (v28):** wild slimes roll their tier exactly as before, then pick a species of that tier from `SlimeRoster` (uniform within the tier); `name` is the species display name. Saved slimes keep their stored `name`; `species` is optional and an unknown id is dropped on load. Secret species (tier 7) are roster-only and never spawn. Mutations are ordered by multiplier (Merge ranks by position): Glow 1.5/50, Lava 2/30 (shown as "Syrup", save id stays `Lava`), Galaxy 3/15, Rainbow 4/8, Gold 5/5, Crystal 7/2, Eclipse 10/0.5.

**Growth (FEATURES.GrowingSlimes, `Shared.Growth`):** a pad slime's `growth` rises by `dt / GROWTH_SECONDS` (Income.step, carried slimes skip); on join `(now - lastOnline)` capped at `GROWTH_OFFLINE_CAP_SECONDS` counts too. `Genome.baseIncome` x `1 + GROWTH_MAX_INCOME_BONUS * growth` (so sell price too). Saved as optional `growth` per slime (rounded to 4 decimals); missing = 0, `SAVE_VERSION` stays 3. The server scales the model by `Growth.scale` and shows a `GrowthLabel` "Growth N%" (model attribute `Growth`).

**Return value:** a new, **unparented** `Model`:
- **Name:** `Slime_<id>`.
- **PrimaryPart:** `Body`. A part with diameter `SLIME_BASE_DIAMETER × size`.
- **Physics:** `Body.Anchored = true`. Every part is Massless with `CanCollide = false`. Decoration parts are welded to `Body`, and `Body.CanQuery = true`.
- **Pivot:** the bottom centre. `Body.PivotOffset` points at the bottom of the ball (and `WorldPivot` matches), so `model:PivotTo(padTop)` sits the slime on the pad. The server places pad slimes with `model:PivotTo(pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0))` and wild slimes with `PivotTo` a ground-level CFrame; it never offsets by the slime's radius.
- **Attributes set by the factory:** `SlimeId: string`, `Tier: number`, `Mutation: string`, `Size: number`.
- **Tag:** `Constants.SLIME_TAG` (`"Slime"`).

**Guarantees:**
- It's a pure function of `slimeData`. It doesn't yield, adds no scripts, and works on server and client (ViewportFrames).
- Pattern, eyes, mouth and mutation must be visibly different from each other.

**The server (Phoenix) owns everything after `build`:**
- Parenting: wild slimes go to `workspace.WildSlimes`; pad slimes go to their plot's `Slimes` folder.
- Attributes `OwnerUserId: number` (0 = wild), `State: "Wild" | "Pad" | "Carried" | "Escaping"`, and `Price: number` (wild only).
- The ProximityPrompt.
- Unanchoring and welding the model to the carrier's character.

**Mesh look (server-side wrapper, `src/server/SlimeMesh.luau`):** at server start the server loads Jolt's slime mesh package (`Config.SLIME_MESH_ASSET_ID` = 103340234939607) once with `InsertService:LoadAsset` inside a `pcall`, and keeps its first `MeshPart` as a template. Every slime is still built by `ModelFactory.build` (so the contract above is unchanged); with a template the server then adds a welded, non-colliding `MeshPart` named `Mesh`, sized to `Body`'s box and given `Body`'s colour and material (genome / mutation colours stay), and makes `Body` transparent. `Body` stays the PrimaryPart, prompt parent and raycast target; rims, crowns, eyes, mouth and pattern stay. If the asset can't be loaded (no access, no MeshPart) or dressing a slime fails, the server warns once and uses the procedural look. `workspace.SlimeLook` (§5.2) says which one is active.

## 5. UI state: `State` payload and world attributes

### 5.1 `Types.State` (full snapshot)

**When it's sent:**
1. Once the player's data has loaded.
2. On every `Request("Sync")`.
3. After any change to that player's state: an action, income tick, steal, escape, rebirth, Slime Rain start/end, or lock expiry. Changes are coalesced to at most one push per `STATE_MIN_INTERVAL` (0.25 s). That includes `Sync`, which isn't rate-limited. The server flushes due pushes on every Heartbeat tick (0.1 s) and right after each `Request`.
4. At least once a second while income is above 0.

The client always replaces its copy and never diffs.

```luau
{
	serverTime: number, plotIndex: number,
	cash: number, incomePerSec: number,
	rebirths: number, rebirthMultiplier: number, rebirthCost: number, canRebirth: boolean,
	padsUnlocked: number, padsMax: number, nextPadCost: number?,
	slimes: { { slime: SlimeData, income: number, sellPrice: number, stolenBy: number? } },
	favoriteId: string?,
	lockUntil: number, lockCost: number, lockDuration: number,
	carrying: { slime: SlimeData, kind: "wild" | "stolen", ownerUserId: number?,
	            startedAt: number, escapeAt: number?, walkSpeed: number }?,
	rain: { active: boolean, endsAt: number?, nextAt: number? },
	dex: { string }, dexTotal: number,          -- Genome.dexKey values; total = 6*8*4*6 = 1152 (v28; was 720)
	daily: { available: boolean, streak: number, amount: number, day: number },
	shop: {
		LockUpgrade: { price: number?, level: number, maxLevel: number },  -- price nil = maxed
		SpeedCoil: { price: number?, owned: boolean },                      -- price nil = owned
		MysteryEgg: { price: number }?,                                      -- FEATURES.MysteryEgg only
	},
	egg: { enabled: boolean, price: number, hatched: { slime: SlimeData, at: number }? },  -- newest hatch, never saved
	tutorialStep: number?,   -- 1..6 (§2 Tutorial); nil = finished
}
```

- `daily.day` is the streak day the pending claim pays (1..`DAILY_STREAK_CAP`, `amount = DAILY_BASE × day × rebirthMultiplier`). When nothing is pending, it's the day the last claim paid.
- `shop` keys are the UI's `ShopCatalog` item ids. Prices are final (what `Request` charges).

### 5.2 Instance attributes (read by UI billboards and visuals)
- **`workspace.Plots.Plot_<i>`:**
  - `OwnerUserId: number` (0 = free).
  - `LockUntil: number` (server time).
  - `Rebirths: number`.
- **Slime models:** the attributes in §4.
- **`GrabPrompt` (ProximityPrompt on a slime's `Body`, name `Constants.GRAB_PROMPT_NAME`):** the same prompt serves grab, buy and steal; the server never creates another slime prompt name. `HideFromUserId: number?` (`Constants.PROMPT_HIDE_ATTRIBUTE`). Set to the owner's UserId while the prompt is a `"Steal"` prompt (state `Pad`); nil on wild, carried and escaping slimes. Set on every reconcile (`Scene.Entry.hideFromUserId`).
  - Roblox has no server-side per-player prompt visibility (`Enabled` replicates to everyone), and the server has no client folder of its own, so **one client LocalScript must honour it** (owner: Jolt, `src/ui`). Rule: for every `ProximityPrompt` named `GrabPrompt` under `workspace`, if `prompt:GetAttribute("HideFromUserId") == LocalPlayer.UserId`, keep `prompt.Enabled = false` locally. Re-apply on `GetAttributeChangedSignal("HideFromUserId")` and `GetPropertyChangedSignal("Enabled")`, because a server-side `Enabled` change (lock/unlock) replicates over the local value. Sketch:
    ```luau
    local function apply(p: ProximityPrompt)
    	if p:GetAttribute("HideFromUserId") == Players.LocalPlayer.UserId and p.Enabled then
    		p.Enabled = false
    	end
    end
    -- for each GrabPrompt (workspace.DescendantAdded + existing): apply(p), and connect both signals to apply
    ```
  - Client side: Jolt's `src/ui/PromptHide` implements this rule (matches only `GrabPrompt`, reads only `HideFromUserId`).
  - Server-side safety net: `Carry.grab` refuses the owner, so a client that ignores the attribute only shows a useless prompt.
- **Player:** `Carrying: string?` (`Constants.CARRYING_ATTRIBUTE`). The carried slime's id, set on pickup (grab or steal). Cleared (nil) on drop, deposit, a failed steal (wriggle, timeout or slap escape; the owner leaving), death / respawn and leave. A full plot doesn't clear it: the slime stays in your arms. The server derives it from `Carry.carryingId` after every action and every tick.
- **`workspace`:**
  - `SlimeRain: boolean` (`Constants.RAIN_ATTRIBUTE`): `true` during Slime Rain, `false` otherwise (set at server start). VisualsClient keys its rain particles off it.
  - `DataStoreStatus: string` (`Constants.DATASTORE_STATUS_ATTRIBUTE`): `"Ok" | "Memory" | "Unavailable" | "Error"`, see §2 Persistence.
  - `SlimeLook: string` (`Constants.SLIME_LOOK_ATTRIBUTE`): `"Mesh"` if the slime mesh asset loaded at server start, `"Procedural"` if the server fell back to ModelFactory's look (see §4).
  - `RainActive: boolean` (same value as `SlimeRain`), `RainEndsAt: number?` and `RainNextAt: number?` (server time) for the HUD countdowns. Names: `Constants.RAIN_ACTIVE_ATTRIBUTE`, `RAIN_ENDS_AT_ATTRIBUTE`, `RAIN_NEXT_AT_ATTRIBUTE`.
- **Player (more):**
  - `TutorialStep: number?` (`Constants.TUTORIAL_STEP_ATTRIBUTE`): same as `State.tutorialStep`, so VisualsClient can draw the tutorial arrow without remotes (targets: 1 → `Map.Volcano.Crater`, 2 → own plot `HomeZone`, 3 → own `LockButton`, 4 → own `MergeVat`, 5 → another owned plot's `Base`, 6 → none). nil = finished or not loaded.
  - `SpeedCoil: boolean?` (`Constants.SPEED_COIL_ATTRIBUTE`): `true` once the Speed Coil is owned (for a cosmetic coil on the character).
  - `PetSlimeId: string?` (`Constants.PET_ATTRIBUTE`): the slime that follows the player (`FEATURES.FollowPets`, §2 Extras).

### 5.3 World (built by Archer's WorldBuilder, wired by Phoenix)

**The world is static in the place file.** `lune run scripts/gen-world` runs `WorldBuilder.build` under Lune and writes `world/Map.rbxmx`, `world/Plots.rbxmx` and `world/HubSpawn.rbxmx` (an anchored, neutral `SpawnLocation` on the Ground between the Plot_2 / Plot_3 paths). `default.project.json` puts them under Workspace, so floor, plots and spawn exist before any character loads. **Rerun `gen-world` after changing WorldLayout / WorldBuilder** and commit the `.rbxmx` files; `tests/StaticWorld.spec.luau` fails if they're stale.

On start the server still calls `ReplicatedStorage.Visuals.WorldBuilder.build(workspace)` first, before anything that yields (idempotent: it reuses the static pieces and never clobbers slimes or plot attributes). If that module is missing or fails and `workspace.Plots` doesn't exist, `src/server/FallbackWorld` builds a greybox with the same names and attributes.

**Void safety:** every Workspace BasePart except slimes is Anchored. `Workspace.FallenPartsDestroyHeight = -1000` (set in `default.project.json`; scripts can't write it). Every frame the server puts any living character whose root is below `Rescue.KILL_PLANE_Y` (-60) back on its plot's Base (or HubSpawn before a plot is assigned) and zeroes its velocity. `lune run scripts/check-place <file>` checks a built place (also run by `tests/StaticWorld.spec.luau`).

The server finds plots by the `PlotIndex` attribute and pads by `PadIndex` (`Constants.PLOT_INDEX_ATTRIBUTE` / `PAD_INDEX_ATTRIBUTE`, via `PlotLookup`). The `Plot_<i>` / `Pad_<j>` names are only a fallback. Folder names are in `Constants`: `MAP_FOLDER = "Map"`, `PLOTS_FOLDER = "Plots"`, `PLOT_SLIMES_FOLDER = "Slimes"`, `HOME_ZONE = "HomeZone"`. `WorldLayout` hardcodes `"Map"` and `"Slimes"`, and `tests/Integration.spec.luau` checks they match.

- **`workspace.Map`:** `Volcano` (with a `Crater` Part, the spawn origin) and `Chute`. The server adds `Volcano.SlideColliders` at boot (`server/FountainColliders`, `Shared.SlideColliders`): invisible, anchored, always-solid floor / wall / skirt Parts along the low slide (attribute `FountainCollider` = kind), so players cannot walk through the slide; wild slimes ride it anchored and non-colliding. The model keeps its legacy name `Volcano` (it is the slime fountain). Drops land at `Fountain.roll` angle/radius around the crater (moved straight out past the low slide when they would land on it, `FountainRide.clearLanding`) after the slide ride (`FountainRide`: emerge, every `SLIDE_PATH` waypoint, run-out round the plaza).
- **`workspace.Plots.Plot_1..PLOT_COUNT`** (attribute `PlotIndex = i`):
  - `Base`.
  - `Pad_1..Pad_<PADS_MAX>` (attribute `PadIndex = j`). The top surface is where `PivotTo` targets.
  - `HomeZone`: CanCollide false, transparent. A carrier whose root part is inside their own plot's zone deposits. If the plot is full, they get one Notify `"bad"` per zone visit.
  - `MergeVat`, `LockButton`, `Sign` and a `Slimes` folder.
- **Props** (`src/server/WorldProps.luau`, placed on start right after WorldBuilder): one of each Model below goes under `workspace.Map` at `WorldLayout.PROP_SPOTS[name]` (pivot `CFrame.new(pos) * CFrame.Angles(0, rad(yaw), 0)`, bottom centre on the Ground), unless a Model with that name already exists anywhere under `workspace` (so a future static copy wins). Built by Archer's `Props`; every part is Anchored. Names are in `Constants`.
  - **`ShopStand`** (`Constants.SHOP_STAND`): PrimaryPart `Counter` holds ONE ProximityPrompt `ShopPrompt` (`Constants.SHOP_PROMPT_NAME`, E, ObjectText "Shop", ActionText "Open Shop"). v28: it buys nothing; the triggering client opens the Shop menu (every item, bought through `Request` there). The v27 per-item prompts `ShopPrompt_SpeedCoil` / `ShopPrompt_LockUpgrade` are gone.
  - **`LeaderboardBoard`** (`Constants.LEADERBOARD_BOARD`): `LeaderboardBoard` > `Board` (Part) > SurfaceGui `BoardGui` (Face Front) > Frame `Content` > TextLabel `Title` + Frame `Rows` (UIListLayout), plus `Frame`, `PostL` / `PostR`. **The server fills `Rows`** on every leaderboard refresh: `Row_<k>` Frames (k = 1..`LEADERBOARD_SIZE`, LayoutOrder k) with TextLabels `Rank` (`"#k"`), `Name`, `Value` (`"$" .. Economy.formatNumber`). Rows are updated in place when the count is unchanged (so client-side tweaks like the UI's own-row highlight survive), rebuilt otherwise; an empty board shows one `Row_1` "No entries yet". Clients may re-render the same rows locally (the UI's `WorldLeaderboard` does).
  - **`TutorialNpc`** (`Constants.TUTORIAL_NPC`): R6-style primitives, no Humanoid, PrimaryPart `HumanoidRootPart`, `NameTag` BillboardGui, Attachment `ArrowStart` in `SlimeHat` (start of the tutorial arrow). v28: `HumanoidRootPart` holds ProximityPrompt `GuidePrompt` (`Constants.GUIDE_PROMPT_NAME`, E, ObjectText "Guide", ActionText "Talk"); the triggering client opens the Guide card (next goal + tips, `src/ui/GuideTips.luau`). No server effect.
  - **`TutorialArrow`** (client-only Beam): VisualsClient draws `Props.tutorialArrow` from the local character's `HumanoidRootPart` to the target of the player's `TutorialStep` (§5.2) and removes it when the step is nil or has no target.

### 5.4 Effects (Archer's `ReplicatedStorage.Visuals.Effects`)

`Effects.play(kind, target: Vector3 | CFrame | BasePart): Instance?` with `kind` in `Effects.KINDS` = `"Collect" | "Steal" | "Merge" | "Rebirth"`. The server queues `{ type = "Effect", kind, userId?, slimeId?, plotIndex? }` in `world.outbox` and init.server plays it (pcall'd; never breaks gameplay):

| Kind | When (server) | Target |
|---|---|---|
| `"Collect"` | a carried slime is deposited (wild or stolen) | the depositor's `HumanoidRootPart` |
| `"Steal"` | a steal starts (grab from someone's pad) | the stolen slime's `Body` |
| `"Merge"` | a merge succeeds | the plot's `MergeVat` |
| `"Rebirth"` | a rebirth succeeds | the player's `HumanoidRootPart` |

Server-played bursts replicate to everyone (emitters run for `Effects.BURST_TIME`, cleaned up by Debris).

Client-only ambience (VisualsClient, no server part): emitters `Smoke` / `Embers` / `Eruption` on `Map.Volcano.Crater` with an eruption burst + `CraterGlow` flash every 9–16 s (3–6 s during Slime Rain), and while `workspace.SlimeRain` is true a camera-following `SlimeRainEmitter` (`Drops` + `Blobs`) plus a `SlimeRainTint` ColorCorrectionEffect in Lighting. The static map carries the `CraterGlow` PointLight on `Map.Volcano.Crater`.

## 6. Shared config (`src/shared/Config.luau`)

| Key | Value | Design source |
|---|---|---|
| `JOIN_LOCK_SECONDS` / `LOCK_SECONDS` / `LOCK_SECONDS_PER_REBIRTH` | 45 / 60 / 10 | "45 s on join, then a 60 s lock button, +10 s per rebirth" |
| `RARITIES[i].escapeTime` | 25, 23, 21, 19, 17, 15 | "15–25 s by rarity" |
| `RARITIES[i].carrySlow` (+`STOLEN_EXTRA_SLOW` ramp, max `MAX_CARRY_SLOW`) | 0.05…0.30 (+0.25, ≤0.6) | "slows the carrier more the rarer it is" |
| `RARITIES[i].income` | 1, 3, 9, 27, 80, 250 | income = rarity × size × mutation |
| `MUTATIONS` | Glow ×1.5, Lava (shown "Syrup") ×2, Galaxy ×3, Rainbow ×4, Gold ×5, Crystal ×7, Eclipse ×10 | "Glow, Galaxy, Lava, Gold" + v28 roster (§2 Roster) |
| `RAIN_INTERVAL` / `RAIN_DURATION` / `RAIN_LUCK` | 3600 / 180 / 3 | "every hour … for 3 minutes" |
| `PADS_START` / `PADS_MAX` / `PLOT_COUNT` | 4 / 8 / 8 | MVP "8 pads" |
| `OFFLINE_RATE` / `OFFLINE_CAP_SECONDS` | 0.5 / 7200 | capped offline income |
| `REBIRTH_BASE_COST` / `REBIRTH_COST_GROWTH` / `REBIRTH_MULTIPLIER_STEP` | 5000 / 3 / 0.5 | rebirth gives a multiplier, keeps one favourite |
| `SPAWN_INTERVAL` / `MAX_WILD_SLIMES` / `FREE_DROP_CHANCE` / `WILD_PRICE_SECONDS` | 4 / 18 / 0.25 / 20 | "buy cheap ones … or grab a free drop" |
| `STATE_MIN_INTERVAL` / `LEADERBOARD_INTERVAL` | 0.25 / 60 | §5.1, §2 |

| `LOCK_UPGRADE_MAX` / `LOCK_UPGRADE_SECONDS` / `LOCK_UPGRADE_COSTS` | 5 / 15 / 500, 2 000, 8 000, 30 000, 100 000 | shop: longer locks |
| `MYSTERY_EGG_PRICE` / `MYSTERY_EGG_MUTATION_CHANCE` / `MYSTERY_EGG_REVEAL_SECONDS` / `MYSTERY_EGG_DROPS` | 2 000 / 0.05 / 6 / tiers 2-6, weights 50, 30, 14, 5, 1 | mystery egg: cash-only hatch |
| `SPEED_COIL_PRICE` / `SPEED_COIL_WALK_SPEED` | 1 500 / 22 | shop: speed coil |
| `RAIN_WARNING_SECONDS` | 60 | rain heads-up toast |
| `FEATURES` | `BossSlime`, `FollowPets`, `DayNight`, `Minimap`, `DespawnTelegraph` (`true`); `Parade` (`true`); `ServerProfiler` (`false`, §25); `Revenge` (`true`); `Habitats` (`true`); `SlimeAnimations` (`false`); `SlimeLod` (`true`); `Audio` (**`false`**) | §2 Extras |
| `BOSS_FIRST_AT` / `BOSS_INTERVAL` / `BOSS_TIER` / `BOSS_LIFETIME` | 480 / 900 / 4 / 120 | Boss Slime |
| `DAY_LENGTH` / `DAY_FRACTION` | 720 / 0.7 | day / night |
| `PITY_EPIC` / `PITY_LEGENDARY` / `RARE_ANNOUNCE_TIER` | 30 / 300 / 5 | v13 rarity (§8.7) |
| `REBIRTH_LATE_FROM` / `REBIRTH_COST_GROWTH_LATE` / `REBIRTH_TIERS` / `UPGRADES` / `GOALS` / `DEX_MILESTONES` | 5 / 2 / tables | v13 progression (§8.8) |
| `SAVE_VERSION` | 6 | v13 schema (§8.9), v4 = `slimes[i].mutations` (§8.9a), v5 = weather mutations Wet / Frozen (§8.9b), v6 = `settings` + versioned `plotSkin` / `stealLog` (§8.9c) |

All names (remotes, folders, tag, DataStores, the `DataStoreMode` / `DataStoreStatus` / `SlimeLook` / `Carrying` / `SlimeRain` / `RainActive` / `RainEndsAt` / `RainNextAt` / `TutorialStep` / `SpeedCoil` / `PetSlimeId` / `Boss` / `PlotIndex` / `PadIndex` attributes, `ShopStand` / `LeaderboardBoard` / `TutorialNpc` / `SpeedCoil` tool) are in `Constants.luau`.

## 7. Build and tests

The toolchain is pinned in `rokit.toml` (rojo 7.7.1, lune 0.11.0, selene 0.32.0, stylua 2.6.0, wally 0.3.2, luau-lsp 1.70.1). The approach matches `speed-escape-skeleton`. Run everything from the repo root:

```sh
rojo build -o build.rbxlx   # place file
lune run tests              # unit tests: tests/init.luau runs every *.spec.luau under tests/ (recursing, incl. tests/ui), exit 1 on failure
selene src tests            # lint
stylua --check src tests    # format
scripts/typecheck.sh        # luau-lsp types: fails on src/server + src/shared, reports src/ui + src/visuals counts
```

**Test framework:** `tests/TestRunner.luau`, a small framework with `describe`, `it`, and `expect(x)` matchers (`.toBe`, `.toEqual`, `.toBeCloseTo`, `.toBeNil`, `.toBeTruthy`, `.toBeFalsy`, `.toThrow`).
- Specs require sources by relative path, e.g. `require("../src/shared/Steal")`.
- Pure `src/shared` and `src/server` modules are unit-tested (one spec per system; `tests/ServerFixtures.luau` builds a World with players).
- The Roblox adapters (`init.server.luau`, `WorldView`, `WorldProps`, `FallbackWorld`), visuals and UI are checked by the Rojo build plus Merijn's play-tests. `tests/Members.spec.luau` statically checks that every `Module.member` used in src/server, src/shared and src/visuals exists, and `tests/Props.spec.luau` builds Archer's Props under Lune.

CI is in `.github/workflows/ci.yml` and runs the same five commands.

## 8. v13 additions (2026-10-15, Phoenix)

**Status:** contract first. Names in this section are frozen. The server implements them in the v13 commits that follow; until then a field may be missing, so clients should treat new fields as optional (`state.upgrades or {}`). Where this section and §1-§7 disagree, this section wins.

### 8.1 Request actions (new)

| Action | Args | Effect / `message` on failure |
|---|---|---|
| `"BuyUpgrade"` | `upgradeId: string` (one of `Config.UPGRADES[i].id`: `"Income"`, `"CarrySpeed"`, `"OfflineCap"`, `"Luck"`) | Buys the next level for `Upgrades.cost(id, level)`. Fails with `"unknown upgrade"`, `"locked: reach <n> rebirths"`, `"already maxed"` or `"not enough cash"`. Permanent: saved, kept on rebirth. Rate limit 0.5 s. Notify `"<Name> level <n>!"` (`"good"`, `"Cash"`). |

Goals and Slimedex rewards are **paid automatically** (no claim action). Nothing else is added; every v12 action keeps its name and args.

### 8.2 `State` fields (new; §5.1 fields are unchanged)

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

### 8.3 Tutorial (replaces the §2 list)

`TutorialProgress.STEPS = { "Grab", "Deposit", "Lock", "BuyPad", "Merge", "Steal", "Rebirth" }` (7 steps). `"BuyPad"` (new, step 4) finishes on a successful `Request("BuyPad")` or `BuyPadPrompt`. Indices after 3 shift by one: **Jolt** adds a step 4 to `src/ui/Tutorial.STEPS` (suggested: title "Buy a pad", body "More pads = more slimes. Walk to the glowing pad on your plot and buy it.") and **Archer** shifts the arrow targets: 1 Crater, 2 own `HomeZone`, 3 own `LockButton`, **4 own plot's pad carrying `BuyPadPrompt`**, 5 own `MergeVat`, 6 another owned plot's `Base`, 7 none. Prefer keying on `State.tutorialStepId` / Player attribute `TutorialStepId` (names, stable) over the number. Save migration: a stored `tutorialStep` of 4..6 (old Merge/Steal/Rebirth) maps to 5..7; 0 stays done.

### 8.4 Instance attributes (new)

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

### 8.5 Plot prompts (replace §2 "Owner-only prompts")

All three carry `ShowOnlyToUserId = owner`, are `Enabled = false` on a free plot, `RequiresLineOfSight = false`, `HoldDuration = 0`. Names are in `Constants`.

| Prompt (Constants) | Parent | KeyCode | ActionText | ObjectText |
|---|---|---|---|---|
| `LockPrompt` (`LOCK_PROMPT_NAME`) | `LockButton` | E | `"Lock base $<cost>"` while open, `"Extend lock $<cost>"` while locked, `"Lock is maxed"` at `LOCK_MAX_REMAINING` | `"<name>'s base: OPEN"` or `"<name>'s base: LOCKED m:ss"` (updated every reconcile) |
| `BuyPadPrompt` (`BUY_PAD_PROMPT_NAME`) | the lowest locked `Pad_<j>`; moved as pads unlock; parked (disabled) on the last pad when all are unlocked | E | `"Buy pad $<cost>"` | `"Pad <j> of <PADS_MAX>"` |
| `MergePrompt` (`MERGE_PROMPT_NAME`) | `MergeVat` | E | `"Auto-merge"` | `"Merge vat"` |

`LockPrompt` = `Request("Lock")`, `BuyPadPrompt` = `Request("BuyPad")`, `MergePrompt` = `Merge.findPair` + `Request("Merge")`. Results are Notifies.

### 8.6 Notify sound names (added to §3)

`"Rare"`: a Legendary+ wild drop (everyone, `"good"`: `"A LEGENDARY <name> spilled from the fountain!"`, Mythic: `"A MYTHIC <name> spilled from the fountain!!"`; mutations use their display name). `"Goal"`: a goal stage or dex milestone paid (`"good"`: `"Goal complete: <title>! +$<n>"`, `"Slimedex <count>: +$<n> and +<pct>% income!"`). **Sound IDs are stand-ins:** Jolt's `src/ui/Sounds` maps `"Rare"` and `"Goal"` to placeholder catalog sounds (Rare reuses Rain `12222200`, Goal reuses Cash `12222140`) until real ones are picked. A new rebirth rank sends `"New rank: <title>! <text>"` (`"good"`, `"Rebirth"`), and a Luck upgrade proc sends `"Lucky! Your <old> slime became <rarity>!"` (`"good"`, `"Cash"`).

### 8.7 Rarity curve

- `Config.RARITIES[i].weight` = 52, 28, 13, 5.2, 1.45, 0.35 (was 60, 25, 10, 4, 0.9, 0.1).
- **Pity** (per server, `world.pity`): after `PITY_EPIC` (30) drops in a row without an Epic+, the next drop is at least Epic; after `PITY_LEGENDARY` (300) without a Legendary+, at least Legendary. Rain luck stacks.
- Legendary+ (`RARE_ANNOUNCE_TIER` = 5) wild drops (fountain or rain, not the Boss Slime, which has its own toast) get the `RareSpawn` attribute, update the workspace `RareSpawn*` attributes and send the `"Rare"` Notify to everyone.

### 8.8 Progression

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

### 8.8a Rebirth needs a slime (v29)

Rebirth number N also needs one owned slime (`data.slimes`, i.e. on a pad) of the
`Config.REBIRTH_SLIMES[N]` species (a SlimeRoster id; a level without an entry uses the
last entry below it). The cash cost stays. `Progression.canRebirth` rejects with
`need a <Species Name>` when it is missing. The slime is **not consumed**: the normal
rebirth wipe and keeper rule apply, so it only survives as a keeper. State gains
`rebirthSlime: { id, name, tier, color, owned }?` (nil at `MAX_REBIRTHS`); `canRebirth`
already includes the slime check.

### 8.9 DataStore schema v3 (superseded by v4, §8.9a)

Same store and key. v3 = v2 plus:

```luau
upgrades = { Income = n, CarrySpeed = n, OfflineCap = n, Luck = n },  -- levels, missing = 0
stats = { caught = n, merges = n, locks = n, sold = n },
goals = { [goalId] = stagesPaid },
dexRewards = n,                                                       -- dex milestones paid (0..#DEX_MILESTONES)
```

Migration (`SaveData.migrate`, pure, tested with a v12-shaped save): v1 -> v2 as before; v2 (or a version-less v2 shape) -> v3 adds zero upgrades / stats / goals / dexRewards, seeds `stats.caught = max(#slimes, dex count)`, and remaps `tutorialStep` 4..6 -> 5..7 (§8.3). Unknown or newer versions are read field by field with the v3 sanitizer. Everything is clamped (levels to `maxLevel`, stages to `#targets`).


### 8.9a DataStore schema v4: stacking mutations (`Config.SAVE_VERSION = 4`)

Same store and key; no key or field is renamed. v4 = v3 plus `slimes[i].mutations = { name, ... }` (at most `Config.MAX_MUTATIONS`; a fused combo from `Config.COMBOS` is stored by its combo name). The single `mutation` field is still written (the strongest entry, "None" when empty): v3 readers, visuals and dex keys use it.

`SaveData.migrateV3` (v1/v2/v3 -> v4) is pure, returns a copy and is idempotent: `mutations = {}` for "None" / missing, else `{ mutation }`; a slime that already has a list is untouched. Value is the product of the list (a single entry = the v3 value). A version above 4 is never rewritten by the migration; `Genome.sanitize` reads both fields. `FEATURES.MutationStacking` (default on) only controls new rolls (stack chance `STACK_MUTATION_CHANCE`, combo fusing, merge carry-over); migration and loading always run. The Dex counts a stacked slime under its primary mutation (`DEX_TOTAL` adds `#COMBOS` with the flag on).


### 8.9b DataStore schema v5: weather mutations (`Config.SAVE_VERSION = 5`)

No field changes. `SaveData.migrateV4` (v4 -> v5, pure, idempotent) drops duplicate / "None" / non-string entries from each slime's `mutations` and rebuilds a missing list from `mutation`; clean slimes pass through untouched. New mutation ids `Wet`, `Frozen` and combos `Sleet`, `Comet` are added; no id or key is renamed. `FEATURES.WeatherMutations` (default on) gates only the roll bonus from `Config.WEATHER[id].mutation / chanceBonus` (WEATHER.md); loading never depends on it.

### 8.9c DataStore schema v6: settings, plotSkin, stealLog (`Config.SAVE_VERSION = 6`)

- **New field:** `settings = { musicVolume: number 0..1, sfxVolume: number 0..1, muted: boolean }` (`Shared.AudioSettings`; volumes rounded to 0.01; defaults `Config.AUDIO.DEFAULT_MUSIC_VOLUME` / `DEFAULT_SFX_VOLUME`, not muted). Missing or junk fields load as their default.
- **Migration:** `SaveData.migrateV5` (v5 -> v6, pure, idempotent) normalises three fields that were unversioned before: `plotSkin` (a known skin id is kept, else `"classic"`; unlock is still checked on load), `stealLog` (`StealAlert.clean`, capped at `LOG_CAP` 12, junk -> empty) and `settings` (`AudioSettings.clean`). It never looks at a feature flag: with `PlotSkins`, `StealAlerts` or `Audio` off the field is kept, saved again and simply unused.
- **Remote:** `Request("SetAudioSettings", musicVolume: number, sfxVolume: number, muted: boolean)`, rate limit 0.5 s. Wrong types and non-finite numbers are `"bad argument"`; numbers are clamped to 0..1. With `FEATURES.Audio` off it is refused (`"audio settings are off"`) and the save is not touched.
- **State:** `settings?` (same shape), only with `FEATURES.Audio` on.

### 8.10 Speed Coil (replaces the §2 bullet)

Owning the coil makes the server enforce WalkSpeed `SPEED_COIL_WALK_SPEED` (22) when not carrying and `22 x (1 - slowdown)` while carrying (was: ignored while carrying). The server always enforces its target (Player attribute `TargetWalkSpeed`), every 0.1 s and on every `CharacterAdded`, instead of only overwriting speeds it recognised. The `SpeedCoil` tool still sits in the Backpack (cosmetic; `ToolTip` "Speed Coil: always on").

### 8.11 Dropped slimes

A dropped wild slime is snapped to the first **collidable** surface under the drop point: raycast from 4 studs above the carrier's root straight down (`RespectCanCollide = true`, excluding characters and slime models), so it lands on the ground, a plot base or a ramp, never on a head, canopy or invisible trigger. No hit within 200 studs: it goes back to its fountain landing spot. It falls there over 0.3 s and stays anchored (§4). The Lune harness checks it (`tools/livetest`).

### 8.12 Test hooks (server-only, never live)

`src/server/TestHooks.luau` lets scripted sessions grant cash and skip time on a live `world`. **Guard:** (1) it is not wired to any remote, prompt or chat command, so no client can reach it; only server code that already runs with full authority (a Luau Execution task, Lune tests) can call it; (2) `TestHooks.enable(world)` refuses (returns false, every hook then errors) unless `workspace.DataStoreMode == "Memory"`, and the publish checks (`scripts/check-place`, `tests/PlaceSafety.spec`) already fail any place that sets that attribute; (3) `tests/TestHooks.spec` fails if any `src/` file other than TestHooks and its spec references it.

## 9. v16 additions (2026-10-15, Phoenix)

**Status:** contract first; the server commits that follow implement it. Driven by the v15 Studio playtest (`/workspace/roblox/usability/v15-findings.md`). New fields are optional for readers. Where this section and §1-§8 disagree, this section wins.

### 9.1 No "claim free plot" (removed in v30 C6)

Plots are **auto-assigned on join** (`Sessions.join`, lowest free plot) and freed on leave. The v16 `ClaimPrompt` on a free plot's `BuyStand`, `PlotClaim.luau`, `Constants.CLAIM_PROMPT_NAME`, `world.claims` and the per-plot `BuyStand` model are gone. `ranch_shop_stand` is used only by the plaza `ShopStand`.

### 9.2 Tutorial: no skipping steps you haven't done (finding #8)

Replaces the "finishes that step and every step before it" rule of §2 / §8.3. `TutorialProgress.complete(data, name)`:

- The **current** step's action finishes it. A **later** step's action no longer jumps ahead (buying a pad at step 1 used to skip Deposit and Lock); an earlier step's action still does nothing.
- After any action the server **skips every step the player has already done**, judged from saved data (`TutorialProgress.isDone`): Grab / Deposit `stats.caught > 0`, Lock `stats.locks > 0`, BuyPad `padsUnlocked > PADS_START`, Merge `stats.merges > 0`, Steal `totalStolen > 0` or `rebirths > 0` (solo servers can't steal: `StealService.tickTutorial` skips Steal after `TUTORIAL_STEAL_SKIP_SECONDS` = 20 s with no other player's pad slime), Rebirth `rebirths > 0`.
- So a player sees every step they haven't done yet, in order. Save format, step names and `State.tutorialStep` / `tutorialStepId` are unchanged.

### 9.3 `State.lockStartedAt` (finding "lock bar scaled to 300 s")

```luau
lockStartedAt: number,  -- server time the current lock began (join lock or a purchase while open); extending keeps it
```

The HUD lock bar can show `(lockUntil - now) / (lockUntil - lockStartedAt)`, so a fresh 60 s lock reads full instead of 18 % of `LOCK_MAX_REMAINING`. In every snapshot.

### 9.4 Findings that are not server work (owners)

- **Jolt (src/ui):** scroll lists `VerticalAlignment` (#1), carry panel under tutorial card (#2), Speed Coil description in `ShopCatalog` (#4, see §8.10: it works while carrying), boss banner width (#5), rebirth disclaimer clip (#6), `UIScale` (#7), tutorial copy "hold" -> "press E" and free-vs-paid (#8; `GrabPrompt.HoldDuration` is 0), Daily modal vs tutorial on spawn (#9), lock bar via §9.3, cash format, rebirth double-click, dex badge.
- **Archer (src/visuals):** tutorial arrow texture (#10), Sky / night, pad colours, LockButton colour should follow the plot `Locked` attribute, plot signs at night, the plot Sign + BuyStand duplication.

## 11. v29 #4: friend income bonus (2026-10-16, Jolt)

**Status:** contract first. `Config.FEATURES.FriendBonus` (default on); `false` = no bonus, no badge.

- **Rule:** +`FRIEND_BONUS_PER_FRIEND` (10%) income per friend of the player who is in the **same server**, at most `FRIEND_BONUS_CAP` (+30%). `FriendBonus.bonus(count)` (`src/shared/FriendBonus`).
- **Server (`src/server/Friends`):** `Player:IsFriendsWith` through a pcall, cached per pair for `FRIEND_CACHE_SECONDS` (600). A failed check keeps the last known answer (false when none) and isn't retried for `FRIEND_RETRY_SECONDS` (30). `Friends.refresh` runs on every join and leave (async; it yields) and writes `session.friends` and `data.friendBonus`.
- **Income path:** `data.friendBonus` (runtime, **never saved**, no save-format change; optional on `PlayerData.Data`) is a factor of `Perks.bonusMultiplier`, so `incomePerSecond`, `slimeIncome`, `State.incomeMultiplier` and offline income all use it (offline pays at join, before any friend is known: 0).
- **State:** `friends: { count: number, bonus: number }` in every snapshot (0 / 0 with none or the feature off).
- **UI:** HUD banner `"👥 +20% friends"` (hidden while a menu is open, like the modifier banner); the SlimeDex card's income line adds `Friends +20% income`.

## 12. v29 #10: live admin events (2026-10-16, Jolt)

**Status:** contract first. `Config.FEATURES.AdminEvents` (default on); `false` = nothing can be triggered. Server-only logic.

- **Who:** `AdminEvents.isAdmin(userId, creatorId)` (`src/shared/AdminEvents`): the place owner (when `game.CreatorType` is User) or a UserId in `Config.ADMIN_USER_IDS` (empty by default). There is no remote and no client code path; non-admins get no reply at all.
- **Trigger:** chat `"/event <luck|mutation|rain> [minutes]"` (`Player.Chatted`, minutes clamped to `ADMIN_EVENT_MIN/MAX_SECONDS`, default 10). `src/server/AdminEventsService`.
- **Cross-server:** `MessagingService` topic `Config.ADMIN_EVENT_TOPIC`, payload `{ v = 1, id, seconds, by, nonce }`. Every call is in a pcall; a failed send still starts the event on this server. Receivers rebuild the payload (`AdminEvents.validate`: known id, clamped seconds, `by` must itself be an admin), drop a repeated nonce, and share one cooldown (`ADMIN_EVENT_COOLDOWN`, 20 s) with local triggers.
- **Effects (existing systems):** `luck` / `mutation` set `world.adminEvent`, which overrides the dawn / dusk `world.modifier` until it ends (`Spawner.stepModifier`; then the normal roll resumes); `rain` calls `Spawner.forceRain`. Needs `FEATURES.CycleModifier` for the multipliers.
- **State / UI:** `State.modifier.icon?` (emoji) is set while an admin event runs; the HUD modifier banner shows `"<icon> Luck Event x3 luck - 9:00 left"`. A server-wide toast announces it. No save-format change.

## 13. v29 #12: co-op ritual circle (2026-10-16, Jolt)

**Status:** contract first. `Config.FEATURES.CoopRitual` (default on); `false` = no circle is built, nobody is blessed. Server-authoritative; no remote, no client code path, no save-format change.

- **Circle:** `workspace.Map.RitualCircle` (`server/RitualView`), plain anchored decor parts at `Config.RITUAL` `BEARING` 247.5 / `DISTANCE` 46 (inside the plaza: past the slide end (r35.5, +Z) and inside the goo-parade lane (r64.75+), so it blocks no path, plot or prop spot; `tests/Ritual.spec` checks it). 4 glowing spot discs plus an orb with a `BillboardGui` ("Slime Ritual / 2/3 players", then "Hold still! 5s", then "Ritual resting 3:20"). Spots turn green while someone stands on them.
- **Rule (`shared/Ritual`, `server/RitualService`):** 3 or 4 distinct players stand on distinct spots for `HOLD_SECONDS` (6). Dropping below 3 resets the timer. Then each participant gets **Blessed**: `data.ritualBonus` = +20% (3 players) or +30% (4) income for `BLESS_SECONDS` (180), a factor of `Perks.bonusMultiplier` like `friendBonus` (runtime only, never saved). The circle then rests `SERVER_COOLDOWN` (240 s); a blessed player can't count again for `PLAYER_COOLDOWN` (600 s, kept when they leave).
- **Anti-abuse:** positions are read on the server from `HumanoidRootPart`; a player counts on the nearest spot within `STAND_RADIUS` and at most `STAND_HEIGHT` above the ground, at most once; a spot holds one player (nearest wins), so two accounts can't share a spot; only players with a loaded session and a slime (on their plot or carried) count.

## 14. v29 #14: follow-pet passives (2026-10-16, Jolt)

**Status:** contract first. `Config.FEATURES.PetPassives` (default on); `false` = the follow pet is cosmetic only. Server-authoritative; no new remote, **no save-format change** (derived at runtime from the saved `favoriteId` and the owned slime, so old saves just work).

- **Rule (`Config.PET_PASSIVES`, `Perks.petPassive`):** the favourite slime's tier picks the kind (`KIND_BY_TIER`: income, income, luck, luck, mutation, mutation, luck); value = `tier * perTier` + `MUTATION_STEP` (1%) per mutation, capped per kind (income 8%, luck 6%, mutation 12%). No favourite (or not owned) = no perk; changing or clearing the favourite changes it on the next snapshot.
- **Effects:** income is a factor of `Perks.bonusMultiplier` (so `incomePerSecond`, `slimeIncome`, offline income); luck is added to `Perks.luckChance` (rarity-up on deposit, `Carry`); mutation is added to `Config.MERGE_MUTATION_CHANCE` in `Merge.apply` (`Perks.petMutationBonus`).
- **State / UI:** `State.petPerk? = { kind, value, icon, text }`; the My Plot panel shows a chip (`🍀 +3% luck`) under the favourite's row (row grows from 56 to 80 px). Glyphs are existing emoji (supplementary plane, already allowed).

## 15. Gaps #15: plot skins unlocked by collection (2026-10-16, Archer)

**Status:** contract first. `Config.FEATURES.PlotSkins` (default **off**: needs frame review); `false` = no remote, no State fields, no plot attribute, no visuals. The save field is still read and written.

- **Rule:** `Config.PLOT_SKINS` lists the skins; each is tied to a SlimeDex set (`set` = rarity tier, 288 keys: `PlotSkins.setSize`) and unlocks at `owned / setSize >= threshold` (0.75, integer test `owned >= ceil(setSize * threshold)`; weather mutation keys do not count). `classic` is the default and always unlocked. `src/shared/PlotSkins`.
- **Save (versioned since v6, §8.9c):** `plotSkin: string`. Missing, unknown or not unlocked loads as `"classic"` (`SaveData.deserialize`; `SaveData.migratePlotSkin` is the pure step; `migrateV5` normalises unknown ids).
- **Remote:** `Request("EquipPlotSkin", skinId)` (`string`; rate limit 0.5 s). Refused unless the skin exists and is unlocked, or when the flag is off. Equipping `classic` always works.
- **State (flag on only):** `plotSkin: string`, `plotSkins: { { id, name, setName, tier, owned, total, needed, fraction, unlocked, equipped } }` (classic first).
- **Plot attribute (flag on only):** `Plot_<i>.PlotSkin = <id>` ("classic" for a free plot). Clients paint from it.
- **Visuals (client, `PlotDecor.applySkin`):** floor `Base` colour + material, fence / gate mesh tint, and the skin's decor mesh stands in for the plot's `Mailbox_<i>` slot. **No new mesh slots:** the decor meshes are templates in `ReplicatedStorage.PlotSkinMeshes` (server-published), not world slots. `WorldLayout.build` is unchanged.
- **Studio-only debug:** SlimeUI attribute `PcwPlotSkin` (skin id) forces Plot_1's skin and the picker view for shots.

## 16. Revenge steal (FEATURES.Revenge, default `true`)

- When a steal completes (`Carry.deposit(world, thiefId, now)` of a stolen slime), the victim gets a window of `Config.REVENGE_SECONDS` (60) on that thief. Robbing the same victim again refreshes it. Server state: `world.revenge[victimId][thiefId] = window end` (`server/Revenge`).
- **Lock cost:** while the thief is inside any victim's window their lock costs `Config.REVENGE_LOCK_COST_MULT` (2) x `Economy.lockCost`; several windows do not stack. It applies to the purchase (`Steal.buyLock` 5th arg), `State.lockCost` and the `Plot_<i>.LockCost` attribute. Lock length is unchanged.
- **Highlight:** Player attribute `RevengePlots` (`Constants.REVENGE_PLOTS_ATTRIBUTE`, string "3,5" via `Shared.RevengePlots`) is set on the **victim only**: plot indexes of thieves in their window who are still in the server; nil = none. `VisualsClient/RevengeFx` draws one local `Highlight` (`RevengeHighlight`) per plot on `Plot_<i>.Base`.
- A window ends at expiry (`StealService.step` prunes it), or when the thief or the victim leaves (`Sessions.leave` -> `Revenge.forget`). State is pushed to the thief so `lockCost` drops back. Nothing is saved.
- Flag off: no marks, no attribute, normal lock price.

## 17. v21: full steal alerts (2026-10-16)

**Status:** contract first. `Config.FEATURES.StealAlerts` (default **off**: needs frame review); `false` = today's behaviour exactly (HUD banner `STOLEN! ...` + the Alarm toast), no attributes, no State field, nothing logged. Server-authoritative; the client only draws. No new remote and no new MeshParts or Parts (Frames, a BillboardGui, Highlights, a Trail with two Attachments, a ParticleEmitter).

- **Owner (client, `ui/StealAlertFx`):** when one of my slimes gets `stolenBy` set: a red screen-edge flash (`StealAlert.flashAlpha`, `Config.STEAL_ALERT.FLASH_SECONDS` 1.2 s), repeat alarms (the server's toast plays the first `Alarm`; it sounds again every `ALARM_REPEAT` s, at most `ALARM_REPEATS` more times; the sound is the existing `Sounds.IDS.Alarm`), a direction arrow on the screen edge (`StealAlert.bearing` / `edgePoint`) with the distance, and a world ping on the thief (billboard `THIEF` + red outline, seen through walls; the arrow hides inside `PING_HIDE_STUDS`). It ends when `stolenBy` clears (escape, slap, deposit).
- **Thief trail:** Player attribute `Stealing` (`Constants.STEALING_ATTRIBUTE`, `true` while `session.carry.kind == "stolen"`, nil otherwise; flag on only). Every client draws a `Trail` (lifetime `TRAIL_LIFETIME` 0.6 s) on that player's `HumanoidRootPart`, so the thief sees it too.
- **SLAP hit effect:** `World.Event.reason` (Escaped: `"wriggle" | "timeout" | "slap" | "drop" | "left"`); on `"slap"` the adapter sets the carrier's Player attribute `SlapHitAt` (`SLAP_HIT_ATTRIBUTE`, server time). Clients draw a white flash, a `SLAP!` pop and a particle burst on that character when it changes (a value older than 3 s, e.g. seen on late join, is ignored).
- **Save (versioned since v6, §8.9c):** `stealLog: { { thief: string, slime: string, at: number } }` (`PlayerData.stealLog`, `SaveData` clean/capped, `StealAlert.clean`). `Carry.deposit` appends the finished theft to the **victim's** log (`StealAlert.record`, cap `LOG_CAP` 12, oldest dropped, names control-stripped and cut to `NAME_MAX`). At join (`Sessions.join`) the saved log moves to `session.awayLog` (never saved) and the saved log starts empty again, so a notice shows once.
- **State:** `stealAway: string?`, e.g. `"While you were away 3 slimes were stolen by Rex, Mia and Kit."` (`StealAlert.summary`: thieves most recent first, each once, at most `SUMMARY_NAMES` 3, then `and N more`). nil when none or the flag is off. The client shows it once per join as a long `away` toast.
- **Offline note:** a theft only completes while the victim is in the server (a plot is unreachable once its owner leaves; `Carry.deposit` refuses), so the log is "thefts since you were last here" and always includes ones the player saw live. Reading a theft off a persistent store of an offline player is not done (it would write another player's key).
- **Studio-only debug:** SlimeUI attribute `PcwStealAlert` = true fakes one theft (flash held at its peak, arrow pointing right) and the join notice, for the pc-watcher proof shot.

## 18. v21: weekly event rotation (2026-10-16)

**Status:** contract first. `Config.FEATURES.WeeklyEvents` (default `false`); `false` = no boost, no multiplier, no attribute (an existing value is cleared). Server-authoritative; no remote, **no save-format change**, nothing saved.

- **Schedule (`src/shared/WeeklyEvents`, `Config.WEEKLY`):** a pure function of unix time (UTC), so every server agrees; tests pass a fake `now`. Weeks are ISO weeks: Monday 00:00 to the next Monday 00:00 UTC (`weekIndex`, `isoWeek`). Intervals are half-open `[startsAt, endsAt)`.
  - **Weekly mutation:** exactly one per week, `MUTATION_ROTATION[week % n]` (plain `Config.MUTATIONS` names; Eclipse stays rare). It adds `MUTATION_CHANCE_BONUS` (3 %) of roll range to that mutation only, the same window mechanism as the weather bonus (`Genome.rollMutation(…, weeklyMutation, weeklyBonus)`, placed after the weather window). Consecutive weeks differ.
  - **Saturday trait event:** `TRAITS[week % m]` (Lucky: x1.5 rarity luck, Mutant: x1.5 mutation chance) on `TRAIT_WEEKDAY` 6 from `TRAIT_START_HOUR` 18 UTC for `TRAIT_SECONDS` (2 h). Clamped to end inside its own week.
  - **Caps:** `WeeklyEvents` clamps the bonus to `MAX_CHANCE_BONUS` (5 %) and each multiplier to `MAX_MULTIPLIER` (x2) whatever the config says. One mutation event is always active, at most one trait event, and none of the same kind overlaps (`tests/WeeklyEvents.spec` simulates 21 days).
- **Shared API (for the events board):** `WeeklyEvents.current(now)` (mutation event first, then the trait event when live), `next(now)` (the first event starting after `now`), `state(now)`, plus `Event = { kind, id, label, icon, week, startsAt, endsAt, mutation?, chanceBonus, luck, mutationMult }`.
- **Replicated attribute:** `workspace:GetAttribute(Constants.WEEKLY_EVENT_ATTRIBUTE)` (`"WeeklyEvent"`), written by `server/WeeklyEventService` (only when the value changes; re-checked at every boundary, at most every `SYNC_SECONDS`). Format `week|mutation|mutationEndsAt|activeTraitId or -|traitEndsAt or 0|nextKind|nextId|nextStartsAt` (unix seconds); `WeeklyEvents.decode` parses it.
- **Effects:** applied at drop time in `Spawner.spawnOne` (wild fountain drops only; merges, Appraise and the Boss Slime are untouched). The trait multipliers stack with the dawn / dusk modifier and Slime Rain by multiplication; the weekly values are small and capped. The clock is `Spawner.unixTime` (default `os.time`; `tests/ServerFixtures` pins it to `nil` = no schedule so seeded specs never depend on the date).
- **Live admin events (§12):** a running admin `luck` / `mutation` event **replaces** the weekly effects (no stacking, so an admin's x3 / x4 stays exactly what they asked for): `spawnOne` skips the weekly multipliers and the mutation boost while `world.adminEvent` is set, and they resume when it ends. The admin `rain` event does not set `adminEvent` (it calls `forceRain`), so weekly effects continue under it. The attribute keeps showing the schedule either way. Admin events and `Config.WEEKEND` (income) are independent.

## 19. v19: fountain tiers + slime families per rank (`FEATURES.FountainTiers`, default `false`)

Owner: Phoenix (server, shared), Archer (visuals). Off = one Meadow fountain, Classic drops only, no attribute, no templates, rank cards unchanged.

- **Tier.** `World.fountainTier` (1..4) is the best rank seen on the server: `FountainTiers.tierFor(max rebirths over sessions)`, raised by `Spawner.stepFountainTier` each frame, never lowered while the server lives. Steps at the `Config.REBIRTH_TIERS` entries that carry `family`: 3 rebirths (Slime Wrangler) = Orchard Fountain, 6 (Goo Tycoon) = Frost, 10 (Slime Sovereign) = Starlight. Raising it toasts everyone once.
- **Families.** `SlimeRoster` entries with `family` set (`orchard`, `frost`, `starlight`), one type per tier 1..6 (18 new ids, permanent, lower-case; none at Secret). `SlimeRoster.forTier(tier)` still returns Classic only; `forTier(tier, family)` returns a family's. Species stay the only saved trace (`Genome.sanitize` already keeps a known species id and drops an unknown one), so there is **no new saved field and no `SAVE_VERSION` bump**.
- **Drops.** `Fountain.roll(..., familyPool)`: with a pool (`FountainTiers.pool(world.fountainTier)`) `Config.FAMILY_DROP_CHANCE` (0.3) of drops are a family type (weights 5 / 3 / 2) rolled with the family's rarity luck (1.2 / 1.4 / 1.7 on the tier >= 3 weights). With no pool (flag off or tier 1) no extra `rng` draw is made, so drop sequences are exactly the old ones. Boss slimes stay Classic.
- **Catching.** `Carry.grabWild` refuses a family slime when the player's own rebirths are below its family's rank (`Carry.familyBlock`, "Reach Slime Wrangler (3 rebirths) to catch Orchard slimes"), before any price is charged. Stealing, merging and owning are never gated.
- **Economy untouched.** No income multiplier, no price change: a family slime's income, wild price and sell value are those of a Classic slime of the same tier, size and mutations.
- **Replication.** workspace attribute `FountainTier` (`Constants.FOUNTAIN_TIER_ATTRIBUTE`), set only with the flag on. `ReplicatedStorage.FountainTierMeshes` holds the two templates (`MeshSwap.publishFountainTierTemplates`).
- **Visuals (client, `FountainTierFx` + `FountainTierDecor`).** Tier 2+: `fountain_tier_ring` (8 lantern posts, r 14.6) on the ground; tier 3+: `fountain_tier_crest` floating over the goo crown, spinning and bobbing; both tinted per tier (copper / silver / gold, `MeshPart.Color`), tier 4 crest Neon; `Map.Volcano.Crater.CraterGlow` takes the tier's glow colour. Both meshes are run-time only: 0 `WorldLayout` slots (`RanchProps.INTENTIONALLY_UNPLACED`), at most 2 extra MeshParts while shown. Studio only: SlimeUI attribute `PcwFountainTier` forces the tier (pc-watcher shots `19-fountain-tier-N`).
- **Rank cards.** `Perks.tierText` appends "opens the Orchard slimes" for ranks with a family, only with the flag on.
- **Needs frame review before the flag goes on:** the ring posts against the slide legs, the crest height against the emerge slimes, the glow colours at night.

## 20. v21: server events board (2026-10-17)

**Status:** `Config.FEATURES.EventsBoard` (default `false`); `false` = no banner. Client only: **no remote, no server code, no save-format change**, no new mesh.

- **What it shows (`src/ui/EventsBoard`, pure):** one HUD banner `EventsBoard` in the `Banners` stack (hidden while a menu is open like the others), lines: `📅 Server events`; `🧪 <Mutation> week - <time> left` and the Saturday trait event (`🍀 Lucky Saturday x1.5 luck - <time> left`) from the replicated `WeeklyEvent` attribute (§18, `WeeklyEvents.decode`; needs `FEATURES.WeeklyEvents`, otherwise those lines are absent); the day/night or live admin modifier through `ModifierBadge.banner` (needs `FEATURES.CycleModifier`); and `Next: <event> in <time>` from the same attribute. Nothing running = banner hidden.
- **Clocks:** weekly times are unix (`os.time()`, like the schedule), the modifier uses the server clock (`ctx.serverNow()`), as their own badges do. Past events are dropped, so a stale attribute never shows an ended event.
- **Pc-watcher:** shot `v21-events-board` (`luau/events_board`) fails when the banner is missing, hidden or lists no event.



## 21. v19: 3-slime merge vat (`FEATURES.MergeVat3`, default `false`)

Owner: Phoenix (server, shared), Jolt (panel), Archer (vat model). Off = the two-slime vat exactly as before: no `Merge3` action (refused "the 3-slime vat is off"), no switch in the Merge panel, no template, the primitive vat disc.

- **Rules (`Shared.TripleMerge`, pure).** Exactly three **different**, owned, not-busy slimes of **one** rarity T go in; one slime comes out and all three are consumed. Tier: T + 1, or with `Config.TRIPLE_MERGE_JUMP_CHANCE` (0.2) T + 2, never a jump into Secret (a jump needs T + 2 <= MAX_TIER - 1: Common..Epic can jump); T = 6 gives Secret (T + 1), as in the pair vat; tier-7 inputs stay 7 and always roll a mutation. Mutation: the strongest of the three (matching ones upgrade, `Merge.inheritedMutation` folded over the three), every other mutation they carry too (strongest first, combos fuse, `Config.MAX_MUTATIONS`), plus a fresh roll at `Config.TRIPLE_MERGE_MUTATION_CHANCE` (0.3, + the pet bonus) and the `MutationStacking` roll. Size: mean + `Config.TRIPLE_MERGE_SIZE_BONUS` (0.15), clamped. Pattern / eyes / mouth each from one of the three. The child is a real `SlimeRoster` species of its tier (its name and colour), not a blended name.
- **Deterministic.** All randomness is the server `world.rng`, drawn in a fixed order (jump, species, mutation x2, three trait picks, stacking): one seed and inputs always give one child (`tests/TripleMerge.spec`).
- **Anti-dupe / authority.** `Request("Merge3", a, b, c)` (3 strings, `Validate.ACTIONS.Merge3` 0.5 s). `TripleMerge.apply` validates everything first (3 ids, no repeats, each owned, none in `World.busySet`, one tier, a fresh child id) and only then removes the three and adds the child on the first slime's pad, so a refused merge changes nothing and the same slimes can never be merged twice. The favourite moves to the child. Stats (`merges`), Dex and the toast go through `MergeVat.merge3` like the pair vat. The client only gates its button (`Selection.canMergeTriple`).
- **Economy untouched.** No cash cost, no sell / buy value changes. Three slimes for one tier up (the pair vat does it with two) is the price of the extra odds: a 20 % second tier, every mutation kept, a species result.
- **Panel (existing menu system).** `Panels/Merge`: a "2 slimes / 3 slimes" switch above the hint (only while the flag is on), up to three picks, `Merge 3` hold button, status "You get: <rarity> · 20% <rarity+1>". Studio only: SlimeUI attribute `PcwMergeVat` = true forces it on and opens in 3-slime mode (pc-watcher shots `19-merge-vat-*`).
- **Vat model.** `merge_vat` (kit mesh, copper goo cauldron, three funnel spouts, 1508 tris): the client (`VatFx`, `VatDecor.pose`) stands a clone of `ReplicatedStorage.MergeVatMeshes.merge_vat` over the **local player's own** plot `MergeVat` disc (the disc and its goo only turn invisible; the MergePrompt keeps working). 0 `WorldLayout` slots (`RanchProps.INTENTIONALLY_UNPLACED`), at most 1 extra MeshPart. The server publishes the template with the flag on (and in Studio, for the shots).
- **Needs frame review before the flag goes on:** the panel with the switch on a 390 px phone, the vat scale against the disc, the vat in the night look.

## 22. v29 #13: restocking consumables shop (2026-10-16)

**Status:** `Config.FEATURES.Consumables` (default on); `false` = no Shop section, `BuyConsumable` refused ("the shop is closed"). Server-authoritative.

- **Schedule (`shared/Consumables`):** slot = `floor(unix time / CONSUMABLES_RESTOCK_SECONDS)` (300 s). The stock of a slot is a pure function of the slot (seeded `Rng`), so every server agrees; `State.consumables.restockAt` drives the shop countdown. Each item rolls `minStock..maxStock` = the quantity **each player** may buy this restock (0 = sold out); counts live in `data.consumables = { slot, bought }` and reset when the slot changes.
- **Remote:** `Request("BuyConsumable", itemId, slimeId?)`, rate limit 0.5 s (`Validate.ACTIONS`). Checks stock, cash (price x rebirth multiplier) and the item's precondition first; nothing is charged when the effect cannot happen.
- **Items (ids are save keys, never rename):** `MutationSpray` (rolls a `MUTATIONS` mutation onto an owned, idle slime; respects `MutationStacking` combos and `MAX_MUTATIONS`; rerolls a no-op roll up to 8 times), `LuckPotion` (server-wide: `world.potionUntil`, each potion adds `LUCK_POTION_SECONDS` up to `LUCK_POTION_MAX_SECONDS`; spawn luck = day/night modifier x `LUCK_POTION_MULT`, capped at `SPAWN_LUCK_CAP`, a modifier above the cap alone is never cut), `WeatherTotem` (`WeatherService.request`: the stock-seeded weather is next; only offered with `FEATURES.Weather` and a Weather service).
- **Save:** optional `consumables` field, default "nothing bought"; no `SAVE_VERSION` bump. **State:** `State.consumables?` (items with `left` / `max`, `restockAt`, `luckUntil`).

## 23. v19: Rain Magnet upgrade (`FEATURES.RainMagnet`, default `false`)

Owner: Phoenix (server, shared), Jolt (shop row), Archer (prop). Off = the upgrade is not listed in `State.upgrades`, `BuyUpgrade "RainMagnet"` answers "unknown upgrade", `Perks.rainMagnetChance` is 0 (a saved level is inert, not lost), no plot attribute, no template, no prop.

- **The upgrade.** `Config.UPGRADES` entry `RainMagnet` ("Rain Magnet"): rank 6 (Goo Tycoon), 5 levels, +5 % per level (max 25 %), price `300000 * 3^level` like Lucky Charm's curve one rank later, `flag = "RainMagnet"` (new optional `Upgrade.flag`: `Upgrades.available` hides / refuses a flag-gated upgrade while its flag is off). Saves are untouched: `SaveData` keeps `upgrades.RainMagnet` clamped to `maxLevel` whether or not the flag is on, no `SAVE_VERSION` bump. Other upgrades are listed exactly as before.
- **Effect (`Shared.RainMagnet`, `Carry.applyMagnet`).** When a **wild** slime the player caught reaches their plot (`Carry.deposit`, next to Lucky Charm), it has `Perks.rainMagnetChance` to pick up the current weather's mutation: Rain -> Wet, Snow -> Frozen, Starfall -> Galaxy (`Config.WEATHER[id].mutation`, the same hook `Genome.rollMutation` reads, `Weather.getCurrent()`); with no weather mutation the Slime Rain event (`world.raining`) counts as Rain (Wet). It goes through `Genome.addMutation`, so the stack limit and combos (Sleet, Comet...) apply; a slime that already has it or has no room is left alone. Stolen slimes are never touched. Server-authoritative: one `world.rng` draw per deposit that has a level and a target, none otherwise, so seeds are unchanged for everyone else. The player gets a toast "Rain Magnet! Your slime picked up Wet!".
- **Economy untouched.** No sell / buy / income change (a mutation is worth what it already is).
- **Shop row.** The existing upgrade list (`ShopCatalog.upgradeViews`) shows it from `State.upgrades`: badge `UPGRADE_ICONS.RainMagnet`, short text "+5% weather mutation chance", item icon `Upgrade_RainMagnet` (`ItemIcons`; `ITEM-ICONS-NEEDED.md` regenerated). Studio only: SlimeUI attribute `PcwRainMagnet` adds the row (Lv 2/5) and the prop for the shots.
- **Prop.** `rain_magnet` (kit mesh, red horseshoe magnet on a wooden stand pulling three raindrops, 782 tris): `WorldView` sets `Plot_<i>.RainMagnet` (the owner's level, flag on only), the client (`RainMagnetFx`, `MagnetDecor.pose`) stands a clone of `ReplicatedStorage.RainMagnetMeshes.rain_magnet` on the **local player's own** plot, 9 studs to the vat's left, while the level is above 0. 0 `WorldLayout` slots (`RanchProps.INTENTIONALLY_UNPLACED`), at most 1 extra MeshPart. The server publishes the template with the flag on (and in Studio).
- **Needs frame review before the flag goes on:** the prop's spot against the plot's pads on every plot yaw, the shop row text on a 390 px phone.

## 24. v20: welcome-back card (2026-10-17)

**Status:** `Config.FEATURES.WelcomeBack` (default `true`); `false` = no State field, no card. Server-authoritative; no remote, **no save-format change**, nothing saved.

- **Report (`src/shared/WelcomeBack.report`):** at join, `Income.applyOffline` builds `session.welcome = { away, cash, grown }` when the player was away at least `Config.WELCOME_BACK_MIN_SECONDS` (4 h): `cash` is the offline income just paid, `grown` the number of pad slimes whose growth rose from offline time (`Growth.applyOffline`). Missing / future `lastOnline` gives nil.
- **State:** `welcomeBack: { away, cash, grown }?`, present for the whole session. The client shows it once per join (an edge in `PopupQueue`), as the content-sized `Welcome` menu card with the daily streak / reward and the next goal read from `State.daily` / `State.goals`. Collect only closes the card: the cash was paid at join.
- **Ordering (`ui/PopupQueue`):** the tutorial blocks it like the Daily popup; Welcome opens before Daily, and Daily waits until the Welcome card is closed (no overlap).

## 25. v23: server performance profiler (`FEATURES.ServerProfiler`, default `false`)

**Status:** `false` = every `Profiler` call returns at once (no clock read, no table write, no log, no attribute). Server only; no remote, no State field, no save change.

- **Module (`src/server/Profiler`, pure, Lune-tested):** `record` / `time` keep the last `Config.PROFILER.WINDOW` (120) samples per system in a ring buffer (ms from `os.clock`); `stats` gives avg, nearest-rank p95 and max; `count` bumps named counters (the `Request` remote) that the summary prints per second.
- **Wired in `init.server`:** the Heartbeat is timed as `Heartbeat` with `Rescue`, `GameLoop` (spawner, steal, income, milestones), `Players` and `View` inside it; `Request` calls are counted.
- **Output:** every `Config.PROFILER.LOG_INTERVAL` (30 s) one line, e.g. `[Profiler] | GameLoop 0.12/0.30ms | Heartbeat 0.8/1.9ms | instances=1234 | players=3 | Request=3.2/s` (avg/p95 per system; instance count is taken only when a line is due), and one `warn` per system whose p95 is over `Config.PROFILER.BUDGET_MS[name]`. The line is also set as workspace attribute `ProfilerSummary` (read-only dump; no chat command).
