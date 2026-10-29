# 50. Admin menu: cheats on a test save, admin tools for admins (2026-10-29)

**Status:** step 1 of the plan Merijn approved (proposal page `docs/admin-menu-proposal.html`). No feature flag: the
admin check is the gate. Later steps: the sandbox save (cheats on a real server, walled off from real players), the
Players and Debug tabs.

## 1. Who gets what

`AdminService.view(world, userId)` decides, from `world.admin` (set once at boot by `AdminService.setup`):

| Server | Who has the menu | Cheats | Admin tools |
|---|---|---|---|
| Test save (`workspace.DataStoreMode = "Memory"`, so `TestHooks.enable` succeeded) | everyone in it | yes | yes |
| Real saves | the place owner (`game.CreatorId` for a user-owned place) and `Config.ADMIN_USER_IDS` (`AdminEvents.isAdmin`) | no | yes |
| Real saves | everyone else | no menu, no `State.admin`, every `Admin` request refused | |

`world.admin = { creatorId: number?, cheats: boolean }` (plain data, `World.AdminConfig`); nil = no admin service
(Lune worlds that never call `setup`), which refuses every command.

## 2. Request

`Admin(command: string, text: string?, amount: number?)`, rate limit 0.25 s (`Validate.ACTIONS.Admin`). `command`
is an `AdminCommands` id; `text` an id (Validate.slimeId), `amount` a finite number the command clamps. Refusals:
`"not an admin"` (no menu for this player), `"cheats only work on a test save"`, `"unknown command"`, plus each
command's own reason. Never errors. The result's `message` is a short line the panel shows.

## 3. Commands (`src/shared/AdminCommands.luau`, the one list)

Each entry: `{ id, tab, level, label }`; `level` is `"cheat"` (test save only, runs through `TestHooks`) or `"admin"`
(any server, for admins). `AdminCommands.clamp(id, amount)` bounds the number.

| Tab | id | Level | Args | Effect |
|---|---|---|---|---|
| Me | `cashAdd` | cheat | amount 1..1e15 | `TestHooks.grantCash` (not counted as earned) |
| Me | `cashSet` | cheat | amount 0..1e15 | `TestHooks.setCash` |
| Me | `skipTime` | cheat | seconds 1..86400 | `TestHooks.skipTime` (income and lock timers for everyone on the server) |
| Me | `setRebirths` | cheat | 0..`MAX_REBIRTHS` | `TestHooks.setRebirths` |
| Me | `setPads` | cheat | 1..`PADS_MAX` | `TestHooks.setPads` |
| Me | `setGrowth` | cheat | percent 0..100 | `TestHooks.setGrowth`: every pad slime's growth |
| Me | `fillDex` | cheat | none | `TestHooks.fillDex`: every SlimeDex species found |
| Me | `skipTutorial` | cheat | none | `TutorialService.skip` |
| Me | `resetSave` | cheat | none | `TestHooks.resetSave`: the save becomes a new player's; refused while carrying or while one of your slimes is busy |
| Me | `goHome` / `goHub` | admin | none | moves your character home (`ctx.dropDown`) or onto the hub spawn (`ctx.toHub`) |
| Items | `grantProduct` | cheat | text = any `EXCLUSIVE_SHOP.products` key but `Gift_*` (cosmetics, bundles, boosts, quick-buys; seasonal ones on any date) | `TestHooks.grantProduct` → `Purchases.grant` (same grant as a receipt, no receipt id; a boost that can't start becomes a credit) |
| Items | `grantCosmetics` | cheat | none | every cosmetic product (`TestHooks.COSMETIC_KINDS`: seats, base skins and bases, lock styles, trails, fanfares, hats, Bat skins) |
| Items | `setPass` | cheat | text = an `EXCLUSIVE_SHOP.passes` key, amount 1 on / 0 off | `TestHooks.setPass` → `Purchases.applyPasses` (this session; a rejoin asks Roblox again) |
| Items | `setSubscription` | cheat | text = an `EXCLUSIVE_SHOP.subscriptions` key, amount 1 / 0 | `TestHooks.setSubscription` → `Purchases.applySubscriptions` (today's Club credits) |
| Items | `setPaidRandom` | cheat | amount 1 allowed / 0 restricted | `TestHooks.setPaidRandom`: the PolicyService answer for this session (hides the potion, Slime Rain, totem, Lucky Charm+) |
| Items | `unlockSkins` | cheat | none | `TestHooks.unlockSkins`: marks each plot skin's slimes found, so every skin unlocks |
| Items | `unlockSeats` | cheat | none | `TestHooks.unlockSeats`: meets the free seats' goals (merges, Dex share) |
| Items | `giveConsumable` | cheat | text = `CONSUMABLES` id, amount 1..`CONSUMABLE_HELD_MAX` | adds to `consumables.held`, up to the cap |
| Spawn | `spawnSlime` | cheat | text = species id (optional), amount = tier 1..`MAX_TIER` | `TestHooks.spawnSlime` onto your first free pad; a species id sets its tier |
| Spawn | `hatchEggs` | cheat | none | `TestHooks.hatchEggs`: your incubating pad eggs are ready now |
| Spawn | `spawnWave` | admin | amount 1..20 | `Spawner.spawnBonus` at normal luck |
| Spawn | `dropEgg` | admin | none | `Spawner.spawnEgg` (needs `FEATURES.MysteryEggs`) |
| World | `luckEvent` | admin | minutes | `AdminEventsService.trigger` "luck" (all servers, same as `/event luck`) |
| World | `slimeRain` | admin | none | `AdminEventsService.trigger` "rain" |
| World | `nextWeather` | admin | text = weather id | `ctx.requestWeather` (needs `FEATURES.Weather`) |
| World | `startBoss` | admin | none | the next boss warning starts now (`world.nextBossAt`); refused while one runs |

## 4. State

`State.admin: { cheats: boolean }?` (`Types.AdminView`), only for players the table in §1 gives the menu. The client
builds the rows from `AdminCommands.LIST` itself; `AdminCommands.lockedReason(command, cheats)` says why a row can't
run here.

## 5. Client

`ui/AdminMenu.start` builds the `Admin` panel (`Panels/Admin`) the first time a State carries `admin`, registers it
as a menu card, and binds F2 to toggle it. Non-admins never build it (no instances, no input binding). Tabs Me,
Items, Spawn, World; rows from `AdminCommands.LIST`; each button sends `Admin` and shows the reply line. A locked row is a sunken well with its
reason (`Widgets.status`). `resetSave` is a hold button.

## 6. Safety

- Every cheat is a `TestHooks` function and keeps its guard: `TestHooks.enable` still refuses unless
  `DataStoreMode == "Memory"`. `AdminService` is the one `src/` file allowed to reference `TestHooks`
  (`tests/TestHooks.spec`, §8.12).
- `tests/AdminService.spec` checks: non-admins refused on a real server, cheats refused on a real server even for
  the owner, everyone allowed on a test save, bad text and numbers refused or clamped.

Studio only: SlimeUI `PcwOpen` = "Admin:<Tab>" opens the admin menu on that tab (once State made the player an admin).
