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
| `src/core` | `Rng`, `NumberFormat`, `RateLimiter`, `Migrations`, `Signal` | pure | Seeded random, number and duration formatting, per-key action limits, versioned save migrations + sanitizers, a small signal |
| `src/data` | `SessionLock`, `DataService` | pure, server | Session-locked load / save with retries, injected backend, and refusal to overwrite data from a newer save format |
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

## Checks

From `shared/luau`:

```sh
lune run tests
selene src tests testing
stylua --check src tests testing
rojo build -o lib.rbxm
```

`HotbarView` and `ToolProvider` need Roblox and are not covered by the Lune specs; check them in Studio when you change them.
