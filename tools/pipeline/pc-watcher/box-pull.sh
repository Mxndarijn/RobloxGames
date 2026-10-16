#!/usr/bin/env bash
# Box side: copy PC watcher reports from origin's orphan branch `studio-reports`
# to /workspace/roblox/pipeline/studio-reports/ (<sha>.json + <sha>/ frames).
#   box-pull.sh            pull once
#   box-pull.sh --loop 60  pull every 60s
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${PCW_DEST:-/workspace/roblox/pipeline/studio-reports}"
CLONE="${PCW_CLONE:-/workspace/roblox/pipeline/.studio-reports-git}"
URL="${PCW_URL:-$(git -C "$HERE" remote get-url origin)}"

pull() {
	if [ ! -d "$CLONE/.git" ]; then
		git init -q "$CLONE"
		git -C "$CLONE" remote add origin "$URL"
	fi
	if ! git -C "$CLONE" fetch -q origin studio-reports 2>/dev/null; then
		echo "box-pull: no studio-reports branch yet"
		return 0
	fi
	git -C "$CLONE" checkout -q -f FETCH_HEAD
	mkdir -p "$DEST"
	if [ -d "$CLONE/studio-reports" ]; then
		cp -r "$CLONE/studio-reports/." "$DEST/"
	fi
	echo "box-pull: $(git -C "$CLONE" rev-parse --short HEAD) -> $DEST ($(ls "$DEST"/*.json 2>/dev/null | wc -l) reports)"
}

if [ "${1:-}" = "--loop" ]; then
	every="${2:-60}"
	while true; do
		pull || echo "box-pull: failed, retrying"
		sleep "$every"
	done
else
	pull
fi
