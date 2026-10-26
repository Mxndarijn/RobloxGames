# One Mushroom Pagoda game mesh, shipped like the goo jar tower's (models/_goo_jar.py ship). PIECE=<name> where name is
# a _pagoda_pieces.SHIP key ("pagoda_room_1", "pagoda_cap_extra@crystal", ...):
#   PIECE=pagoda_room_1 python iterate.py models/_pagoda_ship.py --name pagoda_room_1
# A skin's version of a shared slot gets two tiny anchor tetrahedra at the union box's corners
# (inputs/pagoda_theme_boxes.json, from models/_pagoda_meshes.py), so every skin's mesh fits its slot the same way.
import json
import os

import bmesh

from lib import obj_from_bm
from models._goo_jar import ship
from models._pagoda_pieces import SHARED_SLOTS, SHIP

name = os.environ["PIECE"]
parts = SHIP[name]()
slot = name.split("@")[0]
if slot in SHARED_SLOTS:
    boxes = json.load(open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "inputs",
                                        "pagoda_theme_boxes.json")))
    for k, corner in enumerate((boxes[slot]["lo"], boxes[slot]["hi"])):
        bm = bmesh.new()
        d = 0.02 if k == 0 else -0.02
        x, y, z = corner
        vs = [bm.verts.new(p) for p in ((x, y, z), (x + d, y, z), (x, y + d, z), (x, y, z + d))]
        for f in ((0, 2, 1), (0, 1, 3), (0, 3, 2), (1, 2, 3)):
            bm.faces.new([vs[i] for i in f])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        parts.append(obj_from_bm(f"Anchor{k}", bm, (0.5, 0.5, 0.5, 1.0)))
ship(name, parts)
