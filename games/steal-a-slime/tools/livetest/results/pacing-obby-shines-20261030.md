# Pacing with the Goo Gauntlet obby and the weather shines

The economy check after the Goo Gauntlet obby (x1.5 income for 5 minutes, ready again 5 minutes later) and the Gold / Diamond / Rainbow shines (x1.5 / x2 / x3).

**Aim:** the obby makes cash come in a little faster. A player who never runs it keeps the normal pace and doesn't fall behind.

**Result:** no Config change is needed. Skipping the obby gives the same pace as before. Running it gets a grinder to rebirth 30 about 10% sooner.

## What the sim now models

- **Weather** cycles like WeatherService (`Weather.pick` / `Weather.duration`), so Diamond (Snow) and Rainbow (Starfall) shines roll. Before this the sim was always Clear and only Gold ever rolled. `--no-weather` turns it off.
- **Obby runs.** Each time the boost is ready, a bot runs the course with chance `obby`, spends about `obbySeconds` on it (no trips meanwhile), then the real `ObbyRules.grant` gives the boost. Profiles: casual 0.25 / 180 s, average 0.6 / 120 s, grinder 0.9 / 80 s. These are guesses. Turn it off with `--set grinder.obby=0` (per profile).
- A new report table, **Obby boost and shines**, shows runs, the share of online time spent boosted, the mean income factor from the obby, and the mean number of shining slimes owned.

## Runs

`lune run tools/livetest/pacing --seeds 1-20 --days 7` and `--seeds 1-4 --days 55 --mix average=5,grinder=5,casual=6`. Each was run three ways, all on the same REBIRTH_COSTS:

- **before**: the old sim (always Clear, no obby).
- **no obby**: weather on, nobody runs the obby (`--set casual.obby=0 --set average.obby=0 --set grinder.obby=0`).
- **with obby**: weather on, profiles as above.

Median played hours to each rebirth, grinder (rebirth 1-12 from the 7-day run, 20 seeds; the rest from the 55-day run, 4 seeds):

| Rebirth | target | before | no obby | with obby |
|---|---|---|---|---|
| 1 | 0.5 | 0.5 | 0.5 | 0.4 |
| 5 | 2.2 | 2.3 | 2.3 | 2.0 |
| 10 | 7 | 6.9 | 6.9 | 6.0 |
| 15 | 18 | 17.8 | 18.0 | 15.5 |
| 20 | 42 | 39.8 | 40.6 | 34.1 |
| 25 | 90 | 92.5 | 96.7 | 78.9 |
| 30 | 150-170 | 153.7 | 158.6 | 139.0 |

Average players (7-day run): rebirth 10 at 5.2 / 5.3 / 5.2 h, rebirth 12 at 7.0 / 7.3 / 6.8 h. They gain about 5%, because they run the obby less often and their pace is set by other things than cash.

Obby boost share of online time: casual 17%, average 33%, grinder 42% (income x1.08 / x1.16 / x1.21 on average). Shining slimes owned: about 0.6 (casual) to 1.5 (grinder) on average. Wild prices scale with income, so a bought shine costs what it earns. Shines only help through free drops, steals and the limited number of pads. On their own they don't move the pace.

## Notes

- A tried variant raised rebirth costs x1.12 from rebirth 5 to cancel the obby. It was dropped: it puts players who skip the obby about 10% behind, against the aim above.
- If the obby should pay more or less, tune `Config.OBBY.BONUS` / `BOOST_SECONDS` / `COOLDOWN_SECONDS` and rerun the "with obby" runs. The "no obby" pace does not depend on them.
