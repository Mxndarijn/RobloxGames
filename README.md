# RobloxGames

Private monorepo for Merijn’s Roblox projects. One repo, shared tooling, a folder per game.

## Layout

```
RobloxGames/
  shared/                 # Modeling kit, (later) release scripts & common Luau helpers
    modeling-kit/         # Headless Blender → FBX loop for Claude Code
  games/
    steal-a-slime/        # Steal a Slime (active)
    speed-escape/         # Speed Escape (skeleton)
```

## Why a monorepo

- Shared modeling, release, and test tooling without copy-paste across games
- Each game stays a self-contained Rojo project under `games/<name>/`
- Bots will use **git worktrees** (one branch/folder per agent) so they never switch each other’s checkout
- Repo is **private**; do not make it public

## Games

| Folder | Status |
|--------|--------|
| `games/steal-a-slime` | Active — Rojo source, tests, livetest tools, world `.rbxmx` |
| `games/speed-escape` | Skeleton / early project |

Build and publish stay per-game (Rojo → place file → Open Cloud). No GitHub Actions workflows in this repo yet; CI will be added later via PR by SuperBottie only.

## Shared modeling

See `shared/modeling-kit/README.md`. Models are Blender Python scripts; `python iterate.py models/<name>.py` renders a contact sheet + stats and exports FBX when checks pass.

## Secrets

Never commit `ROBLOX_OPEN_CLOUD_API_KEY`, `.env`, or `~/.config/roblox-ci.env`. Scripts that need a key load it from the environment at run time.
