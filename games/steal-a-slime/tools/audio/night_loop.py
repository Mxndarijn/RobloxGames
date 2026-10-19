#!/usr/bin/env python3
"""Night ambience for Config.AUDIO.AMBIENT_NIGHT_ID: soft wind with two distant owl calls, a seamless 20 s loop.

    python night_loop.py out/night_wind_owls.wav [--seed 7]
    ffmpeg -i out/night_wind_owls.wav -c:a libvorbis -q:a 5 out/night_wind_owls.ogg

Everything is built to be periodic over the loop length so the end joins the start without a click:
the wind is noise synthesised in the frequency domain (an inverse FFT is periodic), its gusts are LFOs
whose periods divide the loop, and the owls' reverb is a circular convolution. numpy for the maths; the
noise comes from Python's `random` (numpy.random's DLL is blocked by Smart App Control on Merijn's PC).
"""
import argparse
import random
import wave

import numpy as np

RATE = 44100
SECONDS = 20.0
N = int(RATE * SECONDS)
PEAK_DB = -6.0


class Rng:
    """The two numpy.random calls this script needs, on Python's `random`."""

    def __init__(self, seed):
        self.r = random.Random(seed)

    def uniform(self, lo, hi, size):
        return np.array([self.r.uniform(lo, hi) for _ in range(size)])

    def standard_normal(self, size):
        return np.array([self.r.gauss(0.0, 1.0) for _ in range(size)])


def shaped_noise(rng, lo_hz, hi_hz, tilt):
    """Periodic noise with a 1/f^tilt spectrum, band-passed softly between lo_hz and hi_hz."""
    f = np.fft.rfftfreq(N, 1 / RATE)
    mag = np.zeros_like(f)
    nz = f > 0
    mag[nz] = f[nz] ** (-tilt / 2)
    mag *= 1 / (1 + (lo_hz / np.maximum(f, 1e-9)) ** 4)  # soft high-pass
    mag *= 1 / (1 + (f / hi_hz) ** 4)  # soft low-pass
    phase = rng.uniform(0, 2 * np.pi, f.size)
    x = np.fft.irfft(mag * np.exp(1j * phase), N)
    return x / np.max(np.abs(x))


def lfo(t, terms):
    """Sum of sines with whole-number cycles per loop, so it is periodic. terms = [(cycles, depth, phase)]."""
    return sum(d * np.sin(2 * np.pi * c * t / SECONDS + p) for c, d, p in terms)


def wind(rng, t):
    """Airy band-passed noise that swells in slow gusts; each gust also gets brighter (the whistle band)."""
    body = shaped_noise(rng, 70, 320, 1.6)
    air = shaped_noise(rng, 220, 900, 1.0)
    whistle = shaped_noise(rng, 600, 1800, 0.6)
    gust = 0.5 + 0.5 * np.tanh(2.2 * lfo(t, [(1, 1.0, 0.3), (2, 0.7, 1.9), (3, 0.4, 4.1)]))
    flutter = 0.5 + 0.5 * lfo(t, [(9, 0.6, 0.7), (13, 0.4, 2.2)])
    return (
        body * (0.25 + 0.2 * gust)
        + air * (0.15 + 0.55 * gust * (0.75 + 0.25 * flutter))
        + whistle * (0.02 + 0.16 * gust**2)
    )


def hoot(t0, dur, f0, t):
    """One soft owl 'hoo': a low sine with a little second harmonic, slight pitch fall, smooth envelope."""
    local = t - t0
    on = (local >= 0) & (local < dur)
    out = np.zeros_like(t)
    lt = local[on]
    env = np.sin(np.pi * lt / dur) ** 1.5
    freq = f0 * (1.03 - 0.06 * lt / dur)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    out[on] = env * (np.sin(phase) + 0.18 * np.sin(2 * phase) + 0.05 * np.sin(3 * phase))
    return out


def owl_call(start, f0, t):
    """Great-horned rhythm: hoo ... hoo-hoo ... hoo ... hoo."""
    pattern = [(0.0, 0.42), (0.75, 0.18), (1.0, 0.18), (1.45, 0.5), (2.2, 0.55)]
    return sum(hoot((start + a) % SECONDS, d, f0, t) for a, d in pattern)


def distance(x, rng):
    """Far away: muffle the highs and add a long circular reverb tail."""
    f = np.fft.rfftfreq(N, 1 / RATE)
    lowpass = 1 / (1 + (f / 900) ** 2)
    tail_t = np.arange(int(RATE * 2.2)) / RATE
    ir = np.zeros(N)
    ir[: tail_t.size] = rng.standard_normal(tail_t.size) * np.exp(-tail_t / 0.55)
    ir[0] += 6.0  # keep some of the dry call
    wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(ir) * lowpass, N)
    return wet / np.max(np.abs(wet))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    rng = Rng(a.seed)
    t = np.arange(N) / RATE

    w = wind(rng, t)
    owls = distance(owl_call(4.0, 330, t), rng) * 0.32 + distance(owl_call(13.5, 300, t), rng) * 0.2
    left = w + owls
    right = np.roll(w, int(RATE * 3.1)) * 0.95 + np.roll(owls, int(RATE * 0.012))  # a little width
    stereo = np.stack([left, right], axis=1)
    stereo *= 10 ** (PEAK_DB / 20) / np.max(np.abs(stereo))

    pcm = (stereo * 32767).astype("<i2")
    with wave.open(a.out, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())
    jump = np.max(np.abs(stereo[0] - stereo[-1]))
    print(f"wrote {a.out}: {SECONDS:.0f} s stereo, peak {PEAK_DB} dB, loop seam jump {jump:.4f}")


if __name__ == "__main__":
    main()
