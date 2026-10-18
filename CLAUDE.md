# RobloxGames: notes for Claude

Monorepo for Merijn's Roblox games. Layout and rules: [README.md](README.md). How we build, test and release: [guides/README.md](guides/README.md). Each game and the modeling kit have their own `CLAUDE.md` with hard rules; read the one for the area you work in (`games/<name>/CLAUDE.md`, `shared/modeling-kit/CLAUDE.md`).

## Shared code first

Game-agnostic systems live in [shared/luau](shared/luau/README.md): inventory with a default, overridable hotbar UI, session-locked saves, save migrations, rate limiting, formatting, seeded random. Before building one of these in a game, use or extend the shared module. When a system you build in a game has nothing game-specific in it, move it to `shared/luau` following [its rules](shared/luau/CLAUDE.md) (pure core plus thin Roblox adapter, injected dependencies, overridable defaults, Lune specs).

## Get the task done: use every tool you have

You may use whatever helps finish the task well, without asking first:

- **Subagents.** Use the Agent tool for broad searches, research and independent pieces of work. Run independent agents in parallel (one message, several calls). Keep design decisions and the final check yourself.
- **Roblox Studio MCP** (`mcp__Roblox_Studio__*`). Inspect the game tree, read scripts, run Luau, start/stop playtests, read the console and take screenshots to check your work in the real engine. Generate or search assets, meshes, materials and textures when the task needs them.
- **Blender.** Build and fix models with the headless Blender loop in [shared/modeling-kit](shared/modeling-kit/README.md) (bpy script → contact sheet → FBX). Always look at the rendered sheet before calling a model done. Blender is not on `PATH` on this Windows machine; find the install or ask Merijn for its path if a step needs it.
- **Browser** (built-in browser pane) for Roblox docs, the Creator Dashboard and other references.
- **Scripts and CLIs**: Rojo, Lune, selene, stylua, Python, ImageMagick, ffmpeg, `gh`.

## Studio runs hidden: never interrupt Merijn

Merijn works on this PC while you run. Whenever you need Studio and none is already open, start it on a hidden desktop, never a normal window:

```sh
python tools/pipeline/pc-watcher/studio_hidden.py open <place.rbxl>   # build the place with Rojo first
python tools/pipeline/pc-watcher/studio_hidden.py close               # when you are done
```

- Don't launch `RobloxStudioBeta.exe` directly, and don't bring any window to the front.
- Don't use `user_mouse_input` or `user_keyboard_input`: they move the real cursor and press real keys. Drive the game with `execute_luau` instead.
- Close only the Studio you started, with `close` (no save dialog). Never close or touch a Studio Merijn opened.
- Ask Merijn only when you truly can't continue without that input; otherwise pick a sensible default and report it at the end.

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
