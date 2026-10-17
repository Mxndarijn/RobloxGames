# Roblox release process (steal-a-slime, speed-escape)

Date: 2026-10-15. Status: draft. Merijn decides the open items.

## Saved versions (verified)

- Roblox's official place-publishing guide only documents `versionType=Published`:
  https://create.roblox.com/docs/cloud/guides/usage-place-publishing
- Endpoint: `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions`.
- The key needs the `universe-places` scope with Write on the experience. Send it in the `x-api-key` header.
- The response is `{"versionNumber": N}`.
- The official reference page lists `versionType`, but not its allowed values.
- `versionType=Saved` saves a version without publishing it live.
  It is **not** in Roblox's official docs.
  Only a third-party SDK documents it:
  https://mintlify.wiki/AlroviOfficial/RoZod/api/opencloud/universes
  ("Or 'Saved' to save without publishing").
- So `Saved` is unofficial and undocumented. It could change or stop working.

Our own evidence:

- `/workspace/roblox/gate-progress.txt` shows the team's gate is in use.
  The gate is `steal-a-slime-b0/tools/livetest/gate.sh`:
  upload Saved, then run a Luau Execution live check on that version, then upload Published only if it passes.
- But every Saved upload in that file failed.
  There were 14 attempts on 2026-10-15, 10:14-10:32. All got HTTP 409 "Server is busy".
- So the file records no completed Saved upload. It also records no Luau Execution run on a Saved version.
- The latest Luau Execution run (ci/runs history `20261015-101608`) ran against the live version.
  It FAILED: SlimeMesh boot error, and the plot signs were empty.
- Open Cloud cannot promote a Saved version to live.
  `gate.sh` re-uploads the same file as Published.

## Steps (in this exact order)

1. **Branch + PR.** Open the PR with the bot's own GitHub identity.
   Another bot reviews with its own identity (Claude Code review). Merijn merges.
   Never push to main. Never merge. Keep the PR body short. (RULES.md rules 2, 6, 12.)
2. **Local checks.** Run `lune run tests`, `selene`, `stylua --check`, `lune run scripts/check-place.luau`, and the luau-lsp type check `scripts/typecheck.sh` (steal-a-slime; tools pinned in `rokit.toml`, `rokit install`).
   Also run `rojo build` and the map build/check (`lune run src/visuals/tools/build-map.luau`, then `check-map.luau`; steal-a-slime). All must pass.
3. **Visual changes only.** Make a Blender before/after render with
   `/workspace/roblox/live-testing/render_quickwins.py`. Attach both images to the PR.
4. **Publish to the test place.** Until a test place exists, upload a private Saved build on the live place
   (`versionType=Saved`; see the caveat above). Never Published at this step.
5. **Check that version.** Run `/workspace/roblox/live-testing/ci/release-check.sh <version>`.
   It calls `run.py` (Luau Execution). It publishes nothing.
   Never use `--shim`. It is for diagnosis only and can never pass as a gate.
6. **Big releases only.** Studio MCP playtest on Merijn's PC.
   *Update 2026-10-15 (gap analysis, `/workspace/roblox/testing-gap-analysis.md`):* proposed for **every** release, and it must finish before step 8. Steps 2–5 are server-only and can't see the client. v15 went live at 13:01, but the Studio playtest that found its UI bugs ran 13:18. See "Visual/client gate" below. Merijn decides.
7. **Merijn gives OK.** Proposed: only after the visual/client gate owner has signed off in the PR.
8. **Publish live.** Use `versionType=Published` with the same file you tested.
   Record the response in `publish-response.json`.
   Add an entry to `CHANGELOG.md`. It does not exist yet in steal-a-slime-b0, so create it in the PR.
9. **Check live.** Run `release-check.sh` again against the new live version number.
10. **Release note.** Send a short release note to SuperBottie (not Merijn; RULES rule 5).

## Visual/client gate (proposed 2026-10-15, Merijn decides)

Why: every automated check runs on the server or on state only. Lune, run.py and the cloud stand-in session run no client, no PlayerGui and no renderer. The Blender renders use Blender's own sky and leave out GUIs, Beams and textures. Details: `/workspace/roblox/testing-gap-analysis.md`.

- **Owner.** Each release names one visual/client gate owner in the PR (proposed: Jolt, with Archer as backup). The owner runs the gate or gets it run, and signs off.
- **Static checks (add to step 2, `check-place`).**
  - Every Beam, Decal, Texture and ParticleEmitter has a non-empty `Texture`.
  - Every MeshPart has a `MeshId`.
  - Lighting has a Sky, or NightSky creates one.
  - Every sign or stand that names an action (CLAIM/BUY/FREE PLOT) has an enabled ProximityPrompt.
- **Copy check (step 2, Lune).** Player-facing strings use Config numbers and match the CONTRACT phrasing, for example "Speed Coil also helps while carrying". Update `PLAYTEST.md` in the same PR.
- **Screenshot gate (step 6, Studio MCP).**
  - Play to fixed points: spawn, left nav, Shop, Goals, Upgrades, Rebirth, Dex, carrying with the tutorial showing, the Legendary banner, the FREE PLOT stand, then day and night.
  - Capture each point at 1920×1080, 1366×768, 1024×768 and 844×390 (phone, with the device emulator).
  - Save to `usability/v<N>-studio/`, then do a human or vision pass against the checklist.
  - `screen_capture` leaves out BillboardGuis and prompts, so check their text with `execute_luau`.
  - Close Studio afterwards, because it locks the place (409).
- **Client layout script (step 6, `execute_luau` in Play, at each size).** It fails on:
  - a visible GuiObject outside `CurrentCamera.ViewportSize`;
  - `TextFits == false` on a label that is neither scaled nor wrapped;
  - a ScrollingFrame whose content is larger than its window but can't scroll, or whose first or last row is clipped;
  - visible panels that overlap where the lower ZIndex/DisplayOrder panel has an enabled button.
- **Blender renders** help with world geometry only. They are not evidence for sky, lighting, beams, textures or UI.

### Release checklist
- [ ] Gate owner named in the PR
- [ ] Local checks green, including the asset and copy checks
- [ ] Saved version: `release-check.sh` green (run.py) and cloud session green
- [ ] Screenshots at 4 sizes for every point, attached
- [ ] Client layout script: 0 off-screen, 0 unfitted text, 0 clipped lists, 0 overlaps
- [ ] Day and night shots: Sky present, signs readable, no untextured beams
- [ ] Play console: 0 script errors
- [ ] Gate owner signs off, then Merijn OK, then publish (step 8), then check live (step 9)

## No scheduled playtests

- There are no scheduled or automatic playtests. This is Merijn's decision.
- The `7,37` cron for `ci/cron.sh` was disabled on 2026-10-15.
- `release-check.sh` is run by hand, at steps 5 and 9 only.

## Roles

- **Phoenix:** lead, features, integration and publish.
- **Archer:** visuals.
- **Jolt:** UI/client.
- **Gojo:** review + CI.
- **SuperBottie:** coordination.

Note: RULES.md rule 15 says Archer and Jolt are overflow-only.
In that case Gojo absorbs Archer's work and Phoenix absorbs Jolt's.
SuperBottie should confirm which applies.

## Waiting on Merijn

- Create a test place. We need its universe ID and place ID.
- Open Cloud key scopes for the test place.
- Who may publish live.
- What counts as a "big release" (step 6). Proposed: make step 6 apply to every release (see Visual/client gate).
- Who is the visual/client gate owner per release.

## Secrets

- The Open Cloud key comes from the environment or `~/.config/roblox-ci.env`.
- Never print it. Never commit it.

## Open Cloud upload returns 409 Server is busy

**Symptom:** the place upload fails with:

```
HTTP 409 {"code":"Conflict","message":"Save failed. Server is busy and unable to process your upload request. Please try again in a couple minutes."}
```

It hits `versionType=Saved` and `versionType=Published` alike. On 15 Oct 2026 it persisted for over an hour, even after Studio was closed.

**Likely cause:** a lock on the place held by a Team Create/Studio session, or a lingering Luau Execution task.

**What to do:**
1. Stop retrying after ~4 attempts with backoff; more retries won't clear the lock.
2. Ask Merijn to publish the built place from Studio: `/workspace/roblox/gate-out/steal-a-slime-<sha>.rbxl`.
3. Then test against the live version, without `--shim`:
   `python3 /workspace/roblox/live-testing/ci/run.py --version <live>`

## Related guides

- [roblox-building.md](roblox-building.md): worktree per agent, Rojo-as-files, done = Lune + cloud + rhr.
- [roblox-cloud-server-test.md](roblox-cloud-server-test.md): Luau Execution on Saved versions, parallel runs.
- [roblox-publishing.md](roblox-publishing.md): Saved -> smoke -> Published, rollback, first hour, 409.
- [roblox-asset-uploads.md](roblox-asset-uploads.md): Assets API upload, generated ids, FBX.
- [roblox-modeling-process.md](roblox-modeling-process.md): making meshes with the modeling kit.
