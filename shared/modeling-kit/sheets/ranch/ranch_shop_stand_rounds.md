# ranch_shop_stand rounds (jolt, 2026-10-15)
Remake of the greybox `Props.shopStand` (counter 10 x 3.7 x 4, back 9 tall, awning ~9.4, SHOP sign 7 x 1.8 at ~10.8).
- r01 quick (1.3 s): plank counter + cream top, 4 posts, back wall + shelf with 5 goo jars, 7-stripe awning (back 11 -> front 9) with flap + half-round scallop valance, SHOP sign on the back posts. 2156 tris (over target), 12.0 W x 14.2 H x 7.4 D, nm 0. Silhouette reads as a market stall.
- r02 roblox look (3.0 s): dropped bevels on counter planks + stripes, cream caps on the back posts. 1732 tris. Sign face was flush with its frame front (both y 2.0) and read dark; scallops painted flat with the low colour went maroon / grey.
- r03 roblox look (3.1 s): sign face pulled 0.25 forward (outer y 1.75), scallops gradient mix(lo, hi, 0.6) -> hi, two cream battens on the back wall. 1820 tris. Front/scallops still darker only from shadow side (back face is sun-lit in this render).
- r04 roblox look (3.3 s): turntable at 180 deg showed jar colours through the back board gaps; added a solid WallCore behind the boards. 1832 tris, nm 0. Accepted.
- final: `--look roblox --ground 120,196,108 --turntable --no-export` (7.3 s).
In-game hookup: awning underside front ~8.6 (>= 7 canopy rule). Counter top 11 x 4.2, top z 4.1 (put the invisible `Counter` PrimaryPart with the prompts there). SHOP SurfaceGui on SignFace: 7.6 x 2.0, centre z 12.2, outer face y 1.75 (front, -Y).
