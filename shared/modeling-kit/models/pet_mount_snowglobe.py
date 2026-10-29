# pet_mount_snowglobe (winter, limited): see models/_pet_mounts.py and models/PET_MOUNTS.md.
# Origin bottom centre, 1 BU = 1 stud, front faces -Y, flat-ish top where the pet sits. Smooth shaded, vertex colours.
from models._pet_mounts import *

ship("pet_mount_snowglobe", MOUNTS["snowglobe"](), fit="snowglobe" not in NOFIT)
