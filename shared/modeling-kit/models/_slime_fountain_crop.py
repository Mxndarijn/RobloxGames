# Preview (not an asset): a cropped close-up of slime_fountain so the goo reads at sheet size.
#   CROP=crown python3 iterate.py models/_slime_fountain_crop.py --no-export --sheet /tmp/crown.png
#   CROP=exit|slide ...  (slide exit puddle / goo on the helix)
import os
import bmesh, bpy
from lib import finish
import models.slime_fountain as sf

BOXES = {  # silo space: (xmin, xmax, ymin, ymax, zmin, zmax)
    "crown": (-16, 16, -16, 16, 14, 99),
    "exit": (-14, 14, -45, -24, -1, 8),
    "slide": (-30, 30, -30, 30, 6, 40),
}
x0, x1, y0, y1, z0, z1 = BOXES[os.environ.get("CROP", "crown")]
parts, pts = sf.build()
if os.environ.get("EMERGE"):  # EMERGE=1: show the optional emerge slimes in place
    import models.slime_fountain_emerge as em
    parts += em.slimes(pts)[0]
for o in parts:
    bm = bmesh.new()
    bm.from_mesh(o.data)
    out = [f for f in bm.faces if not all(x0 <= v.co.x <= x1 and y0 <= v.co.y <= y1 and z0 <= v.co.z <= z1
                                           for v in f.verts)]
    bmesh.ops.delete(bm, geom=out, context="FACES")
    bm.to_mesh(o.data)
    bm.free()
keep = [o for o in parts if len(o.data.polygons)]
for o in parts:
    if not len(o.data.polygons):
        bpy.data.objects.remove(o)
parts = keep
o = finish("slime_fountain_crop", parts)
a = o.data.attributes["keep_smooth"]
for p, d in zip(o.data.polygons, a.data):
    p.use_smooth = bool(d.value)
o.data.attributes.remove(a)
