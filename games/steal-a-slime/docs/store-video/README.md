# Store-page video (draft)

Draft gameplay video for the Creator Hub game page (Game details → video). **Not uploaded anywhere.**
Merijn signs it off first (house rules 1–3); open [review.html](review.html) to watch it and pick.

| File | What | In git |
|---|---|---|
| `steal-a-slime-store-video-draft.mp4` | 1920×1080, 30 fps, 17.9 s, H.264, no audio, with captions | no (31 MB, gitignored) |
| `steal-a-slime-store-video-draft-nocaptions.mp4` | the same cut without captions | no (31 MB, gitignored) |
| `preview-720p.mp4` | 1280×720 copy of the captioned cut, for review.html | yes (5 MB) |
| `contact-sheet.jpg` | 12 frames from the captioned cut | yes |
| `render.sh` | assembles the MP4s from captured frames | yes |
| `capture/` | the tools that captured the frames | yes |

The full-quality MP4s are in this folder on the PC that made them
(`D:/SoftwareProjects/RobloxGames/.claude/worktrees/slime-store-video-3ce473/games/steal-a-slime/docs/store-video/`);
anyone else rebuilds them with `render.sh` from re-captured frames.

## The cut (17.9 s)

| Time | Shot | What happens in game | Caption |
|---|---|---|---|
| 0.0–3.6 | s1 hook | The player runs into a neighbour's jar base and grabs their Rainbow Celestial (a real steal through the server's `Carry.grab`), turns and runs out with it overhead. | STEAL rare slimes |
| 3.6–6.5 | s2 catch | Wild slimes ride the fountain slide and roam the lanes; the player grabs a wild Legendary (real `grabWild`) and runs at the camera. | Catch wild slimes |
| 6.5–10.1 | s3 rares | Orbit inside the player's base: Rainbow Celestial, Gold Secret, Divine "Goo God" (+$215K/s), Diamond Celestial, Gold Divine, with their pad labels and income. | Collect Divine and Rainbow slimes |
| 10.1–13.7 | s4 merge | Three Mythics in the merge vat finish brewing; the camera pans to the first input's pad as the brewed slime appears (real `VatCollect`). | Merge for rarer slimes |
| 13.7–17.9 | s6 end | Crane up from the fountain to the whole map with all eight jar bases. | STEAL A SLIME (title) |

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
   frame per capture: no stutter (checked: no frame-to-frame jumps in any shot).
4. `render.sh` trims the shots, adds the captions (Segoe UI Black, 84 px, title 150 px) and joins them with hard cuts.

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
cd ../.. && bash render.sh "$VIDEO_WORK/clips" .
python ../../../../tools/pipeline/pc-watcher/studio_hidden.py close <pid>
```

Shots are defined in `capture/drv/shots.py` (camera paths, character paths, the frame of the grab / collect).
Slime ids and wild positions change every run, so s2 picks its wild slime from `wild.json` by id prefix: edit
that prefix after running `wild.py`. A captured shot uses up its slime (stolen, caught, merged); re-stage before a
retake (release the carry, `prep_vat.py` for the merge).

## What I checked

- Looked at every shot as contact sheets and at the final cut (`contact-sheet.jpg`): no HUD, admin menu, output
  window, Studio chrome, name tags or debug text in frame; captions readable at 1080p.
- Frame-to-frame difference over every shot: no jumps; the only ramp is the deliberate fast pan in s4.
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
- Merge result is small on screen (mid-distance pad); the caption carries it.
- Not seen on a phone or in the Creator Hub player; no sound (by design); not uploaded (needs Merijn's OK).
