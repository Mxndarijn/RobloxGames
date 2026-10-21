# 40. Mystery Eggs: wild eggs that hatch on your plot (`FEATURES.MysteryEggs`)

**Status:** `FEATURES.MysteryEggs` (off = the fountain drops no eggs; eggs already on plots still hatch). Server-authoritative. **No save version bump**: an egg is a slime with an optional `egg` field, added like `growth` / `keep`, and the lucky meter is an optional `eggLuck` field (missing = empty).

## 40.1 What it is

Now and then the fountain drops a **Mystery Egg** instead of a slime. It rides the lane like a wild slime and is grabbed, bought, carried, dropped and slapped loose the same way. Once it is on a pad it **incubates**: after the egg's hatch time (real time, also while the owner is offline) it is **ready**, and the owner holds **Hatch** to get the slime inside. Incubating and ready eggs **can be stolen** like slimes, and the thief keeps the progress. While the owner stands in their own HomeZone, their eggs incubate `WARM_SPEED` x faster.

The hatch is a show on the pad (40.6): the egg wobbles, cracks, bursts and the slime pops out, and every nearby player sees it.

## 40.2 Data

- `Genome.Slime.egg: { kind: string, hatchAt: number?, lucky: boolean? }?`. `kind` is a `Config.MYSTERY_EGG.KINDS` id (never rename one). `hatchAt` is the server time (`workspace:GetServerTimeNow()`, unix seconds) the egg is ready; nil until it first lands on a pad. `lucky` is true for a lucky egg (40.3); it is never sent to a client before the hatch.
- The rest of the record **is the slime inside**, rolled when the egg spawns (`EggKind.drops`), so a reroll by dropping, stealing or rejoining is impossible. It is never sent to a client before the hatch (40.5). The only change after the spawn is the lucky meter's guarantee at the hatch (40.4).
- `Genome.sanitize` keeps `egg` only with a known `kind` and a finite `hatchAt` (or none); `lucky` only when it is `true`.
- `PlayerData.Data.eggLuck: { [kindId]: number }`: per kind, how many hatches in a row missed the kind's top tier. Saved; `SaveData` keeps known kind ids with a whole number >= 0 and drops the rest.

## 40.3 Rules (`src/shared/EggKind.luau`, `src/shared/MysteryEgg.luau`, `src/server/MysteryEgg.luau`)

| Rule | Value / where |
| --- | --- |
| Egg chance per fountain drop | `MYSTERY_EGG.DROP_CHANCE`, x `RAIN_MULT` during Slime Rain; never while `MAX_WILD` (`RAIN_MAX_WILD` in rain) eggs are already loose |
| Egg kind | weighted `KINDS[i].weight` |
| Slime inside | `KINDS[i].drops` tier weights, then a species over Classic and every family (`FountainTiers.allFamilies`); no luck; rolled on `world.eggRng`, so the slime drop sequence is unchanged |
| Lucky egg | `LUCKY_CHANCE` of eggs: the slime inside is one tier higher than its roll (capped at Secret), `egg.lucky = true` |
| Hatchling size | `HATCH_SIZE_MIN` + up to `HATCH_SIZE_SPAN` (bigger than a wild slime's `MIN_SIZE` + 0.6), never below the tier's size floor |
| Top tier of a kind | its highest `drops` tier (`EggKind.topTier`) |
| Grab price | free with `FREE_DROP_CHANCE`, else `KINDS[i].price` (flat) |
| Wild lifetime | `Fountain.wildLifetime` of the kind's `tier` |
| Carry slowdown | the kind's `tier` (`Steal.newCarry`); never the hidden tier |
| Hatch time | `KINDS[i].hatchSeconds`, set on the first deposit (`hatchAt = now + hatchSeconds`); a steal keeps `hatchAt` |
| Warm-up | owner in HomeZone: every second `hatchAt -= (WARM_SPEED - 1)` |
| Income | 0 (`Genome.baseIncome`) |
| Sell | `KINDS[i].sell` x the rebirth multiplier (`Economy.sellPrice`) |
| Announced | spawn of a kind with `announce = true` (Golden, Cosmic); a hatch of tier >= `HATCH_ANNOUNCE_TIER` (Legendary), sent when the show reveals it |

An egg is never merged (Merge Vat, 3-slime vat, merge assist), never counts for the rebirth slime, the SlimeDex, badges, habitats, growth, the follow pet or a favourite, and the Lucky Charm never upgrades it. The SlimeDex records the species at the hatch.

## 40.4 Hatching and the lucky meter

- **Request `HatchEgg(slimeId: string)`**: the caller's own egg, on a pad, not being carried, `hatchAt <= now`. Clears `egg`, applies the lucky meter, records the SlimeDex, sets `State.egg.hatched` (no HUD banner) and starts the hatch show (40.6). Refusals: "not your egg", "egg is not ready", "egg is being stolen".
- **Lucky meter** (`MysteryEgg.hatchEgg`): with `m = eggLuck[kind]`, a hatch whose slime is below the kind's top tier while `m + 1 >= KINDS[i].pity` becomes the top tier (the slime is rolled again at that tier with the same id and pad; hatchling size). After the hatch, `eggLuck[kind]` is 0 when the slime is the top tier, else `m + 1`. The meter belongs to whoever hatches (a thief uses their own).
- **Toasts** wait for the reveal: the owner's "Your egg hatched: …" (with "Lucky egg!" or "Lucky meter full!" in front when one applied) and the server toast for `HATCH_ANNOUNCE_TIER`+ go out once `HATCH_REVEAL_SECONDS` have passed (`MysteryEgg.step`, once a second).
- **`HatchPrompt`** (ProximityPrompt on the egg's Body, `ShowOnlyToUserId` = owner, hold `HOLD_CONFIRM_SECONDS`), enabled while the egg is ready on its pad: the same rule. Its ObjectText is the egg name and the owner's meter for that kind ("Golden Mystery Egg · Lucky 3/12").
- When an egg turns ready while the owner is in the server, the owner gets one toast; it names the meter when the next hatch is guaranteed.

## 40.5 What clients see

- `State.slimes[i].slime` / `State.carrying.slime` for an egg is masked (`EggKind.mask`): `name` = egg name ("Golden Mystery Egg"), `tier` = the kind's `tier`, no `species`, `egg = { kind, hatchAt }` (never `lucky`). `income` 0, `sellPrice` = the egg sell price.
- Egg models (`server/EggModel`) have `Body` plus model attributes **`EggKind`** (kind id), **`EggHatchAt`** (server time, nil while not incubating), **`EggHatchSeconds`** (the kind's hatch time) and the usual `OwnerUserId` / `State` / `Price`. The label attributes carry the egg name and kind tier. In `Pad` state the model shows its nest.
- Mesh look: `MeshAssets` names `mystery_egg_<kind>` and `mystery_egg_nest`; until they have a `meshId`, the model is built from primitives.
- Client `EggFx` (`src/visuals/client`): cracks at 1/3 and 2/3 of the incubation, a glow in the kind's colour that pulses faster near the hatch, a bright glow and sparkles when ready; the idle jiggle and carry wriggle are VisualsClient's, as for any slime. `SlimeLifeRunner` skips egg models. The label's income row reads the server's `LabelStatus` ("Hatches in m:ss", "Ready to hatch!").

## 40.6 The hatch show

- For `HATCH_FX_SECONDS` after a hatch the new slime model carries **`HatchedAt`** (server time of the hatch), **`HatchedFrom`** (the egg kind id) and **`HatchLucky`** (true for a lucky egg or a meter guarantee). Set before the model is parented, cleared after.
- Client `EggHatchFx` (`src/visuals/client`, timeline in `Visuals.EggHatchTimeline`, pure) plays it for every client within `EggHatchFx.MAX_DISTANCE`, keyed on server time so every viewer sees the same moment; a late viewer joins mid-way, one after the end sees nothing:
  1. **Wobble** (0 to 1.5 s): a local copy of the egg (the ready egg cloned before the hatch, else `EggModel.build`) rocks three times, harder each time; its glow steps through the rarity colours from the kind's lowest drop up to the hatch's tier.
  2. **Hold** (1.5 to 2 s): a fast shiver and a bright glow; a lucky hatch flashes gold. The owner's camera eases in a little.
  3. **Burst** (2 s): the copy is replaced by shell shards, a flash, a ring and sparks in the rarity colour.
  4. **Pop** (2 to 2.6 s): the slime, kept tiny until now (client `Model:ScaleTo`), springs up with a squash-and-stretch. Epic and up add a light pillar.
  5. **Reveal** (from 2.6 s, `HATCH_REVEAL_SECONDS`): a rarity title ("LEGENDARY!", "LUCKY!") floats up and the slime's label returns. `SlimeInfoCard` hides the label of a model whose `HatchedAt` is less than `HATCH_REVEAL_SECONDS` old.
- Nothing in the show replicates or decides anything; the slime is already the server's.
