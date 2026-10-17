--!strict
--[[
	GroundTerrainView (Roblox adapter, owner: Archer; bugs #13-15)

	GroundTerrainView.place(): boolean
	  Writes the inner ground (Visuals.GroundTerrain) into Workspace.Terrain as voxels: one material per 4-stud
	  cell (Grass / Ground = the packed-dirt path / Sand = the plaza), flat on y = 0 over two solid layers.
	  Terrain is not a Part, so the old Ground tiles, plaza disc and 41 path blocks cost nothing and the dirt path
	  is one seamless shape. Sets the pastel terrain tints (the MaterialService variants SlimeGrass / SlimeGround
	  / SlimeSand multiply them with a soft ColorMap) (the grass tufts come from Terrain.Decoration, set in default.project.json).
	  Written before anything else on the server: ~25 small WriteVoxels calls, no yields. The invisible
	  Map.Ground part stays under it as the void-safety floor. Idempotent: the Terrain attribute GroundTerrain
	  marks it done.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroundTerrain = require(ReplicatedStorage.Visuals.GroundTerrain)

local GroundTerrainView = {}

GroundTerrainView.ATTRIBUTE = "GroundTerrain"

local MATERIALS: { [string]: Enum.Material } = {
	Grass = Enum.Material.Grass,
	Ground = Enum.Material.Ground,
	Sand = Enum.Material.Sand,
}

local function writeTile(terrain: Terrain, grid: GroundTerrain.Grid, tile: GroundTerrain.Tile)
	local cell, count = GroundTerrain.CELL, GroundTerrain.TILE_CELLS
	local layers = (GroundTerrain.SURFACE - GroundTerrain.FLOOR) // cell
	local first = (tile.x - (grid.min - cell / 2)) // cell -- grid column of the tile's first cell
	local firstRow = (tile.z - (grid.min - cell / 2)) // cell
	local materials = table.create(count)
	local occupancy = table.create(count)
	for i = 1, count do
		local mx = table.create(layers)
		local ox = table.create(layers)
		for j = 1, layers do
			local mj = table.create(count)
			for k = 1, count do
				mj[k] = MATERIALS[grid.materials[(firstRow + k - 1) * grid.n + first + i]]
			end
			mx[j] = mj
			ox[j] = table.create(count, 1)
		end
		materials[i] = mx
		occupancy[i] = ox
	end
	local region = Region3.new(
		Vector3.new(tile.x, GroundTerrain.FLOOR, tile.z),
		Vector3.new(tile.x + count * cell, GroundTerrain.SURFACE, tile.z + count * cell)
	)
	terrain:WriteVoxels(region, cell, materials, occupancy)
end

function GroundTerrainView.place(): boolean
	local terrain = workspace.Terrain
	if terrain:GetAttribute(GroundTerrainView.ATTRIBUTE) ~= nil then
		return false
	end
	terrain:SetAttribute(GroundTerrainView.ATTRIBUTE, false)
	for name, color in GroundTerrain.COLORS do
		terrain:SetMaterialColor(MATERIALS[name], Color3.fromRGB(color[1], color[2], color[3]))
	end
	-- Terrain.Decoration (the grass tufts) is not scriptable: it is set on the Terrain in default.project.json.
	local grid = GroundTerrain.grid()
	for _, tile in GroundTerrain.tiles() do
		writeTile(terrain, grid, tile)
	end
	terrain:SetAttribute(GroundTerrainView.ATTRIBUTE, true)
	return true
end

return GroundTerrainView
