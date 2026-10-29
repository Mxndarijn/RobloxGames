# One Snow Globe game mesh, shipped like the goo jar tower's (models/_goo_jar.py ship: mirrored in x, finish()).
# PIECE=<name> where name is a _snowglobe_pieces.SHIP key:
#   PIECE=snowglobe_ped python iterate.py models/_snowglobe_ship.py --name snowglobe_ped
import os

from models._goo_jar import ship
from models._snowglobe_pieces import SHIP

name = os.environ["PIECE"]
ship(name, SHIP[name]())
