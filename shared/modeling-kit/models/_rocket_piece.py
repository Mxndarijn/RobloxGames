# Measuring wrapper (not an asset): builds one Space Rocket piece by name and joins it like a shipping mesh.
#   PIECE=rocket_hull_1 python iterate.py models/_rocket_piece.py --name rocket_hull_1 --quick --no-export
import os

from lib import finish
from models._rocket_pieces import PIECES

name = os.environ.get("PIECE", "rocket_hull_1")
finish(name, PIECES[name]())
