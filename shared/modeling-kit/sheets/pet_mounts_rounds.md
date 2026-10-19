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
