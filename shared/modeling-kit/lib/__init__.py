"""modeling-kit bpy helpers. In a model script:

    from lib import *          # rgb, PALETTE, box, cylinder, cone, blob, tube, finish, ...

Units: 1 Blender unit = 1 Roblox stud (the v17 make_meshes.py convention, confirmed by
the uploaded pad_trim: 9.4 BU -> MeshPart Size 9.4). Z up in Blender; iterate.py
exports Y-up FBX. A stud is 0.28 m in Roblox's physics docs, but nothing here uses
metres: never set scene unit scale, just model in studs.
"""
from .color import PALETTE, flat_material, gradient_bm, hexc, mix, paint_bm, rgb, shade, vcol_material
from .mesh import (apply_modifiers, apply_transforms, bevel, cleanup, decimate, finish, join,
                   origin_bottom_center, reset_scene, select_only, tris)
from .shapes import blob, box, cone, cylinder, gradient, jitter_bm, noise_bm, obj_from_bm, rng, tube
from .units import AVATAR_HEIGHT, STUD_M, meters, studs

__all__ = [n for n in dir() if not n.startswith("_")]
