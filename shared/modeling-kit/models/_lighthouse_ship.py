# One Lighthouse game mesh, shipped like the goo jar tower's (models/_goo_jar.py ship: mirrored in X, the game's look
# slots turn it back). PIECE=<name> where name is a _lighthouse_pieces.SHIP key:
#   PIECE=lighthouse_room_1 python iterate.py models/_lighthouse_ship.py --name lighthouse_room_1
import os

from models._goo_jar import ship
from models._lighthouse_pieces import SHIP

name = os.environ["PIECE"]
ship(name, SHIP[name]())
