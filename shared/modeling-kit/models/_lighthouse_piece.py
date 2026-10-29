# Measuring wrapper (not an asset): builds one Lighthouse piece by name and joins it like a shipping mesh.
#   PIECE=lighthouse_room_1 python iterate.py models/_lighthouse_piece.py --name lighthouse_room_1 --quick --no-export
import os

from lib import finish
from models._lighthouse_pieces import PIECES

name = os.environ.get("PIECE", "lighthouse_room_1")
finish(name, PIECES[name]())
