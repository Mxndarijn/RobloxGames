# Ad images (picks)

Eight 1920×1080 ad images for the Roblox Ads Manager test, plus 1:1 square crops of three. Every one carries the
main "STEAL A SLIME!" caption, as on the game's thumbnail (Merijn: "It should all be like Steal a Slime with
different backgrounds"); what changes is the scene and the hero slime. Open [review.html](review.html) to pick.
**Not uploaded** (not to Roblox, not to Ads Manager).

| File | Scene (all real game moments, memory store) |
|---|---|
| `ad-thief.jpg` (+ square) | A thief running off with a stolen Rainbow Celestial, the owner chasing |
| `ad-divine.jpg` (+ square) | The Divine "Goo Oracle" on its pad, the player reaching for it |
| `ad-night.jpg` (+ square) | The Rainbow Divine "Kirin" glowing in a jar base at night, Starfall weather (brightness +25 %) |
| `ad-rainbow.jpg` | The same Kirin by day (+$9.73M/s) |
| `ad-boss.jpg` | The slime boss on the lane, the player jumping at it |
| `ad-obby.jpg` | The Goo Gauntlet sky course over the goo pit |
| `ad-crowd.jpg` | A busy lane of cute wild slimes (a frame of the store video's catch shot) |
| `ad-egg.jpg` | A Mystery Egg ready to hatch on a pad |

`make_ads.py <stills-dir> <out-dir>` draws them from the raw stills with the store video's caption, drip and
sparkle code (`../store-video/render.py`, Lilita One). The stills came from the store-video capture build in a
hidden, muted Studio (`../store-video/README.md`), graphics quality 21, game time frozen, HUD and labels hidden;
`../store-video/capture/drv/adshot.py` poses the player (R15 animation at a fixed time) and the camera per shot.

Not made (honest-ads rule, from the earlier per-feature caption plan):
- **REBIRTH = x2**: not true. Each rebirth tier adds a few percent income (`Config.REBIRTH_TIERS`, +5–150 %), not x2.
- **SLIME RAIN**: in the game a Slime Rain shows as small sparkles while slimes still come down the fountain slide one
  by one; there is no "slimes falling from the sky" moment to capture.
- **Starfall at night**: the falling stars are a few small specks and the night scene is very dark; it didn't
  read as exciting at ad size.
- **Egg hatch burst**: the hatch played before I could freeze it, so the egg ad shows the ready-to-hatch moment.

Not shot this round: snow weather, a merge-vat hybrid close-up. The day and night Kirin ads share one hero slime.

The chasing owner in `ad-thief.jpg` is a client-side copy of the test avatar in a green shirt (a hidden Studio
can't add a second real player); the steal itself is real (`Carry.grab`). The player is Merijn's own avatar.

## NEW badge (`new-badge/`)

The same eight ads with a red "NEW!" tag in the top left, to test next to the plain ones in Ads Manager. Three
styles were shown (A red tag, B yellow burst, C pink "NEW!" in the caption); Merijn picked **A** ("A red tag").
`make_new_badge.py new-badge` draws them on top of the finished ads. Take the badge off (or switch to an UPDATE tag)
about 4–6 weeks after launch. **Not uploaded.**
