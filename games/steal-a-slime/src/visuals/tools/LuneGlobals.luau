--!nocheck
--# selene: allow(incorrect_standard_library_use)
--[[
	LuneGlobals (owner: Archer, Lune-only tool helper)

	Installs the Roblox datatype globals the visuals modules use (Vector3,
	CFrame, Color3, Enum, Instance, sequences, ...) from @lune/roblox, so
	WorldBuilder / Props / Effects run unchanged under Lune. Not in the Rojo
	tree.
]]
local roblox = require("@lune/roblox")

-- Plain global assignments (Lune shares the main chunk's globals with
-- required modules; _G does not).
Vector3 = roblox.Vector3
Vector2 = roblox.Vector2
CFrame = roblox.CFrame
Color3 = roblox.Color3
Enum = roblox.Enum
Instance = roblox.Instance
UDim = roblox.UDim
UDim2 = roblox.UDim2
NumberRange = roblox.NumberRange
NumberSequence = roblox.NumberSequence
NumberSequenceKeypoint = roblox.NumberSequenceKeypoint
ColorSequence = roblox.ColorSequence
ColorSequenceKeypoint = roblox.ColorSequenceKeypoint

return roblox
