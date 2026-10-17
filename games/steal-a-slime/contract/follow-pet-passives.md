# 14. v29 #14: follow-pet passives (2026-10-16, Jolt)

**Status:** contract first. `Config.FEATURES.PetPassives` (default on); `false` = the follow pet is cosmetic only. Server-authoritative; no new remote, **no save-format change** (derived at runtime from the saved `favoriteId` and the owned slime, so old saves just work).

- **Rule (`Config.PET_PASSIVES`, `Perks.petPassive`):** the favourite slime's tier picks the kind (`KIND_BY_TIER`: income, income, luck, luck, mutation, mutation, luck); value = `tier * perTier` + `MUTATION_STEP` (1%) per mutation, capped per kind (income 8%, luck 6%, mutation 12%). No favourite (or not owned) = no perk; changing or clearing the favourite changes it on the next snapshot.
- **Effects:** income is a factor of `Perks.bonusMultiplier` (so `incomePerSecond`, `slimeIncome`, offline income); luck is added to `Perks.luckChance` (rarity-up on deposit, `Carry`); mutation is added to `Config.MERGE_MUTATION_CHANCE` in `Merge.apply` (`Perks.petMutationBonus`).
- **State / UI:** `State.petPerk? = { kind, value, icon, text }`; the My Plot panel shows a chip (`🍀 +3% luck`) under the favourite's row (row grows from 56 to 80 px). Glyphs are existing emoji (supplementary plane, already allowed).
