--!strict
--[[
	MeshAssets (owner: Phoenix)

	Slime Ranch kit meshes (shared/modeling-kit/out/*.fbx), keyed by kit name.
	WorldLayout tags placeholder Parts with the attribute MeshAsset = <name>;
	server/MeshSwap replaces their look with AssetService:CreateMeshPartAsync
	(scripts can't set MeshId on an existing MeshPart). A name whose meshId is
	still nil keeps its primitive placeholder, so the map plays without uploads.

	Filled from shared/modeling-kit/uploaded.json (Open Cloud Model uploads).
	size = the mesh's native size (studs). MeshSwap fits the MeshPart into the
	placeholder box at one uniform scale (MeshAssets.fit), never stretched.
]]

-- `offset` (FEATURES.FountainSplit pieces only): the piece's bbox centre minus the whole fountain mesh's bbox centre, in the
-- slot's own axes (Roblox X, Y, Z = kit x, kit z, -kit y; rotate with the slot, the mesh's IMPORT_YAW is not applied to it).
export type Entry = { assetId: number?, meshId: string?, size: { number }?, offset: { number }? }

local NAMES = {
	"slime_fountain",
	"phoenix_fence_segment",
	"phoenix_corner_post",
	"phoenix_gate",
	"phoenix_pad_crate",
	"phoenix_top_earners_board",
	"ranch_plaza_signpost",
	"ranch_shop_stand",
	"ranch_item_shop",
	"ranch_upgrade_cabinet",
	"phoenix_plaza_podium_1",
	"phoenix_plaza_podium_2",
	"phoenix_plaza_podium_3",
	"ranch_crate",
	"ranch_crate_goo",
	"ranch_feed_trough",
	"ranch_hay_bale",
	"ranch_shed",
	"ranch_landing_ring",
	"ranch_goo_drain",
	"ranch_barn_loft",
	"ranch_barrel",
	"ranch_barrel_stack",
	"ranch_bench",
	"ranch_birdhouse",
	"ranch_campfire",
	"ranch_compost_bin",
	"ranch_feed_sacks",
	"ranch_fence_stile",
	"ranch_flower_planter",
	"ranch_goo_bucket",
	"ranch_goo_hive",
	"ranch_goo_sign",
	"ranch_hitching_post",
	"ranch_horseshoe_pit",
	"ranch_lantern_post",
	"ranch_log_pile",
	"ranch_mailbox",
	"ranch_milk_churn",
	"ranch_picnic_table",
	"ranch_pumpkin_patch",
	"ranch_rain_barrel",
	"ranch_scarecrow",
	"ranch_slime_coop",
	"ranch_sunflower_patch",
	"ranch_tool_rack",
	"ranch_wagon",
	"ranch_water_pump",
	"ranch_water_trough",
	"ranch_weathervane",
	"ranch_well",
	"ranch_wheelbarrow",
	"ranch_windmill",
	"ranch_guide",
	"slime_fountain_emerge",
	"ranch_border_fence_straight",
	"ranch_border_fence_broken",
	"ranch_border_hedge_long",
	"ranch_border_hedge_round",
	"ranch_border_hedge_stepped",
	"ranch_border_pine_tall",
	"ranch_border_pine_broad",
	"ranch_border_pine_twin",
	"ranch_border_oak_round",
	"ranch_border_sapling_trio",
	"ranch_border_rock_boulder",
	"ranch_border_rock_slab",
	"ranch_border_rock_cluster",
	"ranch_border_rock_spire",
	"ranch_border_hill_ridge",
	"ranch_border_hill_dome",
	"ranch_border_hill_twin",
	"ranch_border_fence_long",
	"ranch_border_hedge_xl",
	"ranch_border_grove_pine",
	"ranch_border_grove_mixed",
	"ranch_border_grove_rocky",
	"ranch_border_chunk_b",
	"ranch_border_chunk_b_m",
	"ranch_border_chunk_d",
	"ranch_border_chunk_d_m",
	"ranch_border_chunk_h",
	"ranch_border_chunk_h_m",
	"habitat_hay_nest_overlay",
	"habitat_mushroom_ring_overlay",
	"habitat_flower_bed_overlay",
	"habitat_barn_crate_overlay",
	"habitat_rodeo_barrel_overlay",
	"habitat_syrup_pool_overlay",
	"habitat_show_stool_overlay",
	"habitat_candy_patch_overlay",
	"habitat_crystal_grotto_overlay",
	"ranch_fence_20",
	"plot_skin_mushroom",
	"plot_skin_candy",
	"plot_skin_crystal",
	"merge_vat",
	"goo_cork_stand",
	"goo_drop_tube_glass_2",
	"goo_drop_tube_glass_3",
	"goo_drop_tube_glass_4",
	"goo_drop_tube_goo_2",
	"goo_drop_tube_goo_3",
	"goo_drop_tube_goo_4",
	"goo_jar_crown",
	"goo_jar_deck_2",
	"goo_jar_deck_3",
	"goo_jar_deck_4",
	"goo_jar_door",
	"goo_jar_door_ring",
	"goo_jar_foot",
	"goo_jar_glass_1_mid",
	"goo_jar_glass_1_top",
	"goo_jar_glass_2_mid",
	"goo_jar_glass_2_top",
	"goo_jar_glass_3_mid",
	"goo_jar_glass_3_top",
	"goo_jar_glass_4_top",
	"goo_jar_mascot",
	"goo_jar_stair",
	"goo_jar_stopper",
	"goo_jar_trim_1_mid",
	"goo_jar_trim_1_top",
	"goo_jar_trim_2_mid",
	"goo_jar_trim_2_top",
	"goo_jar_trim_3_mid",
	"goo_jar_trim_3_top",
	"goo_jar_trim_4_top",
	"goo_lock_button",
	"giant_broadleaf",
	"giant_pine_layered",
	"giant_round_canopy",
	"giant_elder_oak",
	"giant_sequoia_spire",
	"giant_cloud_tree",
	"ranch_bat",
	"ranch_floor_deck",
	"ranch_floor_paths",
	"pet_cloud",
	-- Held PvP items (Shared.PvpModels, server/PvpHeld): the placeholder Parts stand in while a mesh fails to load.
	"pvp_knock_glove_1",
	"pvp_knock_glove_2",
	"pvp_knock_glove_3",
	"pvp_knock_glove_4",
	"pvp_knock_glove_5",
	"pvp_goo_trap_1",
	"pvp_goo_trap_2",
	"pvp_goo_trap_3",
	"pvp_goo_blaster_1",
	"pvp_goo_blaster_2",
	"pvp_goo_blaster_3",
	"pvp_fun_confetti",
	"pvp_fun_balloon",
	"pvp_fun_bubbles",
	"pvp_fun_bounce_pad",
	"pvp_fun_squeaky",
	"pvp_fun_hat_launcher",
	"pvp_fun_dance_bomb",
	"pvp_fun_fireworks",
}

local entries: { [string]: Entry } = {}
-- Size is the polished FBX bbox (goo polish, ~43.316 tall). Version 3 of the
-- asset (2026-10-17) drops the splash-pool blob at the slide exit so the
-- slime lane flows from the slide mouth. The WorldLayout slot uses this box.
entries["slime_fountain"] =
	{ assetId = 137335028699292, meshId = "rbxassetid://117431796782881", size = { 54.45, 43.316, 63.851 } }
entries["phoenix_fence_segment"] =
	{ assetId = 92327721520041, meshId = "rbxassetid://88430332942524", size = { 11, 9.02, 1.8 } }
entries["phoenix_corner_post"] =
	{ assetId = 122993526477202, meshId = "rbxassetid://119122479393270", size = { 2.8, 9.689, 2.8 } }
entries["phoenix_gate"] =
	{ assetId = 92840827180297, meshId = "rbxassetid://95862556594894", size = { 20.2, 13.4, 2.6 } }
entries["phoenix_pad_crate"] =
	{ assetId = 122007188029546, meshId = "rbxassetid://78946442257134", size = { 7.8, 2.61, 7.8 } }
entries["phoenix_top_earners_board"] =
	{ assetId = 126155085567089, meshId = "rbxassetid://98390738410954", size = { 21.103, 19.934, 4.097 } }
entries["ranch_plaza_signpost"] =
	{ assetId = 131934867179344, meshId = "rbxassetid://73448923703025", size = { 12.648, 14.515, 7.55 } }
entries["ranch_shop_stand"] =
	{ assetId = 102942641234419, meshId = "rbxassetid://93701432819080", size = { 12.01, 14.15, 7.454 } }
entries["ranch_item_shop"] =
	{ assetId = 105082858859876, meshId = "rbxassetid://135059318016634", size = { 15.391, 16.558, 8.15 } }
entries["ranch_upgrade_cabinet"] =
	{ assetId = 112507254723244, meshId = "rbxassetid://139845226619480", size = { 16.407, 15.29, 9.93 } }
entries["phoenix_plaza_podium_1"] =
	{ assetId = 77650457545661, meshId = "rbxassetid://94983834296700", size = { 8.923, 7.192, 8.58 } }
entries["phoenix_plaza_podium_2"] =
	{ assetId = 97620670705737, meshId = "rbxassetid://105418025189003", size = { 8.281, 5.198, 7.991 } }
entries["phoenix_plaza_podium_3"] =
	{ assetId = 131978647736381, meshId = "rbxassetid://83534651387040", size = { 7.907, 4.093, 7.586 } }
entries["ranch_crate"] = { assetId = 113390790867779, meshId = "rbxassetid://120918291298344", size = { 3, 3, 3 } }
entries["ranch_crate_goo"] = { assetId = 127060204046625, meshId = "rbxassetid://72755843253725", size = { 3, 3, 3 } }
entries["ranch_feed_trough"] =
	{ assetId = 122284008329780, meshId = "rbxassetid://118620263144053", size = { 5.95, 2.32, 2.509 } }
entries["ranch_hay_bale"] =
	{ assetId = 108180914521962, meshId = "rbxassetid://83011141223539", size = { 4, 2.617, 2.56 } }
entries["ranch_shed"] =
	{ assetId = 84203174193070, meshId = "rbxassetid://78762155869477", size = { 10.55, 9.33, 8.55 } }
-- 2026-10-16 upload (landing ring, goo drain, ranch props).
entries["ranch_barn_loft"] =
	{ assetId = 136936166477639, meshId = "rbxassetid://93201775446947", size = { 13.296, 11.352, 8.637 } }
entries["ranch_barrel"] =
	{ assetId = 90074882159030, meshId = "rbxassetid://112488446568714", size = { 2.536, 2.63, 2.744 } }
entries["ranch_barrel_stack"] =
	{ assetId = 90110889022780, meshId = "rbxassetid://94017107503829", size = { 5.173, 5.374, 4.675 } }
entries["ranch_bench"] =
	{ assetId = 118171478088116, meshId = "rbxassetid://90081497546543", size = { 6, 4.017, 2.376 } }
entries["ranch_birdhouse"] =
	{ assetId = 131084863003090, meshId = "rbxassetid://139996286806181", size = { 3.569, 7.99, 3.361 } }
entries["ranch_campfire"] =
	{ assetId = 88092647657367, meshId = "rbxassetid://133251157496352", size = { 4.266, 4.552, 4.253 } }
entries["ranch_compost_bin"] =
	{ assetId = 78774416660418, meshId = "rbxassetid://129045056696870", size = { 5.495, 4.802, 5.312 } }
entries["ranch_feed_sacks"] =
	{ assetId = 136919381636433, meshId = "rbxassetid://108537116109553", size = { 5.155, 3.458, 5.312 } }
entries["ranch_fence_stile"] =
	{ assetId = 109953899748949, meshId = "rbxassetid://121810118872882", size = { 4.85, 4.6, 4.1 } }
entries["ranch_flower_planter"] =
	{ assetId = 119401948136413, meshId = "rbxassetid://79181201141280", size = { 5.2, 3.191, 2 } }
entries["ranch_goo_bucket"] =
	{ assetId = 129790019317485, meshId = "rbxassetid://102042715713279", size = { 2.164, 2.816, 2.09 } }
entries["ranch_goo_drain"] =
	{ assetId = 126810189276613, meshId = "rbxassetid://104526734095121", size = { 8.8, 4.45, 9.75 } }
entries["ranch_goo_hive"] =
	{ assetId = 107632231989974, meshId = "rbxassetid://83216405009839", size = { 3.82, 5.715, 4.783 } }
entries["ranch_goo_sign"] =
	{ assetId = 77535983276457, meshId = "rbxassetid://128222132547695", size = { 8.8, 8.205, 3.746 } }
entries["ranch_hitching_post"] =
	{ assetId = 72600230488672, meshId = "rbxassetid://115907048572572", size = { 7.32, 4.815, 3.155 } }
entries["ranch_horseshoe_pit"] =
	{ assetId = 111228780556669, meshId = "rbxassetid://118739723434350", size = { 9.5, 1.8, 4.7 } }
entries["ranch_landing_ring"] =
	{ assetId = 126479458852729, meshId = "rbxassetid://84246485274936", size = { 13.145, 3.145, 10.27 } }
entries["ranch_lantern_post"] =
	{ assetId = 124004679363569, meshId = "rbxassetid://99456773451008", size = { 3.65, 9.3, 1.6 } }
entries["ranch_log_pile"] =
	{ assetId = 112182235851209, meshId = "rbxassetid://107529832767130", size = { 10.935, 4.011, 6.812 } }
-- Plot skin decor (Config.PLOT_SKINS): templates for the client, never world slots (CONTRACT.md §15).
entries["plot_skin_mushroom"] =
	{ assetId = 136516938638177, meshId = "rbxassetid://106478306368033", size = { 5.8, 6.171, 5.4 } }
entries["plot_skin_candy"] =
	{ assetId = 121061336707847, meshId = "rbxassetid://122784364834934", size = { 5.312, 6.651, 3.956 } }
entries["plot_skin_crystal"] =
	{ assetId = 114982396568572, meshId = "rbxassetid://140403985164021", size = { 4.972, 6.636, 5.238 } }
entries["ranch_mailbox"] =
	{ assetId = 123381594112643, meshId = "rbxassetid://103027857940649", size = { 1.38, 5.375, 2.72 } }
entries["ranch_milk_churn"] =
	{ assetId = 108899144560348, meshId = "rbxassetid://116671673754337", size = { 2.654, 6.092, 2.501 } }
entries["ranch_picnic_table"] =
	{ assetId = 71355911689705, meshId = "rbxassetid://71215318304529", size = { 8.12, 3.413, 5.96 } }
entries["ranch_pumpkin_patch"] =
	{ assetId = 94668742255879, meshId = "rbxassetid://72341810437307", size = { 6.483, 2.712, 6.361 } }
entries["ranch_rain_barrel"] =
	{ assetId = 91251063973173, meshId = "rbxassetid://106971241039005", size = { 3.316, 5.55, 5.458 } }
entries["ranch_scarecrow"] =
	{ assetId = 73025478213217, meshId = "rbxassetid://91953749943371", size = { 7.183, 9.028, 3.5 } }
entries["ranch_slime_coop"] =
	{ assetId = 81746564089646, meshId = "rbxassetid://136565106617929", size = { 7.4, 7.687, 7.796 } }
entries["ranch_sunflower_patch"] =
	{ assetId = 104428165124733, meshId = "rbxassetid://87297529974712", size = { 8.715, 8.758, 6.098 } }
entries["ranch_tool_rack"] =
	{ assetId = 102189689759823, meshId = "rbxassetid://130140702226639", size = { 7.7, 8.07, 3 } }
entries["ranch_wagon"] =
	{ assetId = 91242028044762, meshId = "rbxassetid://95963906904617", size = { 9.915, 3.011, 5.763 } }
entries["ranch_water_pump"] =
	{ assetId = 128284874715800, meshId = "rbxassetid://76562754886833", size = { 3.84, 4.35, 4.907 } }
entries["ranch_water_trough"] =
	{ assetId = 124856674298679, meshId = "rbxassetid://115074644334448", size = { 9.65, 3.6, 3.2 } }
entries["ranch_weathervane"] =
	{ assetId = 125246498199341, meshId = "rbxassetid://105542335148912", size = { 5.05, 8.555, 3.444 } }
entries["ranch_well"] =
	{ assetId = 128188556443255, meshId = "rbxassetid://76225156610924", size = { 6.9, 7.725, 5.511 } }
entries["ranch_wheelbarrow"] =
	{ assetId = 76889567988116, meshId = "rbxassetid://109036150127137", size = { 6.595, 3.45, 3.799 } }
entries["ranch_windmill"] =
	{ assetId = 122612940835932, meshId = "rbxassetid://120542952502577", size = { 8.382, 17.386, 9.65 } }
-- The Guide's skin (WorldProps TutorialNpc): decor only, the primitive body parts under it stay the collider.
entries["ranch_guide"] =
	{ assetId = 106088623869567, meshId = "rbxassetid://120047572318324", size = { 4.765, 7.987, 3.481 } }
entries["slime_fountain_emerge"] =
	{ assetId = 100517882708695, meshId = "rbxassetid://74501501975558", size = { 19.436, 12.798, 11.353 } }
-- World border v3 pieces (WorldBorder layers: fence/hedge inner, trees + rocks mid, hills outer): Open Cloud size-check.
entries["ranch_border_fence_straight"] =
	{ assetId = 112218798566397, meshId = "rbxassetid://103571944991059", size = { 25.623, 4.783, 2.701 } }
entries["ranch_border_fence_broken"] =
	{ assetId = 103533217929074, meshId = "rbxassetid://121373752619996", size = { 19.074, 4.888, 4.043 } }
entries["ranch_border_hedge_long"] =
	{ assetId = 83794062389872, meshId = "rbxassetid://116685603875924", size = { 24.968, 5.065, 4.92 } }
entries["ranch_border_hedge_round"] =
	{ assetId = 90045428838607, meshId = "rbxassetid://83546390836622", size = { 15.064, 5.506, 5.786 } }
entries["ranch_border_hedge_stepped"] =
	{ assetId = 105237080216235, meshId = "rbxassetid://113985027071790", size = { 21.347, 7.546, 4.909 } }
entries["ranch_border_pine_tall"] =
	{ assetId = 95807680722627, meshId = "rbxassetid://99083195396108", size = { 9.123, 24.87, 8.989 } }
entries["ranch_border_pine_broad"] =
	{ assetId = 112666291556200, meshId = "rbxassetid://84373547344968", size = { 12.347, 13.54, 12.134 } }
entries["ranch_border_pine_twin"] =
	{ assetId = 114991667389583, meshId = "rbxassetid://120168980685941", size = { 15.519, 19.72, 10.903 } }
entries["ranch_border_oak_round"] =
	{ assetId = 128068407623828, meshId = "rbxassetid://136470489381235", size = { 16.645, 16.443, 14.28 } }
entries["ranch_border_sapling_trio"] =
	{ assetId = 90720861579866, meshId = "rbxassetid://121306657581529", size = { 12.187, 9.351, 7.743 } }
entries["ranch_border_rock_boulder"] =
	{ assetId = 132240144452008, meshId = "rbxassetid://125140741014560", size = { 11.813, 6.674, 7.583 } }
entries["ranch_border_rock_slab"] =
	{ assetId = 133289868664978, meshId = "rbxassetid://85815223547935", size = { 13.767, 3.171, 6.564 } }
entries["ranch_border_rock_cluster"] =
	{ assetId = 123208953203128, meshId = "rbxassetid://109013245235520", size = { 14.179, 4.765, 9.208 } }
entries["ranch_border_rock_spire"] =
	{ assetId = 128652155245495, meshId = "rbxassetid://101473511078404", size = { 9.91, 10.517, 6.254 } }
entries["ranch_border_hill_ridge"] =
	{ assetId = 111594495650865, meshId = "rbxassetid://123304503530946", size = { 57.682, 21.673, 20 } }
entries["ranch_border_hill_dome"] =
	{ assetId = 129259673741850, meshId = "rbxassetid://131846670153688", size = { 41.736, 26.641, 29.811 } }
entries["ranch_border_hill_twin"] =
	{ assetId = 72142562438736, meshId = "rbxassetid://108674008696866", size = { 49.686, 21.282, 21.862 } }
entries["ranch_border_fence_long"] =
	{ assetId = 92527416818808, meshId = "rbxassetid://73361473495488", size = { 51.074, 5.612, 7.18 } }
entries["ranch_border_hedge_xl"] =
	{ assetId = 128259914576860, meshId = "rbxassetid://108264493248314", size = { 41.199, 6.755, 5.147 } }
entries["ranch_border_grove_pine"] =
	{ assetId = 110166328268913, meshId = "rbxassetid://132972161278608", size = { 36.498, 21.78, 15.243 } }
entries["ranch_border_grove_mixed"] =
	{ assetId = 102848305698195, meshId = "rbxassetid://119275936779741", size = { 31.183, 16.659, 15.66 } }
entries["ranch_border_grove_rocky"] =
	{ assetId = 131823405838760, meshId = "rbxassetid://73641376964456", size = { 33.409, 15.6, 12.811 } }
-- World border corner groves (WorldBorder CHUNKS): one MeshAsset slot per ~55 studs; "_m" = mirrored twin.
-- size = the probed MeshPart size (upload.py --size-check), else the kit stats.
entries["ranch_border_chunk_b"] =
	{ assetId = 71941409109721, meshId = "rbxassetid://82003799367581", size = { 56.891, 17.815, 21.716 } }
entries["ranch_border_chunk_b_m"] =
	{ assetId = 128326484353168, meshId = "rbxassetid://96881136657782", size = { 56.891, 17.815, 21.716 } }
entries["ranch_border_chunk_d"] =
	{ assetId = 137067804676236, meshId = "rbxassetid://97405969708559", size = { 55.355, 19.042, 19.384 } }
entries["ranch_border_chunk_d_m"] =
	{ assetId = 75235346512732, meshId = "rbxassetid://87662768383786", size = { 55.355, 19.042, 19.384 } }
entries["ranch_border_chunk_h"] =
	{ assetId = 73419946109730, meshId = "rbxassetid://111017472008949", size = { 53.606, 28.241, 42 } }
entries["ranch_border_chunk_h_m"] =
	{ assetId = 88966428868581, meshId = "rbxassetid://104548969463535", size = { 53.606, 28.241, 42 } }
-- Habitat overlays (Habitats.overlayMesh, HABITATS.md): rim dressing on the crate deck.
-- Sizes from the kit build (models/habitat_<id>_overlay.py), native W x H x D studs.
entries["habitat_hay_nest_overlay"] =
	{ assetId = 137655301198387, meshId = "rbxassetid://104179250569700", size = { 7.5, 1.562, 7.5 } }
entries["habitat_mushroom_ring_overlay"] =
	{ assetId = 96204622852852, meshId = "rbxassetid://125733398451227", size = { 7.5, 1.681, 7.5 } }
entries["habitat_flower_bed_overlay"] =
	{ assetId = 130689581528284, meshId = "rbxassetid://126613454986754", size = { 7.511, 1.836, 7.515 } }
entries["habitat_barn_crate_overlay"] =
	{ assetId = 118838784104356, meshId = "rbxassetid://121184718923861", size = { 7.5, 1.85, 7.5 } }
entries["habitat_rodeo_barrel_overlay"] =
	{ assetId = 139158157244798, meshId = "rbxassetid://111490220492313", size = { 7.5, 1.86, 7.5 } }
entries["habitat_syrup_pool_overlay"] =
	{ assetId = 137859014161776, meshId = "rbxassetid://139488288315701", size = { 7.586, 3.362, 7.586 } }
entries["habitat_show_stool_overlay"] =
	{ assetId = 79817145042621, meshId = "rbxassetid://79361559269361", size = { 7.5, 2.07, 7.5 } }
entries["habitat_candy_patch_overlay"] =
	{ assetId = 127018298955173, meshId = "rbxassetid://100478183132156", size = { 7.521, 1.722, 7.5 } }
entries["habitat_crystal_grotto_overlay"] =
	{ assetId = 108153474046130, meshId = "rbxassetid://73986018639306", size = { 7.5, 1.448, 7.5 } }
-- 20-stud plot fence (models/ranch_fence_20.py): Open Cloud size-check.
entries["ranch_fence_20"] =
	{ assetId = 93657150564692, meshId = "rbxassetid://90306341034018", size = { 22, 9.02, 1.8 } }
-- Per-type slime kit (SlimeLooks.kit; server SlimeMesh, NOT world slots: they are
-- cloned per slime, so they never count against WorldLayout.MESH_SLOT_BUDGET).
-- Plot vats (server MeshSwap.swapPlotVats, bug #16): stands over every plot's MergeVat disc, 1 MeshPart per plot.
-- NOT a world slot.
entries["merge_vat"] =
	{ assetId = 122090902536570, meshId = "rbxassetid://94063238729318", size = { 10.808, 7.625, 10.764 } }
-- Goo jar tower (shared/modeling-kit/models/_goo_jar.py; JarMeshes holds where each sits). Open Cloud size-check.
entries["goo_cork_stand"] =
	{ assetId = 73579765961535, meshId = "rbxassetid://118479492434509", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_glass_2"] =
	{ assetId = 99828185885518, meshId = "rbxassetid://82506489920464", size = { 8.084, 21.781, 11.371 } }
entries["goo_drop_tube_glass_3"] =
	{ assetId = 111629425406934, meshId = "rbxassetid://134072741391884", size = { 9.111, 37.781, 14.19 } }
entries["goo_drop_tube_glass_4"] =
	{ assetId = 93007991700620, meshId = "rbxassetid://123554779154481", size = { 9.966, 53.781, 16.54 } }
entries["goo_drop_tube_goo_2"] =
	{ assetId = 86160375582751, meshId = "rbxassetid://125189402569959", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3"] =
	{ assetId = 120298905383196, meshId = "rbxassetid://130227040228962", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4"] =
	{ assetId = 138133715514605, meshId = "rbxassetid://119367874672705", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_crown"] =
	{ assetId = 71380888344034, meshId = "rbxassetid://104778303876847", size = { 0.787, 0.52, 0.809 } }
entries["goo_jar_deck_2"] =
	{ assetId = 99170740533300, meshId = "rbxassetid://121583338947402", size = { 53.2, 1.789, 53.2 } }
entries["goo_jar_deck_3"] =
	{ assetId = 125659145472027, meshId = "rbxassetid://115580191005219", size = { 47.2, 1.789, 47.2 } }
entries["goo_jar_deck_4"] =
	{ assetId = 130699055260662, meshId = "rbxassetid://115829631257177", size = { 42.2, 1.73, 42.2 } }
entries["goo_jar_door"] =
	{ assetId = 139300292465170, meshId = "rbxassetid://74526508452664", size = { 11.596, 11.6, 2.6 } }
entries["goo_jar_door_ring"] =
	{ assetId = 104855077088726, meshId = "rbxassetid://85299355296782", size = { 12.898, 12.9, 0.9 } }
entries["goo_jar_foot"] =
	{ assetId = 94414503603615, meshId = "rbxassetid://124886986404874", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_glass_1_mid"] =
	{ assetId = 131865809092333, meshId = "rbxassetid://129991589789782", size = { 62.0, 14.32, 62.0 } }
entries["goo_jar_glass_1_top"] =
	{ assetId = 123313069381994, meshId = "rbxassetid://137918383953684", size = { 62.0, 20.12, 62.0 } }
entries["goo_jar_glass_2_mid"] =
	{ assetId = 94980896972924, meshId = "rbxassetid://88818373624109", size = { 54.0, 14.32, 54.0 } }
entries["goo_jar_glass_2_top"] =
	{ assetId = 136580412796651, meshId = "rbxassetid://96484483630307", size = { 54.0, 16.52, 54.0 } }
entries["goo_jar_glass_3_mid"] =
	{ assetId = 100018316137117, meshId = "rbxassetid://87246607659278", size = { 48.0, 14.32, 48.0 } }
entries["goo_jar_glass_3_top"] =
	{ assetId = 139876522959966, meshId = "rbxassetid://137628845271462", size = { 48.0, 16.52, 48.0 } }
entries["goo_jar_glass_4_top"] =
	{ assetId = 77025236169848, meshId = "rbxassetid://127663980321662", size = { 43.0, 16.52, 43.0 } }
entries["goo_jar_mascot"] =
	{ assetId = 98686118721094, meshId = "rbxassetid://71405131358303", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_stair"] =
	{ assetId = 98196001176088, meshId = "rbxassetid://86738719353582", size = { 10.99, 16.853, 10.995 } }
entries["goo_jar_stopper"] =
	{ assetId = 121171735307209, meshId = "rbxassetid://98488330645221", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid"] =
	{ assetId = 125609985796662, meshId = "rbxassetid://130215893669639", size = { 60.321, 16.05, 58.307 } }
entries["goo_jar_trim_1_top"] =
	{ assetId = 81111284959159, meshId = "rbxassetid://125794987301481", size = { 60.321, 22.688, 58.307 } }
entries["goo_jar_trim_2_mid"] =
	{ assetId = 98169175981967, meshId = "rbxassetid://108375268575125", size = { 53.091, 16.05, 50.916 } }
entries["goo_jar_trim_2_top"] =
	{ assetId = 121872413785229, meshId = "rbxassetid://72836074236220", size = { 53.091, 19.247, 50.916 } }
entries["goo_jar_trim_3_mid"] =
	{ assetId = 119020744731896, meshId = "rbxassetid://103107135493684", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top"] =
	{ assetId = 115479272829253, meshId = "rbxassetid://75683994927695", size = { 47.314, 19.412, 45.373 } }
entries["goo_jar_trim_4_top"] =
	{ assetId = 118248174951144, meshId = "rbxassetid://96346362080902", size = { 41.082, 17.988, 40.753 } }
entries["goo_lock_button"] =
	{ assetId = 132032016681033, meshId = "rbxassetid://140087463794943", size = { 5.0, 3.966, 5.0 } }
-- Border v5 giant trees (WorldBorder.giants; 3-5x the border pines, MeshPart.Color tints the canopy). Open Cloud size-check.
entries["giant_broadleaf"] =
	{ assetId = 114689108547101, meshId = "rbxassetid://115148865966963", size = { 80.613, 78.349, 65.201 } }
entries["giant_pine_layered"] =
	{ assetId = 82697384730576, meshId = "rbxassetid://131926496841871", size = { 37.327, 86.67, 35.962 } }
entries["giant_round_canopy"] =
	{ assetId = 123353571589135, meshId = "rbxassetid://81542465151090", size = { 52.846, 80.09, 51.819 } }
-- Border v6 giants (even bigger: 100-160 studs native). Open Cloud size-check.
entries["giant_elder_oak"] =
	{ assetId = 81330795778397, meshId = "rbxassetid://132728423157389", size = { 159.376, 102.581, 132.423 } }
entries["giant_sequoia_spire"] =
	{ assetId = 116609891922407, meshId = "rbxassetid://104415065733160", size = { 53.52, 157.248, 54.788 } }
entries["giant_cloud_tree"] =
	{ assetId = 75166170200061, meshId = "rbxassetid://71113886018536", size = { 122.958, 126.341, 69.744 } }
-- Default melee Bat (Tool 'Bat', held, no collision: not in MeshAssets.COLLISION; NOT a world slot).
-- Mesh stands upright, pommel at the bottom (long axis Y). Tool.Grip for the Handle = CFrame.new(0, -1.345, 0)
-- (the red wrap centre, 1.2 above the pommel; mesh centre = bbox centre). 606 tris. models/ranch_bat.py.
entries["ranch_bat"] =
	{ assetId = 111246965997524, meshId = "rbxassetid://94306599639554", size = { 1.351, 5.09, 1.351 } }

-- Held PvP items (Shared.PvpModels, server/PvpHeld; a placed Goo Trap / Bounce Pad marker too, ui/PvpEffects).
-- Held, no collision (not in COLLISION), NOT world slots. size = the native size Roblox reports (Open Cloud size-check);
-- grips and orientation are in PvpModels.
entries["pvp_knock_glove_1"] =
	{ assetId = 110621726072655, meshId = "rbxassetid://71737885567877", size = { 1.635, 2.014, 1.405 } }
entries["pvp_knock_glove_2"] =
	{ assetId = 80334698499483, meshId = "rbxassetid://77260240652660", size = { 1.637, 2.214, 1.4 } }
entries["pvp_knock_glove_3"] =
	{ assetId = 132366088078656, meshId = "rbxassetid://106383629055084", size = { 2.277, 2.247, 1.84 } }
entries["pvp_knock_glove_4"] =
	{ assetId = 135418730632918, meshId = "rbxassetid://78867127184009", size = { 2.729, 2.604, 1.746 } }
entries["pvp_knock_glove_5"] =
	{ assetId = 120579710964122, meshId = "rbxassetid://75411549772769", size = { 1.973, 2.779, 1.979 } }
entries["pvp_goo_trap_1"] =
	{ assetId = 83895249562133, meshId = "rbxassetid://83180176668437", size = { 3.786, 0.836, 3.188 } }
entries["pvp_goo_trap_2"] =
	{ assetId = 116867489683181, meshId = "rbxassetid://117211964777374", size = { 3.626, 0.984, 3.686 } }
entries["pvp_goo_trap_3"] =
	{ assetId = 128824082093246, meshId = "rbxassetid://108663580351164", size = { 3.68, 1.003, 4.107 } }
entries["pvp_goo_blaster_1"] =
	{ assetId = 105327335446583, meshId = "rbxassetid://86172948277407", size = { 0.72, 2.383, 2.55 } }
entries["pvp_goo_blaster_2"] =
	{ assetId = 96662953983125, meshId = "rbxassetid://131920181581288", size = { 1.279, 2.769, 3.28 } }
entries["pvp_goo_blaster_3"] =
	{ assetId = 85444473478925, meshId = "rbxassetid://94914692256376", size = { 1.32, 2.902, 4.171 } }
entries["pvp_fun_confetti"] =
	{ assetId = 122751045559627, meshId = "rbxassetid://130187699965534", size = { 1.521, 3.031, 1.518 } }
entries["pvp_fun_balloon"] =
	{ assetId = 123184486250639, meshId = "rbxassetid://137566643890332", size = { 1.3, 1.57, 1.3 } }
entries["pvp_fun_bubbles"] =
	{ assetId = 100059116789802, meshId = "rbxassetid://95807555526303", size = { 1.267, 3.52, 0.86 } }
entries["pvp_fun_bounce_pad"] =
	{ assetId = 79473190619711, meshId = "rbxassetid://122940558174082", size = { 3, 0.913, 3 } }
entries["pvp_fun_squeaky"] =
	{ assetId = 70595131801050, meshId = "rbxassetid://80237357927975", size = { 2, 3.27, 1.44 } }
entries["pvp_fun_hat_launcher"] =
	{ assetId = 74305371572035, meshId = "rbxassetid://124667953574111", size = { 1.16, 1.944, 2.74 } }
entries["pvp_fun_dance_bomb"] =
	{ assetId = 127767437569765, meshId = "rbxassetid://128407491632382", size = { 1.485, 2.518, 1.462 } }
entries["pvp_fun_fireworks"] =
	{ assetId = 76466741614439, meshId = "rbxassetid://99068800603377", size = { 1.04, 1.678, 3.145 } }

-- B11 floor (FloorLayout, concept c3): hub-centred, 8-fold symmetric baked boardwalk meshes (models/ranch_floor_deck.py,
-- ranch_floor_paths.py). One world slot each at the hub (Map.Paths.DeckPlaza / Boardwalk); decor, no collision.
entries["ranch_floor_deck"] =
	{ assetId = 133184278728331, meshId = "rbxassetid://134304234441487", size = { 131.2, 0.21, 131.2 } }
entries["ranch_floor_paths"] =
	{ assetId = 87043105060649, meshId = "rbxassetid://120582459397748", size = { 192, 0.21, 192 } }
-- Follow pet cloud (models/pet_cloud.py, 1800 tris): a soft smooth-shaded cloud under the favourite slime's clone. Decor, no
-- collision (not in COLLISION); MeshSwap.publishPetCloudTemplate publishes it, the client FollowPets clones it per follower, NOT a world slot. Uploaded 2026-10-18, v2 (smooth) 2026-10-19.
entries["pet_cloud"] =
	{ assetId = 76853347194916, meshId = "rbxassetid://131511097265313", size = { 3.261, 1.225, 2.393 } }
-- Mystery Egg shells and nest (contract/mystery-egg.md): not map slots, so not in NAMES; WorldView loads them by name.
entries["mystery_egg_speckled"] =
	{ assetId = 72448883434671, meshId = "rbxassetid://78500797880978", size = { 1.727, 2.2, 1.714 } }
entries["mystery_egg_shiny"] =
	{ assetId = 89189893144899, meshId = "rbxassetid://120597976593446", size = { 1.923, 2.2, 1.93 } }
entries["mystery_egg_golden"] =
	{ assetId = 124740474802680, meshId = "rbxassetid://79281704120835", size = { 1.858, 2.2, 1.96 } }
entries["mystery_egg_cosmic"] =
	{ assetId = 83469811451722, meshId = "rbxassetid://127150041778047", size = { 1.809, 2.2, 1.792 } }
entries["mystery_egg_nest"] =
	{ assetId = 104020921300950, meshId = "rbxassetid://110322947252445", size = { 3.416, 0.903, 3.416 } }

-- The goo parade lane as ONE curved mesh (models/slime_lane.py, bug 4): not a WorldLayout slot (ParadeView lays
-- it at ParadeLane.MESH_PIVOT). ParadeView swaps the ParadeLane.strips() stand-ins for it once it loads (they stay
-- only if it fails to load). size = out/slime_lane_pivot.json "size".
entries["slime_lane"] =
	{ assetId = 87473643950432, meshId = "rbxassetid://115422391363157", size = { 142.599, 0.43, 139.246 } }

-- FEATURES.FountainSplit (default off; MeshSwap.swapFountainSplit): the slime_fountain mesh cut into 5 pieces by
-- shared/modeling-kit/models/slime_fountain_split.py (out/fountain_split.json has the numbers, tris sum to the whole:
-- 6354). NOT world slots: with the flag off nothing loads them. The four
-- tower pieces are PreciseConvexDecomposition (COLLISION below); the slide piece is PCD only with FEATURES.SlidePCD, else decor.
entries["fountain_split_basin"] = {
	assetId = 113404417037788,
	meshId = "rbxassetid://108371724846314",
	size = { 20.983, 8.123, 22.051 },
	offset = { -6.236, 17.597, -7.119 },
}
entries["fountain_split_dome"] = {
	assetId = 90481723961412,
	meshId = "rbxassetid://96453427876668",
	size = { 27.201, 6.29, 27.312 },
	offset = { -6.321, 11.747, -7.498 },
}
entries["fountain_split_eave"] = {
	assetId = 89581694162701,
	meshId = "rbxassetid://79010101239145",
	size = { 27.201, 3.313, 27.312 },
	offset = { -6.321, 9.374, -7.498 },
}
entries["fountain_split_silo"] = {
	assetId = 70694440108004,
	meshId = "rbxassetid://124837877209980",
	size = { 26.223, 30.673, 26.563 },
	offset = { -6.51, -6.321, -7.572 },
}
entries["fountain_split_slide"] = {
	assetId = 80263316335801,
	meshId = "rbxassetid://133681442583514",
	size = { 54.45, 38.242, 63.851 },
	offset = { 0, -2.537, 0 },
}

-- Slime pool species (contract/slime-pool.md, SlimeLooks kit "slime_<id>"): rigged, fully coloured
-- Models from shared/modeling-kit/models/pool, worn by server SlimeMesh, never world slots (not in
-- NAMES). size = native size of a size-1 slime; offset = bbox centre minus the slime's bottom centre.
entries["slime_gummy"] = { assetId = 109275905134159, size = { 3.008, 2.95, 3.041 }, offset = { 0, 1.475, -0.016 } }
entries["slime_mochi"] = { assetId = 88468109163483, size = { 3.339, 2.159, 3.116 }, offset = { -0, 1.079, -0.01 } }
entries["slime_bubbles"] = { assetId = 136117360920606, size = { 3.299, 3.86, 3.47 }, offset = { -0.1, 1.93, -0.185 } }
entries["slime_pebble"] =
	{ assetId = 124134851993528, size = { 3.219, 2.823, 3.223 }, offset = { 0.032, 1.412, -0.003 } }
entries["slime_sprout"] = { assetId = 95596092652471, size = { 2.783, 4.029, 2.987 }, offset = { 0, 2.014, -0.029 } }
entries["slime_cheddar"] =
	{ assetId = 104100743814476, size = { 2.907, 2.543, 2.914 }, offset = { 0.005, 1.272, -0.009 } }
entries["slime_bumble"] = { assetId = 140176590528302, size = { 3.141, 3.9, 4.131 }, offset = { 0, 1.95, 0.392 } }
entries["slime_mushie"] = { assetId = 117092813936490, size = { 4.16, 3.487, 4.16 }, offset = { 0, 1.743, -0 } }
entries["slime_prickles"] =
	{ assetId = 128744905531044, size = { 4.864, 3.799, 3.05 }, offset = { -0.004, 1.899, 0.032 } }
entries["slime_froggo"] = { assetId = 71274428079528, size = { 3.698, 2.684, 3.113 }, offset = { 0, 1.311, -0.046 } }
entries["slime_flan"] = { assetId = 89380442384228, size = { 3.156, 3.97, 3.136 }, offset = { 0.004, 1.985, 0.013 } }
entries["slime_chomp"] = { assetId = 95926102417193, size = { 4.568, 3.62, 4.121 }, offset = { 0, 1.81, 0.368 } }
entries["slime_whiskers"] =
	{ assetId = 133896172858214, size = { 4.173, 3.003, 3.297 }, offset = { -0.36, 1.501, -0.019 } }
entries["slime_lop"] = { assetId = 107798862734190, size = { 3.541, 3.616, 3.447 }, offset = { 0.001, 1.808, 0.203 } }
entries["slime_moo"] = { assetId = 120951185287411, size = { 3.935, 2.915, 3.633 }, offset = { 0, 1.457, -0.115 } }
entries["slime_pengoo"] = { assetId = 96963913146270, size = { 4.596, 3.9, 3.2 }, offset = { 0, 1.947, -0.156 } }
entries["slime_blaze"] = { assetId = 136135987150514, size = { 3.36, 4.938, 3.159 }, offset = { -0.01, 2.469, -0.023 } }
entries["slime_frostbite"] =
	{ assetId = 137039779756480, size = { 3.165, 3.904, 3.207 }, offset = { 0, 1.952, -0.021 } }
entries["slime_zap"] = { assetId = 80334558020467, size = { 4.078, 3.688, 3.418 }, offset = { 0, 1.844, -0.003 } }
entries["slime_imp"] = { assetId = 84166464527451, size = { 4.596, 3.491, 3.884 }, offset = { 0, 1.746, 0.443 } }
entries["slime_octo"] = { assetId = 121886155113536, size = { 5.058, 3.495, 4.192 }, offset = { 0, 1.673, -0.141 } }
entries["slime_drako"] = { assetId = 85981669582151, size = { 4.194, 3.272, 3.993 }, offset = { 0, 1.636, 0.327 } }
entries["slime_king"] = { assetId = 108773001876450, size = { 3.783, 3.812, 3.378 }, offset = { 0, 1.874, 0.093 } }
entries["slime_ninja"] = { assetId = 99942777828950, size = { 3.747, 3.08, 3.861 }, offset = { 0.085, 1.54, 0.45 } }
entries["slime_robo"] = { assetId = 74626917754091, size = { 3.946, 4.16, 3.679 }, offset = { 0, 2.08, 0.321 } }
entries["slime_cosmo"] = { assetId = 113712257623051, size = { 5.109, 3.66, 4.972 }, offset = { 0, 1.83, -0 } }
entries["slime_seraph"] = { assetId = 130685970099047, size = { 5.92, 3.946, 2.966 }, offset = { 0, 1.973, -0.011 } }
entries["slime_amethyst"] =
	{ assetId = 120514076751923, size = { 4.851, 4.732, 4.11 }, offset = { -0.098, 2.243, 0.392 } }
entries["slime_prism"] = { assetId = 97296414747568, size = { 4.266, 4.392, 4.155 }, offset = { -0.001, 2.005, 0.137 } }
entries["slime_midas"] = { assetId = 84348651618165, size = { 3.895, 3.51, 3.729 }, offset = { 0.035, 1.665, 0.022 } }
entries["slime_eclipse"] =
	{ assetId = 73912580635466, size = { 4.872, 4.374, 3.446 }, offset = { 0.039, 2.114, 0.089 } }
entries["slime_boo"] = { assetId = 96310373601330, size = { 4.198, 3.849, 2.926 }, offset = { 0.015, 1.846, -0.002 } }

entries["slime_soda"] = { assetId = 95888248190580, size = { 3.602, 4.483, 3.085 }, offset = { -0.08, 2.242, -0.023 } }
entries["slime_rocky_road"] =
	{ assetId = 74244309584071, size = { 3.137, 3.518, 3.138 }, offset = { 0.009, 1.759, 0.004 } }
entries["slime_bloom"] = { assetId = 99167270842330, size = { 4.607, 3.658, 4.751 }, offset = { 0, 1.829, -0.092 } }
entries["slime_honey_toad"] = { assetId = 76639819710103, size = { 3.698, 2.903, 3.181 }, offset = { 0, 1.42, -0.012 } }
entries["slime_truffle"] =
	{ assetId = 107050144207287, size = { 3.813, 5.14, 3.734 }, offset = { -0.004, 2.57, 0.033 } }
entries["slime_sushi"] = { assetId = 79864638354637, size = { 3.734, 3.746, 3.506 }, offset = { -0.201, 1.873, 0.326 } }
entries["slime_snow_bunny"] = { assetId = 122177895345867, size = { 3.482, 4.842, 3.482 }, offset = { 0, 2.376, -0 } }
entries["slime_moo_shroom"] =
	{ assetId = 110396997416743, size = { 3.993, 3.467, 3.882 }, offset = { 0, 1.734, -0.021 } }
entries["slime_catfish"] = { assetId = 76770603623417, size = { 4.699, 3.573, 4.43 }, offset = { 0, 1.764, 0.481 } }
entries["slime_steam"] = { assetId = 107367947074628, size = { 4.794, 4.72, 3.279 }, offset = { 0, 2.36, -0.013 } }
entries["slime_kraken"] =
	{ assetId = 70503828098080, size = { 5.49, 4.449, 4.185 }, offset = { -0.025, 2.215, -0.041 } }
entries["slime_thunderbee"] =
	{ assetId = 131233135861150, size = { 4.66, 4.321, 4.21 }, offset = { -0.03, 2.16, 0.376 } }
entries["slime_cyber_ninja"] =
	{ assetId = 116106560463464, size = { 3.697, 3.63, 4.006 }, offset = { -0.04, 1.815, 0.441 } }
entries["slime_dragon_king"] =
	{ assetId = 88961374433419, size = { 5.566, 4.129, 4.424 }, offset = { 0, 2.065, 0.301 } }
entries["slime_nightwing"] =
	{ assetId = 112164365401063, size = { 6.262, 4.163, 3.798 }, offset = { 0.036, 2.081, 0.38 } }
entries["slime_goozilla"] = { assetId = 95597031533993, size = { 3.204, 3.927, 5.049 }, offset = { 0, 1.907, 0.617 } }
entries["slime_queen_jelly"] =
	{ assetId = 108716301261458, size = { 4.401, 4.653, 4.403 }, offset = { -0.032, 2.337, 0.024 } }
entries["slime_mecha_goo"] = { assetId = 78640546070601, size = { 4.48, 3.5, 3.579 }, offset = { 0, 1.75, 0.091 } }
entries["slime_glitch"] =
	{ assetId = 112653965607800, size = { 5.349, 4.23, 3.122 }, offset = { -0.037, 2.115, -0.011 } }
entries["slime_doodle"] = { assetId = 74559390612314, size = { 4.192, 4.199, 3.276 }, offset = { 0, 2.025, -0.041 } }
entries["slime_origami"] = { assetId = 102661066928788, size = { 6.542, 4.521, 4.442 }, offset = { 0, 2.261, 0.608 } }
entries["slime_disco"] = { assetId = 89692353422465, size = { 5.368, 3.97, 3.485 }, offset = { -0.095, 1.985, -0.054 } }
entries["slime_isle"] = { assetId = 106246529336627, size = { 4.667, 5.736, 3.95 }, offset = { 0.055, 2.818, 0.298 } }
entries["slime_chrono"] = { assetId = 80629324297687, size = { 4.982, 4.791, 3.6 }, offset = { 0.013, 2.355, -0 } }
entries["slime_kitsune"] = { assetId = 129157153377304, size = { 7.571, 5.424, 3.51 }, offset = { -0, 2.712, 0.216 } }

local MeshAssets = {}
MeshAssets.NAMES = table.freeze(NAMES)
MeshAssets.entries = entries

-- The FEATURES.FountainSplit pieces, in the order MeshSwap places them; the first four collide (PCD), the slide only with
-- FEATURES.SlidePCD (MeshSwap.splitFidelity), else it is decor.
MeshAssets.FOUNTAIN_SPLIT = table.freeze({
	"fountain_split_basin",
	"fountain_split_dome",
	"fountain_split_eave",
	"fountain_split_silo",
	"fountain_split_slide",
})

-- Yaw (degrees) MeshSwap adds to a mesh in a WorldLayout slot. WorldLayout
-- lays slots out with the kit's documented axes (FBX Lcl Rotation: Roblox
-- (X, Y, Z) = (kit x, kit z, -kit y), so a kit front at -Y faces slot +Z),
-- but the uploaded meshes come into Roblox turned 180 about Y from that:
-- the v28 playtest (live v27) showed the camp bench's back to its campfire,
-- the plot name text on the back of the gate's sign, the shop stall opening
-- away from its Props front and the fountain silo ~20 studs off the map
-- centre (its axis is off the mesh's bbox centre, so the turn moves it).
-- MeshSize models (WorldProps skins) already expect that import front (-Z)
-- and take no turn.
MeshAssets.IMPORT_YAW = 180

-- Slime rig animations (KeyframeSequences from animations/*.rbxmx, uploaded as
-- Animation assets; ids in shared/modeling-kit/uploaded.json). A nil / missing
-- id keeps SlimeLife's procedural idle. SlimeBlink is not authored.
MeshAssets.ANIMATIONS = table.freeze({
	SlimeIdleSquish = 84521119840854,
	SlimeHop = 115750614378002,
	SlimeLookLeft = 92824733933660,
	SlimeLookRight = 128985562979073,
} :: { [string]: number })

-- "rbxassetid://<id>" for an animation, or nil while it isn't uploaded.
function MeshAssets.animationId(name: string): string?
	local id = MeshAssets.ANIMATIONS[name]
	return if id then `rbxassetid://{id}` else nil
end

-- Meshes players must not stand inside: name -> Enum.CollisionFidelity name. MeshSwap passes it to
-- CreateMeshPartAsync (the only place it sticks on a script-made MeshPart) and turns CanCollide on.
-- Every other mesh is decor: CanCollide off. Why each: docs/COLLISION.md.
MeshAssets.COLLISION = table.freeze({
	-- the big slimes stacked at the fountain top (Merijn #10): a solid pile, so its bounding Box: nobody stands in the
	-- gaps and the top is flat enough to stand on (a Hull of the lumpy pile was not). Overlaps are ejected by
	-- server/StackGuard; the slide block and the anchored, non-colliding ride are unaffected
	slime_fountain_emerge = "Box",
	-- bug #16: every plot's merge vat (MeshSwap.swapPlotVats): a blobby cauldron players bump into, never walk inside;
	-- the hull also closes the gaps under the funnel spouts. The MergeVat disc under it keeps its own collision.
	merge_vat = "Hull",
	-- the shop stands (CONTRACT.md §27.2): a solid counter, not a box to stand inside. ranch_shop_stand is the single
	-- ShopStand (FEATURES.WorldShops off), ranch_item_shop / ranch_upgrade_cabinet the Item / Upgrade Shop stands
	ranch_shop_stand = "Hull",
	ranch_item_shop = "Hull",
	ranch_upgrade_cabinet = "Hull",

	-- Bug #11 part 1 (docs/COLLISION.md "Conversions"): one line of reason per mesh. Everything not listed here
	-- is decor (see the same doc for why each stays off).

	-- fences and posts: Box = the whole panel, so the plot's invisible Wall* colliders are no longer needed
	ranch_fence_20 = "Box", -- 22x9x1.8 panel, a flat wall of pickets: the bbox is the wall (replaces WallBack/Left/Right/FrontL/FrontR)
	phoenix_fence_segment = "Box", -- 11x9x1.8 half panel beside the gate: same flat wall
	phoenix_corner_post = "Box", -- 2.8x9.7x2.8 square post closing the fence run at the gate's right stub
	-- plaza showpieces
	ranch_plaza_signpost = "Box", -- sign boards on posts, 12.6x14.5x7.5; the old invisible slot box was this bbox
	phoenix_plaza_podium_1 = "Box", -- stepped block podium, players and rigs stand on its flat top
	phoenix_plaza_podium_2 = "Box", -- same as podium_1
	phoenix_plaza_podium_3 = "Box", -- same as podium_1
	-- boxy ranch props
	ranch_crate = "Box", -- 3x3x3 cube
	ranch_crate_goo = "Box", -- 3x3x3 cube
	ranch_feed_trough = "Box", -- 6x2.3x2.5 low box, nobody walks inside
	ranch_hay_bale = "Box", -- 4x2.6x2.6 bale
	ranch_bench = "Box", -- 6x4x2.4 bench with a back
	ranch_compost_bin = "Box", -- 5.5x4.8x5.3 slatted bin
	ranch_flower_planter = "Box", -- 5.2x3.2x2 planter box
	ranch_goo_sign = "Box", -- 8.8x8.2x3.7 signboard
	ranch_hitching_post = "Box", -- 7.3x4.8x3.2 rail between posts
	ranch_mailbox = "Box", -- 1.4x5.4x2.7 box on a post
	ranch_picnic_table = "Box", -- 8.1x3.4x6 table with benches
	ranch_tool_rack = "Box", -- 7.7x8x3 rack of tools, a flat wall
	ranch_wagon = "Box", -- 9.9x3x5.8 cart, flat bed to stand on
	ranch_water_trough = "Box", -- 9.7x3.6x3.2 low box
	-- blobby and roofed ranch props: Hull
	ranch_barrel = "Box", -- 2.5x2.6x2.7 barrel: a box fits the near-cylinder and has flat faces a walker stops against (v196: a round hull let pushes slide round it)
	ranch_barrel_stack = "Hull", -- 5.2x5.4x4.7 pyramid of barrels
	ranch_birdhouse = "Hull", -- 3.6x8x3.4 house on a pole
	ranch_campfire = "Hull", -- 4.3x4.6x4.3 stone ring and logs
	ranch_feed_sacks = "Hull", -- 5.2x3.5x5.3 pile of sacks
	ranch_goo_bucket = "Hull", -- 2.2x2.8x2.1 bucket
	ranch_goo_hive = "Hull", -- 3.8x5.7x4.8 dome
	ranch_lantern_post = "Hull", -- 3.7x9.3x1.6 post with a lantern arm: the hull is the post, the arm hangs overhead
	ranch_log_pile = "Hull", -- 10.9x4x6.8 stacked logs
	ranch_milk_churn = "Hull", -- 2.7x6.1x2.5 churn
	ranch_rain_barrel = "Hull", -- 3.3x5.6x5.5 barrel with a pipe
	ranch_scarecrow = "Hull", -- 7.2x9x3.5 pole with arms: the hull tapers up to them, nobody walks through the pole
	ranch_shed = "Hull", -- 10.6x9.3x8.6 gabled shed: the hull follows the roof, Box would leave invisible corners
	ranch_slime_coop = "Hull", -- 7.4x7.7x7.8 gabled coop
	ranch_water_pump = "Hull", -- 3.8x4.4x4.9 pump
	ranch_weathervane = "Hull", -- 5x8.6x3.4 vane on a pole
	ranch_well = "Box", -- 6.9x7.7x5.5 stone well with a roof: nobody falls into or walks under it; the box is the ring + roof footprint (v196: Hull let pushes slide round)
	ranch_wheelbarrow = "Hull", -- 6.6x3.5x3.8 wheelbarrow
	ranch_windmill = "Hull", -- 8.4x17.4x9.7 tower: the hull is the tower, the sails are overhead
	-- walkable concave shapes: PreciseConvexDecomposition (expensive; placed a few times at most). The stile is Box since v196.
	ranch_fence_stile = "Box", -- 5.8x5.5x4.9 stile: a solid block players jump onto / over (v196: PCD treads let a 4-stud ball ride over and read as walk-through)
	ranch_barn_loft = "PreciseConvexDecomposition", -- PCD: Phoenix Studio check. Loft platform with an open ground floor: walk under and onto it
	-- FEATURES.FountainSplit (default off): the fountain tower as 4 meshes, each its own convex decomposition, in place of
	-- the hand-placed Basin / Trim / Silo / Top colliders. Only created with the flag on; fountain_split_slide is decor
	-- (the slide stays the SlideColliders block, a precise slide would make the trough walkable: bug #9).
	fountain_split_basin = "PreciseConvexDecomposition",
	fountain_split_dome = "PreciseConvexDecomposition",
	fountain_split_eave = "PreciseConvexDecomposition",
	fountain_split_silo = "PreciseConvexDecomposition",
	-- FEATURES.SlidePCD: the slide with real collision (trough walls, posts, braces). MeshSwap only asks for it with the flag on;
	-- the SlideColliders floor slabs, rails and Skirt stay (the walk surface, docs/COLLISION.md).
	fountain_split_slide = "PreciseConvexDecomposition",
})

function MeshAssets.collision(name: string): string?
	return MeshAssets.COLLISION[name]
end

function MeshAssets.get(name: string): Entry?
	return entries[name]
end

-- The rbxassetid string for `name`, or nil while it isn't uploaded.
function MeshAssets.meshId(name: string): string?
	local e = entries[name]
	return e and e.meshId
end

-- Uniform fit of `name` into a box: the largest native size x one scale that
-- fits inside `box` (keeps the mesh's proportions), and how far the box
-- centre sits above the mesh centre when the mesh stands on the box bottom.
-- Without a native size the box is used as is (scale nil).
function MeshAssets.fit(name: string, box: { number }): ({ number }, number?, number)
	local e = entries[name]
	local native = e and e.size
	if not native then
		return { box[1], box[2], box[3] }, nil, 0
	end
	local scale = math.min(box[1] / native[1], box[2] / native[2], box[3] / native[3])
	local size = { native[1] * scale, native[2] * scale, native[3] * scale }
	return size, scale, (box[2] - size[2]) / 2
end

return MeshAssets
