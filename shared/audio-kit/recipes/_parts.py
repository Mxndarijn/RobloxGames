"""Reusable sound parts for recipes (not registered as sounds themselves)."""
import numpy as np

from synth import (SR, biquad, decay, env, fm, glide, lowpass1, n_samples, osc, place,
                   silence, tvec, vibrato, white, pink)


def bubble(f0, f1, dur, t60=None, kind="sine"):
    """Water-drop / bubble 'bloop': a sine whose pitch rises from f0 to f1, decaying fast."""
    f = glide(dur, (0, f0), (dur * 0.6, f1), (dur, f1))
    return osc(kind, f, dur) * decay(dur, t60 or dur, attack=0.001)


def thump(f0, f1, dur, t60=None):
    """Soft low body: a sine falling from f0 to f1 (keep f1 >= ~90 Hz, no sub rumble)."""
    f = glide(dur, (0, f0), (dur, f1))
    return osc("sine", f, dur) * decay(dur, t60 or dur, attack=0.0015)


def wet_noise(dur, rng, f_start, f_end, q=2.5, grain_hz=90.0, grain_depth=0.7):
    """Squelchy noise: band-passed pink noise sweeping f_start -> f_end, chopped by a random
    'grain' amplitude so it sounds wet and lumpy instead of a smooth hiss."""
    n = n_samples(dur)
    src = pink(dur, rng)
    f = glide(dur, (0, f_start), (dur, f_end))
    y = biquad(src, "bp", f, q)
    # lumpy amplitude: low-passed random steps
    steps = rng.uniform(1 - grain_depth, 1, int(dur * grain_hz) + 2)
    lump = np.interp(np.linspace(0, len(steps) - 1, n), np.arange(len(steps)), steps)
    lump = lowpass1(lump, grain_hz * 1.5)
    return y * lump / (np.max(np.abs(y)) + 1e-12)


def chime(freq, dur, t60=0.6, bright=1.0):
    """Clean glockenspiel-like chime: fundamental + soft inharmonic partials + an FM shimmer."""
    t60 = min(t60, dur * 1.5)
    y = osc("sine", freq, dur) * decay(dur, t60, attack=0.001)
    for ratio, amp, life in ((2.76, 0.32, 0.35), (5.40, 0.12, 0.18)):
        if freq * ratio < 11000:
            y += bright * amp * osc("sine", freq * ratio, dur) * decay(dur, t60 * life, attack=0.001)
    y += 0.25 * bright * fm(freq, 2.0, 1.6, dur, index_end=0.05) * decay(dur, t60 * 0.25, attack=0.001)
    return y


def mallet(freq, dur, t60=0.25, kind="sine"):
    """Soft marimba-ish note: body + a quick 4x partial for the 'tok' of the mallet."""
    y = osc(kind, freq, dur) * decay(dur, t60, attack=0.0015)
    if freq * 4 < 11000:
        y += 0.18 * osc("sine", freq * 4, dur) * decay(dur, t60 * 0.15, attack=0.001)
    return y


# vowel formants (F1, F2, F3) Hz for a small cartoon voice
VOWELS = {"oo": (350, 900, 2400), "oh": (480, 1000, 2600), "ah": (750, 1300, 2700),
          "eh": (550, 1800, 2700), "ee": (320, 2300, 3000), "uu": (400, 1100, 2500)}


def voice(f, dur, vowel_a="oo", vowel_b=None, breath=0.0, rng=None):
    """Voiced cartoon chirp: a band-limited saw at pitch curve f through 3 formant band-passes.
    The formants move from vowel_a to vowel_b over the sound (a tiny 'word')."""
    src = 0.35 * osc("saw", f, dur) + 0.65 * osc("tri", f, dur)
    if breath and rng is not None:
        src = src + breath * white(dur, rng)
    va = VOWELS[vowel_a]
    vb = VOWELS[vowel_b or vowel_a]
    out = 0.0
    for i, (fa, fb, amp) in enumerate(zip(va, vb, (1.0, 0.55, 0.18))):
        fc = glide(dur, (0, fa), (dur, fb))
        out = out + amp * biquad(src, "bp", fc, 5.0 + 2 * i)
    # keep some of the fundamental so tiny voices are not thin
    out = biquad(out, "lp", 5000, 0.7) + 0.35 * osc("sine", f, dur)
    return out / (np.max(np.abs(out)) + 1e-12)


def sparkle(dur, rng, count=8, lo=2500, hi=6000, t0=0.0, spread=None, t60=0.12, gain=0.25):
    """Random tiny high sine pings (glitter). Deterministic through rng."""
    buf = silence(dur)
    spread = dur - t0 if spread is None else spread
    for _ in range(count):
        f = float(np.exp(rng.uniform(np.log(lo), np.log(hi))))
        at = t0 + rng.uniform(0, max(spread - 0.05, 0.01))
        ln = min(0.2, dur - at)
        if ln <= 0.01:
            continue
        ping = osc("sine", f, ln) * decay(ln, t60, attack=0.002)
        place(buf, ping, at, gain * rng.uniform(0.5, 1.0))
    return buf
