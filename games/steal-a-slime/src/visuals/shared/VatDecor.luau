--!strict
--[[
	VatDecor (owner: Archer; used by server MeshSwap.swapPlotVats)

	Where the merge_vat mesh stands over a plot's primitive MergeVat disc. Pure: no Roblox APIs (Lune-safe).
	The disc (WorldLayout plot MergeVat: DISC_DIAMETER wide, DISC_HEIGHT tall, standing on the plot floor) keeps
	the ProximityPrompt and stays; it is only hidden. The mesh stands on the disc's bottom at BODY / MESH scale so
	its copper belly covers the disc and its spouts reach past it.
]]

local MeshAssets = if script
	then require(script.Parent.Parent.Shared.MeshAssets)
	else require("../../shared/MeshAssets")

export type Pose = { size: { number }, position: { number } }

local VatDecor = {}

VatDecor.MESH = "merge_vat"
VatDecor.DISC_DIAMETER = 9 -- the WorldLayout plot MergeVat disc is built from these
VatDecor.DISC_HEIGHT = 4
VatDecor.BODY_DIAMETER = 9.3 -- the cauldron's belly in the mesh (merge_vat.py: r 4.65)
VatDecor.SCALE = VatDecor.DISC_DIAMETER / VatDecor.BODY_DIAMETER

-- The three funnel cups round the rim are the slime seats (merge_vat.py CUP_RADIUS / CUP_SEAT_Z, model units, Z up,
-- front -Y; cup i at angle 90 + 120 (i - 1) degrees). FRONT_REACH is the model's +Y extent (the front cup's rim), so the
-- mesh centre (Roblox puts the pivot at the bounding box centre) sits FRONT_REACH - depth / 2 along +Y from the axis.
VatDecor.CUP_RADIUS = 4.45
VatDecor.CUP_SEAT_Z = 6.25
VatDecor.CUP_SEAT_RADIUS = 1.05 -- the goo pool in each cup
VatDecor.FRONT_REACH = 6.0
VatDecor.SEATS = 3

-- Seat `i`'s offset from the vat mesh's centre in the mesh's own frame (Roblox X, Y, Z = model X, Z, Y: checked in
-- Studio, the front cup faces the mesh's +Z), for a mesh
-- of Roblox size `size` (VatDecor.pose). The slime sits with its bottom on this point.
function VatDecor.seatOffset(i: number, size: { number }): { number }
	local entry = MeshAssets.get(VatDecor.MESH)
	local native = if entry and entry.size then entry.size else size
	local s = size[2] / native[2]
	local a = math.rad(90 + (i - 1) * 120)
	local x, y = math.cos(a) * VatDecor.CUP_RADIUS, math.sin(a) * VatDecor.CUP_RADIUS
	local centreY = VatDecor.FRONT_REACH - native[3] / 2
	return { x * s, VatDecor.CUP_SEAT_Z * s - size[2] / 2, (y - centreY) * s }
end

-- Mesh size and centre for a disc centred at (x, y, z): standing on the disc's bottom.
function VatDecor.pose(discX: number, discY: number, discZ: number): Pose
	local entry = MeshAssets.get(VatDecor.MESH)
	local native = if entry and entry.size then entry.size else { 1, 1, 1 }
	local size = { native[1] * VatDecor.SCALE, native[2] * VatDecor.SCALE, native[3] * VatDecor.SCALE }
	local bottom = discY - VatDecor.DISC_HEIGHT / 2
	return { size = size, position = { discX, bottom + size[2] / 2, discZ } }
end

return table.freeze(VatDecor)
