"""Interface sounds: menus, tutorial, inventory, refusals."""
import numpy as np

from synth import biquad, decay, env, glide, mix, note, osc, pink, saturate, vibrato, lowpass1, reverb, fit
from . import sound
from ._parts import bubble, mallet, wet_noise


def _air(d, rng, f0, f1, q=1.2):
    """Airy whoosh: pink noise through a sweeping band-pass."""
    return biquad(pink(d, rng), "bp", glide(d, (0, f0), (d, f1)), q)


@sound("menu_open", 0.2, "Soft airy pop with a small upward whoosh when a menu opens.")
def menu_open(rng):
    d = 0.2
    pop = bubble(420, 980, 0.11, t60=0.13)
    air = _air(d, rng, 900, 4200) * env(d, (0, 0.5), (0.05, 1), (d, 0))
    air /= np.max(np.abs(air))
    return mix(d, (pop, 0, 1.0), (air, 0, 0.22))


@sound("menu_close", 0.18, "Soft airy pop with a small downward whoosh when a menu closes.")
def menu_close(rng):
    d = 0.18
    f = glide(0.11, (0, 900), (0.11, 380))
    pop = osc("sine", f, 0.11) * decay(0.11, 0.12, attack=0.001)
    air = _air(d, rng, 3600, 800) * env(d, (0, 1), (0.04, 0.8), (d, 0))
    air /= np.max(np.abs(air))
    return mix(d, (pop, 0, 1.0), (air, 0, 0.2))


@sound("tutorial_tick", 0.3, "Gentle two-note confirm for a finished tutorial step.")
def tutorial_tick(rng):
    d = 0.3
    a = mallet(note("E6"), 0.2, t60=0.18)
    b = mallet(note("A6"), 0.22, t60=0.22)
    return reverb(mix(d, (a, 0, 0.8), (b, 0.08, 1.0)), mix=0.12, size=0.3)


@sound("bag_pop", 0.3, "Quick zip and pop: an item went into the bag.")
def bag_pop(rng):
    d = 0.3
    zl = 0.13
    # zip: band-passed noise chopped into fast rising teeth
    teeth_rate = glide(zl, (0, 70), (zl, 160))
    teeth = 0.5 + 0.5 * osc("square", teeth_rate, zl)
    teeth = lowpass1(teeth, 900)
    zip_ = biquad(pink(zl, rng), "bp", glide(zl, (0, 1800), (zl, 4200)), 3.0) * teeth
    zip_ = zip_ / np.max(np.abs(zip_)) * env(zl, (0, 0.8), (zl * 0.8, 1), (zl, 0.2))
    pop = bubble(500, 1250, 0.15, t60=0.14)
    tick = mallet(note("C7"), 0.15, t60=0.13)
    return mix(d, (zip_, 0, 0.45), (pop, 0.12, 1.0), (tick, 0.15, 0.25))


@sound("denied", 0.35, "Soft cartoon 'bwomp' bounce when an action is refused.")
def denied(rng):
    d = 0.35
    # two bouncy syllables, the second lower: bw-omp
    def syl(f0, f1, ln):
        f = glide(ln, (0, f0), (ln * 0.3, f0 * 1.06), (ln, f1))
        tone = 0.75 * osc("tri", f, ln) + 0.25 * osc("square", f, ln)
        wah = biquad(tone, "lp", glide(ln, (0, 500), (ln * 0.25, 1500), (ln, 350)), 2.0)
        return wah * env(ln, (0, 0), (0.004, 1), (ln, 0)) * decay(ln, ln * 1.6, attack=0)
    a = syl(330, 280, 0.13)
    b = syl(250, 160, 0.21)
    return mix(d, (a, 0, 0.8), (b, 0.12, 1.0))


@sound("error_soft", 0.3, "Gentle low double blip for a soft error.")
def error_soft(rng):
    d = 0.3
    def blip(f, ln):
        tone = osc("square", f, ln) * 0.35 + osc("sine", f, ln)
        tone = biquad(tone, "lp", 1200, 0.7)
        return tone * env(ln, (0, 0), (0.003, 1), (ln, 0)) * decay(ln, ln * 2.0, attack=0)
    return mix(d, (blip(note("E4"), 0.11), 0, 1.0), (blip(note("C4"), 0.15), 0.13, 1.0))
