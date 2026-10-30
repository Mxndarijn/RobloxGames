--!strict
--[[
	EdgeArrow: the game's handle on the shared off-screen pointer maths (shared/luau/src/guide/EdgeArrow), used by
	the home plot badge and the thief arrow.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Core = if Lib then require(Lib.guide.EdgeArrow) else require("../../../../shared/luau/src/guide/EdgeArrow")

export type Vec3 = Core.Vec3
export type Point = Core.Point
export type Rect = Core.Rect
export type Arrow = Core.Arrow

return Core
