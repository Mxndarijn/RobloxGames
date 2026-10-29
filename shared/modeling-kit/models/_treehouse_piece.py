# Measuring wrapper (not an asset): builds one Tree House piece by name and joins it like a shipping mesh.
#   PIECE=treehouse_room_1 python iterate.py models/_treehouse_piece.py --name treehouse_room_1 --quick --no-export
import os

from lib import finish
from models._treehouse_pieces import PIECES

name = os.environ.get("PIECE", "treehouse_room_1")
finish(name, PIECES[name]())
