--!strict
--[[
	PathTerrainView (Roblox adapter, owner: Archer)

	PathTerrainView.place(): boolean
	  Writes the plaza sand, the ring path, the spokes and the slide-exit path
	  (Visuals.PathTerrain) into Workspace.Terrain as 4-stud voxels: Ground for
	  the path, Sand for the plaza, a Mud rim round both. Terrain is not a Part
	  and not a MeshPart, so the paths cost no world part and no mesh slot.
	  A column is two layers (FLOOR..TOP), both at the cell's lateral
	  occupancy (signed distance to coverage), so edges are sub-voxel curves and
	  the surface tops out at TOP, flush with the walking surface (the Ground
	  part's top sits a hair under it).
	  One write for the whole box (about 56 x 56 columns). Idempotent: the
	  Terrain attribute PathTerrain marks it done.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PathTerrain = require(ReplicatedStorage.Visuals.PathTerrain)

local PathTerrainView = {}

PathTerrainView.ATTRIBUTE = "PathTerrain"

local MATERIALS: { [string]: Enum.Material } = {
	Ground = Enum.Material.Ground,
	Sand = Enum.Material.Sand,
	Mud = Enum.Material.Mud,
}

function PathTerrainView.place(): boolean
	local terrain = workspace.Terrain
	if terrain:GetAttribute(PathTerrainView.ATTRIBUTE) ~= nil then
		return false
	end
	terrain:SetAttribute(PathTerrainView.ATTRIBUTE, false)
	for name, color in PathTerrain.COLORS do
		terrain:SetMaterialColor(MATERIALS[name], Color3.fromRGB(color[1], color[2], color[3]))
	end
	local cell, extent = PathTerrain.CELL, PathTerrain.EXTENT
	local count = 2 * extent / cell
	local layers = (PathTerrain.TOP - PathTerrain.FLOOR) / cell
	local materials = table.create(count)
	local occupancy = table.create(count)
	for i = 1, count do
		local mx = table.create(layers)
		local ox = table.create(layers)
		for j = 1, layers do
			mx[j] = table.create(count, Enum.Material.Air)
			ox[j] = table.create(count, 0)
		end
		materials[i] = mx
		occupancy[i] = ox
	end
	for _, fill in PathTerrain.fills() do
		local i = math.floor((fill.x + extent) / cell) + 1
		local k = math.floor((fill.z + extent) / cell) + 1
		for j = 1, layers do
			materials[i][j][k] = MATERIALS[fill.material]
			occupancy[i][j][k] = fill.occupancy
		end
	end
	local region =
		Region3.new(Vector3.new(-extent, PathTerrain.FLOOR, -extent), Vector3.new(extent, PathTerrain.TOP, extent))
	terrain:WriteVoxels(region, cell, materials, occupancy)
	terrain:SetAttribute(PathTerrainView.ATTRIBUTE, true)
	return true
end

return PathTerrainView
