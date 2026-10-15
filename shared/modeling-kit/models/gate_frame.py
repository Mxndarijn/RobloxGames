# gate_frame: plot entrance frame (plot kit). Two gate posts with an 8.0-stud clear opening
# (x -4..+4), a tie beam whose underside is 9.0 up (avatar 5 + carried slime: CARRY_HEIGHT 3 above
# the root, 3-stud body), a lintel with a small terracotta roof cap, and short fence stubs out to
# x = +-7 so the whole piece is exactly 2 segments (14 studs) on the 7-stud grid:
# front = 3 x fence_straight + gate_frame + 3 x fence_straight = 21 + 14 + 21 = 56.
# The stub end posts (x = +-7) coincide with the neighbouring fence_straight posts.
from lib import *
from models._fence import *

HALF = GATE_CLEAR / 2       # 4.0
PW = 1.2                    # gate post width -> post centres at +-4.6, outer 10.4
PX = HALF + PW / 2
CLEAR_H = 9.0               # underside of the tie beam
ROOF, ROOF_LO = rgb(206, 98, 72), rgb(168, 76, 58)
parts = []
for i, s in enumerate((-1, 1)):
    x = s * PX
    body = box(f"GPost{i}", (PW, PW, 10.2), (x, 0, 5.1), POST)
    gradient(body, POST_LO, POST)
    parts.append(body)
    # foot grows outward and front/back only: the inner face stays at |x| = 4.0 (clear 8.0 at ground level)
    parts.append(box(f"GFoot{i}", (PW + 0.175, PW + 0.35, 0.7), (x + s * 0.0875, 0, 0.35), POST_LO))
    # knee braces under the tie beam (inside, above 7.6: clear of the avatar and the carried slime)
    parts.append(strut(f"Knee{i}", (s * (HALF + 0.05), -0.0, 7.4), (s * (HALF - 1.5), 0, CLEAR_H + 0.05), 0.4, 0.32, RAIL))
# tie beam + lintel + roof cap
parts.append(beam("Tie", -PX - 0.7, PX + 0.7, 0, CLEAR_H + 0.3, 0.7, 0.6, RAIL, lo=shade(RAIL, 0.88)))
parts.append(beam("Lintel", -PX - 1.3, PX + 1.3, 0, 10.45, 1.2, 0.5, CAP, lo=shade(CAP, 0.86)))
roof = prism_x("Roof", [(-1.15, 10.62), (1.15, 10.62), (0.0, 11.75)], -PX - 1.7, PX + 1.7, ROOF)
gradient(roof, ROOF_LO, ROOF)
parts.append(roof)
# fence stubs (same post/rail/picket heights as fence_straight)
for i, s in enumerate((-1, 1)):
    parts += post(f"StubPost{i}", s * SEGMENT, 0, 0.7, 3.3)
    for k, z in enumerate((0.95, 2.45)):
        x0, x1 = sorted((s * (PX + PW / 2 - 0.05), s * SEGMENT))
        parts.append(beam(f"StubRail{i}{k}", x0, x1, 0.12, z, 0.24, 0.34, RAIL, lo=shade(RAIL, 0.9)))
    span = SEGMENT - 0.35 - (PX + PW / 2)
    for j in range(3):
        x = s * (PX + PW / 2 + span * (j + 0.5) / 3)
        parts.append(picket(f"StubPicket{i}{j}", x, 0.62, 2.95 + 0.12 * (j % 2), -0.2, -0.02, z0=0.12, tip=0.32,
                            color=PLANK if j != 1 else PLANK_ALT))
finish("gate_frame", parts)
