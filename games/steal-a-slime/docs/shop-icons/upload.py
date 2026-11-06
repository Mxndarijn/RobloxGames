#!/usr/bin/env python3
"""Set the approved store icons on Roblox (Steal a Slime, the universe in tools/monetization/apikey.py). DRY RUN BY DEFAULT.

    python upload.py                              # dry run (style B, the picked one): reads the current icons, lists what would change
    python upload.py --go                         # really upload (only after Merijn's OK in chat)
    python upload.py --go --only VIP,Seat_leaf

For each pass / product in manifest.json that has an id in tools/monetization/created_ids.json (the ids in
manifest.json are the old universe's and are not used) it sends out/<style>/<key>.png as `imageFile` to the Open Cloud update
endpoint (PATCH, multipart, 204 on success). Roblox stores the picture as a new Image asset and sets it as the icon. Afterwards it reads
the item back and records {key: {kind, id, style, sha256, iconAssetId, before}} in uploaded.json, so a rerun skips keys
whose file is unchanged. Needs an API key with game-pass:write and developer-product:write (env
ROBLOX_OPEN_CLOUD_API_KEY or ~/.config/roblox-ci.env); the key is never printed. Stops at the first auth, permission
or moderation failure and prints the HTTP status and Roblox's error text.
"""
import argparse, hashlib, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
MONETIZATION = os.path.join(GAME, "tools", "monetization")
sys.path.insert(0, MONETIZATION)
from apikey import UNIVERSE  # noqa: E402
API = "https://apis.roblox.com"
RECORD = os.path.join(HERE, "uploaded.json")
MAX_BYTES = 4_000_000


def endpoint(it):
    if it["kind"] == "pass":
        return f"{API}/game-passes/v1/universes/{UNIVERSE}/game-passes/{it['id']}"
    return f"{API}/developer-products/v2/universes/{UNIVERSE}/developer-products/{it['id']}"


def read_url(it):
    return endpoint(it) + "/creator"


def icon_of(body):
    """Passes call it iconAssetId, products iconImageAssetId."""
    return body.get("iconAssetId") or body.get("iconImageAssetId")


def sha_of(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def call(session, method, url, key, **kw):
    for attempt in range(6):
        r = session.request(method, url, headers={"x-api-key": key}, timeout=60, **kw)
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(5 * (attempt + 1))
            continue
        return r
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", default="B", choices=["A", "B", "C"], help="B is the style Merijn picked")
    ap.add_argument("--go", action="store_true", help="really upload (default: dry run)")
    ap.add_argument("--only", help="comma-separated keys")
    a = ap.parse_args()

    ids = json.load(open(os.path.join(MONETIZATION, "created_ids.json")))
    items = []
    for it in json.load(open(os.path.join(HERE, "manifest.json"))):
        rid = ids.get(f"{it['kind']}:{it['key']}")
        if rid:
            items.append({**it, "id": rid})
        else:
            print(f"  skip {it['key']}: not created in universe {UNIVERSE}")
    if a.only:
        want = set(a.only.split(","))
        items = [i for i in items if i["key"] in want]
        missing = want - {i["key"] for i in items}
        if missing:
            sys.exit("unknown keys: " + ", ".join(sorted(missing)))
    record = json.load(open(RECORD)) if os.path.exists(RECORD) else {}

    todo = []
    for it in items:
        path = os.path.join(HERE, "out", a.style, it["key"] + ".png")
        if not os.path.exists(path):
            sys.exit(f"missing {path}: run build.py first")
        if os.path.getsize(path) > MAX_BYTES:
            sys.exit(f"{path} is over {MAX_BYTES} bytes")
        sha = sha_of(path)
        done = record.get(it["key"])
        if done and done.get("sha256") == sha:
            continue
        todo.append((it, path, sha))
    print(f"style {a.style}: {len(todo)} to set, {len(items) - len(todo)} already set with this exact file")

    from apikey import key as load_key  # never printed
    try:
        key = load_key()
    except SystemExit:
        key = None
    import requests
    s = requests.Session()

    if not a.go:
        for it, path, _ in todo:
            cur = "?"
            if key:
                r = call(s, "GET", read_url(it), key)
                cur = icon_of(r.json()) if r.ok else f"HTTP {r.status_code}"
            print(f"  would set {it['kind']:7} {it['key']:28} {it['id']}  (now {cur})  <- out/{a.style}/{it['key']}.png")
        print("dry run: nothing sent. Add --go after Merijn's OK.")
        return

    if not key:
        sys.exit("no API key (ROBLOX_OPEN_CLOUD_API_KEY or ~/.config/roblox-ci.env)")
    for n, (it, path, sha) in enumerate(todo, 1):
        before = None
        r = call(s, "GET", read_url(it), key)
        if r.ok:
            before = icon_of(r.json())
        with open(path, "rb") as f:
            r = call(s, "PATCH", endpoint(it), key, files={"imageFile": (os.path.basename(path), f, "image/png")})
        if r.status_code >= 300:
            print(f"FAIL {it['key']}: HTTP {r.status_code} {r.text[:300]}")
            if r.status_code in (400, 401, 403):
                sys.exit("stopped: fix the key scope, the file or the moderation issue first")
            continue
        after = None
        r2 = call(s, "GET", read_url(it), key)
        if r2.ok:
            after = icon_of(r2.json())
        record[it["key"]] = {"kind": it["kind"], "id": it["id"], "universe": UNIVERSE, "style": a.style, "sha256": sha,
                             "iconAssetId": after, "before": before,
                             "uploadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        json.dump(record, open(RECORD, "w", newline="\n"), indent=1, sort_keys=True)
        print(f"[{n}/{len(todo)}] {it['key']} -> icon {after}")
        time.sleep(0.4)
    print(f"done; record in {os.path.relpath(RECORD)}")


if __name__ == "__main__":
    main()
