"""Write games/steal-a-slime/src/shared/ExclusiveIds.luau from created_ids.json (product:/pass:/sub: keys)."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from apikey import UNIVERSE
ids = json.load(open(os.path.join(HERE, "created_ids.json")))
target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "src", "shared", "ExclusiveIds.luau")
def block(prefix, quote):
    rows = sorted((k.split(":", 1)[1], v) for k, v in ids.items() if k.startswith(prefix + ":"))
    out = []
    for k, v in rows:
        key = k if k.replace("_", "").isalnum() and not k[0].isdigit() else f'["{k}"]'
        if quote and not v:
            out.append(f"\t\t-- TODO: create the {k} subscription on the Creator Dashboard (universe {UNIVERSE}) and put its EXP- id in created_ids.json")
        out.append(f'\t\t{key} = {json.dumps(str(v)) if quote else v},')
    return "\n".join(out)
src = f'''--!strict
--[[
	ExclusiveIds (generated: the Roblox ids of the Exclusive Shop's products, passes and subscriptions)

	Created on Roblox for the Steal a Slime experience (universe {UNIVERSE}) with the Open Cloud Developer
	Products / Game Passes APIs; subscriptions on the Creator Dashboard. Config.EXCLUSIVE_SHOP reads these by key
	(a key without an id stays 0 / "": "Not on sale yet"). Keys are the permanent product / pass / subscription keys.
]]

return table.freeze({{
	products = table.freeze({{
{block("product", False)}
	}} :: {{ [string]: number }}),
	passes = table.freeze({{
{block("pass", False)}
	}} :: {{ [string]: number }}),
	subscriptions = table.freeze({{
{block("sub", True)}
	}} :: {{ [string]: string }}),
}})
'''
open(target, "w", encoding="utf-8", newline="").write(src)
print("wrote", sum(1 for k in ids if k.startswith("product:")), "products,", sum(1 for k in ids if k.startswith("pass:")), "passes")
