# pvp_knock_glove_2 "Bounce Glove" (Knockback line, rank 2): bright blue -> teal mitt riding on a chunky butter-yellow
# spring coiled round the cuff neck, white cuff band with a teal stripe.
# Held tool, built upright like ranch_bat: see models/_pvp_glove.py for axes, grip and the shared builders.
from models._pvp_glove import *

S = 1.0
DZ = 0.20  # mitt lifted to show the spring
BLUE_LO, BLUE, TEAL_HI = rgb(40, 128, 214), rgb(52, 162, 236), rgb(96, 222, 220)
TEAL = rgb(48, 196, 196)
WHITE, WHITE_LO = rgb(240, 245, 252), rgb(212, 222, 236)
CORE, HOLE = rgb(36, 112, 170), rgb(40, 100, 150)
SPRING, SPRING_LO = rgb(255, 218, 92), rgb(232, 170, 60)

parts = mitt("Mitt", mitt_colour(BLUE_LO, BLUE, TEAL_HI, S, dz=DZ), S=S, dz=DZ)

# cuff: lip + short white band, then a narrow core (the spring's axle) up into the mitt
prof = [(0.00, 0.12), (0.46, 0.12), (0.55, 0.00), (0.66, 0.03), (0.68, 0.12), (0.62, 0.21), (0.61, 0.33),
        (0.58, 0.40), (0.36, 0.42), (0.34, 1.06), (0.00, 1.06)]
rows = ["hole", "hole", "lip", "lip", "lip", "band", "band", "top", "core", "core"]
pal = {"hole": HOLE, "lip": WHITE_LO, "band": TEAL, "top": WHITE, "core": CORE}
parts.append(lathe("Cuff", [(r * S, z * S) for r, z in prof], lambda i, k, z: pal[rows[i]], segs=14, sy=0.88))

# the spring: a fat helix round the core, from the cuff band up under the mitt
turns, z0, z1, R = 2.5, 0.46, 1.02, 0.50
N = int(turns * 11)
pts = [(R * S * math.cos(t * turns * math.tau), R * S * 0.9 * math.sin(t * turns * math.tau), (z0 + (z1 - z0) * t) * S)
       for t in (i / N for i in range(N + 1))]
parts.append(sweep("Spring", pts, 0.085 * S, lambda t: mix(SPRING_LO, SPRING, 0.5 + 0.5 * math.sin(t * turns * math.tau)), segs=6))

ship("pvp_knock_glove_2", parts, grip=(0, 0, GRIP_Z * S))
