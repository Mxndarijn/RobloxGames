# Live server probes (Open Cloud Luau Execution)

Check one behaviour of a published place version on a real Roblox server, with no Studio. Setup, rules and limits of the task itself are in [roblox-cloud-server-test.md](roblox-cloud-server-test.md); read that first. This guide covers running a probe, writing one, what it can honestly claim, and how to report it.

## Run a probe

```sh
cd games/steal-a-slime
OUT=<OUT_PATH>.json tools/livetest/cloud/run.sh <script.luau> <PLACE_VERSION>
```

- `ROBLOX_OPEN_CLOUD_API_KEY` is required. Set it in the shell; never print it, put it in argv, or commit it.
- `UNIVERSE_ID`, `PLACE_ID`, `TIMEOUT` and `OUT` are optional. The runner reads them, and the defaults point at our test place. Give every run its own `OUT`; two runs sharing a path overwrite each other.
- `<PLACE_VERSION>` is a Saved version of the place. Leave it out and the runner uses the latest published one, so always pass it.
- `OUT` saves `{task, state, error, logs, result}`. `result` is the script's returned JSON string, decoded.
- Exit codes: `0` task completed and the result has no `ok=false`; `1` the result says `ok=false`; `2` task failed, HTTP error, or no API key.

A probe script that returns `pass`/`fail` counts but no `ok` field exits `0` even when `fail > 0`. Read `fail` in the saved file; don't trust the exit code alone.

## Write a probe

The script runs once inside one server for the place version. The place's own Scripts do not start and nothing is running when it begins. It must boot what it needs, run its checks, and `return` a JSON string (`HttpService:JSONEncode(...)`). Anything else is not decoded into `result`.

To use the game's server code, require the server modules and replay the boot, as `tools/livetest/cloud/live.luau` does: set `DataStoreMode` to `Memory` first (never touch real DataStores), require the modules under `ServerScriptService.Server`, then drive the game loop yourself.

Minimal skeleton:

```lua
--!nocheck
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local t0 = os.clock()
local pass, fail, assertions = 0, 0, {}
local function check(name, ok, detail)
	if ok then pass += 1 else fail += 1 end
	table.insert(assertions, { name = name, pass = ok == true, detail = tostring(detail or "") })
end

workspace:SetAttribute("DataStoreMode", "Memory") -- before anything boots
local diag, errors = {}, {}

local ok, err = pcall(function()
	local Server = ServerScriptService:WaitForChild("Server")
	-- require modules and replay the boot here, as live.luau does
	check("server modules load", Server ~= nil, "")
	-- ... scenario: set up state, act, then check() what changed
end)
if not ok then
	table.insert(errors, tostring(err))
end

return HttpService:JSONEncode({
	placeVersion = <PLACE_VERSION>, -- or read it from the game
	pass = pass, fail = fail, errors = errors,
	assertions = assertions, diag = diag,
	elapsed = os.clock() - t0,
})
```

Wrap each scenario in `pcall` so one crash is recorded as a failed check instead of losing the whole result. Put the numbers behind a judgement (distances, flags, config values read) in `diag`, so a reader can re-check the verdict.

## What a probe can and can't test

A task server has no real Players, no input, and no physics stepping: parts don't fall, `Stepped` doesn't fire, and velocities don't integrate. So:

- **Players:** build stand-in characters with `Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)` and pass a table with `UserId`, `Name`, `DisplayName` and `Character` to the code that expects a Player. Record in `diag` which kind of rig you got.
- **Movement and knockback:** replace the code that would move or push a character with a recorder, and assert on what it was asked to do (target, direction, length), not on where anything ended up.
- **Contact and barriers:** raycasts honour collision groups. Cast with the same `CollisionGroup` the character would have as a stand-in for "would this touch", and cast both ways across the barrier.
- **Pure rules and server state** (who owns what, cooldowns, carry state, events) can be tested for real.

Be exact about what ran:

- Label a check **PARTIAL** when the real thing was only approximated (stand-in rig, recorder, raycast for contact). Say what the stand-in was.
- List what was not covered (real input, real movement, real client effects, multi-client timing) next to the verdict.
- Never report PASS for something the runner couldn't test. A check that skipped its body, or whose setup failed, is not a pass.

## Probe JSON layout

Saved files have this shape. Fields are generic; a probe may add its own to `result` or `diag`.

```json
{
  "task": "<TASK_PATH>",
  "state": "COMPLETE",
  "error": null,
  "logs": [],
  "result": {
    "placeVersion": 0,
    "pass": 2,
    "fail": 0,
    "errors": [],
    "elapsed": 1.4,
    "assertions": [
      { "name": "control: far target is not hit", "pass": true, "detail": "hit=false reason=nothing in reach" },
      { "name": "HIT: near target is hit", "pass": true, "detail": "hit=true" }
    ],
    "diag": { "rigKind": "R15 CreateHumanoidModelFromDescription" }
  }
}
```

- `task`, `state`, `error`, `logs`: the Open Cloud task path, its final state (`COMPLETE`, `FAILED`, `CANCELLED`), an error object or `null`, and log lines from the server.
- `result.pass` / `result.fail`: counts of passing and failing assertions. `result.errors`: script errors caught during the run. `result.elapsed`: seconds.
- `result.assertions[]`: one entry per check with `name`, `pass`, and a short `detail`. Include controls (cases that must not trigger) next to the positive case.
- `result.diag`: evidence behind the verdicts, such as config values, distances, rig kind and which stand-ins were used.
- Extras seen in practice: `standIns`, `counts`, `found`, `afterBoot`.

Check `state == COMPLETE`, `fail == 0` and `errors` empty before calling anything a pass.

## Reporting

Report one line per check with a status, then the evidence:

- **PASS**: really exercised, all assertions passed, no errors.
- **FAIL**: an assertion failed or the code under test is wrong. Quote the assertion name and `detail`.
- **PARTIAL**: ran, passed, but a stand-in replaced part of the real thing. Name the stand-in and what remains untested.
- **BLOCKED**: couldn't run (no key, task failed, boot error, version missing). Say why; don't count it as a pass or a fail.

Evidence for each line: the place version, `pass`/`fail` counts, and the `OUT` file the result came from. Example:

```
bat hit: PARTIAL (<PLACE_VERSION>, 12 pass / 0 fail, <OUT_PATH>.json). Stand-in rig; knockback checked via recorder, not real movement.
```
