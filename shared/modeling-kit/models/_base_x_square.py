# Square keep walls for the square concept sketches (candy castle, haunted manor). Same per-floor band as bands():
# a solid kick wall, a glass band and a solid lintel on all four sides, the floor-1 door left open on -Y.
from models._base_concept_extra import *


def square_walls(H, cols, glass_col, kick=3.0, lintel=2.5, door_w=10.0, t=0.8):
    for i in range(FLOORS):
        f = i + 1
        z = top(f) if f > 1 else 1.0
        col = cols[i % len(cols)]
        gh = FLOOR_H - kick - lintel
        for side in range(4):
            # side 0 = -Y (front), 1 = +X, 2 = +Y, 3 = -X
            ax = side % 2 == 1
            sgn = -1 if side in (0, 3) else 1
            if f == 1 and side == 0:
                w = H - door_w / 2
                for sx in (-1, 1):
                    cx = sx * (door_w / 2 + w / 2)
                    part(f"Kick{f}{side}{sx}", (w, t, kick), (cx, -H, z + kick / 2), col, into="shell")
                    add(box(f"Gl{f}{side}{sx}", (w, 0.3, gh), (cx, -H + 0.3, z + kick + gh / 2), glass_col), into="glass")
            else:
                size = (t, 2 * H, kick) if ax else (2 * H, t, kick)
                pos = (sgn * H, 0, z + kick / 2) if ax else (0, sgn * H, z + kick / 2)
                part(f"Kick{f}{side}", size, pos, col, into="shell")
                gsize = (0.3, 2 * H, gh) if ax else (2 * H, 0.3, gh)
                gpos = (sgn * (H - 0.3), 0, z + kick + gh / 2) if ax else (0, sgn * (H - 0.3), z + kick + gh / 2)
                add(box(f"Gl{f}{side}", gsize, gpos, glass_col), into="glass")
            lsize = (t + 0.4, 2 * H + 0.4, lintel) if ax else (2 * H + 0.4, t + 0.4, lintel)
            lpos = (sgn * H, 0, z + FLOOR_H - lintel / 2) if ax else (0, sgn * H, z + FLOOR_H - lintel / 2)
            part(f"Lintel{f}{side}", lsize, lpos, shade(col, 0.9), into="shell")
        for cx, cy in ((H, H), (-H, H), (H, -H), (-H, -H)):
            part(f"Corner{f}{cx}{cy}", (2.0, 2.0, FLOOR_H), (cx, cy, z + FLOOR_H / 2), shade(col, 0.8), into="shell")
