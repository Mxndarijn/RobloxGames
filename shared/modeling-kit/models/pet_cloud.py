# pet_cloud: soft cartoon cloud the follow pet (FollowPets) sits on. 3.3 x 2.4 x 1.2 studs.
# Runtime-only decor: the client clones one per follower and glides it behind its owner; the pet stands on the flat top.
# Round puffs fused into one smooth-shaded skin (metaballs, _pet_cloud.py), flat-ish top (z = 1.2) for the pet,
# light blue underside fading to white. Origin bottom centre, 1 BU = 1 stud. Front faces -Y.
from lib import *
from models._pet_cloud import cloud_parts

o = finish("pet_cloud", cloud_parts())
a = o.data.attributes.get("keep_smooth")
for p, d in zip(o.data.polygons, a.data):
    p.use_smooth = bool(d.value)
o.data.attributes.remove(a)
