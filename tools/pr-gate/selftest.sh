#!/usr/bin/env bash
# Proves each PR gate check fails on a deliberately broken tree, then that the
# whole gate passes on the clean tree. Breakage goes into a temp copy of
# tools/pr-gate + games/steal-a-slime (shared/ is symlinked, read-only use);
# the working tree is never modified.
#
#   logic   a failing spec fixture copied into tests/
#   layout  src/ui/Layout.luau edits: one nav column (PR #60's off-screen
#           Rebirth / Goals / Dex / Leaders at 844x390), squashed nav buttons,
#           the carry card moved over the nav (covered buttons); each must fail
#           the Lune part and, when rhr is installed, the rhr part on its own
#   budget  401 mesh slots (counts fixture), a triangle limit under today's
#           count (budgets fixture), WorldLayout.MESH_SLOT_BUDGET raised to
#           450 in code, and a missing FBX folder
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tools" "$tmp/games"
cp -r "$PR_GATE_DIR" "$tmp/tools/pr-gate"
cp -r "$GAME_DIR" "$tmp/games/steal-a-slime"
ln -s "$PR_GATE_ROOT/shared" "$tmp/shared"
T_GATE="$tmp/tools/pr-gate"
T_GAME="$tmp/games/steal-a-slime"
LAYOUT="$T_GAME/src/ui/Layout.luau"
WORLD="$T_GAME/src/visuals/shared/WorldLayout.luau"
cp "$LAYOUT" "$tmp/Layout.luau.orig"
cp "$WORLD" "$tmp/WorldLayout.luau.orig"

rhr="$(find_rhr)"
ok=0
bad=0
rows=()

# expect_fail NAME PATTERN CMD...: CMD must exit non-zero and print PATTERN.
expect_fail() {
	local name="$1" pattern="$2"
	shift 2
	local t0 out rc secs
	t0="$(date +%s.%N)"
	out="$(env PR_GATE_ROOT="$tmp" GAME_DIR="$T_GAME" PR_GATE_VERBOSE=1 "$@" 2>&1)"
	rc=$?
	secs="$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }')"
	if [ "$rc" -ne 0 ] && grep -qE -- "$pattern" <<<"$out"; then
		rows+=("ok    FAIL as expected  ${secs}s  $name")
		ok=$((ok + 1))
	else
		rows+=("BAD   exit $rc, pattern '$pattern' $(grep -qE -- "$pattern" <<<"$out" && echo found || echo missing)  $name")
		bad=$((bad + 1))
		echo "--- output of: $name"
		echo "$out" | tail -25
	fi
}

# break_file FILE OLD NEW: replace one exact snippet (fails loudly if gone).
break_file() {
	python3 - "$@" <<'EOF'
import sys
path, old, new = sys.argv[1:4]
src = open(path).read()
if old not in src:
    sys.exit(f"selftest: snippet not found in {path}: {old!r}")
open(path, "w").write(src.replace(old, new, 1))
EOF
}

restore() {
	cp "$tmp/Layout.luau.orig" "$LAYOUT"
	cp "$tmp/WorldLayout.luau.orig" "$WORLD"
	rm -f "$T_GAME/tests/PrGateSelftest.spec.luau"
}

echo "=== selftest: logic ==="
cp "$T_GATE/fixtures/failing.spec.luau" "$T_GAME/tests/PrGateSelftest.spec.luau"
expect_fail "logic: failing assertion fixture" "pr-gate selftest .*a wrong assertion" bash "$T_GATE/logic.sh"
restore

layout_case() {
	local name="$1" old="$2" new="$3" lune_pat="$4" rhr_pat="$5"
	break_file "$LAYOUT" "$old" "$new" || {
		bad=$((bad + 1))
		rows+=("BAD   could not apply breakage  $name")
		return
	}
	expect_fail "layout/lune: $name" "$lune_pat" bash "$T_GATE/layout.sh" --lune-only
	if [ -n "$rhr" ]; then
		expect_fail "layout/rhr:  $name" "$rhr_pat" bash "$T_GATE/layout.sh" --rhr-only
	else
		rows+=("skip  rhr not installed  layout/rhr: $name")
	fi
	restore
}

echo "=== selftest: layout ==="
layout_case "one nav column at 844x390 (pre-#60 off-screen nav)" \
	"local columns = if short then Layout.navColumns(H - inset - top) else 1" \
	"local columns = 1" \
	"844x390 nav collapsed\] Nav\.(Rebirth|Goals|Dex|Leaders) .* is off the" \
	"\[844x390-collapsed\] Nav/(Rebirth|Goals|Dex|Leaders) .* is off the 844x390 screen"
layout_case "squashed nav buttons (70% height)" \
	"nav.y + p + row * (size + gap), w, size))" \
	"nav.y + p + row * (size + gap), w, size * 0.7))" \
	"Nav\.Dex .* is squashed" \
	"Nav/Dex .* is squashed"
layout_case "carry card moved over the nav (covered buttons)" \
	"local carry, slap, tutorial, tutorialCarrying = bottomCards(row, W, H, inset, beside)" \
	"local carry, slap, tutorial, tutorialCarrying = bottomCards(row, W, H, inset, beside)
	carry = Layout.rect(nav.x, nav.y, carry.w, carry.h)" \
	"Nav\.(Toggle|Plot) .* overlaps Carry" \
	"Nav/(NavToggle|Plot) .* is covered (by SlimeUI/Root/Carry|: a click at its centre goes to SlimeUI/Root/Carry)"

echo "=== selftest: budget ==="
expect_fail "budget: 401 mesh slots (counts fixture)" "mesh_slots +401 +400 .*OVER" \
	env PR_GATE_COUNTS="$T_GATE/fixtures/over-budget-counts.json" bash "$T_GATE/budget.sh"
expect_fail "budget: triangle limit 300k (budgets fixture)" "world_triangles .* 300000 .*OVER" \
	env PR_GATE_BUDGETS="$T_GATE/fixtures/tight-budgets.json" bash "$T_GATE/budget.sh"
break_file "$WORLD" "WorldLayout.MESH_SLOT_BUDGET = 400" "WorldLayout.MESH_SLOT_BUDGET = 450"
expect_fail "budget: WorldLayout.MESH_SLOT_BUDGET raised to 450 in code" "MESH_SLOT_BUDGET = 450 is above" \
	bash "$T_GATE/budget.sh"
restore
mkdir -p "$tmp/no-fbx"
expect_fail "budget: FBX folder missing (triangles unknown)" "no FBX in" \
	env PR_GATE_FBX_DIR="$tmp/no-fbx" bash "$T_GATE/budget.sh"

echo "=== selftest: clean tree (the real working tree, unmodified) ==="
t0="$(date +%s.%N)"
clean_out="$(env -u GAME_DIR -u PR_GATE_ROOT bash "$PR_GATE_DIR/run.sh" 2>&1)"
clean_rc=$?
secs="$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1f", b - a }')"
echo "$clean_out" | sed -n '/=== pr-gate summary ===/,$p'
if [ "$clean_rc" -eq 0 ]; then
	rows+=("ok    PASS on clean tree  ${secs}s  run.sh (logic, layout, budget)")
	ok=$((ok + 1))
else
	rows+=("BAD   clean tree failed (exit $clean_rc)  run.sh")
	bad=$((bad + 1))
	echo "$clean_out" | tail -40
fi

echo
echo "=== selftest summary ==="
printf '  %s\n' "${rows[@]}"
echo "  $ok ok, $bad bad"
[ "$bad" -eq 0 ]
