from recipes import icon
from props import *

# Plot skin icons: the top of that skin's goo jar tower, built with the tower's own builders in the skin's theme
# (models/_goo_jar.py, models/_goo_jar_themes.py): the theme's cork lid with its goo oozing over the rim, and the
# theme's mascot in its hat on top. Classic's mascot wears no hat.
SKIN_VIEW = (28, 30)
MASCOT = 3.0  # mascot radius on the icon lid


def tower_top(theme):
    import models._goo_jar as G

    G.set_theme(theme)
    try:
        lid = cylinder("Lid", 3.4, 1.3, (0, 0, 0), G.CORK, segs=40, r_top=3.8)
        gradient(lid, shade(G.CORK, 0.78), G.CORK)
        parts = [lid, cylinder("Band", 3.65, 0.35, (0, 0, 0.35), G.METAL, segs=40)]
        parts += G.ooze("Ooze", 3.55, 1.15, 0.75, 6, seed=11)
        top = 1.3
        for o in G.mascot() + G.mascot_hat():
            o.scale = (MASCOT, MASCOT, MASCOT)
            o.location = (0, 0, top)
            parts.append(o)
        return parts
    finally:
        G.set_theme("classic")


@icon("PlotSkin_classic", view=SKIN_VIEW)
def skin_classic():
    return tower_top("classic")


@icon("PlotSkin_garden", view=SKIN_VIEW)
def skin_garden():
    return tower_top("garden")


@icon("PlotSkin_crystal", view=SKIN_VIEW)
def skin_crystal():
    return tower_top("crystal")


@icon("PlotSkin_starlight", view=SKIN_VIEW)
def skin_starlight():
    return tower_top("starlight")


@icon("PlotSkin_candy", view=SKIN_VIEW)
def skin_candy():
    return tower_top("candy")


@icon("PlotSkin_mushroom", view=SKIN_VIEW)
def skin_mushroom():
    return tower_top("mushroom")
