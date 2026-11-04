# Shop models v2 (2026-11-04): claw prize capsule + three seat reworks

Why: the Exclusive Shop showed "plain white orbs": the claw show grabs a plain lilac Ball as the prize, and the Bubble,
Crescent Moon and Ice Cloud seats read as a white disc, a cream blob and a grey-blue blob in game
(`games/steal-a-slime/docs/shop-audit/meshes_ingame.jpg`). All rounds are ~1.7 s Cycles sheets (`--no-ref --res 320`
close-ups unless noted); the final check is `--look roblox`. Before pictures: `pet_mount_<name>_v2_before_robloxlook.png`
(the old FBX rendered with `--look roblox`).

Sizes are Roblox X, Y (up), Z in studs. Seat = top surface over the bbox centre (`ship()` SEAT print), where the game puts the pet.

## claw_prize_capsule (new, `models/claw_prize_capsule.py`)
| round | tris | change |
|---|---|---|
| r01 | 1384 | lathe sphere r 0.62: lilac dome, mint base, gold torus band, bevelled extruded gold star, white streak tube + dot. Reads as a gacha capsule right away; over the 1200 budget, star low and sticking out at the side. |
| r02 | 1098 | own faceted star (raised centre, 38 tris) instead of the bevelled one, star higher (el -26 deg), thinner band (5 sides), longer/thicker streak. |
| r03 | 1098 | star sunk 0.035 into the shell (side view no longer pokes out), streak moved from the left silhouette onto the front face. |
| r04 | 1136 | second star on the back (the game spins the prize at 40 rpm), star shading by outward normal so the back one is lit too. |
| look | | `--look roblox`: shadow side of the dome went deep purple, band underside brown. |
| r05 | 1136 | lifted darks: glass low 200,176,246, mint low 74,206,164, gold low 250,184,60; dropped the far-side darkening. |
| r06 | 1136 | refactor only: the star now comes from the shared `facet_star()`; same tris and look. |

Final: **1136 tris, 1.35 x 1.24 x 1.35 studs** (1.3 target, +3.8 % with the band and stars; inside ±10 %), stands on z = 0, 1 mesh, 0 non-manifold, PASS.
Sheets: `claw_prize_capsule_v2_r06.png`, `claw_prize_capsule_v2_robloxlook.png`.
Verdict: **good**. Lilac dome + white streak, gold band, mint base, gold star all read at 320 px; the shadow side still goes
plum in the Roblox look (lighting; the avatar block does the same). Game note: `makePrize` builds a Ball Part today; the mesh
needs a MeshPart with `Color` white (Color multiplies vertex colours) and size ~1.3, which is game code, not done here.

## pet_mount_bubble (rework; builder `bubble()` in `models/_pet_mounts.py`)
Before: 1856 tris, 3.30 x 1.22 x 2.40, seat 1.22; pale pearl disc with colour only at the rim.
| round | tris | change |
|---|---|---|
| r01 | 2360 | same pillow shape; new `bubble_paint()`: wide swirling bands pink / lilac / sky / mint / butter (mostly flat colour, short blends), seat only slightly paler; white highlight window + dot decals; banded satellites with white glints. Colourful at last, but over 2000 tris and the highlights hidden. |
| r02 | 1864 | pillow nz 6 -> 5, satellites subdiv 2, bigger highlight window. Highlights landed on the flat TOP (cast direction had too much -z): under the pet. |
| r03 | 1972 | highlight cast nearly horizontal at wall height: now on the front-left shoulder; pillow 14 x 10 x 5; big satellites back to subdiv 3 (subdiv 2 was faceted). |
| r04 | 1876 | second highlight window + dot on the back-right shoulder (the pet follows the player, the back is seen most); middle satellite back to subdiv 2 to stay under 2000. |

Final: **1876 tris, 3.30 x 1.22 x 2.40** (same as before), **seat 1.22** (Config 1.22), PASS, 0 non-manifold.
Sheets: `pet_mount_bubble_v2_r04.png`, `pet_mount_bubble_v2_robloxlook.png`.
Verdict: **good** on colour (clearly an iridescent soap bubble, not a white orb, in both looks). Shape is unchanged (a plump
oval pillow); the small satellite at subdiv 2 shows slight facets up close.

## pet_mount_crescent_moon (rework; builder `crescent_moon()` in `models/_pet_mounts_extra.py`)
Before: 1950 tris, 3.00 x 0.88 x 1.77, seat 0.63; pale lemon top, silver sides.
| round | tris | change |
|---|---|---|
| r01 | 2192 | warm gold paint (butter 255,228,104 top, gold 255,196,58 sides, amber 240,160,64 belly); sleepy face decals on the front wall (closed-eye arcs, smile, pink cheeks). Face reads well; stars vanish (gold on gold); top view banana-like. |
| r02 | 2152 | horn stars now cream-white `facet_star()` (20 tris each instead of 276); pale lemon horn tips (dark tips = banana); amber crater decals on the horns. Craters read as banana bruises. |
| r03 | 1920 | craters dropped; three small white 4-point twinkle stars pressed onto the outer wall. One twinkle (172 deg) partly missed the surface and drew a white sliver across the bite. |
| r04 | 1920 | that twinkle moved to 196 deg: clean. |

Final: **1920 tris, 3.00 x 0.90 x 1.79** (height +2 %, depth +1 %), **seat 0.63** (Config 0.63), PASS, 0 non-manifold.
Sheets: `pet_mount_crescent_moon_v2_r04.png`, `pet_mount_crescent_moon_v2_robloxlook.png`.
Verdict: **ok**. Saturated gold, cute sleepy face from the front, stars readable. From above / behind it still reads somewhat
like a banana (the flat crescent shape itself, an old lesson); fixing that needs a geometry change (deeper bite, curlier
horns) that I did not risk against the seat-at-bbox-centre rule. Warm yellows went olive in an earlier Studio check
(LESSONS, shop stands 2026-10-20): check this gold in Studio.

## pet_mount_ice_cloud (rework; builder `ice_cloud()` in `models/_pet_mounts.py`)
Before: 1894 tris, 3.30 x 1.70 x 2.40, seat 1.22; mid-blue cloud and same-blue shards.
| round | tris | change |
|---|---|---|
| r01 | 1894 | frosty white cloud (sky blue only low down); shards painted per FACE (`paint_facets()`): saturated ice blue, lighter to the tip, lit facets near white (sparkle), shadow facets deeper blue. Reads as ice now. |
| r02 | 1908 | cloud gradient bluer at the belly (128,194,252), cloud 1250 -> 1080 tris, two more small shards (front-left, back) so the front view shows ice too. |

Final: **1908 tris, 3.30 x 1.70 x 2.40** (same as before), **seat 1.22** (Config 1.22), PASS, 0 non-manifold.
Sheets: `pet_mount_ice_cloud_v2_r02.png`, `pet_mount_ice_cloud_v2_robloxlook.png`.
Verdict: **good**. White frosty cloud with clear blue crystal spikes in both looks. The cloud body is the shared lumpy
`cloud_parts()` shape (unchanged).

## Not checked
- None of the four was looked at in Studio or on a phone; the Roblox look is an estimate (see CLAUDE.md).
- Not uploaded (no `upload.py --go`); the game still uses the old asset ids. The capsule is not wired into `ShopDisplayFx`.
- The `_with_pet` renders, lineup and colour maps (`tools/pet_mounts_render.py`, `tools/pet_mounts_colormap.py`) were not re-rendered.
