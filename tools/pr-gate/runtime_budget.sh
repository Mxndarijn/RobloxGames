#!/usr/bin/env bash
# PR gate: runtime part / unique mesh / MeshPart budget, counted like the Studio perf step (pc-watcher's
# perf_server.luau, run against the booted fake runtime; see runtime_budget.luau and README.md).
# Limits: tools/pipeline/pc-watcher/budgets.json (single source, also read by watcher.py, budget.sh and
# tests/RuntimeParts.spec). Parts FAIL > fail / WARN > warn, unique meshes FAIL, MeshParts WARN only.
# Override (selftest): PR_GATE_RT_COUNTS = counts JSON file, no counting; PR_GATE_SHARED_BUDGETS = another budgets.json.
_owner=0
[ -n "${PR_GATE_PRIVATE_TMP:-}" ] || _owner=1
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need python3

budgets="${PR_GATE_SHARED_BUDGETS:-$PR_GATE_ROOT/tools/pipeline/pc-watcher/budgets.json}"
work="$(mktemp -d)"
cleanup() {
	rm -rf "$work"
	[ "$_owner" = 1 ] && rm -rf "$PR_GATE_PRIVATE_TMP"
	return 0
}
trap cleanup EXIT

counts="$work/counts.json"
if [ -n "${PR_GATE_RT_COUNTS:-}" ]; then
	cp "$PR_GATE_RT_COUNTS" "$counts"
	echo "  counts: $PR_GATE_RT_COUNTS (override)"
else
	need lune
	need rojo
	(
		cd "$GAME_DIR" &&
			PR_GATE_PERF_SERVER="$PR_GATE_ROOT/tools/pipeline/pc-watcher/luau/perf_server.luau" \
				lune run "$PR_GATE_DIR/runtime_budget.luau"
	) >"$counts" || { echo "runtime-budget: counting the working tree failed" >&2; exit 1; }
fi

if python3 "$PR_GATE_DIR/runtime_budget_check.py" "$counts" "$budgets"; then
	exit 0
fi
echo "runtime-budget: FAIL (limits: tools/pipeline/pc-watcher/budgets.json)"
exit 1
