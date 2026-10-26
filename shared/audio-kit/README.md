# audio-kit

Procedural sound effects for the games: a Python recipe -> review sheet -> .ogg loop. numpy for the synthesis, matplotlib for the sheets, ffmpeg for the Vorbis encode. No samples, no paid services, no network. Bot rules: `CLAUDE.md`.

```sh
python shared/audio-kit/render.py --all             # every sound + out/_sheet.png (about 8 s)
python shared/audio-kit/render.py coin boing        # just these
python shared/audio-kit/render.py --list            # names, target lengths, descriptions
python shared/audio-kit/upload.py --all             # dry run of the Roblox upload
```

Needs `python` with numpy and matplotlib, and `ffmpeg` with libvorbis on `PATH`.

## The loop

1. Write or change a recipe in `recipes/`.
2. Run `render.py <name>`. It prints one line per sound: OK/WARN, length, peak, RMS, LUFS-ish loudness, onset (in the .wav and in the decoded .ogg) and file size.
3. Look at `out/<name>.png`: waveform on top (red dashes = -1 dBFS, green line = onset), spectrogram below (0-16 kHz, cyan dashes = 12 kHz), stats and warnings at the bottom.
4. Change one or two things, render again. When the set is done, run `--all` and look at `out/_sheet.png`, the contact sheet of every sound on the same time scale.

## Outputs (`out/`)

| File | What | In git |
|---|---|---|
| `<name>.ogg` | Vorbis q5, 44.1 kHz, mono. The upload source. Bit-exact: the same recipe gives the same bytes. | yes |
| `<name>.wav` | 16-bit PCM of the same samples | no |
| `<name>.png` | review sheet | no |
| `_sheet.png` | contact sheet of all sounds | no |
| `_stats.json` | the numbers behind the sheets | no |

`manifest.json` is rewritten on every render: one entry per sound with `name`, `file`, `description`, `assetId` and `lufs`. An `assetId` that is already there is kept. Empty means not uploaded yet.

## Adding a recipe

Put it in one of the files in `recipes/` (`slime.py`, `ui.py`, `rewards.py`, `world.py`) or in a new file there (any module not starting with `_` is loaded):

```python
from synth import decay, mix, note, osc
from . import sound
from ._parts import chime

@sound("my_ding", 0.4, "One-line description; it goes into manifest.json and the Roblox asset.")
def my_ding(rng):
    a = chime(note("E6"), 0.4, t60=0.3)
    return mix(0.4, (a, 0, 1.0))
```

- Return a raw mono float array. `render.py` runs `synth.finish()` on it, so don't normalize or fade yourself.
- Use the `rng` you get for every random choice. It is seeded from the name, so renders are repeatable.
- The second argument is the target length; the render warns when the result is more than 20% off.
- `recipes/_parts.py` has the shared parts: `bubble` (water-drop bloop), `thump`, `wet_noise` (lumpy squelch), `chime` (glockenspiel-like), `mallet`, `voice` (formant chirp), `sparkle` (random high pings).
- `synth.py` has the building blocks: oscillators with pitch glides (`osc`, `glide`, `vibrato`, `fm`), noise (`white`, `pink`), envelopes (`adsr`, `decay`, `env`), filters (`lowpass1`, `highpass1`, `biquad` lp/hp/bp with sweeping cutoff), `saturate`, `reverb`, and mixing (`mix`, `place`).

## What `finish()` does

High-pass at 70 Hz (no rumble or DC), low-pass at 14 kHz, trims leading silence so the sound starts at once, 1 ms fade-in, trims the dead tail (below -60 dB), fades the last 25 ms, and normalizes the peak to -1 dBFS.

## Quality bar

A sound is done when the sheet shows all of this:

- **Starts instantly.** Onset (first sample within 20 dB of the peak) under 5 ms, in the .wav and in the decoded .ogg. Game sounds that lag feel broken.
- **Peak -1 dBFS, no clipping.** The .ogg peak may land slightly above -1 dBFS after encoding, but must stay under -0.1 dBFS.
- **Short tails.** Close to the target length; no long reverb wash.
- **Mono, 44.1 kHz.**
- **Cute, not harsh.** Most energy in the mids and highs (the spectral centroid is shown), under 5% below 80 Hz, under 3% above 12 kHz. No bright hiss band across the top of the spectrogram.

The render warns about everything it can measure. Whether it sounds cute is a judgement call: when you can listen, listen; when you can't, read the spectrogram for shape (clean pitch lines for tonal sounds, noise bands that move for wet sounds) and say so in your report.

## Loudness

Every file peaks at -1 dBFS, so loudness differs: a sustained square-ish blip is much louder than a sparse chime with the same peak. `manifest.json` carries `lufs` per sound; set `Sound.Volume` in the game from it (a quieter LUFS needs a higher volume).

## Uploading

`upload.py` creates one Roblox Audio asset per sound through the Open Cloud Assets API (`POST /assets/v1/assets`, multipart `request` + `fileContent`), polls the operation until it is done and writes the `assetId` into `manifest.json`. It is a dry run unless you pass `--yes-upload --user-id <id>`, and that needs the owner's OK first. The key comes from `ROBLOX_OPEN_CLOUD_API_KEY` or `~/.config/roblox-ci.env` and is never printed.

After an upload, `apply_ids.py` copies the new ids into the game. Each manifest entry's `uses` (kept by hand,
preserved by `render.py`) names the game's sound registry and the names there, for example
`{"games/steal-a-slime/src/ui/Sounds.luau": ["Cash"]}`. It is a dry run unless you pass `--write`:

```sh
python shared/audio-kit/apply_ids.py           # what would change
python shared/audio-kit/apply_ids.py --write   # fill the empty ids in the game
```

Until a sound is uploaded its game name keeps an empty id and plays its fallback (see the game's `Sounds.FALLBACK`).
