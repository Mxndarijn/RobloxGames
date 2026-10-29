# World labels: BillboardGui and SurfaceGui (2026-10-29)

Read this before you add or change any text, tag, sign or icon that lives in the 3D world: a `BillboardGui` (faces the camera) or a `SurfaceGui` (painted on a part's face). Every label we have is listed in the [registry](#registry-every-label-in-the-world) at the end; a new label adds its row there in the same PR.

## 1. The three ways a label can be sized

A `BillboardGui.Size` is a `UDim2` where **scale = studs** and **offset = screen pixels**. That one choice decides how the label behaves with distance:

| Kind | How you set it | Up close | Far away | On a phone |
|---|---|---|---|---|
| **Pixel tag** | `UDim2.fromOffset(w, h)` | small next to the object | the same size on screen: it covers more and more of the world | **2.8× bigger** share of the screen than on a 1080p monitor |
| **Stud tag** | `UDim2.fromScale(w, h)` | big, can fill the screen | shrinks like any object, text becomes unreadable | same share as on a monitor, but fewer pixels: unreadable sooner |
| **Hybrid** (preferred) | `UDim2.new(wStuds, wPx, hStuds, hPx)` | studs dominate (grows like an object, capped by a close limit) | pixels are a floor: it never shrinks below readable | scale the pixel part by the viewport (below) |

A `SurfaceGui` is always "studs": it is painted on the part, so its text shrinks with distance exactly like the part.

Rules:
- Info about a thing in the world (a slime, a vat, an NPC): **hybrid**, like [SlimeInfoCard](../games/steal-a-slime/src/ui/SlimeInfoCard.luau) (`SIZE`, `size()`, `fit()`, `closeLimit`).
- Short one-shot pops (BONK!, +$50): pixel tag is fine, they live 1 to 2 s.
- Guidance you must find from far away (Your plot, tutorial arrow): pixel tag, `AlwaysOnTop`, and hide it once you are there.
- Fixed signage (plot names, shop signs, boards): `SurfaceGui` on a real part.

## 2. How big it is on screen

Roblox's default camera has a 70° vertical field of view. A stud at distance `d` covers:

```
px per stud = viewportHeight / (1.40 * d)
```

| Distance (studs) | 1080p monitor | 720p (reference) | Phone landscape (390 px tall) |
|---|---|---|---|
| 10 | 77 px | 51 px | 28 px |
| 20 | 39 | 26 | 14 |
| 40 | 19 | 13 | 7 |
| 60 | 13 | 8.6 | 4.6 |
| 100 | 7.7 | 5.1 | 2.8 |
| 200 | 3.9 | 2.6 | 1.4 |

Roblox UI offsets are logical pixels. A phone is about 390 logical pixels tall in landscape (844×390), a 1080p monitor about 1000 after the top bar. **Plan for the phone first**: most players are on phones.

### Readable and spottable

- **Readable**: the text box is at least **14 px** tall on screen (Fredoka glyphs are about 70% of the box). Below 10 px nobody reads it.
- **Spottable**: the label's colour or shape is at least **6 px**: you can see "something is there" (a rarity colour, a lamp) but not read it.

So a text line `h` studs tall (SurfaceGui or stud tag) **reads up to**:

| Screen | Read distance | Example: 0.5 stud text | 1.5 stud text |
|---|---|---|---|
| 1080p | 55 × h | 28 studs | 83 studs |
| 720p | 37 × h | 19 | 56 |
| Phone | 20 × h | 10 | 30 |

A pixel tag reads at any distance, but on a phone a 44 px tag already takes 11% of the screen height. Keep a pixel tag **≤ 60 px tall at the 720p reference** and scale its pixel size with the viewport:

```lua
pxScale = math.clamp(viewportHeight / 720, 0.6, 1)   -- SlimeInfoCard.fit()
```

Re-fit on `Camera:GetPropertyChangedSignal("ViewportSize")` (rotating a phone, resizing a window).

## 3. MaxDistance: always set it

`MaxDistance` is the camera distance (studs) beyond which the engine doesn't draw the label. The defaults are bad for us:

- `BillboardGui.MaxDistance` default is **infinite**: the tag draws across the whole map.
- `SurfaceGui.MaxDistance` default is **1000**: in our map that is "always".

**Every label sets `MaxDistance` explicitly**, from what the player needs:

| Label purpose | MaxDistance (desktop) | Phone |
|---|---|---|
| Interaction card (key hint, can't-grab reason) | 30 to 40 | same |
| Info tag on a thing (slime, vat, podium, NPC) | 50 to 60 | about 2/3 (40) |
| Your own plot's small text (cash pad, pad signs) | 60 to 80 | same (SurfaceGui shrinks by itself) |
| State other players act on (lock timer, lock sign) | 90 to 150 | 60 to 100 |
| Landmark signs (plot names, shops, boards, arch) | 200 to 300 | same |
| Short FX pops | the FX range (`FX_RANGE`) or less | same |
| Guidance markers (Your plot, tutorial arrow) | as far as needed, but hide when you arrive | same |

Rules of thumb:
- Never show text past where it is spottable: past the read distance a SurfaceGui is only colour, and that is fine for landmarks but wasted draw for small text.
- A shorter limit on phones (`smallViewportPx = 500`, `Ritual.labelDistance`) because many pixel tags pile up on a small screen.
- `MaxDistance` hides the label suddenly. For a guidance marker that needs to fade, fade it in code (see [HomePlotMarker](../games/steal-a-slime/src/visuals/client/HomePlotMarker.luau)).
- If code already culls the label by distance (a loop that checks `Magnitude`), still set `MaxDistance` to the same number, so the engine and the code agree.

## 4. Close up: don't fill the screen

A stud or hybrid tag grows without bound as the camera comes closer. Cap it: compute `px per stud` at a `closeLimit` (SlimeInfoCard uses 12 studs) and stop growing nearer than that. A SurfaceGui doesn't need this (it is a part).

## 5. Look and placement

- `LightInfluence = 0` on every label: it stays readable at night and in shade.
- `AlwaysOnTop = false` by default, so walls hide it. Use `true` only for labels about the viewer (Your plot, a thief on your base, a hit you landed) or with a sight check (LockTimerTag casts a ray, so glass doesn't hide it but walls do). An always-on-top label without a limit shows through the whole map.
- Anchor with `SizeOffset`: `(0, 0.5)` puts the bottom edge on the anchor point (a tag above a head), `(0, -0.5)` hangs it below. Put the anchor on the object's top plus a small lift (1 to 2 studs) so the tag never hides the object.
- `StudsOffsetWorldSpace` for "above this object", `StudsOffset` only for camera-relative pops.
- Text: Fredoka/Nunito bold, an Ink `UIStroke` (2 to 3 px) round white text, `TextScaled` with a `UITextSizeConstraint` (max) so a long name shrinks instead of overflowing.
- SurfaceGui `PixelsPerStud` 40 to 80. Keep the canvas (part size × PixelsPerStud) under 1024 px per side; more only costs memory.
- One label per thing. If two labels can stand over the same spot (info tag and key card), let one hide the other.
- Many tags in one view (a full plot of slimes): test overlap and hide the farther one (SlimeInfoCard `overlapSlack`).

## 6. Cost

Each drawn label is a small render target. Dozens are fine; hundreds are not. `MaxDistance` is the cheap fix, because the engine skips culled labels. Per-slime or per-pad labels (40+ in a server) must have a limit of 80 studs or less. Build pixel tags on the client when only one player needs them (key card, next pad), not on the server for everyone.

## 7. Checklist for a new label

1. Pick the kind (section 1) and write the size as named constants in the module, with a comment per number.
2. Work out the read distance on a phone (section 2). Is the text big enough for where players stand?
3. Set `MaxDistance` (section 3), and a phone value if it is a pixel or hybrid tag.
4. `LightInfluence = 0`; decide `AlwaysOnTop` on purpose.
5. Pixel or hybrid tag: scale the pixels with the viewport (`pxScale`), cap close-up growth.
6. Check it in Studio at 844×390 and at 1920×1080, near and at `MaxDistance`. `screen_capture` leaves BillboardGuis out during Play, so read on-screen size with `execute_luau` (`gui.AbsoluteSize`, or `Camera:WorldToViewportPoint` on its corners) and say so in the PR.
7. Add the label to the registry below.

## Registry: every label in the world

Game: steal-a-slime unless noted. "px" = pixel tag, "studs", "hybrid", "SG" = SurfaceGui. MaxDistance in studs; "default" means not set (BillboardGui: infinite, SurfaceGui: 1000).

| Label | Code | Kind / size | MaxDistance | AlwaysOnTop |
|---|---|---|---|---|
| Slime info tag (rarity, name, income, price) | `ui/SlimeInfoCard` | hybrid 3.4 st + 160 px, pxScale 0.6..1, close 12 | 60 / phone 40 | yes |
| Grab key card | `ui/SlimeKeyCard` | px | 40 | yes |
| Can't-grab card | `ui/GrabBlockCard` | px 24+22 rows | 40 | yes |
| Pad sign plank | `ui/SlimePadSign` | SG 4.6×1.5, 80 ppS | 80 | no |
| Lock timer on other bases | `ui/LockTimerTag` | px 150×44 | 90 | yes + sight ray |
| Friends-lock sticker | `ui/FriendsLockIcon` | SG 3.2 st | 120 | no |
| Friends-lock badge | `ui/FriendsLockIcon` | studs 2.2×2.2 | 70 | no |
| Slime emote bubble | `ui/SlimeEmotes` | px 34×34 | 70 | no |
| BONK/CHOMP popup | `ui/PvpEffects` | px 140×48 | default | no |
| Fun FX text | `ui/PvpFunFx` | px 220×60 × scale | 220 | yes |
| Steal ping over thief | `ui/StealAlertFx` | px 110×56 | default | yes |
| Slap pop | `ui/StealAlertFx` | px 120×50 | default | yes |
| Vat tag | `server/VatView` | px 220×104 | 60 | no |
| Ritual orb label | `server/RitualView` | px 300×96 | 60 / phone 40 | no |
| Ritual rules sign | `server/RitualView` | SG 6×1.8, 50 ppS | default | no |
| Podium name board | `server/PodiumRigs` | px 120×61 | 50 | no |
| Plot name board | `server/PlotSigns` | SG 8×2.6, 50 ppS | default | no |
| Lock sign (LOCKED / timer) | `visuals/shared/PlotDecor` | SG 8×3.2, 40 ppS | default | no |
| Cash pad coin | `server/CashPadView` | SG, 60 ppS | default | no |
| Shop stand signs | `visuals/shared/Props.standSign` | SG, 80 ppS | default | no |
| Hall arch banner | `visuals/shared/Props.hallArch` | SG, 40 ppS | default | no |
| Leaderboard boards | `visuals/shared/Props.leaderboardBoard`, `ui/WorldLeaderboard` | SG, 40 ppS | default | no |
| Tutorial NPC name | `visuals/shared/Props.tutorialNpc` | px 170×44 | 80 | no |
| Professor Goo name | `visuals/shared/Props.professorGoo` | px 220×44 | 80 | no |
| Your plot marker | `visuals/client/HomePlotMarker` | px 170×98 | 2000, fades in code | yes |
| Next pad tag | `visuals/client/NextPadMarker` | px 176×42 | 40 | no |
| Boss hit pop | `visuals/client/BossTelegraph` | px 120×50 | default (code culls at 220) | yes |
| Egg hatch title | `visuals/client/EggHatchFx` | studs 6×1.2 | 45 | no |
| Lucky title | `visuals/client/LuckyFx` | studs 6×2.16 | 45 | no |
| Tutorial guide label (shared) | `shared/luau/src/guide/GuideView` | px 220×56 | 400 | no |
