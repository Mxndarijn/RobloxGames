"""Slime sounds: hop squishes, voice blips, pick up and put down."""
from synth import decay, env, glide, mix, n_samples, osc, saturate, vibrato, tvec, biquad, lowpass1
from . import sound
from ._parts import bubble, thump, voice, wet_noise

# --- hop squishes: wet squelch = lumpy band-passed noise falling in pitch + a soft body + a bubble
_SQUISH = {
    1: dict(dur=0.18, f=(2200, 700), body=(260, 140), bub=(700, 1300, 0.06)),
    2: dict(dur=0.22, f=(1800, 520), body=(220, 120), bub=(560, 1050, 0.08)),
    3: dict(dur=0.15, f=(2600, 900), body=(300, 170), bub=(850, 1600, 0.05)),
}


def _squish(v):
    p = _SQUISH[v]

    def fn(rng):
        d = p["dur"]
        noise = wet_noise(d, rng, *p["f"], q=2.2, grain_hz=110) * env(d, (0, 1), (0.015, 0.9), (d * 0.5, 0.35), (d, 0))
        body = thump(*p["body"], d * 0.7, t60=d * 0.5)
        b0, b1, bl = p["bub"]
        bub = bubble(b0, b1, bl, t60=bl)
        y = mix(d, (noise, 0, 0.55), (body, 0, 0.8), (bub, d * 0.35, 0.35))
        return saturate(y, 1.4)
    return fn


for _v in _SQUISH:
    sound(f"slime_squish_{_v}", _SQUISH[_v]["dur"],
          f"Wet squelch for a slime hop (variant {_v}).")(_squish(_v))


# --- voice blips: tiny voiced "bloop" chirps
_BLIP = {
    1: dict(dur=0.13, pts=((0, 600), (0.05, 940), (0.13, 800)), vowels=("oo", "ah")),
    2: dict(dur=0.17, pts=((0, 860), (0.06, 640), (0.17, 1020)), vowels=("oh", "ee")),
    3: dict(dur=0.11, pts=((0, 720), (0.04, 1100), (0.11, 1250)), vowels=("uu", "eh")),
}


def _blip(v):
    p = _BLIP[v]

    def fn(rng):
        d = p["dur"]
        f = vibrato(glide(d, *p["pts"]), d, rate=22, depth=0.015)
        y = voice(f, d, *p["vowels"])
        return y * env(d, (0, 0.0), (0.004, 1), (d * 0.3, 0.85), (d, 0)) * decay(d, d * 2.5, attack=0)
    return fn


for _v in _BLIP:
    sound(f"slime_blip_{_v}", _BLIP[_v]["dur"],
          f"Tiny cute voiced 'bloop' chirp from a slime (variant {_v}).")(_blip(_v))


@sound("slime_pickup", 0.25, "Rising wet pop when the player picks up a slime.")
def slime_pickup(rng):
    d = 0.25
    squelch = wet_noise(0.09, rng, 900, 2200, q=2.0) * env(0.09, (0, 1), (0.09, 0))
    rise = bubble(320, 950, 0.2, t60=0.22) * env(0.2, (0, 0.6), (0.12, 1), (0.2, 0.3))
    pop = bubble(1100, 1700, 0.06, t60=0.05)
    return saturate(mix(d, (squelch, 0, 0.35), (rise, 0, 0.8), (pop, 0.15, 0.5)), 1.3)


@sound("slime_putdown", 0.25, "Soft plop when a slime is placed down.")
def slime_putdown(rng):
    d = 0.25
    plop = thump(480, 150, 0.2, t60=0.2)
    settle = thump(330, 160, 0.1, t60=0.09)
    splash = biquad(wet_noise(0.08, rng, 1400, 500, q=1.5), "lp", 2500) * env(0.08, (0, 1), (0.08, 0))
    drip = bubble(650, 1000, 0.06, t60=0.06)
    return saturate(mix(d, (plop, 0, 1.0), (splash, 0, 0.3), (settle, 0.12, 0.35), (drip, 0.17, 0.2)), 1.3)
