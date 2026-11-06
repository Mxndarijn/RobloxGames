# Steal a Slime: releases

Newest first. Each entry: the live version, the commit it was built from, what was checked, and what to roll back to.

## Place version 4: first live version in the new experience (2026-11-06)

- **Experience:** universe 10774962286, place 105898249206841 (owned by Forgeborn, still private).
- **Built from:** `main` af74a6262bf4bdde6289c132fb520b525814055c (#733 move to the new experience, #734), clean
  `rojo build default.project.json` (no `ServerStorage.CloudTests`, no `DataStoreMode` attribute). File sha256 starts
  `c8ab6103919bbffe`.
- **Published by:** a bot, on Merijn's OK ("I think now you can create a live version of the game").
- **Version number:** the Saved upload of this file returned version 4 (the same game files were already saved as v4 from
  the #733 branch head), and the Published upload of the same file returned 4 too: Roblox promoted v4 instead of making
  a new version. The Assets API (`GET /assets/v1/assets/105898249206841/versions`) shows v4 `published: true`.
- **Checks before publishing (Saved v4, Memory store):** `lune run scripts/test-parallel` 5281 passed, `test-flags`
  on 5278 / off 5139 passed, selene, stylua, typecheck, `check-place` clean; cloud `smoke.luau` PASS (mesh slimes),
  `live.luau` ok, `terrain_burial.luau` ok (terrain ready, 1018 grounded parts); `tools/assets/check_assets.py` every
  sound, slime package, mesh and image loads.
- **Checks after publishing (live v4):** `smoke.luau` PASS, `live.luau` ok, `terrain_burial.luau` ok.
- **Not checked:** no Studio visual/client gate (screenshots at four sizes, client layout script), no phone, no human
  play-test, audio not heard. The cloud stand-in session (`cloud/session.luau`) fails 8 of 14 scenario checks: the
  same 8 fail on the old experience's last version (276), so it is drift in that harness, not this release.
- **Previous live:** version 1, the blank Baseplate the experience was created with. No game file to restore; to take
  the game down, roll back to v1 in Creator Hub (the place's Version History) or keep the experience private.
- **Next (Merijn):** put the 8 game passes on sale, activate the Slime Club subscription, make the experience public.
