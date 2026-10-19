# Base remodel: the goo jar tower

Status: **design approved, build paused** (2026-10-20). Branch `feat/base-floors`.

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
| WIP commit | Jar geometry in `WorldLayout` (radii, pad ring, stair, deck ring, glass wall, lid, drop hatch, `WorldLayout.floor` for upper jars), `WorldBuilder.buildFloor`, lids hidden under a jar above (`BaseFloors`), `tests/JarTower.spec.luau`. The static ground plot is **not** switched yet. |

## Still to do

Order matters: the lock guard comes before any fence is removed.

1. **Lock guard for a round jar** (`server/PlotLockGuard`, `WorldView.enforceLocks`). Today "inside" is the whole 80×80 square, so with the jar a non-owner on the bridge or the moat would count as a leaver and walk through the stopper. Inside has to be the jar interior at the character's height (radius < `jarRadius(floor)`) plus the doorway. Write the spec first: a point on the bridge while locked is not a leaver. Keep `Base` as the 80×80 box: `enforceLocks` reads `half` from `Base.Size.X`.
2. **Static ground jar** in `WorldLayout.plot()` (Archer's file). Remove `Fence`, `Gate`, the crate pad grid and the old `LockBarrier` panels. Add the foot, moat, bridge, jar 1 glass wall with the door lintel, `Lid` (`JarLid = 1`), the pads on the ring (turned with `padYaw`), and `LockBarrier` = a doorway collider plus the stopper. Then regenerate `world/*.rbxmx` with `lune run scripts/gen-world`. Today's plot is 82 parts; fence 17, gate 3, pads 16 and barrier 4 are freed.
3. **Move the vat, lock button and sign.** `MergeVat` at (-19, -14) and `LockButton` at (19, -14) collide with the new pad ring. Put the vat inside jar 1 between two pads and the button on the bridge. `Sign` (PlotSigns writes on its Front face) goes on jar 1's label board. `LockSign` follows the button.
4. **What hung on the fence** (mostly Archer's files):
   - `PlotDecor` rebirth bands (trims, pillars, banners, crown) need new spots on the jar.
   - Plot skins (`PlotDecor.applySkin`): the fence tint has nothing left to tint. Retint the cork and trim, and keep the mailbox decor.
   - DexBoard behind the glass at the back. Its trophy slots (`WorldView.trophySpot`, about z 31) land on the glass line, so move them.
5. **Specs and tools that assume the square fence and gate:**
   - Fence and gate: `FenceJoints`, `RanchProps` (fence/gate sections, keep-clear zones), `MeshCollision`, `PlotMesh`, `SlimeRanch`, `WorldBudget` (fence/gate/post counts), `PlotSkins` (fence tint), `WorldPlacement`.
   - Lock: `LockBarrier`, `PlotLockGuard`.
   - Ground and props: `PropWalk`, `Meadow`, `YardDress`, `FloorLayout` (gate ramp), `Ritual`.
   - `PropCollision` inventory counts.
   - Tools: `tools/placement/export.luau`, `tools/render/export.luau`.
   - Docs: `docs/COLLISION.md`.
   - Full list with line numbers: ask a bot to re-run the dependency survey, or see the PR description.
6. **Drop tube.** Server `DropPrompt` on each `DropHatch` (`Constants.DROP_PROMPT_NAME`): refuse while carrying, otherwise move the character to `WorldLayout.dropLanding()`. Add the tube visuals.
7. **Habitats are ON.** The overlays are made for the crate's square deck (`PAD_DECK`). Keep the crate stand mesh until a round cork stand and matching overlays exist, or fit the overlays to the round dish.
8. **Kit meshes** (modeling-kit loop, **no upload without Merijn's OK**): cork stand, door frame and stopper, jar shoulder with ribs, goo ooze ring, drop tube, mascot slime. Until they're uploaded, the primitive stand-ins stay.
9. **Mascot and goo decor** (client, `src/visuals`): mascot size per version, crown at 4, ooze and drips.
10. **Check in a hidden Studio** (`tools/pipeline/pc-watcher/studio_hidden.py`):
    - Buy pads 8 → 9 and the jar appears.
    - A thief walks up the stairs, steals, and walks out.
    - The stopper blocks entry while locked; a leaver walks out.
    - The drop tube refuses carriers.
    - The runtime part count with 8 maxed plots: about 70 parts per upper jar.

Owners (game `CLAUDE.md`): `src/visuals` is Archer's, `src/ui` is Jolt's. This remodel needs both, so agree it with them, or have Merijn sign off, before editing their files.
