# shared/

Cross-game tools and helpers for every Roblox project in this monorepo.

| Path | Purpose |
|------|---------|
| `modeling-kit/` | Headless Blender modeling loop (Claude Code + `iterate.py`, lessons, helpers) |
| *(planned)* `release/` | Release scripts, Saved → smoke → Published helpers |
| `luau/` | Shared Luau systems (inventory + default hotbar UI, save/session lock, core helpers); see `luau/README.md` |
| *(planned)* `guides/` | Process docs (modeling, release, testing) |

Do not put API keys, `.env` files, or credentials here. Scripts read secrets from the environment or `~/.config/roblox-ci.env` at runtime only.
