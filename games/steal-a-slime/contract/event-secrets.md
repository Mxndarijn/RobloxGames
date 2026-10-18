# §34 Event Secrets: one featured Secret per week

The 7 `"event"` species of `SlimeRoster` (§30: `glitch doodle origami disco isle chrono kitsune`, all tier 7) rotate:
one is featured each week and joins the fountain's Secret pool while it is featured. Server-authoritative, no remote,
no save-format change, nothing saved. Design note: `shared/modeling-kit/models/pool/POOL.md` ("Event Secrets").

- **Rotation (`src/shared/EventSecrets`, pure).** A function of unix time (UTC), so every server agrees; tests pass a fake
  `now`. Weeks are the weekly-event weeks (§18, `WeeklyEvents.weekIndex`: Monday 00:00 to the next Monday 00:00 UTC,
  half-open). The featured Secret of week `w` is `ROTATION[w % 7 + 1]`, where `ROTATION` is `SlimeRoster.ofKind("event")`
  in roster order. Consecutive weeks differ and every 7 weeks show all 7.
  - `EventSecrets.featured(now) -> Featured` with `Featured = { id, name, week, startsAt, endsAt }`.
  - `EventSecrets.extraSpecies(now) -> { SlimeRoster.Entry }`: the featured entry as a one-item list, for the spawn pool.
  - `EventSecrets.view(now) -> FeaturedSecretView` (`{ id, name, endsAt }`) for State.
  - `EventSecrets.featuredWeek(id, now) -> number?`: unix start of the week `id` is featured (this week when it is
    featured now, else its next week); nil for an id outside the rotation. The Dex reads it.
- **Spawn pool.** A wild fountain drop (`Spawner.spawnOne`) passes `EventSecrets.extraSpecies(unix)` as the optional
  `extraSpecies` argument of `Fountain.roll` (last argument), which hands it to `Genome.generate` (`GenerateOptions.extraSpecies`)
  and `Genome.speciesPool(tier, families, extra)` / `rollSpecies` (§32). The pool appends only the extra entries whose tier
  equals the rolled tier, then the pick is uniform: on a tier-7 roll the featured Secret is one equal slot next to `midas`,
  plus `eclipse` / `boo` while Starlight is open. Lower tiers are unchanged, and no extra rng draw is made, so seeded
  drops of other tiers stay the same. The tier odds are unchanged (the featured Secret shares the Secret weight).
  The clock is `Spawner.unixTime` (nil in `tests/ServerFixtures` = no featured Secret). Admin events (§12) do not change it.
- **Never otherwise.** An event Secret that is not featured never spawns: `SlimeRoster.forTier` excludes `"event"`, random
  merges (`TripleMerge`) and the Boss Slime call the roll without `extraSpecies`.
- **Owned forever.** An event Secret already on a plot stays a normal tier-7 slime after its week: it keeps its species,
  earns, can be stolen and merged like any Secret (`Genome.sanitize` keeps every roster id; a tier-7 merge stays tier 7).
- **State.** `featuredSecret: FeaturedSecretView?` (`Types.FeaturedSecretView = { id: string, name: string, endsAt: number }`,
  `endsAt` in server time, the same clock as `State.serverTime`).
- **Client.** The HUD banner stack (top centre, hidden with a menu open) shows `EventSecretBanner.banner(view, now)`:
  `"✨ Featured Secret this week: Kitsune (ends in 3d 4h)"`, `"5h 12m"` below a day, `"m:ss"` in the last hour; nil when
  absent, malformed or over.
