import drv, json, sys
s = drv.session()
ok, d, _ = s.luau(drv.SID, """
local out = {}
for _, m in game:GetService("CollectionService"):GetTagged("Slime") do
	if m:GetAttribute("State") == "Wild" and m:GetAttribute("BossMove") == nil then
		local p = m:GetPivot()
		table.insert(out, {id = string.sub(m.Name, 7), tier = m:GetAttribute("Tier"), p = {p.X, p.Y, p.Z}, h = {p.LookVector.X, p.LookVector.Z}})
	end
end
return {w = out}""", datamodel="Client")
for x in d["w"]: print(x)
json.dump(d["w"], open("wild.json", "w"))
