# shared/luau

Game-agnostic Luau systems for every game in this repo. Each system has a pure core that runs under Lune (and is tested there) and, where it needs Roblox, a thin adapter next to it. Rules for adding or changing modules: [CLAUDE.md](CLAUDE.md).

## Modules

| Folder | Module | Kind | What it does |
|---|---|---|---|
| `src/inventory` | `ItemRegistry` | pure | Item catalog: id, name, maxStack, kind, icon, colour, game data |
| | `Inventory` | pure, server | Slots and stacks owned by the server: atomic add / remove, move, split, equip, use, snapshot, save / load with cleanup |
| | `InventoryActions` | pure, server | Validates and applies untrusted client requests (Equip, Move, Split, optional Drop) |
| | `Hotbar` | pure, client | View model: snapshot (+ game extras such as Tools) → entries, press → intent, count / cooldown text |
| | `HotbarLayout` | pure | Bar and grid geometry from overridable metrics |
| | `HotbarView` | adapter, client | Default hotbar + inventory grid UI; theme, metrics, icon and slot renderers can be overridden |
| | `ToolProvider` | adapter, client | Lists / equips Roblox Tools, hides the default backpack, number-key and world-press input |
| `src/core` | `Rng`, `NumberFormat`, `RateLimiter`, `Migrations`, `Signal`, `Spring`, `StepTrack` | pure | Seeded random, number and duration formatting (short, cash, full digits, rate, duration, clock), per-key action limits, versioned save migrations + sanitizers, a small signal, second-order springs for procedural motion, smooth drawing of stepwise (replicated) values |
| | `SafeCall`, `TickGuard`, `Retry`, `NameCache` | pure | A step that may fail without stopping the rest (pcall + one tagged log line), a loop tick guard that logs once per component, bounded retries with injected waits, userId → name lookups that keep good answers and retry failed ones |
| `src/data` | `SessionLock`, `DataService` | pure, server | Session-locked load / save with retries, injected backend, and refusal to overwrite data from a newer save format |
| | `ReceiptLedger` | pure, server | Developer Product receipts kept in a save: capped list of processed ids, and the grant → record → save decision (Granted only after a successful save) |
| `src/guide` | `GuideTarget` | pure | Picks the closest candidate on the ground plane, keeping the current pick unless another is clearly closer |
| | `GuideTrail` | pure | Lays out ground-trail arrows along a route: spacing, scroll phase, fade at both ends, length and count caps |
| | `GuideEdge` | pure | Screen-edge pointer position and angle for an off-screen target (flips targets behind the camera) |
| | `EdgeArrow` | pure | Screen-edge arrow from the target in camera space (no projection flips beside or behind the camera), with any screen box as the edge |
| | `GuideMarker` | pure | Height of the marker above a target that carries its own floating labels (studs-plus-pixels BillboardGuis) |
| | `GuideRoute` | pure | Route bookkeeping: approach spots around a target's footprint, forward-only progress along a route, off-route distance, when to recompute (with back-off), arrival fade |
| | `GuideView` | adapter, client | Leads the local player to a target: neon chevrons snapped to the ground (optional pathfinding route), ring, labelled marker (optionally lifted above the target's own labels, `clearLabels`), Highlight outline, screen-edge pointer; colours, sizes and the arrow template can be overridden |
| `src/ranking` | `OrderedBoard` | pure, server | Top-N rankings in OrderedDataStores: value clamping, write-on-change, page → ranked entries, in-memory pages, one store per period (weekly boards) |
| `src/analytics` | `Analytics` | pure, server | AnalyticsService events behind a catalog of names (onboarding steps, funnels, custom events, currencies, progression paths), a per-minute rate budget, batched counts and economy flows, once-per-session onboarding steps, funnel session ids, custom fields as a list; `recorder()` sink for specs and Studio |
| | `AnalyticsSink` | adapter, server | Sends tracker calls to AnalyticsService with the right Enums inside `pcall`; `tee` sends to two sinks |
| `src/anticheat` | `MovementGuard` | pure, server | Checks server-read character positions for teleports, speed hacks and flying; tolerates lag freezes, downhill runs and server-made moves (`allow`, `reset`) |
| | `Suspicion` | pure, server | Points per player that drain over time and reach "pause" / "kick" levels |
| `src/pad` | `RingPad` | pure | A round floor pad to stand on, in two styles: `"ring"` (one smooth circle, the light sweeps round) or `"pieces"` (curved pieces with even-width cuts, lit a piece at a time). Its block layout, who stands on it, a stand-to-activate timer, and how many segments a charge or countdown lights |
| | `RingPadView` | adapter | Builds a RingPad as non-colliding parts (Model `Seg_<i>` per piece), places it on a floor point and yaw, and lights pieces 1..n in a named look; looks and a block template can be overridden |
| `src/settings` | `SettingsSchema` | pure | A list of player settings (toggles, sliders, choices): defaults, cleaning saved values, checking values a client sends, applying changes |
| `src/ui` | `InputKind` | pure | Which device the player is on (keyboard / touch / gamepad) from the UserInputService it is handed, and the gamepad aim point |
| | `ButtonClicks` | adapter, client | Every GuiButton under a root plays a click sound; sound name, skip attributes and an on / off switch are injected |
| | `MenuMouse` | adapter, client | Frees the cursor in first person / shift lock while the game says a menu is open (one hidden `Modal` button) |
| | `LabelFit` | pure | World-label maths: px per stud, read distance, phone pixel scale and MaxDistance; `mark(gui)` tags a pixel tag for the fitter ([guide](../../guides/roblox-world-labels.md)) |
| | `LabelFitView` | adapter, client | Shrinks every marked BillboardGui on a phone-sized screen (Size × scale plus a UIScale) and applies its phone MaxDistance; re-fits on screen-size changes |
| `testing` | `TestRunner` | Lune only | describe / it / expect used by these specs; games can reuse it |

## Mounting in a game

Add the library to the game's `default.project.json` (Rojo accepts paths outside the project folder):

```json
"ReplicatedStorage": {
  "$className": "ReplicatedStorage",
  "Lib": { "$path": "../../shared/luau/src" }
}
```

In game code, require it in the dual form so the module still loads under Lune:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Inventory = if script then require(ReplicatedStorage.Lib.inventory.Inventory)
	else require("../../../../shared/luau/src/inventory/Inventory")
```

The Lune path is relative to the requiring file. Server-only modules (`Inventory`, `DataService`) are pure code with nothing secret, so living in ReplicatedStorage is fine.

## Inventory: how the pieces fit

```
server                                   client
------                                   ------
ItemRegistry.new(defs)                   same registry (shared defs)
Inventory.new / deserialize(saved)
  add / remove from game logic
InventoryActions.handle(inv, action,     Hotbar.entries(snapshot, registry, extras)
  args)  <── Request("Equip", 3) ─────   HotbarView.new(gui, { onSelect = send intent })
inv:snapshot() ──── State push ──────>   view.update(entries, gridEntries)
inv:serialize() → save                   ToolProvider.bindNumberKeys(view.pressKey)
```

The client never changes the inventory: `HotbarView` reports a press, `Hotbar.select` turns it into an intent, the game sends it through its own request remote, and `InventoryActions.handle` validates it on the server. Using an item is game logic: the game checks its own "Use" action, then calls `inv:consumeEquipped()`.

Customising the default UI:

```lua
HotbarView.new(gui, {
	onSelect = onSelect,
	theme = { slot = Color3.fromRGB(84, 58, 150), slotEquipped = Color3.fromRGB(128, 86, 224) },
	metrics = { slot = 48, maxSlots = 6 },
	renderIcon = function(container, entry) MyIcons.draw(container, entry.itemId) end,
	zone = function(screen, touch) return MyLayout.hotbarZone(screen, touch) end,
})
```

For a completely different look, build your own view on `Hotbar` + `HotbarLayout` and skip `HotbarView`.

## Ring pad: a round pad to stand on

`RingPad` + `RingPadView` make the same round floor pad anywhere (a lock pad, a shop pad, a teleport, a vote spot). The game keeps its own rules: when the pad fires and which look it shows.

```lua
local pad = RingPadView.new(plot, {
	name = "LockPad",
	shape = { radius = 4.6, width = 1.6 }, -- style "ring" (default); { style = "pieces", segments = 12, gap = 0.2 } for pieces
	looks = { charge = { color = Color3.fromRGB(88, 214, 207), material = Enum.Material.Neon, transparency = 0 } },
})
pad:place(floorPoint, yawDegrees)

-- every tick (server):
local fired
fired, since = RingPad.hold(since, pad:standing(root.Position), busy, now, 1)
if fired then doTheThing() end
pad:show(if since then RingPad.charge(pad.shape.segments, since, now, 1) else 0, "charge")
```

## Checks

From `shared/luau`:

```sh
lune run tests
selene src tests testing
stylua --check src tests testing
rojo build -o lib.rbxm
```

`HotbarView` and `ToolProvider` need Roblox and are not covered by the Lune specs; check them in Studio when you change them.

## Guide: leading the player to a target

```lua
local GuideView = require(ReplicatedStorage.Lib.guide.GuideView)
local guide = GuideView.new({
	color = Color3.fromRGB(255, 226, 60), -- every option is optional
	trail = { spacing = 4, maxLength = 120 }, -- GuideTrail.Options
	usePathfinding = true, -- false: a straight line on the ground
	getIgnore = function() return { workspace.Enemies } end, -- the trail never lands on these
	agentParams = function() -- or a table; merged over AgentRadius 2, AgentHeight 5, AgentCanJump true
		return { Costs = { Plot_3 = math.huge } } -- called for every path, so costs can follow the player
	end,
})
guide:setTarget(model, "Buy $40") -- any PVInstance; nil or guide:clear() hides everything
guide:setTarget(model, "Buy $40", spot) -- the trail ends at `spot`; ring, marker and outline stay on `model`
guide:setTrail({ maxLength = 200, spacing = 5 }) -- replaces the trail options at any time
guide:setEdgeHidden(true) -- hides only the screen-edge pointer (say, while a menu is open)
guide:destroy()
```

The trail never ends inside the target. Without a goal it ends at a descendant Attachment named `GuideGoal` when the target has one, else at a free spot just outside the target's footprint, closest to the player (`approach = true`, `approachDirections = 12`, `approachMargin = 4`). With pathfinding the route is only recomputed when the player strays more than `offRoute` (6) studs from it, the goal moves more than `goalMoved` (6) studs, or every `routeRefresh` (5) seconds. Until the first route for a target is found no ground arrows show (failed computes retry after 1, 2, 4 s); `straightFallback = true` draws a straight line meanwhile. Within `arriveDistance` (10) studs of the goal the ground arrows fade out.

Picking the target is the game's job: build the candidates it allows (affordable, unlocked...) and let `GuideTarget.pick(candidates, from, currentKey)` choose, so the guide does not flick between two targets at nearly the same distance.
