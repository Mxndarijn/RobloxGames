# Speed Escape (skeleton)

Rojo + Luau starter for a Roblox "speed escape" game: players earn **steps** by
moving, steps raise **WalkSpeed**, and **rebirths** reset steps in exchange for a
permanent step multiplier.

## Setup

Toolchain versions are pinned in `rokit.toml`:

| Tool   | Version |
| ------ | ------- |
| rojo   | 7.7.1   |
| selene | 0.32.0  |
| stylua | 2.6.0   |
| lune   | 0.11.0  |
| wally  | 0.3.2   |

```sh
rokit install        # installs the pinned tools (https://github.com/rojo-rbx/rokit)
wally install        # fetches packages into ./Packages (optional; build works without it)
```

## Commands

| Task             | Command                        |
| ---------------- | ------------------------------ |
| Build place file | `rojo build -o build.rbxlx`    |
| Live sync        | `rojo serve` (+ Rojo Studio plugin) |
| Unit tests       | `lune run tests`               |
| Lint             | `selene src tests`             |
| Format check     | `stylua --check src tests`     |
| Format (write)   | `stylua src tests`             |
| Type check       | `luau-analyze src/shared tests` (optional) |

Run every command from the repo root (`lune run tests` discovers specs in `./tests`).
CI runs the same checks: `.github/workflows/ci.yml`.

## Layout

```
default.project.json      Rojo tree mapping (below)
src/
  server/init.server.luau   -> ServerScriptService.Server   (course build, WalkSpeed growth, checkpoints, wins, saves)
  jolt-client/Hud.client.luau -> StarterPlayerScripts.JoltHud (read-only speed/stage/wins HUD)
  shared/                   -> ReplicatedStorage.Shared
    StageGenerator.luau       course layout + build (see INTERFACES.md)
    GameLogic.luau            pure speed/checkpoint/win rules (unit tested)
    SpeedCalculator.luau      pure speed/rebirth math (no Roblox APIs; unit tested)
    Constants.luau            shared tunables and remote names
Packages/                 -> ReplicatedStorage.Packages (Wally, git-ignored, optional)
tests/
  init.luau                 runner entry: loads *.spec.luau, exits 1 on failure
  TestRunner.luau           tiny describe/it/expect framework
  SpeedCalculator.spec.luau
wally.toml                dependencies (sleitnick/signal)
selene.toml, roblox.yml   lint config; roblox.yml from `selene generate-roblox-std`
stylua.toml               formatter config
rokit.toml                tool pins
```

## SpeedCalculator API

All functions are pure and accept an optional partial `config` that overrides
`SpeedCalculator.DEFAULT_CONFIG` (`baseSpeed`, `speedPerStep`, `maxSpeed`,
`rebirthBaseCost`, `rebirthCostGrowth`, `rebirthMultiplierStep`).

- `getMultiplier(rebirths)` → `1 + rebirths * rebirthMultiplierStep`
- `getSpeed(steps, rebirths?)` → `min(maxSpeed, baseSpeed + steps * speedPerStep * multiplier)`
- `getStepsForSpeed(targetSpeed, rebirths?)` → steps needed, or `nil` if unreachable
- `getRebirthCost(rebirths)` → `floor(rebirthBaseCost * rebirthCostGrowth ^ rebirths)`
- `canRebirth(steps, rebirths)` / `getRebirthProgress(steps, rebirths)` (0..1)
- `applyRebirth(steps, rebirths)` → `(ok, newSteps, newRebirths)`
- `stepsFromDistance(studs, studsPerStep)`
- `formatNumber(n)` → `"1.5K"`, `"2M"`, …

## Regenerating the Roblox std

```sh
selene generate-roblox-std   # rewrites roblox.yml (needs network)
```
