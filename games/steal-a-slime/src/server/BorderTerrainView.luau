--!strict
--[[
	BorderTerrainView (Roblox adapter, owner: Archer)

	BorderTerrainView.place(): boolean
	  Writes the hills behind the world border (Visuals.BorderTerrain) into
	  Workspace.Terrain as voxels: a heightfield, 4-stud cells, Grass /
	  LeafyGrass / Rock tinted to the Slime Ranch palette. Terrain is not a
	  Part and not a MeshPart, so it costs no world part and no mesh slot.
	  Only columns outside the Ground square are written (INNER), so nothing
	  covers a path, plot, the plaza, the slide or the parade lane, and the
	  invisible walls (r 292, 80 tall) stay above everything the land reaches.
	  Writes one tile at a time and yields between a few, so boot never
	  hitches. Idempotent: the Terrain attribute BorderTerrain marks it done.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BorderTerrain = require(ReplicatedStorage.Visuals.BorderTerrain)

local BorderTerrainView = {}

BorderTerrainView.ATTRIBUTE = "BorderTerrain"
BorderTerrainView.READY_ATTRIBUTE = "BorderTerrainReady"
BorderTerrainView.CHUNK_CELLS = BorderTerrain.CHUNK_CELLS
BorderTerrainView.FRAME_BUDGET_S = 0.003 -- max seconds of terrain work per frame before yielding

local MATERIALS: { [string]: Enum.Material } = {
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Rock = Enum.Material.Rock,
}

local function writeChunk(terrain: Terrain, field: BorderTerrain.Field, chunk: BorderTerrain.Chunk)
	local cell, floor = BorderTerrain.CELL, BorderTerrain.FLOOR
	local voxels = BorderTerrain.voxels(field, chunk, MATERIALS, Enum.Material.Air)
	local region = Region3.new(
		Vector3.new(chunk.x, floor, chunk.z),
		Vector3.new(chunk.x + chunk.size, floor + voxels.layers * cell, chunk.z + chunk.size)
	)
	terrain:WriteVoxels(region, cell, voxels.materials, voxels.occupancy)
end

function BorderTerrainView.place(): boolean
	local terrain = workspace.Terrain
	if terrain:GetAttribute(BorderTerrainView.ATTRIBUTE) ~= nil then
		if terrain:GetAttribute(BorderTerrainView.ATTRIBUTE) == true then
			workspace:SetAttribute(BorderTerrainView.READY_ATTRIBUTE, true)
		end
		return false
	end
	terrain:SetAttribute(BorderTerrainView.ATTRIBUTE, false)
	workspace:SetAttribute(BorderTerrainView.READY_ATTRIBUTE, false)
	for name, color in BorderTerrain.COLORS do
		terrain:SetMaterialColor(MATERIALS[name], Color3.fromRGB(color[1], color[2], color[3]))
	end
	local field = BorderTerrain.field()
	local chunks = BorderTerrain.chunks()
	BorderTerrain.runBudgeted(#chunks, function(n)
		writeChunk(terrain, field, chunks[n])
	end, BorderTerrainView.FRAME_BUDGET_S, os.clock, task.wait)
	terrain:SetAttribute(BorderTerrainView.ATTRIBUTE, true)
	workspace:SetAttribute(BorderTerrainView.READY_ATTRIBUTE, true)
	return true
end

return BorderTerrainView
