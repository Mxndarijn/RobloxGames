# Shared setup for tools/pr-gate/*.sh (sourced, not run).
# PR_GATE_ROOT  repo root (default: two levels above this file)
# GAME_DIR      game under test (default: $PR_GATE_ROOT/games/steal-a-slime)
set -euo pipefail

PR_GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_GATE_ROOT="${PR_GATE_ROOT:-$(cd "$PR_GATE_DIR/../.." && pwd)}"
GAME_DIR="${GAME_DIR:-$PR_GATE_ROOT/games/steal-a-slime}"

need() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "pr-gate: '$1' not found on PATH (rokit install in $GAME_DIR, or see tools/pr-gate/README.md)" >&2
		exit 2
	fi
}

# rhr binary: $PR_GATE_RHR, else rhr on PATH, else the box wrapper. Empty if none works.
find_rhr() {
	local c
	for c in "${PR_GATE_RHR:-}" "$(command -v rhr 2>/dev/null || true)" "$HOME/.local/bin/rhr"; do
		if [ -n "$c" ] && [ -x "$c" ] && "$c" --version >/dev/null 2>&1; then
			echo "$c"
			return 0
		fi
	done
	return 0
}

# Test log: failing tests, the distinct problem lines LayoutAssert reported, and
# the summary. PR_GATE_VERBOSE=1 prints the whole log.
show_log() {
	if [ "${PR_GATE_VERBOSE:-0}" = 1 ]; then
		cat "$1"
		return 0
	fi
	{
		grep -E "^\s+FAIL" "$1" | head -20
		grep -oE "\[[0-9]+x[0-9]+[^]]*\] [^\\\"]+" "$1" | sort -u | head -60
		grep -E "passed, .* failed" "$1"
	} || true
}
