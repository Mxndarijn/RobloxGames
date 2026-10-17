# slime_lane rounds (2026-10-17)
Before: ~50 sunk Cylinder parts with mitred joins (ParadeLane.strips), angular in game (bug 4). Now one smooth swept mesh.

| round | wall | tris | size (studs) | change / why |
|---|---|---|---|---|
| r01 | 5.8 s | 5482 | 141.08 x 0.43 x 137.72 | Centripetal Catmull-Rom through all 144 centreline points (inputs/slime_lane_centreline.json), 211 rings resampled by curvature (0.9-2.0 studs), 11-point domed section (crown 0.35, edge -0.05, skirt to -0.08), darker rim vertex colour, smooth normals (`smooth_normals` custom prop -> FBX normals only) |
