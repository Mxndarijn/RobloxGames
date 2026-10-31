# exclusive_slime_claw_shop: the shop mesh of exclusive_slime_claw for upload (Exclusive Shop concept).
# Offsets between the meshes, display spots, arm root, funnel, chute and sign face: out/exclusive_slime_claw_layout.json.
import os
import runpy

os.environ["CLAW_PART"] = "shop"
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "exclusive_slime_claw.py"), run_name="__main__")
