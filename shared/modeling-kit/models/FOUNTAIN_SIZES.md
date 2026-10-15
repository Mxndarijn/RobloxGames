# Fountain centre: proposed sizes (studs, draft, not in game code)

Based on live WorldLayout (map 640², PLOT_SIZE 56, plot ring 120, drop ring 34..62, ring path 72/7) and Merijn's locks.

| Item | Proposal | Notes |
|---|---|---|
| Fountain/silo footprint | Ø 16–28 (r ≤ 14) | stays inside the r 28 where the volcano foot was, so the drop ring is clear |
| Fountain/silo height | 28–48 (fountain ~36, silo ~48, ranch hybrid ~28) | old volcano 40 |
| Slide/spiral | 0.85–2.2 turns, r ~8 → ~42, length ~55–120, width 7 (6.5–8) | old chute ~50 long, 7 wide; ends inside the landing ring |
| Landing plaza | flat disc r ~55, `ranch_plaza` sand | shop + HubSpawn on the edge; no ranch_cream on the big floor |
| Wild landing ring | r 34..62 (unchanged) | |
| Goo-parade lane | centreline r 68, lane r 64.75..71.25 (6.5 incl. edging; goo channel 4.5 = r 65.75..70.25), 8 x 45 deg = 7 `parade_lane_arc45` + 1 `parade_lane_gate` + `parade_lane_countdown_ring` = 9 MeshParts | between landing ring (62) and ring path (74); edging top <= 1.0 (step over), goo z 0.20 centre; gate arch beam underside 9.6, posts r 63.25 / 72.75; 45-deg chord 54.5 < 64 decor axis |
| Ring path | r 78, width 8 | was 72/7; moved out for bigger plots |
| Spokes | width 8 | unchanged |
| Plot floor | 80 × 80 (6400 vs 3136 = 2.04× v26) | one entrance; pads 4→8 |
| Plot centres | r ~130 (was 120) | inner edge 90 > ring path outer 82; 8 plots, neighbour spacing ~99 > 80, no overlap |
| Gate / walls | slot 20, clear opening 14, walls 8 tall | fence segments 10; 6×10 + 20 = 80; top beam (if any) ≥ 9 |
| Scale refs | player 5, slime 3 | |

## Shipped fountain mesh (slime_fountain, goo polish 2026-10-15)

- `slime_fountain` (one MeshPart): 6814 tris, 54.45 x 43.3 x 63.85 studs (W x H x D), silo axis at kit (-6.52, 7.75) from the bbox centre (the script prints `SILO_AXIS`). The goo crown, drips, slide goo and the splash pool at the slide exit are all in this mesh.
- `slime_fountain_emerge` (optional second MeshPart, `models/slime_fountain_emerge.py`): the 4 gumdrop slimes (3 welling out of the crown, 1 at the slide head), 640 tris, 19.4 x 12.8 x 11.4. Not baked into the fountain any more, so it can be hidden, bobbed or swapped. Place it at fountain bbox centre + EMERGE_OFFSET: kit (-11.20, 8.25, 18.94) = Roblox (X, Y, Z) (-11.20, 18.94, -8.25) for an unrotated fountain (rotate the offset with the fountain). Per-slime base points are printed as `EMERGE_BASE` lines. The Roblox Z sign assumes Studio keeps the FBX axes (forward -Z); check once in Studio.
