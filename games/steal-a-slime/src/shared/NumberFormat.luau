--!strict
--[[
	NumberFormat: the game's handle on the shared number and time text (shared/luau/src/core/NumberFormat). The one
	cash / count abbreviation used by the HUD, shop, rebirth, toasts, billboards and leaderboards.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
return if Lib then require(Lib.core.NumberFormat) else require("../../../../shared/luau/src/core/NumberFormat")
