# habitat_prop_kitsune: a small vermilion torii gate on stone feet, black upturned top beam, gold plaque.
from models._habitat_prop5 import *

RED, RED_HI = rgb(226, 58, 40), rgb(255, 104, 70)
BLACK, BLACK_HI = rgb(64, 50, 60), rgb(96, 78, 90)
STONE, STONE_HI = rgb(170, 160, 150), rgb(214, 206, 196)
GOLD = rgb(255, 206, 80)
PX, H = 0.56, 1.06
parts = []
for sx in (-1, 1):
    parts.append(gbox(f"Foot{sx}", (0.26, 0.26, 0.12), (sx * PX, 0, 0.06), STONE, STONE_HI, bev=0.03))
    parts.append(gcyl(f"Post{sx}", 0.085, H, (sx * PX, 0, 0.1), shade(RED, 0.88), RED_HI, segs=8, r_top=0.07))
parts.append(gbox("Nuki", (1.5, 0.1, 0.11), (0, 0, 0.88), RED, RED_HI, bev=0.02))
parts.append(gbox("Shimaki", (1.62, 0.18, 0.12), (0, 0, 1.1), RED, RED_HI, bev=0.02))
# kasagi: black top beam with upturned ends
kas = [(-0.92, 1.3), (-0.8, 1.22), (0.8, 1.22), (0.92, 1.3), (0.94, 1.36), (0.8, 1.31), (-0.8, 1.31), (-0.94, 1.36)]
parts.append(slab("Kasagi", kas, 0.24, BLACK, hi=BLACK_HI))
parts.append(gbox("Kasa2", (1.64, 0.2, 0.06), (0, 0, 1.19), RED, bev=0.0))
parts.append(gbox("Plaque", (0.22, 0.05, 0.22), (0, -0.07, 0.99), GOLD, bev=0.02))
parts.append(gbox("PlaqueIn", (0.12, 0.03, 0.12), (0, -0.1, 0.99), BLACK_HI, bev=0.0))
ship("habitat_prop_kitsune", parts)
