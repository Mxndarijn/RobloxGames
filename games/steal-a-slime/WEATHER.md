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
