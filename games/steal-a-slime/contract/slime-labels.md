# §38 Slime labels: one info card above every slime

Every slime model (wild, on a pad, escaping, carried) shows one small card above the top of its mesh: species name in
the rarity colour, the rarity, its income per second, and the wild buy price or the pad growth.
The server decides every value and writes it as model attributes; each client draws the card locally. No remote, no
State field, no save-format change.

- **Model attributes (server, `WorldView.reconcile` via `src/server/SlimeLabelView`).** Names live in `Constants`.
  - `LabelName` (`Constants.LABEL_NAME_ATTRIBUTE`): `slime.name` (the species name, e.g. `"Lop"`).
  - `LabelTier` (`Constants.LABEL_TIER_ATTRIBUTE`): `slime.tier`, the `Config.RARITIES` index.
  - `LabelIncome` (`Constants.LABEL_INCOME_ATTRIBUTE`): cash per second of this slime. Owned slimes (pad, escaping,
    carried away by a thief): `PlayerData.slimeIncome(owner data, slime)` (size, growth, the owner's rebirth
    multiplier and income perks), the same number as `State` `SlimeView.income`. Wild slimes: `Economy.slimeIncome(slime, 0)`
    (no rebirths). Rewritten only when `SlimeLabel.incomeText` of the new value differs from the shown one, so growth
    does not replicate an attribute every tick.
  - `LabelHeight` (`Constants.LABEL_HEIGHT_ATTRIBUTE`): studs from the Body's centre to the card's bottom edge:
    `Growth.labelOffset(top of the model's bounding box - Body centre)`, measured after every scale change (growth,
    boss scale). The card never covers the face or the Grab prompt, which sit on the Body.
  - Existing attributes the card also reads: `Price` (wild buy price; > 0 shows `"Buy $X"`), `Growth` (whole percent,
    shown as `"Growth N%"` on pads), `Boss` (name prefixed `"BOSS "`).
- **Pure text (`src/shared/SlimeLabel`).** `SlimeLabel.view(attrs) -> View?` turns the attributes into
  `{ name, rarity, rarityColor, income, extra }`: `income = "+$1.25K/s"` (`NumberFormat.cash`), `extra` =
  `"Buy $500"` (priced wild) or `"Growth 46%"` (1..100) or nil. nil when `LabelName` is missing.
- **Client (`src/ui/SlimeInfoCard`, started from `init.client`).** One `BillboardGui` per tagged slime model
  (`Constants.SLIME_TAG`), parented to a local folder under PlayerGui with `Adornee` = Body, `SizeOffset` (0, 0.5) so its
  bottom edge sits `LabelHeight` above the Body. Size mixes studs and pixels so it shrinks with distance but stays
  readable; `MaxDistance` hides it far away. Re-rendered only on `AttributeChanged` of the attributes above; no frame
  loop, no tween. Removed with the tag (model destroyed or streamed out). `FollowPets` clones never carry it.
- **Replaces** the server `GrowthLabel` BillboardGui ("Growth N%" now lives on the card). The server still scales the
  model by growth and sets the `Growth` attribute (§5 Growth).
