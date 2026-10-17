#!/usr/bin/env bash
# PR gate: logic, layout, budget and typecheck checks with per-check PASS/FAIL and
# wall-clock seconds. Exit 1 if any check fails. Runs locally and in CI:
#   tools/pr-gate/run.sh            # all four
#   tools/pr-gate/run.sh layout     # a subset, by name
#   tools/pr-gate/run.sh runtime_budget   # opt-in: not in the default list, CI runs it as its own step
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e

checks=("$@")
[ ${#checks[@]} -gt 0 ] || checks=(logic layout budget typecheck)

now() { date +%s.%N; }
start_all="$(now)"
results=()
failed=0
for c in "${checks[@]}"; do
	if [ ! -f "$PR_GATE_DIR/$c.sh" ]; then
		echo "pr-gate: unknown check '$c' (logic, layout, budget, typecheck, runtime_budget)" >&2
		exit 2
	fi
	echo "=== $c ==="
	t0="$(now)"
	bash "$PR_GATE_DIR/$c.sh"
	rc=$?
	secs="$(awk -v a="$t0" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }')"
	if [ "$rc" -eq 0 ]; then
		results+=("PASS  $c  ${secs}s")
	else
		results+=("FAIL  $c  ${secs}s (exit $rc)")
		failed=1
	fi
done
total="$(awk -v a="$start_all" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }')"

echo
echo "=== pr-gate summary ==="
for r in "${results[@]}"; do
	echo "  $r"
done
echo "  total ${total}s"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
	{
		echo "### pr-gate"
		echo '```'
		printf '%s\n' "${results[@]}" "total ${total}s"
		echo '```'
	} >>"$GITHUB_STEP_SUMMARY"
fi
exit "$failed"
