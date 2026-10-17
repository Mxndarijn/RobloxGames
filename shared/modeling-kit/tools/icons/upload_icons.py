#!/usr/bin/env python3
"""Upload every out/icons/<id>.png as a Decal (Open Cloud Assets API) via upload.py's functions. DRY RUN BY DEFAULT.

    python3 tools/icons/upload_icons.py                 # dry run: lists what would be sent
    python3 tools/icons/upload_icons.py --go            # really upload (idempotent: ids whose sha is already recorded are skipped)
    python3 tools/icons/upload_icons.py --go --only Lock,Gift
    python3 tools/icons/upload_icons.py --resolve --go  # only (re)resolve image ids of recorded decals

Records icons_uploaded.json: {id: {assetId (the Decal), imageId (what ItemIcons.IMAGES needs), sha256}}.
Open Cloud's Decal create returns the DECAL asset id; a Decal's Texture points at the Image asset (the
id usable as rbxassetid:// in an ImageLabel). resolve_image_id() reads it back through Luau Execution
(InsertService:LoadAsset(decalId) -> Decal.Texture), the probe_meshids.py pattern.
Stops at the first auth / permission / moderation failure and prints the HTTP status + error text (never the key).
"""
import argparse, hashlib, json, os, re, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, KIT)
import upload as U  # noqa: E402

ICONS = os.path.join(KIT, "out", "icons")
RECORD = os.path.join(KIT, "icons_uploaded.json")
UNIVERSE, PLACE = "10770917350", "135787188192378"  # Luau Execution target (probe_meshids.py)


def sha_of(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def request_for(icon_id, user_id):
    return {"assetType": "Decal", "displayName": f"Slime icon {icon_id}",
            "description": f"{icon_id}: item icon (own work, modeling-kit)",
            "creationContext": {"creator": {"userId": user_id}}}


def create(path, icon_id, key, user_id):
    body, ctype = U.multipart(request_for(icon_id, user_id), path)
    for attempt in range(6):
        status, op = U.call("POST", f"{U.API}/assets", key, body, ctype)
        if status == 429:
            time.sleep(5 * (attempt + 1))
            continue
        break
    if status >= 300:
        raise RuntimeError(f"HTTP {status} {op.get('error', '')}")
    op = U.poll(U.API, op, key)
    if "error" in op:
        raise RuntimeError(f"operation failed: {json.dumps(op['error'])[:300]}")
    return str(op["response"]["assetId"]), op


def resolve_image_ids(decals, key):
    """{id: decalAssetId} -> {id: imageAssetId} through one Luau Execution task."""
    import urllib.request
    lua = "local IS=game:GetService('InsertService');local out={}\n"
    for n, d in decals.items():
        lua += (f"do local ok,m=pcall(function() return IS:LoadAsset({d}) end) if not ok then table.insert(out,'{n} ERR '..tostring(m)) else "
                f"for _,x in m:GetDescendants() do if x:IsA('Decal') then table.insert(out,'{n} '..x.Texture) end end end end\n")
    lua += "return table.concat(out,'\\n')"
    status, t = U.call("POST", f"https://apis.roblox.com/cloud/v2/universes/{UNIVERSE}/places/{PLACE}/luau-execution-session-tasks",
                       key, json.dumps({"script": lua}).encode(), "application/json")
    if status >= 300:
        raise RuntimeError(f"luau execution HTTP {status} {t.get('error', '')}")
    path = t["path"]
    for _ in range(60):
        time.sleep(3)
        status, t = U.call("GET", "https://apis.roblox.com/cloud/v2/" + path, key)
        if t.get("state") in ("COMPLETE", "FAILED", "CANCELLED"):
            break
    if t.get("state") != "COMPLETE":
        raise RuntimeError(f"luau execution {t.get('state')} {t.get('error')}")
    out = t.get("output", {}).get("results", t.get("output"))
    text = "\n".join(out) if isinstance(out, list) else str(out)
    res = {}
    for line in text.splitlines():
        m = re.match(r"(\S+) \S*?(\d+)\s*$", line)
        if m and " ERR " not in line:
            res[m.group(1)] = m.group(2)
    return res, text


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--go", action="store_true")
    ap.add_argument("--only")
    ap.add_argument("--resolve", action="store_true", help="only resolve image ids of already uploaded decals")
    ap.add_argument("--user-id", default=U.USER_ID)
    ap.add_argument("--sleep", type=float, default=1.5)
    a = ap.parse_args()

    ids = a.only.split(",") if a.only else sorted(f[:-4] for f in os.listdir(ICONS) if f.endswith(".png"))
    record = json.load(open(RECORD)) if os.path.isfile(RECORD) else {}
    todo = []
    for i in ids:
        path = os.path.join(ICONS, i + ".png")
        sha = sha_of(path)
        if record.get(i, {}).get("sha256") == sha and record[i].get("assetId"):
            continue
        todo.append((i, path, sha))
    print(f"{len(ids)} icons, {len(ids) - len(todo)} already uploaded (same sha), {len(todo)} to {'upload' if a.go else 'send (dry run)'}")
    if not a.go:
        for i, path, sha in todo:
            print(f"would send: POST {U.API}/assets  request={json.dumps(request_for(i, a.user_id))}  fileContent={i}.png ({os.path.getsize(path)} B, sha {sha[:16]}, image/png)")
        print("dry run: nothing sent. Pass --go to upload.")
        return
    if not os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY"):
        U.load_env_file()
    key = os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY")
    if not key:
        sys.exit("upload_icons: ROBLOX_OPEN_CLOUD_API_KEY is not set (env or ~/.config/roblox-ci.env)")

    def save():
        with open(RECORD, "w") as f:
            json.dump(record, f, indent=2, sort_keys=True)

    if not a.resolve:
        for n, (i, path, sha) in enumerate(todo):
            try:
                asset_id, _ = create(path, i, key, a.user_id)
            except Exception as e:  # auth / permission / moderation: stop, keep what we have
                save()
                sys.exit(f"upload_icons: STOP at {i}: {e}")
            record[i] = {"assetId": asset_id, "assetType": "Decal", "sha256": sha, "uploadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            save()
            print(f"[{n + 1}/{len(todo)}] {i}: decal {asset_id}", flush=True)
            time.sleep(a.sleep)
    need = {i: r["assetId"] for i, r in record.items() if "imageId" not in r}
    if need:
        res, text = resolve_image_ids(need, key)
        for i, img in res.items():
            record[i]["imageId"] = img
        save()
        print(f"resolved {len(res)}/{len(need)} image ids")
        if len(res) < len(need):
            print("unresolved:\n" + text[:1500])


if __name__ == "__main__":
    main()
