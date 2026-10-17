#!/usr/bin/env bash
# PR gate 3/3: world budgets (then the client UI perf budget, ui_perf_check.luau) from tools/pr-gate/budgets.json (parts, border parts, largest mesh's
# triangles) and tools/pipeline/pc-watcher/budgets.json (world triangles FAIL, MeshParts SOFT warn only). Counts come from budget_counts.luau (WorldLayout.build()),
# triangles from shared/modeling-kit/out/<mesh>.fbx.
# Overrides (selftest, experiments):
#   PR_GATE_BUDGETS  another budgets file
#   PR_GATE_SHARED_BUDGETS  another tools/pipeline/pc-watcher/budgets.json
#   PR_GATE_COUNTS   a counts JSON instead of counting the world
#   PR_GATE_FBX_DIR  another FBX folder
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need lune
need python3

budgets="${PR_GATE_BUDGETS:-$PR_GATE_DIR/budgets.json}"
fbx_dir="${PR_GATE_FBX_DIR:-$PR_GATE_ROOT/shared/modeling-kit/out}"
shared="${PR_GATE_SHARED_BUDGETS:-$PR_GATE_ROOT/tools/pipeline/pc-watcher/budgets.json}"
counts="$(mktemp)"
trap 'rm -f "$counts"' EXIT

if [ -n "${PR_GATE_COUNTS:-}" ]; then
	cp "$PR_GATE_COUNTS" "$counts"
	echo "  counts: $PR_GATE_COUNTS (override)"
else
	(cd "$GAME_DIR" && lune run "$PR_GATE_DIR/budget_counts.luau") >"$counts"
fi
[ "$budgets" = "$PR_GATE_DIR/budgets.json" ] || echo "  budgets: $budgets (override)"

if python3 "$PR_GATE_DIR/budget_check.py" "$counts" "$budgets" "$fbx_dir" "$shared"; then
	echo "budget: ok"
else
	echo "budget: FAIL"
	exit 1
fi

# Client UI performance budget (ratchet): games/steal-a-slime/ui-perf-budget.json
if [ -f "$GAME_DIR/ui-perf-budget.json" ]; then
	if (cd "$GAME_DIR" && lune run "$PR_GATE_DIR/ui_perf_check.luau"); then
		echo "ui-perf: ok"
	else
		echo "ui-perf: FAIL"
		exit 1
	fi
fi
