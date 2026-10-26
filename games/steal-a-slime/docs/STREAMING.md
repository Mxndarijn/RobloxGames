# StreamingEnabled in Steal a Slime

The place streams; the Workspace streaming settings live in `default.project.json` (StreamOutBehavior is left at
Roblox's default, which only streams out under memory pressure). This page is the audit behind that switch, what
the code does about it, and the Studio measurements of 2026-10-26.

## How streaming behaves here (checked in Studio)

- A Folder or a non-atomic Model (`Map`, `Plots`, every `Plot_i`) is always on the client with its attributes and
  non-part children. Its parts come and go by distance. A plot Model's pivot stays right when its parts are gone.
- A streamed-out part comes back as **the same Instance**: its `Parent` goes to nil and returns, `DescendantAdded`
  and tag added/removed fire again. Cached references recover.
- Children the client made (BillboardGuis, folders) survive the round trip. **Client-side property changes do not**:
  the part comes back with the server's values (colour, attributes).
- Streaming works in coarse cells. At radius 256 almost nothing on this map (plots on a 140-stud ring, border at
  ~277) ever streams out. Radius 128 is the first one that really streams.
- Joining at the hub spawn then moving to the plot loads the area round both.

## What the code does

| What | Where | Why |
|---|---|---|
| Slime and egg models `Atomic` | `server/WorldView` (create) | Clients never see a Body without its eyes, skin, prompts. Ghost, vat and pet copies inherit it. |
| Boss guards `Atomic` | `server/BossFxView` | BossTelegraph bobs a guard as one piece. |
| Ritual circle `Atomic` | `server/RitualView` | RitualFx rigs beams over every `Spot_i` at once. |
| `Map.Volcano` `Persistent` | `server/WorldView.setup` | The client hangs eruption, tier glow and Secret splash on the crater once at start. |
| Each player's pet slime `Persistent` while it is a pet | `server/WorldView.updatePlayer` | FollowPets copies the pet from its slime on the owner's pad, which can be far away. |
| Respawn waits for the plot to stream in (3 s max) | `server/PlayerLifecycle` | The character spawns at the hub and is moved to its plot. |
| Home beacon placed from `WorldLayout.plotCentre`, not the Base part | `visuals/client/HomePlotMarker` | The beacon and edge arrow are needed exactly when the plot is streamed out. |
| Tutorial arrow asks the server to stream the own plot in when its target is missing | `visuals/client/TutorialArrow` | Deposit / Lock / Merge / BuyPad targets are on the own plot. |
| Steal alert points home when the thief is not on the client | `ui/StealAlertFx` | A far thief's character is streamed out (its `Player.Character` still points at a stale model). |
| Snow repaints a part that streams back in | `visuals/client/SnowGround` | The part returns with the server's colour. |

`tests/Streaming.spec.luau` boots the real server and checks the place setting, the Persistent fountain and Atomic
wild slimes.

## Audit: client code that assumes far parts exist

Nothing crashes or waits forever with streaming on: every world lookup is nil-checked or has a timeout. The items
below would go silently wrong. Fixed = by this change.

| Place | Assumption | Status |
|---|---|---|
| `visuals/client/HomePlotMarker` | own plot's `Base` is on the client | fixed (layout position) |
| `visuals/client/TutorialArrow` | own HomeZone / LockButton / MergeVat / pads are on the client | fixed (stream request) |
| `visuals/client/init.client` setupVolcano, `FountainTierFx`, `PlotVisuals` erupt | `Map.Volcano.Crater` is there at start | fixed (Persistent fountain) |
| `visuals/client/FollowPets` | the pet's source slime is on the client | fixed (Persistent pet slime) |
| `visuals/client/init.client` blink, `DespawnTelegraphFx`, `EggFx`, `EggHatchFx`, `PvpFunFx` proxies | a slime arrives with all its parts | fixed (Atomic slimes) |
| `ui/SlimeLifeRunner`, `SlimeMotor`, `SlimeInfoCard` | the same Body for a slime's life | fixed (Atomic slimes; same Instance returns) |
| `visuals/client/BossTelegraph` | guards arrive whole | fixed (Atomic guards) |
| `visuals/client/RitualFx` | every `Spot_i` is there when the rig is built | fixed (Atomic circle) |
| `ui/StealAlertFx` | the thief's character is on the client | fixed (points home) |
| `visuals/client/SnowGround` | a tracked part keeps its local colour | fixed (repaint on stream-in) |
| `first/init.client` loading screen | preloads every Map / Plots mesh | fine: preloads what has streamed; `visuals/client/Preload` fetches the rest as it arrives |
| `ui/SlimePadSign` (via SlimeInfoCard) | the pad is there when the slime refreshes | open, cosmetic: a far slime shows a floating tag until its next attribute change |
| `ui/SlimeMove` | `padsOf(plot)` read once at move start | open, low: you stand on your own plot when moving |
| `shared/PlotMascot` | counts `Floor_f` children for the mascot height | open, cosmetic: a half-streamed far plot shows its crown low or missing |
| `shared/luau` GuideView route | pathfinding sees the whole map | acceptable: far routes are rougher |
| `ui/FriendsLockIcon`, `ui/WorldLeaderboard`, `ui/SlimeKeys`, `ui/PromptHide`, `visuals/client/HabitatFx`, `NextPadMarker`, `PlotVisuals` decor | | fine: rebind on DescendantAdded, poll, or same-Instance adornees |
| ViewportFrames (SlimeDex, Merge, Rebirth, Skins, item icons) | | fine: built from ReplicatedStorage, never from world parts |

## Measurements (Studio play solo, 2026-10-26)

All 8 plots full: the player's plot at 32 pads, its pads, floors and slimes copied onto plots 2-8 as inert stand-ins
(~1,160 instances per plot). Client counts are `workspace:GetDescendants()`; mesh MB is
`GraphicsMeshParts`.

| Setup | Spot | Client instances | Parts | MeshParts | Unique meshes | Mesh MB |
|---|---|---|---|---|---|---|
| Streaming off | anywhere | 14,694 | 7,227 | 1,311 | 160 | 57.3 |
| Radius 256 | home / far corner | 13,723 / 14,241 | 6,951 / 7,019 | 1,222 / 1,263 | 146 / 152 | 54.6 / 55.9 |
| Radius 128, default stream-out (this branch) | home after join | 12,710 | 6,559 | 1,176 | 136 | 53.0 |
| | far corner (Hall of Fame) | 13,498 | 6,794 | 1,239 | 153 | 57.4 |
| Radius 128, Opportunistic stream-out | home | 8,140 | 3,928 | 693 | 121 | 51.0 |
| | plaza | 11,031 | 5,502 | 983 | 126 | 51.9 |
| | far corner | 6,639 | 3,462 | 634 | 127 | 55.1 |
| Radius 128, Opportunistic, whole-plot (Atomic plots) | home | 11,260 | 5,686 | 990 | 121 | 51.2 |

Empty plots, right after join: 3,948 client instances with streaming off, 3,469 on this branch, 2,568 with
Opportunistic.

- Join time in Studio is the same with and without streaming (loading screen lifts at ~2.5 s): everything is local
  and the meshes are cached. The join gain on a real connection could not be measured here.
- Mesh memory hardly moves: loaded mesh assets stay cached after their parts stream out.
- Whole-plot (Atomic) plots stream in early and halve the saving, so plots stay non-atomic.

## Playtest (branch build, Opportunistic stream-out to stress it, radius 128)

Checked with no client or server script errors: join; home beacon and edge arrow at the far corner while the plot is
streamed out; fountain eruption fx; 20 pads unlocked (Studio hook) and seen by the client; pet follows at the far
corner with the rest of the plot gone; grab a wild slime at the plaza, carry it across the map, deposit on pad 7 with
its info card; boss arrives and streams in whole, streams out when you leave and back in when you return, present
55/55 s while next to it; SlimeDex opens and renders.

Not checked: a steal between two players (hidden Studio only plays solo), the boss guard attack (did not come up),
the drop tube (its prompt cannot be triggered from a script, with or without streaming). Once, a boss was missing
on the client 18 studs away after a long session of teleports; this did not happen again in a fresh run.
