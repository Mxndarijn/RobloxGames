# Goo Gauntlet: the sky obby

A short parkour course floating above the map. Clearing it earns **x1.5 income for 5 minutes**; the next run earns it again **5 minutes after the boost ends**. The course rebuilds every **10 minutes** from new sections. Design: `docs/obby-proposal.html`. Tunables: `Config.OBBY`. No feature flag (it ships on).

## 1. Modules

| Module | Kind | Owns |
|---|---|---|
| `shared/ObbyCourse` | pure | Sections (`BUILD`, 12 ids x `LAYOUTS` layouts), the rotation (`slot`, `pick`), the layout (`build`: start pad, sections, a checkpoint pad after each, the last one the finish), checkpoint / fall / respawn geometry, the course frame (`toWorld`, `toLocal`) |
| `shared/ObbyRules` | pure | The boost over the saved timers: `phase`, `grant`, `bonus`, `view`, `clean` |
| `server/ObbyService` | pure | `world.obby`, `session.obbyRun`: portal, checkpoints in order, falls, finish, rotation, `refresh` (data.obbyBonus), `view` (State.obby) |
| `server/ObbyView` | adapter | `workspace.Obby` (Portal once, Course per rotation), root positions, teleports |
| `visuals/client/ObbyFx` | client | Plays the moving parts locally at server time |
| `ui/ObbyHud` | client | The run card and the portal sign's two lines (per player) |
| `ui/HudClusters.obby` | client | The `Obby` status slot while boosted (icon `Boost_Obby`) |

## 2. Rotation

`slot = floor(serverTime / ROTATION_SECONDS)`. `pick(slot)` takes one section per entry of `ORDER` (easy, easy, medium, medium, hard), never one twice, and none of the previous course's sections inside a chain of `CHAIN_SLOTS` rotations (the first course of a chain starts fresh). Each gets a layout 1..`LAYOUTS`. The same slot gives the same course on every server and client. A new rotation rebuilds the course once no one is running, or `REBUILD_GRACE` seconds after it starts; runners still on it are set down by the portal.

## 3. A run

- **Start**: stepping into the portal circle (`WorldLayout.OBBY.portalRadius`) from outside it. Refused while carrying a slime, or while a new course is waiting to be built.
- **Checkpoints**: standing on the next checkpoint pad (`ObbyCourse.onCheckpoint`, within `STAND_HEIGHT` above its top) counts it. Pads only count in order. A pad reached less than `MIN_SECTION_SECONDS` after the last one marks the run invalid: it still finishes, but earns nothing.
- **Fall**: below `ObbyCourse.fallHeight` (the lower of the last and next pad tops minus `FALL_DEPTH`): back to the last pad reached, `RESPAWN_LIFT` above it.
- **Off course** (more than `ObbyService.OFF_COURSE` studs past the ends or sides, or far below), death or no character: the run ends.
- **Finish**: the run time, a best on this course (`session.obbyBest`), and `ObbyRules.grant` when ready. Then the player is set down at `exit` by the portal.
- Runs during the boost or the cooldown are allowed; they earn no boost.

## 4. Save and State

- `PlayerData.obbyUntil` / `obbyReadyAt` (server time, 0 = never), saved as `obby = { untilAt, readyAt }` without a version bump (`SaveData`, missing = never earned). `obbyReadyAt = obbyUntil + COOLDOWN_SECONDS`.
- `data.obbyBonus` is runtime only: `ObbyService.refresh` (every `GameLoop.step`) sets it from the timers, so it survives a rejoin. `Perks.bonusMultiplier` multiplies `1 + obbyBonus` with the other bonuses.
- `State.obby` (`Types.ObbyView`): `bonus`, `endsAt?` (while boosted), `readyAt?` (until ready), `sections` (names), `rotatesAt`, `run? = { reached, of, startedAt }`, `best?`.
- No remote: the server reads positions.

## 5. World

- `WorldLayout.OBBY`: the portal in the yard between plots 8 and 1 (bearing 337.5, r 238), the course `skyHeight` studs above it, running towards the map centre. `PropClearance` keeps `clearRadius` round the portal clear.
- `workspace.Obby.Course` (attribute `Slot`): one Part per `ObbyCourse.Part`. Moving parts carry `Constants.OBBY_*` attributes (motion kind, rest CFrame, axis, amplitude, period, phase, delay, away, duty, min, shrink axes). Belts have a surface velocity, ice no friction.
- `workspace.Obby.Portal`: ring, floor, light column and a SurfaceGui sign (`Title`, `Constants.OBBY_SIGN_STATUS`, `Constants.OBBY_SIGN_COURSE`), MaxDistance 200 (guides/roblox-world-labels.md).

## 6. Analytics

`ObbyStarted`, `ObbyFinished` (value = seconds; field: boost earned / cooling / invalid), `ObbyFell` (field: section).
