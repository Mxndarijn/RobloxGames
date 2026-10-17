from recipes import icon, FRONT
from props import *

SKIN_VIEW = (28, 38)


def fence_run(color, cap, length=8.4, along="x", at=4.2):
    parts = []
    n = int(length // 1.8) + 1
    for i in range(n):
        t = -length / 2 + i * length / (n - 1)
        pos = (t, at, 1.3) if along == "x" else (at, t, 1.3)
        parts.append(rbox(f"Post{i}", (0.55, 0.55, 2.0), pos, color, 0.08))
        parts.append(rbox(f"Cap{i}", (0.7, 0.7, 0.2), (pos[0], pos[1], 2.38), cap, 0.04))
    size = (length, 0.22, 0.3) if along == "x" else (0.22, length, 0.3)
    for z in (1.0, 1.75):
        pos = (0, at, z) if along == "x" else (at, 0, z)
        parts.append(box(f"Rail{z}", size, pos, shade(color, 0.92)))
    return parts


def diorama(floor, fence, cap, extra, soil=None):
    parts = [rbox("Soil", (9.4, 9.4, 0.9), (0, 0, 0.45), soil or rgb(130, 92, 62), 0.15)]
    top = rbox("Floor", (9.0, 9.0, 0.5), (0, 0, 1.0), floor, 0.12)
    gradient(top, shade(floor, 0.92), shade(floor, 1.08), 0.75, 1.25)
    parts.append(top)
    parts += fence_run(fence, cap, 8.6, "x", 4.2)
    parts += fence_run(fence, cap, 8.6, "y", 4.2)
    parts += extra
    return parts


@icon("PlotSkin_classic", view=SKIN_VIEW)
def skin_classic():
    ex = [run_model("ranch_mailbox", (-2.6, -2.4, 1.25), (0, 0, 20), 0.85), run_model("ranch_hay_bale", (1.4, 1.4, 1.25), (0, 0, -15), 1.0)]
    ex.append(blobc("Bush", 1.0, (-2.8, 2.6, 2.0), C["green_d"], squash=(1, 1, 0.9)))
    ex.append(blobc("Bush2", 0.8, (-1.7, 3.0, 1.9), C["green"], squash=(1, 1, 0.9)))
    ex.append(slime((120, 225, 140), "happy", (2.2, -1.8, 1.25), (0, 0, -20), 0.8))
    return diorama(rgb(120, 196, 108), rgb(196, 138, 86), rgb(226, 170, 110), ex)


@icon("PlotSkin_mushroom", view=SKIN_VIEW)
def skin_mushroom():
    ex = [run_model("plot_skin_mushroom", (0.3, 0.8, 1.25), (0, 0, 0), 1.15)]
    ex.append(slime((120, 225, 140), "happy", (-2.4, -2.4, 1.25), (0, 0, 20), 0.75))
    return diorama(rgb(112, 150, 72), rgb(255, 214, 196), rgb(255, 238, 226), ex)


@icon("PlotSkin_candy", view=SKIN_VIEW)
def skin_candy():
    ex = [run_model("plot_skin_candy", (-0.3, 1.0, 1.25), (0, 0, 0), 1.25)]
    ex.append(slime((255, 160, 200), "happy", (-2.4, -2.4, 1.25), (0, 0, 20), 0.75))
    return diorama(rgb(224, 142, 172), rgb(255, 190, 214), rgb(255, 232, 242), ex, rgb(176, 104, 126))


@icon("PlotSkin_crystal", view=SKIN_VIEW)
def skin_crystal():
    ex = [run_model("plot_skin_crystal", (0.3, 0.9, 1.25), (0, 0, 0), 1.0)]
    ex.append(slime((190, 160, 255), "happy", (-2.4, -2.4, 1.25), (0, 0, 20), 0.75))
    return diorama(rgb(148, 124, 190), rgb(214, 196, 255), rgb(238, 228, 255), ex, rgb(104, 84, 140))
