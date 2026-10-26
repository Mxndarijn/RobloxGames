"""Reward sounds: level up, unlocks, discoveries, money."""
import numpy as np

from synth import biquad, decay, env, fm, glide, mix, note, osc, pink, reverb, saturate, silence, place, vibrato, white
from . import sound
from ._parts import bubble, chime, mallet, sparkle


@sound("level_up", 0.8, "Bright rising four-note arpeggio chime for a level up.")
def level_up(rng):
    d = 0.8
    buf = silence(d)
    notes = ["C6", "E6", "G6", "C7"]
    for i, n in enumerate(notes):
        ln = d - i * 0.08
        place(buf, chime(note(n), ln, t60=0.35 if i < 3 else 0.6, bright=0.8), i * 0.08, 0.7 + 0.1 * i)
    # a soft octave-down pad under the last note for warmth
    place(buf, osc("tri", note("C5"), 0.5) * env(0.5, (0, 0), (0.01, 1), (0.5, 0)), 0.24, 0.15)
    buf += sparkle(d, rng, count=6, lo=3000, hi=7000, t0=0.26, spread=0.35, gain=0.12)
    return reverb(buf, mix=0.22, size=0.5, damp=6000)


@sound("pad_unlock", 0.9, "Sparkly 'something new' chime when a pad unlocks.")
def pad_unlock(rng):
    d = 0.9
    buf = silence(d)
    # quick upward shimmer then a held two-note chord
    for i, n in enumerate(["G5", "D6", "G6"]):
        place(buf, chime(note(n), 0.3, t60=0.18, bright=0.6), i * 0.045, 0.5)
    for n, g in (("B6", 0.8), ("D7", 0.55)):
        place(buf, chime(note(n), d - 0.14, t60=0.7, bright=0.7), 0.14, g)
    # gentle tremolo shimmer
    shimmer = fm(note("G7"), 1.5, 0.6, d - 0.14) * decay(d - 0.14, 0.5) * (0.6 + 0.4 * osc("sine", 9, d - 0.14))
    place(buf, shimmer, 0.14, 0.08)
    buf += sparkle(d, rng, count=10, lo=2800, hi=7500, t0=0.1, spread=0.55, gain=0.14)
    return reverb(buf, mix=0.25, size=0.6, damp=6500)


@sound("dex_new", 1.2, "Magical six-note discovery jingle for a new Slimedex entry.")
def dex_new(rng):
    d = 1.2
    buf = silence(d)
    run = ["C6", "D6", "E6", "G6", "A6"]
    for i, n in enumerate(run):
        place(buf, chime(note(n), 0.35, t60=0.25, bright=0.7), i * 0.075, 0.55 + 0.05 * i)
    t_end = 0.42
    ln = d - t_end
    chord = sum(g * chime(note(n), ln, t60=0.75, bright=0.7) for n, g in (("C7", 0.9), ("G6", 0.45), ("E6", 0.35)))
    chord *= 0.8 + 0.2 * osc("sine", 7, ln)  # soft tremolo: the 'magic' wobble
    place(buf, chord, t_end)
    buf += sparkle(d, rng, count=14, lo=3000, hi=8000, t0=0.3, spread=0.6, gain=0.12)
    return reverb(buf, mix=0.28, size=0.65, damp=6500)


@sound("jar_fill", 0.6, "Glassy rising bubble fill as a jar fills up.")
def jar_fill(rng):
    d = 0.6
    buf = silence(d)
    # resonance of the jar rises as it fills (air column gets shorter)
    res = glide(d, (0, 520), (d, 1450))
    glass = fm(res, 2.0, 0.5, d) * env(d, (0, 0.6), (0.4, 1.0), (d, 0.0))
    place(buf, glass, 0, 0.12)
    # bubbles: quick upward blips that also climb
    t = 0.0
    k = 0
    while t < d - 0.07:
        base = 380 * (1450 / 380) ** (t / d) * rng.uniform(0.9, 1.15)
        ln = rng.uniform(0.04, 0.07)
        place(buf, bubble(base, base * 1.6, ln, t60=ln), t, rng.uniform(0.55, 0.9))
        t += rng.uniform(0.035, 0.06)
        k += 1
    # a glassy ping at the top
    place(buf, chime(note("A6"), 0.18, t60=0.16, bright=0.5), d - 0.17, 0.3)
    return reverb(buf, mix=0.15, size=0.35)


@sound("coin", 0.35, "Bright coin pickup: two quick high notes.")
def coin(rng):
    d = 0.35
    def tone(f, ln, t60):
        y = 0.55 * osc("square", f, ln) + 0.6 * osc("sine", f, ln)
        return biquad(y, "lp", 6000, 0.7) * decay(ln, t60, attack=0.001)
    a = tone(note("B5"), 0.07, 0.25) * env(0.07, (0, 1), (0.06, 1), (0.07, 0))
    b = tone(note("E6"), d - 0.065, 0.32)
    return mix(d, (a, 0, 0.8), (b, 0.065, 1.0))


@sound("cash_register", 0.7, "Cha-ching: a drawer clack and a bright ringing bell.")
def cash_register(rng):
    d = 0.7
    # "cha": short metallic noise rattle in two clacks
    def clack(ln):
        n = biquad(white(ln, rng), "bp", 3200, 1.8) * decay(ln, ln * 0.6, attack=0.0008)
        body = mallet(700, ln, t60=0.04)
        return 0.8 * n + 0.4 * body
    buf = silence(d)
    place(buf, clack(0.05), 0, 2.2)
    place(buf, clack(0.06), 0.05, 1.8)
    # "ching": inharmonic bell + two chime notes
    ring_t = 0.12
    ln = d - ring_t
    bell = fm(note("E6"), 1.41, 2.2, ln, index_end=0.2) * decay(ln, 0.6, attack=0.001)
    place(buf, bell, ring_t, 0.55)
    place(buf, chime(note("E7"), ln, t60=0.5, bright=0.5), ring_t, 0.55)
    place(buf, chime(note("B6"), ln, t60=0.45, bright=0.5), ring_t + 0.01, 0.4)
    buf += sparkle(d, rng, count=7, lo=3500, hi=7500, t0=ring_t, spread=0.3, gain=0.1)
    return reverb(buf, mix=0.15, size=0.4)
