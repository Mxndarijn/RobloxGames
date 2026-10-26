#!/bin/bash
# Ships every Goo Factory game mesh (models/_factory_ship.py) to out/<name>.fbx, 4 at a time.
# Run models/_factory_meshes.py first (it writes inputs/factory_theme_boxes.json for the themed pieces).
cd "$(dirname "$0")/.." || exit 1
PIECES=$(python -c "import ast,re;s=open('models/_factory_pieces.py').read();print(' '.join(re.findall(r'^    \"(factory_[a-z0-9_]+)\": \(', s, re.M)))")
THEMES="garden crystal starlight candy mushroom"
jobs=()
for p in $PIECES; do
  [ "$p" = "factory_dress" ] || jobs+=("$p:classic")
done
for p in factory_foot factory_roof_kit factory_dress; do
  for t in $THEMES; do jobs+=("$p:$t"); done
done
run() {
  local p=${1%%:*} t=${1##*:} n
  n=$p; [ "$t" = "classic" ] || n="$p@$t"
  PIECE=$p THEME=$t python iterate.py models/_factory_ship.py --name "$n" --views 0,3 2>&1 | grep -E "PASS|FAIL" | head -1
}
export -f run
printf '%s\n' "${jobs[@]}" | xargs -P 4 -I{} bash -c 'run "$@"' _ {}
