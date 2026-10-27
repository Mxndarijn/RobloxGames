# §30 Slime pool: one mesh per species

The roster is the new slime pool (`shared/modeling-kit/models/pool`, design `docs/SLIME-ECONOMY.md`). There are no live
saves yet, so the old roster ids are simply gone: no migration, no legacy map. An unknown saved species is dropped on load
as before (`Genome.sanitize`).

- **Species (`Shared.SlimeRoster`, permanent ids from now on).** 32 spawning species.
  Classic (family nil): `gummy mochi bubbles pebble` (1), `bumble mushie froggo` (2), `whiskers lop moo` (3),
  `blaze octo` (4), `king` (5), `cosmo` (6), `midas` (7).
  `orchard`: `sprout cheddar` (1), `prickles flan` (2).
  `frost`: `chomp pengoo` (3), `frostbite zap` (4), `ninja` (5).
  `starlight`: `imp drako` (4), `robo` (5), `seraph amethyst prism` (6), `eclipse boo` (7).
  Families keep their ids and rank gates (§19); a family may now have several species per tier, none at some tiers,
  and Secret species.
- **Kinds (`Entry.kind`).** `"spawn"` (the 32 above: the fountain and random merges; `SlimeRoster.forTier` returns only
  these), `"hybrid"` (merge recipes only): `soda rocky_road` (2), `bloom honey_toad truffle` (3),
  `sushi snow_bunny moo_shroom catfish` (4), `steam kraken thunderbee` (5), `cyber_ninja dragon_king` (6), `nightwing` (7);
  `"boss"` (the boss event only): `goozilla queen_jelly klawdius pumpking` (6), `mecha_goo goomancer` (7);
  `"event"` (a limited Secret, only while its event runs): `glitch doodle origami disco isle chrono kitsune` (7). `SlimeRoster.ofKind(kind)` lists one kind.
  Non-spawn species have no family. Every kind has a look and a species mesh.
- **Looks (`Shared.SlimeLooks`).** Every species has `kit = "slime_<id>"`, a fully coloured mesh (body, pattern,
  accessories and face in vertex colours). `colour` stays the species colour for UI and the procedural fallback.
- **Meshes (`Shared.MeshAssets`).** `entries["slime_<id>"] = { assetId, size, offset }`: `size` is the native size of a
  size-1 slime (Config.SLIME_BASE_DIAMETER wide body), `offset` the mesh bbox centre minus the slime's bottom centre
  (Roblox axes, slime front -Z). Species meshes are not world slots, so they are not in `MeshAssets.NAMES`.
  A species whose mesh is not uploaded yet has an entry with `size` and `offset` but no `assetId`: `SlimeMesh` doesn't
  fetch it, and the slime wears the shared slime mesh in its species colour until the id is filled in.
  The old shared kits `slime_base`, `slime_acc_*`, `slime_ears`, `slime_horns`, `slime_wobble` are removed.
- **Server `SlimeMesh`.** A species mesh is worn as the `Mesh` part: size `size x Body.Size.X / SLIME_BASE_DIAMETER`,
  placed at the body's bottom centre + `offset` (scaled) with `MeshAssets.IMPORT_YAW`, `Color` white, material from
  `SlimeLooks`. It keeps its `Bone` children (skinned rig: Root, Top, Side*, Eyes, Lids,
  accessory bones). The procedural face / pattern / tier-crown parts are hidden (`SlimeMesh.isReplacedPart`); Body,
  Aura and GlowShell stay. No slime has a rarity ring under it. The per-type accessory path (`SlimeMesh.plan`,
  `Accessory`) is gone.
- **`Config.REBIRTH_SLIMES`** uses the new ids: one list per rebirth, see contract/v13-additions.md §8.8a.

## Species income bonus

Every species has an income bonus within its rarity (`SlimeRoster.Entry.income`, set in `SlimeRoster` `INCOME`): about x0.9 to x1.0 for the Classic species, more for the families that open later (Garden, then Frost & Sea, then Starlight, up to x1.4), x1.2 for every merge hybrid and x1.4 for every event Secret. `Genome.baseIncome` multiplies by it, so the wild price and the sell price follow. Within a rarity a species is rolled with weight `1 / income ^ SPECIES_RARITY_POWER` (`Genome.speciesWeight`, `Genome.pickWeighted`), both from the fountain and in random merges, so the better-earning species are the rarer ones.

