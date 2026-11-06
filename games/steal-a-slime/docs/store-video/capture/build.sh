#!/usr/bin/env bash
# Builds the THROWAWAY video place into $VIDEO_WORK (never into the repo, never uploaded):
#   * a copy of src with the video clock (vclock.py) and the scratch hooks (patches/*.patch)
#   * Workspace DataStoreMode = "Memory", ServerScriptService.LoadStringEnabled = true
set -euo pipefail
W=${VIDEO_WORK:?set VIDEO_WORK to a scratch folder outside the repo}
HERE=$(cd "$(dirname "$0")" && pwd); GAME=$(cd "$HERE/../../.." && pwd)
rm -rf "$W/vsrc"; mkdir -p "$W/vsrc"; cp -r "$GAME/src" "$W/vsrc/src"
(cd "$W/vsrc" && for p in "$HERE"/patches/*.patch; do patch -p1 --quiet < "$p"; done)
python "$HERE/vclock.py" "$W/vsrc/src"
python - "$GAME" "$W" <<'PY'
import json, os, sys
game, w = sys.argv[1], sys.argv[2]
d = json.load(open(os.path.join(game, "default.project.json")))
d["tree"]["Workspace"].setdefault("$attributes", {})["DataStoreMode"] = "Memory"
d["tree"].setdefault("ServerScriptService", {}).setdefault("$properties", {})["LoadStringEnabled"] = True
def fix(n):
    for k, v in list(n.items()):
        if k == "$path" and isinstance(v, str):
            n[k] = (w + "/vsrc/" + v) if v.startswith("src") else os.path.abspath(os.path.join(game, v)).replace(os.sep, "/")
        elif isinstance(v, dict):
            fix(v)
fix(d["tree"])
json.dump(d, open(os.path.join(w, "video.project.json"), "w", newline=""), indent=1)
PY
cd "$GAME" && rojo build "$W/video.project.json" -o "$W/video.rbxl"
