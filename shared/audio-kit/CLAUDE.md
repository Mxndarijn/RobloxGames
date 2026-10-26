# audio-kit: rules for bots

Procedural game sounds: recipe -> review sheet -> .ogg. How it works and the quality bar: `README.md`.

## Hard rules
- **Never upload without the owner's explicit OK.** `upload.py` is a dry run; `--yes-upload` really creates Roblox assets. Don't pass it on your own.
- **Never print, log, `cat` or commit `ROBLOX_OPEN_CLOUD_API_KEY` or `~/.config/roblox-ci.env`.** Only `upload.py --yes-upload` may read them.
- **Always look at the review sheet** (`out/<name>.png`, with the Read tool) before calling a sound done, and at `out/_sheet.png` after a full render. The numbers alone are not enough.
- No samples from the internet and no paid services. Every sound is made from code in `recipes/`.
- Commit the recipe and its `.ogg` together, and keep `manifest.json` in sync (render does that). Don't commit `.wav` or `.png` (gitignored).
- Don't clear or change an `assetId` in `manifest.json` by hand; the game may already use it.

## Per sound
1. Write the recipe; use the seeded `rng` for all randomness.
2. `python shared/audio-kit/render.py <name>`; fix every WARN.
3. Read the sheet: onset under 5 ms, peak -1 dBFS, no clipping, length near the target, energy in the mids and highs, no hiss band above 12 kHz, no rumble below 80 Hz.
4. Report honestly what you could not judge (you can't hear it). Name the sounds you are unsure about.
