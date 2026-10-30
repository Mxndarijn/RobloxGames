--!strict
--[[
	Rng: the game's handle on the shared seeded generator (shared/luau/src/core/Rng). A seed gives the same slime
	in Lune and in Roblox.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Core = if Lib then require(Lib.core.Rng) else require("../../../../shared/luau/src/core/Rng")

export type Rng = Core.Rng

return Core
