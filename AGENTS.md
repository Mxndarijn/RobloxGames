# AGENTS.md: how AI agents work in RobloxGames

Every AI agent (Claude Code, Codex, any other) reads this file at the start of every chat. It is the short form of the **AI Game Guidebook**, [guides/ai-guidebook.html](guides/ai-guidebook.html). The guidebook holds the full chapters, the evidence (PR numbers) and the decision log. When you change a rule here, change the guidebook in the same PR, and the other way round.

## House rules

1. **A human signs off everything players see or hear.** 3D models, UI screens, world placement, music, sound effects and player-facing wording are reviewed by Merijn or Niels before they ship. An AI review, a bot reviewer or a playtest subagent "Pass" is evidence, not a sign-off.
2. **Show it before you build it.** Anything visible starts as a mockup, render or before/after page with options (A, B, C). The human picks; the PR quotes the pick. Big features get an HTML proposal in `games/<name>/docs/` with a "Decided" section first.
3. **Nothing goes out without Merijn's OK.** No `Published` upload, no asset upload or re-upload, no merge to `main` by a bot.
4. **Never touch production DataStores.** Tests and cloud scripts run with `DataStoreMode = "Memory"`. Cheats only go through the guarded TestHooks.
5. **The AI never plays on a real Roblox account.** Test in Studio over MCP or with Open Cloud Luau Execution.
6. **Don't interrupt the person at the PC.** Studio runs hidden (`tools/pipeline/pc-watcher/studio_hidden.py`) and muted. No real mouse or keyboard input. Close only the Studio you opened.
7. **Report what you did not check.** Every PR lists the checks it ran and the ones it could not ("not tested on phone", "not listened to by ear"). Missing evidence counts as a fail.
8. **One task, one worktree, one branch**, cut from a freshly pulled `main`. Stage your own files by path. Never commit to `main`.
9. **One place for every value.** Colours in the palette file, sizes in Layout, tunables in Config, world sizes in WorldLayout.
10. **Common systems live in `shared/luau`, not in a game.** Inventory and hotbar, saves, migrations, rate limiting, formatting, seeded random, analytics, settings. Use or extend the shared module first; move anything game-agnostic you build in a game to shared ([its rules](shared/luau/CLAUDE.md)).
11. **No secrets in output.** The Open Cloud key is never printed or committed.

## What keeps going wrong (check before you hand in)

- **Too much on screen.** Most UI rework was about clutter, too many options and too much text, not bugs. Fewer words beat smaller words; nothing under 14 px; one main button per card; tabs instead of long lists.
- **Phone sizes.** Run the layout gate at all six sizes and look at a phone screenshot. Touch targets are at least 44 px.
- **Build from the game's kit** (Steal a Slime: GooKit = `GooPalette`, `Widgets`, `Layout`, `UI-STYLEGUIDE.md`). No raw Frames, colours or ZIndex numbers.
- **Models look different in Roblox.** Lift dark colours, match the old mesh's size within 10%, check axes and colours in Studio. Stop after about six rounds and report the limit instead of shipping a weak model.
- **World:** no `Glass` material; pick collision before upload; every world label has an explicit `MaxDistance` and a registry row ([guide](guides/roblox-world-labels.md)); run the terrain burial probe when anything touches the ground.
- **Sound:** you can't hear. Measure and log, give the human options, and never upload before the sound is approved.
- **Already decided?** Check the guidebook's Decision log before proposing a feature or a change. Don't re-propose what was rejected.

## Read the guidebook tab for the task

Open [guides/ai-guidebook.html](guides/ai-guidebook.html) and read the part that fits before you start (the content is in the HTML source, one `<section>` per tab or chapter):

| Task | Read |
|---|---|
| Any UI screen, HUD or menu | Guides: `g-kit` (the game kit) and `g-ui` |
| A 3D model | Guides: `g-models`, then `shared/modeling-kit/LESSONS.md` |
| Map, props, collision, labels | Guides: `g-world` |
| Music or sound | Guides: `g-audio` and `shared/audio-kit` |
| Checking your work in game | Guides: `g-verify` and `g-weak` |
| Starting a new game | `newgame` tab |
| Writing a brief, prompt or PR body | `briefs` tab |
| Economy, balancing, analytics, roadmap | `economy` tab |
| Uploading or releasing | `release` tab |
| Proposing a feature or design change | `decisions` tab |
| An unknown term or role | `glossary` tab |

When Merijn or Niels makes a lasting decision, add a row to the guidebook's Decision log in the same PR.
