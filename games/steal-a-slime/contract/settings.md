# §51 Settings menu

The player's own settings, in one card opened from the gear (⚙️) in the top-right slot. It replaces the old Sound card and its speaker button.

## Values

- **Source of truth:** `src/shared/PlayerSettings.luau`, on top of the shared `shared/luau/src/settings/SettingsSchema.luau` (toggles, sliders, choices; `clean`, `parse`, `apply`). Ids are save keys: never rename one.
- **Save:** `settings` (the field from save v6, §8.9c). The three audio ids (`muted`, `musicVolume`, `sfxVolume`) keep their old names, so old saves load unchanged. Every newer id that is missing or junk loads as its default. No save version bump.
- **Client:** each value lives on a LocalPlayer attribute (`PlayerSettings.TABS[*].entries[*].attribute`). Any client script reads it with `PlayerSettings.get(player, id)` / `PlayerSettings.on(player, id)`. `ui/SettingsController` loads `State.settings` once on join and sends changes back.
- **State:** `settings` (every id, `PlayerSettings.clean`), always.

| Tab | Id | Kind, default | What it does |
|---|---|---|---|
| Sound | `muted` | toggle, off | Every SoundGroup at 0; a 🔇 badge on the gear |
| | `musicVolume`, `sfxVolume` | slider 0..1, `Config.AUDIO` defaults | Music / SFX SoundGroup volume (the card moves in 5 % steps) |
| | `stealAlarm` | toggle, on | Off: no alarm sound (`SoundController.play("Alarm")`, the Notify fallback, StealAlertFx repeats); the red flash and arrow stay |
| | `buttonClicks` | toggle, on | Off: `Lib.ui.ButtonClicks` plays nothing |
| Game | `holdToSell` | toggle, on | Off: the pad Sell prompt is a tap (`SlimeKeys.setSellHold(0)`) |
| | `tutorialHints` | toggle, on | Off: no tutorial card, no Goals ring, no tutorial arrow. The server still tracks the step |
| | `dailyPopup` | toggle, on | Off: the daily popup does not open by itself; the reward waits in Goals ("Daily reward" row with Open, a `!` on the Goals tile) |
| Visuals | `reducedMotion` | toggle, off | Same as Roblox's Reduced Motion (`ReducedMotion` attribute): no habitat tweens / puffs, no camera shake, no hatch zoom |
| | `effects` | `low` / `full`, full | Low: fewer particles (`visuals/shared/EffectPrefs.LOW_SCALE`): client Emit counts, PvP and weather effects, habitat bursts, and server-made emitters dimmed locally (`visuals/client/EffectsDimmer`) |
| | `cameraShake` | toggle, on | Off: no PvP hit shake, no shake at a Secret's fountain show, no hatch zoom |
| | `othersEffects` | toggle, on | Off: other players' carry trails, their PvP hit effects and slap effects are hidden (traps and steal trails stay: they are gameplay) |
| Me | `showOnBoards` | toggle, on | Off: every global board shows `PlayerSettings.HIDDEN_NAME`, the default podium rig, `userId = 0`, also while offline (below) |
| | `numberStyle` | `short` / `full`, short | Full: the HUD cash shows every digit ($1,234,567; `NumberFormat.full`, short again from `FULL_MAX`) |

The Game tab also has **Replay tutorial** and the Me tab the **game version** (`game.PlaceVersion`, "Studio" in Studio) with the player id, and **Reset settings** (hold to confirm; only these values).

## Requests

- `Request("SetSettings", changes: { [id]: value })`, rate limit 0.5 s. `changes` must be a table of known ids with valid values (`PlayerSettings.parse`), at most one entry per setting; anything else is `"bad argument"` and nothing changes. Values are applied over the saved ones (`PlayerSettings.apply`). The client sends only the ids that changed, 0.6 s after the last change.
- `Request("ReplayTutorial")`, rate limit 2 s. Starts a finished tutorial again at step 1 (§49); refused with `"the tutorial is already running"` while it runs. During a replay (`data.tutorialReplay`, runtime only, never saved) every step waits for its own action, even one the save shows as done.

## Hidden on the leaderboards

Board keys are `u_<userId>`; a hidden player's values are written under `h_<userId>` instead (`Leaderboard.prefixFor`). On a session's first write to a board, and whenever the prefix changes, the save also removes the key under the other prefix (`Leaderboard.boardWrites`, `Persistence.rank`). Reading a board accepts both prefixes; for players on this server their current setting wins (`Leaderboard.overlay`), so a change shows before the next save. Own ranks (`State.boardRanks`) count both prefixes.
