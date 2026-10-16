#!/usr/bin/env bash
# PR gate 2/3: UI layout at 390x844, 844x390, 1024x768, 1366x768, 1920x1080.
#   a) Lune: tests/ui Layout* + ScrollLists specs (LayoutAssert on
#      Layout.screen rects: off-screen, covered / overlapping, squashed,
#      touch size, text fit). Always gates.
#   b) rhr: draws the HUD + nav per viewport (rhr_hud.luau) and asserts on
#      rhr's own layout and hit map (rhr_check.py). Skips with a notice when
#      rhr is not installed, unless PR_GATE_REQUIRE_RHR=1.
# Flags: --lune-only, --rhr-only. PR_GATE_SKIP_RHR=1 skips (b).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need lune

do_lune=1
do_rhr=1
case "${1:-}" in
--lune-only) do_rhr=0 ;;
--rhr-only) do_lune=0 ;;
"") ;;
*)
	echo "usage: layout.sh [--lune-only|--rhr-only]" >&2
	exit 2
	;;
esac

cd "$GAME_DIR"
failed=0

if [ "$do_lune" = 1 ]; then
	log="$(mktemp)"
	rc=0
	lune run tests/ui Layout ScrollLists >"$log" 2>&1 || rc=$?
	show_log "$log"
	rm -f "$log"
	if [ "$rc" -ne 0 ]; then
		echo "layout (lune LayoutAssert): FAIL"
		failed=1
	else
		echo "layout (lune LayoutAssert): ok"
	fi
fi

if [ "$do_rhr" = 1 ]; then
	rhr="$(find_rhr)"
	if [ "${PR_GATE_SKIP_RHR:-0}" = 1 ]; then
		echo "layout (rhr render): SKIP (PR_GATE_SKIP_RHR=1)"
	elif [ -z "$rhr" ]; then
		if [ "${PR_GATE_REQUIRE_RHR:-0}" = 1 ]; then
			echo "layout (rhr render): FAIL (rhr not installed and PR_GATE_REQUIRE_RHR=1)"
			failed=1
		else
			echo "layout (rhr render): SKIP - rhr (roblox-headless-renderer==1.0.0rc1) is not installed;"
			echo "  the Lune LayoutAssert part above still gates. Install: tools/pr-gate/README.md."
			[ -n "${GITHUB_ACTIONS:-}" ] && echo "::notice title=pr-gate rhr skipped::rhr not installed; Lune LayoutAssert still gated"
		fi
	else
		out="$(mktemp -d)"
		rc=0
		lune run "$PR_GATE_DIR/rhr_hud.luau" "$out" >/dev/null && python3 "$PR_GATE_DIR/rhr_check.py" "$out" "$rhr" || rc=$?
		rm -rf "$out"
		if [ "$rc" -ne 0 ]; then
			echo "layout (rhr render): FAIL (exit $rc)"
			failed=1
		else
			echo "layout (rhr render): ok"
		fi
	fi
fi

[ "$failed" = 0 ] || exit 1
