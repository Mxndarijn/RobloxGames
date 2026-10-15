# Plot fence/gate kit (Volcanic Meadow)

Modular wood fence, gate and sign for a Steal a Slime plot, made with the kit loop
(2026-10-15). Theme: `THEME.md` (Volcanic Meadow): wood for fences and signs, warm stone,
terracotta roof like the cottage, and neon only for the gate_bar latch (a gameplay signal).
Scripts: `models/<name>.py`; shared sizes and colours: `models/_fence.py`. Sheets and round logs
are in `sheets/plot-kit/`, FBXs in `out/<name>.fbx`.

**Scale:** 1 Blender unit = 1 stud, uniform. Import at scale 1; no rescaling in the game.

## Pieces

Sizes are the exported bounding box in studs, W x H x D (Roblox X x Y x Z). Origin = bottom-centre of
the bbox. In kit space the front (pickets, latch, sign face) faces -Y.

| Piece | W x H x D | Tris | What it is | Snap |
|---|---|---|---|---|
| `fence_straight` | 7.84 x 3.76 x 0.84 | 212 | 1 segment: posts on both joints (x = ±3.5), 2 back rails, 8 dog-ear pickets on the front | pitch **7.0** along X; neighbours share the end post exactly |
| `fence_corner` | 1.1 x 4.21 x 1.1 | 42 | chunky capped corner/end post | on a joint; 1.1 wide, so it covers the 0.7 posts that meet there |
| `gate_frame` | 14.84 x 11.75 x 2.3 | 308 | 2 gate posts (1.2), tie beam, lintel, terracotta roof cap, knee braces, plus fence stubs out to x = ±7 | **2 segments (14.0)**, centred on the entrance; stub end posts land on the ±7 joints |
| `gate_bar` | 7.6 x 2.7 x 0.82 | 176 | plank door with Z brace, orange latch plate and knob (front, right) | same origin as gate_frame (closed); hinge line x = -3.8 |
| `wall_low` | 7.84 x 2.71 x 1.25 | 192 | 2 courses of warm stone, wooden sill + top rail, capped end posts | same as fence_straight (pitch 7.0) |
| `sign_board` | 7.3 x 6.84 x 0.8 | 132 | standing board on 2 posts with a drip cap | free-standing; SurfaceGui face below |

Grid constants: `SEGMENT = 7`, `GATE_CLEAR = 8`, `FENCE_H = 3.5` (`models/_fence.py`).

- **gate_frame clear opening:** x -4.0..+4.0 (8.0 wide) from the ground up to z 7.2; the knee-brace
  tips narrow it to 7.87 above that. The tie beam underside is at **9.0**. Checked on the exported OBJ.
- **gate_bar** sits inside the opening (7.6 of 8.0) with 0.2 play each side. Its latch is
  `rgb(236, 92, 36)`.
- **sign_board SurfaceGui face:** flat, light plank `rgb(214, 176, 120)`, 5.6 x 3.1, from 2.6 to 5.7 up,
  0.25 in front of the origin (exported OBJ: Roblox +Z side), set 0.05 behind the frame. No seams cross
  it; dark text reads on it. The frame covers its outer 0.06 on each side.

## Assembling a 56 x 56 plot

`WorldLayout.PLOT_SIZE = 56` = 8 segments of 7. Joints sit at -28, -21, ..., +21, +28 on each side;
segment centres sit at ±3.5, ±10.5, ±17.5, ±24.5.

| Side | Pieces | Count |
|---|---|---|
| Back, Left, Right | 8 x `fence_straight` each, centred on the segment centres | 24 |
| Front (entrance) | 3 x `fence_straight` (x = -24.5, -17.5, -10.5) + `gate_frame` (x = 0) + 3 x `fence_straight` (10.5, 17.5, 24.5) | 7 |
| Corners | `fence_corner` at (±28, ±28) | 4 |
| Gate | `gate_bar` at the gate_frame origin (closed), or turned 90° about the hinge x = -3.8 (open) | 1 |
| Sign | `sign_board`, e.g. on the meadow beside the path | 1 |

Front math: left wing 24 = 3 x 7 + 3 (gate_frame stub), then the clear 8, then the right wing 24, so 56 total.
`wall_low` swaps 1:1 for any `fence_straight` (same pitch and joints).

**Placing in Roblox (check in Studio first):**
- A MeshPart's `Position` is its bbox **centre**, so `Position.Y = base top (1) + H/2`
  (fence_straight 2.88, gate_frame 6.875). In X and Z the bbox centre is the origin, which is the snap point.
  `gate_bar`: the latch and knob stick out in front, so its plank body sits 0.19 behind the origin. That is
  still inside the 1.2-deep gate posts.
- The kit's FBX maps Blender -Y to Roblox **+Z** (LESSONS, kit gotcha), so mesh "front" = local +Z.
  For the pickets to face outward on a plot whose entrance is local -Z, use these yaws about Y:
  front 180°, back 0°, right (+X) +90°, left (-X) -90°. Verify one piece in Studio before placing all of them.

Proof render: `models/_plot_kit_assemble.py` loads the FBXs from `out/` and lays out a whole plot (base,
8 pads on pad_trim, fences, gate with the bar open, sign, cottage behind). Sheet:
`sheets/plot-kit/assembled_plot_meadow_robloxlook.png` (top, front, top-3/4, back-3/4). It uses the new
opt-in plan view `--views 4`.

## MeshPart budget (important)

One plot as above = **37 MeshParts**; 8 plots = **296**. That is over the v17 decor budget of
**150 per map** (CLAUDE.md, CONTRACT §10). Options:
1. Ship joined variants: one `fence_side` (8 segments + corner, about 1.7k tris) per side and one front
   (wings + gate_frame). That is about 7 MeshParts per plot (3 sides + front + gate_bar + sign + spare),
   56 per map. The same builders make them; it's a small script once the dimensions are confirmed.
2. Keep the modular pieces for editing and join in Studio (a union doesn't join MeshParts; needs a
   re-export).

## Assumptions Phoenix must confirm (layout redesign / v26)

1. The plot stays **56 x 56**.
2. The entrance stays on local **-Z** (toward the volcano).
3. A clear gate width of **8 studs** is enough for a player plus a carried slime (body diameter 3 at size
   1.0; bigger slimes are wider).
4. Fence height **~3.5** (pickets 3.1-3.4, posts 3.6) instead of the current Part walls (height 3).
5. Segment length **7** (8 per side) instead of the alternative 8 (7 per side; then the gate would need
   a different stub length).
6. The **LockBarrier** ForceField (height 16) stays separate. `gate_bar` is only visual/tint. Note: a
   MeshPart has one Material and one Color, so `Material = Neon` makes the **whole bar** glow, not just
   the latch, and `Color` tints the wood too. If only the latch should glow, it must become its own
   MeshPart (easy to split off).
7. The existing **Sign** (16 x 5 Part on 11-stud posts over the entrance) or the new `sign_board` mesh:
   which one wins? The sign_board is 6 x 3.5 and stands beside the path. It does not fit on the
   gate_frame lintel as is.
8. **New:** the gate is **11.75 tall**, not the brief's ~4.5. A crossbeam has to clear the avatar
   (5 studs) and the carried slime (`WorldView.CARRY_HEIGHT = 3` above the HumanoidRootPart, 3-stud
   body, so its top is around 7.5 to 9 studs). The underside is at 9.0. A lower frame needs no crossbeam.
9. **New:** the MeshPart budget (above): modular pieces x 8 plots = 296 against a budget of 150.
10. **New:** `gate_frame` covers 2 segments (14 studs, with stubs) so the front stays on the 7-stud
    grid; the gate posts themselves are 10.4 wide (outer).
