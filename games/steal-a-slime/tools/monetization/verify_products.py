import json, os, sys, requests
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from apikey import key
from create_products import catalogue
U = "10770917350"
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
ids = json.load(open("created_ids.json"))
bad = 0
for k, name, desc, robux in catalogue():
    p = got.get(ids.get(f"product:{k}"))
    if not p or p["name"] != name or p["priceInformation"]["defaultPriceInRobux"] != robux or not p["isForSale"]:
        bad += 1
        print("MISMATCH", k, p and (p["name"], p["priceInformation"], p["isForSale"]))
print("on Roblox:", len(got), "checked:", len(catalogue()), "mismatches:", bad)
