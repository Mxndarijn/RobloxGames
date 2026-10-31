# Obby: the sky course

A short parkour course in its own sky world, reached through a portal in the yard, called **Obby** everywhere players see it. Clearing it earns **x1.5 income for 5 minutes**; the next run earns it again **5 minutes after the boost ends**. The course rebuilds every **10 minutes** from new sections. Design: `docs/obby-proposal.html`. Tunables: `Config.OBBY`. No feature flag (it ships on).

## 1. Modules

| Module | Kind | Owns |
|---|---|---|
| `shared/ObbyCourse` | pure | Sections (`BUILD`, 30 ids, 10 per tier, x `LAYOUTS` (6) layouts; each asks for a jump, a timing or a route: `tests/ObbyCourse.spec` fails any layout you can cross by holding forward along the middle line), the rotation (`slot`, `pick`), the layout (`build`: start pad, sections joined by short plain connectors, finish pad; no checkpoints), section spans (`sectionAt`), fall height, the finish zone (`onFinish`), the course frame (`toWorld`, `toLocal`) |
| `shared/ObbyRules` | pure | The boost over the saved timers: `phase`, `grant`, `bonus`, `view`, `clean` |
| `server/ObbyService` | pure | `world.obby`, `session.obbyRun`: portal, section progress in order, falls back to the start, finish, rotation, `refresh` (data.obbyBonus), `view` (State.obby) |
| `server/ObbyView` | adapter | `workspace.Obby` (Portal once, Course per rotation), root positions, teleports |
| `visuals/client/ObbyFx` | client | Plays the moving parts locally at server time |
| `ui/ObbyHud` | client | The run card and the portal sign's two lines (per player) |
| `ui/HudClusters.obby` | client | The `Obby` status slot (icon `Boost_Obby`): the boost's time left, then a dimmed cooldown countdown (§4) |

## 2. Rotation

`slot = floor(serverTime / ROTATION_SECONDS)`. `pick(slot)` takes one section per entry of `ORDER` (easy, easy, medium, medium, hard), never one twice, and none of the previous course's sections inside a chain of `CHAIN_SLOTS` rotations (the first course of a chain starts fresh). Each gets a layout 1..`LAYOUTS`. The same slot gives the same course on every server and client. A new rotation rebuilds the course once no one is running, or `REBUILD_GRACE` seconds after it starts; runners still on it are set down by the portal.

## 3. A run

- **Start**: stepping into the portal circle (`WorldLayout.OBBY.portalRadius`) from outside it. Refused while carrying a slime, or while a new course is waiting to be built. The runner appears `RESPAWN_LIFT` above the start pad and the clock starts.
- **No checkpoints.** The sections follow each other with a `LINK_LENGTH` plain connector (look `pad`) between two sections; every section starts and ends with a jump. Each section owns a span along the course (`Course.spans`: `from`, `to`, `floor` = the lower of its entry and exit heights), the connector after it included.
- **Section progress** (invisible): every tick the server finds the part of the course the runner is over (`ObbyCourse.sectionAt`: 0 = start pad, 1..5 = sections, 6 = finish pad) and keeps the furthest one, in order (`run.section`). Getting past a section without ever being over it marks the run invalid.
- **Fall**: below `ObbyCourse.fallHeight` (the `floor` of the span under the runner minus `FALL_DEPTH`; the start pad's top for the start, the finish pad's top for the finish) sends the runner back to the start pad, `RESPAWN_LIFT` above it. The clock keeps running, the sections already done stay done, and no boost is lost. `ObbyFell` is tracked with the section the runner fell from. Checks wait `MOVE_GRACE` after every move the server makes.
- **Off course** (more than `ObbyService.OFF_COURSE` studs past the ends or sides), death or no character: the run ends.
- **Finish**: standing on the finish pad (`ObbyCourse.onFinish`, within `STAND_HEIGHT` above its top). The run time, a best on this course (`session.obbyBest`), and `ObbyRules.grant` when ready. Then the player is set down at `exit` by the portal. An invalid run (a skipped section, or a finish faster than `MIN_RUN_SECONDS`) still finishes but earns nothing and sets no best.
- Runs during the boost or the cooldown are allowed; they earn no boost.

## 4. Save and State

- `PlayerData.obbyUntil` / `obbyReadyAt` (server time, 0 = never), saved as `obby = { untilAt, readyAt }` without a version bump (`SaveData`, missing = never earned). `obbyReadyAt = obbyUntil + COOLDOWN_SECONDS`.
- `data.obbyBonus` is runtime only: `ObbyService.refresh` (every `GameLoop.step`) sets it from the timers, so it survives a rejoin. `Perks.bonusMultiplier` multiplies `1 + obbyBonus` with the other bonuses.
- `session.obbyRun = { slot, section, startedAt, invalid?, settleUntil? }` is runtime only.
- `State.obby` (`Types.ObbyView`): `bonus`, `endsAt?` (while boosted), `readyAt?` (until ready), `sections` (names), `rotatesAt`, `run? = { section, of, startedAt }` (`section` = furthest section reached, 0 = start pad), `best?`. The run card shows `OBBY` on the start pad, then `SECTION x/5`, with the run clock.
- HUD (bottom-right status row, `HudClusters.obby`): while boosted, the slot shows the time left to `endsAt`. After it, until `readyAt`, the same slot shows kind `"cooldown"`: the icon under an Ink veil, the timer muted, tooltip "Next boost ready in m:ss". Once ready the slot goes away (no "Ready!" flash; the portal sign says it). A cooldown slot is the first to give way when the row is full, before the featured Secret.
- No remote: the server reads positions.

## 5. World

- `WorldLayout.OBBY`: the portal in the lawn lane between plots 8 and 1 (bearing 337.5, r 155), in front of the yard's windmill scene. `PropClearance` keeps `clearRadius` round the portal clear.
- **Path**: a star walk (`WorldLayout.obbyPath`, the Hall of Fame path's style, with goo-green dots in the stars' places) from the ring path's outer rail out to the portal, `pathWidth` wide, and the `Constants.OBBY_ARCH` arch ("OBBY", `Props.obbyArch`, a `PROP_SPOTS` entry) over it `archDistance` from the map centre, just past the ritual circle (`Config.RITUAL`) beside its plaza end. `PropClearance` keeps the path clear ("Obby path"), so the yard dressing (`YardProps`) and the plaza props stand off it.
- **Obby world**: the course stands in its own zone, `WorldLayout.OBBY.world`, thousands of studs from the map (past any view distance and the Atmosphere), so nothing of it shows from the plots, plaza or bases and nothing of the map shows from it. The course frame is `world.origin` / `world.yaw`. `WorldLayout.inObbyWorld(pos)` is true inside `world.radius` of the zone's centre.
- The backdrop (`visuals/client/ObbyBackdrop`, from `WorldLayout.obbyBackdrop()`, a `Constants.OBBY_BACKDROP` Folder in workspace): floating goo islands, cloud puffs and a cloud sea round the course. Client only: `ObbyWorld` builds it when the local player arrives and removes it after they leave, so the server world and its part budget never carry it. Decor only: no collision, no queries, no touches.
- The portal moves the runner to the start pad in the obby world; a finish, a rotation or leaving the course sets them down at `exit` by the portal. A player in the obby world without a run (off course, a cancelled run) is set down at `exit` on the next tick.
- `visuals/client/ObbyWorld`: while the local player's root is `inObbyWorld`, it swaps to `ObbyLook` (Lighting, Atmosphere, a ColorCorrection tint, and the place's Bloom and SunRays turned down) on the frame they arrive, and back on the frame they leave: at once, under a short neutral veil (`ObbyLook.VEIL`), with the camera kept behind the player at the same zoom and pitch. The way back restores the map's look exactly (NightSky recomputes it from the day / night and weather values; the weather grade snaps back instead of fading in). The boss card hides while the player is there. `NightSky` blends the look on top of the day / night and weather look; the look has its own day and night values (`ObbyLook.LOOK` / `NIGHT`, by `NightLook.factor`). Course parts use no Neon.
- `ObbyLook.isInside` (set by `ObbyWorld` each frame, `onInsideChanged` for changes) is the one "in the obby world" signal on the client. While it is true the home plot marker (beacon, tag, edge arrow) hides, the weather (`WeatherFx`) and Slime Rain draw nothing, and the tutorial guide computes no paths (`GuideView` `shouldPath`) and hides its edge pointer. All of it comes back on the way out.
- `workspace.Obby.Course` (attribute `Slot`): one Part per `ObbyCourse.Part` (a TrussPart for ladders). Moving parts carry `Constants.OBBY_*` attributes (motion kind, rest CFrame, axis, amplitude, period, phase, delay, away, duty, min, shrink axes, power, arm). Motion kinds: slide, spin, melt, flip, shrink, bounce (trampolines and cannons throw the local player up at `power`), lift (wind columns), swing (pendulums), rock (seesaws), roll (logs rolling round their length), punch (out fast, hold, back), gust (a wind zone that blows the local player sideways while on). Belts have a surface velocity, ice no friction.
- Slime Guard opens its launch window for players on a run (`SlimeGuardView`): bounces and fans rise faster than a jump.
- `workspace.Obby.Portal`: ring, floor and a SurfaceGui sign (no light column: the path and the OBBY arch lead players there) (`Title` "OBBY", `Constants.OBBY_SIGN_STATUS`, `Constants.OBBY_SIGN_COURSE`), MaxDistance 200 (guides/roblox-world-labels.md).

## 6. Analytics

`ObbyStarted`, `ObbyFinished` (value = seconds; field: boost earned / cooling / invalid), `ObbyFell` (field: the section the runner fell from; the runner goes back to the start pad).
