"""Small DSP library for game sound effects. numpy only, mono, 44.1 kHz, float64 in [-1, 1].

Everything is deterministic: noise takes a numpy Generator (recipes get one seeded from
the sound name), so the same recipe always renders the same samples.

Building blocks
    time / pitch:  n_samples, tvec, note, glide, vibrato
    oscillators:   osc(kind, freq, dur)   kind = sine | tri | square | saw (polyBLEP for square/saw)
                   fm(carrier, ratio, index, dur)   bells and chimes
    noise:         white, pink
    envelopes:     adsr, decay, env, fade_in, fade_out
    filters:       lowpass1, highpass1 (one-pole), biquad(x, kind, freq, q) kind = lp | hp | bp
                   (freq may be an array: a sweeping filter)
    shaping:       saturate (soft tanh), reverb (Schroeder: 4 combs + 2 allpasses)
    mixing:        silence, place, mix, gain_db
    mastering:     finish(x) -> (y, stats), analyze(y)
"""
import numpy as np

SR = 44100
PEAK_DB = -1.0          # finish() normalizes to this peak
ONSET_DB = -20.0        # onset = first sample within 20 dB of the peak
MAX_ONSET_MS = 5.0


# ---------------------------------------------------------------- time and pitch
def n_samples(dur):
    return max(1, int(round(dur * SR)))


def tvec(dur):
    return np.arange(n_samples(dur)) / SR


_NOTES = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}


def note(name):
    """'A4' -> 440.0, 'C#5', 'Eb6'."""
    letter, rest = name[0].upper(), name[1:]
    semi = _NOTES[letter]
    while rest and rest[0] in "#b":
        semi += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 440.0 * 2 ** ((semi + 12 * (int(rest) - 4)) / 12)


def glide(dur, *points):
    """Pitch curve through (time_s, hz) points, interpolated in log-frequency (musical glides).
    glide(0.2, (0, 300), (0.05, 900), (0.2, 600))"""
    t = tvec(dur)
    ts = np.array([p[0] for p in points], float)
    fs = np.log(np.array([p[1] for p in points], float))
    return np.exp(np.interp(t, ts, fs))


def vibrato(freq, dur, rate=6.0, depth=0.02, depth_end=None):
    """Multiply a pitch (scalar or array) by 1 + depth * sin(2 pi rate t); depth can fade to depth_end."""
    t = tvec(dur)
    d = depth if depth_end is None else np.linspace(depth, depth_end, len(t))
    return np.broadcast_to(np.asarray(freq, float), t.shape) * (1 + d * np.sin(2 * np.pi * rate * t))


# ---------------------------------------------------------------- oscillators
def _phase(freq, dur, phase0=0.0):
    """Normalized phase in [0, 1) and per-sample increment for a scalar or array frequency."""
    n = n_samples(dur)
    f = np.broadcast_to(np.asarray(freq, float), (n,)).copy()
    inc = f / SR
    ph = (phase0 + np.concatenate(([0.0], np.cumsum(inc)[:-1]))) % 1.0
    return ph, inc


def _blep(p, dt):
    """polyBLEP residual for a unit step at phase 0 (p in [0,1), dt = increment)."""
    out = np.zeros_like(p)
    a = p < dt
    x = p[a] / dt[a]
    out[a] = 2 * x - x * x - 1
    b = p > 1 - dt
    x = (p[b] - 1) / dt[b]
    out[b] = x * x + 2 * x + 1
    return out


def osc(kind, freq, dur, phase0=0.0):
    """Band-limited-ish oscillator. freq: Hz, scalar or per-sample array (glides)."""
    ph, dt = _phase(freq, dur, phase0)
    if kind == "sine":
        return np.sin(2 * np.pi * ph)
    if kind == "tri":
        return 1 - 4 * np.abs(ph - 0.5)  # harmonics fall 1/n^2, aliasing is negligible
    if kind == "saw":
        return 2 * ph - 1 - _blep(ph, dt)
    if kind == "square":
        sq = np.where(ph < 0.5, 1.0, -1.0)
        return sq + _blep(ph, dt) - _blep((ph + 0.5) % 1.0, dt)
    raise ValueError(f"unknown oscillator {kind!r}")


def fm(carrier, ratio, index, dur, index_end=None, feedback_shape=None):
    """Two-operator FM (phase modulation). carrier Hz (scalar/array); modulator = carrier * ratio.
    index fades exponentially to index_end (bell: bright attack, mellow tail)."""
    n = n_samples(dur)
    car_ph, _ = _phase(carrier, dur)
    mod_ph, _ = _phase(np.asarray(carrier, float) * ratio, dur)
    if index_end is None:
        idx = np.full(n, float(index))
    else:
        idx = index * (max(index_end, 1e-4) / max(index, 1e-4)) ** (np.arange(n) / max(n - 1, 1))
    return np.sin(2 * np.pi * car_ph + idx * np.sin(2 * np.pi * mod_ph))


# ---------------------------------------------------------------- noise
def white(dur, rng):
    return rng.uniform(-1, 1, n_samples(dur))


def pink(dur, rng):
    """1/f noise by shaping white noise in the frequency domain; normalized to peak 1."""
    n = n_samples(dur)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1] if n > 1 else 1.0
    y = np.fft.irfft(spec / np.sqrt(f), n)
    return y / (np.max(np.abs(y)) + 1e-12)


# ---------------------------------------------------------------- envelopes
def adsr(dur, a=0.005, d=0.05, s=0.6, r=0.05):
    """Attack/decay/sustain/release, release ends at dur."""
    n = n_samples(dur)
    t = np.arange(n) / SR
    rel_start = max(dur - r, a + d)
    pts_t = [0, a, a + d, rel_start, dur]
    pts_a = [0, 1, s, s, 0]
    return np.interp(t, pts_t, pts_a)


def decay(dur, t60, attack=0.002):
    """Exponential decay reaching -60 dB after t60 seconds, with a short linear attack."""
    t = tvec(dur)
    e = np.exp(-6.907755 * t / t60)
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def env(dur, *points):
    """Linear envelope through (time_s, amp) points."""
    t = tvec(dur)
    return np.interp(t, [p[0] for p in points], [p[1] for p in points])


def fade_in(x, ms):
    k = min(len(x), int(SR * ms / 1000))
    if k > 1:
        x = x.copy()
        x[:k] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(k) / k)
    return x


def fade_out(x, ms):
    k = min(len(x), int(SR * ms / 1000))
    if k > 1:
        x = x.copy()
        x[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(1, k + 1) / k)
    return x


# ---------------------------------------------------------------- filters
def _arr(v, n):
    return np.broadcast_to(np.asarray(v, float), (n,))


def lowpass1(x, freq):
    """One-pole low-pass (6 dB/oct). freq scalar or per-sample array."""
    n = len(x)
    a = np.exp(-2 * np.pi * np.clip(_arr(freq, n), 1, SR * 0.49) / SR)
    y = np.empty(n)
    s = 0.0
    xs, as_ = x.tolist(), a.tolist()
    for i in range(n):
        s = (1 - as_[i]) * xs[i] + as_[i] * s
        y[i] = s
    return y


def highpass1(x, freq):
    """One-pole high-pass: x minus its one-pole low-pass."""
    return x - lowpass1(x, freq)


def _biquad_coefs(kind, f, q):
    w = 2 * np.pi * np.clip(f, 10, SR * 0.49) / SR
    cw, sw = np.cos(w), np.sin(w)
    al = sw / (2 * q)
    if kind == "lp":
        b0 = b2 = (1 - cw) / 2
        b1 = 1 - cw
    elif kind == "hp":
        b0 = b2 = (1 + cw) / 2
        b1 = -(1 + cw)
    elif kind == "bp":  # constant 0 dB peak gain
        b0, b1, b2 = al, 0 * al, -al
    else:
        raise ValueError(f"unknown biquad {kind!r}")
    a0 = 1 + al
    return b0 / a0, b1 / a0, b2 / a0, -2 * cw / a0, (1 - al) / a0


def iir2(x, b0, b1, b2, a1, a2):
    """Direct form I biquad; coefficients scalar or per-sample arrays."""
    n = len(x)
    cs = [_arr(c, n).tolist() for c in (b0, b1, b2, a1, a2)]
    B0, B1, B2, A1, A2 = cs
    xs = x.tolist()
    y = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    for i in range(n):
        xi = xs[i]
        yi = B0[i] * xi + B1[i] * x1 + B2[i] * x2 - A1[i] * y1 - A2[i] * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return np.array(y)


def biquad(x, kind, freq, q=0.707):
    """RBJ biquad: 'lp', 'hp' or 'bp'. freq and q may be per-sample arrays (sweeps)."""
    n = len(x)
    f, qq = _arr(freq, n), _arr(q, n)
    if f.ndim and np.ptp(f) == 0 and np.ptp(qq) == 0:
        f, qq = f[0], qq[0]
    return iir2(x, *_biquad_coefs(kind, f, qq))


# ---------------------------------------------------------------- shaping
def saturate(x, drive=1.5):
    """Soft tanh saturation, gain-compensated so a full-scale input stays full scale."""
    return np.tanh(drive * x) / np.tanh(drive)


def _comb(x, d, g):
    y = np.copy(x)
    for k in range(d, len(x), d):
        e = min(k + d, len(x))
        y[k:e] += g * y[k - d:e - d]
    return y


def _allpass(x, d, g):
    y = -g * x
    y[:d] = -g * x[:d]
    out = np.copy(y)
    for k in range(d, len(x), d):
        e = min(k + d, len(x))
        out[k:e] = -g * x[k:e] + x[k - d:e - d] + g * out[k - d:e - d]
    return out


def reverb(x, mix=0.2, size=0.5, damp=5000.0, tail=0.0):
    """Cheap Schroeder reverb (4 parallel combs, 2 series allpasses). size 0..1 sets comb
    feedback (decay), damp low-passes the wet signal. tail (s) appends room for the decay;
    the dry signal is not delayed so the onset stays instant."""
    x = np.concatenate([x, np.zeros(n_samples(tail))]) if tail > 0 else x
    g = 0.70 + 0.25 * np.clip(size, 0, 1)
    wet_in = lowpass1(x, damp)
    combs = [1116, 1188, 1277, 1356]  # Freeverb lengths at 44.1 kHz
    wet = sum(_comb(wet_in, d, g) for d in combs) / len(combs)
    for d in (556, 441):
        wet = _allpass(wet, d, 0.5)
    wet = highpass1(wet, 200)  # keep the tail out of the mud
    wet *= np.max(np.abs(x)) / (np.max(np.abs(wet)) + 1e-12)
    return (1 - mix) * x + mix * wet


# ---------------------------------------------------------------- mixing
def silence(dur):
    return np.zeros(n_samples(dur))


def place(buf, sig, t0=0.0, gain=1.0):
    """Add sig into buf at t0 seconds (clipped to buf length). Returns buf (modified in place)."""
    i = int(round(t0 * SR))
    if i >= len(buf):
        return buf
    k = min(len(sig), len(buf) - i)
    buf[i:i + k] += gain * sig[:k]
    return buf


def mix(dur, *layers):
    """mix(0.3, (sig, t0, gain), (sig2, t0, gain), ...) -> buffer of dur seconds."""
    buf = silence(dur)
    for layer in layers:
        layer = layer if isinstance(layer, tuple) else (layer,)
        sig, t0, g = layer + (0.0, 1.0)[len(layer) - 1:]
        place(buf, sig, t0, g)
    return buf


def gain_db(db):
    return 10 ** (db / 20)


def fit(x, dur):
    n = n_samples(dur)
    return x[:n] if len(x) >= n else np.concatenate([x, np.zeros(n - len(x))])


# ---------------------------------------------------------------- analysis and mastering
def _kweight(x):
    """ITU-R BS.1770 K-weighting (shelf + high-pass) for the given SR."""
    # stage 1: high shelf
    G, Q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    A = 10 ** (G / 40)
    w = 2 * np.pi * fc / SR
    cw, al = np.cos(w), np.sin(w) / (2 * Q)
    sa = 2 * np.sqrt(A) * al
    b0, b1, b2 = A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sa)
    a0, a1, a2 = (A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa
    y = iir2(x, b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
    # stage 2: high-pass
    return iir2(y, *_biquad_coefs("hp", 38.13547087602444, 0.5003270373238773))


def analyze(y):
    """Stats used by the review sheet and the quality checks."""
    peak = float(np.max(np.abs(y))) + 1e-12
    rms = float(np.sqrt(np.mean(y ** 2))) + 1e-12
    onset_i = int(np.argmax(np.abs(y) >= peak * 10 ** (ONSET_DB / 20)))
    lufs = -0.691 + 10 * np.log10(np.mean(_kweight(y) ** 2) + 1e-20)  # ungated, "LUFS-ish"
    spec = np.abs(np.fft.rfft(y)) ** 2
    f = np.fft.rfftfreq(len(y), 1 / SR)
    tot = spec.sum() + 1e-20
    centroid = float((f * spec).sum() / tot)
    stats = {
        "duration_s": round(len(y) / SR, 3),
        "peak_dbfs": round(20 * np.log10(peak), 2),
        "rms_dbfs": round(20 * np.log10(rms), 2),
        "lufs": round(float(lufs), 1),
        "onset_ms": round(1000 * onset_i / SR, 2),
        "centroid_hz": round(centroid),
        "sub_bass_pct": round(100 * spec[f < 80].sum() / tot, 2),
        "air_pct": round(100 * spec[f > 12000].sum() / tot, 2),
        "clipped": int(np.sum(np.abs(y) >= 0.999)),
    }
    warn = []
    if stats["onset_ms"] > MAX_ONSET_MS:
        warn.append(f"onset {stats['onset_ms']} ms > {MAX_ONSET_MS}")
    if stats["clipped"]:
        warn.append(f"{stats['clipped']} clipped samples")
    if stats["sub_bass_pct"] > 5:
        warn.append(f"sub-bass {stats['sub_bass_pct']}% > 5%")
    if stats["air_pct"] > 3:
        warn.append(f"energy above 12 kHz {stats['air_pct']}% > 3%")
    stats["warnings"] = warn
    return stats


def finish(x, tail_ms=25.0, hp=70.0, lp=14000.0):
    """Master a raw recipe signal: high-pass (no rumble/DC), gentle top roll-off, trim leading
    silence (onset well under 5 ms), 1 ms fade-in, trim the dead tail, fade the end,
    normalize the peak to PEAK_DB. Returns (y, stats)."""
    y = np.asarray(x, float)
    y = biquad(y, "hp", hp, 0.707)
    if lp:
        y = biquad(y, "lp", lp, 0.707)
    peak = np.max(np.abs(y)) + 1e-12
    loud = np.nonzero(np.abs(y) >= peak * 10 ** (-50 / 20))[0]
    start = max(0, loud[0] - int(0.0005 * SR))
    end = loud[-1] + 1
    end_tail = np.nonzero(np.abs(y) >= peak * 10 ** (-60 / 20))[0][-1] + 1
    y = y[start:max(end, end_tail)]
    y = fade_in(y, 1.0)
    y = fade_out(y, min(tail_ms, 1000 * len(y) / SR * 0.3))
    y *= 10 ** (PEAK_DB / 20) / (np.max(np.abs(y)) + 1e-12)
    return y, analyze(y)
