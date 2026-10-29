"""Create every Exclusive Shop Developer Product for Steal a Slime (universe 10770917350), once each.

Reads products.json (dumped from Config) plus the five Exclusive bases. Dry run unless --go. Ids go to
created_ids.json (product:<key> -> id); a key already there is skipped, so a rerun resumes. The key is never printed.
Developer Products can only be bought inside the game, so they are created on sale.
"""
import json, os, sys, time, requests
sys.path.insert(0, os.path.dirname(__file__))

U = "10770917350"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "created_ids.json")
data = json.load(open(os.path.join(HERE, "products.json")))

BASES = [("carousel", "Carousel Tent", 599), ("rocket", "Space Rocket", 499), ("treehouse", "Tree House", 499),
         ("lighthouse", "Lighthouse", 399), ("snowglobe", "Snow Globe", 399)]


def find(lst, i):
    for d in lst or []:
        if d["id"] == i:
            return d
    return {"id": i, "name": i}


FIXED = {
    "StarterBundle": ("Starter bundle", "The Leaf cloud for your pet and x2 income for 15 minutes. Once per player."),
    "BoutiqueBundle": ("Boutique bundle", "The Magic Carpet cloud, the Fairground base skin and the Confetti fanfare, for less than the three."),
    "SkyBundle": ("Sky bundle", "Storm, Sunset, Ice and Flame clouds together, for less than the four."),
    "FinishBrew_1": ("Finish brew (up to 5 min)", "Finishes your merge vat brew now. The result was already decided when the brew started."),
    "FinishBrew_2": ("Finish brew (up to 30 min)", "Finishes your merge vat brew now. The result was already decided when the brew started."),
    "FinishBrew_3": ("Finish brew (up to 1 hour)", "Finishes your merge vat brew now. The result was already decided when the brew started."),
    "FinishBrew_4": ("Finish brew (over 1 hour)", "Finishes your merge vat brew now. The result was already decided when the brew started."),
    "HatchNow_speckled": ("Hatch now: Speckled egg", "Your Speckled Mystery Egg is ready to hatch now. What is inside was decided when it started."),
    "HatchNow_shiny": ("Hatch now: Shiny egg", "Your Shiny Mystery Egg is ready to hatch now. What is inside was decided when it started."),
    "HatchNow_golden": ("Hatch now: Golden egg", "Your Golden Mystery Egg is ready to hatch now. What is inside was decided when it started."),
    "HatchNow_cosmic": ("Hatch now: Cosmic egg", "Your Cosmic Mystery Egg is ready to hatch now. What is inside was decided when it started."),
    "DoubleOffline": ("Double offline cash", "Get your last welcome-back offline cash a second time."),
    "ServerLuckPotion": ("Server Luck Potion", "Rarer slimes for everyone on the server: tier 3+ odds x2.5 for 5 more minutes (up to 15)."),
    "LockBreak": ("Open locked door", "Walk through one locked base's door for 60 seconds. The lock stays up for everyone else."),
    "SlimeRain": ("Slime Rain now", "Starts a Slime Rain for the whole server. One paid rain per server every 20 minutes, never during a boss."),
    "SummonBoss": ("Summon the boss", "The boss comes to this server after its usual warning. Once per server every 20 minutes."),
    "WeatherTotem": ("Weather Totem", "The Item shop totem's weather comes next, for everyone on the server."),
    "IncomeBoost15": ("x2 income, 15 min", "Doubles your income for 15 minutes. Adds to a running boost, up to the boost cap."),
    "IncomeBoost60": ("x2 income, 1 hour", "Doubles your income for an hour. Adds to a running boost, up to the boost cap."),
    "KeepStreak": ("Keep my streak", "Missed a day? Your daily streak carries on as if you had not."),
    "GrowthSnack": ("Growth snack", "One slime of yours grows 3 hours at once."),
}


def item(key, grant):
    k = grant["kind"]
    shop = data["shop"]
    if k == "seat":
        n = find(data["seats"], grant["seat"])["name"]
        return (n if n.endswith("Cloud") else f"{n} cloud"), f"An Exclusive pet cloud: your pet rides the {n}. Yours to keep."
    if k == "trail":
        n = find(shop["trails"], grant["trail"])["name"]
        return f"{n} trail", f"A {n.lower()} carry trail that streams behind you while you carry a slime. Yours to keep."
    if k == "batSkin":
        n = find(shop["batSkins"], grant["skin"])["name"]
        return (n if "Bat" in n else f"{n} Bat") + " skin", f"Your Bat looks like a {n.lower()}. Same reach and timing as the normal Bat."
    if k == "fanfare":
        n = find(shop["fanfares"], grant["style"])["name"]
        return f"{n} fanfare", f"A {n.lower()} burst over every slime you bring home. Yours to keep."
    if k == "lockStyle":
        n = find(shop["lockStyles"], grant["style"])["name"]
        return f"{n} lock", f"A {n.lower()} look for the plug that closes your base when you lock it. Locks exactly the same."
    if k == "hat":
        n = find(shop["hats"], grant["style"])["name"]
        return n, f"Every slime on your pads wears a {n.lower()}. Yours to keep."
    if k == "plotSkin":
        n = find(data["skins"], grant["style"])["name"]
        return f"{n} base skin", f"Dresses your whole goo jar tower as the {n}. Yours to keep."
    if k == "plotBase":
        n = dict((b[0], b[1]) for b in BASES)[grant["style"]]
        return f"{n} base", f"Your base becomes the {n}. Same pads, door and lock as every base. Yours to keep."
    return FIXED[key]


def catalogue():
    rows = []
    products = {p["key"]: p for p in data["products"]}
    for bid, name, robux in BASES:
        products[f"Base_{bid}"] = {"key": f"Base_{bid}", "robux": robux, "grant": {"kind": "plotBase", "style": bid}}
        products[f"Gift_Base_{bid}"] = {"key": f"Gift_Base_{bid}", "robux": robux, "grant": {"kind": "gift", "item": f"Base_{bid}"}}
    for key in sorted(products):
        p = products[key]
        g = p["grant"]
        if g["kind"] == "gift":
            inner = products[g["item"]]
            n, _ = item(g["item"], inner["grant"])
            name, desc = f"Gift: {n}", f"Give {n} to another player on your server."
        else:
            name, desc = item(key, g)
        rows.append((key, name, desc, p["robux"]))
    return rows


def main():
    go = "--go" in sys.argv
    rows = catalogue()
    names = [r[1] for r in rows]
    assert len(set(names)) == len(names), "duplicate names"
    if not go:
        for r in rows:
            print(f"{r[0]:32} {r[3]:>4}  {r[1]}  |  {r[2]}")
        print(len(rows), "products (dry run)")
        return
    from apikey import key as api_key
    H = {"x-api-key": api_key()}
    ids = json.load(open(OUT)) if os.path.exists(OUT) else {}
    made = 0
    for key, name, desc, robux in rows:
        if f"product:{key}" in ids:
            continue
        for attempt in range(5):
            r = requests.post(
                f"https://apis.roblox.com/developer-products/v2/universes/{U}/developer-products",
                headers=H,
                files={"name": (None, name), "description": (None, desc), "isForSale": (None, "true"), "price": (None, str(robux))},
                timeout=60,
            )
            if r.status_code == 429 or r.status_code >= 500:
                time.sleep(2 ** attempt)
                continue
            break
        if r.status_code >= 300:
            print("FAIL", key, r.status_code, r.text[:300])
            sys.exit(1)
        ids[f"product:{key}"] = r.json()["productId"]
        json.dump(ids, open(OUT, "w"), indent=1)
        made += 1
        time.sleep(0.4)  # 3 requests per second per user
    print("created", made, "total", sum(1 for k in ids if k.startswith("product:")))


if __name__ == "__main__":
    main()
