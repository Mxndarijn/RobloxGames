# Concept preview (not an asset): the goo jar tower in a theme (JAR_THEME, models/_goo_jar_themes.py) at version JAR_V,
# with the theme's props round the foot and its hat on the mascot. The tower itself is models/_goo_jar_assembled.py
# (every piece built in the theme's palette); this adds the extras as a third preview mesh.
import math
import os

import bpy

from models._goo_jar_assembled import *

extras = []
for o in theme_props():
    o.location.z += top(1)
    extras.append(o)
if V < FLOORS:  # the crowned last jar keeps its crown instead
    for o in mascot_hat():
        o.scale = (s, s, s)
        o.location = (0, 0, lid_top)
        extras.append(o)

if extras:
    o = join("goo_jar_theme_extras", extras)
    apply_transforms(o)
    o.data.materials.clear()
    o.data.materials.append(vcol_material("jar_vcol"))
    if "Col" in o.data.color_attributes:
        o.data.color_attributes.active_color = o.data.color_attributes["Col"]
    o.rotation_euler.z = math.radians(float(os.environ.get("JAR_TURN", "-20")))
