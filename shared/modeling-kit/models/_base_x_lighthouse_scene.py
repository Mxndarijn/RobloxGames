# Base concept (design sketch, not an asset): THE LIGHTHOUSE (Exclusive).
# A red-and-white striped tower on sea rocks, each floor a wide glass window band, narrowing a little per floor.
# A gallery balcony and the glass lantern room with a turning beam crown the top floor. Door on -Y with a jetty.
from models._base_concept_extra import *

RS = [28.0, 26.5, 25.0, 23.5]
WHITE, RED_L = rgb(246, 246, 250), rgb(226, 60, 60)
SEA, ROCK = rgb(80, 170, 230), rgb(140, 140, 150)

plot_foot(moat=True, moat_col=SEA, ground=rgb(230, 210, 160), door_r=28.0, bridge_len=10.0)
for k in range(22):
    a = k * 360 / 22 + R.uniform(-6, 6)
    if -112 < (a + 180) % 360 - 180 < -68:
        continue
    x, y = polar(R.uniform(30.5, 33.5), a)
    S(blob(f"Rock{k}", R.uniform(2.0, 3.6), (x, y, 0.8), ROCK, subdiv=2, jitter=0.2), shade(ROCK, 0.7), ROCK)
core(RS, rgb(200, 180, 150), WHITE, rgb(120, 160, 200), [PINK, LILAC, BUTTER, rgb(120, 190, 250)])
bands(RS, [RED_L, WHITE, RED_L, WHITE], glass_from=3.0)

zt = top(FLOORS) + FLOOR_H
disc("Gallery", RS[-1] + 3.0, 1.0, (0, 0, zt), shade(RED_L, 0.7), segs=40, into="shell")
for k in range(24):
    x, y = polar(RS[-1] + 2.6, k * 15)
    disc(f"Rail{k}", 0.25, 3.0, (x, y, zt + 1.0), rgb(60, 60, 70), segs=5, into="shell")
ring_wall("RailTop", RS[-1] + 2.4, RS[-1] + 2.9, zt + 4.0, 0.4, rgb(60, 60, 70), segs=40)
disc("LanternBase", 11.0, 2.0, (0, 0, zt + 1.0), WHITE, segs=24, into="shell")
add(cylinder("Lantern", 9.5, 9.0, (0, 0, zt + 3.0), rgb(200, 235, 255), segs=24), into="glass")
add(blob("Lamp", 4.0, (0, 0, zt + 7.5), rgb(255, 230, 120), subdiv=2, jitter=0))
part("Beam", (3.0, 30.0, 2.5), (8.0, -16.0, zt + 7.5), rgb(255, 245, 190), rot=(0, 0, -30))
wedge_cone("Cap", 11.0, 0.0, zt + 12.0, 9.0, [RED_L], n=24)
add(blob("CapBall", 1.4, (0, 0, zt + 21.5), rgb(60, 60, 70), subdiv=2, jitter=0), into="shell")
# Front door frame.
part("DoorFrame", (12.0, 1.6, 1.6), (0, -(RS[0] + 0.5), 12.8), rgb(60, 60, 70), into="shell")
mascot(-7.0, -24.0, zt + 1.0, s=2.2, col=rgb(250, 250, 255))  # the seagull-white mascot on the gallery

ship("_base_x_lighthouse_scene", turn=-25)
