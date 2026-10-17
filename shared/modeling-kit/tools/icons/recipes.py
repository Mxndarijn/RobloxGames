"""Icon registry: one recipe per ItemIcons id (DRAWN groups). A recipe builds objects in the scene
(kit conventions, see helpers.py) and returns them; render_icons.py frames + lights them.
`@icon(id, view=(yaw, pitch), fill=0.8)` registers; ORDER is the render / sheet order."""
REGISTRY = {}
ORDER = []


def icon(icon_id, view=None, fill=None):
    def deco(fn):
        REGISTRY[icon_id] = {"fn": fn}
        if view:
            REGISTRY[icon_id]["view"] = view
        if fill:
            REGISTRY[icon_id]["fill"] = fill
        ORDER.append(icon_id)
        return fn
    return deco


FRONT = (0.0, 12.0)  # "front view" recipes: straight on, slightly above

from recipes_shop import *  # noqa: E402,F401,F403
from recipes_upgrade import *  # noqa: E402,F401,F403
from recipes_boost import *  # noqa: E402,F401,F403
from recipes_misc import *  # noqa: E402,F401,F403
from recipes_goal import *  # noqa: E402,F401,F403
from recipes_badge import *  # noqa: E402,F401,F403
from recipes_skin import *  # noqa: E402,F401,F403
from recipes_gear import *  # noqa: E402,F401,F403
