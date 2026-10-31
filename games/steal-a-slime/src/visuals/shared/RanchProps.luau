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
	obby_goo_ring_eyes = "the Obby's Goo Ring portal: server/ObbyView builds its slots (MeshSwap.applyUnder) and the ring home is filled on the client (ObbyCourseView); decor, walk-through",
	obby_goo_swirl = "the Obby's Goo Ring portal: server/ObbyView builds its slots (MeshSwap.applyUnder) and the ring home is filled on the client (ObbyCourseView); decor, walk-through",
	obby_goo_sign = "the Obby's Goo Ring portal: server/ObbyView builds its slots (MeshSwap.applyUnder) and the ring home is filled on the client (ObbyCourseView); decor, walk-through",
	goo_jar_glass_1_mid = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_glass_2_mid = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_glass_3_mid = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_glass_2_top = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_glass_3_top = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_glass_4_top = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_trim_1_mid = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_trim_2_mid = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_trim_3_mid = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_trim_2_top = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_trim_3_top = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_trim_4_top = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_deck_2 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_deck_3 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_deck_4 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_stair = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_jar_crown = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_drop_tube_glass_2 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_drop_tube_glass_3 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_drop_tube_glass_4 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_drop_tube_goo_2 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_drop_tube_goo_3 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	goo_drop_tube_goo_4 = "goo jar tower upper jars: server/BaseFloors builds them at runtime (WorldLayout.floor), no static slot",
	phoenix_pad_crate = "plot pad crate: the goo jar tower's pads stand on round cork stands (goo_cork_stand)",
	ranch_border_fence_broken = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_hedge_stepped = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_pine_twin = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_rock_spire = "border v3 slot trim: merged into a sibling design to stay under the 400 mesh-slot gate; mesh kept uploaded",
	ranch_border_chunk_b_m = "border v5 slot trim: one corner grove a corner leaves no room for the mirrored twin; mesh kept uploaded",
	ranch_border_chunk_d_m = "border v5 slot trim: one corner grove a corner leaves no room for the mirrored twin; mesh kept uploaded",
	plot_skin_mushroom = "plot skin decor (Config.PLOT_SKINS): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_candy = "plot skin decor (Config.PLOT_SKINS): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_crystal = "plot skin decor (Config.PLOT_SKINS): stands in for Mailbox_<i> on the client, no world slot",
	merge_vat = "plot merge vat: MeshSwap.swapPlotVats stands it over every plot's MergeVat disc, no world slot",
	pet_cloud = "follow pet cloud (FollowPets): the client clones the server-published ReplicatedStorage.PetCloudMeshes template under the owner's pet slime, decor, no world slot",
	pet_mount_jelly = "pet seat (Config.PET_SEATS, FollowPets): the client clones the server-published ReplicatedStorage.PetCloudMeshes template under the owner's pet slime, decor, no world slot",
	pet_mount_rainbow_cloud = "pet seat (Config.PET_SEATS, FollowPets): the client clones the server-published ReplicatedStorage.PetCloudMeshes template under the owner's pet slime, decor, no world slot",
	pet_mount_storm_cloud = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_sunset_cloud = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_ice_cloud = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_flame_cloud = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_leaf = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_bubble = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_lily_pad = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_mushroom = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_pancakes = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_star_cushion = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_crescent_moon = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_magic_carpet = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_ufo = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_royal_cushion = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_hoverboard = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_clam_shell = "pet seat (Config.PET_SEATS, FollowPets, the Exclusive Shop's floating display): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	ranch_bat = "default melee Bat: the Handle mesh of Tool 'Bat' (held, no collision), no world slot",
	bat_skin_lollipop = "Bat skin (Exclusive Shop): another Handle mesh for Tool 'Bat' (held, no collision), no world slot",
	bat_skin_fish = "Bat skin (Exclusive Shop): another Handle mesh for Tool 'Bat' (held, no collision), no world slot",
	bat_skin_foam_finger = "Bat skin (Exclusive Shop): another Handle mesh for Tool 'Bat' (held, no collision), no world slot",
	bat_skin_golden = "Bat skin (Exclusive Shop): another Handle mesh for Tool 'Bat' (held, no collision), no world slot",
	pet_mount_pumpkin = "pet seat (Config.PET_SEATS, seasonal Exclusive, FollowPets): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	pet_mount_snowglobe = "pet seat (Config.PET_SEATS, seasonal Exclusive, FollowPets): the client clones the server-published ReplicatedStorage.PetCloudMeshes template, decor, no world slot",
	slime_hat_party = "slime hat (Exclusive Shop): the client welds the server-published ReplicatedStorage.SlimeHatMeshes template on pad slimes (SlimeHatsFx), no collision, no world slot",
	slime_hat_bow = "slime hat (Exclusive Shop): the client welds the server-published ReplicatedStorage.SlimeHatMeshes template on pad slimes (SlimeHatsFx), no collision, no world slot",
	slime_hat_chef = "slime hat (Exclusive Shop): the client welds the server-published ReplicatedStorage.SlimeHatMeshes template on pad slimes (SlimeHatsFx), no collision, no world slot",
	slime_hat_flower_crown = "slime hat (Exclusive Shop): the client welds the server-published ReplicatedStorage.SlimeHatMeshes template on pad slimes (SlimeHatsFx), no collision, no world slot",
	slime_hat_top_hat = "slime hat (Exclusive Shop): the client welds the server-published ReplicatedStorage.SlimeHatMeshes template on pad slimes (SlimeHatsFx), no collision, no world slot",
	slime_hat_witch = "slime hat (Exclusive Shop): the client welds the server-published ReplicatedStorage.SlimeHatMeshes template on pad slimes (SlimeHatsFx), no collision, no world slot",
	lock_stopper_candy = "lock style (Exclusive Shop): MeshSwap shows it in a plot's StopperShut goo_jar_stopper slot (lookOf), the same box, decor, no slot of its own",
	lock_stopper_carousel = "lock style (Exclusive Shop): MeshSwap shows it in a plot's StopperShut goo_jar_stopper slot (lookOf), the same box, decor, no slot of its own",
	lock_stopper_sleepy = "lock style (Exclusive Shop): MeshSwap shows it in a plot's StopperShut goo_jar_stopper slot (lookOf), the same box, decor, no slot of its own",
	plot_skin_fairground = "plot skin decor (Config.PLOT_SKINS, Exclusive): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_beach = "plot skin decor (Config.PLOT_SKINS, Exclusive): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_space = "plot skin decor (Config.PLOT_SKINS, Exclusive): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_winter = "plot skin decor (Config.PLOT_SKINS, Exclusive): stands in for Mailbox_<i> on the client, no world slot",
	plot_skin_haunted = "plot skin decor (Config.PLOT_SKINS, Exclusive): stands in for Mailbox_<i> on the client, no world slot",
	ranch_fence_20 = "plot fence panel: the goo jar tower's glass encloses each plot (CONTRACT.md §5.3), no fence slot",
	phoenix_fence_segment = "plot fence half panel: the goo jar tower's glass encloses each plot (CONTRACT.md §5.3), no fence slot",
	phoenix_gate = "plot gate: the goo jar tower's door and bridge are the plot entrance (CONTRACT.md §5.3), no gate slot",
	exclusive_jar_boutique = "Exclusive Shop jar: server/WorldProps builds the ExclusiveShopStand at runtime with this mesh's Shop slot (WorldLayout.EXCLUSIVE_JAR), no static slot",
	exclusive_jar_boutique_glass = "Exclusive Shop jar glass: the Glass slot of the runtime ExclusiveShopStand (WorldLayout.EXCLUSIVE_JAR), no static slot",
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
-- Vignettes on the free bisectors (22.5, 292.5; 337.5 is the obby path's, beside the ritual circle) and a planter beside the shop (67.5) PROP_SPOT. The 112.5
-- bisector is the Exclusive Shop jar's (WorldLayout.EXCLUSIVE_JAR). The 202.5 lawn is the Upcoming Events
-- board's (WorldLayout.EVENT_BOARD), so its picnic table and sunflowers flank the horseshoe pit on the 292.5 lawn; the
-- well and its pump stand on that lawn's plot 6 side, between the board and the plot 6 entrance, by the ring path.
polar("Campfire", "ranch_campfire", "plaza", 22.5, 92, 180, 1.3)
polar("CampBench", "ranch_bench", "plaza", 16.5, 92, 90, 1.2)
rows[#rows].face = "Campfire"
polar("Well", "ranch_well", "plaza", 211.75, 92, 180, 1.2)
polar("WellPump", "ranch_water_pump", "plaza", 216.25, 93, 180, 1.2)
polar("PicnicTable", "ranch_picnic_table", "plaza", 301.5, 90, 180, 1.2)
polar("Sunflowers", "ranch_sunflower_patch", "plaza", 300, 97.5, 180, 1)
polar("HorseshoePit", "ranch_horseshoe_pit", "plaza", 292.5, 90, 180, 1.2)
polar("Planter", "ranch_flower_planter", "plaza", 56, 90, 180, 1.2)
-- The Guide's corner (TutorialNpc spot, 247.5 / r 90, PropClearance.SPOT_RADII): the ranch hand's hay, feed and
-- goo round the sides and back, a lantern behind; the plaza side stays open to walk up to the Guide.
polar("GuideHay", "ranch_hay_bale", "plaza", 243.4, 91, 180, 1.2)
polar("GuideBucket", "ranch_goo_bucket", "plaza", 240.4, 89.5, 200, 1.1)
polar("GuideSacks", "ranch_feed_sacks", "plaza", 243, 96.5, 170, 1)
polar("GuideCrate", "ranch_crate_goo", "plaza", 251.6, 91, 165, 1)
polar("GuideBarrel", "ranch_barrel", "plaza", 253.8, 94, 180, 1.1)
polar("GuideLantern", "ranch_lantern_post", "plaza", 250.5, 96, 180, 1)

-- Entrances --------------------------------------------------------------
-- A mailbox by the gate on every
-- plot (v29 B2: odd plots used to get a lantern instead, so half the plots had
-- no mailbox). One each a plot paid for the old plot DexBoard meshes
-- (the old decor slot cap, C6; the board is gone since the goo jar tower); the lanterns' slots became the odd plots' mailboxes,
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
