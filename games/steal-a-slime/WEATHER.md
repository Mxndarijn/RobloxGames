# Weather (v29 #9, `Config.FEATURES.Weather`, off by default)

Server cycles **Clear -> Rain / Snow / Starfall** (never the same id twice in a row, weighted by
`Config.WEATHER[id].weight`, length between `minSeconds` and `maxSeconds`; first change
`WEATHER_FIRST_AT` s after server start). Not related to the older Slime Rain event (`RAIN_*`, `SlimeRain`).

- `server/WeatherService`: `new / step / publish / start`. One `task.wait` per change, nothing per frame.
  Writes the workspace attribute `Weather` (`Constants.WEATHER_ATTRIBUTE`). Started only when the flag is on.
- `shared/Weather`: `getCurrent()`, `Changed:Connect(fn(new, old))`, `data(id)`, plus the pure helpers
  (`pick`, `duration`, `qualityScale`, `emitterRate`, `visualId`).
- `visuals/client/WeatherFx` + `visuals/shared/WeatherLook`: one anchored emitter part that follows the camera
  and a `WeatherTint` ColorCorrection, tweened in/out over `WEATHER_FADE_SECONDS`.
  Emitter rate = base rate x quality scale (graphics level 1..10, x0.6 on touch), limited so every emitter
  stays under its share of `WEATHER_PARTICLE_CAP` (160 live particles in total). The part is destroyed after Clear.
- Flag off: no service, no attribute, no visuals. The only exception is the client-local
  `WeatherDebug` attribute (`Constants.WEATHER_DEBUG_ATTRIBUTE`) that the pc-watcher sets for the `18-weather-*`
  shots; it is never replicated and never set by game code.

## Whole-screen grade (v30 F1)

A weather change is one `WEATHER_FADE_SECONDS` (3.5 s) tween on a single NumberValue. Each frame `WeatherGrade.lerp`
(`visuals/shared/WeatherGrade`, pure, Lune-tested) blends one flat vector (ColorCorrection tint / brightness / contrast /
saturation, Atmosphere colour mix + density + haze, ambient mix, exposure) and the emitter rates with the same eased alpha, so
nothing changes piecemeal. `WeatherFx` writes the tint; `NightSky` listens to `WeatherGrade.onChanged` and layers the
Atmosphere / ambient part on top of the day-night look. A change mid-tween starts from what is on screen. Targets live in
`WeatherLook.LOOKS[id].tint / atmo`. Shots: `18-weather-<id>-<device>` (settled, 3.9 s) and `18-weather-<id>-mid-<device>` (1.2 s).

## Ground snow (SnowGround v2, `FEATURES.SnowGround`)

ON. "Snow on the surfaces, no sheet": v1 laid one translucent Snow Part over the whole ground and washed the plaza sand and
paths into a flat grey/white sheet (cut in #223). v2 has NO overlay. `visuals/client/SnowGround` tints surfaces that already
exist, client-side only: the `Ground` block (and other big flat grass parts) lerp toward snow white (248,250,255) at full
weight; the border Terrain gets `SetMaterialColor` for Grass / LeafyGrass (full) and Rock (35 %); paths, the plaza disc and
the pads get only a light frost (max 22 %) so they stay readable. Materials never change (no pop). Cost: 0 parts, 0 mesh
slots (`SnowCover.PART_COUNT / MESH_SLOTS`), and it is flush by construction: no second layer, so no z-fighting and nothing
clipping into props. Props / roofs get no snow. `WeatherFx` only calls `SnowGround.start` with the flag on.

`SnowCover` (pure, Lune-tested, also used by the render exporter): `level` 0..1 builds over `BUILD_SECONDS` (50) of Snow and
melts over `MELT_SECONDS` (35) after. `SnowCover.tints(level, snowing) -> { grass, terrainGrass, rock, path }` are the 0..1
weights; `SnowCover.lerpColor` mixes one into the ORIGINAL colour (weight 0 returns it exactly). Settling is one smoothstep
curve; melting is different: the path / plaza / pad frost is gone at half level (twice as fast) while the grass and hills keep
their snow to the end.

Flicker avoidance: the level is quantized to 1/128 (`SnowCover.quantize`) and a colour is only written when the quantized step or
the phase changes; every colour is computed from the instance's saved ORIGINAL colour (weak table; Terrain colours saved on
first use), never from its current one, so nothing drifts and level 0 restores the original exactly. If something else recolours
a tinted part (e.g. the server restyling a pad) the new colour becomes the original. Heartbeat disconnects once settled and
creates no instances. Parts that stream in under `Map` / `Plots` get the current tint; removed ones are dropped.

Shots: `18c-snow-ground-<settle-mid|settle-full|melt-mid>-<device>`: the client-local `SnowCoverDebug` attribute pins the level
(0.5 / 1 / 0.5); with the pin set, weather `Snow` = settling and `Clear` = melting (the melt shot sets `weather: "Clear"`).
Renders: `lune run tools/render/export --snow <level> --snow-phase settle|melt` applies the same `SnowCover` tints to the exported
part colours and terrain vertex colours.

Late joiners: the server (`WeatherService.publish`) stamps workspace attributes `WeatherStartedAt` (server time the current weather
began) and `SnowEndedAt` (server time Snow last ended, cleared while Snow shows), written before `Weather`. `SnowCover.levelAt`
turns them plus `workspace:GetServerTimeNow()` into the level (10 s into the 50 s build-up = 0.2; mid-melt = partly melted; Snow
lasts >= 120 s so a melt starts from 1) and the phase is "snowing or not" (`SnowCover.phaseAt`), so a joiner mid-melt sees the
paths cleared first. Missing stamps: full while snowing, bare while clear. `SnowCoverDebug` / `WeatherDebug`
start from 0 and ignore the stamps. `SnowGround.start` places the level once.

## Hook for #8

For Gojo (stacking mutations + combos). Nothing in the mutation code reads weather yet.

- `Weather.getCurrent() -> id` (`"Clear" | "Rain" | "Snow" | "Starfall"`), server and client. On the server it
  is current once `WeatherService.start` ran (flag on); with the flag off it stays `"Clear"`.
- `Weather.Changed:Connect(function(new, old) end)` returns `{ Disconnect }`.
- `Config.WEATHER[id] = { displayName, mutation = nil, chanceBonus = 0, weight, minSeconds, maxSeconds }`.
  - `mutation`: a `Config.MUTATIONS[].name` the weather favours. Left **nil** for #8 to fill in.
  - `chanceBonus`: added to the mutation roll chance while that weather is current (0 = no effect).
- To use it in the roll: `local w = Weather.data(Weather.getCurrent())`; if `w.mutation` then add
  `w.chanceBonus` to the chance for that mutation.

Proposed mapping (docs only, no ids added here; today's ids: Glow, Lava (shown Syrup), Galaxy, Rainbow, Gold, Crystal, Eclipse):

| Weather  | Proposed mutation | Note |
| -------- | ----------------- | ---- |
| Rain     | `Wet` (new id)    | no existing id fits; fallback `Glow` |
| Snow     | `Frozen` (new id) | fallback `Crystal` |
| Starfall | `Galaxy`          | exists; `Starry` / `Cosmic` if #8 wants a separate one |

New ids are appended to `Config.MUTATIONS` by #8 (the array is ordered by multiplier and `name` is the permanent save id).

## Tests and proof

`tests/Weather.spec.luau` (cycle, replication, quality scaling and cap, flag off, hook API). Watcher shots
`18-weather-Rain|Snow|Starfall` (`shots/*.json`, `weather` + `wait`, `luau/weather_set`).

## Weather mutations (#8, FEATURES.WeatherMutations, save v5)

`Config.WEATHER`: Rain -> `Wet` (+0.10), Snow -> `Frozen` (+0.10), Starfall -> `Galaxy` (+0.05), Clear none. `Genome.rollMutation`
reads `Weather.data(Weather.getCurrent())` through a cache refreshed from `Weather.Changed` (`Genome.bindWeather`): while a weather with a
mutation is current, roll values in `[chance, chance + chanceBonus)` land on that mutation. No other mutation's chance changes, and Clear is
identical to before. `Wet` (x1.75) and `Frozen` (x2.5) have weight 0, so they only come from weather (or a merge ladder step); combos
`Sleet` (Wet + Frozen) and `Comet` (Frozen + Galaxy). Save v4 -> v5 (`SaveData.migrateV4`) only normalises each slime's `mutations` list;
ids and keys are unchanged. Tests: `tests/WeatherMutations.spec.luau`. Shot: `21-weather-mutation-dex` (`shots/96-21-weather-mutation-dex.json`).

## Rain Magnet (v19, FEATURES.RainMagnet)

An upgrade (rank 6) that makes a wild slime you bring home during Rain / Snow / Starfall (or the Slime Rain event) pick up that weather's mutation with +5 % per level. It reads the same `Config.WEATHER[id].mutation` hook and `Weather.getCurrent()` as `Genome.rollMutation`; see CONTRACT §23 and `tests/RainMagnet.spec.luau`.
