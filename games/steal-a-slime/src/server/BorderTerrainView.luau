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
BorderTerrainView.TILES_PER_YIELD = 4

local MATERIALS: { [string]: Enum.Material } = {
	Grass = Enum.Material.Grass,
	LeafyGrass = Enum.Material.LeafyGrass,
	Rock = Enum.Material.Rock,
}

local function writeTile(terrain: Terrain, field: BorderTerrain.Field, tile: BorderTerrain.Tile)
	local cell, count = BorderTerrain.CELL, BorderTerrain.TILE_CELLS
	local floor = BorderTerrain.FLOOR
	local heights: { number } = {}
	local tops: { string } = {}
	local tallest = 0
	for i = 1, count do
		local x = tile.x + (i - 0.5) * cell
		for k = 1, count do
			local z = tile.z + (k - 0.5) * cell
			local h = field.height(x, z)
			local inside = math.max(math.abs(x), math.abs(z)) <= BorderTerrain.INNER
			-- -1: no column here (inside the Ground square)
			heights[(i - 1) * count + k] = if inside then -1 else h
			tops[(i - 1) * count + k] = if h > 0 then field.material(x, z) else "Grass"
			tallest = math.max(tallest, h)
		end
	end
	local layers = math.ceil((tallest - floor) / cell) + 1
	local materials = table.create(count)
	local occupancy = table.create(count)
	for i = 1, count do
		local mx = table.create(layers)
		local ox = table.create(layers)
		for j = 1, layers do
			local mj = table.create(count, Enum.Material.Air)
			local oj = table.create(count, 0)
			local bottom = floor + (j - 1) * cell
			for k = 1, count do
				local h = heights[(i - 1) * count + k]
				if h >= 0 then
					local filled = math.clamp((h - bottom) / cell, 0, 1)
					if filled > 0.02 then
						mj[k] = MATERIALS[tops[(i - 1) * count + k]]
						oj[k] = filled
					end
				end
			end
			mx[j] = mj
			ox[j] = oj
		end
		materials[i] = mx
		occupancy[i] = ox
	end
	local region = Region3.new(
		Vector3.new(tile.x, floor, tile.z),
		Vector3.new(tile.x + count * cell, floor + layers * cell, tile.z + count * cell)
	)
	terrain:WriteVoxels(region, cell, materials, occupancy)
end

function BorderTerrainView.place(): boolean
	local terrain = workspace.Terrain
	if terrain:GetAttribute(BorderTerrainView.ATTRIBUTE) ~= nil then
		return false
	end
	terrain:SetAttribute(BorderTerrainView.ATTRIBUTE, false)
	for name, color in BorderTerrain.COLORS do
		terrain:SetMaterialColor(MATERIALS[name], Color3.fromRGB(color[1], color[2], color[3]))
	end
	local field = BorderTerrain.field()
	for n, tile in BorderTerrain.tiles() do
		writeTile(terrain, field, tile)
		if n % BorderTerrainView.TILES_PER_YIELD == 0 then
			task.wait()
		end
	end
	terrain:SetAttribute(BorderTerrainView.ATTRIBUTE, true)
	return true
end

return BorderTerrainView
