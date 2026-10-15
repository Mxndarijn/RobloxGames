# ranch_plaza_signpost rounds (jolt, 2026-10-15)
- r01 quick (1.3 s): 1.5 post + 3 arrow boards (yaw 0 / 150 / -35, z 10.0 / 8.1 / 6.2), red roof cap, cross-foot, goo puddle. 708 tris, 12.6 W x 14.5 H x 7.5 D, nm 0. Reads as a signpost from all 4 views; boards above avatar head.
- r02 roblox look (2.7 s): colours OK (cream + butter faces, red / wood frames), but the WOOD_D post goes near-black on the shadow side and the boards look thin next to the post.
- r03 roblox look (3.0 s): post 1.7 wide, WOOD_LO->WOOD gradient + cream cap; boards 6 x 1.9 faces in 7.2 x 2.5 frames. 688 tris, nm 0. Accepted.
- final: `--look roblox --ground 120,196,108 --turntable --no-export` (6.7 s): reads from all 8 angles; back/shadow side darkens like the avatar block (lighting).
SurfaceGui: each board has a blank face on both sides (Face0 yaw 0 z 10.0, Face1 yaw 150 z 8.1, Face2 yaw -35 z 6.2; faces 0.65 thick, frame 0.45).
