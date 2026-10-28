# exclusive_jar_boutique_shop: the shop mesh of exclusive_jar_boutique for upload (contract/exclusive-shop.md §7).
# Offsets between the two, display spots, counter and sign face: out/exclusive_jar_boutique_layout.json.
import os
import runpy

os.environ["JAR_PART"] = "shop"
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "exclusive_jar_boutique.py"), run_name="__main__")
