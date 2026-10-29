# Measuring wrapper (not an asset): builds one Carousel Tent piece by name and joins it like a shipping mesh.
#   PIECE=carousel_room_1 python iterate.py models/_carousel_piece.py --name carousel_room_1 --quick --no-export
import os

from lib import finish
from models._carousel_pieces import PIECES

name = os.environ.get("PIECE", "carousel_room_1")
finish(name, PIECES[name]())
