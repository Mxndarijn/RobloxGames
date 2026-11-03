# Pacing with the per-section obby boost (x2 for a full clear)

The obby boost now grows with each section a run clears: +1/6 per section on a 6-section course, so a full clear gives x2 income for 5 minutes. Before, a finish gave x1.5. The 5-minute cooldown after the boost is unchanged.

**What the sim measures.** The pacing bots don't play the course. They spend about `obbySeconds` on a run and then always finish it (`ObbyRules.grant`, every share at once). Each run therefore earns the full x2, so these numbers are an upper bound. Real players who stop part-way earn a share per section cleared.

**Result:** a grinder reaches rebirths 10 to 17 about 5 to 8% sooner than with x1.5. Average and casual players move about 0 to 7%. Players who skip the obby are unaffected: the boost is the only thing that changed.

## Run

`lune run tools/livetest/pacing --seeds 1-20 --days 7`: default mix, weather on, the same seeds on both builds. "x1.5" is main's code, "x2" is this branch.

Played hours to each rebirth (median):

| Rebirth | casual x1.5 | casual x2 | average x1.5 | average x2 | grinder x1.5 | grinder x2 |
|---|---|---|---|---|---|---|
| 1 | 25m | 26m | 27m | 26m | 25m | 22m |
| 3 | 1.1h | 1.1h | 1.2h | 1.1h | 1.2h | 1.1h |
| 5 | - | - | 2.0h | 1.9h | 2.1h | 1.9h |
| 8 | - | - | 3.8h | 3.7h | 4.0h | 3.7h |
| 10 | - | - | 5.7h | 5.4h | 6.5h | 6.0h |
| 12 | - | - | 7.0h | 6.7h | 9.3h | 8.8h |
| 15 | - | - | - | - | 16.4h | 15.7h |
| 17 | - | - | - | - | 22.2h | 21.1h |

Grinders who reached rebirth 17 within the 7 days: 67% with x1.5, 83% with x2.

Obby boost (per player, online time):

| profile | boost on x1.5 | boost on x2 | mean income x from the obby, x1.5 | x2 |
|---|---|---|---|---|
| casual | 16.2% | 16.6% | 1.081 | 1.166 |
| average | 32.9% | 32.4% | 1.165 | 1.324 |
| grinder | 42.4% | 42.4% | 1.212 | 1.424 |

## Not run

- I didn't run the late game (`--seeds 1-4 --days 55 --mix average=5,grinder=5,casual=6`), so rebirths 20 to 30 aren't measured. Expect the same few-percent pull-in, since only the boost size changed.
- No partial runs are modelled. The bot profiles' `obby` / `obbySeconds` are still guesses from `pacing-obby-shines-20261030.md`.
