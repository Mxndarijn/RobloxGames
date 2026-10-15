# modeling-kit: rules for bots

Fast loop for low-poly Roblox props: bpy script → 4-view contact sheet + budget check → FBX. CPU only: about 2.5 s per round, 1.2 s for a `--quick` shape check.
This kit is Merijn's official modeling process: `PROCESS.md` (in this kit).

## Hard rules
- **Never upload for real, publish a place or `git push`** without Merijn's explicit OK. `upload.py` is a dry run unless `--go`.
- Never print, log, `cat` or commit `ROBLOX_OPEN_CLOUD_API_KEY` or `~/.config/roblox-ci.env`. Only `upload.py --go` may load that file into its own env.
- No paid services. Don't touch the game repos (`steal-a-slime-*`) from here; hand FBX files over instead.
- Commit locally in this repo only. Stage your own files by path.
- **Report the limits.** When a model hits the limits of this process (organic shapes such as slimes, characters or anything that needs sculpting; a quality ceiling where ~6 rounds don't make it good; rounds getting slow, over ~15 s), stop and report it to **SuperBottie**: which model, which limit, the sheets as evidence, and what would fix it (e.g. a generator API). SuperBottie decides what goes to Merijn. Don't quietly ship a weak model.

## The loop (per model)
1. **Read `LESSONS.md` first.**
2. Write the model as a bpy script: `models/<name>.py` (`from lib import *`, end with `finish("<name>", parts)`). Model in studs (1 Blender unit = 1 stud), Z up, front faces -Y, standing on z=0.
3. Run `python3 iterate.py models/<name>.py --sheet sheets/<name>_rNN.png`. It prints one line: PASS/FAIL, tris, size in studs, non-manifold edges, wall time.
   For shape-only steps (silhouette, proportions) use `--quick` instead: clay Workbench sheet with cavity + outline, ~1.2 s, no FBX. Don't judge colour from it.
4. **LOOK at the sheet with the Read tool** (always; the numbers aren't enough). Critique in this order:
   silhouette (readable from all 4 views? interesting outline?) → shape and proportions → scale against the grey 5-stud avatar block → colour (bright, saturated, value contrast between parts; gradients dark-below/light-above) → tris (spend them on the silhouette).
5. Change one or two things, rerun. Log the round in `sheets/<name>_rounds.md` (round, wall time, tris, what changed and why).
6. Stop at about **6 rounds**, or earlier when it's good. The final round's FBX is `out/<name>.fbx`; copy the sheet to `sheets/<name>_after.png`.
   Then check it the way the game will show it: `python3 iterate.py models/<name>.py --look roblox --no-export --turntable --sheet sheets/<name>_after_robloxlook.png` (~8.5 s with the turntable). If parts go muddy or too dark there, fix the colours and do one more round.
7. **Append lessons to `LESSONS.md`** (what worked, what didn't, any lib gotcha).

Watch mode (a person editing by hand, or a bot running it in the background): `python3 iterate.py models/<name>.py --quick --watch` re-runs on every save of the model or `lib/*.py`; the new sheet is ready ~1.2 s after the save.
Optional: compare with a concept image: `python3 compare.py out/<name>_sheet.png concept.png --tile front`.
Remaking an existing mesh: render it first with `python3 iterate.py path/to/old.fbx --no-export --sheet sheets/<name>_before.png`.

## Roblox limits (checked by iterate.py)
| Check | Rule | iterate.py |
|---|---|---|
| Tris per prop | target 500–2000 | warn outside |
| Tris per mesh | Roblox hard limit 20,000 | **fail at ≥ 10,000** (kit limit) |
| Size | ≤ 2048 studs per axis (MeshPart) | fail |
| FBX file | < 20 MB (Open Cloud upload) | fail; FBX deleted |
| Mesh objects | each one becomes a MeshPart | warn if > 1; use `finish()` |
| Non-manifold edges | holes and stray edges hurt collision and shading | warn |
| Vertex colours | without them the mesh imports grey | warn |
| Materials per mesh | a MeshPart has one Material/Color/TextureID/SurfaceAppearance | warn if > 1 used |
| Material colours | FBX material colours are ignored; only vertex colours survive | warn per material not driven by a colour attribute |
| Image textures | not carried by the kit's FBX upload | warn |
| Colour attributes | Roblox uses one | warn if > 1 (keep `Col`) |
| Vertex alpha | not used as transparency | warn if any < 1 |

FBX is written only when everything passes. It uses the v17 settings (`FBX_SCALE_UNITS`, forward -Z, up Y, flat faces, sRGB colours, modifiers applied). A `.obj` is written too.
v17 decor (CONTRACT §10): max decor axis 64 studs; a collidable canopy needs its underside ≥ 7 studs up; MeshPart budget 150 per map.

## `--look roblox`: what it does, and what it still gets wrong
It renders with the game's own Lighting (`steal-a-slime` `default.project.json`: Future, Brightness 2.5, ClockTime 14.5, latitude 25, Ambient, OutdoorAmbient, ExposureCompensation 0.1, BaseGrade colour correction) instead of the flattering 3-point studio light:
- material: SmoothPlastic-like (roughness 0.55, specular 0.2, no subsurface/coat/metal), colour from the vertex colours as Roblox would;
- one sun fixed in the world (~45° up, from front-left, warm, crisp shadows) + sky ambient (OutdoorAmbient, occluded) + flat Ambient (never occluded), no light bounce;
- Standard view transform (no Filmic/AgX), exposure +0.1, then the BaseGrade (contrast/saturation/tint) on the tiles.

**It is an estimate, not a calibrated match.** The values are the game's, but how they map to Cycles (sun strength, ambient split, no bounce) is my guess and hasn't been checked against a Studio screenshot yet. Still different:
- **Vertex colours**: the kit assumes Roblox shows FBX vertex colours as exported (sRGB). Not yet checked side by side in Studio for kit meshes; a MeshPart's Color/Material may tint them.
- **Shading detail at distance**: small bevels and facets that read in a 256 px close-up don't read at play distance; MeshPart **LOD** (RenderFidelity Automatic) also drops triangles far away. The renders always show full detail up close.
- **Bloom, SunRays, Atmosphere haze, Roblox's tone mapping**: not modelled (bloom barely touches matte props; haze matters for far objects).
- **Shadows and occlusion**: Future shadow maps are softer and lower-res; Roblox's sky occlusion is coarse (voxel grid), so Cycles crevices come out darker than in-game.
- **Time and placement**: the game runs a day/night cycle (06:30–17:30 day), so 14.5 is one moment; the real sun side depends on how the prop is rotated in the map.
- **Screen**: phone size, compression and the device's display aren't simulated.
Use it to catch "too dark / muddy / washed out" before Phoenix's Studio gate. That gate's screenshot is the truth; when one is available, calibrate `RBX` in `kit/bl_iterate.py` against it and note it in LESSONS.md.

## Files
- `iterate.py`: the loop (host; also `--quick`, `--watch`, `--look roblox`, `--turntable`, the BaseGrade, GIF/strip). `kit/bl_iterate.py` runs inside Blender (stats, rig, renders, export; `RBX` = the Roblox look values).
- `lib/`: bpy helpers: `box cylinder cone blob tube gradient noise_bm jitter_bm bevel decimate join cleanup finish origin_bottom_center tris rgb hexc shade mix PALETTE studs meters`.
- `examples/`: `rock.py`, `mushroom.py`. `models/`: real assets (`tree_oak.py`).
- `compare.py`: render vs concept (side-by-side sheet + score). `upload.py`: Open Cloud create/update, dry run by default.
- `sheets/`: contact sheets and round logs (committed). `out/`: build output (only final FBXs committed). Modes write separate files (`<name>_quick_sheet.png`, `<name>_roblox.stats.json`, `<name>_roblox_turntable.gif`...) and never overwrite the default round's files.
