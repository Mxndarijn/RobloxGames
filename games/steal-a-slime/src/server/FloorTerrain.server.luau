--!strict
--[[
	FloorTerrain (Roblox adapter, owner: Archer; B11 floor)

	A standalone Script (it needs no call site, so it touches none of Gojo's terrain files): once GroundTerrainView has written
	the inner ground, the voxel Grass under the new floor becomes Sand (FloorLayout.terrainRows, the same cells as
	FloorLayout.groundMaterial). Terrain.Decoration grows its grass tufts on Grass voxels and they would poke through every
	floor part (the sand yard, the lawns, the boardwalk); Sand voxels grow none. Terrain heights and the rest of the
	ground are not touched, and the grass outside the border band keeps its tufts.

	The top voxel layer under the floor (y -4..0) is then cleared, so that terrain renders ~2 studs below the floor parts,
	and under the green border band the terrain left is LeafyGrass (green), so the gaps of the far-away low-detail disc
	show green, not sand (lowerTop).
	The floor discs lie only a few hundredths of a stud above y = 0: from far away (the end of a camera pull-back, the top
	of a tall base) the depth test could not tell them apart from terrain at y = 0, and the sand under the grass border
	band showed through. Nobody can see that terrain, and the invisible Map.Ground part still holds everyone up.

	Idempotent: the Terrain attribute FloorTerrain marks it done. A no-op when the ground was never written.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FloorLayout = require(ReplicatedStorage.Visuals.FloorLayout)

local GROUND_ATTRIBUTE = "GroundTerrain" -- GroundTerrainView.ATTRIBUTE: true once the ground is written
local DONE_ATTRIBUTE = "FloorTerrain"
local WAIT_SECONDS = 60
local RIM_MARGIN = 6 -- studs: a cell whose centre is this close to the band edge may poke past it

local terrain = workspace:WaitForChild("Terrain") :: Terrain

-- One row of the written ground (two voxel layers, y -8..0). Cells well inside the band lose their top layer (the
-- terrain then renders 2 studs below the floor parts). Under the green border band the rest turns LeafyGrass (green,
-- grows no tufts): from far away Roblox draws the big FieldBand disc with fewer sides, its straight edges cut inside the
-- circle and this terrain shows through the gaps. The outer ring of cells, which reaches past the band's edge, goes back
-- to Grass at the full height, so no lowered sand shows round the band.
local function lowerTop(row: FloorLayout.Row)
	local region = Region3.new(Vector3.new(row.x0, -8, row.z0), Vector3.new(row.x1, 0, row.z0 + 4))
	local materials, occupancy = terrain:ReadVoxels(region, 4)
	local size = materials.Size
	for i = 1, size.X do
		local x = row.x0 + (i - 0.5) * 4
		local z = row.z0 + 2
		local r = math.sqrt(x * x + z * z)
		local rim = r + RIM_MARGIN > FloorLayout.BAND_RADIUS
		local band = r > FloorLayout.HEM_RADIUS
		for j = 1, size.Y do
			for k = 1, size.Z do
				if materials[i][j][k] == Enum.Material.Sand then
					if rim then
						materials[i][j][k] = Enum.Material.Grass
					elseif j == size.Y then
						materials[i][j][k] = Enum.Material.Air
						occupancy[i][j][k] = 0
					elseif band then
						materials[i][j][k] = Enum.Material.LeafyGrass
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, 4, materials, occupancy)
end

local function place()
	if terrain:GetAttribute(DONE_ATTRIBUTE) ~= nil then
		return
	end
	terrain:SetAttribute(DONE_ATTRIBUTE, false)
	-- rows of whole 4-stud cells, from the bottom of the written voxels (GroundTerrain.FLOOR -8) to a cell above the surface
	for _, row in FloorLayout.terrainRows() do
		local region = Region3.new(Vector3.new(row.x0, -8, row.z0), Vector3.new(row.x1, 4, row.z0 + 4))
		terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.Sand)
		lowerTop(row)
	end
	terrain:SetAttribute(DONE_ATTRIBUTE, true)
end

if terrain:GetAttribute(GROUND_ATTRIBUTE) == true then
	place()
else
	local connection: RBXScriptConnection? = nil
	connection = terrain:GetAttributeChangedSignal(GROUND_ATTRIBUTE):Connect(function()
		if terrain:GetAttribute(GROUND_ATTRIBUTE) == true then
			if connection then
				connection:Disconnect()
			end
			place()
		end
	end)
	task.delay(WAIT_SECONDS, function()
		if connection then
			connection:Disconnect() -- the ground never came (a test place without GroundTerrainView): nothing to do
		end
	end)
end
