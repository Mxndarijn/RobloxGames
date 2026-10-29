# Pet mounts (future cosmetics, models only)

Eighteen FBX meshes a follow pet can sit on instead of the `pet_cloud`: same footprint (3.3 x 2.4 studs, origin bottom centre,
front -Y, 1 BU = 1 stud), same smooth, soft, rounded slime-cartoon style (smooth normals, vertex colours, one mesh each).
**Not registered, not uploaded, no game code.** Review images are committed in `sheets/`: `pet_mounts_lineup.png` (all eighteen with a tier-3 slime), `pet_mounts_set2_lineup.png` (the second set of eight), `pet_mount_<name>_with_pet.png`,
`_after.png`, `_after_robloxlook.png`, `_colormap.png` and the per-round `_rNN.png`; the round log is `sheets/pet_mounts_rounds.md`.

| mount | tris | W x H x D (studs) | seat height | look |
|---|---|---|---|---|
| `pet_mount_storm_cloud` | 1842 | 3.30 x 1.23 x 2.40 | 1.22 | dark grey pet_cloud shape, yellow lightning bolt off the front-right |
| `pet_mount_rainbow_cloud` | 1786 | 3.30 x 1.74 x 2.40 | 1.22 | white cloud, six-band rainbow arch over the back rim |
| `pet_mount_sunset_cloud` | 1798 | 3.30 x 1.23 x 2.40 | 1.22 | peach / pink / orange gradient cloud |
| `pet_mount_ice_cloud` | 1894 | 3.30 x 1.70 x 2.40 | 1.22 | icy pale-blue cloud with crystal shards round the rim |
| `pet_mount_flame_cloud` | 1800 | 3.30 x 1.53 x 2.40 | 1.22 | red / orange cloud with soft flame tufts, yellow tips |
| `pet_mount_leaf` | 1864 | 3.30 x 0.71 x 2.40 | 0.25 | cupped green leaf raft, pointed tip, midrib + 5 side vein pairs painted light green into the vertex colours (no raised geometry), short stem curling up from the back |
| `pet_mount_bubble` | 1856 | 3.30 x 1.22 x 2.40 | 1.22 | pale pearl soap-bubble disc, pastel sheen, white highlight, three bigger mini bubbles |
| `pet_mount_magic_carpet` | 1776 | 3.30 x 0.57 x 2.40 | 0.30 | Persian carpet: crimson field, purple dash-motif border, gold diamond medallion, gold trim, short tassels on the short ends, gentle wave |
| `pet_mount_ufo` | 1924 | 3.30 x 1.34 x 2.40 | 1.00 | saucer: blue-grey hull, 6 rim lamps, glass dome at the back, cyan underlight |
| `pet_mount_lily_pad` | 1800 | 3.30 x 1.56 x 2.40 | 0.99 | green lily pad with notch and veins, pink lotus bud, on a water disc |
| `pet_mount_star_cushion` | 1320 | 3.09 x 0.94 x 2.38 | 0.94 | puffy golden 5-point star pillow, one point to the front, orange rim (own proportions, not stretched to 3.3 x 2.4) |
| `pet_mount_crescent_moon` | 1950 | 3.00 x 0.88 x 1.77 | 0.63 | pale crescent lying flat like a cushion (a disc with a big bite out of the back): pale lemon top, cool silver sides, lavender belly, slim horns sweeping low behind the pet, a star on each horn (own proportions) |
| `pet_mount_mushroom` | 1880 | 3.30 x 1.25 x 2.40 | 1.23 | red toadstool cap with 9 raised white spots, striped cream gills, short stout stem |
| `pet_mount_pancakes` | 1820 | 3.30 x 0.99 x 2.40 | 0.99 | four golden pancakes, off-centre, maple syrup glaze with five drips down the side |
| `pet_mount_jelly` | 1626 | 3.30 x 2.18 x 2.40 | 1.17 | wobbly three-layer jelly (raspberry, mango, lime), glossy streak, whipped cream + cherry on the front-right corner |
| `pet_mount_hoverboard` | 1928 | 3.27 x 1.00 x 1.41 | 0.70 | purple deck, two cyan neon stripes, dark grip pad, magenta rim, kicked-up nose and tail, two thruster pods with pale cyan glow cones (own proportions) |
| `pet_mount_clam_shell` | 1376 | 3.30 x 2.26 x 2.40 | 0.80 | coral scallop dish with 11 ribs and a pearly inside, the lid standing open behind the pet, a pearl in front |
| `pet_mount_royal_cushion` | 1724 | 3.30 x 0.80 x 2.40 | 0.80 | plump purple velvet cushion, gold button, gold piping round the seam, a gold tassel on each corner |
| `pet_mount_pumpkin` | 1970 | 3.30 x 1.64 x 2.40 | 1.20 | Halloween (limited): squat 8-lobed jack-o'-lantern, friendly carved face (amber glow decals with a dark rim, two uncarved teeth), stem at the back of the top, curly vine + five-lobed leaf on the back shoulders |
| `pet_mount_snowglobe` | 1992 | 2.32 x 2.05 x 2.32 | 2.05 | winter (limited): round wooden base with red band and butter trims, sky-cyan globe with a shine streak, snowy floor, two pine trees + star and snowflakes as decals, flat snow cap with soft drips for the seat (own proportions, `NOFIT`) |

Seat height = top surface under the mount's centre (what a pet's foot should touch; the pet_cloud is 1.2). The clouds, bubble, ufo and
lily pad sit at 1.0 to 1.23; the thin leaf (0.25) and carpet (0.30) float much lower because nothing is under them. The game must
read the seat height per mount; that belongs to the PR that wires mounts into `FollowPets`, not to these models.
The second set: mushroom 1.23 and jelly 1.17 match the cloud; pancakes and star sit at 0.94 to 0.99, clam and royal cushion
0.80, moon 0.63, hoverboard 0.70. Height above ~1.3 is decoration beside the seat (rainbow arch, ice shards, flame tufts, lotus bud, leaf rim,
moon stars, jelly cherry, clam lid).

## Files
- `models/_pet_mount.py`: shared builders (`pillow` rounded shells, polar `slab`, `ring_slab` with exact per-face pattern edges, crystals, extruded bolt, `ship()`: fit the footprint to 3.3 x 2.4, `finish()`, restore smooth flags and set `smooth_normals` so the FBX keeps the soft shading).
- The cloud mounts do not have their own cloud builder: they call `models/_pet_cloud.py` `cloud_parts()` (the pet_cloud builder; defaults = the shipped pet_cloud).
- `models/_pet_mounts.py`: one builder per mount (`MOUNTS` dict); `models/_pet_mounts_extra.py`: the second set (`EXTRA`, merged into `MOUNTS`; `NOFIT` = mounts that keep their own proportions instead of the 3.3 x 2.4 fit) plus `rings_mesh` / `lathe_rings` (closed shells through explicit rings, optional one colour per face for crisp stripes); `models/pet_mount_<name>.py`: the 3-line generator that ships it.
- `models/_pet_mount_scene.py`: preview only. Mount x0.9, tier-3 slime x0.55 sunk 0.12 into the seat (as `_pet_cloud_scene.py`), pitched 20 degrees so the seat shows.
- `tools/pet_mounts_render.py` (alone / with pet 3/4 renders, lineup), `tools/pet_mounts_colormap.py` (colour maps).
- `out/pet_mount_<name>.fbx` and `.stats.json` (committed; `.obj`/`.mtl` and the `_roblox*` / `_quick*` side outputs are not).

## Colour maps
The meshes carry **vertex colours only** (no UV texture: the kit's FBX upload does not carry image textures), so the
"colour map" is `sheets/pet_mount_<name>_colormap.png`: the vertex colours drawn flat and unlit (3/4 + top) with the 8
dominant colours as hex swatches. There is no `models/textures/` folder in this repo.

### Rebuilding the colour maps
`out/*.obj` is gitignored, so `tools/pet_mounts_colormap.py` only works after a local rebuild:
```
cd shared/modeling-kit
for n in storm_cloud rainbow_cloud sunset_cloud ice_cloud flame_cloud leaf bubble magic_carpet ufo lily_pad \
         star_cushion crescent_moon mushroom pancakes jelly hoverboard clam_shell royal_cushion; do python3 iterate.py models/pet_mount_$n.py; done
python3 tools/pet_mounts_colormap.py --out renders/pet_mounts --copy sheets
python3 tools/pet_mounts_render.py --out renders/pet_mounts --lineup   # with-pet renders + lineup (slow: 20 Cycles renders)
```
Run `iterate.py --look roblox` rounds one at a time: parallel runs share `out/.tiles` and clobber each other.
`--suffix _v2` appends a suffix to every file name; `--view side` renders the level profile.
Avoid `iterate.py --quick` for these (it writes `*_quick*` files into `out/`); use `--out <tmp dir>`.

## Known weak spots
See `sheets/pet_mounts_rounds.md`.
