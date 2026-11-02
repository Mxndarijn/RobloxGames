# obby_key_a (option A): the classic cartoon gold key (steal-a-slime obby, Key Run).
# A fat round bow (a chunky gold ring), a ribbed collar, a thick shaft and two big square teeth, all painted gold with
# a bright highlight on the front-left so it reads as shiny metal, not yellow plastic. Upright, bow on top, the ring's
# hole faces -Y. Fits the old 1.5-stud key box (height ~1.6).
import math
from lib import *
from models._obby_key_parts import *

parts = []
H = 1.6
BOW_R, BOW_T = 0.29, 0.12         # ring radius and tube radius: outer diameter 0.82
BOW_Z = H - BOW_R - BOW_T          # bow centre
SHAFT_R = 0.13
SHAFT_TOP = BOW_Z - BOW_R           # the shaft runs up into the ring

# -- the bow: one fat ring, flattened a little front to back
parts.append(paint(torus_xz("Bow", BOW_R, BOW_T, (0, 0, BOW_Z), segs=24, sides=10, sy=0.85), metal))

# -- the collar: two rings round the shaft under the bow
for k, z in enumerate((SHAFT_TOP - 0.06, SHAFT_TOP - 0.2)):
    parts.append(paint(torus_xz(f"Collar{k}", SHAFT_R + 0.02, 0.06, (0, 0, z), segs=14, sides=6, rot=(90, 0, 0)), metal))

# -- the shaft with a rounded tip and the two-tooth bit to +X
parts += blade(SHAFT_TOP + 0.05, SHAFT_R)

finish_smooth("obby_key_a", parts)
