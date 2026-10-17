-- Client datamodel: release probe R7 (ADVISORY), the minimap (FEATURES.Minimap provides MinimapData points only, no UI so far): looks in
-- PlayerGui.SlimeUI for a GuiObject named like a minimap (name contains "minimap", else "map") and, in it, a pin for the local player (a
-- descendant whose name contains "pin" / "you" / "me" / "player" / "self"). If there is no minimap UI the result is ok = nil. Otherwise
-- the pin's centre, as a fraction of the minimap's AbsoluteSize, must match MinimapData.toMap(character x, z) within 0.05 on both axes.
-- Checks (ok = every non-nil check true):
--   minimap_ui   a minimap GuiObject exists under SlimeUI (n/a = no minimap UI in the client)
--   player_pin   its player pin matches MinimapData.toMap of the character within 0.05
-- Nothing is changed. ~1 s.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local ORDER = { "minimap_ui", "player_pin" }
local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local function finish(extra)
	local parts, all, any = {}, true, false
	for _, name in ORDER do
		local c = checks[name] or { ok = nil, info = "not run" }
		checks[name] = c
		table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
		if c.ok == false then
			all = false
		elseif c.ok == true then
			any = true
		end
	end
	return {
		ok = if not all then false elseif any then true else nil,
		summary = table.concat(parts, ", "),
		detail = { checks = checks, extra = extra },
	}
end
local NONE = "no minimap UI in the client (FEATURES.Minimap only provides MinimapData points)"

local player = Players.LocalPlayer
local gui = player.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return finish("SlimeUI missing")
end
local map
for _, pass in { "minimap", "map" } do
	for _, d in gui:GetDescendants() do
		if d:IsA("GuiObject") and string.find(string.lower(d.Name), pass, 1, true) then
			map = d
			break
		end
	end
	if map then
		break
	end
end
if not map then
	set("minimap_ui", nil, NONE)
	set("player_pin", nil, NONE)
	local r = finish(NONE)
	r.ok = nil
	r.summary = NONE
	return r
end
set("minimap_ui", true, map:GetFullName())
local pin
for _, d in map:GetDescendants() do
	local n = string.lower(d.Name)
	if d:IsA("GuiObject") and (string.find(n, "pin", 1, true) or string.find(n, "you", 1, true) or string.find(n, "player", 1, true) or string.find(n, "self", 1, true) or n == "me") then
		pin = d
		break
	end
end
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local dataMod = RS:FindFirstChild("Visuals") and RS.Visuals:FindFirstChild("MinimapData")
if not pin or not root or not dataMod then
	set("player_pin", false, { pin = pin and pin:GetFullName(), character = root ~= nil, minimap_data = dataMod ~= nil })
	return finish(map:GetFullName())
end
local okData, data = pcall(require, dataMod)
if not okData then
	set("player_pin", false, "MinimapData require failed: " .. tostring(data))
	return finish(map:GetFullName())
end
local ex, ez = data.toMap(root.Position.X, root.Position.Z)
local centre = pin.AbsolutePosition + pin.AbsoluteSize / 2
local fx = (centre.X - map.AbsolutePosition.X) / math.max(map.AbsoluteSize.X, 1)
local fz = (centre.Y - map.AbsolutePosition.Y) / math.max(map.AbsoluteSize.Y, 1)
local dx, dz = math.abs(fx - ex), math.abs(fz - ez)
set("player_pin", dx <= 0.05 and dz <= 0.05, { pin = pin:GetFullName(), pin_fraction = { fx, fz }, expected = { ex, ez }, delta = { dx, dz } })
return finish(map:GetFullName())
