# WalkCheck

Drops wild slimes at awkward spots in a real Studio playtest and records how they walk back to the lane
(contract/slime-walk.md). It is the baseline for the slime walk-back rework: run it before and after a change and
compare the reports.

```sh
python tools/walkcheck/run.py --studio <your place name> [--cases id,id] [--out DIR] [--no-shots]
python tools/walkcheck/run.py --studio x --report-only --out DIR   # rebuild report.html from DIR/results.json
```

Needs a Studio of your own in play mode on the memory store (build a copy of the project with Workspace attribute
`DataStoreMode = "Memory"`, open it with `tools/pipeline/pc-watcher/studio_hidden.py open`), reachable over StudioMCP.
Mute the playtest first (root `CLAUDE.md`).

## How a case runs

1. `arm.server.luau` (Server) resolves the spot, builds any test walls and waits for the slime a player carries
   (`Carrying` attribute) to turn up `Wild` again (found by `SlimeId`: the model is rebuilt when it changes hands).
2. `drop.client.luau` (Client) tops up cash and skips the tutorial through the admin menu's test-save commands,
   grabs the nearest lane slime it has not dropped before (the game hides a dropped slime's prompt from whoever
   dropped it), carries it to the spot and sends the real `Drop` request. Runs as a background job that run.py polls.
   How the character moves, and why:
   - It glides at 12 studs/s. SlimeGuard kicks a player who teleports while carrying (limit 14.4 studs/s).
   - It moves by physics: velocity toward the goal each frame, platform-standing, its parts not colliding so it
     passes through walls. An anchored root moved on the client never reaches the server, and per-frame CFrame
     writes are undone by the physics step.
   - Collisions are put back afterwards, or the character falls through the floor and the game's rescue moves it.
   - A newer run stops an older one that broke off (`_G.WalkCheckRun`).
3. `cam.client.luau` tries to point the camera at the slime for one screenshot mid-walk. Studio resets the camera
   after each script, so most shots show the default follow camera; the report's top view is the main evidence.
4. The recorder samples the slime every Heartbeat until it has been on the lane for 1.5 s (or `seconds`, default 60);
   `collect.server.luau` returns the result plus the solid parts round the path.

`common.luau` is prepended to every script with `local CASE = {...}` above it.

## Cases (`cases.json`)

A spot is `at = {x, z}` (with `top`, the height the ground ray starts from), `behind = "Map/..."` (past that part on
the side away from the lane, `gap` studs out) or `lane = share, out = studs` (off the lane, away from the fountain).
`box = r` puts four walls round the spot, `blockAt = s` drops a wall 6 studs ahead of the slime `s` seconds in.

## Checks

| Check | Fails when |
|---|---|
| inside | a solid part is within 60% of the body's half size on more than 2% of frames |
| floats | more than 10 frames over 1 stud above the ground under it, off the lane, after the fall |
| back | it never reached the lane (within `ParadeLane.HALF_WIDTH`) and stayed |
| detour | warn only: walked more than 3x the straight line to the nearest lane point |

Output: `DIR/results.json`, `DIR/report.html` (a top view per case: solid parts, lane, the path coloured by check)
and `DIR/<case>.jpg`. `out/` is gitignored. Dev tool only: nothing in the game requires it.
