# One Space Rocket game mesh, shipped like the goo jar tower's (models/_goo_jar.py ship: mirrored in x, see there).
# PIECE=<name> where name is a _rocket_pieces.SHIP key:
#   PIECE=rocket_hull_1 python iterate.py models/_rocket_ship.py --name rocket_hull_1
import os

from models._goo_jar import ship
from models._rocket_pieces import SHIP

name = os.environ["PIECE"]
ship(name, SHIP[name]())
