# 45. Lucky Charm show

**Status:** always on (no flag). Server-authoritative; no remote, **no save-format change**, nothing saved.

The Lucky Charm (`Perks.luckChance`: the Luck upgrade plus a luck follow pet) gives a wild slime a chance to come home one rarity higher. `Genome.promote` raises the tier and swaps the species for one of the new rarity. The player sees it happen on the pad.

- **Server.** `Carry.deposit` records the upgrade in `world.lucky[slimeId]` (`LuckyShow.record`: the slime as it was caught, the server time, the owner). For `LUCKY_SHOW.MORPH_SECONDS` the pad still shows the caught slime: `Scene` describes the old copy (old tier, species, name, colour, income), so WorldView builds the old model, then rebuilds it as the new species (a species change rebuilds a model). For `LUCKY_SHOW.FX_SECONDS` the model on the pad carries **`LuckyAt`** (server time of the deposit) and **`LuckyFromTier`** (the rarity it was caught at). At `MORPH_SECONDS` the owner gets a Notify with sound **`Lucky`** (toasts stay off, so only the sound plays). The record itself is the promoted slime from the deposit on (State, income, saves).
- **Client** `LuckyFx` (`src/visuals/client`, numbers in `Visuals.LuckyTimeline`, pure) for every viewer within `LuckyFx.MAX_DISTANCE`:
  1. **Glow** (0 to `MORPH_SECONDS`, server clock): the old model gets a pulsing gold highlight and clover sparkles.
  2. **Burst** (the new model, once `MORPH_SECONDS` have passed): a gold flash and a ring of clover sparkles, and the highlight fades from gold to the new rarity colour.
  3. **Title**: "🍀 LUCKY!" over "Legendary → Mythic" in the two rarity colours floats up above the pad and fades.
- Nothing in the show replicates or decides anything.
