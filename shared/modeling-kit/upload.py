#!/usr/bin/env python3
"""Upload a kit FBX to Roblox as a Model asset (Open Cloud Assets API). DRY RUN BY DEFAULT.

    python3 upload.py out/tree_oak.fbx                       # dry run: prints what it would send
    python3 upload.py out/tree_oak.fbx --update 123456789    # dry run of a new version of asset 123456789
    python3 upload.py out/tree_oak.fbx --go                  # really create (needs Merijn's OK)
    python3 upload.py out/tree_oak.fbx --go --size-check     # + probe the MeshPart size via Luau Execution

create: POST  /assets/v1/assets               multipart: request={assetType,displayName,description,creationContext}, fileContent
update: PATCH /assets/v1/assets/{assetId}     multipart: request={assetId}, fileContent  (new version of the same Model)
Both return an Operation; polled at GET /assets/v1/operations/{id} until done.
Creator: userId 1040646178 (Merijn) unless --user-id/--group-id.

Key: ROBLOX_OPEN_CLOUD_API_KEY from the environment. Only with --go, if it is unset,
~/.config/roblox-ci.env is read into this process's env. The key is never printed,
logged or written. Results go to uploaded.json in the kit (assetId per name).
Refuses an FBX whose <name>.stats.json (from iterate.py) says the budget check failed.
"""
import argparse, hashlib, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request, uuid

KIT = os.path.dirname(os.path.abspath(__file__))
RECORD = os.path.join(KIT, "uploaded.json")
API = "https://apis.roblox.com/assets/v1"
ENV_FILE = os.path.expanduser("~/.config/roblox-ci.env")
# Luau Execution size-check helper, shipped with the kit; override with MODELING_KIT_PROBE.
PROBE = os.environ.get("MODELING_KIT_PROBE", os.path.join(KIT, "tools", "probe_meshids.py"))
USER_ID = "1040646178"
MAX_BYTES = 20 * 1024 * 1024


def load_env_file():
    """Source KEY=VALUE lines into os.environ without echoing anything."""
    if not os.path.isfile(ENV_FILE):
        return
    for line in open(ENV_FILE):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.removeprefix("export ").split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip("'\""))


def ctype_of(path):
    if path.endswith(".png"):
        return "image/png"
    return "model/x-rbxm" if path.endswith((".rbxm", ".rbxmx")) else "model/fbx"


def asset_type_of(path):
    """Animation = KeyframeSequence .rbxm/.rbxmx (Assets API, assetType Animation); .png = Decal (item icons); everything else is a Model FBX."""
    if path.endswith(".png"):
        return "Decal"
    return "Animation" if path.endswith((".rbxm", ".rbxmx")) else "Model"


def multipart(request, path):
    boundary = uuid.uuid4().hex
    body = (f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n{json.dumps(request)}\r\n'
            f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{os.path.basename(path)}"\r\n'
            f"Content-Type: {ctype_of(path)}\r\n\r\n").encode() + open(path, "rb").read() + f"\r\n--{boundary}--\r\n".encode()
    return body, f"multipart/form-data; boundary={boundary}"


def call(method, url, key, body=None, ctype=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if ctype:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode(errors="replace")[:500]}


def poll(api, op, key, tries=30, wait=2.0):
    path = op.get("path") or f"operations/{op.get('operationId')}"
    for _ in range(tries):
        if op.get("done"):
            return op
        time.sleep(wait)
        status, op = call("GET", f"{api}/{path}", key)
        if status >= 300:
            raise RuntimeError(f"operation {path}: HTTP {status} {op.get('error', '')}")
    raise RuntimeError(f"operation {path} not done after {tries * wait:.0f} s")


def plan(a, name, fbx):
    if a.update:
        return "PATCH", f"{a.api}/assets/{a.update}", {"assetId": int(a.update)}
    who = {"groupId": a.group_id} if a.group_id else {"userId": a.user_id}
    return "POST", f"{a.api}/assets", {
        "assetType": asset_type_of(fbx),
        "displayName": a.display_name or name,
        "description": a.description or (f"{name}: item icon (own work, modeling-kit)" if fbx.endswith(".png") else f"{name}: slime animation (KeyframeSequence, own work)" if asset_type_of(fbx) == "Animation" else f"{name}: low-poly mesh made with modeling-kit (own work)"),
        "creationContext": {"creator": who},
    }


def size_check_cmd(name, asset_id, tmp):
    with open(tmp, "w") as f:
        json.dump({name: {"assetId": str(asset_id)}}, f)
    return [sys.executable, PROBE, tmp]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fbx")
    ap.add_argument("--go", action="store_true", help="really call the API (default: dry run)")
    ap.add_argument("--update", metavar="ASSET_ID", help="upload a new version of this existing Model asset")
    ap.add_argument("--name", help="record name (default: fbx stem)")
    ap.add_argument("--display-name")
    ap.add_argument("--description")
    ap.add_argument("--user-id", default=USER_ID)
    ap.add_argument("--group-id")
    ap.add_argument("--size-check", action="store_true", help="after upload, run probe_meshids.py (Luau Execution) for MeshId + Size")
    ap.add_argument("--force", action="store_true", help="upload even if stats.json says FAIL")
    ap.add_argument("--api", default=API, help=argparse.SUPPRESS)  # tests point this at a local mock
    a = ap.parse_args()

    fbx = os.path.abspath(a.fbx)
    name = a.name or os.path.splitext(os.path.basename(fbx))[0]
    if not fbx.endswith((".fbx", ".rbxm", ".rbxmx", ".png")) or not os.path.isfile(fbx):
        sys.exit(f"upload: {a.fbx} is not an existing .fbx / .rbxm / .rbxmx / .png")
    size = os.path.getsize(fbx)
    if size >= MAX_BYTES:
        sys.exit(f"upload: {size} B >= 20 MB Open Cloud limit")
    stats_path = os.path.splitext(fbx)[0] + ".stats.json"
    if os.path.isfile(stats_path):
        st = json.load(open(stats_path))
        if not st.get("pass") and not a.force:
            sys.exit(f"upload: {stats_path} says FAIL: {st.get('fails')}")
        print(f"stats: {st['tris']} tris, size {st['size_studs']} studs, {'PASS' if st['pass'] else 'FAIL'}")
    else:
        print(f"stats: none ({os.path.basename(stats_path)} missing; run iterate.py first)")

    method, url, request = plan(a, name, fbx)
    sha = hashlib.sha256(open(fbx, "rb").read()).hexdigest()[:16]
    print(f"{'SEND' if a.go else 'would send'}: {method} {url}")
    print("  headers: x-api-key: <ROBLOX_OPEN_CLOUD_API_KEY, not shown>, Content-Type: multipart/form-data")
    print(f"  request: {json.dumps(request)}")
    print(f"  fileContent: {os.path.basename(fbx)} ({size} B, sha256 {sha}..., {ctype_of(fbx)})")
    print("  then: poll GET {api}/operations/<id> until done -> assetId -> uploaded.json".format(api=a.api))
    if a.size_check:
        print(f"  then: size check: python3 {PROBE} <tmp json {{{name}: {{assetId}}}}> (Luau Execution, loads the asset only)")
    if not a.go:
        print("dry run: nothing sent. Pass --go to upload (get Merijn's OK first).")
        return

    if not os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY"):
        load_env_file()
    key = os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY")
    if not key:
        sys.exit("upload: ROBLOX_OPEN_CLOUD_API_KEY is not set (env or ~/.config/roblox-ci.env)")
    body, ctype = multipart(request, fbx)
    status, op = call(method, url, key, body, ctype)
    if status >= 300:
        sys.exit(f"upload: HTTP {status} {op.get('error', '')}")
    op = poll(a.api, op, key)
    if "error" in op:
        sys.exit(f"upload: operation failed: {json.dumps(op['error'])[:300]}")
    asset_id = op.get("response", {}).get("assetId") or a.update
    record = json.load(open(RECORD)) if os.path.isfile(RECORD) else {}
    entry = record.get(name, {})
    entry.update({"assetId": str(asset_id), "assetType": asset_type_of(fbx), "sha256": sha,
                  "uploadedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  "versions": entry.get("versions", 0) + 1})
    record[name] = entry
    with open(RECORD, "w") as f:
        json.dump(record, f, indent=2, sort_keys=True)
    print(f"{'updated' if a.update else 'created'} {name}: asset {asset_id} -> {os.path.relpath(RECORD)}")
    if a.size_check:
        with tempfile.TemporaryDirectory() as d:
            cmd = size_check_cmd(name, asset_id, os.path.join(d, "ids.json"))
            print("size check:", " ".join(cmd[1:]))
            subprocess.run(cmd, check=False)  # key reaches it via inherited env only


if __name__ == "__main__":
    main()
