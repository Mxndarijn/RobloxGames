# parade_lane_arc45: one 45-degree segment of the goo-parade lane (Slime Ranch, Steal a Slime hub).
# Wild slimes (3 studs) ride a shallow goo channel round the fountain; 7 of these + 1 parade_lane_gate
# close the ring (8 x 45 deg). Lane centreline r 68 (between landing ring r 62 and ring path r 74):
# goo channel 4.5 wide (r 65.75..70.25), soft wooden edging 1.0 each side, total r 64.75..71.25.
# Edging top 0.88 (planks up to 0.93, stakes 1.0): players step over it. Goo surface z 0.20 in the
# centre (slimes ride here), 0.42 against the walls.
#
# Placement: the segment spans -112.5..-67.5 deg about the hub (centred on kit -Y). The script prints
# the hub position relative to the MeshPart; tile by rotating copies k * 45 deg about the hub.
# Builder: models/_parade_lane.py (shared with the gate so the end profiles match exactly).
from lib import *
from models._parade_lane import *

SPAN = 45.0
ts = ring_ts(SPAN, planks=6, interior=2)
parts = [channel("Goo", SPAN, [(k / 16, False) for k in range(17)])]
parts.append(rail("RailIn", -1, SPAN, ts))
parts.append(rail("RailOut", 1, SPAN, ts))
# a few chunky stakes (hand-made), never at the segment ends so tiles don't double them
for side, t in ((1, 1 / 6), (1, 3 / 6), (1, 5 / 6), (-1, 2 / 6), (-1, 4 / 6)):
    parts += post(f"Stake{side}{t}", side, SPAN, t)
# goo life: a few highlight bubbles (kept off the ends)
parts += bubbles("Bubble", SPAN, [(-0.7, 0.12, 0.62), (0.2, 0.14, 0.34), (0.8, 0.43, 0.55), (-0.5, 0.71, 0.7), (-1.15, 0.74, 0.3)])

report("parade_lane_arc45", parts)
finish("parade_lane_arc45", parts)
