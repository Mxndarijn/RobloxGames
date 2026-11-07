# Ad images (picks)

Seven 1920×1080 ad images for the Roblox Ads Manager test, in the style of the game's thumbnails, plus 1:1 square
crops of three. Open [review.html](review.html) to pick. **Not uploaded** (not to Roblox, not to Ads Manager).

| File | Moment (all real game moments, memory store) | Caption |
|---|---|---|
| `ad-boss.jpg` (+ square) | The slime boss on the lane, the player jumping at it | BEAT THE BOSS! |
| `ad-thief.jpg` (+ square) | A player running off with a stolen Rainbow Celestial, the owner chasing | CATCH THE THIEF! |
| `ad-divine.jpg` (+ square) | The Divine "Goo Oracle" on its pad, the player cheering | FIND A DIVINE! |
| `ad-rainbow.jpg` | The Rainbow Divine "Kirin" (+$9.73M/s) on its pad | RAINBOW SLIMES! |
| `ad-rich.jpg` | A $16.4M cash pad next to a Rainbow Celestial earning +$3.52M/s | GET RICH! |
| `ad-egg.jpg` | A Speckled Mystery Egg ready to hatch on a pad | HATCH EGGS! |
| `ad-claw.jpg` | The Slime Claw exclusive shop | SLIME CLAW! |

`make_ads.py <stills-dir> <out-dir>` draws them from the raw stills with the store video's caption, drip and
sparkle code (`../store-video/render.py`, Lilita One). The stills came from the store-video capture build in a
hidden, muted Studio (`../store-video/README.md`), graphics quality 21, game time frozen, HUD and labels hidden;
`../store-video/capture/drv/adshot.py` poses the player (R15 animation at a fixed time) and the camera per shot.

Not made (honest-ads rule):
- **REBIRTH = x2**: not true. Each rebirth tier adds a few percent income (`Config.REBIRTH_TIERS`, +5–150 %), not x2.
- **SLIME RAIN**: in the game a Slime Rain shows as small sparkles while slimes still come down the fountain slide one
  by one; there is no "slimes falling from the sky" moment to capture.
- **Starfall at night**: the falling stars are a few small specks and the night scene is very dark; it didn't
  read as exciting at ad size.
- **Egg hatch burst**: the hatch played before I could freeze it, so the egg ad shows the ready-to-hatch moment.

The chasing owner in `ad-thief.jpg` is a client-side copy of the test avatar in a green shirt (a hidden Studio
can't add a second real player); the steal itself is real (`Carry.grab`). The player is Merijn's own avatar.
