--!strict
--[[
	FloorTerrain (Roblox adapter, owner: Archer; B11 floor)

	A standalone Script (it needs no call site, so it touches none of Gojo's terrain files): once GroundTerrainView has written
	the inner ground, the voxel Grass under the new floor becomes Sand (FloorLayout.terrainRows, the same cells as
	FloorLayout.groundMaterial). Terrain.Decoration grows its grass tufts on Grass voxels and they would poke through every
	floor part (the sand yard, the lawns, the boardwalk); Sand voxels grow none. Terrain heights and the rest of the
	ground are not touched, and the grass outside the border band keeps its tufts.

	Idempotent: the Terrain attribute FloorTerrain marks it done. A no-op when the ground was never written.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FloorLayout = require(ReplicatedStorage.Visuals.FloorLayout)

local GROUND_ATTRIBUTE = "GroundTerrain" -- GroundTerrainView.ATTRIBUTE: true once the ground is written
local DONE_ATTRIBUTE = "FloorTerrain"
local WAIT_SECONDS = 60

local terrain = workspace:WaitForChild("Terrain") :: Terrain

local function place()
	if terrain:GetAttribute(DONE_ATTRIBUTE) ~= nil then
		return
	end
	terrain:SetAttribute(DONE_ATTRIBUTE, false)
	-- rows of whole 4-stud cells, from the bottom of the written voxels (GroundTerrain.FLOOR -8) to a cell above the surface
	for _, row in FloorLayout.terrainRows() do
		local region = Region3.new(Vector3.new(row.x0, -8, row.z0), Vector3.new(row.x1, 4, row.z0 + 4))
		terrain:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.Sand)
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
