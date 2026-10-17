# Roblox publishing: Saved -> smoke -> Published (2026-10-15)

Going live needs Merijn's OK and a named publisher ([roblox-release-process.md](roblox-release-process.md) steps 7-8). Until then, upload `Saved` only. Mechanics: [roblox-build-and-publish.md](roblox-build-and-publish.md) §3.

## 1. Saved

Build once and keep the exact file: `/workspace/roblox/gate-out/steal-a-slime-<sha>.rbxl`. Everything below tests and publishes that file.

```sh
. ~/.config/roblox-ci.env                         # never echo the key
tools/livetest/gate.sh /workspace/roblox/gate-out/steal-a-slime-<sha>.rbxl
# = local checks -> upload versionType=Saved -> live.luau gate on that version; prints "saved versionNumber: N"
```

## 2. Smoke on Saved version N

All three must pass:

```sh
python3 /workspace/roblox/live-testing/ci/run.py --version N --out /tmp/run-vN.json
python3 /workspace/roblox/live-testing/ci/run.py tools/livetest/cloud/session.luau --version N --out /tmp/session-vN.json
```

Then the **Studio gate** (visual/client gate in the release process): screenshots at 4 sizes, client layout script, 0 console errors, and the gate owner signs off. Close Studio afterwards (it locks the place, see §5).

## 3. Record the current live version (for rollback)

Before publishing, write down what is live now:

```sh
python3 /workspace/roblox/live-testing/ci/run.py --out /tmp/live-before.json   # no --version = latest published
jq .placeVersion /tmp/live-before.json
```

Note it in the PR and `CHANGELOG.md` as "previous live: vP, file gate-out/steal-a-slime-<old sha>.rbxl".

## 4. Published

Upload the **same file** with `versionType=Published` (Open Cloud can't promote a Saved version):

```sh
printf 'x-api-key: %s\n' "$ROBLOX_OPEN_CLOUD_API_KEY" | curl -sS -H @- -X POST \
  -H 'Content-Type: application/octet-stream' --data-binary @/workspace/roblox/gate-out/steal-a-slime-<sha>.rbxl \
  -o publish-response.json -w 'HTTP %{http_code}\n' \
  "https://apis.roblox.com/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions?versionType=Published"
/workspace/roblox/live-testing/ci/release-check.sh <new live version>
```

Old servers keep the old version until they close; new servers get the new one.

### Rollback

- Re-upload the previous live file (`gate-out/steal-a-slime-<old sha>.rbxl`) with `versionType=Published` (same command), then `release-check.sh` on the new number. This creates a new version with the old content.
- Or in Creator Hub: the place's Version History, Restore version vP (Merijn, or whoever has access).
- Tell SuperBottie what was rolled back and why.

## 5. First hour after publish

- Errors: Creator Dashboard error report / server console for new script errors; re-run `release-check.sh` on the live version.
- Funnel: Creator Dashboard, Analytics, Funnels (onboarding + shop); compare step conversions against the previous version ([roblox-planning.md](roblox-planning.md)). A clear drop or new error, roll back (§4).

## 409 "Server is busy" (Studio lock)

`HTTP 409 ... Save failed. Server is busy` hits Saved and Published alike. Likely cause: an open Studio/Team Create session (or a lingering task) holds a lock on the place.

1. Close Studio on every machine with the place open.
2. Retry with backoff (1, 2, 4, 8 min). **Stop after ~4 tries**; more won't clear it.
3. Still 409: ask Merijn to publish `gate-out/steal-a-slime-<sha>.rbxl` from Studio, then test that live version with `run.py --version <live>` (no `--shim`).
