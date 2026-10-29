# One Carousel Tent game mesh, shipped like the goo jar tower's (models/_goo_jar.py ship: mirrored in x, see there).
# PIECE=<name> where name is a _carousel_pieces.SHIP key:
#   PIECE=carousel_room_1 python iterate.py models/_carousel_ship.py --name carousel_room_1
import os

from models._goo_jar import ship
from models._carousel_pieces import SHIP

name = os.environ["PIECE"]
ship(name, SHIP[name]())
