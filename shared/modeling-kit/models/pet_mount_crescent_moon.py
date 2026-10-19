# pet_mount_crescent_moon: see models/_pet_mounts_extra.py and models/PET_MOUNTS.md.
# Origin bottom centre, 1 BU = 1 stud, front faces -Y, the pet sits on top. Smooth shaded, vertex colours.
from models._pet_mounts import *

ship("pet_mount_crescent_moon", MOUNTS["crescent_moon"](), fit="crescent_moon" not in NOFIT)
