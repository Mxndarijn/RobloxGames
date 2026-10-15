# gate_bar: the door that fills the gate_frame clear opening (plot kit). ~7.6 x 2.8 x 0.4 studs,
# origin bottom-centre: place it at the gate_frame origin (closed) and toggle/tint it from lock code.
# Wood body + a saturated orange latch plate on the front (-Y) face = the lock signal colour.
# NOTE: one MeshPart has one Material/Color; setting Material=Neon lights the whole bar, not just
# the latch (see PLOT_KIT.md).
from lib import *
from models._fence import *

W, H, D = 7.6, 2.8, 0.4
parts = []
# stiles (vertical end frames) and top/bottom rails
for i, s in enumerate((-1, 1)):
    st = box(f"Stile{i}", (0.5, D - 0.04, H - 0.5), (s * (W / 2 - 0.25), 0, 0.1 + (H - 0.5) / 2), POST)  # stops under Top: no coincident faces
    gradient(st, POST_LO, POST)
    parts.append(st)
parts.append(beam("Top", -W / 2, W / 2, 0, H - 0.2, D + 0.04, 0.4, CAP, lo=shade(CAP, 0.9)))
parts.append(beam("Bottom", -W / 2 + 0.5, W / 2 - 0.5, 0, 0.45, D - 0.04, 0.4, RAIL))
# vertical planks between the rails, set back a little
N = 7
inner = W - 1.0
for i in range(N):
    x = -inner / 2 + inner * (i + 0.5) / N
    o = box(f"Plank{i}", (inner / N - 0.1, D - 0.16, H - 0.6), (x, 0.02, 0.2 + (H - 0.6) / 2 + 0.05), PLANK if i % 3 else PLANK_ALT)
    gradient(o, PLANK_LO, PLANK)
    parts.append(o)
# Z brace on the front face
parts.append(strut("Brace", (-W / 2 + 0.6, -D / 2 - 0.06, 0.65), (W / 2 - 0.6, -D / 2 - 0.06, H - 0.4), 0.14, 0.36, RAIL))
# latch plate + knob (front, near the right stile, so it reads from the path)
lx = W / 2 - 1.05
parts.append(box("LatchPlate", (0.9, 0.12, 0.9), (lx, -D / 2 - 0.1, 1.5), LATCH))
parts.append(cylinder("Knob", 0.22, 0.25, (lx, -D / 2 - 0.15, 1.5), shade(LATCH, 1.08), segs=6, rot=(90, 0, 0)))
finish("gate_bar", parts)
