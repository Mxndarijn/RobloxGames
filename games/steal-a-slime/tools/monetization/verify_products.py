"""Check that every Exclusive Shop product and pass in created_ids.json exists on Roblox with the right name, price,
sale state and an icon. Read only. The key is never printed."""
import json, os, sys, requests
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from apikey import key, UNIVERSE as U
from create_products import catalogue
from create_passes import PASSES

H = {"x-api-key": key()}
got, token = {}, None
while True:
    url = f"https://apis.roblox.com/developer-products/v2/universes/{U}/developer-products/creator?pageSize=100" + (f"&pageToken={token}" if token else "")
    d = requests.get(url, headers=H, timeout=30).json()
    for p in d.get("developerProducts", []):
        got[p["productId"]] = p
    token = d.get("nextPageToken")
    if not token:
        break
ids = json.load(open(os.path.join(HERE, "created_ids.json")))
bad, icons = 0, {}
for k, name, desc, robux in catalogue():
    p = got.get(ids.get(f"product:{k}"))
    if not p or p["name"] != name or p["priceInformation"]["defaultPriceInRobux"] != robux or not p["isForSale"]:
        bad += 1
        print("MISMATCH", k, p and (p["name"], p["priceInformation"], p["isForSale"]))
    elif not p.get("iconImageAssetId"):
        bad += 1
        print("NO ICON", k)
    else:
        icons[f"product:{k}"] = p["iconImageAssetId"]
for k, name, desc, price in PASSES:
    gid = ids.get(f"pass:{k}")
    r = requests.get(f"https://apis.roblox.com/game-passes/v1/universes/{U}/game-passes/{gid}/creator", headers=H, timeout=30)
    g = r.json() if r.ok else None
    price_now = g and (g.get("priceInformation") or {}).get("defaultPriceInRobux")
    if not g or g.get("name") != name or (price_now is not None and price_now != price):
        bad += 1
        print("MISMATCH pass", k, r.status_code, g and (g.get("name"), price_now))
    elif not g.get("iconAssetId"):
        bad += 1
        print("NO ICON pass", k)
    else:
        icons[f"pass:{k}"] = g["iconAssetId"]
dupes = len(icons) - len(set(icons.values()))
print(f"universe {U}: products on Roblox {len(got)}, checked {len(catalogue())} products + {len(PASSES)} passes,",
      f"mismatches {bad}, icons {len(icons)}, shared icon ids {dupes}")
sys.exit(1 if bad or dupes else 0)
