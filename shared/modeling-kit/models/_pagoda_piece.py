# Measuring wrapper (not an asset): builds one Mushroom Pagoda piece by name and joins it like a shipping mesh.
#   PIECE=pagoda_room_1 python iterate.py models/_pagoda_piece.py --name pagoda_room_1 --quick --no-export
import os

from lib import finish
from models._pagoda_pieces import PIECES

name = os.environ.get("PIECE", "pagoda_room_1")
finish(name, PIECES[name]())
