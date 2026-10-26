"""World sounds: eggs, goo, springs."""
import numpy as np

from synth import biquad, decay, env, glide, mix, osc, pink, place, saturate, silence, vibrato, white, n_samples
from . import sound
from ._parts import bubble, thump, wet_noise


@sound("egg_wobble", 0.4, "Wooden-ish rattle as an egg wobbles.")
def egg_wobble(rng):
    d = 0.4
    buf = silence(d)
    # alternating left/right knocks: a woody resonance excited by short clicks, slowing and fading
    times = [0.0, 0.07, 0.135, 0.205, 0.28, 0.35]
    for i, t in enumerate(times):
        f = 820 if i % 2 == 0 else 640
        ln = 0.07
        click = white(ln, rng) * decay(ln, 0.006, attack=0.0003)
        wood = biquad(click, "bp", f, 9.0) * 6
        wood += 0.5 * biquad(click, "bp", f * 2.3, 6.0) * 3
        body = osc("sine", f * 0.5, ln) * decay(ln, 0.035, attack=0.0008)
        place(buf, wood + 0.6 * body, t, 1.0 * (0.82 ** i))
    return saturate(buf / (np.max(np.abs(buf)) + 1e-12), 1.3)


@sound("goo_splat", 0.3, "Thick wet goo splat with droplets, juicier than a plain splat.")
def goo_splat(rng):
    d = 0.3
    burst = wet_noise(0.16, rng, 3000, 450, q=1.6, grain_hz=140, grain_depth=0.8)
    burst *= env(0.16, (0, 1), (0.02, 0.85), (0.16, 0))
    body = thump(260, 95, 0.14, t60=0.12)
    # gooey "stretch": a low formant that glides down, like goo sagging
    sag = biquad(osc("saw", glide(0.18, (0, 180), (0.18, 110)), 0.18), "bp", glide(0.18, (0, 900), (0.18, 350)), 4.0)
    sag *= env(0.18, (0, 0), (0.02, 1), (0.18, 0))
    buf = mix(d, (burst, 0, 0.7), (body, 0, 0.9), (sag, 0.01, 0.6))
    # droplets landing after the splat
    for _i in range(5):
        f = rng.uniform(900, 2200)
        ln = rng.uniform(0.03, 0.05)
        place(buf, bubble(f, f * 1.5, ln, t60=ln), 0.06 + 0.045 * _i + rng.uniform(0, 0.02), rng.uniform(0.15, 0.28))
    return saturate(buf, 1.6)


@sound("boing", 0.5, "Cartoon spring boing with a wobbling pitch.")
def boing(rng):
    d = 0.5
    t = np.arange(n_samples(d)) / 44100
    # quick upward scoop then a wobble around 330 Hz that slows and shrinks
    base = glide(d, (0, 180), (0.04, 380), (d, 340))
    wob_rate = 16 - 6 * t / d
    wob_phase = 2 * np.pi * np.cumsum(wob_rate) / 44100
    depth = 0.18 * np.exp(-t / 0.22)
    f = base * (1 + depth * np.sin(wob_phase))
    tone = 0.6 * osc("tri", f, d) + 0.4 * osc("saw", f, d)
    # jaw-harp like moving formant
    twang = biquad(tone, "bp", glide(d, (0, 2400), (d, 1100)) * (1 + 0.5 * depth * np.sin(wob_phase)), 4.0)
    tone = 1.6 * twang / (np.max(np.abs(twang)) + 1e-12) + 0.5 * tone + 0.5 * osc("sine", f, d)
    tone = biquad(tone, "lp", 6000, 0.7)  # take the buzz off the top
    return tone * env(d, (0, 0), (0.003, 1), (0.08, 0.9), (d, 0)) * decay(d, 0.95, attack=0)
