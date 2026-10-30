# Guides

How we build, test and release the games in this repo. Copied from the team's box guides (`/workspace/guides`) on 2026-10-18; this folder is now the source of truth. Code comments that say `/guides/<name>.md` mean `guides/<name>.md` here.

## Start here
- [ai-guidebook.html](ai-guidebook.html): the AI Game Guidebook. House rules, the game kit, UI, 3D models, world placement, sound and verifying, with what Merijn and Niels approved and what needed rework. Open it in a browser.
- [roblox-pipeline-index.md](roblox-pipeline-index.md): map of the whole pipeline
- [task-brief.md](task-brief.md): how to write a task brief

## Building
- [roblox-building.md](roblox-building.md): worktrees, Rojo files, done criteria
- [roblox-toolchain-linux.md](roblox-toolchain-linux.md): toolchain on Linux
- [roblox-planning.md](roblox-planning.md): from funnel data to a roadmap
- [roblox-world-labels.md](roblox-world-labels.md): BillboardGui / SurfaceGui sizing, view distance, phone rules, and the registry of every label. Read before adding one.

## Models and assets
- [roblox-modeling-process.md](roblox-modeling-process.md), [roblox-modeling-kit.md](roblox-modeling-kit.md), [roblox-modeling-weak-spots.md](roblox-modeling-weak-spots.md)
- [roblox-assets.md](roblox-assets.md), [roblox-asset-uploads.md](roblox-asset-uploads.md)
- In the kit: [PROCESS](../shared/modeling-kit/PROCESS.md), [THEME](../shared/modeling-kit/THEME.md), [LESSONS](../shared/modeling-kit/LESSONS.md)

## Testing and review
- [roblox-automated-tests.md](roblox-automated-tests.md), [roblox-cloud-server-test.md](roblox-cloud-server-test.md), [roblox-live-testing.md](roblox-live-testing.md)
- [live-server-probes.md](live-server-probes.md): run and write a probe on a real server, and report it honestly
- [roblox-ai-testing-rules.md](roblox-ai-testing-rules.md), [roblox-usability-playtest.md](roblox-usability-playtest.md), [roblox-screenshots.md](roblox-screenshots.md)
- [roblox-critical-review.md](roblox-critical-review.md), [claude-code-review-artifacts.md](claude-code-review-artifacts.md), [pr-watch.md](pr-watch.md)
- Steal a Slime: [COLLISION](../games/steal-a-slime/docs/COLLISION.md), [PVP](../games/steal-a-slime/docs/PVP.md), [PLAYTEST](../games/steal-a-slime/PLAYTEST.md)
- PR gate and Studio watcher: [pr-gate](../tools/pr-gate/README.md), [pc-watcher](../tools/pipeline/pc-watcher/README.md)

## Releasing
- [roblox-release-process.md](roblox-release-process.md), [roblox-build-and-publish.md](roblox-build-and-publish.md), [roblox-publishing.md](roblox-publishing.md)
- Current pipeline: [docs/release-pipeline.md](../docs/release-pipeline.md), [steal-a-slime pipeline](../games/steal-a-slime/tools/pipeline/README.md)

## Current rules (2026-10-18)
- Auto-publish is off. Releases only go out after Merijn approves them at the 12:00 / 19:00 release check.
- Non-visual work runs in Claude Code (Sonnet 5.5). Bots review renders and frames themselves.
- Before starting a feature, ask SuperBottie whether it's already built. Remove your worktree once your PR merges.
- Players are never teleported out of a locked base; the lock only blocks entering.
- Before a publish, a terrain probe on a real server checks that nothing sinks into the ground (#309).
