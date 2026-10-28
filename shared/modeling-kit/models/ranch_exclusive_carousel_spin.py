# ranch_exclusive_carousel_spin: the spinning half of ranch_exclusive_carousel for the game
# (contract/exclusive-shop.md §7). Offsets between the halves, rider spots and the kiosk counter: out/ranch_exclusive_carousel_layout.json.
import os
import runpy

os.environ["CAROUSEL_PART"] = "spin"
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ranch_exclusive_carousel.py"), run_name="__main__")
