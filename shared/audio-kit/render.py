#!/usr/bin/env python3
"""Render sound recipes to .ogg (+ .wav) with a review sheet per sound and a contact sheet.

    python shared/audio-kit/render.py --all            # every recipe + out/_sheet.png
    python shared/audio-kit/render.py coin boing       # just these (the contact sheet still shows all rendered .wav files)
    python shared/audio-kit/render.py --list           # names, target durations, descriptions

Writes out/<name>.wav (16-bit), out/<name>.ogg (Vorbis q5, 44.1 kHz mono), out/<name>.png
(waveform + spectrogram + stats), out/_stats.json and out/_sheet.png. Keeps manifest.json in
sync (name, file, description, lufs; an existing assetId is never touched).
Prints one line per sound: OK/WARN, duration, peak, RMS, LUFS-ish, onset (wav and decoded ogg).
Exit code 0 = all OK, 2 = at least one warning, 1 = error.
"""
import argparse
import json
import os
import subprocess
import sys
import wave

import numpy as np

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)

import synth  # noqa: E402
from recipes import load_all  # noqa: E402

OUT = os.path.join(KIT, "out")
MANIFEST = os.path.join(KIT, "manifest.json")
DUR_TOLERANCE = 0.2  # warn when the finished length is more than 20% off the target


def write_wav(path, y):
    pcm = np.clip(np.round(y * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(synth.SR)
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(float) / 32768


def encode_ogg(wav, ogg):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", wav,
                    "-c:a", "libvorbis", "-q:a", "5", "-ar", str(synth.SR), "-ac", "1",
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", ogg], check=True)  # bitexact: same input, same bytes (no git churn)


def decode_ogg(ogg):
    raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", ogg,
                          "-f", "f32le", "-ac", "1", "-ar", str(synth.SR), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, "<f4").astype(float)


def _spec(ax, y, vmin=-90):
    with np.errstate(divide="ignore"):
        _specgram(ax, y, vmin)
    ax.set_ylim(0, 16000)
    ax.axhline(12000, color="cyan", lw=0.6, ls="--", alpha=0.6)


def _specgram(ax, y, vmin):
    ax.specgram(y + 1e-7, NFFT=512, Fs=synth.SR, noverlap=448, cmap="magma", vmin=vmin, vmax=-10, scale="dB")


def review_sheet(path, name, recipe, y, st):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    t = np.arange(len(y)) / synth.SR * 1000
    fig = plt.figure(figsize=(9, 6.2), dpi=100)
    gs = fig.add_gridspec(3, 1, height_ratios=[1.1, 1.8, 0.75], hspace=0.35)
    ax = fig.add_subplot(gs[0])
    ax.plot(t, y, lw=0.6, color="#2a6fdb")
    lim = 10 ** (synth.PEAK_DB / 20)
    for v in (lim, -lim):
        ax.axhline(v, color="red", lw=0.5, ls="--")
    ax.axvline(st["onset_ms"], color="green", lw=0.8)
    ax.set_xlim(0, max(t[-1], recipe.dur * 1000))
    ax.set_ylim(-1.05, 1.05)
    ax.set_ylabel("amp")
    ax.set_title(f"{name}  ({'OK' if not st['warnings'] else 'WARN'})", loc="left", fontsize=12, fontweight="bold")
    ax2 = fig.add_subplot(gs[1])
    _spec(ax2, y)
    ax2.set_xlim(0, max(len(y) / synth.SR, recipe.dur))
    ax2.set_ylabel("Hz")
    ax2.set_xlabel("s")
    ax3 = fig.add_subplot(gs[2])
    ax3.axis("off")
    lines = [
        f"duration {st['duration_s']:.3f} s (target {recipe.dur:.2f})   peak {st['peak_dbfs']:.2f} dBFS   "
        f"RMS {st['rms_dbfs']:.1f} dBFS   LUFS-ish {st['lufs']:.1f}",
        f"onset {st['onset_ms']:.2f} ms (ogg {st.get('ogg_onset_ms', float('nan')):.2f} ms, ogg peak "
        f"{st.get('ogg_peak_dbfs', float('nan')):.2f} dBFS)   centroid {st['centroid_hz']} Hz   "
        f"<80 Hz {st['sub_bass_pct']:.2f}%   >12 kHz {st['air_pct']:.2f}%",
        recipe.description,
        ("warnings: " + "; ".join(st["warnings"])) if st["warnings"] else "warnings: none",
    ]
    ax3.text(0, 1, "\n".join(lines), va="top", fontsize=9, family="monospace",
             color="black" if not st["warnings"] else "#b00000")
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)


def contact_sheet(path, items):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    cols = 5
    rows = (len(items) + cols - 1) // cols
    fig = plt.figure(figsize=(cols * 3.6, rows * 3.5), dpi=90)
    gs = fig.add_gridspec(rows * 3, cols, height_ratios=[0.8, 2.2, 0.9] * rows, hspace=0.1, wspace=0.25, top=0.95)
    for i, (name, y, st) in enumerate(items):
        r, c = divmod(i, cols)
        wa = fig.add_subplot(gs[3 * r, c])
        sa = fig.add_subplot(gs[3 * r + 1, c], sharex=wa)
        tt = np.arange(len(y)) / synth.SR
        wa.plot(tt, y, lw=0.4, color="#2a6fdb")
        wa.set_ylim(-1.05, 1.05)
        wa.set_yticks([])
        wa.tick_params(axis="x", labelbottom=False)
        _spec(sa, y)
        sa.set_xlim(0, 1.2)
        sa.set_yticks([0, 4000, 8000, 12000, 16000], ["0", "4k", "8k", "12k", "16k"], fontsize=6)
        sa.tick_params(axis="x", labelsize=6)
        flag = "" if not st["warnings"] else "  WARN"
        wa.set_title(f"{name}{flag}  {st['duration_s']:.2f}s\n"
                     f"pk {st['peak_dbfs']:.1f}  rms {st['rms_dbfs']:.1f}  "
                     f"lufs {st['lufs']:.1f}  on {st['onset_ms']:.1f}ms", fontsize=7.5,
                     color="black" if not flag else "#b00000")
    fig.suptitle("audio-kit contact sheet (x: 0-1.2 s; spectrogram 0-16 kHz, dashed = 12 kHz)", fontsize=10)
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)


def sync_manifest(registry, stats):
    old = {}
    if os.path.isfile(MANIFEST):
        old = {e["name"]: e for e in json.load(open(MANIFEST))["sounds"]}
    sounds = []
    for name, r in registry.items():
        e = old.get(name, {})
        entry = {"name": name, "file": f"out/{name}.ogg", "description": r.description,
                 "assetId": e.get("assetId", "")}
        lufs = stats.get(name, {}).get("lufs", e.get("lufs"))
        if lufs is not None:
            entry["lufs"] = lufs  # loudness hint for setting Sound.Volume in the game
        if e.get("uses"):
            entry["uses"] = e["uses"]  # where a game plays it (apply_ids.py), hand-kept
        sounds.append(entry)
    with open(MANIFEST, "w", newline="\n") as f:
        json.dump({"sounds": sounds}, f, indent=2)
        f.write("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--no-sheet", action="store_true", help="skip the per-sound PNGs")
    a = ap.parse_args()

    reg = load_all()
    if a.list:
        for n, r in reg.items():
            print(f"{n:18s} {r.dur:.2f}s  {r.description}")
        return 0
    names = list(reg) if a.all or not a.names else a.names
    unknown = [n for n in names if n not in reg]
    if unknown:
        print(f"unknown sound(s): {', '.join(unknown)}. Try --list.", file=sys.stderr)
        return 1
    os.makedirs(OUT, exist_ok=True)
    stats_path = os.path.join(OUT, "_stats.json")
    all_stats = json.load(open(stats_path)) if os.path.isfile(stats_path) else {}
    worst = 0
    for name in names:
        r = reg[name]
        y, st = synth.finish(r.render())
        if abs(st["duration_s"] - r.dur) > DUR_TOLERANCE * r.dur:
            st["warnings"].append(f"duration {st['duration_s']} s vs target {r.dur} s")
        wav, ogg, png = (os.path.join(OUT, f"{name}.{ext}") for ext in ("wav", "ogg", "png"))
        write_wav(wav, y)
        encode_ogg(wav, ogg)
        dec = decode_ogg(ogg)
        dst = synth.analyze(dec)
        st["ogg_onset_ms"], st["ogg_peak_dbfs"] = dst["onset_ms"], dst["peak_dbfs"]
        st["ogg_bytes"] = os.path.getsize(ogg)
        if dst["peak_dbfs"] > -0.1:
            st["warnings"].append(f"ogg peak {dst['peak_dbfs']} dBFS (encoder overshoot)")
        if dst["onset_ms"] > synth.MAX_ONSET_MS:
            st["warnings"].append(f"ogg onset {dst['onset_ms']} ms")
        if not a.no_sheet:
            review_sheet(png, name, r, y, st)
        all_stats[name] = st
        flag = "WARN" if st["warnings"] else "OK  "
        worst = max(worst, 2 if st["warnings"] else 0)
        print(f"{flag} {name:18s} {st['duration_s']:.3f}s  peak {st['peak_dbfs']:6.2f}  rms {st['rms_dbfs']:6.1f}  "
              f"lufs {st['lufs']:6.1f}  onset {st['onset_ms']:.2f}/{st['ogg_onset_ms']:.2f} ms  "
              f"{st['ogg_bytes'] // 1024} KB" + (f"  [{'; '.join(st['warnings'])}]" if st["warnings"] else ""))
    with open(stats_path, "w") as f:
        json.dump(all_stats, f, indent=2)
    sync_manifest(reg, all_stats)
    items = []
    for name in reg:
        wav = os.path.join(OUT, f"{name}.wav")
        if os.path.isfile(wav) and name in all_stats:
            items.append((name, read_wav(wav), all_stats[name]))
    contact_sheet(os.path.join(OUT, "_sheet.png"), items)
    print(f"contact sheet: {os.path.join(OUT, '_sheet.png')}")
    return worst


if __name__ == "__main__":
    sys.exit(main())
