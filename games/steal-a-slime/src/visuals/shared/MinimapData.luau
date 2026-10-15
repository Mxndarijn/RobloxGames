--!strict
--[[
	MinimapData (FEATURES.Minimap)

	Points of interest for a UI minimap, straight from WorldLayout (no
	Instances): the fountain (map centre), every plot (index i -> workspace
	Plot with PlotIndex i, whose OwnerUserId attribute says who owns it), the
	props at PROP_SPOTS and the hub spawn. `toMap` turns world X/Z into 0..1 map
	coordinates over the Ground (u = +X to the right, v = +Z downwards).
	Pure; returns no points when the flag is off.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Point = { kind: string, name: string, x: number, z: number, plotIndex: number? }

local MinimapData = {}

MinimapData.WORLD_SIZE = 640 -- Ground size (WorldLayout), centred on the fountain
-- Hub SpawnLocation (scripts/StaticWorld SPAWN_YAW / SPAWN_RADIUS; tests check they match)
MinimapData.SPAWN_YAW = 67.5
MinimapData.SPAWN_RADIUS = 64

function MinimapData.points(): { Point }
	if not Config.FEATURES.Minimap then
		return {}
	end
	local points: { Point } = { { kind = "Fountain", name = "Fountain", x = 0, z = 0 } }
	for i = 1, Config.PLOT_COUNT do
		local c = WorldLayout.plotCentre(i)
		table.insert(points, { kind = "Plot", name = `Plot_{i}`, x = c[1], z = c[3], plotIndex = i })
	end
	for name, spot in WorldLayout.PROP_SPOTS do
		table.insert(points, { kind = name, name = name, x = spot.pos[1], z = spot.pos[3] })
	end
	local n = LayoutMath.direction(MinimapData.SPAWN_YAW, 0)
	table.insert(points, {
		kind = "Spawn",
		name = "HubSpawn",
		x = n[1] * MinimapData.SPAWN_RADIUS,
		z = n[3] * MinimapData.SPAWN_RADIUS,
	})
	table.sort(points, function(a, b)
		return a.name < b.name
	end)
	return points
end

function MinimapData.toMap(x: number, z: number): (number, number)
	local half = MinimapData.WORLD_SIZE / 2
	return math.clamp((x + half) / MinimapData.WORLD_SIZE, 0, 1), math.clamp((z + half) / MinimapData.WORLD_SIZE, 0, 1)
end

return MinimapData
