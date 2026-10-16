#!/usr/bin/env bash
# PR gate 1/3: Lune logic tests, the same `lune run tests` step as
# .github/workflows/pr-checks.yml and cheap-gates.yml (every *.spec.luau).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need lune

cd "$GAME_DIR"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
rc=0
lune run tests >"$log" 2>&1 || rc=$?
# Failures and the summary only; the full log is long.
show_log "$log"
if [ "$rc" -ne 0 ]; then
	tail -5 "$log"
	echo "logic: FAIL (lune run tests exit $rc)"
	exit 1
fi
echo "logic: ok"
