# phoenix_pad_crate: wood crate stand, 7.6 square footprint (fits 8x8 pad grid), slime stands on top at z=2.4.
from lib import *
from models._phoenix_ranch import *
W, Hc = 7.6, 2.4
parts = [bbox("Core", (W - 0.4, W - 0.4, Hc - 0.3), (0, 0, (Hc - 0.3) / 2), shade(WOOD, 0.8), shade(WOOD, 0.95))]
for s in (-1, 1):
    for ax in (0, 1):
        for k in range(2):
            z = 0.55 + k * 1.1
            size = (W, 0.35, 0.9) if ax == 0 else (0.35, W, 0.9)
            pos = (0, s * (W / 2 - 0.17), z) if ax == 0 else (s * (W / 2 - 0.17), 0, z)
            parts.append(bbox(f"Slat{ax}{s}{k}", size, pos, shade(WOOD, 0.9), WOOD if k else shade(WOOD, 0.95), bev=0.08))
for i, (x, y) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
    parts.append(bbox(f"Corner{i}", (0.8, 0.8, Hc), (x * (W / 2 - 0.3), y * (W / 2 - 0.3), Hc / 2), shade(WOOD_D, 0.9), WOOD_D, bev=0.12))
parts.append(bbox("Top", (W - 0.2, W - 0.2, 0.4), (0, 0, Hc - 0.1), shade(CREAM, 0.9), CREAM, bev=0.15))
parts.append(bbox("Mat", (5.0, 5.0, 0.14), (0, 0, Hc + 0.14), shade(ROOF, 0.9), ROOF, bev=0.05))
finish("phoenix_pad_crate", parts)
