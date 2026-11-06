"""Check that every asset id Steal a Slime uses loads in its experience, and grant the experience use of the ones
that don't. Read-only unless --grant.

    python tools/assets/check_assets.py                 # from games/steal-a-slime: list the ids by kind, probe them
    python tools/assets/check_assets.py --version 2     # probe on that place version (default: the latest)
    python tools/assets/check_assets.py --grant         # then grant the universe Use of every failing id, and probe again

Kinds: audio (Sound IsLoaded + TimeLength), model (InsertService:LoadAsset, the slime kit packages), mesh
(AssetService:CreateMeshPartAsync), image (ContentProvider:PreloadAsync status). The probe is tools/assets/probe.luau,
run with Open Cloud Luau Execution; it never touches DataStores. A group-owned game can't load user-owned audio or
packages until the owner grants the universe use of them (/guides/roblox-assets.md); a grant keeps the asset id.
The key (tools/monetization/apikey.py) is never printed.
"""
import argparse, json, os, re, sys, time
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(GAME, "tools", "monetization"))
from apikey import key, UNIVERSE, PLACE  # noqa: E402

API = "https://apis.roblox.com"


def src(p):
    return open(os.path.join(GAME, p), encoding="utf-8").read()


def asset_ids(s):
    return re.findall(r"rbxassetid://(\d+)", s)


def collect():
    """{kind: {id: label}} for every asset id under src/."""
    ma = src("src/shared/MeshAssets.luau")
    mesh = {}
    for m in re.finditer(r'entries\["([^"]+)"\]\s*=\s*\{([^}]*)\}', ma):
        mid = re.search(r'meshId = "rbxassetid://(\d+)"', m.group(2))
        if mid:
            mesh[mid.group(1)] = m.group(1)
    for name, i in re.findall(r'(\w+) = \{ id = "rbxassetid://(\d+)"', src("src/visuals/client/ObbyBackdrop.luau")):
        mesh[i] = name

    cfg = src("src/shared/Config.luau")
    kits = re.findall(r'"(slime_\w+)"', src("src/shared/SlimeLooks.luau").split("KITS = table.freeze({", 1)[1].split("})", 1)[0])
    model = {}
    for k in kits:
        m = re.search(r'entries\["%s"\]\s*=\s*\{[^}]*assetId = (\d+)' % k, ma)
        if m:
            model[m.group(1)] = k
    model[re.search(r"SLIME_MESH_ASSET_ID = (\d+)", cfg).group(1)] = "SLIME_MESH_ASSET_ID"

    bat = src("src/shared/BatModel.luau")
    audio = {}
    for line in src("src/ui/Sounds.luau").splitlines():
        if line.strip().startswith("--"):
            continue  # doc examples
        for i in asset_ids(line):
            audio[i] = "Sounds: " + line.strip()[:40]
    for line in cfg.splitlines():
        if re.search(r"SOUND|AMBIENT|ONESHOT|MUSIC|FOUNTAIN_ID|RITUAL_HUM|day =|night =|boss =|Rain =|Snow =", line):
            for i in asset_ids(line):
                audio[i] = "Config: " + line.strip()[:40]
    for i in asset_ids(src("src/visuals/client/EggSmashFx.luau")):
        if i != "0":
            audio[i] = "EggSmashFx"
    audio[re.search(r'SWING_SOUND = "rbxassetid://(\d+)"', bat).group(1)] = "BatModel.SWING_SOUND"

    image = {}
    for line in src("src/ui/ItemIcons.luau").splitlines():
        for i in re.findall(r"\b(\d{9,16})\b", line):
            image[i] = "ItemIcons: " + line.strip()[:40]
    for i in asset_ids(src("src/server/EventBoardView.luau")):
        image[i] = "EventBoardView"
    image[re.search(r'ICON_ID = "rbxassetid://(\d+)"', bat).group(1)] = "BatModel.ICON_ID"

    lists = {"audio": audio, "model": model, "mesh": mesh, "image": image}
    seen = set().union(*lists.values())
    rest = set()
    for root, _, files in os.walk(os.path.join(GAME, "src")):
        for f in files:
            if f.endswith(".luau"):
                rest |= set(asset_ids(open(os.path.join(root, f), encoding="utf-8").read()))
    rest -= seen | {"0", "123"}
    if rest:
        print("WARNING: ids under src/ this script does not classify:", sorted(rest))
    return lists


def run_probe(H, lists, kind, version):
    body = open(os.path.join(HERE, "probe.luau"), encoding="utf-8").read()
    script = f"--!nocheck\nMODE_FILTER = {json.dumps(kind)}\nLISTS = game:GetService('HttpService'):JSONDecode([==[{json.dumps(lists)}]==])\n" + body
    base = f"{API}/cloud/v2/universes/{UNIVERSE}/places/{PLACE}" + (f"/versions/{version}" if version else "")
    for wait in (0, 15, 30, 60, 120):
        time.sleep(wait)
        r = requests.post(base + "/luau-execution-session-tasks", headers=H, json={"script": script, "timeout": "300s"}, timeout=60)
        if r.status_code != 429:
            break
    r.raise_for_status()
    path = r.json()["path"]
    for _ in range(140):
        time.sleep(3)
        t = requests.get(f"{API}/cloud/v2/{path}", headers=H, timeout=60).json()
        if t.get("state") in ("COMPLETE", "FAILED", "CANCELLED"):
            break
    if t.get("state") != "COMPLETE":
        sys.exit(f"{kind}: task {t.get('state')} {t.get('error')}")
    return json.loads(t["output"]["results"][0])


def grant(H, ids):
    ok, errors = [], []
    for i in range(0, len(ids), 20):
        reqs = [{"assetId": int(a), "grantToDependencies": True} for a in ids[i:i + 20]]
        r = requests.patch(f"{API}/asset-permissions-api/v1/assets/permissions", headers=H, timeout=60,
                           json={"subjectType": "Universe", "subjectId": UNIVERSE, "action": "Use", "requests": reqs})
        if not r.ok:
            sys.exit(f"grant: HTTP {r.status_code} {r.text[:300]}")
        ok += r.json().get("successAssetIds", [])
        errors += r.json().get("errors", [])
    print(f"granted {len(ok)} of {len(ids)}" + (f", errors: {json.dumps(errors)[:800]}" if errors else ""))


def probe_all(H, lists, version):
    failed = []
    for kind in lists:
        res = run_probe(H, lists, kind, version)
        c = res["counts"][kind]
        print(f"{kind:6} {c['ok']}/{c['total']} load")
        for f in res["failed"]:
            print(f"  FAIL {kind} {f['id']}  {f['label']}  ({f['why']})")
        failed += res["failed"]
    return failed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", help="place version (default: latest)")
    ap.add_argument("--grant", action="store_true", help="grant the universe Use of every failing id, then probe again")
    a = ap.parse_args()
    H = {"x-api-key": key()}
    lists = collect()
    print(f"universe {UNIVERSE}: " + ", ".join(f"{k} {len(v)}" for k, v in lists.items()))
    failed = probe_all(H, lists, a.version)
    if failed and a.grant:
        grant(H, sorted({f["id"] for f in failed}))
        failed = probe_all(H, lists, a.version)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
