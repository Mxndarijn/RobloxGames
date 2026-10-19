# pet_mounts rounds (2026-10-19)
Ten smooth cosmetic mounts for the follow pet, same 3.3 x 2.4 footprint as pet_cloud. Per-round sheets: `sheets/pet_mount_<name>_rNN.png`
(r01 = the first version, 2476 to 3056 tris); final sheets `_after.png`, Roblox look `_after_robloxlook.png`, colour maps `_colormap.png`,
with-pet renders `pet_mount_<name>_with_pet.png`, lineup `pet_mounts_lineup.png`. Wall time of a round: 2 to 5 s (box load 20+ makes it 3x).

## Round 1 (first version, 8 builders then ufo + lily_pad)
| round | what changed and why |
|---|---|
| r01 | First complete set (sheets `_r01.png` = the old `_after`): metaball clouds with their own builder, pillow shells, tubes, crystals. Tris 1904 to 3056, over the 2000 target. Reviewed by Niels: carpet looks like a target with a comb fringe, leaf stem reaches the ground, bubble reads as an egg. |

## Round 2: rework after review (all tris 1712 to 1924)
| mount | round | tris | what changed |
|---|---|---|---|
| storm / sunset / ice / flame / rainbow cloud | r02 | 1842 / 1800 / 1894 / 1800 / 1786 | Own cloud builder removed: all five call `_pet_cloud.py cloud_parts()` (extra puffs for the flame tufts, a colour function for the rest), so they share the pet_cloud shape, one smooth pass and the footprint fit. Tri target 1800 via decimate (bolt, shards and rainbow tubes are budgeted out of it: rainbow 1150 + bands, ice 1250 + shards). Smooth-shaded, not faceted. |
| leaf | r02 | 1528 | Redo: thin cupped blade, raised midrib + 5 side vein pairs as real tubes, short stem. Too bowl-like, veins hooked. |
| leaf | r03 | 1712 | Flatter cup (edges up 0.15), pointed tip with a gentle upturn, thicker light veins on the blade, stem leaves the back edge and curls up (never near the ground), 52 segments. Final. |
| leaf | r04 | 1864 | Veins no longer geometry (the raised tubes read as loose sticks from the side): midrib + 5 side vein pairs painted light yellow-green (226,250,146) into the vertex colours on the darker green blade. The blade top is now an even grid whose rows follow the vein curves (`leaf_blade`), so the painted lines sit exactly on vertices and stay crisp; outline, cup, stem and size unchanged. Sheet `pet_mount_leaf_r04.png`. |
| bubble | r02 | 1856 | Pale pearl body with pastel pink / lilac / cyan / mint sheen gathered at the rim, strong white highlight plus a small bounce light, minis 2 to 3x bigger (r 0.36 / 0.27 / 0.17). Body resolution lowered to pay for them. |
| magic_carpet | r02 | 1776 | Redo: crimson field, purple border band with a cream/purple dash motif between gold lines, smooth gold-rimmed diamond medallion with a 4-point star, gold trim edge, gentle wave and curled +x corners, only 10 short chunky tassels on the two short ends. Pattern edges are real mesh rings (`ring_slab`), rim sampled at equal arc length, 56 segments. |
| ufo | r02 | 1924 | Hull 14 x 10 x 4 pillow, 6 lamps instead of 8, smaller underlight. |
| lily_pad | r02 | 1800 | Pond 8 x 6 x 3, pad 40 x 7 rings, petals and core kept at 80 tris each. |

## Final table
| mount | tris r01 (old) | tris final | W x H x D (studs) | seat z |
|---|---|---|---|---|
| `pet_mount_storm_cloud` | 2788 | 1842 | 3.30 x 1.23 x 2.40 | 1.23 |
| `pet_mount_rainbow_cloud` | 2812 | 1786 | 3.30 x 1.74 x 2.40 | 1.22 |
| `pet_mount_sunset_cloud` | 2600 | 1800 | 3.30 x 1.23 x 2.40 | 1.22 |
| `pet_mount_ice_cloud` | 2536 | 1894 | 3.30 x 1.70 x 2.40 | 1.22 |
| `pet_mount_flame_cloud` | 2800 | 1800 | 3.30 x 1.55 x 2.40 | 1.22 |
| `pet_mount_leaf` | 2684 | 1864 | 3.30 x 0.71 x 2.40 | 0.25 |
| `pet_mount_bubble` | 1904 | 1856 | 3.30 x 1.22 x 2.40 | 1.22 |
| `pet_mount_magic_carpet` | 2476 | 1776 | 3.30 x 0.57 x 2.40 | 0.30 |
| `pet_mount_ufo` | 2912 | 1924 | 3.30 x 1.34 x 2.40 | 1.00 |
| `pet_mount_lily_pad` | 3056 | 1800 | 3.30 x 1.56 x 2.40 | 0.99 |

Seat z = top surface under the centre (pet_cloud is 1.2). The cloud, bubble, ufo and lily pad mounts sit at 1.0 to 1.22; the thin carpet and
leaf float much lower (0.30, 0.25) because they have no pillar under them. Seat height per mount belongs to the PR that wires mounts into
`FollowPets`, not to these models.

## Weak spots left
- Carpet and leaf seat heights are far below the cloud's 1.2 (see above); the carpet fringe is only visible from low angles.
- Ice shards are close in colour to the cloud, flame tufts are fairly pointed at the tips; rainbow arch is thin behind the pet.
- The bubble is pale and iridescent but still opaque (no vertex alpha in Roblox); it reads as a pearl disc with bubbles.
- Looks are Cycles estimates, not Studio screenshots; nothing was uploaded or run in Studio.

## Round 3: cloud v3 + second set (2026-10-19)
The five cloud mounts were rebuilt on the refined pet_cloud (cloud v3, see `pet_cloud_rounds.md`) with no change to their own
code: `_r03.png`. Bolt, arch, shards and tufts still sit right on the new shape (checked against the old with-pet renders).

| mount | round | tris | what changed |
|---|---|---|---|
| star_cushion | r01 | 1320 | Star outline `slab()` (60 segments), pillowed top and bottom by a bend, yellow top, orange rim. 2.64 deep. |
| star_cushion | r02-r03 | 1320 | y scaled 0.92, then 0.9: inside 2.4. Keeps its own proportions (`NOFIT`): fitted to 3.3 x 2.4 it stops being a star. Final. |
| crescent_moon | r01 | 1596 | Swept crescent (68 degree arc, round section, width tapering to the horns). Read as a banana from every view; craters invisible. |
| crescent_moon | r02 | 1608 | Arc to 96 degrees (horns curl in), slimmer, richer gold. Still a banana from the top: the width tapered like a fruit. |
| crescent_moon | r03 | 1608 | Nearly even width with flat faces: a crescent coin. Craters painted on both flat faces at positions computed on the arc. Reads as a moon. |
| crescent_moon | r04 | 1608 | Review: the dark round craters read as Swiss cheese. Now 3 big soft dimples (wide falloff, lighter gold, 70 %). |
| mushroom | r01 | 1880 | Lathe cap with per-face colours (gill stripes underneath, red gradient), 9 raised spot lenses on the cap normal. Stem hidden under the cap. |
| mushroom | r02 | 1880 | Cap underside raised 0.12, stem longer: the stem shows from the front. Final. |
| pancakes | r01 | 2184 | 4 lathe cakes (browned faces, light side band), syrup slab, 6 tube drips. Over budget, syrup too orange. |
| pancakes | r02 | 1944 | 30 segments, darker syrup. With the pet the drips read as crab legs (they leave the glaze sideways). |
| pancakes | r03 | 1820 | The glaze outline reaches the rim at each drip; drips hang flat on the wall and end in a fat round drop (no separate beads). Final. |
| jelly | r01 | 1626 | Squircle lathe, 3 layers as exact ring bands (per-face colour), wobble bend, cream + cherry on a corner. The glossy streak was a square patch (a sticker). |
| jelly | r02 | 1626 | Streak narrowed to one column, lower two layers only, 50 %. Final. |
| hoverboard | r01 | 2104 | `ring_slab` deck with neon stripes, kicked nose and tail, pods + glow cones. 3.41 long, over budget. |
| hoverboard | r02 | 1928 | Shorter deck, 48 segments. Kept narrow (`NOFIT`). Final. |
| clam_shell | r01 | 1376 | Fluted dish (11 ribs as bend + rib colour), the same shell flipped as the lid, hinged at the back and opened 135 degrees, pearl in front. Final. |
| royal_cushion | r01 | 2100 | Squarish pillow with a button dimple, gold piping tube, corner tassels. Over budget. |
| royal_cushion | r02 | 1724 | Lower pillow resolution, 34 piping points. With the pet the tassels floated off the corners. |
| royal_cushion | r03 | 1724 | Tassels hang from the piping's corners (45 degrees on the squircle). Final. |

Weak spots: the hoverboard and the clam lid are big decoration around a low
seat; the star and hoverboard footprints are smaller than 3.3 x 2.4 on purpose. Still Cycles estimates: nothing uploaded or run in Studio.

## Crescent moon redo (2026-10-19)
Merijn: the slime disappears in the curve (the upright horns wrap round it). The moon now lies flat like a cushion.

| round | tris | what changed |
|---|---|---|
| r05 | 1726 | Flat crescent: a disc (R 1.48) with a bite (disc at y 1.107, r 1.17) filled with metaballs on a 0.2 grid, soft flat top. The slime sits fully on top. But the bite was shallow (reads as a bean pillow), the skin lumpy, the dimples like bruises. |
| r06 | 1776 | Deeper bite (y 0.95, r 1.2), ball size follows the distance to the edge so the horns taper to points, 2 smooth passes, no dimples. Reads as a crescent, but the star floated (the horn moved). |
| r07 | 1776 | Star pinned to the horn (found from the mesh, not a fixed point). Merijn: now it looks like a croissant (gold, puffy, fat curled ends). |
| r08 | 2052 | Pale lemon top, cool silver sides, lavender belly; bigger bite (y 1.2, r 1.45) for slim horns; smaller, flatter balls on a 0.12 grid; a star on each horn. |
| r09 | 1952 | Decimate target 1400. Final (OK'd by Merijn). |
