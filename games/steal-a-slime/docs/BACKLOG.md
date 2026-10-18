# Backlog (Merijn's decisions, to do later)

## Remove all mutations for now, add them back later (2026-10-18)

Merijn doesn't like how mutations ("extra species" like Gold, Glowing) are implemented today, and wants them out of the
game until there is a better design. Re-adding them is a later, separate piece of work.

What "mutations" covers today (check the code for the full list):
- the core mutations in `Config.MUTATIONS` (Glow, Lava/"Syrup", Galaxy, Gold, plus the drafts in `SlimeRoster.NEW_MUTATIONS`:
  Rainbow, Crystal, Eclipse) and the combo mutations (`Config.COMBOS`: Solar, Nebula, Aurora, Royal, Comet, ...);
- weather mutations (`Config.WEATHER_MUTATIONS`: Wet, Frozen, Sleet, ...) and `FEATURES.MutationStacking`;
- everything that rolls or shows them: spawn rolls (Genome), merge inheritance and fresh rolls (Merge / TripleMerge),
  Mutation Spray (Consumables), weather, the Dex mutation stamps (species Dex, PR #360), income multipliers (Economy),
  mutation materials and effects on the slime model (SlimeMesh / visuals), labels and toasts.

When removing:
- no live users yet, so no save migration is needed: drop the `mutation` / mutation list fields or ignore them on load;
- keep the code paths simple to re-add later (one place that rolls a mutation, one that shows it), or delete them
  outright and design the new version from scratch;
- update the economy design (`docs/SLIME-ECONOMY.md` §5.2, mutation stamps) and the contract.

Re-adding later: design first (what a mutation looks like on a fully coloured species mesh, how it is earned,
how it shows in the Dex), then build.
