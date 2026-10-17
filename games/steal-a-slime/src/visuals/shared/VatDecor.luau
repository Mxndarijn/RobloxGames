--!strict
--[[
	VatDecor (owner: Archer; used by server MeshSwap.swapPlotVats)

	Where the merge_vat mesh stands over a plot's primitive MergeVat disc. Pure: no Roblox APIs (Lune-safe).
	The disc (WorldLayout plot: dia 9, 4 tall, centre 3 above the plot floor, i.e. bottom at the floor + 1) keeps
	the ProximityPrompt and stays; it is only hidden. The mesh stands on the disc's bottom at BODY / MESH scale so
	its copper belly covers the disc and its spouts reach past it.
]]

local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")

export type Pose = { size: { number }, position: { number } }

local VatDecor = {}

VatDecor.MESH = "merge_vat"
VatDecor.DISC_DIAMETER = 9 -- WorldLayout plot MergeVat disc
VatDecor.DISC_HEIGHT = 4
VatDecor.BODY_DIAMETER = 9.3 -- the cauldron's belly in the mesh (merge_vat.py: r 4.65)
VatDecor.SCALE = VatDecor.DISC_DIAMETER / VatDecor.BODY_DIAMETER

-- Mesh size and centre for a disc centred at (x, y, z): standing on the disc's bottom.
function VatDecor.pose(discX: number, discY: number, discZ: number): Pose
	local entry = MeshAssets.get(VatDecor.MESH)
	local native = if entry and entry.size then entry.size else { 1, 1, 1 }
	local size = { native[1] * VatDecor.SCALE, native[2] * VatDecor.SCALE, native[3] * VatDecor.SCALE }
	local bottom = discY - VatDecor.DISC_HEIGHT / 2
	return { size = size, position = { discX, bottom + size[2] / 2, discZ } }
end

return table.freeze(VatDecor)
