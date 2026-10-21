# Steal a Slime: team contract

**Design:** `/workspace/roblox/steal-a-designs.md` §6. **Date:** 2026-10-14, v13 additions 2026-10-15 (§8).

**Rule: new features add their own `contract/<feature>.md` file plus ONE line in the index table at the bottom of this file. Do not append sections to this file.** This file is the core (§1-§7) and the index; feature sections (§8 and up) live in `contract/`.

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
  init.server.luau wiring only: Remotes.setup(), Request -> Actions.handle, builds
                   the modules below and connects them
  entry adapters:  Persistence (save backend, DataStoreStatus), ServerContext (the one
                   ctx), Outbox (World events -> remotes / Effects / badges), EffectsView,
                   LeaderboardView, PlayerAttributes, PlayerLifecycle (join / leave,
                   autosave, BindToClose), ServerLoop (Heartbeat), StudioHooks (Pcw*),
                   SafeCall (pcall + one log line)
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
  HUD, plot/merge/rebirth panels, Slimedex, steal alerts, leaderboard
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
  - **Slime Rain:** every `RAIN_INTERVAL` (1 h) for `RAIN_DURATION` (3 min). Spawns keep the normal pace, the wild cap is ×2 and luck is ×5 (`Progression.rainStatus`, `Fountain.wildCap`).
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
  - `Request("Lock")` buys `LOCK_SECONDS + LOCK_SECONDS_PER_REBIRTH × rebirths` s; one purchase and the stacked lock are both capped at `LOCK_MAX_REMAINING` (3 min) (`Steal.lockDuration`, `Steal.buyLock`). Locks are bought only on the owner's own plot (the `LockButton` prompt, or the HUD Lock button; under `WorldShopsStrict` the HUD button needs the player at their lock pad). No shop sells locks or longer locks.
  - Stealing pings the owner (Notify `"bad"` plus `SlimeView.stolenBy`).
  - **No time limit:** a thief can hold a stolen slime as long as they like. It escapes home only when the carrier is slapped (Bat or a PvP knockback), drops it, dies / respawns or leaves. While it is carried the thief sees it see-through (client-only `ui/CarryFade`, the Move fade). An escaped slime glides back to its pad (flat, no bounce, §37) for 1.5 s (`World.ESCAPE_BOUNCE_SECONDS`, model `State = "Escaping"`). It can't be stolen, sold or merged until it lands.
  - If the thief reaches their own `HomeZone` first, `Steal.complete` moves the slime to the thief.
- **Rebirth:** `Progression.rebirth` wipes cash and slimes but keeps the favourite (or the best slime). It adds +`REBIRTH_MULTIPLIER_STEP` income and +10 s lock.
- **DataStore:**
  - Store `Constants.DATASTORE_NAME`, key `"u_<UserId>"`.
  - The record is `SessionLock` wrapped around `SaveData.serialize`.
  - Autosave every `AUTOSAVE_INTERVAL`, plus on leave and on `BindToClose` (waits up to 25 s for pending saves).
  - Load retries 5 times with `SessionLock.backoff`. In a live server a failed load kicks the player; in Studio they get an unsaved fresh profile.
  - A save retries 3 times. If another server took the session over, this server stops saving that player.
  - A stored record this build can't safely overwrite (`SaveData.check`: `"newer"` = version above `SAVE_VERSION`, e.g. during a rolling update; `"unreadable"` = not a save it recognises) loads best-effort but the session is **read-only**: saves only refresh / release the lock and write the stored data back untouched, the leaderboard store is not written, the server `warn`s once and the player gets a `"bad"` Notify that progress won't save.
  - Set the workspace attribute `DataStoreMode = "Memory"` to use an in-memory store (no DataStore calls; the leaderboard then ranks this server's players only). Never set it in the published place: `default.project.json` sets no Workspace attributes, and the publish step checks the built file.
  - **Failures are visible:** the server sets the workspace attribute `DataStoreStatus` (`Constants.DATASTORE_STATUS_ATTRIBUTE`) and `warn`s `[Server] DataStoreStatus = ...` on every change to a bad state. Values: `"Ok"` (real DataStore, last load/save succeeded), `"Memory"` (`DataStoreMode = "Memory"`), `"Unavailable"` (`GetDataStore` failed at start; the server fell back to memory and **nothing saves**), `"Error"` (the last load or save hit a DataStore error after retries; goes back to `"Ok"` on the next success).
- **Leaderboard:**
  - `leaderstats` holds IntValues `Cash`, `Rebirths` and `Steals`.
  - A global OrderedDataStore `Constants.LEADERBOARD_STORE` (`"StealASlime_TotalEarned"`, key `"u_<UserId>"`) ranks by `totalEarned`. It's written on every save. It's refreshed every `LEADERBOARD_INTERVAL` and pushed to all clients (§3). A joining player gets the latest board right away. In memory mode the board is also refreshed when someone joins.
- **Shop:** `src/shared/Shop.luau` (pure). `"BuySpeedCoil"` buys an **item** (Item Shop, 2026-10-18: it works while held, so it has a hotbar slot; §27.1). Its price is in `State.shop` (§5.1).
- **Speed Coil** (v13: also while carrying, always enforced, see §8.10): owning it (`data.speedCoil`) sets WalkSpeed to `SPEED_COIL_WALK_SPEED` whenever you're not carrying (equipped or not). While you own it the server keeps one `SpeedCoil` Tool (`Props.speedCoil()`, a `Handle` Part plus welded decor, unanchored, CanCollide false) in your Backpack or character, re-adding it after respawns. It's cosmetic; carrying still unequips it.
- **Tutorial** (v13: 7 steps with `BuyPad` as step 4, see §8.3): `src/shared/TutorialProgress.luau` (pure). The server owns the step; the client only shows it (`State.tutorialStep`, Player attribute `TutorialStep`). Steps (1-based, same order as the UI's `Tutorial.STEPS`):
  1. `Grab`: grab or buy a wild slime.
  2. `Deposit`: bring any carried slime home onto a pad.
  3. `Lock`: buy a lock (`Request("Lock")` or the LockButton).
  4. `Merge`: merge two slimes.
  5. `Steal`: start a steal or hit a thief with the Bat.
  6. `Rebirth`: rebirth.
  Doing a step's action finishes that step and every step before it (so a rebirth finishes the tutorial). Doing an *earlier* step's action again does nothing. After step 6 the tutorial is done (`tutorialStep = nil`). New profiles start at 1. Saves made before the field existed start at 1 if they have no slimes and no rebirths, otherwise done. Saved as `tutorialStep` (0 = done) and kept on rebirth.
- **Daily reward:** `Request("Daily")` (`Progression.claimDaily`). `State.daily` says whether it's available, the streak and what the pending claim pays (`day`, `amount`).
- **Effects:** the server plays `Effects.play` bursts on gameplay events (§5.4).
- **Rain heads-up:** `RAIN_WARNING_SECONDS` (60) before each rain everyone gets Notify "Slime Rain in 1 minute! …" (`"info"`).
- **Extras** (each behind `Config.FEATURES.<name>`, `false` turns it fully off, except the ones marked *always on*, whose flag is retired):
  - Boss event (*always on*): a server-wide boss fight, haul race and trophy, see §33 ([boss-event.md](contract/boss-event.md)). The boss model has attribute `Boss = true` (`Constants.BOSS_ATTRIBUTE`).
  - `FollowPets` (*always on*): the server sets Player attribute `PetSlimeId` (`Constants.PET_ATTRIBUTE`) to `Progression.keeper(data).id` (favourite, else best slime; nil without slimes). VisualsClient (`FollowPets`) clones that slime's replicated model into a local `workspace.ClientPets` folder at 0.55 scale, stands it on a low-poly cloud (`MeshAssets` `pet_cloud`, decor: the server (`MeshSwap.publishPetCloudTemplate`, retried a bounded number of times with backoff) publishes one template in `ReplicatedStorage.PetCloudMeshes` and the client clones it via `PetCloud`; the pet is made at once and gets its cloud when the template arrives, an invisible Mount stands in until then) and glides both after its owner: one RenderStepped connection, the pure `PetFollow` spring (`src/visuals/shared`: critically damped position, smoothed yaw, small bob, snap past 60 studs or on the first frame). Client-only, cosmetic.
  - `DayNight` (*always on*): the server sets `Lighting.ClockTime = DayNight.clockTime(elapsed)` twice a second: one day per `DAY_LENGTH` (12 min), daytime 06:30–17:30 for `DAY_FRACTION` (70 %) of it.
  - `Minimap` (*always on*): `ReplicatedStorage.Visuals.MinimapData.points()` lists `{ kind, name, x, z, plotIndex? }` for the fountain (`kind = "Fountain"`, map centre), `Plot_i`, the three props and HubSpawn from WorldLayout; `toMap(x, z)` gives 0..1 map coordinates over the 640-stud Ground. Data only (no UI yet).
  - `Audio`: client `ui/SoundController` (pure rules in `ui/AudioLogic`, ids in `Config.AUDIO`). SoundGroups `SFX` and `Music` under SoundService; a registry (`buy`, `collect`, `steal`, `merge`, `rebirth`, `alarm`, `error`, `click`) maps to `Sounds.IDS` names or `rbxasset://` ids, an empty / malformed id plays nothing. Toast and steal-alert sounds route through it, throttled per name (`SFX_MIN_GAP`, `SFX_MAX_LIVE`). Every GuiButton under the game's ScreenGui plays `click` (`ui/ButtonClicks`), except hold-to-confirm buttons and disabled Widgets buttons. Ambience: a looped day (birds) / night bed crossfaded over `AMBIENT_FADE_SECONDS` from `Lighting.ClockTime` (night = outside `DayNight.SUNRISE..SUNSET`), at `AMBIENT_VOLUME`, plus at night a one-shot owl (`NIGHT_ONESHOT_ID`) every `NIGHT_ONESHOT_MIN..MAX_SECONDS` once the night has faded in; the ambient asset ids are empty until uploaded (silent). A small "Sound: on/off" button opens a compact panel (bottom-left) with a Mute toggle and two sliders, SFX and Music / Ambience: 5% steps, percent shown, mouse or touch drag, applied live to the attributes / SoundGroups (pure maths in `AudioLogic.snapVolume` / `volumeFromPixel`). Mute / volumes are Player attributes `AudioMuted`, `AudioSfxVolume`, `AudioMusicVolume`, saved per player since save v6 (§8.9c): `State.settings` is applied once on join (`SoundController.load`) and changes are sent back 0.6 s after the last one with `Request("SetAudioSettings", musicVolume, sfxVolume, muted)`. Flag off = Notify sounds play as before, no groups, ambience, button clicks or Sound button; the request is refused.
  - Slime LOD (always on, no flag): the procedural motion gets tiers by camera distance and the saved graphics quality (`Config.SLIME_LOD`, `ui/SlimeLod`): near = full motion every frame, mid = squish only, smaller, every `MID_EVERY` frames, far = Transform reset to identity once, then skipped; low quality shrinks the near / mid radii. Selection stays 4x a second, cap 16 and the on-screen check unchanged. Client-only.
  - `SlimeAnimations`: `true` lets the client play the uploaded KeyframeSequences (`MeshAssets.ANIMATIONS`) on a slime's Animator, but only after a probe load of `SlimeIdleSquish` reports `Length > 0`; a failed or slow probe, or a track that never plays, keeps every slime on the procedural motion. `false`: rigged slimes are driven in code by `ui/SlimeMotor` (squish, wobble, sway, look on the FaceRoot / SkinRoot Motor6D `Transform`; no hops, §37), same LOD (nearest 16 within 80 studs, on screen). Client-only; nothing replicates.
  - `Parade`: the goo parade replaces the plain wild despawn. A fresh wild rides the fountain slide onto the head of a goo lane (`Shared.ParadeLane.WAYPOINTS`, laid on the plaza as `Map.Plaza.ParadeLane` by `server/ParadeView`). The drawn lane starts exactly at the slide mouth (`ParadeLane.MOUTH` = the end of `WorldLayout.SLIDE_PATH`) and leads out to `ENTRY` through a gap in `Plaza.LandingRing` (seven of its 18 tiles are left out, yaw 320..80, where the slide's last stretch runs and the lane leaves); the strips are mitred, flush and opaque (`ParadeLane.strips`, tests/SlimePath.spec). Slime ride physics and the walk are unchanged that loops counter-clockwise round the plaza from just past the goo drain (+Z), dipping inside the hub SpawnLocation and the leaderboard podiums / signpost, and ends at the drain. Its spot is time left: `progress = 1 - (expiresAt - now) / lifetime`; it rides the slide for `RIDE_SECONDS`, glides along the lane linearly in time left (no hop, heading eased through the bends), and in the last `DRAIN_SECONDS` climbs over the drain curb and sinks. The server removes it at `expiresAt` as before and emits World event `Drained` (`slimeId`), which plays a goo splash at the drain. Lane slimes stay grabbable / buyable (same `Grab` / `Buy $` prompt; `Carry.grab`); a grabbed slime leaves the lane at once, and a dropped one walks back to the nearest point of the lane and rejoins the flow with its lifetime kept (§37, [slime-walk.md](contract/slime-walk.md)). `wild.angle` / `wild.radius` keep the `Fountain.roll` values (`radius` sets the slime's sideways offset on the lane). Spawn cadence, cap and lifetimes don't change. The ring warning is the `DespawnTelegraph` window (`"leaving! N"`), which opens while the slime is still walking beside the drain. With the flag off, wilds land in the `Fountain.MIN_RADIUS..MAX_RADIUS` band (`Volcano` is a thin alias) as before.
  - `Habitats` (`HABITATS.md`): a pad whose slime rests on it gets that slime's habitat overlay on the unchanged pad (`Shared.Habitats.forSlime`: type, then tier family, else `base`); empty / stolen / escaping = `base`. Server state in `HabitatPads` (never saved), written as the `Pad_<j>` attributes below; `VisualsClient.HabitatFx` tweens a local overlay on the crate deck in `workspace.ClientHabitats` over 1 s, cloned from the server's MeshPart templates in `ReplicatedStorage.HabitatMeshes`. Flag off = no attributes, no parts.
- **Out of MVP scope:** sticky floor / bouncer upgrades, Robux products. (Fountain tiers and the 3-slime vat came later: §19, §21.)

## 3. Remotes

Every remote lives in the `ReplicatedStorage.Remotes` folder, which the server creates with `Remotes.setup()`. Clients get a remote with `Remotes.get(name)`. Times are **server time** (`workspace:GetServerTimeNow()`).

| Name | Class | Direction | Payload |
|---|---|---|---|
| `Request` | RemoteFunction | client → server | `InvokeServer(action: Action, ...args)` → `RequestResult = { ok: boolean, message: string? }` |
| `State` | RemoteEvent | server → client | `FireClient(player, state: Types.State)` (§5) |
| `Notify` | RemoteEvent | server → client | `FireClient(player, text: string, kind: "info" \| "good" \| "bad", sound: string?, itemId: string?)`. `itemId` (optional) is the UI ItemIcons registry id the toast is about (`"SpeedCoil"`, `"Upgrade_Luck"`, `"PlotSkin_candy"`); absent/unknown ids fall back to the client text heuristic. Global toasts (Slime Rain) use `FireAllClients`. **Oct 18 (B6, Merijn): the client draws no toast any more; a Notify only plays its `sound`.** The server side is unchanged. |
| `Leaderboard` | RemoteEvent | server → client | `FireClient/FireAllClients(board: { stat: "TotalEarned", entries: { { rank: number, userId: number, name: string, value: number } } })` |

`Request` actions (from `Remotes.ACTIONS`; rate limits in `Validate.ACTIONS`):

| Action | Args | Effect / `message` on failure |
|---|---|---|
| `"Merge"` | `slimeIdA: string, slimeIdB: string` | Merges two owned, not-busy slimes of the same tier. |
| `"Merge3"` | `slimeIdA: string, slimeIdB: string, slimeIdC: string` | `FEATURES.MergeVat3`: three owned, not-busy, not-kept slimes of one rarity become one of a higher rarity (§21). |
| `"AutoMerge"` | `tierMask: number` | `FEATURES.MergeVat3`: merges every group of three the server's `MergePlan` finds in the chosen rarities (bit `t - 1` = rarity `t`), lowest income first, never the favourite or kept slimes (§21.1). `"nothing to merge"` when there is none. |
| `"KeepSlime"` | `slimeId: string, keep: boolean` | Marks an owned slime as kept (never merged) or clears it (§21.1). |
| `"Lock"` | none | Buys or extends the plot lock. Costs `Economy.lockCost(income)`. |
| `"Rebirth"` | none | Rebirths if `Progression.canRebirth`. |
| `"Sell"` | `slimeId: string` | Sells for `Economy.sellPrice`. |
| `"Favorite"` | `slimeId: string?` | Sets the rebirth keeper. `nil` clears it. |
| `"BuyPad"` | none | Unlocks the next pad (`Economy.padCost`). |
| `"MoveSlime"` | `slimeId: string, pad: number` | `FEATURES.MoveSlime`: moves that owned, not-busy slime to `pad` (an unlocked pad, `1..padsUnlocked`, a whole number). If another slime sits there, the two swap pads; that slime must not be busy either. Moving to its own pad is a no-op. Fails with `"moving slimes is off"`, `"not your slime"`, `"pad is locked"`, `"slime is busy"`. Only `slime.pad` changes (no save change); the slime models re-place on the next world refresh. |
| `"Daily"` | none | Claims the daily reward (`Progression.claimDaily`). |
| `"ClaimQuest"` | `slot: number` | Claims daily quest `slot` (1..`DAILY_QUESTS.count`) once finished (`Quests.claim`): cash x rebirth multiplier or an income boost. `State.dailyQuests` has the 3 quests rolled per UTC day (progress = gained since the roll, saved as `quests`; missing = nothing rolled). |
| `"BuySpeedCoil"` | none | Buys the Speed Coil once for `SPEED_COIL_PRICE`. While you're not carrying, WalkSpeed is `SPEED_COIL_WALK_SPEED` instead of `BASE_WALK_SPEED`. Saved and kept on rebirth. An **item**, not an upgrade (Item Shop row, §27.1; a `SpeedCoil` Tool in the Backpack, hotbar slot, inventory panel). |
| `"BuyConsumable"` | `itemId: string, slimeId: string?` | `FEATURES.Consumables`. Buys one Luck Potion / Weather Totem: checks the restock allowance, cash and the held cap (`CONSUMABLE_HELD_MAX`), then **adds one to the held stack** (`data.consumables.held`). Nothing is applied on purchase; `slimeId` is ignored. See [restocking-shop.md](contract/restocking-shop.md). |
| `"UseConsumable"` | `itemId: string, slimeId: string?` | `FEATURES.Consumables`. Uses one held consumable: the server checks the item and that the stack is at least 1, runs the effect (spray onto the owned idle `slimeId`, luck potion, weather totem) and only then takes one off the stack. A refused effect keeps the stack. Rate limit 0.5 s. |
| `"Drop"` | none | Drops what you're carrying. Wild → falls to the ground; stolen → escapes home. |
| `"SetHotbar"` | `order: string` | Saves the player's hotbar order (`Shared.HotbarOrder`): up to 9 slot keys joined by `","`, slot 1 first; fewer parts = the rest empty, `""` = an empty slot. A key is the client's inventory entry key: `tool:<ToolName>`, `pvp:<Config.PVP_TOOLS id>` or `consumable:<Config.CONSUMABLES id>`, id up to 32 chars of ASCII letters, digits, space, `_ - . '` (no leading / trailing space). A `pvp:` / `consumable:` id must be a catalog id; a Tool name is free-form, but a Tool whose name has any other character (non-ASCII included) can't be placed on the bar. Example: `"tool:Bat,pvp:KnockGlove1,,consumable:LuckPotion"`. Refused with `"bad argument"`: not a string, longer than 400 chars, more than 9 parts, a malformed key, an unknown pvp / consumable id or the same key twice. Ownership is not checked (the client skips keys it doesn't hold). Stored as `hotbar` in the save (9 strings, no version bump) and sent back as `State.hotbar`; a stored key that is no longer legal loads as an empty slot. An all-empty order is stored as 9 `""`. Rate limit 0.3 s per player; a faster one answers `"too fast"` (the client sends the order again after the gap). |
| `"Sync"` | none | The server re-sends `State` right away. The UI calls it once on start. At most one per `STATE_MIN_INTERVAL` (0.25 s); a faster one answers `"too fast"`. |

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
	pad: number?,        -- home pad 1..PADS_MAX on the owner's plot; nil while wild/carried
	species: string?,    -- SlimeRoster id (v28+); nil on older and merged slimes
	growth: number?,     -- 0..1 (FEATURES.GrowingSlimes); nil = 0, old saves load unchanged
}
```

**Roster (v28):** wild slimes roll their tier exactly as before, then pick a species of that tier from `SlimeRoster` (uniform within the tier); `name` is the species display name. Saved slimes keep their stored `name`; `species` is optional and an unknown id is dropped on load. Secret species (tier 7) spawn like any other tier. The roster is the slime pool (§30).

**Growth (FEATURES.GrowingSlimes, `Shared.Growth`):** a pad slime's `growth` rises by `dt / GROWTH_SECONDS` (Income.step, carried slimes skip); on join `(now - lastOnline)` capped at `GROWTH_OFFLINE_CAP_SECONDS` counts too. `Genome.baseIncome` x `1 + GROWTH_MAX_INCOME_BONUS * growth` (so sell price too). Saved as optional `growth` per slime (rounded to 4 decimals); missing = 0, `SAVE_VERSION` stays 3. The server scales the model by `Growth.scale` and sets the model attribute `Growth`; the pad sign shows its growth bar (§38).

**Return value:** a new, **unparented** `Model`:
- **Name:** `Slime_<id>`.
- **PrimaryPart:** `Body`. A part with diameter `SLIME_BASE_DIAMETER × size`.
- **Physics:** `Body.Anchored = true`. Every part is Massless with `CanCollide = false`. Decoration parts are welded to `Body`, and `Body.CanQuery = true`.
- **Pivot:** the bottom centre. `Body.PivotOffset` points at the bottom of the ball (and `WorldPivot` matches), so `model:PivotTo(padTop)` sits the slime on the pad. The server places pad slimes with `model:PivotTo(pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0))` and wild slimes with `PivotTo` a ground-level CFrame; it never offsets by the slime's radius.
- **Attributes set by the factory:** `SlimeId: string`, `Tier: number`, `Size: number`.
- **Tag:** `Constants.SLIME_TAG` (`"Slime"`).

**Guarantees:**
- It's a pure function of `slimeData`. It doesn't yield, adds no scripts, and works on server and client (ViewportFrames).
- Pattern, eyes and mouth must be visibly different from each other.

**The server (Phoenix) owns everything after `build`:**
- Parenting: wild slimes go to `workspace.WildSlimes`; pad slimes go to their plot's `Slimes` folder.
- Attributes `OwnerUserId: number` (0 = wild), `State: "Wild" | "Pad" | "Carried" | "Escaping"`, and `Price: number` (wild only).
- The ProximityPrompt.
- Unanchoring and welding the model to the carrier's character.

**Mesh look (server-side wrapper, `src/server/SlimeMesh.luau`):** at server start the server loads Jolt's slime mesh package (`Config.SLIME_MESH_ASSET_ID` = 103340234939607) once with `InsertService:LoadAsset` inside a `pcall`, and keeps its first `MeshPart` as a template. Every slime is still built by `ModelFactory.build` (so the contract above is unchanged); with a template the server then adds a welded, non-colliding `MeshPart` named `Mesh`, sized to `Body`'s box and given `Body`'s colour and material (genome colours stay), and makes `Body` transparent. `Body` stays the PrimaryPart, prompt parent and raycast target; rims, crowns, eyes, mouth and pattern stay. If the asset can't be loaded (no access, no MeshPart) or dressing a slime fails, the server warns once and uses the procedural look. `workspace.SlimeLook` (§5.2) says which one is active.

## 5. UI state: `State` payload and world attributes

### 5.1 `Types.State` (full snapshot)

**When it's sent:**
1. Once the player's data has loaded.
2. On every `Request("Sync")`.
3. After any change to that player's state: an action, income tick, steal, escape, rebirth, Slime Rain start/end, or lock expiry. Changes are coalesced to at most one push per `STATE_MIN_INTERVAL` (0.25 s). That includes `Sync`, which is limited to one per `STATE_MIN_INTERVAL`. The server flushes due pushes on every Heartbeat tick (0.1 s) and right after each `Request` that got past the guards (a call refused as unknown, still loading, bad argument or too fast does no world refresh and no flush).
4. At least once a second while income is above 0.

The client always replaces its copy and never diffs.

```luau
{
	serverTime: number, plotIndex: number,
	cash: number, incomePerSec: number,
	rebirths: number, rebirthMultiplier: number, rebirthCost: number, canRebirth: boolean,
	rebirthSlimes: { { id: string, name: string, tier: number, color: { number }, owned: boolean } }, -- §8.8a, empty at max
	padsUnlocked: number, padsMax: number, nextPadCost: number?,
	slimes: { { slime: SlimeData, income: number, sellPrice: number, stolenBy: number? } },
	favoriteId: string?,
	lockUntil: number, lockCost: number, lockDuration: number,
	carrying: { slime: SlimeData, kind: "wild" | "stolen", ownerUserId: number?,
	            startedAt: number, walkSpeed: number }?,
	rain: { active: boolean, endsAt: number?, nextAt: number? },
	dex: DexView,                               -- species Dex (§36.4)
	daily: { available: boolean, streak: number, amount: number, day: number },
	shop: {
		SpeedCoil: { price: number?, owned: boolean },                      -- price nil = owned
	},
	egg: { hatched: { slime: SlimeData, at: number }? },  -- newest Mystery Egg hatch, never saved
	tutorialStep: number?,   -- 1..6 (§2 Tutorial); nil = finished
	hotbar: { string }?,     -- saved hotbar order: exactly 9 slot keys ("" = empty), nil until the player first sends SetHotbar
}
```

- `daily.day` is the streak day the pending claim pays (1..`DAILY_STREAK_CAP`, `amount = DAILY_BASE × day × rebirthMultiplier`). When nothing is pending, it's the day the last claim paid.
- `egg.hatched` is the newest Mystery Egg the player hatched (`HatchEgg`, [mystery-egg.md](contract/mystery-egg.md)). The HUD shows no banner for it.
- `shop` keys are the UI's `ShopCatalog` item ids. Prices are final (what `Request` charges).
- `hotbar` is what the last successful `Request("SetHotbar", order)` stored (§3), saved across sessions and rebirths. Keys may name items the player no longer holds; the client skips those.

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
  - Owner side: `src/ui/SlimeKeys` adds two **client-only** ProximityPrompts on the Body of every slime model whose `OwnerUserId` is the local player and `State` is `"Pad"`: `FavoritePrompt` (R, gamepad DPadUp, tap: "Favorite" / "Unfavorite", sends `Favorite(slimeId)` / `Favorite(nil)`; the favourite's prompt shows `State.petPerk`; none on Mystery Eggs, models with `EggKind`) and `SellPrompt` (X, gamepad DPadDown, hold `HOLD_CONFIRM_SECONDS`: "Sell $price" from `State.slimes[i].sellPrice`, sends `Sell(slimeId)`). Hatch stays the server's `HatchPrompt` (F). E is left free on owned pad slimes. The server never creates or sees these prompts; there is no slime card and no Plot nav button.
  - `FEATURES.MoveSlime`: SlimeKeys also adds `MovePrompt` (E, gamepad ButtonX, tap, "Move") to those slimes. It starts client-only move mode (`src/ui/SlimeMove`): the slime turns see-through for this player, a see-through copy sits on the target pad (the pad under the mouse or tap, else the unlocked pad nearest the character), the pad is tinted green (empty), yellow (swap) or red (locked). Click / tap a pad, E or gamepad ButtonX sends `MoveSlime(slimeId, pad)`; Q, gamepad ButtonB, the Cancel button, leaving the home zone or the slime leaving its pad cancels. Every ProximityPrompt is off for this player while moving.
  - These SlimeKeys prompts use `ProximityPromptStyle.Custom`: `src/ui/SlimeKeyCard` draws one card over the slime (its name, the favourite's perk, one row per shown prompt with its key, a fill while a hold prompt is held) instead of Roblox's stacked bubbles. A click or tap on a row holds that prompt.
- **Player:** `Carrying: string?` (`Constants.CARRYING_ATTRIBUTE`). The carried slime's id, set on pickup (grab or steal). Cleared (nil) on drop, deposit, a failed steal (slap escape; the owner leaving), death / respawn and leave. A full plot doesn't clear it: the slime stays in your arms. The server derives it from `Carry.carryingId` after every action and every tick.
- **`workspace`:**
  - `SlimeRain: boolean` (`Constants.RAIN_ATTRIBUTE`): `true` during Slime Rain, `false` otherwise (set at server start). VisualsClient keys its rain particles off it.
  - `DataStoreStatus: string` (`Constants.DATASTORE_STATUS_ATTRIBUTE`): `"Ok" | "Memory" | "Unavailable" | "Error"`, see §2 Persistence.
  - `WorldMeshesReady: boolean` (`Constants.WORLD_MESHES_READY_ATTRIBUTE`): `true` once MeshSwap has dressed `Map` / `Plots` and the merge vats (or given up on the meshes that failed). The client's loading screen (ReplicatedFirst) holds until it is set, up to a timeout.
  - `SlimeLook: string` (`Constants.SLIME_LOOK_ATTRIBUTE`): `"Mesh"` if the slime mesh asset loaded at server start, `"Procedural"` if the server fell back to ModelFactory's look (see §4).
  - `RainActive: boolean` (same value as `SlimeRain`), `RainEndsAt: number?` and `RainNextAt: number?` (server time) for the HUD countdowns. Names: `Constants.RAIN_ACTIVE_ATTRIBUTE`, `RAIN_ENDS_AT_ATTRIBUTE`, `RAIN_NEXT_AT_ATTRIBUTE`.
- **Player (more):**
  - `TutorialStep: number?` (`Constants.TUTORIAL_STEP_ATTRIBUTE`): same as `State.tutorialStep`, so VisualsClient can draw the tutorial arrow without remotes (targets: 1 → `Map.Volcano.Crater`, 2 → own plot `HomeZone`, 3 → own `LockButton`, 4 → own `MergeVat`, 5 → another owned plot's `Base`, 6 → none). nil = finished or not loaded.
  - `SpeedCoil: boolean?` (`Constants.SPEED_COIL_ATTRIBUTE`): `true` once the Speed Coil is owned (for a cosmetic coil on the character).
  - `PetSlimeId: string?` (`Constants.PET_ATTRIBUTE`): the slime that follows the player (FollowPets, §2 Extras).

### 5.3 World (built by Archer's WorldBuilder, wired by Phoenix)

**The world is static in the place file.** `lune run scripts/gen-world` runs `WorldBuilder.build` under Lune and writes `world/Map.rbxmx`, `world/Plots.rbxmx` and `world/HubSpawn.rbxmx` (an anchored, neutral `SpawnLocation` on the Ground between the Plot_2 / Plot_3 paths). `default.project.json` puts them under Workspace, so floor, plots and spawn exist before any character loads. **Rerun `gen-world` after changing WorldLayout / WorldBuilder** and commit the `.rbxmx` files; `tests/StaticWorld.spec.luau` fails if they're stale.

On start the server still calls `ReplicatedStorage.Visuals.WorldBuilder.build(workspace)` first, before anything that yields (idempotent: it reuses the static pieces and never clobbers slimes or plot attributes). If that module is missing or fails and `workspace.Plots` doesn't exist, `src/server/FallbackWorld` builds a greybox with the same names and attributes.

**Void safety:** every Workspace BasePart except slimes is Anchored. `Workspace.FallenPartsDestroyHeight = -1000` (set in `default.project.json`; scripts can't write it). Every frame the server puts any living character whose root is below `Rescue.KILL_PLANE_Y` (-60) back on its plot's Base (or HubSpawn before a plot is assigned) and zeroes its velocity. `lune run scripts/check-place <file>` checks a built place (also run by `tests/StaticWorld.spec.luau`).

The server finds plots by the `PlotIndex` attribute and pads by `PadIndex` (`Constants.PLOT_INDEX_ATTRIBUTE` / `PAD_INDEX_ATTRIBUTE`, via `PlotLookup`). The `Plot_<i>` / `Pad_<j>` names are only a fallback. Folder names are in `Constants`: `MAP_FOLDER = "Map"`, `PLOTS_FOLDER = "Plots"`, `PLOT_SLIMES_FOLDER = "Slimes"`, `HOME_ZONE = "HomeZone"`. `WorldLayout` hardcodes `"Map"` and `"Slimes"`, and `tests/Integration.spec.luau` checks they match.

- **Border terrain** (`server/BorderTerrainView.place`, spawned from the server script, never blocks boot): the hills behind the world border are voxel Terrain written in 64-stud chunks (`BorderTerrain.chunks`, nearest the play area first) with at most `FRAME_BUDGET_S` = 3 ms of work per frame. Readiness: Terrain attribute `BorderTerrain` (false while writing, true when done) and Workspace attribute `BorderTerrainReady` (false when writing starts, true when done; nil before `place()` runs). Tests and the pc-watcher wait on these.
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

`Effects.play(kind, target: Vector3 | CFrame | BasePart): Instance?` with `kind` in `Effects.KINDS` = `"Collect" | "Steal" | "Merge" | "Rebirth"`. The server queues `{ type = "Effect", kind, userId?, slimeId?, plotIndex? }` in `world.outbox` and `server/Outbox` plays it through `EffectsView` (safeCall'd; never breaks gameplay):

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
| `RARITIES[i].carrySlow` (max `MAX_CARRY_SLOW`) | 0.05…0.35 (≤0.6) | "slows the carrier more the rarer it is" |
| `RARITIES[i].income` | 1, 3, 9, 27, 80, 250 | income = rarity × size × growth |
| `RAIN_INTERVAL` / `RAIN_DURATION` / `RAIN_LUCK` | 3600 / 180 / 5 | "every hour … for 3 minutes" |
| `PADS_START` / `PADS_MAX` / `PLOT_COUNT` | 4 / 8 / 8 | MVP "8 pads" |
| `OFFLINE_RATE` / `OFFLINE_CAP_SECONDS` | 0.5 / 7200 | capped offline income |
| `REBIRTH_BASE_COST` / `REBIRTH_COST_GROWTH` / `REBIRTH_MULTIPLIER_STEP` | see `Config` | rebirth gives a multiplier, keeps one favourite (§8.8) |
| `SPAWN_INTERVAL` / `MAX_WILD_SLIMES` / `FREE_DROP_CHANCE` / `WILD_PRICE_SECONDS` | 4 / 18 / 0.25 / 20 | "buy cheap ones … or grab a free drop" |
| `STATE_MIN_INTERVAL` / `LEADERBOARD_INTERVAL` | 0.25 / 60 | §5.1, §2 |

| `SPEED_COIL_PRICE` / `SPEED_COIL_WALK_SPEED` | 1 500 / 22 | shop: speed coil |
| `RAIN_WARNING_SECONDS` | 60 | rain heads-up toast |
| `FEATURES` | every flag and its value live in `Config.FEATURES` only; not restated here | §2 Extras |
| `BOSS` | table | boss event (§33) |
| `DAY_LENGTH` / `DAY_FRACTION` | 720 / 0.7 | day / night |
| `PITY_EPIC` / `PITY_LEGENDARY` / `RARE_ANNOUNCE_TIER` | 30 / 300 / 5 | v13 rarity (§8.7) |
| `REBIRTH_LATE_FROM` / `REBIRTH_COST_GROWTH_LATE` / `REBIRTH_TIERS` / `UPGRADES` / `GOALS` / `DEX_MILESTONES` | 5 / 2 / tables | v13 progression (§8.8) |
| `SAVE_VERSION` | 7 | v13 schema (§8.9), v6 = `settings` + versioned `plotSkin` / `stealLog` (§8.9c), v7 = mutation fields stripped (§8.9d) |

All names (remotes, folders, tag, DataStores, the `DataStoreMode` / `DataStoreStatus` / `WorldMeshesReady` / `SlimeLook` / `Carrying` / `SlimeRain` / `RainActive` / `RainEndsAt` / `RainNextAt` / `TutorialStep` / `SpeedCoil` / `PetSlimeId` / `Boss` / `PlotIndex` / `PadIndex` attributes, `ShopStand` / `LeaderboardBoard` / `TutorialNpc` / `SpeedCoil` tool) are in `Constants.luau`.

## 7. Build and tests

The toolchain is pinned in `rokit.toml` (rojo 7.7.1, lune 0.11.0, selene 0.32.0, stylua 2.6.0, wally 0.3.2, luau-lsp 1.70.1). The approach matches `speed-escape-skeleton`. Run everything from `games/steal-a-slime`:

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

CI: `.github/workflows/pr-checks.yml` runs these plus `rojo build`, `scripts/check-place` and `lune run scripts/test-flags` (all flags on / all off) on every PR that touches this game; `.github/workflows/cheap-gates.yml` runs the Lune tests and the static UI layout check on pushes to `main`.

## Feature contracts (index)

Section numbers are kept, so references such as "CONTRACT.md §26.1" now mean `contract/pvp.md` §26.1. There is no §10 (it was never written; budgets cite THEME.md).

| Section | File | Topic |
| --- | --- | --- |
| §8 | [v13-additions.md](contract/v13-additions.md) | v13 additions (2026-10-15, Phoenix) |
| §9 | [v16-additions.md](contract/v16-additions.md) | v16 additions (2026-10-15, Phoenix) |
| §11 | [friend-income-bonus.md](contract/friend-income-bonus.md) | v29 #4: friend income bonus (2026-10-16, Jolt) |
| §12 | [admin-events.md](contract/admin-events.md) | v29 #10: live admin events (2026-10-16, Jolt) |
| §13 | [coop-ritual.md](contract/coop-ritual.md) | v29 #12: co-op ritual circle (2026-10-16, Jolt) |
| §14 | [follow-pet-passives.md](contract/follow-pet-passives.md) | v29 #14: follow-pet passives (2026-10-16, Jolt) |
| §15 | [plot-skins.md](contract/plot-skins.md) | Gaps #15: plot skins unlocked by collection (2026-10-16, Archer) |
| §16 | [revenge-steal.md](contract/revenge-steal.md) | Revenge steal (`FEATURES.Revenge`) |
| §17 | [steal-alerts.md](contract/steal-alerts.md) | v21: full steal alerts (2026-10-16) |
| §18 | [weekly-event-rotation.md](contract/weekly-event-rotation.md) | v21: weekly event rotation (2026-10-16) |
| §19 | [fountain-tiers.md](contract/fountain-tiers.md) | v19: fountain tiers + slime families per rank (`FEATURES.FountainTiers`) |
| §21 | [merge-vat3.md](contract/merge-vat3.md) | v19: 3-slime merge vat (`FEATURES.MergeVat3`) |
| §22 | [restocking-shop.md](contract/restocking-shop.md) | v29 #13: restocking consumables shop (2026-10-16) |
| §24 | [welcome-back.md](contract/welcome-back.md) | v20: welcome-back card (2026-10-17) |
| §25 | [server-profiler.md](contract/server-profiler.md) | v23: server performance profiler (`FEATURES.ServerProfiler`) |
| §26 | [pvp.md](contract/pvp.md) | PvP: rules, gloves, traps, blasters, fun items (`FEATURES.PvP`) |
| §27 | [world-shops.md](contract/world-shops.md) | World shops: Item Shop and Upgrade Shop (`FEATURES.WorldShops`) |
| §28 | [fountain-split.md](contract/fountain-split.md) | Fountain split: PCD tower pieces (`FEATURES.FountainSplit`) |
| §29 | [inventory.md](contract/inventory.md) | S3: inventory hotbar + panel (client only, 2026-10-18) |
| §30 | [slime-pool.md](contract/slime-pool.md) | Slime pool: 32 species, one fully coloured mesh each |
| §31 | [slime-bones.md](contract/slime-bones.md) | Slime bones: species meshes driven on the client (Bone.Transform) |
| §32 | [slime-odds.md](contract/slime-odds.md) | Slime odds: rarity weights, family drop rule, Mythic / Secret presentation |
| §33 | [boss-event.md](contract/boss-event.md) | Boss event: team meter fight, haul race, unstealable trophy |
| §34 | [event-secrets.md](contract/event-secrets.md) | Event Secrets: one featured Secret per week joins the Secret pool |
| §35 | [merge-recipes.md](contract/merge-recipes.md) | Merge recipes, merge caps and the merge assist |
| §36 | [species-dex.md](contract/species-dex.md) | Species Dex: 50 species and the milestone ladder |
| §37 | [slime-walk.md](contract/slime-walk.md) | Slime walk: wild slimes glide the lane and walk back to it when dropped |
| §38 | [slime-labels.md](contract/slime-labels.md) | Slime labels: a tag above every loose slime, a sign on every pad |
| §39 | [slime-life.md](contract/slime-life.md) | Slime life: species gaits, hops, lane beats and reactions |
| §40 | [mystery-egg.md](contract/mystery-egg.md) | Mystery Eggs: wild eggs that incubate on a pad, can be stolen, hatch into a slime (`FEATURES.MysteryEggs`) |
