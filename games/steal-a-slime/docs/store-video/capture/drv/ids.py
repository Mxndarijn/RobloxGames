import drv, json
s = drv.session()
ok, d, _ = s.luau(drv.SID, """
local out = {}
for _, m in game:GetService("CollectionService"):GetTagged("Slime") do
	local o, t = m:GetAttribute("OwnerUserId"), m:GetAttribute("Tier")
	if m:GetAttribute("State") == "Pad" then
		local p = m:GetPivot().Position
		table.insert(out, {id = string.sub(m.Name, 7), owner = o, tier = t, pos = {p.X, p.Y, p.Z}})
	end
end
return {slimes = out}""", datamodel="Client")
json.dump(d["slimes"], open("ids.json", "w"), indent=0)
for x in d["slimes"]:
    if x["owner"] in (-2001, -2002) or x["tier"] >= 8: print(x)
