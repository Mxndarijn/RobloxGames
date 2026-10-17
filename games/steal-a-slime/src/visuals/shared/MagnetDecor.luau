--!strict
--[[
	MagnetDecor (owner: Archer, FEATURES.RainMagnet)

	Where the rain_magnet mesh stands on a plot. Pure: no Roblox APIs (Lune-safe). It stands on the plot floor
	beside the merge vat disc (WorldLayout plot: dia 9, 4 tall, bottom at the floor + 1), OFFSET studs to the
	vat's left in plot-local X, so it shares the vat's clear corner; the caller turns the offset by the plot's
	yaw (the plot Base part's rotation).
]]

local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")

export type Pose = { size: { number }, offset: { number } }

local MagnetDecor = {}

MagnetDecor.MESH = "rain_magnet"
MagnetDecor.DISC_HEIGHT = 4 -- the vat disc
MagnetDecor.OFFSET_X = -9 -- plot-local studs from the vat centre
MagnetDecor.SCALE = 1

-- Mesh size and the offset of its centre from the vat disc's centre (plot-local axes).
function MagnetDecor.pose(): Pose
	local entry = MeshAssets.get(MagnetDecor.MESH)
	local native = if entry and entry.size then entry.size else { 1, 1, 1 }
	local size = { native[1] * MagnetDecor.SCALE, native[2] * MagnetDecor.SCALE, native[3] * MagnetDecor.SCALE }
	return { size = size, offset = { MagnetDecor.OFFSET_X, -MagnetDecor.DISC_HEIGHT / 2 + size[2] / 2, 0 } }
end

-- Whether the magnet shows: the plot's RainMagnet attribute (the owner's upgrade level, only published with
-- the flag on) is a positive number.
function MagnetDecor.shown(level: any): boolean
	return type(level) == "number" and level > 0
end

return table.freeze(MagnetDecor)
