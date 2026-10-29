# Base concept (design sketch, not an asset): THE GIANT SLIME (Exclusive).
# One huge friendly goo blob with the four floors floating inside it: the whole shell is see-through goo, so the
# pads read from every side. Big eyes and a smile on the front, goo drips round its foot, a goo-curtain arch on -Y
# is the door. Same centre ramp, pads, vat and lock as every base.
from models._base_concept_extra import *

GOO_S = rgb(120, 230, 120)
GOO_D = rgb(60, 170, 80)

plot_foot(moat=True, moat_col=GOO_D, door_r=30.0)
core([27.0, 31.0, 31.0, 25.0], rgb(190, 240, 190), GOO_D, rgb(250, 220, 90), [PINK, LILAC, BUTTER, rgb(120, 190, 250)])

# The goo shell: a big squashed sphere, centre z 24, 34 wide, 44 tall each way (clipped at the ground by the plot).
add(blob("Shell", 34.0, (0, 0, 24.0), mix(GOO_S, rgb(200, 255, 200), 0.3), subdiv=4, squash=(1, 1, 1.3), jitter=0.0),
    into="glass")
# Thick goo foot ring and drips.
ring_wall("Foot", 26.0, 30.5, 0.5, 2.2, GOO_D, segs=48)
for k in range(18):
    a = k * 20 + R.uniform(-5, 5)
    if -112 < a - 360 * (a > 180) < -68:
        continue
    x, y = polar(30.0 + R.uniform(-0.5, 1.0), a)
    S(blob(f"Drip{k}", R.uniform(1.4, 2.4), (x, y, 1.6), GOO_D, subdiv=2, squash=(1, 1, 1.4), jitter=0.05), shade(GOO_D, 0.8), GOO_S)

# Face on the front, high up: eyes with shine, and a smile.
for sx in (-1, 1):
    ex, ey = sx * 10.0, -30.5
    S(blob(f"Eye{sx}", 5.0, (ex, ey, 52.0), rgb(250, 250, 255), subdiv=2, squash=(1, 0.5, 1.15), jitter=0))
    S(blob(f"Pupil{sx}", 2.6, (ex + sx * 0.6, ey - 2.2, 51.0), rgb(30, 30, 40), subdiv=2, squash=(1, 0.5, 1.1), jitter=0))
    S(blob(f"Shine{sx}", 0.9, (ex + sx * 0.6 - 0.9, ey - 3.4, 52.6), rgb(255, 255, 255), subdiv=1, jitter=0))
pts = [(x, -32.6 + 0.02 * x * x, 41.0 + 0.06 * x * x) for x in range(-8, 9, 2)]
add(tube("Smile", pts, [0.9] * len(pts), rgb(40, 90, 50), segs=8), into="shell")

# Goo-curtain door arch: a ring of goo blobs round the doorway.
for k in range(13):
    a = math.radians(k * 15)
    S(blob(f"Arch{k}", 1.6, (7.0 * math.cos(a), -29.5, 1.0 + 11.0 * math.sin(a)), GOO_D, subdiv=2, jitter=0.05))
mascot(0, 0, 66.0, s=3.0, col=rgb(255, 150, 200))

ship("_base_x_blob_scene", turn=-25)
