# 21. Merge vat: three slimes of one rarity brew into one

Owner: Phoenix (rules, actions, world), Jolt (menu), Archer (vat model). Design and screens: `docs/merge-vat-rework.html`.

Every plot has one merge vat with `Config.VAT_SIZE` spots. The player Moves three pad slimes of one rarity into it, starts a timed brew and collects one slime of a higher rarity.

## 21.1 Rules (`Shared.VatState`, pure)

- **The vat is a list of ids.** A slime in the vat keeps its pad. The vat only names which owned pad slimes are in it, in spot order (spot 1, 2, 3). The first slime sets the rarity the vat takes.
- **Add.** Move mode puts a pad slime in the next free spot. Refusals: `"not your slime"`, `"Eggs can't go in the vat"`, `"Already in the vat"`, `"The vat is brewing"`, `"The vat is full"`, `"The vat takes <Rarity> slimes"`; a slime that is busy (`World.busySet`: carried, escaping) gets `"slime is busy"`. There is no swapping and no replacing.
- **Remove.** The menu's X takes a slime out. It is simply back on its own pad, which was kept for it, so it always fits. Refused while brewing (`"Cancel the brew first"`) and for a slime not in the vat (`"not in the vat"`).
- **Waiting (no brew).** The inputs earn as usual and can be stolen, sold, moved to another pad or used by a rebirth. One that is no longer an owned pad slime leaves the vat (`VatState.prune`; every read prunes first, so the vat never names a lost slime).
- **Start.** Needs a full vat (else `"Add <n> more <Rarity>"`, or `"Add <n> slimes of one rarity"` while empty), `TripleMerge.canMerge` and the rank gate (21.9, else `"Rebirth <n> to unlock"`). Sets `startedAt = now` and `endsAt = now + brewSeconds`. A second start is refused `"already brewing"`.
- **Brew time.** `Config.MERGE_BREW_SECONDS[tier]` by the rarity going in, times `Perks.brewFactor` (Quick Brew, 21.8), rounded, at least 1 s. Recipes take the same time as a random merge of that rarity. Times are unix seconds, so a brew runs on while the player is offline. A started brew keeps its end time when Quick Brew levels up.
- **Brewing (`endsAt` set).** The inputs are locked (`VatState.isLocked`): they earn nothing (live and offline income skip them, their `SlimeView.income` is 0), and they can't be stolen, moved or sold. `Sell` and `MoveSlime` (either slime of a swap) refuse with `"That slime is brewing in the vat"`, and so does `StealService` (the steal prompt is also off).
- **Cancel.** Clears `endsAt` / `startedAt`. Nothing is lost: the three stay in the vat. Refused `"not brewing"`.
- **Collect.** Once `now >= endsAt` (else `"still brewing"`, or `"not brewing"`): `TripleMerge.apply` merges the three. The child takes the first input's pad, the other two pads free up and the vat is empty. The favourite moves to the child.
- **Every change checks all its rules first** and changes nothing when it refuses.

## 21.2 Result (`Shared.TripleMerge`, pure)

- Three **different**, owned, not-busy slimes of **one** rarity T go in; all three are consumed and one comes out.
- A recipe (three species that form a merge recipe, §35) gives its hybrid: one tier up, no jump.
- Anything else is a random merge: tier `T + 1` capped at Mythic, with `Config.TRIPLE_MERGE_JUMP_CHANCE` of `T + 2` while that stays at Legendary or below and the player's rank opens it (21.9); tier-7 inputs stay tier 7. Caps and the merge assist: §35.
- Size: mean of the three + `Config.TRIPLE_MERGE_SIZE_BONUS`, clamped. Pattern / eyes / mouth each from one of the three. The child is a real `SlimeRoster` species of its tier.
- **Deterministic.** All randomness is the server `world.rng`, drawn in a fixed order (jump, assist, species, three trait picks), rolled at Collect: one seed and inputs always give one child (`tests/TripleMerge.spec`).
- **Anti-dupe.** `TripleMerge.apply` validates everything first and only then removes the three and adds the child, so a refused collect changes nothing and the same slimes can never be merged twice.
- On Collect `MergeVat.collect` adds 1 to `stats.merges`, finishes the tutorial's Merge step and plays the `"Merge"` effect on the vat. Notify (`"good"`): `"You discovered <Hybrid>!"` / `"You brewed a <Hybrid>!"` on a recipe (sound `Rare`), else `"Merged into a <name>!"` with `" (new SlimeDex entry)"` for a new species (sound `Merge`).
- **Economy.** No cash cost; sell and buy values don't change. The price of a merge is the three slimes and the income their copies miss while they brew.

## 21.3 Requests (`server/MergeVat`)

| Action | Args | Rate limit | Effect |
|---|---|---|---|
| `"VatAdd"` | `slimeId: string` | 0.25 s | Move mode placed this pad slime in the vat (21.1 Add). |
| `"VatRemove"` | `slimeId: string` | 0.25 s | Takes it out; it stays on its pad. |
| `"VatStart"` | none | 0.5 s | Starts the brew of a full vat. Refused `"slime is busy"` while an input is busy. |
| `"VatCancel"` | none | 0.5 s | Stops the brew; the slimes stay in the vat. |
| `"VatCollect"` | none | 0.5 s | Merges a finished brew onto the first input's pad. |

Rate limits live in `Validate.ACTIONS`. The client never decides: it gates its buttons on `State.vat` and the server checks every rule again.

## 21.4 State and save

- **`State.vat: Types.VatView`** (always present):

```luau
{
	ids: { string },   -- slime ids in the vat, spot order (each is also in State.slimes, still on its pad)
	tier: number?,     -- the rarity it takes; nil while empty
	endsAt: number?,   -- unix seconds the brew is done; nil = not brewing
	startedAt: number?, -- unix seconds the brew started (the progress bar)
	seconds: number?,  -- how long a brew of `tier` takes now, Quick Brew applied; nil while empty
}
```

- **Save field `vat`** (no version bump): `{ ids = { slimeId }, endsAt = unix?, startedAt = unix? }`, left out while the vat is empty. `VatState.sanitize` on load keeps up to `VAT_SIZE` string ids and finite positive times, and drops anything else (junk = empty vat). `VatState.prune` then drops ids that are not owned pad slimes, and a brew without three inputs stops.

## 21.5 Menu (`Panels/Merge`)

- **Prompt.** The plot's `MergePrompt` on `MergeVat` (owner only, instant): ActionText `"Manage vat"`, ObjectText `"Merge vat"`. The server does nothing on it; the owner's client opens the menu.
- **Inputs.** Three slots in spot order. Each filled slot has an X (`VatRemove`); while brewing a padlock replaces it. An empty slot says how to fill it ("Move a <Rarity> here"). Slimes only arrive by Move; the menu has no picker.
- **Result.** `Shared.MergePreview.forSlimes(slimes, state)`: a recipe whose hybrid the player has discovered shows the hybrid by name; every other load, an undiscovered recipe included, shows `"Random slime"` with a rarity pill, the jump chance and the expected size, so the vat never gives a recipe away (§35).
- **Buttons.** A load the player's rank can't merge yet (21.9): the well `"Rebirth <n> to unlock"`, full or not. Not full: the reason line (`VatState.missingText`) and the button off. Full: `"Start merge · <time>"` (`VatStart`). Brewing: a goo progress bar with the time left and a pink hold-to-confirm `"Hold to cancel"` (`VatCancel`). Ready: the result card and a gold `"Collect to pad <n>"` (`VatCollect`). The player can close the menu at any time; the brew goes on.

## 21.6 Move mode

- `E Move` on a pad slime works as before; the vat is one more target. The client sends `VatAdd(slimeId)` when the player places the slime on the vat (click, tap or E).
- The vat lights green when it can take the slime and red when it can't, and the move bar says why (`"The vat is full"`, `"The vat takes <Rarity> slimes"`; the same texts `VatState.canAdd` gives).
- A slime the vat takes but the player's rank can't merge yet (21.9) lights the vat yellow; the bar adds `"<Rarity> merges open at Rebirth <n>."` and the place still goes through.

## 21.7 World look

- **Vat model.** `merge_vat` (kit mesh, copper goo cauldron, three funnel spouts) is the look of every plot's vat: the server (`MeshSwap.swapPlotVats`, `VatDecor.pose`) parents one MeshPart `VatMesh` under each plot's `MergeVat` disc. The disc and its `Goo` turn invisible once the mesh is placed; name, position, collision, `MergePrompt` and attributes stay. If the template can't load, the cylinder stays visible.
- **Spots.** Each slime in the vat shows as a small copy of itself on one of the vat's three spots, in spot order.
- **Pad copies.** The slime on its pad turns see-through while it is in the vat, so the pad stays visibly taken. Its pad sign says `"In vat"` while waiting and `"IN VAT"` while brewing.
- **World tag.** A tag over the vat shows its load while waiting (`"<n>/3 <Rarity>"`), the time left while brewing (`"Brewing m:ss"`) and when it is ready to collect. Under it, while not brewing, a second line (`VatView.capLine`): `"Up to <Rarity>"` (the owner's top rarity, 21.9), or for a load the owner can't merge yet `"Rebirth <n> to merge"` in Warn with the load pill in Warn too.

## 21.8 Quick Brew upgrade

- `Config.UPGRADES` id `QuickBrew` ("Quick Brew", Upgrade Shop, bought with `BuyUpgrade`): each level takes 15 % off every brew, up to 60 % at level 4 (`Perks.brewFactor = 1 - level x step`). Like every upgrade it is saved and kept on rebirth.
- Each level waits for its own rebirth count: `levelRequires = { 2, 4, 6, 8 }` (§8.8 Upgrades). Price follows the shop rule, `base x growth^n`.
- `State.vat.seconds` already includes it; a started brew keeps its `endsAt`.

## 21.9 Rank gate (`Shared.MergeGate`, pure)

- **Which rarities a player may merge** depends on their rebirths. Each `Config.REBIRTH_TIERS` rank that opens a rarity carries `merge = <top input tier>`; the best reached rank counts. Slime Rookie (0): Common. Goo Getter (1): Uncommon. Slime Wrangler (3): Rare. Blob Baron (5): Epic. Ooze Overlord (8): Legendary. Gel Emperor (12): Mythic. No rank opens Secret.
- **The gate is on the rarity going in.** `MergeGate.topTier(rebirths)`, `MergeGate.allows(tier, rebirths)`, `MergeGate.rebirthsFor(tier)` (the rebirth count that opens `tier`, nil if no rank does) and `MergeGate.lockText(tier)` (`"Rebirth <n> to unlock"`). Recipes follow the same gate as their inputs.
- **Loading is free.** `VatAdd` ignores the gate: a locked slime may wait in the vat and keeps earning on its pad. Only `VatStart` refuses it. A brew already running finishes and collects as normal.
- **Jump.** The +2 jump only rolls when the rarity it lands on is open as a result: `T + 2 <= topTier + 1` (`MergeGate.jumpAllowed`). `MergeRecipes.Ctx.rebirths` carries the rank into `resolve` (nil = no gate); `TripleMerge.ctxFor` fills it from the save, `TripleMerge.odds(tier, rebirths?)` and `MergePreview` from State. The draw order does not change.
- **Rank rewards.** `Perks.tierText` names the rarity a rank opens (`"opens Epic merges"`), so the rebirth menu's next-rank line and the `"New rank"` notice say it.

## 21.10 Brewed income and value-losing merges

- **Brewed slimes earn more.** `TripleMerge.merge` marks its child `brewed = 1` (random result) or `brewed = 2` (recipe hybrid). `Genome.baseIncome` multiplies by `BREWED_INCOME_MULT` (1.5) or `RECIPE_INCOME_MULT` (2) (`Genome.brewMultiplier`). The bonus stays with the slime (stolen, sold price, rebirth) and never stacks: merging brewed slimes gives one brewed child. Saved as the optional slime field `brewed` (missing = not brewed, no version bump). The pad label shows "Brewed <name>" for `brewed = 1`.
- **Only recipes merge the top.** `TripleMerge.canMerge` refuses three slimes of tier `MERGE_MAX_TIER` (Mythic) or higher unless they form a recipe of the next tier (Nightwing): "only a recipe merges these". A random Mythic or Secret merge would give back one slime of the same tier, losing income.
