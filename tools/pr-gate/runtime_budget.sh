#!/usr/bin/env bash
# PR gate: runtime part + mesh slot budget, counted like the Studio perf step (pc-watcher's
# perf_server.luau, run against the booted fake runtime; see runtime_budget.luau and README.md).
# Counts the working tree and, when a base is known, the base in a temporary git worktree.
#   BASE_SHA / PR_GATE_BASE   base commit (default: git merge-base HEAD origin/main; "none" = no base)
# Overrides (selftest): PR_GATE_RT_COUNTS_HEAD / PR_GATE_RT_COUNTS_BASE = counts JSON files, no counting.
# Budgets come from tools/pipeline/pc-watcher/watcher.py DEFAULTS (runtime_part_budget, mesh_slot_budget).
# Rule per metric: base over budget -> fail only if head > base; else fail if head > budget.
_owner=0
[ -n "${PR_GATE_PRIVATE_TMP:-}" ] || _owner=1
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need python3

watcher="${PR_GATE_WATCHER:-$PR_GATE_ROOT/tools/pipeline/pc-watcher/watcher.py}"
read -r part_budget mesh_budget < <(python3 - "$watcher" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
def get(key):
    m = re.search(r'"%s":\s*(\d+)' % key, src)
    if not m:
        sys.exit("runtime-budget: %s not found in %s" % (key, sys.argv[1]))
    return m.group(1)
print(get("runtime_part_budget"), get("mesh_slot_budget"))
PY
)

work="$(mktemp -d)"
base_tree=""
cleanup() {
	if [ -n "$base_tree" ]; then
		git -C "$PR_GATE_ROOT" worktree remove --force "$base_tree" >/dev/null 2>&1 || true
		git -C "$PR_GATE_ROOT" worktree prune >/dev/null 2>&1 || true
	fi
	rm -rf "$work"
	[ "$_owner" = 1 ] && rm -rf "$PR_GATE_PRIVATE_TMP"
	return 0
}
trap cleanup EXIT

# count_tree ROOT OUT: runtime_budget.luau from the game dir of ROOT; the probe and the Studio
# offset always come from this checkout, so both sides are counted by the same code.
count_tree() {
	local root="$1" out="$2"
	(
		cd "$root/games/steal-a-slime" &&
			PR_GATE_PERF_SERVER="$PR_GATE_ROOT/tools/pipeline/pc-watcher/luau/perf_server.luau" \
				lune run "$PR_GATE_DIR/runtime_budget.luau"
	) >"$out"
}

head_json="$work/head.json"
base_json="-"
if [ -n "${PR_GATE_RT_COUNTS_HEAD:-}" ]; then
	cp "$PR_GATE_RT_COUNTS_HEAD" "$head_json"
	echo "  head counts: $PR_GATE_RT_COUNTS_HEAD (override)"
else
	need lune
	need rojo
	count_tree "$PR_GATE_ROOT" "$head_json" || { echo "runtime-budget: counting the working tree failed" >&2; exit 1; }
fi

base="${BASE_SHA:-${PR_GATE_BASE:-}}"
if [ -n "${PR_GATE_RT_COUNTS_BASE:-}" ]; then
	cp "$PR_GATE_RT_COUNTS_BASE" "$work/base.json" && base_json="$work/base.json"
	echo "  base counts: $PR_GATE_RT_COUNTS_BASE (override)"
elif [ "$base" != none ] && [ -z "${PR_GATE_RT_COUNTS_HEAD:-}" ]; then
	[ -n "$base" ] || base="$(git -C "$PR_GATE_ROOT" merge-base HEAD origin/main 2>/dev/null || true)"
	if [ -z "$base" ]; then
		echo "runtime-budget: no base commit (set BASE_SHA); judging head against the budget alone"
	elif ! git -C "$PR_GATE_ROOT" cat-file -e "$base^{commit}" 2>/dev/null; then
		echo "runtime-budget: base $base not available locally (git fetch it); judging head against the budget alone"
	else
		base_tree="$work/base"
		if git -C "$PR_GATE_ROOT" worktree add --detach "$base_tree" "$base" >/dev/null 2>&1; then
			game_base="$base_tree/games/steal-a-slime"
			# Packages are gitignored: share the head's when wally.toml is unchanged, else install.
			if cmp -s "$GAME_DIR/wally.toml" "$game_base/wally.toml" && [ -d "$GAME_DIR/Packages" ]; then
				ln -s "$GAME_DIR/Packages" "$game_base/Packages"
				[ ! -d "$GAME_DIR/DevPackages" ] || ln -s "$GAME_DIR/DevPackages" "$game_base/DevPackages"
			else
				(cd "$game_base" && wally install >/dev/null 2>&1) || echo "runtime-budget: wally install failed in the base tree" >&2
			fi
			if count_tree "$base_tree" "$work/base.json" 2>"$work/base.err"; then
				base_json="$work/base.json"
			else
				echo "runtime-budget: counting base ${base:0:8} failed (judging head alone):"
				tail -5 "$work/base.err"
			fi
		else
			echo "runtime-budget: git worktree add failed for ${base:0:8} (judging head alone)"
			base_tree=""
		fi
	fi
fi

if python3 "$PR_GATE_DIR/runtime_budget_check.py" "$head_json" "$base_json" "$part_budget" "$mesh_budget"; then
	exit 0
fi
echo "runtime-budget: FAIL (budgets: runtime_part_budget and mesh_slot_budget in tools/pipeline/pc-watcher/watcher.py)"
exit 1
