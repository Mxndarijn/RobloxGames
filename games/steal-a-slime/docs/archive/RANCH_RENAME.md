# Steal a Slime — ranch rename draft

> **Archived.** The rename shipped (fountain naming, `Volcano` kept as an alias, Lava displays as Syrup with its save id unchanged). Kept for the save-id rules; the code is the source of truth.

**Status:** draft (not implemented). Models-first; code/copy may follow after place wiring.
**Rule:** keep mutation **save ids** so player data is not wiped; change display names / module names only where noted.

## Module / systems

| Today | Proposed | Notes |
|---|---|---|
| `Volcano.luau` | `Fountain.luau` (alias ok short-term) | Same `roll` / `canSpawn` / radius; angle = around fountain |
| Config comments "Volcano" | Fountain | `SPAWN_*`, rain caps unchanged |
| Minimap centre "volcano" | Fountain | `MinimapData` |

## Mutation display (save id stays)

| Save id | Display today | Proposed display |
|---|---|---|
| `Lava` | Lava | **Syrup** (ranch/candy; alt: Spicy) |
| `Glow` / `Galaxy` / `Gold` | unchanged | unchanged |

Map id → display in UI / rare announce; keep `MUTATIONS[].name` as save key or add `displayName`.

## UI / tutorial / rare / boss copy

| Today | Direction |
|---|---|
| "volcano" / "erupted" | fountain / spilled from the fountain |
| "lava" in player-facing strings | goo / syrup (by context) |
| Boss / rare spawn lines | slid into the plaza / spilled |

## FX / decor names (client)

| Today | Direction |
|---|---|
| `Eruption` burst | Spill / Splash |
| `LavaBubbles` / `LavaCrack*` | strip with volcano decor; soft goo splash later |
| Crater smoke / embers | soft spill steam (later; not blocking layout) |

## Mesh / tiers

| Today | Direction |
|---|---|
| `volcano.py` / VOLCANO_TIERS | held/dropped with Volcanic Meadow |
| Fountain/silo tiers | only if Merijn revives progression around the fountain |
| `color.py` `lava` / `lava_crack` | leave for legacy sheets; new props use `ranch_*` only |

## Out of scope

- Implementing the renames (Phoenix place wiring first).
- Changing save schema or wipe risk.
