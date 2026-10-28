--!strict
--[[
	MinimapData

	Points of interest for a UI minimap, straight from WorldLayout (no
	Instances): the fountain (map centre), every plot (index i -> workspace
	Plot with PlotIndex i, whose OwnerUserId attribute says who owns it), the
	props at PROP_SPOTS (the Exclusive Shop jar only with FEATURES.ExclusiveShop) and the hub spawn. `toMap` turns world X/Z into 0..1 map
	coordinates over the Ground (u = +X to the right, v = +Z downwards).
	Pure.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local Shops = if script then require(script.Parent.Parent.Shared.Shops) else require("../../shared/Shops")
local LayoutMath = if script then require(script.Parent.LayoutMath) else require("./LayoutMath")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Point = {
	kind: string,
	name: string,
	x: number,
	z: number,
	plotIndex: number?,
	label: string?,
	icon: string?,
}

local MinimapData = {}

MinimapData.WORLD_SIZE = 640 -- Ground size (WorldLayout), centred on the fountain
-- Hub SpawnLocation (scripts/StaticWorld SPAWN_YAW / SPAWN_RADIUS; tests check they match)
MinimapData.SPAWN_YAW = 67.5
MinimapData.SPAWN_RADIUS = 64

-- Pins with a label and an icon (the shop item icons): the world shop stands (CONTRACT.md §27.2) and the Exclusive
-- Shop's jar (contract/exclusive-shop.md §7.1).
MinimapData.SHOP_PINS = table.freeze({
	[Shops.SHOPS.ItemShop.stand] = table.freeze({ label = Shops.SHOPS.ItemShop.name, icon = "🛒" }),
	[Shops.SHOPS.UpgradeShop.stand] = table.freeze({ label = Shops.SHOPS.UpgradeShop.name, icon = "⬆️" }),
	[WorldLayout.EXCLUSIVE_JAR.model] = table.freeze({ label = "Exclusive Shop", icon = "👑" }),
}) :: { [string]: { label: string, icon: string } }

-- `features` defaults to Config.FEATURES: with ExclusiveShop off the jar has no point (it is not built).
function MinimapData.points(features: { [string]: any }?): { Point }
	local flags = features or Config.FEATURES
	local points: { Point } = { { kind = "Fountain", name = "Fountain", x = 0, z = 0 } }
	for i = 1, Config.PLOT_COUNT do
		local c = WorldLayout.plotCentre(i)
		table.insert(points, { kind = "Plot", name = `Plot_{i}`, x = c[1], z = c[3], plotIndex = i })
	end
	for name, spot in WorldLayout.PROP_SPOTS do
		if name == WorldLayout.EXCLUSIVE_JAR.model and flags.ExclusiveShop ~= true then
			continue
		end
		local point: Point = { kind = name, name = name, x = spot.pos[1], z = spot.pos[3] }
		local pin = MinimapData.SHOP_PINS[name]
		if pin then
			point.label, point.icon = pin.label, pin.icon
		end
		table.insert(points, point)
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
