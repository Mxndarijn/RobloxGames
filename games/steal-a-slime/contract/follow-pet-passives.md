# 14. v29 #14: follow-pet passives (2026-10-16, Jolt)

**Status:** contract first. Always on (the `PetPassives` flag is retired). Server-authoritative; no new remote, **no save-format change** (derived at runtime from the saved `favoriteId` and the owned slime, so old saves just work).

- **Rule (`Config.PET_PASSIVES`, `Perks.petPassive`):** the favourite slime's tier picks the kind (`KIND_BY_TIER`: income, income, luck, luck, income, luck, luck); value = `tier * perTier`, capped per kind (income 8%, luck 6%). No favourite (or not owned) = no perk; changing or clearing the favourite changes it on the next snapshot.
- **Effects:** income is a factor of `Perks.bonusMultiplier` (so `incomePerSecond`, `slimeIncome`, offline income); luck is added to `Perks.luckChance` (rarity-up on deposit, `Carry`).
- **State / UI:** `State.petPerk? = { kind, value, icon, text }`; the favourite's Favorite prompt at its pad (`src/ui/SlimeKeys`) shows it (`🍀 +3% luck`). Glyphs are existing emoji (supplementary plane, already allowed).
