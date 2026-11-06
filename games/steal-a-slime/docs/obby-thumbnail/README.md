# Obby thumbnail (picks)

Three 1920×1080 thumbnails of the Goo Gauntlet sky course for the game page, in the style of the existing
thumbnails. Open [review.html](review.html) to pick. **Decided: B** ("NEW OBBY / EVERY 30 MIN!"). Merijn's pick, verbatim: "B, every 30 min". **Not uploaded**: `thumb-B.jpg` is the file to upload.

- `thumb-A.jpg`, `thumb-B.jpg`, `thumb-C.jpg`: the three picks; `caption-*.jpg`: every caption on picture B.
- `make_thumbnails.py <stills-dir> <out-dir>` draws them from raw stills `A.jpg B.jpg C.jpg`, with the store
  video's caption, drip and sparkle code (`../store-video/render.py`, Lilita One).

Stills were taken in a hidden, muted Studio on the memory store (the store-video capture build, see
`../store-video/README.md`): the test player walks into the portal, the run starts, game time is frozen, and
`../store-video/capture/drv/still.py <out> <t> <cam offset> <look offset> [fov] [dof]` poses the jump of the
obby shot (`s5` in `capture/drv/shots.py`) at time `t`, with the follow-pet cloud hidden.
The course comes from the rotation that was live in that session; a re-shoot gets another course and needs new
step positions in `shots.py`.
