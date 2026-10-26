#!/bin/bash
# Ships every Mushroom Pagoda game mesh (models/_pagoda_pieces.SHIP via models/_pagoda_ship.py) to out/<name>.fbx,
# 4 at a time. Run models/_pagoda_meshes.py first (it writes inputs/pagoda_theme_boxes.json).
cd "$(dirname "$0")/.." || exit 1
NAMES=$("$BLENDER" -b --factory-startup --python-expr "import sys; sys.path.insert(0, '.'); import models._pagoda_pieces as PC; print('SHIP:' + ' '.join(n for n in PC.SHIP if n != 'pagoda_door'))" 2>/dev/null | grep '^SHIP:' | sed 's/^SHIP://')
run() {
  PIECE="$1" python iterate.py models/_pagoda_ship.py --name "$1" --views 0,3 2>&1 | grep -E "PASS|FAIL" | head -1
}
export -f run
printf '%s\n' $NAMES | xargs -P 4 -I{} bash -c 'run "$@"' _ {}
