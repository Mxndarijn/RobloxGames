#!/usr/bin/env bash
# PR gate 4/4: luau-lsp type check, the same games/steal-a-slime/scripts/typecheck.sh
# the CI types job runs. Skips (exit 0) when luau-lsp or rojo is missing, so the
# pr-gate job still passes on runners without them.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! command -v luau-lsp >/dev/null 2>&1 || ! command -v rojo >/dev/null 2>&1; then
	echo "typecheck: SKIP (luau-lsp/rojo missing; CI types job covers it)"
	exit 0
fi

cd "$GAME_DIR"
bash scripts/typecheck.sh
