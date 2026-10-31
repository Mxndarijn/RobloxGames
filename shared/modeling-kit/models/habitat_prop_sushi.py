# habitat_prop_sushi: a soy-sauce dish with a pair of red chopsticks resting across it for the Sushi slime.
# The dish sits on a little wooden board next to a salmon nigiri so it reads as sushi and reaches 0.5 studs.
import math
from lib import *
from models._habitat_prop import *

BOARD, BOARD_LO = rgb(222, 174, 112), rgb(186, 136, 84)
DISH_LO, DISH_HI = rgb(206, 220, 240), rgb(252, 254, 255)
DISH_BLUE = rgb(54, 110, 214)
SOY = rgb(84, 40, 28)
RICE = rgb(252, 250, 244)
SALMON, SALMON_HI = rgb(255, 120, 72), rgb(255, 196, 150)
STICK, STICK_TIP = rgb(214, 44, 52), rgb(246, 222, 180)

BW, BD, BH = 1.62, 0.92, 0.10
parts = [box("Board", (BW, BD, BH), (0, 0, BH / 2 + 0.06), BOARD)]
for s in (-1, 1):
    parts.append(box(f"Foot{s}", (0.16, BD - 0.04, 0.06), (s * (BW / 2 - 0.22), 0, 0.03), BOARD_LO))

# soy dish on the left: round shallow bowl with a blue rim and a dark soy pool
DX, DY, Z0 = -0.36, -0.02, BH + 0.06
parts.append(lathe("Dish", [(0, Z0), (0.24, Z0), (0.32, Z0 + 0.06), (0.38, Z0 + 0.16), (0.40, Z0 + 0.18), (0.34, Z0 + 0.17),
                            (0.28, Z0 + 0.08), (0, Z0 + 0.08)], segs=16, pos=(DX, DY, 0),
                   color_fn=lambda i, k, z: DISH_BLUE if i in (3, 4) else mix(DISH_LO, DISH_HI, min(1, i / 3))))
parts.append(lathe("Soy", [(0, Z0 + 0.10), (0.31, Z0 + 0.10), (0.32, Z0 + 0.12), (0, Z0 + 0.12)], segs=16, pos=(DX, DY, 0),
                   color_fn=lambda i, k, z: SOY))

# salmon nigiri on the right, at an angle
NX, NY = 0.40, 0.10
rice = blob("Rice", 0.2, (0, 0, 0), RICE, seed=2, subdiv=2, jitter=0.04, squash=(1.45, 0.9, 0.75))
for v in rice.data.vertices:
    v.co.z = max(v.co.z, -0.1)
xf(rice, (NX, NY, Z0 + 0.12), (0, 0, 18))
parts.append(rice)
fish = box("Salmon", (0.66, 0.36, 0.08), (0, 0, 0), SALMON)
for v in fish.data.vertices:  # drape: ends lower than the middle
    v.co.z -= 0.08 * (v.co.x / 0.33) ** 2
xf(fish, (NX, NY, Z0 + 0.25), (0, 0, 18))
parts.append(fish)
for j in (-1, 0, 1):  # white fat stripes
    st = box(f"Fat{j}", (0.025, 0.37, 0.085), (j * 0.16, 0, 0.004), SALMON_HI, rot=(0, 0, 25))
    for v in st.data.vertices:
        v.co.z -= 0.08 * (v.co.x / 0.33) ** 2
    parts.append(xf(st, (NX, NY, Z0 + 0.25), (0, 0, 18)))

# chopsticks: rest on the dish rim (left) and on the nigiri (right), a little apart, tapered, light tips
top_l = Z0 + 0.18 + 0.035
top_r = Z0 + 0.36
for n, dy in enumerate((-0.10, 0.02)):
    a = (-0.86, DY + dy - 0.20, top_l - 0.02)
    b = (0.86, DY + dy + 0.02 + n * 0.04, top_r + 0.03)
    mid = tuple(a[i] + (b[i] - a[i]) * 0.78 for i in range(3))
    parts.append(tube(f"Stick{n}", [a, mid, b], [0.028, 0.04, 0.045], STICK, segs=6))
    tip = tuple(a[i] + (b[i] - a[i]) * 0.14 for i in range(3))
    parts.append(tube(f"Tip{n}", [a, tip], [0.031, 0.034], STICK_TIP, segs=6))

ship("habitat_prop_sushi", parts)
