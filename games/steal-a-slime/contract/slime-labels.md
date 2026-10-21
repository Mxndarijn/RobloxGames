# §38 Slime labels: a tag above every loose slime, a sign on every pad

Every slime model has one label. A wild, carried or escaping slime shows a floating tag above the top of its mesh:
species name, rarity, income per second and, while it is for sale, its price. A slime resting on a pad shows no tag;
its label is a wooden plank on the front of the pad crate, dipped in goo of its rarity colour: the rarity in the
goo, the name and income painted on the wood, and a goo tube for its growth.
The server decides every value and writes it as model attributes; each client draws the labels locally. No remote, no
State field, no save-format change.

- **Model attributes (server, `WorldView.reconcile` via `src/server/SlimeLabelView`).** Names live in `Constants`.
  - `LabelName` (`Constants.LABEL_NAME_ATTRIBUTE`): `slime.name` (the species name, e.g. `"Lop"`).
  - `LabelTier` (`Constants.LABEL_TIER_ATTRIBUTE`): `slime.tier`, the `Config.RARITIES` index.
  - `LabelIncome` (`Constants.LABEL_INCOME_ATTRIBUTE`): cash per second of this slime. Owned slimes (pad, escaping,
    carried away by a thief): `PlayerData.slimeIncome(owner data, slime)` (size, growth, the owner's rebirth
    multiplier and income perks), the same number as `State` `SlimeView.income`. Wild slimes: `Economy.slimeIncome(slime, 0)`
    (no rebirths). Rewritten only when `SlimeLabel.incomeText` of the new value differs from the shown one, so growth
    does not replicate an attribute every tick.
  - `LabelPad` (`Constants.LABEL_PAD_ATTRIBUTE`): the pad index while the slime rests on it (Scene state `"Pad"`);
    nil while it is wild, carried or escaping.
  - `LabelHeight` (`Constants.LABEL_HEIGHT_ATTRIBUTE`): studs from the Body's centre to the tag's bottom edge:
    `Growth.labelOffset(top of the model's bounding box - Body centre)`, measured after every scale change (growth,
    boss scale). The tag never covers the face or the Grab prompt, which sit on the Body.
  - Existing attributes the labels also read: `Price` (wild buy price; > 0 shows the price row), `Growth` (whole
    percent, the sign's bar), `Boss` (name prefixed `"BOSS "`).
- **Pure values (`src/shared/SlimeLabel`).** `SlimeLabel.view(attrs) -> View?` turns the attributes into
  `{ name, rarity, tier, rarityColor, income, price, growth, pad }`: `income = "+$1.25K/s"` (`NumberFormat.rate`),
  `price = "$500"` (priced wild) or nil, `growth` = whole percent 0..100, `pad` = index or nil. nil when `LabelName`
  is missing.
- **Tag (`src/ui/SlimeInfoCard`, started from `init.client`).** One `BillboardGui` per tagged slime model
  (`Constants.SLIME_TAG`), parented to its Body (`Archivable` false) with `Adornee` = Body, `SizeOffset` (0, 0.5) so its
  bottom edge sits `LabelHeight` above the Body. Outlined text, no panel: the name in white edged in the rarity colour,
  the rarity word filled with a gradient of its colour (a rainbow for Secret), the income in green and the price in
  gold. Size mixes studs and pixels so it shrinks with distance but stays readable; `MaxDistance` 60 hides it far
  away. Every tag sits at the same height above its slime, so neighbours on the lane can overlap. Disabled while
  `LabelPad` is set and the pad is found.
- **Pad sign (`src/ui/SlimePadSign`, driven by `SlimeInfoCard`).** A thin non-colliding, non-queried WoodPlanks part with
  a `SurfaceGui` on the pad crate's entrance side (pad-local -Z), in a local `SlimePadSigns` folder. Goo of the rarity
  colour (a rainbow for Secret) runs along its top edge with the rarity written in it and drips down both ends; the
  name (cream) and income (gold) are painted on the wood; the growth fills a goo tube, its percent beside it.
  `MaxDistance` 45: the plank is too small to read beyond that. The pad is the plot's part with `PadIndex` =
  `LabelPad`. Moves when the slime changes pad; looked up again when the model moves (it may land in its plot after
  `LabelPad` arrives); removed when it leaves the pad or loses its tag.
- Both are re-rendered only on `AttributeChanged` of the attributes above; no frame loop, no tween. Removed with the
  tag (model destroyed or streamed out). `FollowPets` clones never carry them.
- **Replaces** the server `GrowthLabel` BillboardGui (growth now lives on the pad sign). The server still scales the
  model by growth and sets the `Growth` attribute (§5 Growth).
