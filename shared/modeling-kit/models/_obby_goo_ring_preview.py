# Preview only (not shipped): the Goo Ring with its swirl in place, as the game puts them together.
# GOO_RING_EYES=1 for the eyes variant.
import math, os
import lib
from lib import *

kept = {}


def _keep(name, parts):
    kept[name] = join(name, parts)
    return kept[name]


SIGN = os.environ.get("GOO_RING_SIGN") == "1"  # the yard scene: the status sign beside the ring
for f in ("models/obby_goo_ring.py", "models/obby_goo_swirl.py") + (("models/obby_goo_sign.py",) if SIGN else ()):
    src = open(f, encoding="utf-8").read().replace("finish(", "_keep(")
    exec(compile(src, f, "exec"), {"__name__": "goo", "_keep": _keep})
ring = [o for n, o in kept.items() if n.startswith("obby_goo_ring")][0]
sw = kept["obby_goo_swirl"]
R, T = 5.2, 1.7
sw.location = (0, 0.3, R + T * 0.42)  # ring centre, a little behind the ring's middle so the drips hang in front
out = [ring, sw]
if SIGN:
    from mathutils import Matrix
    sg = kept["obby_goo_sign"]
    sg.data.transform(Matrix.Translation((11.2, -1.2, 0)) @ Matrix.Rotation(math.radians(-22), 4, "Z"))
    out.append(sg)
finish("goo_ring_preview", out)
