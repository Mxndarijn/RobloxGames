# Roblox pipeline index (2026-10-15)

One-page map of the Roblox guides under `/guides` (same files as `/workspace/guides`). Paths below use `/guides/…`. Only guides that exist are listed.

## Pipeline (Merijn’s release flow)

| Step / topic | Guide | Notes |
|---|---|---|
| **Planning** (pipeline step 1) | [roblox-planning.md](roblox-planning.md) | Funnel → roadmap. Gojo. |
| **Building / publish mechanics** | [roblox-build-and-publish.md](roblox-build-and-publish.md) | Rojo + Lune + Open Cloud Saved upload. |
| **Release process** (branch → gate → Merijn OK) | [roblox-release-process.md](roblox-release-process.md) | Ordered steps, visual/client gate, roles. |
| **Critical review** (pipeline step 7) | [roblox-critical-review.md](roblox-critical-review.md) | Independent Gojo review before Merijn OK. |
| **Cloud / live testing** | [roblox-live-testing.md](roblox-live-testing.md) | Static render, Luau Execution, cron CI, Saved gate. |
| **Screenshots** | *(no separate guide)* | Covered in [roblox-live-testing.md](roblox-live-testing.md) §1 (static render) and [roblox-critical-review.md](roblox-critical-review.md) (PC/phone/tablet before/after). Release-process names the Studio screenshot gate. |
| **Playtest** | *(no separate guide)* | Studio / client gate in [roblox-release-process.md](roblox-release-process.md); cloud playtest loop in [roblox-live-testing.md](roblox-live-testing.md) §4. |
| **Assets (Open Cloud meshes)** | [roblox-assets.md](roblox-assets.md) | FBX/glTF upload, MeshId, Rojo use. |
| **Modeling process** (official) | [roblox-modeling-process.md](roblox-modeling-process.md) | Claude Code + iterate.py loop; report limits to SuperBottie. |
| **Modeling weak spots** | [roblox-modeling-weak-spots.md](roblox-modeling-weak-spots.md) | Blind/slow steps; empty “Replacement (Merijn)” lines. |
| **Modeling kit** (pointer) | [roblox-modeling-kit.md](roblox-modeling-kit.md) | Kit paths, scale/upload notes. Source of truth for bots: `/workspace/roblox/modeling-kit`; monorepo copy: `RobloxGames/shared/modeling-kit`. |
| **AI testing rules** | [roblox-ai-testing-rules.md](roblox-ai-testing-rules.md) | What Roblox’s rules allow for automated testing of our own game. |
| **Toolchain (Linux box)** | [roblox-toolchain-linux.md](roblox-toolchain-linux.md) | Rojo, Lune, Rokit, Blender, no sudo. |

## Tests (broader / other repos)

| Topic | Guide |
|---|---|
| Schiet + MnLib test guidelines | [testing-guidelines.md](testing-guidelines.md) |
| Frontend tests with Claude Code | [frontend-tests-with-cc.md](frontend-tests-with-cc.md) |

Roblox game unit/integration tests live in each game’s `tests/` and are driven by the build/release guides above; there is no separate “Roblox unit tests” guide yet.

## Related non-pipeline Roblox docs

| Topic | Guide |
|---|---|
| Schiet / MnLib env (not Roblox) | [schietvereniging-mnlib-environment.md](schietvereniging-mnlib-environment.md) |
| Verification skill restatement | [schietvereniging-verification-skill.md](schietvereniging-verification-skill.md) |

Team notes (not guides): `/workspace/team/roblox-feasibility.md`, `/workspace/team/roblox-github-proposal.md`.

## Modeling kit locations

- Working kit (local git, proof sheets): `/workspace/roblox/modeling-kit`
- Monorepo shared copy (PR into `Mxndarijn/RobloxGames`): `shared/modeling-kit/`
- Official process: `/guides/roblox-modeling-process.md`
