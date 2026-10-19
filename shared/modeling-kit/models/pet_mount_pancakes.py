# pet_mount_pancakes: see models/_pet_mounts_extra.py and models/PET_MOUNTS.md.
# Origin bottom centre, 1 BU = 1 stud, front faces -Y, the pet sits on top. Smooth shaded, vertex colours.
from models._pet_mounts import *

ship("pet_mount_pancakes", MOUNTS["pancakes"](), fit="pancakes" not in NOFIT)
