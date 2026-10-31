# habitat_prop_goozilla: a toppled toy city block: a little street base, two bright toy buildings standing and one
# knocked over across the street (the kaiju was here).
from models._habitat_prop3 import *

STREET, STREET_LO = rgb(120, 126, 140), rgb(96, 100, 114)
WIN = rgb(190, 236, 255)
parts = []
base = box("Street", (1.7, 1.0, 0.1), (0, 0, 0.05), STREET)
bevel(base, 0.03)
parts.append(base)
for i, x in enumerate((-0.6, -0.2, 0.2, 0.6)):  # dashed centre line
    parts.append(box(f"Dash{i}", (0.22, 0.05, 0.02), (x, -0.36, 0.105), rgb(255, 230, 100)))


def building(name, w, d, h, col, rows, cols):
    """Toy building standing on z = 0 at the origin: block, roof cap, window grid on the front (-Y) and both sides."""
    out = []
    b = box(name, (w, d, h), (0, 0, h / 2), col)
    bevel(b, 0.03)
    out.append(grad(b, shade(col, 0.82), col))
    out.append(box(name + "Roof", (w + 0.06, d + 0.06, 0.07), (0, 0, h + 0.03), shade(col, 0.7)))
    for r in range(rows):
        z = h * (r + 0.7) / (rows + 0.4)
        for c in range(cols):
            x = -w / 2 + w * (c + 0.5) / cols
            out.append(box(f"{name}W{r}{c}", (w / cols * 0.5, 0.03, h / (rows + 1) * 0.45), (x, -d / 2 - 0.01, z), WIN))
        out.append(box(f"{name}S{r}", (0.03, d * 0.4, h / (rows + 1) * 0.45), (-w / 2 - 0.01, 0, z), WIN))
        out.append(box(f"{name}T{r}", (0.03, d * 0.4, h / (rows + 1) * 0.45), (w / 2 + 0.01, 0, z), WIN))
    return out


# tall red tower at the back left, yellow block at the back right
for o in building("Tower", 0.42, 0.42, 1.2, rgb(240, 84, 84), 4, 2):
    parts.append(xf(o, (-0.56, 0.22, 0.1)))
for o in building("Shop", 0.46, 0.38, 0.62, rgb(255, 196, 64), 2, 2):
    parts.append(xf(o, (0.0, 0.26, 0.1)))
# blue building knocked over: lying on its back across the front-right, slightly turned
for o in building("Fallen", 0.34, 0.34, 0.78, rgb(80, 150, 240), 3, 2):
    parts.append(xf(o, (0.62, -0.12, 0.27), (0, -90, -16)))
# rubble bits by the fallen top and the broken stump it came from
parts.append(box("Stump", (0.34, 0.34, 0.14), (0.58, 0.24, 0.17), rgb(80, 150, 240)))
for i, (x, y, s) in enumerate(((-0.3, -0.3, 0.09), (-0.22, -0.1, 0.07), (0.75, -0.05, 0.08), (0.38, 0.0, 0.06))):
    parts.append(box(f"Rub{i}", (s, s, s), (x, y, 0.1 + s / 2), rgb(230, 228, 236), rot=(0, 0, 30 * i)))
ship("habitat_prop_goozilla", parts)
