# pet_cloud: low-poly cloud the follow pet (FollowPets) sits on. 3.3 x 2.4 x 1.2 studs, 560 tris.
# Runtime-only decor: the client clones one per follower and glides it behind its owner; the pet stands on the flat top.
# Flat-ish top (z = 1.2) for the pet, lumpy puffs round the rim, light blue underside fading to white (puffs: _pet_cloud.py).
# Origin bottom centre, 1 BU = 1 stud. Front faces -Y.
from lib import *
from models._pet_cloud import cloud_parts

finish("pet_cloud", cloud_parts())
