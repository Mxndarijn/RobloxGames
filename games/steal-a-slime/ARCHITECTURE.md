# Steal a Slime: how to write code here

This is the code-structure guide for agents and people working in `games/steal-a-slime`. It describes the patterns the code already uses, so new work fits in instead of reinventing them. `CONTRACT.md` holds the shared names (remotes, State fields, attributes, ownership); `src/shared/Config.luau` holds every tunable value and feature flag. When this file and the code disagree, the code wins: fix this file in the same PR.

## 1. Layers and data flow

```
client (src/ui, src/visuals/client)          server (src/server)
  calls Request(action, ...)  ───────────►  init.server  ──►  Actions.handle
                                                               parseArgs + Validate.allow
                                                               └► systems (MergeVat, StealService, ...)
                                                                    mutate World, emit into world.outbox
  renders State   ◄── Snapshot.build ◄────  Heartbeat: GameLoop.step(world, now)
  plays Notify    ◄── World.drain(outbox) ◄─            WorldView.reconcile(world, now)  (Scene.describe)
```

| Layer | Where | Rules |
|---|---|---|
| Pure rules | `src/shared/*` | Data and functions only. No Roblox API at load time, so every module runs under Lune. Config, Types, Remotes, Validate, SaveData, Genome, Economy, Steal, ... |
| Live state | `src/server/World.luau` | One table with every piece of live gameplay state: sessions, plots, wild slimes, carries, escapes, clocks. No Roblox APIs. |
| Systems | `src/server/*` (pure ones) | Plain functions over `World`: `Spawner`, `Carry`, `StealService`, `Income`, `MergeVat`, `Rebirth`, `Sessions`, `GameLoop`. Side effects the engine must perform go into `world.outbox` (`World.emit`, `World.notify`, `World.effect`), never straight to Instances. |
| Requests | `src/server/Actions.luau` | The only entry for client intent (see §1.1). |
| Snapshot | `src/server/Snapshot.luau` | Builds `Types.State` for one session; pushes only when `session.dirty`, at most once per `Config.STATE_MIN_INTERVAL`. |
| Roblox adapters | `init.server.luau`, `WorldView`, `WorldProps`, `FallbackWorld`, `DataService`, `*View.luau` | Make workspace match `World` (`Scene.describe` → models, attributes). Hold no gameplay rules. |
| Client | `src/ui` (Jolt), `src/visuals/client` (Archer) | Calls `Request`, renders `State`, reads replicated attributes. Never decides an outcome. |

### 1.1 One remote in, one snapshot out

- `Remotes.ACTIONS` (shared) lists every `Request` action with its argument types. `Validate.ACTIONS` gives each its rate limit in seconds. Both tables must name the same actions (`Sync` is the free exception).
- `Actions.handle(world, userId, action, raw, now, ctx)`: unknown action → `"unknown action"`; no session → `"still loading"`; `Actions.parseArgs` checks types (slime ids through `Validate.slimeId`, vectors finite); `Validate.allow` rate-limits; `dispatch` runs inside `pcall`. A successful result marks the session dirty, which schedules a State push.
- Never error out of a handler. Return `{ ok = false, message = "<reason>" }`.
- `ctx` (`Actions.Context`) carries the adapter's world queries (`distanceBetween`, `positionOf`, `shopAccess`, ...) and optional flag overrides for tests. Actions never reach for `workspace`.
- Server → client channels are `State` (full snapshot), `Notify` (toasts from the outbox), `Leaderboard`, and the flag-gated `PvpEvent` / `ShopEvent`. Don't add a remote for something State or an Instance attribute can carry.

### 1.2 Dual require pattern

Every module that must run in both Roblox and Lune requires like this, and nothing else:

```lua
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")
```

Inside `src/shared` the short form is `if script then require(script.Parent.X) else require("./X")`. Adapters that only run in Roblox (`init.server`, `WorldView`, UI panels) use plain `require(script.Parent.X)` / `require(UI.X)`. `scripts/typecheck.sh` rewrites the pattern for luau-lsp, so keep it on one line in exactly this shape.

## 2. Module templates

### 2.1 Pure server system

```lua
--!strict
--[[
	Thing (pure)

	What it owns and which World fields it reads / writes. One paragraph, present tense.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")

local Thing = {}

-- Returns ok + a player-facing reason; never errors.
function Thing.buy(world: World.World, session: World.Session, now: number): (boolean, string?)
	...
	World.notify(world, session.userId, "Bought!", "good")
	return true
end

return Thing
```

- State lives in `World` (or in a `State` table the caller owns), never in module-level locals.
- Time comes in as `now`, randomness as an `Rng` or a `roll: () -> number`. No `os.clock()` / `math.random()` inside rules, so tests are deterministic.

### 2.2 Timed service

A service with its own clock follows `WeatherService`: `new(t0) -> State`, `step(state, t, roll) -> changed`, a `publish(state, holder)` that writes attributes, and a `start(...)` that only loops and calls `step` / `publish`. The pure part is tested by stepping it; `start` holds no logic.

### 2.3 Dependencies: one pattern (`ctx`)

Pass what a module needs from the engine as a `ctx` / `Context` table argument (see `Actions.Context`). Tests pass a fake table. `init.server` builds one `ctx` and hands it to `Actions`, the PvP lines (`PvpService.Context`: positions, plot checks, `launch`, `pose`), `BatTool.swing` and `WorldView.updatePlayer`. Feature-flag overrides for tests go in one table, `ctx.features` (`{ PvP = false }`); `Actions.feature(ctx, name)` reads it and falls back to `Config.FEATURES`. Events for clients go into `world.outbox` (`World.emit`; PvP uses type `"PvpEvent"`), never through a module-level sink. No module-level setters (`setEnv`, `setSink`, ...).

### 2.4 Client runtime module

```lua
-- Starts listening / animating. Returns a stop function that disconnects everything it made.
function Fx.start(opts: Options): () -> ()
	local conns = {}
	...
	return function()
		for _, c in conns do c:Disconnect() end
	end
end
```

`ui/PromptHide.start` is the reference. Per-frame work goes through the client's one frame loop (the `tick` calls at the end of `init.client.luau`), culls by distance and skips what is off screen; don't add another `RenderStepped` / `Heartbeat` connection for a new effect.

### 2.5 UI panel

```lua
local UI = script.Parent.Parent
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)
local Theme = Widgets.Theme

local Thing = {}

function Thing.new(parent: Instance, ctx: any)
	local panel = Widgets.panel(parent, "ThingPanel", "Thing", "🧪", Theme.Accent)
	local list = Widgets.keyedList(content, keyOf, makeRow, updateRow) -- rows survive State pushes
	local self = { frame = panel.frame, close = panel.close }
	function self.update(state: any) list.sync(state.things) end
	function self.tick(now: number) end -- optional, only for countdowns
	return self
end

return Thing
```

- Built once by `init.client.luau` with `Thing.new(gui, ctx)`; `ctx` gives `send`, `request`, `Config`, `serverNow`, ... Panels never call `Remotes` themselves.
- Open / close only through the client's `setOpen(key)` (`panel.close` is wired to `setOpen(nil)`); `MenuState` decides what is visible.
- Rows: `Widgets.keyedList` (keyed reuse) and `Widgets.restack` / `Layout.stackRows`, not a `UIListLayout` (it doesn't reflow while hidden).
- Colours from `Widgets.Theme`, draw order from `Layout.ZINDEX`, sizes and row heights from `Layout` or a frozen `ROWS` table at the top of the panel. No raw `ZIndex` numbers, and no new `TextSize` / colour literals when a Theme / Layout value exists.

### 2.6 Entry scripts

`init.server.luau` and `init.client.luau` wire modules together: create remotes, build panels, connect signals, run the frame loop. New behaviour goes in a module with a test, and the entry gets one line that calls it. Studio-only review fakes (`force*` helpers, `Pcw*` attributes) belong in a dedicated module, not in the entry script.

## 3. Recipes (each lists the tests it needs)

### 3.1 Add a Request action

1. `CONTRACT.md` §3: name, arguments, effect (commit the contract first if another role consumes it).
2. `src/shared/Remotes.luau` `ACTIONS`: `Name = table.freeze({ args = { "string" } })` with a comment naming the argument.
3. `src/shared/Validate.luau` `ACTIONS`: its rate limit.
4. The rule in a system module (§2.1), returning `(ok, reason)`; one `elseif` in `Actions` `dispatch`.
5. Tests: `tests/Actions.spec.luau` (bad args refused, rate limit, success path through `Actions.handle` with `ServerFixtures`), plus a spec for the system module. `tests/Contract.spec.luau` already checks that `Remotes.ACTIONS` and `Validate.ACTIONS` agree.

### 3.2 Add a State field

1. `CONTRACT.md` §5.1 and `src/shared/Types.luau` `State`.
2. Fill it in `Snapshot.build` from `World` / `session.data`. If it changes without an action, call `World.markDirty(session)` where it changes.
3. Tests: `tests/Snapshot.spec.luau` asserts the field for a built world; a UI spec through `UiHarness` if a panel reads it.

### 3.3 Change the save format

1. Bump `Config.SAVE_VERSION`; add `SaveData.migrateVn` that turns a version-n table into n+1 (so `migrateV5` makes v6), and chain it in `SaveData.migrate`.
2. `serialize` / `deserialize` handle the new field; `deserialize` cleans junk (wrong types, unknown ids) instead of trusting it.
3. Tests: a `tests/SaveMigrationV<n+1>.spec.luau` with a real old-version table, the round trip in `tests/SaveData.spec.luau`. Never rename a saved id; change only its display name.

### 3.4 Add a constant

- Tunable numbers (prices, timers, chances) go in `Config` with a comment saying what the unit is. Names shared by server and client (remotes, attributes, tags, folders) go in `Constants`. World geometry goes in `src/visuals/shared/WorldLayout.luau` (or `Config` for gameplay sizes like `PADS_MAX`), once.
- Never copy a number into a second file. Read it from where it lives; if Lune can't reach that module, move the value to `src/shared`.
- Tests: whichever spec covers the behaviour; `tests/Contract.spec.luau` "Config matches the design" for values the design names.

### 3.5 Add a feature flag

1. `Config.FEATURES.<Name> = false` with one comment: what it does and what `false` means.
2. The rule reads the flag through `ctx`: `Actions.feature(ctx, "<Name>")` (`ctx.features.<Name>` for tests, else `Config.FEATURES.<Name>`).
3. Tests cover both values by passing the override. A flag Config can't pass in runs through `tests/FeatureFlags.spec.luau` (a flipped copy of Config). Note tests that can't run in the all-on / all-off modes of `scripts/test-flags` in `tests/ForcedFlags.luau`.
4. Expiry: one release after the flag goes ON, delete the flag, the `false` branch, its override and its `ForcedFlags` entries. A flag that stays OFF for good gets its code deleted.

## 4. Testing policy

- `lune run tests` runs every `*.spec.luau` under `tests/` (incl. `tests/ui`) with `tests/TestRunner.luau` (`describe`, `it`, `expect`).
- Test behaviour, not text: build state with `tests/Fixtures.luau` (slimes, profiles, roll sequences) and `tests/ServerFixtures.luau` (a `World` with joined players, `notifications`), call the real functions, assert on `World`, `State` or the outbox. UI: load the real panel through `tests/ui/UiHarness.luau`, feed it a State, read Instance properties.
- Source-text asserts (reading a `.luau` file and matching a string) are only for safety guards that can't be checked by running code: TestHooks not referenced from `src/`, no `DataStoreMode` in a place, no DataStore calls in tests. New ones go through one shared helper in `tests/` (add it with the first new guard; the per-spec `read()` copies are existing debt). Don't assert that a comment, a line of layout code or a variable name exists.
- A test that pins a doc (`ITEM-ICONS-NEEDED.md`, a contract file) must say which generator or owner keeps it current.
- A bug fix comes with a test that fails without the fix. The test name says the behaviour, not the bug number or the date.

## 5. Housekeeping

- Comments say what the code does and why, in present tense. No version tags (`v28:`), dates, bug numbers or "was X, now Y" stories in code or comments: git log and the PR hold history.
- When the last caller of a module goes, delete the module and its spec in the same PR.
- Generated files are either gitignored or checked by a spec that fails when they are stale (`tests/StaticWorld.spec.luau` for `world/*.rbxmx`).
- `--!strict` on every new file; `selene src tests`, `stylua --check src tests` and `scripts/typecheck.sh` must stay clean.
