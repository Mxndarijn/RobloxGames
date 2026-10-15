# slime_ears: see models/_slime.py and models/SLIMES.md.
from models._slime import *

rarity, body_parts, acc = VARIANTS["slime_ears"]
parts = body_parts()
if acc and __import__("os").environ.get("SLIME_WITH_ACC") == "1":  # preview only: body + accessory
    parts += acc()
ship("slime_ears", parts)
