# One Tree House game mesh, shipped like the goo jar tower's (models/_goo_jar.py ship: mirrored in X, the game's look
# slots turn it back). PIECE=<name> where name is a _treehouse_pieces.SHIP key:
#   PIECE=treehouse_room_1 python iterate.py models/_treehouse_ship.py --name treehouse_room_1
import os

from models._goo_jar import ship
from models._treehouse_pieces import SHIP

name = os.environ["PIECE"]
ship(name, SHIP[name]())
