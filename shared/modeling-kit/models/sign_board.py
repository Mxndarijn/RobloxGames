# sign_board: standing wooden plot sign (plot kit). Board 6 x 3.5 x 0.4 on two posts (~7 x 6.6 x 0.6).
# The front (-Y) face is one flat light plank face for a SurfaceGui (face plane y = -0.2,
# x -2.75..+2.75, z 2.65..5.65); seams are only in the frame and the posts.
from lib import *
from models._fence import *

BW, BH, BD = 6.0, 3.5, 0.4
Z0 = 2.4           # board bottom
parts = []
for i, s in enumerate((-1, 1)):
    parts += post(f"Post{i}", s * (BW / 2 + 0.25), 0.15, 0.55, Z0 + BH + 0.5, cap_h=0.28)
# board: light face slab, frame on top of it (proud 0.06 at the front)
face = box("Face", (BW - 0.4, BD - 0.1, BH - 0.4), (0, 0.0, Z0 + BH / 2), LIGHT_FACE)
gradient(face, shade(LIGHT_FACE, 0.9), LIGHT_FACE)
parts.append(face)
for k, z in enumerate((Z0 + 0.12, Z0 + BH - 0.12)):
    parts.append(beam(f"FrameH{k}", -BW / 2, BW / 2, 0.0, z, BD, 0.26, RAIL if k == 0 else CAP))
for k, s in enumerate((-1, 1)):
    parts.append(box(f"FrameV{k}", (0.26, BD - 0.04, BH - 0.5), (s * (BW / 2 - 0.13), 0.0, Z0 + BH / 2), RAIL))  # between the H frames
# drip cap over the board, resting on the posts
parts.append(beam("CapBoard", -BW / 2 - 0.65, BW / 2 + 0.65, 0.05, Z0 + BH + 0.22, BD + 0.3, 0.22, CAP, lo=shade(CAP, 0.9)))
finish("sign_board", parts)
