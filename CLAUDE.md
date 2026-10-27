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
python tools/pipeline/pc-watcher/studio_hidden.py open <place.rbxl>   # build the place with Rojo first; prints your pid
python tools/pipeline/pc-watcher/studio_hidden.py close <pid>         # when you are done: closes only that Studio
python tools/pipeline/pc-watcher/studio_hidden.py list                # every hidden Studio still running, and whose
```

- `open` waits until Studio shows the place (about 15 s) and prints the pid as the last line. Keep that pid. MCP can reach that Studio as soon as `open` returns.
- Several bots share this PC. `close <pid>` kills only that pid and refuses any pid the script did not start. A bare `close` kills only the Studios opened from your own checkout. Never close another bot's Studio, and never kill Studio processes by image name.
- Don't launch `RobloxStudioBeta.exe` directly, and don't bring any window to the front.
- Don't use `user_mouse_input` or `user_keyboard_input`: they move the real cursor and press real keys. Drive the game with `execute_luau` instead.
- Close only the Studio you started (no save dialog). Never close or touch a Studio Merijn opened.
- Always mute the run. A hidden Studio still plays music and sound effects on Merijn's speakers. Right after `start_stop_play`, run a Client `execute_luau` that sets every `Sound` and `SoundGroup` `Volume` to 0, and keeps doing so for new ones (`game.DescendantAdded`) and for later `Volume` changes. To check audio, log which sounds get created and played; don't listen.
- Ask Merijn only when you truly can't continue without that input; otherwise pick a sensible default and report it at the end.

Verify in the real game where you can (Studio playtest, screenshots, the tests in each game's `CLAUDE.md`), and report honestly what you could not check.

The hard rules still win over "get it done": no production DataStores, no real publish or upload without Merijn's OK, no secrets printed or committed (see the per-area `CLAUDE.md` files).

## Git: one worktree and branch per task

Every task (feature or fix) gets its own git worktree on its own branch, cut from the latest `main`. Always pull `main` first; never start from a stale base:

```sh
git fetch origin
git -C D:/SoftwareProjects/RobloxGames pull --ff-only origin main   # keep the main checkout current too
git worktree add ../RobloxGames-wt/<short-slug> -b <type>/<short-slug> origin/main   # e.g. feat/slime-shop, fix/fountain-collision
```

- Work, build and test only inside that worktree. Don't switch branches in the main checkout (`D:/SoftwareProjects/RobloxGames`); other bots and Merijn use it.
- If the app already started you in a worktree it made, use that one, and pull the latest `main` into it before you start (`sync_with_base_branch`, or `git pull origin main`).
- Never commit straight to `main`.
- One task per worktree and branch; the next task gets a new worktree, again from a freshly pulled `main`.
- Before opening a PR, pull `main` into the branch again and fix any conflicts.
- Commit messages follow the existing style: `feat(<area>): ...`, `fix(<area>): ...`, `docs: ...`.
- Stage your own files by path; other bots may share the checkout. Don't `git push` or open a PR unless the task or Merijn asks for it.
- Once a PR is merged, its branch goes away. GitHub deletes the remote branch automatically (repo setting); when you merge with `gh`, use `gh pr merge --delete-branch`. Then remove the worktree and the local branch too (`git worktree remove ../RobloxGames-wt/<short-slug> && git branch -D <branch>`; squash merges need `-D`).
