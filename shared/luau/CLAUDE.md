# shared/luau: rules for agents

Game-agnostic Luau systems every game in this repo can mount. A module only lands here when at least one game needs it and nothing in it names a game (no slimes, no plots, no `Config` of a game). Read [README.md](README.md) for the module list and how a game mounts the library.

## The module pattern (follow it for every new module)

1. **Pure core, thin adapter.** Rules and data live in a pure module: no `game`, no `Instance`, no services at load time or in its functions. It runs under Lune and is tested there. Anything that touches Roblox (`Players`, `DataStoreService`, `UserInputService`, GUI instances) goes in a separate adapter module whose name says so (`ToolProvider`, `HotbarView`, `DataStoreBackend`). The adapter stays small and calls the core.
2. **Dependencies come in, never reach out.** A core takes what it needs as arguments: a `deps`/`options` table or function parameters (clock `now`, `wait`, a backend, a registry, callbacks). No module-level `setX()` singletons, no requiring a game's modules.
3. **Requires.** Inside the library use the dual form so the same file loads in Roblox and under Lune:
   `local X = if script then require(script.Parent.X) else require("./X")`
   and across folders `if script then require(script.Parent.Parent.core.X) else require("../core/X")`.
4. **Types first.** `--!strict` on every file. Export the public types (`export type Item = ...`). Freeze returned module tables and constant tables (`table.freeze`).
5. **Return values, don't throw, for expected failures.** Mutating functions return `(ok: boolean, reason: string?)` with a short machine-readable reason (`"Full"`, `"Unknown"`, `"NotEnough"`). Only programming errors (bad registry, wrong types at setup) `error()`.
6. **Overridable defaults.** Default UI and default behaviour take an `overrides`/`theme` table merged over the defaults, and expose hooks (`renderSlot`, `onSelect`) so a game can restyle or replace pieces without forking the module.
7. **Cleanup.** Anything that connects events returns a handle with `destroy()` that disconnects everything it made. Starting twice must not double the work.
8. **Comments describe what the code does now.** No version tags (`v19`), bug or PR numbers, or "used to" history; git holds history.

## Tests

- Every pure module has `tests/<Module>.spec.luau` testing behaviour (inputs → outputs, state transitions), not source text.
- Run from `shared/luau`: `lune run tests` (filter with `SPEC_FILTER=Inventory`). Lint and format: `selene src tests testing` and `stylua --check src tests testing`.
- Adapters that need Roblox are kept thin enough that their logic is covered through the core; say in the PR when something was only checked in Studio.

## Changing a shared module

Games depend on this API. Keep changes backwards compatible, or update every game that uses the module in the same PR. List the games you checked in the PR.
