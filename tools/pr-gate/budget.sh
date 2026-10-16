#!/usr/bin/env bash
# PR gate 3/3: world budgets from tools/pr-gate/budgets.json - mesh slots
# (MeshParts, <= 400), parts, border parts, world triangles and the largest
# mesh's triangles. Counts come from budget_counts.luau (WorldLayout.build()),
# triangles from shared/modeling-kit/out/<mesh>.fbx.
# Overrides (selftest, experiments):
#   PR_GATE_BUDGETS  another budgets file
#   PR_GATE_COUNTS   a counts JSON instead of counting the world
#   PR_GATE_FBX_DIR  another FBX folder
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need lune
need python3

budgets="${PR_GATE_BUDGETS:-$PR_GATE_DIR/budgets.json}"
fbx_dir="${PR_GATE_FBX_DIR:-$PR_GATE_ROOT/shared/modeling-kit/out}"
counts="$(mktemp)"
trap 'rm -f "$counts"' EXIT

if [ -n "${PR_GATE_COUNTS:-}" ]; then
	cp "$PR_GATE_COUNTS" "$counts"
	echo "  counts: $PR_GATE_COUNTS (override)"
else
	(cd "$GAME_DIR" && lune run "$PR_GATE_DIR/budget_counts.luau") >"$counts"
fi
[ "$budgets" = "$PR_GATE_DIR/budgets.json" ] || echo "  budgets: $budgets (override)"

if python3 "$PR_GATE_DIR/budget_check.py" "$counts" "$budgets" "$fbx_dir"; then
	echo "budget: ok"
else
	echo "budget: FAIL"
	exit 1
fi
