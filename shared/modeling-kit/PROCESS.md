# Roblox modeling process (official, 2026-10-15)

This is Merijn's official way to make 3D props for the Roblox games. The tool is the modeling kit in this folder (`shared/modeling-kit` in RobloxGames). Its `CLAUDE.md` has the exact bot rules.

## Who does what
- **Claude Code is the modeler.** It writes each model as a short Python (bpy) script in `models/<name>.py`, built from simple shapes (boxes, tubes, puffs) with colours painted on as vertex colours. 1 Blender unit = 1 Roblox stud.
- **No Blender window.** Blender runs headless on the server. Instead of a viewport, every round produces pictures that Claude Code looks at and critiques.

## One command per round: `iterate.py`
`python3 iterate.py models/<name>.py` does a whole round:
1. builds the model in headless Blender,
2. renders a 4-angle contact sheet (front, side, back, top) with Cycles on the CPU, about 256 px per view, with a 5-stud avatar block for scale,
3. writes `stats.json`: triangles, size in studs, holes, and a pass/fail against the Roblox budget (500–2000 tris per prop, under 10,000 per mesh, under 2048 studs, FBX under 20 MB, one mesh, vertex colours),
4. exports the FBX only if it passes.

Extra modes:
- `--quick`: a grey clay sheet showing only the shape (Workbench with cavity shading and outlines), about **1.2 s**. Use it for silhouette and proportion rounds.
- `--watch`: re-runs on every save of the model; the new sheet is ready about 1.2 s later.
- `--look roblox`: renders with the game's own lighting and a plastic-like material, closer to how it looks in-game. It is an estimate, not calibrated against Studio yet. `--turntable` adds an 8-angle strip and GIF.
- It also warns when something won't survive the Roblox import (extra materials, material colours, textures, vertex alpha).

Measured on this 8-core box with the tree_oak (1404 tris): quick 1.17 s, normal round 2.5 s, Roblox look 3.1 s, Roblox look + turntable 8.5 s. The tree_oak remake took 6 rounds, under 20 s of render time in total. When other bots load the box, a round can take 10× longer (seen: 30 s at load 48).

## Memory between models
- `CLAUDE.md`: the rules and the loop.
- `LESSONS.md`: what worked and what didn't, read before every model, appended after.
- `lib/`: shared shape and colour helpers. `examples/`: small finished models to copy from.
- `sheets/`: every round's sheet plus a short log, so a person can follow the rounds.

## Optional: concept image
If there is a concept picture, `compare.py` puts the render next to it and gives a rough similarity score. Looking at the sheet still matters more than the score.

## From model to game (bot side)
1. `upload.py out/<name>.fbx` uploads the FBX to Roblox through Open Cloud. It is a **dry run by default**. A real upload (`--go`, new asset or `--update <id>`) needs Merijn's OK.
2. The mesh is placed in the game, then checked in a real playtest through **Phoenix's Studio gate** (see `roblox-release-process.md`). That screenshot is the real look; the renders are a preview.

## Honest limits
- **Organic shapes** (slimes, characters, anything soft or sculpted) are beyond simple shapes in code. They need a 3D generator API later.
- The renders are not Roblox. The Roblox look is closer but still misses bloom, haze, level of detail and the real screen.
- Quality tops out at "clean stylised low-poly". This is good for trees, rocks, fences and props, not hero assets.

## Rule: report the limits
When a model hits the limits of this process (organic shapes, a quality ceiling after about 6 rounds, or slow rounds), the bot **reports it to SuperBottie**. Include which model, which limit, the sheets and what would fix it. SuperBottie makes sure Merijn hears about it. Don't quietly ship a weak model.
