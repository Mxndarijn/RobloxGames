# Steal a Slime: releases

Newest first. Each entry: the live version, the commit it was built from, what was checked, and what to roll back to.

## Place version 6: translations shipped, English still shown (2026-11-07)

- **Experience:** universe 10774962286, place 105898249206841 (Forgeborn, still private).
- **Built from:** `main` 20cc1afaea814ec2b349f97b6080862fb0642d59, clean `rojo build default.project.json` (no
  `ServerStorage.CloudTests`, no `DataStoreMode` attribute). File sha256 starts `7027fa5944909499`.
- **In it:** every player-facing string goes through the Strings catalog and `LocalizationService.Strings` (#742);
  two-line labels for long translated text and 13 short hand-written translations in 17 languages (#743, "A + C").
- **Published by:** a bot, on Merijn's OK ("create a new version once all the translations are merged").
- **Version number:** Saved upload returned 6; the Published upload of the same file returned 6, and the Assets API
  flipped v6 to `published: true` (v5 was the newest published before).
- **Checks before publishing (Saved v6, Memory store):** `lune run scripts/test-parallel` 5367 passed (includes
  `Locale.spec`: `Strings.csv` not stale), `test-flags` on 5364 / off 5225 passed, selene, stylua, typecheck,
  `check-place` clean; `tools/assets/check_assets.py --grant`: audio 88/88, packages 99/99, meshes 772/772, images
  91/91, materials 3/3; cloud `smoke.luau` PASS (mesh slimes), `live.luau` ok, `terrain_burial.luau` ok (1018 grounded
  parts).
- **Localization check (Saved v6 and live v6, Luau Execution):** `LocalizationService.Strings` is a LocalizationTable
  with all 1429 rows of `locale/Strings.csv`, every row has its English source, and an en-us translator returns the
  English text. 13 rows also carry the short translations for 17 languages (by design, #743), so a player whose Roblox
  language is one of those sees those 13 labels translated now; everything else stays English until the Creator Hub
  steps in `docs/translations.md` are done.
- **Checks after publishing (live v6):** `smoke.luau` PASS, `live.luau` ok, `terrain_burial.luau` ok, localization
  check as above.
- **Not checked:** no Studio visual/client gate on this build, no phone, no human play-test, audio not heard; the
  client-side English fallback (`Text.t`) was not run on a real client here (covered by the Lune specs). Creator Hub
  localization (CSV upload, languages, "Use Translated Content") untouched.
- **Previous live:** version 5 (`main` 3b3259d8, file sha256 `0e657fb407e43f6d`). Roll back by restoring v5 in
  Creator Hub (the place's Version History), or re-upload that build as Published.

## Place version 5: broke-player top-up and the snow colour fix (2026-11-07)

- **Experience:** universe 10774962286, place 105898249206841 (Forgeborn, still private).
- **Built from:** `main` 3b3259d88adbd4c2d307abfb2074f0f27b6f2f5a, clean `rojo build default.project.json` (no
  `ServerStorage.CloudTests`, no `DataStoreMode` attribute). File sha256 starts `0e657fb407e43f6d`.
- **In it:** a broke player's cash is topped up to 50, with the toast "Here's 50 cash to get you going!" (#738); every
  snowed floor part gets its colour back after the melt (#740); the asset check also covers the place's own ids (#739).
- **Published by:** a bot, on Merijn's OK ("Yes, publish tonight"), before the ad campaign of 7 November 05:30.
- **Version number:** Saved upload returned 5; the Published upload of the same file returned 5 and the Assets API shows
  v5 `published: true`.
- **Checks before publishing (Saved v5, Memory store):** `lune run scripts/test-parallel` 5290 passed, `test-flags` on
  5287 / off 5148 passed, selene, stylua, typecheck, `check-place` clean; `tools/assets/check_assets.py --grant`:
  audio 88/88, packages 99/99, meshes 772/772, images 91/91, materials 3/3 (the 3 material ids granted as always);
  cloud `smoke.luau` PASS (mesh slimes), `live.luau` ok, `terrain_burial.luau` ok (terrain ready, 1018 grounded parts).
- **Checks after publishing (live v5):** `smoke.luau` PASS, `live.luau` ok, `terrain_burial.luau` ok.
- **Not checked:** no Studio visual/client gate, no phone, no human play-test, audio not heard; the top-up toast and the
  snow melt were not seen on a client. The cloud stand-in session was not re-run (known harness drift, see v4).
- **Previous live:** version 4 (`main` af74a626, file sha256 `c8ab6103919bbffe`). Roll back by restoring v4 in
  Creator Hub (the place's Version History), or re-upload that build as Published.

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
