# pvp_knock_glove_5 "Royal Glove" (Knockback line, rank 5): gold mitt with a big faceted sapphire in a gold bezel on the
# back of the hand, a small crown on the upper back of the fist, crimson velvet cuff with gold trim and a white ermine fur roll.
# Held tool, built upright like ranch_bat: see models/_pvp_glove.py for axes, grip and the shared builders.
from models._pvp_glove import *

S, FIST, LIFT = 1.16, 1.10, 0.08
GOLD_LO, GOLD, GOLD_HI = rgb(240, 150, 40), rgb(252, 198, 60), rgb(255, 240, 160)  # warm lows: (212,132,36) went olive in the roblox look
CRIM, CRIM_LO, HOLE = rgb(206, 44, 72), rgb(170, 36, 64), rgb(130, 36, 56)
FUR_LO, FUR = rgb(214, 222, 238), rgb(240, 247, 255)
SPOT = rgb(84, 76, 100)
SAPH, SAPH_HI, SAPH_LO = rgb(64, 128, 244), rgb(150, 200, 255), rgb(40, 84, 196)
RUBY = rgb(230, 40, 80)
PEARL = rgb(240, 247, 255)

parts = mitt("Mitt", mitt_colour(GOLD_LO, GOLD, GOLD_HI, S), S=S, fist=FIST, lift=LIFT, tris=390, thumb_tris=90)
body = parts[0]

pal = {"hole": HOLE, "lip": CRIM_LO, "band_lo": CRIM, "band": GOLD, "band_hi": CRIM, "top": CRIM}
parts.append(cuff("Cuff", lambda row, k: pal[row], S=S, segs=14))

# ermine fur roll round the cuff opening: lumpy metaball ring, cool white, a few dark ermine tails
N, R = 11, 0.60
balls = []
for i in range(N):
    a = i * math.tau / N
    rr = 0.20 + 0.03 * math.sin(i * 2.7)
    balls.append(Ball((R * S * math.cos(a), R * S * 0.88 * math.sin(a), 0.21 * S), (rr * S, rr * S, 0.19 * S)))
fur = metaball_mesh("Fur", balls, resolution=0.045 * S, tris=260, smooth=1)
paint_goo(fur, lambda co, n: rgba(mix(FUR_LO, FUR, clamp(0.3 + 0.7 * n.z))))
parts.append(fur)
for i, a in enumerate((-1.95, -1.05, 0.3, 2.4)):
    d = Vector((math.cos(a), 0.88 * math.sin(a), 0))
    p, q, n = on_surface(fur, d * 2 + Vector((0, 0, 0.24 * S)), -d, sink=0.03)
    parts.append(blob("Spot%d" % i, 0.06 * S, pos=p, color=SPOT, subdiv=1, jitter=0.0, squash=(1, 1, 1.6)))

# sapphire in a gold bezel on the back of the hand
p, q, n = on_surface(body, (0.0, -3, (1.30 + LIFT) * S), (0, 1, 0))
parts.append(torus("Bezel", 0.25 * S, 0.055 * S, lambda k, j: GOLD_HI if j in (1, 2) else GOLD, pos=p + n * 0.02, segs=12, rsegs=4, rot=q))
parts.append(lathe("Seat", [(0, -0.08 * S), (0.24 * S, -0.08 * S), (0.24 * S, 0.03 * S), (0, 0.03 * S)], lambda i, k, z: GOLD_LO, segs=12, pos=p, rot=q))
pal_gem = {"table": SAPH_HI, "crown": SAPH, "crown2": mix(SAPH, SAPH_HI, 0.45), "pavilion": SAPH_LO}
m = q.to_matrix().to_4x4()
m.translation = p + n * 0.08 * S
parts.append(gem("Gem", 0.22 * S, 0.10 * S, 0.08 * S, lambda z: pal_gem[z], m, segs=8))

# small crown on the upper back of the fist (between the top and the back of the hand): it sits on top both in the
# upright sheet views and when the glove is held fist-forward, back of the hand up (the punch pose)
aim = Vector((0.0, -0.30, 1.86 + LIFT)) * S
top, qt, nt = on_surface(body, aim + Vector((0, -1, 1)) * 3, (0, 1, -1), sink=0.08 * S)
up = (nt + Vector((0, -0.35, 0))).normalized()  # ~45 deg between "fist up" and "back of the hand up"
print("CROWN_UP", tuple(round(c, 2) for c in up))
tilt = up.to_track_quat("Z", "Y")
cm = Matrix.Translation(top) @ tilt.to_matrix().to_4x4()
CR = 0.30 * S
parts.append(lathe("CrownBand", [(0, 0), (CR * 0.92, 0), (CR, 0.15 * S), (0, 0.15 * S)],
                   lambda i, k, z: GOLD if i == 1 else GOLD_HI, segs=15, pos=top, rot=tilt))
for i in range(5):
    a = math.pi * 1.5 + i * math.tau / 5
    base = Vector((CR * 0.82 * math.cos(a), CR * 0.82 * 0.95 * math.sin(a), 0.12 * S))
    out = Vector((math.cos(a), math.sin(a), 0))
    lean = Quaternion(out.cross(Vector((0, 0, 1))).normalized(), math.radians(-12))
    q2 = tilt @ lean
    parts.append(lathe("Point%d" % i, [(0, 0), (0.085 * S, 0), (0.0, 0.18 * S)], lambda r, k, z: GOLD_HI if k % 2 else GOLD,
                       segs=6, pos=cm @ base, rot=q2, smooth=False))
    tipw = cm @ base + q2 @ Vector((0, 0, 0.18 * S))
    parts.append(blob("Pearl%d" % i, 0.05 * S, pos=tipw, color=PEARL, subdiv=1, jitter=0.0))
fr = cm @ Vector((0, -CR * 0.96, 0.075 * S))
parts.append(blob("CrownGem", 0.06 * S, pos=fr, color=RUBY, subdiv=1, jitter=0.0))

ship("pvp_knock_glove_5", parts, grip=(0, 0, GRIP_Z * S))
