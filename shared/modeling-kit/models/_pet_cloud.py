# Shared builder for pet_cloud (and its preview scene): lumpy low-poly cloud puffs, light-blue underside fading to white.
from lib import *

WHITE, BLUE = rgb(255, 255, 255), rgb(168, 208, 244)
# (name, x, y, z, radius, squash x/y/z)
PUFFS = [
    ("Core", 0.0, 0.0, 0.62, 1.0, (1.45, 1.1, 0.58)),
    ("PuffL", -1.05, 0.1, 0.5, 0.62, (1.0, 1.05, 0.8)),
    ("PuffR", 1.1, -0.1, 0.48, 0.58, (1.0, 1.0, 0.8)),
    ("PuffF", 0.35, -0.85, 0.46, 0.55, (1.05, 1.0, 0.8)),
    ("PuffB", -0.35, 0.88, 0.5, 0.55, (1.1, 1.0, 0.82)),
    ("PuffFL", -0.8, -0.7, 0.4, 0.42, (1, 1, 0.8)),
    ("PuffBR", 0.8, 0.75, 0.42, 0.45, (1, 1, 0.8)),
]


def cloud_parts():
    parts = []
    for i, (n, x, y, z, r, sq) in enumerate(PUFFS):
        o = blob(n, r, (x, y * 0.82, z), seed=40 + i, subdiv=2, squash=(sq[0], sq[1] * 0.9, sq[2]), jitter=0.07)
        gradient(o, BLUE, WHITE)
        parts.append(o)
    return parts
