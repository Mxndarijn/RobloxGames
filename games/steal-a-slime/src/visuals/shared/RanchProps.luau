--!strict
--[[
	RanchProps (owner: Archer)

	Where the Slime Ranch kit props stand (data only; WorldLayout turns each
	row into a MeshAsset slot under Map.Decor, PropClearance checks them).
	Fixed numbers, no randomness: every build places the same props.

	Two anchors:
	  polar  { angle, r }   about the fountain, same convention as
	                        WorldLayout.PROP_SPOTS (pos = (sin a, 0, cos a) * r).
	                        Turn = angle + yaw, so yaw 180 faces the fountain.
	  plot   { plot, x, z } in plot i's frame (WorldLayout.plotCentre: local
	                        -Z = the entrance, +Z = behind the back fence).
	                        Turn = plot yaw + yaw, so yaw 180 faces the entrance side.
	Kit fronts face local +Z (LESSONS kit gotcha; MeshSwap turns the upload
	onto that, MeshAssets.IMPORT_YAW), so yaw 180 shows the front to a player
	coming from the plaza. `face` = another row's name turns the front at it
	instead (the camp bench at its campfire). `scale` is uniform: slot =
	native size * scale.

	Facing (TODO v28 #11, tests/WorldPlacement.spec): seats face what they
	are for, signs / boards / doors face the way players come (the plaza for
	the plaza edge and the wedges, the entrance side for the farmyards),
	mailboxes face the spoke path, lantern arms hang over it.

	Clusters (map colours, PropClearance zones):
	  plaza     the plaza edge between the ring path (r 82) and the plot fronts
	  entrance  a lantern or a mailbox by each plot's entrance corridor
	  farm      behind the plots and in the wedges between neighbours
	  yard      the sand yard's dressing: clusters in the wedge gaps and behind the plots (YardProps)

	The fence segments (WorldLayout plot walls), pad stands, plaza showpieces,
	landing ring, goo drain and the fountain place themselves in WorldLayout.
	Anything that is never placed goes in INTENTIONALLY_UNPLACED with a reason.
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local YardProps = if script then require(script.Parent.YardProps) else require("./YardProps")

export type Placement = {
	name: string,
	mesh: string,
	cluster: string, -- "plaza" | "entrance" | "farm"
	scale: number,
	yaw: number,
	angle: number?, -- polar anchor
	r: number?,
	plot: number?, -- plot anchor
	x: number?,
	z: number?,
	face: string?, -- name of another placement: turn the kit front at it (yaw ignored)
	tint: { number }?, -- slot colour that multiplies the mesh's vertex colours (MeshTint), near white
}

local RanchProps = {}

RanchProps.CLUSTERS = table.freeze({ "plaza", "entrance", "farm", "yard" })

-- Uploaded kit meshes that never get a slot of their own. Empty on purpose:
-- every MeshAssets entry has a slot today. Add { mesh = reason } here rather
-- than leaving an asset silently unused (tests/RanchProps.spec enforces it).
RanchProps.INTENTIONALLY_UNPLACED = table.freeze({
	ranch_lantern_post = "its entrance slots became the odd plots' mailboxes (v29 B2); no spare decor slot",
	ranch_border_fence_broken = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_hedge_stepped = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_pine_twin = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_rock_spire = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_chunk_b_m = "border v5 slot trim: one corner grove a corner leaves no room for the mirrored twin; mesh kept uploaded",
	ranch_border_chunk_d_m = "border v5 slot trim: one corner grove a corner leaves no room for the mirrored twin; mesh kept uploaded",
	plot_skin_mushroom = "plot skin decor (Config.PLOT_SKINS): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_candy = "plot skin decor (Config.PLOT_SKINS): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_crystal = "plot skin decor (Config.PLOT_SKINS): stands in for Mailbox_<i> on the client, no world slot",
	fountain_tier_ring = "fountain tier decor (FountainTiers): cloned round the fountain by the client at tier 2+, no world slot",
	fountain_tier_crest = "fountain tier decor (FountainTiers): cloned over the fountain by the client at tier 3+, no world slot",
	merge_vat = "plot merge vat: MeshSwap.swapPlotVats stands it over every plot's MergeVat disc, no world slot",
	rain_magnet = "Rain Magnet upgrade prop (RainMagnet): the client stands it on the owner's plot while the upgrade has a level, no world slot",
	ranch_bat = "default melee Bat: the Handle mesh of Tool 'Bat' (held, no collision), no world slot",
	slime_base = "per-type slime kit mesh, worn by slimes (server SlimeMesh), not a world slot",
	slime_acc_leaf = "per-type slime kit mesh, worn by slimes (server SlimeMesh), not a world slot",
	slime_ears = "per-type slime kit mesh, worn by slimes (server SlimeMesh), not a world slot",
	slime_horns = "per-type slime kit mesh, worn by slimes (server SlimeMesh), not a world slot",
	slime_acc_crown = "per-type slime kit mesh, worn by slimes (server SlimeMesh), not a world slot",
	slime_acc_crystal = "per-type slime kit mesh, worn by slimes (server SlimeMesh), not a world slot",
	slime_wobble = "per-type slime kit mesh, worn by slimes (server SlimeMesh), not a world slot",
}) :: { [string]: string }

local rows: { Placement } = {}

local function polar(name: string, mesh: string, cluster: string, angle: number, r: number, yaw: number, scale: number)
	table.insert(rows, { name = name, mesh = mesh, cluster = cluster, angle = angle, r = r, yaw = yaw, scale = scale })
end

local function onPlot(
	name: string,
	mesh: string,
	cluster: string,
	plot: number,
	x: number,
	z: number,
	yaw: number,
	scale: number
)
	table.insert(
		rows,
		{ name = name, mesh = mesh, cluster = cluster, plot = plot, x = x, z = z, yaw = yaw, scale = scale }
	)
end

-- Budget (tests/WorldBudget.spec): every kit mesh once, plus one entrance
-- prop per plot (a lantern or a mailbox). No second copies of a decorative piece.

-- Plaza edge -------------------------------------------------------------
-- Vignettes on the free bisectors (22.5, 112.5, 202.5, 292.5, 337.5) and a
-- planter beside the shop (67.5) PROP_SPOT.
polar("Campfire", "ranch_campfire", "plaza", 22.5, 92, 180, 1.3)
polar("CampBench", "ranch_bench", "plaza", 16.5, 92, 90, 1.2)
rows[#rows].face = "Campfire"
polar("Well", "ranch_well", "plaza", 112.5, 92, 180, 1.2)
polar("WellPump", "ranch_water_pump", "plaza", 120, 91, 180, 1.2)
polar("PicnicTable", "ranch_picnic_table", "plaza", 202.5, 91, 180, 1.2)
polar("Sunflowers", "ranch_sunflower_patch", "plaza", 196, 94, 180, 1)
polar("HorseshoePit", "ranch_horseshoe_pit", "plaza", 292.5, 90, 180, 1.2)
polar("GooSign", "ranch_goo_sign", "plaza", 337.5, 91, 180, 1.2)
polar("Birdhouse", "ranch_birdhouse", "plaza", 330, 93, 180, 1.2)
polar("Planter", "ranch_flower_planter", "plaza", 56, 90, 180, 1.2)

-- Entrances --------------------------------------------------------------
-- A mailbox by the gate on every
-- plot (v29 B2: odd plots used to get a lantern instead, so half the plots had
-- no mailbox). One each a plot paid for the plot DexBoard meshes
-- (the old decor slot cap, C6); the lanterns' slots became the odd plots' mailboxes,
-- so the budget is unchanged. The mailbox door (kit front) faces the spoke path
-- (plot-local x 0): yaw 270 = front towards plot -X. ENTRANCE_PATH_YAW keeps the
-- lantern's old yaw for when it gets a slot again.
RanchProps.ENTRANCE_PATH_YAW = table.freeze({ ranch_lantern_post = 0, ranch_mailbox = 270 })
for i = 1, Config.PLOT_COUNT do
	onPlot(`Mailbox_{i}`, "ranch_mailbox", "entrance", i, 17, -45, 270, 1.2)
end

-- Farm -------------------------------------------------------------------
-- One farmyard behind each plot (back fence at local z 40) ...
onPlot("Windmill_1", "ranch_windmill", "farm", 1, 0, 64, 180, 1.6)
onPlot("FeedSacks_1", "ranch_feed_sacks", "farm", 1, -16, 52, 180, 1.2)
onPlot("Wheelbarrow_1", "ranch_wheelbarrow", "farm", 1, 16, 52, 160, 1.2)

onPlot("BarnLoft_2", "ranch_barn_loft", "farm", 2, 0, 62, 180, 1.4)
onPlot("Weathervane_2", "ranch_weathervane", "farm", 2, 16, 54, 180, 1.2)
onPlot("ToolRack_2", "ranch_tool_rack", "farm", 2, -17, 52, 180, 1.1)

onPlot("GooHive_3", "ranch_goo_hive", "farm", 3, 6, 52, 180, 1.2)
onPlot("GooBucket_3", "ranch_goo_bucket", "farm", 3, 8, 60, 180, 1.2)

onPlot("Pumpkins_4", "ranch_pumpkin_patch", "farm", 4, -12, 54, 180, 1.3)
onPlot("Scarecrow_4", "ranch_scarecrow", "farm", 4, 0, 60, 180, 1.2)

onPlot("LogPile_5", "ranch_log_pile", "farm", 5, -12, 54, 180, 1.2)
onPlot("CompostBin_5", "ranch_compost_bin", "farm", 5, 10, 53, 180, 1.2)
onPlot("Wagon_5", "ranch_wagon", "farm", 5, 0, 68, 180, 1.3)

onPlot("WaterTrough_6", "ranch_water_trough", "farm", 6, -12, 52, 180, 1.2)
onPlot("HitchingPost_6", "ranch_hitching_post", "farm", 6, 8, 52, 180, 1.2)
onPlot("MilkChurn_6", "ranch_milk_churn", "farm", 6, 17, 52, 180, 1.2)

onPlot("BarrelStack_7", "ranch_barrel_stack", "farm", 7, -16, 52, 180, 1.2)
onPlot("RainBarrel_7", "ranch_rain_barrel", "farm", 7, 16, 52, 180, 1.2)

onPlot("SlimeCoop_8", "ranch_slime_coop", "farm", 8, 0, 60, 180, 1.3)
onPlot("FenceStile_8", "ranch_fence_stile", "farm", 8, -16, 52, 180, 1.2)
-- The plots' fence corners close on the panels' own end posts, so the kit
-- corner post stands here once, as the stile's gatepost.
onPlot("StilePost_8", "phoenix_corner_post", "farm", 8, -23, 52, 180, 1)
onPlot("Barrel_8", "ranch_barrel", "farm", 8, 13, 51, 180, 1.2)

-- ... and the sparse props in the wedges between neighbours (every other
-- bisector, r 200, and the shed at r 245; the old Decor Ranch / Shed slots),
-- fronts (the shed's door) towards the plaza players come from.
local WEDGE = {
	{ "ranch_hay_bale", 1.25 },
	{ "ranch_crate", 4 / 3 },
	{ "ranch_feed_trough", 1.3 },
	{ "ranch_crate_goo", 4 / 3 },
}
for k, def in WEDGE do
	local angle = (2 * k - 2) * 360 / Config.PLOT_COUNT + 180 / Config.PLOT_COUNT
	polar(`Ranch{k}`, def[1], "farm", angle, 200, 180, def[2])
end
polar("Shed", "ranch_shed", "farm", 112.5, 245, 180, 1.4)

-- Yard: the sand yard's dressing (YardProps, generated by tools/yard/generate from a seed): small clusters and a few
-- single props in the gaps between plots and on the sand behind them, each with its own yaw, scale and slight tint.
for _, y in YardProps.ROWS do
	table.insert(rows, {
		name = y[1],
		mesh = y[2],
		cluster = "yard",
		angle = y[3],
		r = y[4],
		yaw = y[5],
		scale = y[6],
		tint = y[7],
	})
end

RanchProps.PLACEMENTS = table.freeze(rows)

return table.freeze(RanchProps)
