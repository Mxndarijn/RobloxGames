# Exclusive Shop products on Roblox

Creates the Exclusive Shop's Developer Products and Game Passes for Steal a Slime (universe 10770917350) with the
Open Cloud APIs, once each, and writes their ids into `src/shared/ExclusiveIds.luau` (which `Config` reads).
The key comes from `ROBLOX_OPEN_CLOUD_API_KEY` or `~/.config/roblox-ci.env` and needs `developer-product` and
`game-pass` read + write for the universe. Subscriptions have no API: create them on the Creator Dashboard and add
`sub:<key>` to `created_ids.json`.

```sh
lune run tools/monetization/dump_products.luau > tools/monetization/products.json  # from games/steal-a-slime
python tools/monetization/create_products.py          # dry run: every product with its name, description and price
python tools/monetization/create_products.py --go     # create the missing ones (created_ids.json: resumes, never twice)
python tools/monetization/create_passes.py            # Game Passes, created OFF SALE (turn them on after a publish)
python tools/monetization/verify_products.py          # names, prices and on-sale match Roblox
python tools/monetization/write_ids.py                # -> src/shared/ExclusiveIds.luau
```

`created_ids.json` is the record of what exists on Roblox (key -> id). Developer products can't be deleted, only
taken off sale, so never delete a line from it.
