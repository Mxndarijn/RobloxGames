# habitat_frame_glow: the thin glowing lip ring for the top 3 rarity frames (Secret, Celestial, Divine). Pure white
# vertex colour: the game tints it per tier and sets it to Neon. Sits just inside the frame (2.48..2.6), z 0..0.32,
# a rounded top so the neon reads as a soft tube.
from lib import *
from models._habitat_frame import *

WHITE = rgb(255, 255, 255)
prof = [(2.48, 0.0), (2.48, 0.27), (2.54, 0.32), (2.6, 0.27), (2.6, 0.0)]
ring = arc_mesh("Glow", 0.0, 0.0, prof, WHITE, segs=48, closed=True, col_fn=lambda *a: WHITE)
frame_finish("habitat_frame_glow", [ring])
