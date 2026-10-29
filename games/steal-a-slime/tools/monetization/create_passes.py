"""Create the Exclusive Shop Game Passes for Steal a Slime (universe 10770917350), OFF SALE, once each.

Ids go to created_ids.json next to this script (key -> id); a key already there is skipped. The key is never printed.
"""
import json, os, sys, time, requests
sys.path.insert(0, os.path.dirname(__file__))
from apikey import key

U = "10770917350"
OUT = os.path.join(os.path.dirname(__file__), "created_ids.json")
PASSES = [
    ("VIP", "VIP", "A gold VIP tag over your name and in chat, +10% income, and one free Luck Potion for the whole server every day.", 599),
    ("Income2x", "x2 Income", "Every slime on your pads earns twice as much, for good.", 449),
    ("Offline2x", "x2 Offline Cash", "Earn half your income while you are away instead of a quarter, for good.", 199),
    ("FastBrew", "Fast Brew", "Every merge brews in half the time, for good. Stacks with the Quick Brew upgrade.", 249),
    ("WarmNest", "Warm Nest", "Mystery Eggs on your pads incubate at the warm speed even while you are away from home.", 129),
    ("LuckyCharmPlus", "Lucky Charm+", "+5% chance that a wild slime you bring home turns one rarity higher. Wild slimes only.", 249),
    ("ThiefRadar", "Thief Radar", "Tells you when someone walks into your base while you are away, and points you to them. Information only.", 149),
]


def main():
    H = {"x-api-key": key()}
    ids = json.load(open(OUT)) if os.path.exists(OUT) else {}
    for k, name, desc, price in PASSES:
        if f"pass:{k}" in ids:
            print("skip", k)
            continue
        r = requests.post(
            f"https://apis.roblox.com/game-passes/v1/universes/{U}/game-passes",
            headers=H,
            files={"name": (None, name), "description": (None, desc), "isForSale": (None, "false"), "price": (None, str(price))},
            timeout=60,
        )
        if r.status_code >= 300:
            print("FAIL", k, r.status_code, r.text[:300])
            break
        gid = r.json()["gamePassId"]
        ids[f"pass:{k}"] = gid
        json.dump(ids, open(OUT, "w"), indent=1)
        print("created", k, gid)
        time.sleep(0.5)


if __name__ == "__main__":
    main()
