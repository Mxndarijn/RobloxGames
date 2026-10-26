# One Goo Factory game mesh, shipped like the goo jar tower's (models/_goo_jar.py ship: mirrored in x, so the game's
# slots, turned half round, put it where the builder did). PIECE=<name> [THEME=<skin id>]:
#   PIECE=factory_storey python iterate.py models/_factory_ship.py --name factory_storey
#   PIECE=factory_foot THEME=garden python iterate.py models/_factory_ship.py --name factory_foot@garden
# Tint-only pieces are value greys (MeshPart.Color themes them in game); themed pieces take the skin's palette.
import json
import os

import bmesh

from lib import obj_from_bm
from models._base_design_common import theme
from models._factory_pieces import PIECES
from models._goo_jar import ship

name = os.environ["PIECE"]
build, _ = PIECES[name]
tid = os.environ.get("THEME", "classic")
parts = build(tid, theme(tid))
# themed pieces: two tiny anchor tetrahedra at the corners of the box every skin's version shares
# (inputs/factory_theme_boxes.json, written by models/_factory_meshes.py), so MeshSwap fits each one the same
boxes = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "inputs",
                                    "factory_theme_boxes.json")))
if name in boxes:
    for k, corner in enumerate((boxes[name]["lo"], boxes[name]["hi"])):
        bm = bmesh.new()
        d = 0.02 if k == 0 else -0.02
        x, y, z = corner
        vs = [bm.verts.new(p) for p in ((x, y, z), (x + d, y, z), (x, y + d, z), (x, y, z + d))]
        for f in ((0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)):
            bm.faces.new([vs[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        parts.append(obj_from_bm(f"Anchor{k}", bm, (0.5, 0.5, 0.5, 1.0)))
ship(name if tid == "classic" else f"{name}@{tid}", parts)
