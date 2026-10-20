# 40. Mystery Eggs: wild eggs that hatch on your plot (`FEATURES.MysteryEggs`)

**Status:** `FEATURES.MysteryEggs` (off = the fountain drops no eggs; eggs already on plots still hatch). Server-authoritative. **No save version bump**: an egg is a slime with an optional `egg` field, added like `growth` / `keep`.

## 40.1 What it is

Now and then the fountain drops a **Mystery Egg** instead of a slime. It rides the lane like a wild slime and is grabbed, bought, carried, dropped and slapped loose the same way. Once it is on a pad it **incubates**: after the egg's hatch time (real time, also while the owner is offline) it is **ready**, and the owner holds **Hatch** to get the slime inside. Incubating and ready eggs **can be stolen** like slimes, and the thief keeps the progress. While the owner stands in their own HomeZone, their eggs incubate `WARM_SPEED` x faster.

## 40.2 Data

- `Genome.Slime.egg: { kind: string, hatchAt: number? }?`. `kind` is a `Config.MYSTERY_EGG.KINDS` id (never rename one). `hatchAt` is the server time (`workspace:GetServerTimeNow()`, unix seconds) the egg is ready; nil until it first lands on a pad.
- The rest of the record **is the slime inside**, rolled when the egg spawns (`EggKind.drops`), so a reroll by dropping, stealing or rejoining is impossible. It is never sent to a client before the hatch (40.5).
- `Genome.sanitize` keeps `egg` only with a known `kind` and a finite `hatchAt` (or none).

## 40.3 Rules (`src/shared/EggKind.luau`, `src/shared/MysteryEgg.luau`, `src/server/MysteryEgg.luau`)

| Rule | Value / where |
| --- | --- |
| Egg chance per fountain drop | `MYSTERY_EGG.DROP_CHANCE`, x `RAIN_MULT` during Slime Rain; never while `MAX_WILD` (`RAIN_MAX_WILD` in rain) eggs are already loose |
| Egg kind | weighted `KINDS[i].weight` |
| Slime inside | `KINDS[i].drops` tier weights; a Classic species (no rank gate can block the grab or hint at the contents); no pity, no luck; rolled on `world.eggRng`, so the slime drop sequence is unchanged |
| Grab price | free with `FREE_DROP_CHANCE`, else `KINDS[i].price` (flat) |
| Wild lifetime | `Fountain.wildLifetime` of the kind's `tier` |
| Carry slowdown | the kind's `tier` (`Steal.newCarry`); never the hidden tier |
| Hatch time | `KINDS[i].hatchSeconds`, set on the first deposit (`hatchAt = now + hatchSeconds`); a steal keeps `hatchAt` |
| Warm-up | owner in HomeZone: every second `hatchAt -= (WARM_SPEED - 1)` |
| Income | 0 (`Genome.baseIncome`) |
| Sell | `KINDS[i].sell` x the rebirth multiplier (`Economy.sellPrice`) |
| Announced | spawn of a kind with `announce = true` (Golden, Cosmic); a hatch of tier >= `HATCH_ANNOUNCE_TIER` |

An egg is never merged (Merge Vat, 3-slime vat, merge assist), never counts for the rebirth slime, the SlimeDex, badges, habitats, growth, the follow pet or a favourite, and the Lucky Charm never upgrades it. The SlimeDex records the species at the hatch.

## 40.4 Hatching

- **Request `HatchEgg(slimeId: string)`**: the caller's own egg, on a pad, not being carried, `hatchAt <= now`. Clears `egg`, records the SlimeDex, sets `State.egg.hatched` (the existing reveal banner) and toasts. A hatch of `HATCH_ANNOUNCE_TIER`+ toasts the server. Refusals: "not your egg", "egg is not ready", "egg is being stolen".
- **`HatchPrompt`** (ProximityPrompt on the egg's Body, `ShowOnlyToUserId` = owner, hold `HOLD_CONFIRM_SECONDS`), enabled while the egg is ready on its pad: the same rule.
- When an egg turns ready while the owner is in the server, the owner gets one toast.

## 40.5 What clients see

- `State.slimes[i].slime` / `State.carrying.slime` for an egg is masked (`EggKind.mask`): `name` = egg name ("Golden Mystery Egg"), `tier` = the kind's `tier`, no `species`, `egg = { kind, hatchAt }`. `income` 0, `sellPrice` = the egg sell price.
- Egg models (`server/EggModel`) have `Body` plus model attributes **`EggKind`** (kind id), **`EggHatchAt`** (server time, nil while not incubating), **`EggHatchSeconds`** (the kind's hatch time) and the usual `OwnerUserId` / `State` / `Price`. The label attributes carry the egg name and kind tier. In `Pad` state the model shows its nest.
- Mesh look: `MeshAssets` names `mystery_egg_<kind>` and `mystery_egg_nest`; until they have a `meshId`, the model is built from primitives.
- Client `EggFx` (`src/visuals/client`): cracks at 1/3 and 2/3 of the incubation, a glow in the kind's colour that pulses faster near the hatch, a bright glow and sparkles when ready; the idle jiggle and carry wriggle are VisualsClient's, as for any slime. `SlimeLifeRunner` skips egg models. The label's income row reads the server's `LabelStatus` ("Hatches in m:ss", "Ready to hatch!").
