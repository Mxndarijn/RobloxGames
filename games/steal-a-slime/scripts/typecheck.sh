#!/usr/bin/env bash
# luau-lsp type check (strict files) of src/ against the Rojo sourcemap.
#
#   scripts/typecheck.sh          # fails on errors in src/server + src/shared, reports the rest
#   scripts/typecheck.sh --all    # fails on errors anywhere in src/
#
# Our modules require each other with
#   if script then require(script.Parent.X) else require("./X")
# so the same file runs in Roblox and under Lune. luau-lsp can't type an
# if-expression require (every import becomes "Unknown require" / unknown
# types), so this checks a temporary copy where that line is rewritten to
# its Roblox branch (same line numbers), then maps paths back to the repo.
# Needs rojo + luau-lsp (rokit.toml) and perl. Definitions:
# tools/luau-lsp/globalTypes.None.d.luau (luau-lsp 1.70.1, committed for offline runs).
set -euo pipefail

for tool in rojo luau-lsp; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "typecheck: $tool not found on PATH; install via rokit (rokit install)" >&2
		exit 1
	fi
done

all=0
[[ "${1:-}" == "--all" ]] && all=1
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp -r "$root/default.project.json" "$root/rokit.toml" "$root/src" "$root/world" "$tmp/"
rm -rf "$tmp/src/visuals/static" # Archer's build-map output, not in the Rojo tree
# ReplicatedStorage.Lib is the repo's shared/luau library, outside this folder: copy it in and point the project at the copy.
mkdir -p "$tmp/lib"
cp -r "$root/../../shared/luau/src" "$tmp/lib/"
perl -pi -e 's#"\.\./\.\./shared/luau/src"#"lib/src"#' "$tmp/default.project.json"
# Whole-file pass (-0) so a guard stylua wrapped over three lines is rewritten too; the newlines it spanned are
# kept after the require, so line numbers stay the same.
find "$tmp/src" "$tmp/lib" -name '*.luau' -print0 | xargs -0 perl -0pi -e '
	s/if (?:Shared|script|Lib)(\s+)then (require\([^)]*\))(\s+)else require\("[^"]+"\)/$2 . ("\n" x (($1 . $3) =~ tr{\n}{}))/ge;
	s/^local Shared = if script then \(game:GetService\("ReplicatedStorage"\) :: any\)\.Shared else nil/local Shared = game:GetService("ReplicatedStorage").Shared/mg;
	s/^local Lib = if script then \(game:GetService\("ReplicatedStorage"\) :: any\)\.Lib else nil/local Lib = game:GetService("ReplicatedStorage").Lib/mg;
'

cd "$tmp"
rojo sourcemap default.project.json -o sourcemap.json >/dev/null
set +e
luau-lsp analyze --platform roblox --sourcemap sourcemap.json \
	--definitions "@roblox=$root/tools/luau-lsp/globalTypes.None.d.luau" \
	src/shared src/server src/ui src/visuals/shared src/visuals/client >raw.txt 2>&1
set -e

# One line per diagnostic, repo-relative, without the [game/...] instance path.
grep -E "^($tmp/)?src/" raw.txt | sed -E "s#^$tmp/##; s# \[[^]]*\]##" | sort -u >errors.txt || true

count() { grep -cE "^$1" errors.txt || true; }
owned=$(count "src/(server|shared)/")
ui=$(count "src/ui/")
visuals=$(count "src/visuals/")
echo "luau-lsp: src/server+src/shared $owned, src/ui $ui, src/visuals $visuals"

fatal="^src/(server|shared)/"
[[ $all == 1 ]] && fatal="^src/"
if grep -E "$fatal" errors.txt; then
	echo "typecheck: FAIL"
	exit 1
fi
echo "typecheck: OK (src/ui and src/visuals are report-only; --all to include them)"
