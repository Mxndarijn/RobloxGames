# Measuring wrapper (not an asset): builds one Snow Globe piece by name and joins it like a shipping mesh.
#   PIECE=snowglobe_ped python iterate.py models/_snowglobe_piece.py --name snowglobe_ped --quick --no-export
import os

from lib import finish
from models._snowglobe_pieces import PIECES

name = os.environ.get("PIECE", "snowglobe_ped")
finish(name, PIECES[name]())
