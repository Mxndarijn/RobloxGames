# One Goo Factory mesh piece on its own (for tris and the kit checks): PIECE=<name> [THEME=<id>] iterate.py models/_factory_piece.py --name <name>
import os

from lib import finish
from models._base_design_common import theme
from models._factory_pieces import PIECES

name = os.environ["PIECE"]
build, _ = PIECES[name]
tid = os.environ.get("THEME", "classic")
finish(name, build(tid, theme(tid)))
