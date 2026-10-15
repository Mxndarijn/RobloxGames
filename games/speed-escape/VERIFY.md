# Verification

Run: 2026-10-14 15:25 UTC — rojo 7.7.1, lune 0.11.0, selene 0.32.0, stylua 2.6.0

## `rojo build -o build.rbxlx` — PASS (exit 0)

```
Building project 'speed-escape'
Built project to build.rbxlx
```

## `lune run tests` — PASS (exit 0)

```
SpeedCalculator.spec
  PASS  getMultiplier > is 1 with no rebirths
  PASS  getMultiplier > grows linearly per rebirth
  PASS  getMultiplier > treats negative and NaN rebirths as 0
  PASS  getMultiplier > respects a custom config
  PASS  getSpeed > returns base speed at 0 steps
  PASS  getSpeed > adds speedPerStep per step
  PASS  getSpeed > applies the rebirth multiplier
  PASS  getSpeed > is capped at maxSpeed
  PASS  getSpeed > floors fractional and clamps negative steps
  PASS  getStepsForSpeed > returns 0 for speeds at or below base
  PASS  getStepsForSpeed > returns nil above maxSpeed
  PASS  getStepsForSpeed > is the inverse of getSpeed
  PASS  getStepsForSpeed > returns nil when steps give no speed
  PASS  getRebirthCost > starts at rebirthBaseCost
  PASS  getRebirthCost > grows geometrically
  PASS  getRebirthCost > is strictly increasing
  PASS  getRebirthCost > returns whole numbers
  PASS  canRebirth > is false below cost
  PASS  canRebirth > is true at exactly the cost
  PASS  canRebirth > uses the cost for the current rebirth count
  PASS  getRebirthProgress > is 0 with no steps, 0.5 halfway, clamped to 1
  PASS  applyRebirth > resets steps and increments rebirths when affordable
  PASS  applyRebirth > leaves state unchanged when not affordable
  PASS  stepsFromDistance > floors distance / studsPerStep
  PASS  stepsFromDistance > returns 0 for non-positive studsPerStep
  PASS  formatNumber > formats small numbers verbatim
  PASS  formatNumber > abbreviates with suffixes
  PASS  formatNumber > handles negatives and NaN
  PASS  DEFAULT_CONFIG > is frozen

29 passed, 0 failed, 29 total
```

## `selene src tests` — PASS (exit 0)

```
Results:
0 errors
0 warnings
0 parse errors
```

## `stylua --check src tests` — PASS (exit 0)

```

```

## Summary

| Command | Exit | Result |
|---|---|---|
| `rojo build -o build.rbxlx` | 0 | PASS |
| `lune run tests` | 0 | PASS |
| `selene src tests` | 0 | PASS |
| `stylua --check src tests` | 0 | PASS |
