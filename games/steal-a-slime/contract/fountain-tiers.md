# 19. v19: fountain tiers + slime families (`FEATURES.FountainTiers`, default `true`)

Owner: Phoenix (server, shared), Archer (visuals). Off = one Meadow fountain, Classic drops only, no attribute, no templates.

- **Tier.** `World.fountainTier` (1..4) is the best rank seen on the server: `FountainTiers.tierFor(max rebirths over sessions)`, raised by `Spawner.stepFountainTier` each frame, never lowered while the server lives. Steps at the `Config.REBIRTH_TIERS` entries that carry `family`: 3 rebirths (Slime Wrangler) = Garden Fountain, 6 (Goo Tycoon) = Frost & Sea, 10 (Slime Sovereign) = Starlight. Raising it toasts everyone once ("The fountain grew into the Garden Fountain!"). The tier only changes the fountain's look.
- **Families.** `SlimeRoster` entries with `family` set (`orchard`, `frost`, `starlight`), species per [slime-pool.md](slime-pool.md) (§30). `SlimeRoster.forTier(tier)` still returns Classic only; `forTier(tier, family)` returns a family's. Species stay the only saved trace (`Genome.sanitize` already keeps a known species id and drops an unknown one), so there is **no new saved field and no `SAVE_VERSION` bump**.
- **Drops.** Tier first, then a uniform pick over the species of that tier in Classic and every family, on every server whatever the ranks: [slime-odds.md](slime-odds.md) (§32). Boss slimes stay Classic.
- **No rank gate on slimes.** Catching, buying, stealing, merging and owning a family slime need no rebirths.
- **Economy untouched.** No income multiplier, no price change: a family slime's income, wild price and sell value are those of a Classic slime of the same tier and size.
- **Replication.** workspace attribute `FountainTier` (`Constants.FOUNTAIN_TIER_ATTRIBUTE`), set only with the flag on.
- **Visuals (client, `FountainTierFx`).** `Map.Volcano.Crater.CraterGlow` takes the tier's glow colour and brightness (`FountainTiers.LOOKS`). No meshes are added round or over the fountain. Studio only: SlimeUI attribute `PcwFountainTier` forces the tier (pc-watcher shots `19-fountain-tier-N`).
- **Rank cards.** `Perks.tierText` says nothing about families.
- **Needs frame review before the flag goes on:** the glow colours at night.
