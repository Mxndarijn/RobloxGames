# Base remodel: the goo jar tower

Status: **built with primitive stand-ins; kit meshes and the runtime part budget still to do** (2026-10-20). Branch `feat/base-floors`.

A base now grows by **floors of 8 pads, up to 32 pads**. Each floor is a glass jar stacked on the one below, so a player's version reads from across the map. The design replaces the square fenced yard, the crate pads and the wooden gate.

![Goo jar tower: versions 1-4, open and locked door, side and back](goo-jar-tower.jpg)

## The design

| Version | Pads | What you see |
|---|---|---|
| 1 | 8 | One glass jar on a wooden foot inside a goo moat. A cork stopper lid, and the slime mascot on top. |
| 2 | 16 | A second, smaller jar on the first. The drop tube starts on the back. |
| 3 | 24 | A third jar. The mascot gets bigger. |
| 4 | 32 | A fourth jar. The mascot gets a crown, and goo spills over the top lid. |

- **Jars.** Each jar has a see-through glass wall (a Roblox Glass part, transparency about 0.6) with brass ribs running up over the shoulder to a threaded neck and a cork lid. The next jar stands on that lid. A jam-jar label on the front is in the plot colour. Jar 1's label is the owner's name board, front-left so the door stays clear. The upper jars show their floor number as goo dots.
- **Slime stands.** A cork pedestal with a brass band and a dish in the plot colour, holding a goo bed. The seat is 2.4 studs high, like today's pads. The stands sit on a ring round the centre, 8 per jar.
- **Getting around.** You come in through the round door on the front of jar 1. A spiral stair round the centre post climbs one stud per step, up through a hole in each deck. You leave fast by the goo drop tube down the back: a hatch on every upper jar drops you in a splash pool behind the moat. **A player carrying a slime can't use the tube**; they have to walk out through the door.
- **Lock.** A giant cork stopper is parked beside the door while the base is open. While it's locked, the stopper plugs the door and a red ring glows around it. The lock button is a red goo button on a cork post by the bridge.
- **Slime vibes.** Goo oozes from under every lid with teardrop drips, a thin goo line runs along the door frame, goo is smeared on the glass and bubbles in the pools, and the mascot slime on top grows with each version.

Palette: the locked Slime Ranch theme (`shared/modeling-kit/THEME.md`): `ranch_goo`, `ranch_goo_hi`, cork (214, 170, 116), brass `ranch_metal`, glass (200, 240, 244), and the plot colour for trim. The only neon is gameplay: the locked ring and the lock button.

### Concepts that were not chosen

| A. Goo jar tower (chosen) | B. Slime tree | C. Floating islands |
|---|---|---|
| ![](concept-jar.jpg) | ![](concept-tree.jpg) | ![](concept-islands.jpg) |

The renders come from `shared/modeling-kit/models/_goo_jar_tower_scene.py` (`JAR_V=1..4`, `JAR_LOCKED=1`) and `_base_concepts_scene.py`, made with `iterate.py --look roblox`. They are design blockouts, not upload meshes.

## Decisions made

- 4 versions, 8 pads each, 32 pads in total. Prices are in `Config.BASE_FLOORS`: floor 1 costs 100 ×2.5 per pad, floor 2 starts at 25K, floor 3 at 2.5M and floor 4 at 250M, each ×1.6 per pad. These are first guesses to tune.
- Pads goal: 6 / 8 / 16 / 24 / 32.
- Floors are 16 studs apart. The jar radii are **34 / 31 / 29 / 27**. That's wider than the render (31 / 26 / 21.5 / 17.5), because 8×8 pads need a 3-stud walkway between them and 4.5 studs to the glass (`tests/JarTower.spec.luau`). The pad rings are at radius 21 / 20 / 19 / 18.
- The upper jars are built at runtime (`server/BaseFloors`) only on plots whose owner has them. The static map has just 15 parts of headroom (1385 of 1400).
- Walking stair, not a lift: top-floor steals stay a chase.
- No new save field: the version comes from `padsUnlocked`, and old saves load unchanged.

## Done on this branch

| Commit | What |
|---|---|
| `docs: contract for bases that grow by floors` | First contract: 32 pads, 8 per floor. |
| `feat: bases grow by floors of 8 pads, up to 32` | `Config.BASE_FLOORS` pricing, `Economy.floorOf` / `floorsShown`, the "Build floor N" prompt, `server/BaseFloors` (build/remove upper floors through an injected builder), `MeshSwap.applyUnder`, `HomeZone.ReachUp`, and the fallback world with 32 flat pads. All tests pass. |
| `feat(modeling-kit): concept scenes` | Concept and jar scenes, plus `rbx_transparency` for glass previews in `--look roblox`. |
| `docs: contract for the goo jar tower base` | CONTRACT.md §5.3: jars, door, stopper lock, radial lock guard, drop tube. |
| WIP commit | Jar geometry in `WorldLayout` (radii, pad ring, stair, deck ring, glass wall, lid, drop hatch, `WorldLayout.floor` for upper jars), `WorldBuilder.buildFloor`, lids hidden under a jar above (`BaseFloors`), `tests/JarTower.spec.luau`. The static ground plot was switched in the next row. |
| Jar tower switch | Round lock guard (`PlotLockGuard`: jar radius at the character's height plus the doorway) with its spec first; the static ground plot is jar 1 (moat, jar floor, bridge, glass with the door, lid, ring pads, the `Stopper` as `LockBarrier`, `ParkedStopper`); vat, lock button, label sign, trophies and spawn moved (`WorldLayout` `VAT_SPOT`, `LOCK_BUTTON_SPOT`, `LABEL`, `TROPHY_SPOTS`, `SPAWN_SPOT`); rebirth decor and plot-skin `trim` on the jar; the drop tube (`DropPrompt` from `BaseFloors`, `Actions.useDropTube` refuses carriers, tube and splash pool); the client mascot and ooze (`PlotMascot`); fence and gate specs, tools and the pc-watcher reworked. |

## Checked in a hidden Studio

With `PADS_START` raised to 17 in the throwaway Studio copy (so jars 2 and 3 stand): the player spawns on the walkway; jars 2 and 3 build with their DropPrompts and the lids under them hide; the owner walks in through the locked stopper while an NPC outsider is stopped at its face; a player climbs both stairs to jar 3; the drop tube puts them on the splash pool; the client builds the mascot (version 3 on the owner's plot, 1 on free plots). Not checked in Studio: the drop refusal while carrying (covered by `tests/DropTube.spec`), and a real non-owner leaving through the stopper (needs two players; covered by `tests/PlotLockGuard.spec`).

## Still to do

1. **Runtime part budget.** An upper jar is about 62 Parts (24 glass segments, 16 deck pieces, the 17-part stair, 8 pads with stands, lid, hatch, tube). In Studio the world was at 2443 parts with two upper jars on one plot; eight maxed plots add about 1,500 more, well past the 2900 warn level. The kit meshes below are the fix: one glass mesh per jar (24 to 1), one deck mesh (16 to 1), one stair mesh (17 to 1).
2. **Kit meshes** (modeling-kit loop, **no upload without Merijn's OK**): jar glass with ribs and shoulder, deck, stair, cork stand, door frame and stopper, goo ooze ring, drop tube, mascot slime. Until then the primitive stand-ins stay; the round cork stand also needs habitat overlays fitted to the round dish (today the crate stand stays, so the overlays still fit).
3. Leftover `MeshAssets` entries for the retired `ranch_fence_20`, `phoenix_fence_segment` and `phoenix_gate` (no slot uses them).
