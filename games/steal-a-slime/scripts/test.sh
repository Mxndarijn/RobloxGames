#!/usr/bin/env bash
# Run the lune tests with a private TMPDIR (mktemp -d per run, removed on exit) so parallel bot
# runs on the shared box never collide in /tmp. Usage: scripts/test.sh [lune test args...]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
T="$(mktemp -d "${TMPDIR:-/tmp}/lune-tests-XXXXXXXX")"
trap 'rm -rf "$T"' EXIT
TMPDIR="$T" lune run tests "$@"
