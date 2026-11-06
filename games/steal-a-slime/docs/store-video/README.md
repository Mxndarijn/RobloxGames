# Store-page video (draft)

Draft gameplay video for the Creator Hub game page (Game details → video). **Not uploaded anywhere.**
Merijn signs it off first (house rules 1–3); open [review.html](review.html) to watch it and pick.

| File | What | In git |
|---|---|---|
| `steal-a-slime-store-video-draft.mp4` | **A**: 1920×1080, 30 fps, 17.9 s, H.264, no audio, thumbnail-style captions | no (gitignored, ~40 MB) |
| `steal-a-slime-store-video-draft-deco.mp4` | **B**: A plus the slime-drip top border and twinkling sparkles | no (gitignored, ~40 MB) |
| `steal-a-slime-store-video-draft-nocaptions.mp4` | **C**: the same footage, clean | no (gitignored, ~40 MB) |
| `preview-720p.mp4`, `preview-720p-deco.mp4` | 1280×720 copies of A and B, for review.html | yes |
| `contact-sheet.jpg`, `contact-sheet-deco.jpg` | 12 frames from A and from B | yes |
| `before-after.jpg` | the same four moments, draft 2 capture (left) and draft 3 capture (right) | yes |
| `reference-thumbnail.jpg` | one of the game's thumbnails, the style the captions copy | yes |
| `render.py` | draws the captions and assembles the MP4s from captured frames | yes |
| `fonts/` | Lilita One (SIL Open Font License, `fonts/OFL.txt`) | yes |
| `capture/` | the tools that captured the frames | yes |

The full-quality MP4s are in this folder on the PC that made them
(`D:/SoftwareProjects/RobloxGames/.claude/worktrees/slime-store-video-3ce473/games/steal-a-slime/docs/store-video/`);
anyone else rebuilds them with `render.py` from re-captured frames.

## The cut (17.9 s)

| Time | Shot | What happens in game | Caption |
|---|---|---|---|
| 0.0–3.6 | s1 hook | The player runs into a neighbour's jar base and grabs their Rainbow Celestial (a real steal through the server's `Carry.grab`), turns and runs out with it overhead. | STEAL / RARE SLIMES! |
| 3.6–6.5 | s2 catch | By the fountain slide the player grabs a wild Mythic off the lane (real `grabWild`) and runs at the camera. | CATCH / WILD SLIMES! |
| 6.5–10.1 | s3 rares | Orbit inside the player's base: Rainbow Celestial, Gold Secret, Divine "Goo God" (+$215K/s), Diamond Celestial, Gold Divine, with their pad labels and income. | SHINY / DIVINE SLIMES! |
| 10.1–13.7 | s4 merge | Three Mythics in the merge vat finish brewing; the camera pushes in on the vat and the pad beside it as the brewed Secret appears (real `VatCollect`). | MERGE 3 / = RARER! |
| 13.7–17.9 | s6 end | Crane up from the fountain to the whole map with all eight jar bases. | STEAL / A SLIME! (title, centre) |

### Caption style

Copied from the game's thumbnails (`reference-thumbnail.jpg`): all caps in **Lilita One** (Google Fonts, SIL Open
Font License 1.1, free for commercial use; the closest free match to the thumbnail lettering), the first word in a
yellow-to-orange vertical gradient and the rest in mint-to-teal, a thick dark teal outline, a dark extrusion and soft
shadow below, a 2.5° tilt, about 70% of the frame width, bottom centre (the end title is centred). Each caption pops
in 0.12 s after the cut with a 0.32 s overshoot bounce, stays up for the rest of the shot (2.6–3.9 s) and shrinks
away in the last 0.12 s. Version B adds the thumbnails' mint slime-drip border along the top edge and a few white
four-point sparkles near the hero object that twinkle. The sparkles sit at fixed screen spots, so on moving shots
they do not stick to the slime; the drips cover the top ~6–14% of the frame. All of it is drawn with Pillow onto
each frame (`render.py`), not with ffmpeg drawtext.

No sound track: the store video plays muted and Roblox rejects copyrighted music. A track can be added later from
the game's own approved audio.

## How it was captured

Studio's `screen_capture` takes about 1.2 s per frame, so real-time recording is impossible. Instead every frame of
the game is stepped by hand:

1. `capture/build.sh` builds a **throwaway** place into `$VIDEO_WORK` (outside the repo): a copy of `src` where every
   `os.clock()` and `workspace:GetServerTimeNow()` reads workspace attributes `VClock` / `VServer` when they are set
   (`capture/vclock.py`), plus three scratch-only patches (`capture/patches/`): stand-in owners on free plots
   (`vidFake`), a spawn with a shine (`vidSpawn`), and a `VidReq` workspace attribute that runs the real Request
   handler, a real grab / deposit, or a server snippet. `DataStoreMode = "Memory"` is set; the place is never saved
   back, published or uploaded. **Never apply these patches to `src`.**
2. The place runs in a hidden, muted Studio (`tools/pipeline/pc-watcher/studio_hidden.py`, every Sound/SoundGroup
   volume forced to 0). The scene is staged through the admin cheats on the memory store (`capture/scene.json`):
   rare slimes with shines on my pads, three stand-in neighbours ("Gloopy", "Bloop", "Mochi"), clear weather, no
   Slime Rain, the anti-cheat in watch mode (my scripted moves look like teleports to it).
3. `capture/drv/clip.py <shot>` then, per frame: advances `VClock`/`VServer` by 1/30 s on the server, sets the
   camera (a scripted CFrame locked by `capture/lua/ctl.luau`, all HUD, billboards and prompts hidden) and poses the
   player character (position plus the R15 run/idle animation at a fixed time position), waits for the client to see
   the new time, and captures. So slime animations, wild slime walks, carries and the merge all move exactly one
   frame per capture. Particle emitters (sparkles, auras, glints) don't read the game clock, so each frame also sets
   every emitter's `TimeScale` to (1/30 s) / (real time between captures), which steps them at video speed too.
   `capture/lua/look.luau` sets the capture-only look on the client (draft 3): quality Level 21, mesh detail Level04,
   `RenderFidelity = Precise` on every MeshPart, an extra ColorCorrection (saturation +0.2, contrast +0.12), half the
   Atmosphere haze, half the Bloom, exposure -0.2, and a soft far depth of field on the close shots (`dof` in
   `shots.py`). None of it touches the game's own `Lighting` in `src` or `world/`.
4. `render.py` trims the shots, crops to 16:9, sharpens lightly (unsharp mask, the capture JPEGs are soft), draws the
   captions (and in B the drips and sparkles) and joins the shots with hard cuts, x264 CRF 16 (~18 Mbit/s).

### Re-render

```sh
# from games/steal-a-slime/docs/store-video, with VIDEO_WORK set to a scratch folder outside the repo
bash capture/build.sh
python ../../../../tools/pipeline/pc-watcher/studio_hidden.py open "$VIDEO_WORK/video.rbxl"   # keep the pid
cd capture/drv
python drv.py play 1                                  # start play + mute
python drv.py req "$(cat ../scene.json)"              # stage the scene (memory store only)
python ids.py && python wild.py                       # ids of the pad and wild slimes for shots.py
python clip.py s1                                     # likewise s2, s3, s4 (run prep_vat.py first), s6
cd ../.. && python render.py "$VIDEO_WORK/clips" .     # needs Pillow; --sample 30,250 writes test frames only
python ../../../../tools/pipeline/pc-watcher/studio_hidden.py close <pid>
```

Shots are defined in `capture/drv/shots.py` (camera paths, character paths, the frame of the grab / collect).
Slime ids and wild positions change every run, so s2 picks its wild slime from `wild.json` by id prefix: run it as
`WILD_ID=<prefix> python clip.py s2` after `wild.py` (the player needs rebirths for rare wild slimes: `scene.json`
sets 20). A captured shot uses up its slime (stolen, caught, merged); re-stage before a
retake (release the carry, `prep_vat.py` for the merge).

## What I checked

- Looked at every shot as contact sheets and at the final cuts (`contact-sheet.jpg`, `contact-sheet-deco.jpg`): no
  HUD, admin menu, output window, Studio chrome, name tags or debug text in frame; captions readable at 1080p.
- Caption pop-in checked frame by frame (tiny, overshoot, settle) and compared side by side with a thumbnail.
- Draft 3 "glitchy world" hunt (Merijn: "the world was glitchy, it did not look normal"). The draft-1 frames were
  scored for one-frame pops (a frame that differs from the mean of its neighbours). Causes found and fixed:
  1. **Particles ran in real time** while the game clock was stepped: each capture took ~1.5 s, so sparkles, auras
     and glints jumped ~45 frames' worth between video frames and flickered (worst in s3, the rare-slime orbit:
     9.6% of each frame popped). Fixed with the emitter `TimeScale` step above: s3 4.4%.
  2. **s3 orbited 110° in 3.6 s** at 9 studs from the slimes, so close slimes swept across the frame like a strobe.
     Now 40° at 10 studs.
  3. **s4 had a whip pan** that swung the camera through the floor and the column for ~25 frames (pops up to 20%).
     Now a slow push-in with the vat and the result pad side by side (1.3% mean).
  No `minterpolate` or frame blending was ever used; no z-fighting or missing / low-detail meshes found in the frames.
  The remaining "pops" in s1, s2 and s6 are fast but even camera moves over busy detail (checked as frame triplets).
- Every gameplay beat ran through the real server code: the steal and the wild catch through `Carry.grab`, the merge
  through `VatStart` / `VatCollect`. Server results were logged (all `ok`).
- `ffprobe`: 1920×1080, 30 fps, 17.93 s, H.264 yuv420p, faststart.

## What I could not get or check

- **Not watched as moving video by a person.** I judged motion from frame sequences and the difference check only.
- **PvP bat bonk not in the cut.** A second real player can't join a hidden Studio without a visible window, and a
  stand-in owner has no character, so a bonk would have been a puppet; left out instead of faked.
- **Rebirth, Top Earners podium and boss shots not in the cut.** The boss was out during capture (it walks the
  lanes), but I ran out of time to stage it. Easy follow-ups with the same tools.
- **The drop-off at home (slime lands on a pad and starts earning) was dropped.** The game deposits as soon as the
  carrier reaches the base edge, before the camera saw it, and my one retake framed it badly. Earning is shown in
  s3 through the pad income labels (+$/s) instead.
- **Thief is Merijn's own avatar** (the Studio test player). His VIP member tag and name are hidden, but the
  avatar look is his. If that should not be on the store page, re-shoot with a different test avatar.
- Not seen on a phone or in the Creator Hub player; no sound (by design); not uploaded (needs Merijn's OK).
