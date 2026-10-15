# parade_lane_gate rounds (archer, 2026-10-15)

Despawn-gate segment: same 45-degree channel and end profiles as `parade_lane_arc45`, plus a round goo drain
basin with the countdown-ring seat, and a ranch arch over the lane. Close-ups: `_rNN_detail.png`
(`models/_parade_lane_detail.py`, PL_PIECE=gate; shrunken 0.5x slime in the basin + the countdown ring).

| Round | Wall | Tris | What changed / why |
|---|---|---|---|
| r01 quick | 1.5 s | 3700 | Channel width blends 2.25 -> 3.35 round the basin (cosine, +-5.2 studs) so the edging bulges round it; basin = surface of revolution (drain swirl, ring seat groove r 1.5..2.3 at z 0.20, goo_hi lip r 2.95); arch: posts at +-4.75 outside the edging, beam underside 9.6, braces, red sign with butter faces + goo-drop icon, gable roof. Roof slab rotation sign was wrong in the first draft (V instead of ^), fixed before render. Over budget; posts spindly. |
| r02 quick + detail | 2.0 s | 3232 | Tri diet (dense rings 10 -> 8, 1 interior ring per plank, basin 28 -> 24 segs, bubbles 4 -> 2); posts 1.2 -> 1.45; swirl stripes 2-on-2-off. Countdown ring in the detail: the telegraph reads. Dark facets in the goo round the basin. |
| r03 colour | 3.5 s | 3104 | **Bug:** the goo sample t's were not sorted, so the slab zig-zagged (the dark facets). Sorted + an assert in `sweep()`. Channel goo near the basin now follows the basin's top profile - 0.05 instead of a hard drop to 0.03 (no dip ring round the lip). Clean goo. |
| r04 colour | 4.7 s | 2932 | Dense rings 8 -> 6, one swirl row less, no bubbles, unbevelled braces/sign faces; post/foot lows lifted (shadow side went dark brown). The beam sign faces along the lane, so it's edge-on from the plaza: added a butter plaque (red frame) on the hub-facing side of the inner post at eye height (SurfaceGui-ready). Final. |

## Final
- 54.53 x 14.03 x 14.13 studs (W x H x D), 2932 tris, 0 non-manifold, `out/parade_lane_gate.fbx`.
- Beam underside 9.6 (>= 9): a player can walk the lane under it. Posts stand at r 63.25 / 72.75 (feet 62.25..73.75),
  inside the gap between the landing ring (62) and the ring path (74).
- `parade_lane_gate_after.png`, `parade_lane_gate_after_robloxlook.png` (+ `_turntable.png`), `parade_lane_gate_joint_check.png` (gate/arc joint, clean).
- Butter faces go olive on the shadow side in the roblox look (known, see LESSONS ranch_hay_bale).
