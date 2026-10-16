# Fountain audit (2026-10-16, archer)

Scope: `models/slime_fountain.py`, `models/slime_fountain_emerge.py`, `models/_slime_fountain_scene.py`, the slide geometry, compared against `models/FOUNTAIN_SIZES.md` and the game code (`games/steal-a-slime/src/visuals/shared/WorldLayout.luau`, `src/shared/MeshAssets.luau`). Base: origin/main 8af9893.

**Verdict: the models match the shipped spec and the game code. No model changes.** The emerge Z sign is correct (Roblox Z = −kit y → **−8.25**). The only gap is in the doc: the slide numbers were never recorded in the shipped section, and the shipped slide is longer than the old draft proposal. FOUNTAIN_SIZES.md now records them (doc only).

## Rebuilt headless (Blender, `iterate.py`)

| Mesh | Tris | Size W x H x D (studs) | nm | Doc / MeshAssets | Match |
|---|---|---|---|---|---|
| slime_fountain | 6814 | 54.45 x 43.316 x 63.851 | 0 | 6814, 54.45 x 43.3 x 63.85 / `{54.45, 43.316, 63.851}` | yes |
| slime_fountain_emerge | 640 | 19.436 x 12.798 x 11.353 | 0 | 640, 19.4 x 12.8 x 11.4 / `{19.436, 12.798, 11.353}` | yes |

The rebuilt FBXs are the same size in bytes as the committed ones (only the FBX timestamp and the stats paths differ), so `out/` matches the scripts. The rebuild was reverted and not committed.

Printed by the scripts:
- `SILO_AXIS from mesh bbox centre: x -6.52, y 7.75` (kit); bbox x −20.7..33.7, y −39.7..24.2. Doc: (−6.52, 7.75). WorldLayout `fountainCentre = {6.52, h/2, 7.75}` (Roblox) puts the silo axis at the world origin. ✔
- `EMERGE_OFFSET kit (-11.20, 8.25, 18.94); Roblox (-11.20, 18.94, -8.25)`. Doc: same. WorldLayout `emergePos = fountainCentre + {-11.2, 18.94, -8.25}`. ✔
- `SLIDE length 232.9 studs, drop 35.7, avg grade 9.7 deg, max 14.2 deg, end r 35.5`.

## Emerge offset Z sign: VERIFIED (−8.25 is right)

1. **FBX axes (read from the binary FBX, not assumed).** Both FBXs store raw vertices in kit space (z-up, z min 0) with Model `Lcl Rotation = (−90, 0, 0)` and GlobalSettings Up = +Y, Front = +Z, Coord = +X (right-handed, Y-up, the same as Roblox). Rx(−90°) maps (x, y, z) → (x, z, −y), so **Roblox (X, Y, Z) = (kit x, kit z, −kit y)**: the same mapping as the scripts' `rbx()`, the doc and WorldLayout's `SLIDE_PATH` (`{p[1], z, -p[2]}`).
2. **End to end against the game placement.** Applying that rotation to the raw FBX verts and placing each mesh's bbox centre where WorldLayout puts it:
   - fountain world bbox X −20.70..33.74, Z −24.18..39.68 (silo axis at the origin, slide mouth at +Z as WorldLayout's comment says);
   - with Z = **−8.25**: the nearest emerge vertex to the game slide head point (first kit path point with r > 12.5 = Roblox X/Z (−12.55, −4.42)) is **0.00** studs away (SlimeD's base), and **0.16** from the silo axis (SlimeA in the crown);
   - with Z = +8.25 (flipped): 14.75 and 14.05 studs off. So the minus sign is right.
3. **Visual:** `fountain_emerge_check_robloxlook.png`, both shipped FBXs re-imported and the emerge mesh placed at the documented offset: three slimes sit in the goo crown and one at the slide head.

Caveat (unchanged from the doc): this proves the FBX data and the game math agree. Studio's importer is assumed to honour the FBX node rotation like every other kit mesh, and the uploaded fountain already depends on that. The emerge mesh is not uploaded yet (`MeshAssets` has no meshId), so one look in Studio after the upload is still worth doing.

How the game consumes it: `WorldLayout.luau` `volcano()` → `EmergeMesh` slot at `fountainCentre + (-11.2, 18.94, -8.25)`, size `{19.436, 12.798, 11.353}`, hidden until the mesh id is filled. **Consumed correctly; no code change needed.**

## Against the FOUNTAIN_SIZES proposal table

| Item | Proposal | Shipped | Status |
|---|---|---|---|
| Fountain footprint | Ø 16–28 (r ≤ 14) | silo plinth r 13.1, eave r 13.4 (`FOUNTAIN_DIAMETER = 28`) | ✔ |
| Fountain height | 28–48 (fountain ~36) | 43.3 (goo crown top); emerge slimes reach 47.0 | ✔ (in range) |
| Slide turns | 0.85–2.2 | 1.75 | ✔ |
| Slide radius | r ~8 → ~42 | 4.8 (starts inside the basin) → helix 17.2 → 35.5 | ✔ end inside the landing ring 34..62 |
| Slide length | ~55–120 | **232.9** (plan length; the helix at r 17.2 carries most of it) | ✘ vs the draft; doc updated, model kept (see below) |
| Slide width | 7 (6.5–8) | 7.0 outer (HW 3.5), 5.8 inner; mouth flares to 8.4 over the last 10 % | ✔ (the mouth flare is deliberate so riders spill out) |
| Max decor axis | 64 | 63.85 | ✔ (0.15 to spare) |
| Tris | hero up to ~6000 (THEME) | 6814 (+640 emerge) | ~14 % over the THEME guideline; under the 10k kit fail; already accepted in the doc |

Why the slide length stays: `WorldLayout.SLIDE_PATH` is a port of this exact spiral (same TURNS/R/Z constants) and is the live ride path, so shortening the mesh would mean a game-code change too. 1.75 turns at r 17.2 can't fit in 120 studs. The draft table predates the polished mesh, so the doc was out of date, not the model. FOUNTAIN_SIZES.md now lists the shipped slide numbers under "Shipped fountain mesh".

`_slime_fountain_scene.py` (preview only): it rebuilds `sf.build()` to get the silo-axis offset and places the FBX at (C.x, C.y, 0), the same maths as SILO_AXIS. ✔ No sizes of its own beyond the plaza r 55 / landing ring 34..62, which match the doc.

## Outcome

Fountain + slide match, so this went to **branch 2b**: two new plaza/farm props (`ranch_sunflower_patch`, `ranch_log_pile`). See their sheets and `_rounds.md` files.

## Studio check attempt (2026-10-16 ~08:45 CEST, archer)
- Route: Claude Code on Merijn's PC with the Roblox_Studio MCP (guides/roblox-live-testing.md). The MCP connected, but `get_studio_state` returned "Place is not open" (Studio sat on its start screen).
- Read-only run stopped there. Nothing opened, saved, imported or published. The emerge offset (-11.20, 18.94, -8.25) after Roblox import and the prop scale vs rig are **still unverified in Studio**. Next step: open the place in Studio, then rerun the read-only check.
