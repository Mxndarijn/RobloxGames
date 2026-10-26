"""Recipe registry. Every module in this folder (not starting with '_') is imported, and each
@sound(...) function registers one sound.

    @sound("coin", 0.35, "Bright coin pickup: two quick high notes.")
    def coin(rng):
        return ...   # raw mono float array; render.py calls synth.finish() on it

The rng is a numpy Generator seeded from the sound name, so renders are repeatable.
"""
import importlib
import pkgutil
import zlib

import numpy as np

REGISTRY = {}


class Recipe:
    def __init__(self, name, dur, description, fn):
        self.name, self.dur, self.description, self.fn = name, dur, description, fn

    def render(self):
        rng = np.random.default_rng(zlib.crc32(self.name.encode()))
        return self.fn(rng)


def sound(name, dur, description):
    """Register a recipe. dur is the target length in seconds (the review sheet checks it)."""
    def deco(fn):
        if name in REGISTRY:
            raise ValueError(f"duplicate sound name {name!r}")
        REGISTRY[name] = Recipe(name, dur, description, fn)
        return fn
    return deco


ORDER = ["slime", "ui", "rewards", "world"]  # listing order; other modules follow alphabetically


def load_all():
    found = sorted(m.name for m in pkgutil.iter_modules(__path__) if not m.name.startswith("_"))
    for name in [m for m in ORDER if m in found] + [m for m in found if m not in ORDER]:
        importlib.import_module(f"{__name__}.{name}")
    return REGISTRY
