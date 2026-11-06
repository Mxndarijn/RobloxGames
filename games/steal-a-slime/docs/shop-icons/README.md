# Roblox store icons

The picture Roblox shows for each Game Pass and Developer Product: in the purchase popup, the Store tab on the game
page (passes) and the Roblox Shop. Every pass and product on Roblox gets one 512 x 512 PNG.

| File | What |
|---|---|
| `src/<icon id>.png` | Transparent renders from the modeling kit's icon rig (`shared/modeling-kit/tools/icons`). New pictures for passes, trails and quick buys are in `recipes_store.py`; clouds, hats, locks, Bat skins, bases and bundles reuse their in-game icon recipes. |
| `build.py` | Maps every key to its picture, adds the gift badge to `Gift_*`, composes the three styles into `out/A`, `out/B`, `out/C` (gitignored), writes `manifest.json` and `review.html`. |
| `review.html` | What Merijn signs off (he picked **style B, Plum stage**, 2026-11-05): the style options on the passes, then every icon by group at full size and 48 px. Open it after `build.py` (it reads `out/`). |
| `upload.py` | Sets each icon on Roblox (Open Cloud). Dry run unless `--go`; needs Merijn's OK in chat first. Takes the ids from `tools/monetization/created_ids.json` (universe in `apikey.py`) and records what it did in `uploaded.json`; `uploaded.old-10770917350.json` is the record for the old experience. |

```sh
python games/steal-a-slime/docs/shop-icons/build.py
python games/steal-a-slime/docs/shop-icons/upload.py            # dry run, style B: lists what would change
python games/steal-a-slime/docs/shop-icons/upload.py --go       # only after Merijn's OK
```

Re-render the sources (Blender 4.5; about a minute):

```sh
blender -b --factory-startup --python shared/modeling-kit/tools/icons/render_icons.py -- \
    --out games/steal-a-slime/docs/shop-icons/src --only $(python games/steal-a-slime/docs/shop-icons/build.py --ids)
```

The 8 `Fanfare_*` / `Gift_Fanfare_*` products are retired from the game but still exist (on sale) on Roblox, so they
get icons too; their ids come from `tools/monetization/created_ids.json`. Not covered: the Slime Club subscription (its
picture is set on the Creator Dashboard).
