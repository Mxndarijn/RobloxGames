# Interfaces

## Jolt

### `ReplicatedStorage.Shared.StageGenerator` (`src/shared/StageGenerator.luau`)

```luau
type PartSpec = {
	position: { x: number, y: number, z: number }, -- part centre
	size: { x: number, y: number, z: number },
	kind: "platform" | "checkpoint" | "finish",
	stage: number, -- 0 = spawn pad, 1..stageCount otherwise
}
type LayoutConfig = { stageCount: number, seed: number? }

StageGenerator.layout(config: LayoutConfig): { PartSpec }
StageGenerator.build(parent: Instance, config: LayoutConfig): {
	spawn: BasePart,
	checkpoints: { BasePart },
	finish: BasePart,
}
```

**`layout`**: pure and deterministic. It doesn't use any Roblox APIs and runs under Lune.
- `stageCount` must be an integer from 5 to 8. Any other value **raises an error**. It is not clamped.
- `seed` defaults to `1`. The RNG is a pure-Luau Park-Miller LCG, so a given seed gives the same course in Lune and in Roblox.
- Parts come back in course order along **+Z**: the spawn pad (`kind = "platform"`, `stage = 0`), then for each stage some platforms followed by a `checkpoint` pad, then one `finish` pad.
- The course surface sits at `y = BASE_Y` (20), with x centred on 0 and z starting at 0.
- Difficulty goes up with each stage: gaps get longer, platforms get narrower and there are more of them (`2 + stage // 2`).
- Gaps (measured edge to edge along Z) in stage `s` stay within `[maxGap - 1, maxGap]`, where `maxGap = min(7 + (s - 1), 14)`.
  - `MAX_GAP_AT_BASE_SPEED = 7`. A jump at WalkSpeed 16 with JumpPower 50 covers about 8.2 studs.
  - `ABSOLUTE_MAX_GAP = 14`. Clearing it needs WalkSpeed ≈ 27.5.
- Helpers: `stageParams(stage)`, `airTime(jumpPower?, gravity?)` and `requiredSpeedForGap(gap, jumpPower?, gravity?)`.
- No two parts overlap. The unit tests check this with 3D AABBs.

**`build`**: uses Roblox APIs and is server-side only.
- If `parent` already has a child named `Course`, `build` destroys it. It then creates a new `Model` named `Course` under `parent`.
- Every part has `Anchored = true` and `CanCollide = true`.
- Names:
  - The spawn pad is `Spawn`. It is a plain `Part`, **not** a SpawnLocation.
  - Checkpoints are `Checkpoint_1..n`. They're green Neon, and each has attribute `StageIndex` (1-based).
  - The finish is `WinPad` (gold Neon).
  - Other platforms are `Platform_N` (gray-blue).
- `build` sets up **no touch handling**.

### HUD (`src/jolt-client/Hud.client.luau` → `StarterPlayerScripts.JoltHud`)

Rojo maps this file as a **sibling** LocalScript under `StarterPlayerScripts` (see `default.project.json` key `JoltHud`). It must not live under `src/client/` next to `init.client.luau`, or Rojo would nest it inside the `Client` LocalScript and it would never run.

The HUD creates a ScreenGui named `JoltSpeedHud` (`ResetOnSpawn = false`) in PlayerGui. It is read-only and reads:

| Source | Expected type | Notes |
| --- | --- | --- |
| `player:GetAttribute("Speed")` | number | Shows 0 if the attribute is nil. Updates live. |
| `player:GetAttribute("Stage")` | number | Shows 0 if the attribute is nil. Updates live. |
| `player.leaderstats.Wins` | IntValue | Waits up to 30 s each for `leaderstats` and `Wins`. |
| `ReplicatedStorage.Remotes.WinEvent` | RemoteEvent | `OnClientEvent(totalWins: number)` shows a "YOU WIN!" popup for 3 s. |

### What Archer must wire (server)

1. Call `StageGenerator.build(workspace, { stageCount = 5..8, seed = ... })`. Teleport or respawn players onto `result.spawn`; it is a plain Part, so position characters above it yourself.
2. Set the player attributes `Speed` (number) and `Stage` (number, the last checkpoint `StageIndex` reached).
3. Create `leaderstats` (Folder) containing a `Wins` IntValue for each player.
4. Create `ReplicatedStorage.Remotes` (Folder) with a `WinEvent` RemoteEvent. Call `WinEvent:FireClient(player, totalWins)` on every win.
5. Touch handling:
   - On `Checkpoint_N`, set `Stage` from the part's `StageIndex`.
   - On `WinPad`, increment `Wins`, fire `WinEvent`, then reset the player.
   - Optional: a kill floor or fall reset (the course is at y = 20).
