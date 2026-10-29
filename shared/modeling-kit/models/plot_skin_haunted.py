# plot_skin_haunted: Haunted plot decor (replaces the plot's mailbox slot in game).
# A friendly pumpkin stack: a big ribbed pumpkin with a small one on top, lime stems and a leaf, and a little plum bat
# perched on the top pumpkin with its wings spread. Haunted jar theme colours (models/_goo_jar_themes.py).
# ~4.0 x 5.0 x 3.6 studs, origin bottom-centre. Target < ~1000 tris.
import os

os.environ["JAR_THEME"] = "haunted"  # before the import: the module's colours are copied into this script
from models._goo_jar import *  # noqa: E402

PUMP = THEME["pumpkin"]


def pumpkin(name, r, z, squash=0.72):
    body = blob(name, r, (0, 0, z + r * squash), PUMP, subdiv=2, squash=(1.12, 1.12, squash), jitter=0)
    for v in body.data.vertices:  # eight grooves
        k8 = 0.5 + 0.5 * math.cos(math.atan2(v.co.y, v.co.x) * 8)
        f = 1.0 - 0.08 * (1 - k8)
        v.co.x *= f
        v.co.y *= f
    return painted(body, shade(PUMP, 0.8), mix(PUMP, BUTTER, 0.25))


parts = [pumpkin("Big", 1.7, 0.0), pumpkin("Small", 1.05, 2.25, 0.78)]
top = 2.25 + 1.05 * 0.78 * 2
parts.append(painted(cylinder("Stem", 0.2, 0.55, (0, 0, top - 0.1), METAL, segs=6, r_top=0.13, rot=(12, 0, 0)), shade(METAL, 0.75), METAL))
parts.append(blob("Leaf", 0.4, (0.4, 0.1, top + 0.05), METAL, subdiv=1, squash=(1, 0.5, 0.25), jitter=0))
parts.append(blob("Leaf2", 0.35, (-0.2, 0.0, 2.25 * 0.95), METAL, subdiv=1, squash=(1, 0.5, 0.25), jitter=0, rot=(0, 0, 60)))
# the bat on the small pumpkin's front shoulder, facing -Y
parts += bat("Bat", Vector((0.0, -0.75, top - 0.45)), 0.0, BATS, k=1.6)
finish("plot_skin_haunted", parts)
