# RobloxGames: notes for Claude

Monorepo for Merijn's Roblox games. Layout and rules: [README.md](README.md). How we build, test and release: [guides/README.md](guides/README.md). Each game and the modeling kit have their own `CLAUDE.md` with hard rules; read the one for the area you work in (`games/<name>/CLAUDE.md`, `shared/modeling-kit/CLAUDE.md`).

## Get the task done: use every tool you have

You may use whatever helps finish the task well, without asking first:

- **Subagents.** Use the Agent tool for broad searches, research and independent pieces of work. Run independent agents in parallel (one message, several calls). Keep design decisions and the final check yourself.
- **Roblox Studio MCP** (`mcp__Roblox_Studio__*`). Inspect the game tree, read scripts, run Luau, start/stop playtests, read the console and take screenshots to check your work in the real engine. Generate or search assets, meshes, materials and textures when the task needs them.
- **Blender.** Build and fix models with the headless Blender loop in [shared/modeling-kit](shared/modeling-kit/README.md) (bpy script → contact sheet → FBX). Always look at the rendered sheet before calling a model done. Blender is not on `PATH` on this Windows machine; find the install or ask Merijn for its path if a step needs it.
- **Browser** (built-in browser pane) for Roblox docs, the Creator Dashboard and other references.
- **Scripts and CLIs**: Rojo, Lune, selene, stylua, Python, ImageMagick, ffmpeg, `gh`.

Verify in the real game where you can (Studio playtest, screenshots, the tests in each game's `CLAUDE.md`), and report honestly what you could not check.

The hard rules still win over "get it done": no production DataStores, no real publish or upload without Merijn's OK, no secrets printed or committed (see the per-area `CLAUDE.md` files).

## Git: one branch per feature

Every feature or fix gets its own branch, cut from an up-to-date `main`:

```sh
git checkout main
git pull origin main
git checkout -b <type>/<short-slug>   # e.g. feat/slime-shop, fix/fountain-collision
```

- Never commit straight to `main`. If you are on `main` when you start a task, update it and branch first.
- One feature per branch; start a new branch (again from a freshly pulled `main`) for the next feature.
- Before opening a PR, bring the branch up to date with `main` (`git pull origin main` or rebase) and fix any conflicts.
- Commit messages follow the existing style: `feat(<area>): ...`, `fix(<area>): ...`, `docs: ...`.
- Stage your own files by path; other bots may share the checkout. Don't `git push` or open a PR unless the task or Merijn asks for it.
