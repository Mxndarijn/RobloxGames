# Backlog (Merijn's decisions, to do later)

## Re-add mutations with a better design (decided 2026-10-18)

Merijn didn't like how mutations ("extra species" like Gold, Glowing) were implemented, and wanted them out of the
game until there is a better design.

**Removal: done** in PR #367 (2026-10-19). Gone: the rolled mutations (Glow, Lava/"Syrup", Galaxy, Rainbow, Gold,
Crystal, Eclipse), the weather ones (Wet, Frozen), the combos (Solar, Nebula, Aurora, Royal, Sleet, Comet),
`FEATURES.MutationStacking`, the Dex mutation stamps, Mutation Spray, the Rain Magnet upgrade, the MutationSurge
modifier, and every mutation multiplier in rolls, merge, appraise, value, income and UI. Species stayed, including
the Secret-tier Midas, Eclipse and Boo. Old saves are cleaned by `SaveData.migrateV6` (save v7, CONTRACT.md §8.9d).

**Still to do: re-adding.** Design first, then build:
- what a mutation looks like on a fully coloured species mesh;
- how it is earned (spawn roll, merge, weather, items) and whether mutations stack;
- how it shows in the Dex and in the economy (`docs/SLIME-ECONOMY.md`, contract);
- keep it to one place that rolls a mutation and one that shows it, and add a save migration for the new fields.
