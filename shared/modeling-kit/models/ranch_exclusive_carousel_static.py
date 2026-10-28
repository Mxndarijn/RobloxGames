# ranch_exclusive_carousel_static: the static half of ranch_exclusive_carousel for the game
# (contract/exclusive-shop.md §7). Offsets between the halves, rider spots and the kiosk counter: out/ranch_exclusive_carousel_layout.json.
import os
import runpy

os.environ["CAROUSEL_PART"] = "static"
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ranch_exclusive_carousel.py"), run_name="__main__")
