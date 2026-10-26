#!/usr/bin/env python3
"""Upload rendered .ogg sounds to Roblox as Audio assets (Open Cloud Assets API). DRY RUN BY DEFAULT.

    python shared/audio-kit/upload.py --all                                  # dry run: prints what it would send
    python shared/audio-kit/upload.py coin boing --user-id 1040646178        # dry run for two sounds
    python shared/audio-kit/upload.py --all --user-id 1040646178 --yes-upload  # really upload (owner's OK first!)

create: POST /assets/v1/assets   multipart: request={assetType: Audio, displayName, description,
        creationContext: {creator: {userId}}}, fileContent (audio/ogg)
The call returns an Operation; it is polled at GET /assets/v1/operations/{id} until done, then the
assetId is written into manifest.json. Sounds that already have an assetId are skipped (--force
uploads them again as new assets).

Key: ROBLOX_OPEN_CLOUD_API_KEY from the environment. Only with --yes-upload, and only if it is
unset, ~/.config/roblox-ci.env is read into this process's env. The key is never printed,
logged or written.
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

KIT = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(KIT, "manifest.json")
API = "https://apis.roblox.com/assets/v1"
ENV_FILE = os.path.expanduser("~/.config/roblox-ci.env")
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


def multipart(request, path):
    boundary = uuid.uuid4().hex
    head = (f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n'
            f"Content-Type: application/json\r\n\r\n{json.dumps(request)}\r\n"
            f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
            f'filename="{os.path.basename(path)}"\r\nContent-Type: audio/ogg\r\n\r\n').encode()
    body = head + open(path, "rb").read() + f"\r\n--{boundary}--\r\n".encode()
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


def poll(api, op, key, tries=60, wait=2.0):
    path = op.get("path") or f"operations/{op.get('operationId')}"
    for _ in range(tries):
        if op.get("done"):
            return op
        time.sleep(wait)
        status, op = call("GET", f"{api}/{path}", key)
        if status >= 300:
            raise RuntimeError(f"operation {path}: HTTP {status} {op.get('error', '')}")
    raise RuntimeError(f"operation {path} not done after {tries * wait:.0f} s")


def request_for(entry, user_id):
    return {
        "assetType": "Audio",
        "displayName": entry["name"][:50],
        "description": (entry.get("description") or entry["name"])[:1000],
        "creationContext": {"creator": {"userId": str(user_id)}},
    }


def save_manifest(man):
    with open(MANIFEST, "w", newline="\n") as f:
        json.dump(man, f, indent=2)
        f.write("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="sound names from manifest.json")
    ap.add_argument("--all", action="store_true", help="every sound in manifest.json")
    ap.add_argument("--user-id", help="Roblox user id that will own the assets (required to upload)")
    ap.add_argument("--yes-upload", action="store_true", help="really call the API (default: dry run)")
    ap.add_argument("--force", action="store_true", help="upload even if the sound already has an assetId")
    ap.add_argument("--api", default=API, help=argparse.SUPPRESS)  # tests can point this at a local mock
    a = ap.parse_args()

    man = json.load(open(MANIFEST))
    by_name = {e["name"]: e for e in man["sounds"]}
    if not a.all and not a.names:
        sys.exit("upload: name some sounds or pass --all")
    names = list(by_name) if a.all else a.names
    unknown = [n for n in names if n not in by_name]
    if unknown:
        sys.exit(f"upload: not in manifest.json: {', '.join(unknown)}")
    if a.yes_upload and not a.user_id:
        sys.exit("upload: --user-id is required with --yes-upload")

    todo = []
    for n in names:
        e = by_name[n]
        path = os.path.join(KIT, e["file"])
        if not os.path.isfile(path):
            sys.exit(f"upload: {e['file']} missing; run render.py first")
        size = os.path.getsize(path)
        if size >= MAX_BYTES:
            sys.exit(f"upload: {e['file']} is {size} B, over the 20 MB limit")
        if e.get("assetId") and not a.force:
            print(f"skip {n}: already uploaded as {e['assetId']} (--force to upload a new copy)")
            continue
        todo.append((e, path, size))

    verb = "SEND" if a.yes_upload else "would send"
    for e, path, size in todo:
        sha = hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]
        req = request_for(e, a.user_id or "<--user-id>")
        print(f"{verb}: POST {a.api}/assets")
        print("  headers: x-api-key: <ROBLOX_OPEN_CLOUD_API_KEY, not shown>, Content-Type: multipart/form-data")
        print(f"  request: {json.dumps(req)}")
        print(f"  fileContent: {os.path.basename(path)} ({size} B, sha256 {sha}..., audio/ogg)")
    if not todo:
        print("nothing to upload.")
        return
    print(f"then: poll GET {a.api}/operations/<id> until done -> assetId -> manifest.json")
    if not a.yes_upload:
        print("dry run: nothing sent. Pass --yes-upload --user-id <id> to upload (get the owner's OK first).")
        return

    if not os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY"):
        load_env_file()
    key = os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY")
    if not key:
        sys.exit("upload: ROBLOX_OPEN_CLOUD_API_KEY is not set (env or ~/.config/roblox-ci.env)")
    failed = 0
    for e, path, _ in todo:
        body, ctype = multipart(request_for(e, a.user_id), path)
        status, op = call("POST", f"{a.api}/assets", key, body, ctype)
        if status >= 300:
            print(f"FAIL {e['name']}: HTTP {status} {op.get('error', '')}")
            failed += 1
            continue
        try:
            op = poll(a.api, op, key)
        except RuntimeError as err:
            print(f"FAIL {e['name']}: {err}")
            failed += 1
            continue
        if "error" in op:
            print(f"FAIL {e['name']}: operation failed: {json.dumps(op['error'])[:300]}")
            failed += 1
            continue
        asset_id = str(op.get("response", {}).get("assetId", ""))
        if not asset_id:
            print(f"FAIL {e['name']}: no assetId in the finished operation")
            failed += 1
            continue
        e["assetId"] = asset_id
        save_manifest(man)  # after every success, so a later failure loses nothing
        print(f"created {e['name']}: rbxassetid://{asset_id}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
