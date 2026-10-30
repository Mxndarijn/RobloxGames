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
	"ranch_item_shop",
	"ranch_upgrade_cabinet",
	"exclusive_jar_boutique",
	"exclusive_jar_boutique_glass",
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
	"guide_professor",
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
	"plot_skin_fairground",
	"plot_skin_beach",
	"plot_skin_space",
	"plot_skin_winter",
	"plot_skin_haunted",
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
	"bat_skin_lollipop",
	"bat_skin_fish",
	"bat_skin_foam_finger",
	"bat_skin_golden",
	"ranch_floor_deck",
	"ranch_floor_paths",
	"pet_cloud",
	"pet_mount_jelly",
	"pet_mount_rainbow_cloud",
	"pet_mount_storm_cloud",
	"pet_mount_sunset_cloud",
	"pet_mount_ice_cloud",
	"pet_mount_flame_cloud",
	"pet_mount_leaf",
	"pet_mount_bubble",
	"pet_mount_lily_pad",
	"pet_mount_mushroom",
	"pet_mount_pancakes",
	"pet_mount_star_cushion",
	"pet_mount_crescent_moon",
	"pet_mount_magic_carpet",
	"pet_mount_ufo",
	"pet_mount_royal_cushion",
	"pet_mount_hoverboard",
	"pet_mount_clam_shell",
	"pet_mount_pumpkin",
	"pet_mount_snowglobe",
	"slime_hat_party",
	"slime_hat_bow",
	"slime_hat_chef",
	"slime_hat_flower_crown",
	"slime_hat_top_hat",
	"slime_hat_witch",
	"lock_stopper_candy",
	"lock_stopper_carousel",
	"lock_stopper_sleepy",
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
-- Version 2 of the asset (2026-10-29) drops the red title strip that showed through the boards' SurfaceGui.
entries["phoenix_top_earners_board"] =
	{ assetId = 126155085567089, meshId = "rbxassetid://77180258500694", size = { 21.103, 19.934, 4.097 } }
entries["ranch_plaza_signpost"] =
	{ assetId = 131934867179344, meshId = "rbxassetid://73448923703025", size = { 12.648, 14.515, 7.55 } }
entries["ranch_item_shop"] =
	{ assetId = 105082858859876, meshId = "rbxassetid://135059318016634", size = { 15.391, 16.558, 8.15 } }
entries["ranch_upgrade_cabinet"] =
	{ assetId = 112507254723244, meshId = "rbxassetid://139845226619480", size = { 16.407, 15.29, 9.93 } }
-- The Exclusive Shop's Golden Jar Boutique (contract/exclusive-shop.md §7;
-- models/exclusive_jar_boutique.py split in two): the solid shop (plinth, goo dome, lid, trophy slime, pedestals, shop
-- front, awning, sign board) and the see-through jar wall. Not uploaded yet: no id, so the stand's primitive jar shows.
entries["exclusive_jar_boutique"] =
	{ assetId = 131532129772503, meshId = "rbxassetid://102127887082736", size = { 16.86, 20.631, 18.57 } }
entries["exclusive_jar_boutique_glass"] =
	{ assetId = 92353179686979, meshId = "rbxassetid://99607808704355", size = { 12.8, 10.5, 12.8 } }
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
-- Professor Goo, the Hall of Fame greeter (WorldProps ProfessorGoo): decor only, his block body stays the collider.
entries["guide_professor"] =
	{ assetId = 125660278107523, meshId = "rbxassetid://94250583088999", size = { 3.719, 7.056, 2.98 } }
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
	{ assetId = 122090902536570, meshId = "rbxassetid://90518138029994", size = { 10.808, 7.115, 10.764 } }
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
	{ assetId = 99170740533300, meshId = "rbxassetid://100488223357881", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3"] =
	{ assetId = 125659145472027, meshId = "rbxassetid://81165650693043", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4"] =
	{ assetId = 130699055260662, meshId = "rbxassetid://114079768078263", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door"] =
	{ assetId = 139300292465170, meshId = "rbxassetid://98914647327097", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_door_ring"] =
	{ assetId = 104855077088726, meshId = "rbxassetid://85299355296782", size = { 12.898, 12.9, 0.9 } }
entries["goo_jar_foot"] =
	{ assetId = 94414503603615, meshId = "rbxassetid://140666745822680", size = { 80.1, 2.076, 80.1 } }
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
	{ assetId = 98196001176088, meshId = "rbxassetid://88590636410277", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper"] =
	{ assetId = 121171735307209, meshId = "rbxassetid://98488330645221", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid"] =
	{ assetId = 125609985796662, meshId = "rbxassetid://82635741539209", size = { 60.321, 16.05, 58.307 } }
entries["goo_jar_trim_1_top"] =
	{ assetId = 81111284959159, meshId = "rbxassetid://84276978768660", size = { 60.321, 22.688, 58.307 } }
entries["goo_jar_trim_2_mid"] =
	{ assetId = 98169175981967, meshId = "rbxassetid://108791104087374", size = { 53.091, 16.05, 50.916 } }
entries["goo_jar_trim_2_top"] =
	{ assetId = 121872413785229, meshId = "rbxassetid://97994730612519", size = { 53.091, 20.047, 50.916 } }
entries["goo_jar_trim_3_mid"] =
	{ assetId = 119020744731896, meshId = "rbxassetid://117539065467529", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top"] =
	{ assetId = 115479272829253, meshId = "rbxassetid://95516527570113", size = { 47.314, 20.212, 45.373 } }
entries["goo_jar_trim_4_top"] =
	{ assetId = 118248174951144, meshId = "rbxassetid://103522673261170", size = { 41.082, 18.788, 40.753 } }
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
-- Bat skins (contract/exclusive-shop.md §10, Config.EXCLUSIVE_SHOP.batSkins): other meshes for the same Handle, held
-- with ranch_bat's Grip (each is 5.09 tall, grip 1.2 above the bottom, bbox centred on the grip axis). Held, no
-- collision, NOT world slots. Not uploaded yet: no ids, so the Handle keeps the default Bat. size = kit bbox (studs).
-- models/bat_skin_<id>.py.
entries["bat_skin_lollipop"] =
	{ assetId = 94349711264908, meshId = "rbxassetid://125426334354361", size = { 2.079, 5.09, 0.76 } } -- 808 tris
entries["bat_skin_fish"] =
	{ assetId = 131245947199367, meshId = "rbxassetid://77117254245604", size = { 1.992, 5.089, 1.074 } } -- 740 tris
entries["bat_skin_foam_finger"] =
	{ assetId = 135901471533511, meshId = "rbxassetid://103574945844021", size = { 1.5, 5.09, 0.955 } } -- 808 tris
entries["bat_skin_golden"] =
	{ assetId = 99603213734708, meshId = "rbxassetid://129112512417990", size = { 1.28, 5.09, 1.482 } } -- 808 tris

-- Exclusive Shop cosmetics (contract/exclusive-shop.md §15): seasonal pet seats, slime hats (client SlimeHatsFx),
-- lock stoppers (the StopperShut look) and the Exclusive skins' decor. size = the uploaded MeshPart's. models/<name>.py.
entries["pet_mount_pumpkin"] =
	{ assetId = 133229159089234, meshId = "rbxassetid://125584818822362", size = { 3.3, 1.638, 2.4 } } -- 1970 tris, seat 1.20
entries["pet_mount_snowglobe"] =
	{ assetId = 105048616075979, meshId = "rbxassetid://116051767660418", size = { 2.32, 2.045, 2.32 } } -- 1992 tris, seat 2.05
entries["slime_hat_party"] =
	{ assetId = 87297006103002, meshId = "rbxassetid://127939688826641", size = { 2.05, 2.174, 1.95 } } -- 732 tris
entries["slime_hat_bow"] =
	{ assetId = 86786632589246, meshId = "rbxassetid://106183691450476", size = { 2.1, 1.169, 0.533 } } -- 792 tris
entries["slime_hat_chef"] =
	{ assetId = 137126006681878, meshId = "rbxassetid://123115694387781", size = { 2.354, 1.85, 2.067 } } -- 672 tris
entries["slime_hat_flower_crown"] =
	{ assetId = 122506525490113, meshId = "rbxassetid://95589743366200", size = { 2.217, 0.599, 2.163 } } -- 792 tris
entries["slime_hat_top_hat"] =
	{ assetId = 73481090748614, meshId = "rbxassetid://79813661118777", size = { 2, 1.43, 2 } } -- 616 tris
entries["slime_hat_witch"] =
	{ assetId = 87431147313574, meshId = "rbxassetid://123651178194074", size = { 2.24, 2.341, 2.24 } } -- 792 tris
entries["lock_stopper_candy"] =
	{ assetId = 115676624703904, meshId = "rbxassetid://137801705548524", size = { 9.889, 9.66, 1.508 } } -- 1198 tris, goo_jar_stopper's box
entries["lock_stopper_carousel"] =
	{ assetId = 136210729503457, meshId = "rbxassetid://122085660724386", size = { 9.889, 9.66, 1.508 } } -- 1860 tris
entries["lock_stopper_sleepy"] =
	{ assetId = 78448357227087, meshId = "rbxassetid://83720293612988", size = { 9.889, 9.66, 1.508 } } -- 1602 tris
entries["plot_skin_fairground"] =
	{ assetId = 102535530047931, meshId = "rbxassetid://95542705899245", size = { 2.518, 7.823, 1.26 } } -- 698 tris
entries["plot_skin_beach"] =
	{ assetId = 83588268067966, meshId = "rbxassetid://128124664474065", size = { 5.2, 5.226, 5.2 } } -- 308 tris
entries["plot_skin_space"] =
	{ assetId = 137192406643018, meshId = "rbxassetid://121418111401175", size = { 4.42, 7.183, 4.42 } } -- 404 tris
entries["plot_skin_winter"] =
	{ assetId = 116237845591059, meshId = "rbxassetid://92094625768196", size = { 4.534, 7.241, 4.459 } } -- 902 tris
entries["plot_skin_haunted"] =
	{ assetId = 111511264347604, meshId = "rbxassetid://84147893318518", size = { 3.406, 4.353, 3.808 } } -- 432 tris

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
-- collision (not in COLLISION); MeshSwap.publishPetSeatTemplates publishes it, the client FollowPets clones it per follower, NOT a world slot. Uploaded 2026-10-18, v2 (smooth) 2026-10-19.
entries["pet_cloud"] =
	{ assetId = 76853347194916, meshId = "rbxassetid://131511097265313", size = { 3.261, 1.225, 2.393 } }
-- Pet seats (Config.PET_SEATS, contract/pet-seats.md; models/pet_mount_*.py): the free unlocks Jelly and Rainbow
-- Cloud. Decor like pet_cloud: MeshSwap.publishPetSeatTemplates publishes them, FollowPets clones them, NOT world slots.
entries["pet_mount_jelly"] =
	{ assetId = 78994170989597, meshId = "rbxassetid://119025780203249", size = { 3.3, 2.177, 2.4 } }
entries["pet_mount_rainbow_cloud"] =
	{ assetId = 85703836251595, meshId = "rbxassetid://133503703482477", size = { 3.3, 1.737, 2.4 } }
-- The 16 Exclusive pet seats (contract/pet-seats.md, sold in the Exclusive Shop).
entries["pet_mount_bubble"] =
	{ assetId = 103208190943072, meshId = "rbxassetid://123993237197371", size = { 3.3, 1.22, 2.4 } }
entries["pet_mount_clam_shell"] =
	{ assetId = 89570872834665, meshId = "rbxassetid://88169356640094", size = { 3.3, 2.264, 2.4 } }
entries["pet_mount_crescent_moon"] =
	{ assetId = 110688241059788, meshId = "rbxassetid://101449917182526", size = { 3.004, 0.88, 1.765 } }
entries["pet_mount_flame_cloud"] =
	{ assetId = 73807919787058, meshId = "rbxassetid://98559924143350", size = { 3.3, 1.53, 2.4 } }
entries["pet_mount_hoverboard"] =
	{ assetId = 89642305653421, meshId = "rbxassetid://108889734002088", size = { 3.269, 1, 1.407 } }
entries["pet_mount_ice_cloud"] =
	{ assetId = 123013660134650, meshId = "rbxassetid://81194482315831", size = { 3.3, 1.703, 2.4 } }
entries["pet_mount_leaf"] =
	{ assetId = 72183867740662, meshId = "rbxassetid://128744982003905", size = { 3.3, 0.713, 2.4 } }
entries["pet_mount_lily_pad"] =
	{ assetId = 74225581339380, meshId = "rbxassetid://104928288982313", size = { 3.3, 1.557, 2.4 } }
entries["pet_mount_magic_carpet"] =
	{ assetId = 103202026869992, meshId = "rbxassetid://116410478481132", size = { 3.3, 0.566, 2.4 } }
entries["pet_mount_mushroom"] =
	{ assetId = 83517779453621, meshId = "rbxassetid://139064712022358", size = { 3.3, 1.251, 2.4 } }
entries["pet_mount_pancakes"] =
	{ assetId = 96206764371173, meshId = "rbxassetid://118977694092989", size = { 3.3, 0.99, 2.4 } }
entries["pet_mount_royal_cushion"] =
	{ assetId = 107740936871790, meshId = "rbxassetid://124607204359016", size = { 3.3, 0.796, 2.4 } }
entries["pet_mount_star_cushion"] =
	{ assetId = 111190607613387, meshId = "rbxassetid://121678430177985", size = { 3.093, 0.939, 2.379 } }
entries["pet_mount_storm_cloud"] =
	{ assetId = 85327679325745, meshId = "rbxassetid://73164924934747", size = { 3.3, 1.225, 2.4 } }
entries["pet_mount_sunset_cloud"] =
	{ assetId = 113877052438419, meshId = "rbxassetid://73345244985162", size = { 3.3, 1.225, 2.4 } }
entries["pet_mount_ufo"] =
	{ assetId = 123494757263958, meshId = "rbxassetid://140454756003550", size = { 3.3, 1.337, 2.4 } }
-- BEGIN goo jar tower themes (generated by shared/modeling-kit/tools/goo_jar_theme_assets.py from uploaded.json):
-- each plot skin's own tower pieces, "<piece>@<skin>" (models/_goo_jar.py, JAR_THEME), and its companions (props,
-- hat). Not map slots, so not in NAMES: server/MeshSwap shows them on a plot whose PlotSkin is that skin
-- (ThemeMeshes, CONTRACT.md §15).
entries["goo_cork_stand@garden"] =
	{ assetId = 111498479612504, meshId = "rbxassetid://77998429477785", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@garden"] =
	{ assetId = 128086671756916, meshId = "rbxassetid://90225111578212", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@garden"] =
	{ assetId = 115631992040208, meshId = "rbxassetid://88027323901270", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@garden"] =
	{ assetId = 121407213277056, meshId = "rbxassetid://85195220900366", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@garden"] =
	{ assetId = 96629153076678, meshId = "rbxassetid://84247768962076", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@garden"] =
	{ assetId = 137661310511219, meshId = "rbxassetid://121995195294099", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@garden"] =
	{ assetId = 121990926750726, meshId = "rbxassetid://97221604331804", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@garden"] =
	{ assetId = 123427292830173, meshId = "rbxassetid://105986650548067", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@garden"] =
	{ assetId = 78745160305329, meshId = "rbxassetid://71927911252111", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@garden"] =
	{ assetId = 71680747187441, meshId = "rbxassetid://135972617420289", size = { 1.9, 0.7, 1.9 } }
entries["goo_jar_mascot@garden"] =
	{ assetId = 100844879804306, meshId = "rbxassetid://71384453270591", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@garden"] =
	{ assetId = 115694202926852, meshId = "rbxassetid://94330329266658", size = { 69.395, 11.877, 59.315 } }
entries["goo_jar_stair@garden"] =
	{ assetId = 108964828834608, meshId = "rbxassetid://98482920485034", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@garden"] =
	{ assetId = 105547366152325, meshId = "rbxassetid://86785934705142", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@garden"] =
	{ assetId = 133479900619299, meshId = "rbxassetid://119063277155206", size = { 60.362, 16.05, 58.368 } }
entries["goo_jar_trim_1_top@garden"] =
	{ assetId = 96641735004465, meshId = "rbxassetid://129321521645373", size = { 60.362, 22.688, 58.368 } }
entries["goo_jar_trim_2_mid@garden"] =
	{ assetId = 104346736296801, meshId = "rbxassetid://92139811679316", size = { 53.132, 16.05, 50.977 } }
entries["goo_jar_trim_2_top@garden"] =
	{ assetId = 94885651260497, meshId = "rbxassetid://106563230728452", size = { 53.132, 20.047, 50.977 } }
entries["goo_jar_trim_3_mid@garden"] =
	{ assetId = 73334973633975, meshId = "rbxassetid://122813621830323", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@garden"] =
	{ assetId = 124998896716569, meshId = "rbxassetid://88092519616426", size = { 47.355, 20.212, 45.434 } }
entries["goo_jar_trim_4_top@garden"] =
	{ assetId = 130028980090440, meshId = "rbxassetid://97746761790574", size = { 41.123, 18.788, 40.815 } }
entries["goo_lock_button@garden"] =
	{ assetId = 100817873147925, meshId = "rbxassetid://126744429952017", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@crystal"] =
	{ assetId = 139944654502426, meshId = "rbxassetid://134719829725038", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@crystal"] =
	{ assetId = 130085733724992, meshId = "rbxassetid://92246530580212", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@crystal"] =
	{ assetId = 120878685257269, meshId = "rbxassetid://70656505895433", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@crystal"] =
	{ assetId = 98449998226984, meshId = "rbxassetid://135818649866082", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@crystal"] =
	{ assetId = 122252541879714, meshId = "rbxassetid://137156531174196", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@crystal"] =
	{ assetId = 83099061558874, meshId = "rbxassetid://111394821387734", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@crystal"] =
	{ assetId = 80816509921372, meshId = "rbxassetid://82856650641089", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@crystal"] =
	{ assetId = 107360854602215, meshId = "rbxassetid://102700073499763", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@crystal"] =
	{ assetId = 124400462572460, meshId = "rbxassetid://97131488891442", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@crystal"] =
	{ assetId = 119122166688256, meshId = "rbxassetid://114736832706559", size = { 1.36, 1.049, 1.36 } }
entries["goo_jar_mascot@crystal"] =
	{ assetId = 123134590076588, meshId = "rbxassetid://102291952051361", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@crystal"] =
	{ assetId = 82138414765743, meshId = "rbxassetid://92667854407813", size = { 70.653, 8.384, 59.61 } }
entries["goo_jar_stair@crystal"] =
	{ assetId = 91943017356789, meshId = "rbxassetid://128725920025691", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@crystal"] =
	{ assetId = 118537490308224, meshId = "rbxassetid://136992999313695", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@crystal"] =
	{ assetId = 115480291139589, meshId = "rbxassetid://90309558535544", size = { 60.321, 16.05, 58.307 } }
entries["goo_jar_trim_1_top@crystal"] =
	{ assetId = 133571377022504, meshId = "rbxassetid://100715266499356", size = { 60.321, 22.688, 58.307 } }
entries["goo_jar_trim_2_mid@crystal"] =
	{ assetId = 81967734291194, meshId = "rbxassetid://81086317718081", size = { 53.091, 16.05, 50.916 } }
entries["goo_jar_trim_2_top@crystal"] =
	{ assetId = 95164554995413, meshId = "rbxassetid://112630366926454", size = { 53.091, 20.047, 50.916 } }
entries["goo_jar_trim_3_mid@crystal"] =
	{ assetId = 107677355249408, meshId = "rbxassetid://71285991643478", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@crystal"] =
	{ assetId = 90835167353091, meshId = "rbxassetid://130942193231660", size = { 47.314, 20.212, 45.373 } }
entries["goo_jar_trim_4_top@crystal"] =
	{ assetId = 71968027060850, meshId = "rbxassetid://79591019211049", size = { 41.082, 18.788, 40.753 } }
entries["goo_lock_button@crystal"] =
	{ assetId = 128227862719325, meshId = "rbxassetid://79509369575292", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@starlight"] =
	{ assetId = 102296110537452, meshId = "rbxassetid://136466754849153", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@starlight"] =
	{ assetId = 138725772597602, meshId = "rbxassetid://126948593410257", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@starlight"] =
	{ assetId = 117012161127578, meshId = "rbxassetid://96196253646596", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@starlight"] =
	{ assetId = 117627479815842, meshId = "rbxassetid://139717485741222", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@starlight"] =
	{ assetId = 118093724618973, meshId = "rbxassetid://115520813903433", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@starlight"] =
	{ assetId = 113696196706035, meshId = "rbxassetid://140335347773583", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@starlight"] =
	{ assetId = 93501615339821, meshId = "rbxassetid://108911375554167", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@starlight"] =
	{ assetId = 72654950079285, meshId = "rbxassetid://103501197573811", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@starlight"] =
	{ assetId = 109946271841685, meshId = "rbxassetid://89876049303091", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@starlight"] =
	{ assetId = 95851613900086, meshId = "rbxassetid://110150038317944", size = { 1.6, 1.195, 1.6 } }
entries["goo_jar_mascot@starlight"] =
	{ assetId = 131566188733994, meshId = "rbxassetid://74017504382639", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@starlight"] =
	{ assetId = 75427078658896, meshId = "rbxassetid://127611199930856", size = { 66.824, 9.827, 57.793 } }
entries["goo_jar_stair@starlight"] =
	{ assetId = 114241554847990, meshId = "rbxassetid://118588263459049", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@starlight"] =
	{ assetId = 92199146507880, meshId = "rbxassetid://124376347154493", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@starlight"] =
	{ assetId = 96364752853027, meshId = "rbxassetid://96994287099954", size = { 60.362, 16.05, 58.368 } }
entries["goo_jar_trim_1_top@starlight"] =
	{ assetId = 90838607934580, meshId = "rbxassetid://112796867514794", size = { 60.362, 22.688, 58.368 } }
entries["goo_jar_trim_2_mid@starlight"] =
	{ assetId = 129237765174327, meshId = "rbxassetid://97265728854130", size = { 53.132, 16.05, 50.977 } }
entries["goo_jar_trim_2_top@starlight"] =
	{ assetId = 115791112547492, meshId = "rbxassetid://133643360710966", size = { 53.132, 20.047, 50.977 } }
entries["goo_jar_trim_3_mid@starlight"] =
	{ assetId = 85627208986479, meshId = "rbxassetid://136067590554976", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@starlight"] =
	{ assetId = 75656165764756, meshId = "rbxassetid://77430370399626", size = { 47.355, 20.212, 45.434 } }
entries["goo_jar_trim_4_top@starlight"] =
	{ assetId = 88056995980141, meshId = "rbxassetid://96417808865243", size = { 41.123, 18.788, 40.815 } }
entries["goo_lock_button@starlight"] =
	{ assetId = 78698785005253, meshId = "rbxassetid://133354608318637", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@candy"] =
	{ assetId = 82408047818647, meshId = "rbxassetid://71988595778246", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@candy"] =
	{ assetId = 137944190033009, meshId = "rbxassetid://76473960799146", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@candy"] =
	{ assetId = 117576699062911, meshId = "rbxassetid://82890369153909", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@candy"] =
	{ assetId = 140631730360062, meshId = "rbxassetid://129315344437417", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@candy"] =
	{ assetId = 99649833414636, meshId = "rbxassetid://124982108157562", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@candy"] =
	{ assetId = 131391597042128, meshId = "rbxassetid://124367608992157", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@candy"] =
	{ assetId = 75875524733081, meshId = "rbxassetid://91754099622202", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@candy"] =
	{ assetId = 74531348793936, meshId = "rbxassetid://91614594491028", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@candy"] =
	{ assetId = 95229291680272, meshId = "rbxassetid://78640554660671", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@candy"] =
	{ assetId = 123744985934878, meshId = "rbxassetid://103498430941370", size = { 0.984, 1.182, 1.013 } }
entries["goo_jar_mascot@candy"] =
	{ assetId = 74170515949650, meshId = "rbxassetid://114756573172399", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@candy"] =
	{ assetId = 95867809102463, meshId = "rbxassetid://84423083466183", size = { 67.869, 13.355, 59.83 } }
entries["goo_jar_stair@candy"] =
	{ assetId = 100499594303336, meshId = "rbxassetid://71049274280691", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@candy"] =
	{ assetId = 92646803582454, meshId = "rbxassetid://79036481597585", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@candy"] =
	{ assetId = 110019109033426, meshId = "rbxassetid://90464191369852", size = { 60.321, 16.05, 58.251 } }
entries["goo_jar_trim_1_top@candy"] =
	{ assetId = 96211103499784, meshId = "rbxassetid://129494689008124", size = { 60.321, 22.688, 58.292 } }
entries["goo_jar_trim_2_mid@candy"] =
	{ assetId = 135787851996179, meshId = "rbxassetid://103737882173883", size = { 53.091, 16.05, 50.909 } }
entries["goo_jar_trim_2_top@candy"] =
	{ assetId = 125475596517383, meshId = "rbxassetid://86997990194117", size = { 53.091, 20.047, 50.905 } }
entries["goo_jar_trim_3_mid@candy"] =
	{ assetId = 76977772731704, meshId = "rbxassetid://135407376636518", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@candy"] =
	{ assetId = 87448877188413, meshId = "rbxassetid://102819226991762", size = { 47.314, 20.212, 45.364 } }
entries["goo_jar_trim_4_top@candy"] =
	{ assetId = 137290204574243, meshId = "rbxassetid://127581714000962", size = { 41.082, 18.788, 40.746 } }
entries["goo_lock_button@candy"] =
	{ assetId = 90929949311608, meshId = "rbxassetid://124008710082935", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@mushroom"] =
	{ assetId = 140108323015726, meshId = "rbxassetid://83710850597956", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@mushroom"] =
	{ assetId = 107003477417621, meshId = "rbxassetid://71044365270975", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@mushroom"] =
	{ assetId = 79663946221673, meshId = "rbxassetid://90203420798550", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@mushroom"] =
	{ assetId = 74938745149873, meshId = "rbxassetid://138860194100231", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@mushroom"] =
	{ assetId = 96002242328328, meshId = "rbxassetid://123092694229460", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@mushroom"] =
	{ assetId = 132223631130440, meshId = "rbxassetid://76973565882477", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@mushroom"] =
	{ assetId = 110772837308250, meshId = "rbxassetid://99868377456280", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@mushroom"] =
	{ assetId = 75535686474136, meshId = "rbxassetid://136559802716159", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@mushroom"] =
	{ assetId = 82097369665156, meshId = "rbxassetid://89224678984271", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@mushroom"] =
	{ assetId = 75544090904428, meshId = "rbxassetid://129389209017503", size = { 1.617, 0.765, 1.7 } }
entries["goo_jar_mascot@mushroom"] =
	{ assetId = 77313213780795, meshId = "rbxassetid://139318171189767", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@mushroom"] =
	{ assetId = 83058345661065, meshId = "rbxassetid://89193707886032", size = { 69.204, 5.031, 65.316 } }
entries["goo_jar_stair@mushroom"] =
	{ assetId = 92291615547565, meshId = "rbxassetid://75027613857431", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@mushroom"] =
	{ assetId = 124665008899641, meshId = "rbxassetid://92740925893580", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@mushroom"] =
	{ assetId = 116310095114229, meshId = "rbxassetid://83476514701472", size = { 60.289, 16.05, 58.234 } }
entries["goo_jar_trim_1_top@mushroom"] =
	{ assetId = 80471217573955, meshId = "rbxassetid://95323802068888", size = { 60.289, 22.688, 58.234 } }
entries["goo_jar_trim_2_mid@mushroom"] =
	{ assetId = 98149253420556, meshId = "rbxassetid://76668507904584", size = { 53.056, 16.05, 50.843 } }
entries["goo_jar_trim_2_top@mushroom"] =
	{ assetId = 98454822696377, meshId = "rbxassetid://82000103973425", size = { 53.056, 20.047, 50.843 } }
entries["goo_jar_trim_3_mid@mushroom"] =
	{ assetId = 116748220649977, meshId = "rbxassetid://88857327679842", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@mushroom"] =
	{ assetId = 137110356362919, meshId = "rbxassetid://87569073341135", size = { 47.279, 20.212, 45.3 } }
entries["goo_jar_trim_4_top@mushroom"] =
	{ assetId = 95112597764822, meshId = "rbxassetid://82581930746006", size = { 41.048, 18.788, 40.681 } }
entries["goo_lock_button@mushroom"] =
	{ assetId = 91904618316828, meshId = "rbxassetid://91586327828683", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@fairground"] =
	{ assetId = 116901934140027, meshId = "rbxassetid://82184096518967", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@fairground"] =
	{ assetId = 116126519191068, meshId = "rbxassetid://104998099000996", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@fairground"] =
	{ assetId = 97244512301286, meshId = "rbxassetid://81338354994448", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@fairground"] =
	{ assetId = 138398936312645, meshId = "rbxassetid://134546084737452", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@fairground"] =
	{ assetId = 72819279424191, meshId = "rbxassetid://102863817305599", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@fairground"] =
	{ assetId = 136809364710294, meshId = "rbxassetid://128014365231619", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@fairground"] =
	{ assetId = 110146206934739, meshId = "rbxassetid://140232285677071", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@fairground"] =
	{ assetId = 94470394990684, meshId = "rbxassetid://81151404106439", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@fairground"] =
	{ assetId = 87724091103416, meshId = "rbxassetid://92158850274432", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@fairground"] =
	{ assetId = 97062415537911, meshId = "rbxassetid://105665934574397", size = { 1.44, 0.74, 1.44 } }
entries["goo_jar_mascot@fairground"] =
	{ assetId = 82123699541460, meshId = "rbxassetid://90906026826705", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@fairground"] =
	{ assetId = 140408660519148, meshId = "rbxassetid://135116680451149", size = { 67.475, 13.039, 58.452 } }
entries["goo_jar_stair@fairground"] =
	{ assetId = 135634238132134, meshId = "rbxassetid://99312952459270", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@fairground"] =
	{ assetId = 136639702563052, meshId = "rbxassetid://117390545708066", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@fairground"] =
	{ assetId = 107237550907330, meshId = "rbxassetid://114100208987565", size = { 60.418, 16.05, 58.464 } }
entries["goo_jar_trim_1_top@fairground"] =
	{ assetId = 132509878961834, meshId = "rbxassetid://129337568485475", size = { 60.418, 22.688, 58.464 } }
entries["goo_jar_trim_2_mid@fairground"] =
	{ assetId = 127417837405327, meshId = "rbxassetid://113354468439482", size = { 53.188, 16.05, 51.073 } }
entries["goo_jar_trim_2_top@fairground"] =
	{ assetId = 89329078954331, meshId = "rbxassetid://85023063438160", size = { 53.188, 20.047, 51.073 } }
entries["goo_jar_trim_3_mid@fairground"] =
	{ assetId = 98319663354379, meshId = "rbxassetid://128051615170975", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@fairground"] =
	{ assetId = 127620439981611, meshId = "rbxassetid://123620139678093", size = { 47.411, 20.212, 45.529 } }
entries["goo_jar_trim_4_top@fairground"] =
	{ assetId = 81148850057973, meshId = "rbxassetid://135786295979776", size = { 41.18, 18.788, 40.91 } }
entries["goo_lock_button@fairground"] =
	{ assetId = 105861314727773, meshId = "rbxassetid://109303859527592", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@beach"] =
	{ assetId = 86488644167567, meshId = "rbxassetid://109066828991860", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@beach"] =
	{ assetId = 122333435149711, meshId = "rbxassetid://127804986913969", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@beach"] =
	{ assetId = 92343878198921, meshId = "rbxassetid://77874185878882", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@beach"] =
	{ assetId = 114840862539422, meshId = "rbxassetid://91511892676512", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@beach"] =
	{ assetId = 132232048786549, meshId = "rbxassetid://99385151152830", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@beach"] =
	{ assetId = 75522391687813, meshId = "rbxassetid://128240265229811", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@beach"] =
	{ assetId = 109074984048313, meshId = "rbxassetid://101157942055160", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@beach"] =
	{ assetId = 74046412248991, meshId = "rbxassetid://98473255969075", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@beach"] =
	{ assetId = 81555025961392, meshId = "rbxassetid://85633273157816", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@beach"] =
	{ assetId = 111688158648588, meshId = "rbxassetid://104197775600649", size = { 2.068, 1.22, 2.1 } }
entries["goo_jar_mascot@beach"] =
	{ assetId = 79390414978428, meshId = "rbxassetid://85630276964121", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@beach"] =
	{ assetId = 135712857151286, meshId = "rbxassetid://85196689268107", size = { 68.844, 8.262, 63.204 } }
entries["goo_jar_stair@beach"] =
	{ assetId = 122289245840700, meshId = "rbxassetid://79009015963391", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@beach"] =
	{ assetId = 119509709081762, meshId = "rbxassetid://119179082940690", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@beach"] =
	{ assetId = 135984102768362, meshId = "rbxassetid://93619987914597", size = { 60.418, 16.05, 58.464 } }
entries["goo_jar_trim_1_top@beach"] =
	{ assetId = 88845393964616, meshId = "rbxassetid://115483689445351", size = { 60.418, 22.688, 58.464 } }
entries["goo_jar_trim_2_mid@beach"] =
	{ assetId = 86885043802609, meshId = "rbxassetid://134074020154803", size = { 53.188, 16.05, 51.073 } }
entries["goo_jar_trim_2_top@beach"] =
	{ assetId = 70847950405363, meshId = "rbxassetid://95536674049656", size = { 53.188, 20.047, 51.073 } }
entries["goo_jar_trim_3_mid@beach"] =
	{ assetId = 96666360984884, meshId = "rbxassetid://130951459352533", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@beach"] =
	{ assetId = 101984028601725, meshId = "rbxassetid://140491595020663", size = { 47.411, 20.212, 45.529 } }
entries["goo_jar_trim_4_top@beach"] =
	{ assetId = 73507129811734, meshId = "rbxassetid://129227217878913", size = { 41.18, 18.788, 40.91 } }
entries["goo_lock_button@beach"] =
	{ assetId = 126940530942467, meshId = "rbxassetid://72199697758711", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@space"] =
	{ assetId = 101514156225281, meshId = "rbxassetid://93572211222811", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@space"] =
	{ assetId = 97515377320869, meshId = "rbxassetid://130404239786124", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@space"] =
	{ assetId = 100643166952959, meshId = "rbxassetid://85419496250478", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@space"] =
	{ assetId = 122336962275868, meshId = "rbxassetid://107782639847742", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@space"] =
	{ assetId = 75532659796436, meshId = "rbxassetid://107177244899920", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@space"] =
	{ assetId = 131045422940877, meshId = "rbxassetid://81121080937617", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@space"] =
	{ assetId = 80536694626872, meshId = "rbxassetid://114943542205369", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@space"] =
	{ assetId = 107316968066642, meshId = "rbxassetid://131048840806341", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@space"] =
	{ assetId = 116304040792392, meshId = "rbxassetid://77019757456904", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@space"] =
	{ assetId = 79200168435959, meshId = "rbxassetid://77796178285002", size = { 1.527, 1.178, 0.26 } }
entries["goo_jar_mascot@space"] =
	{ assetId = 124544583264738, meshId = "rbxassetid://102739444000621", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@space"] =
	{ assetId = 91324997704292, meshId = "rbxassetid://107811386168026", size = { 70.64, 7.95, 59.421 } }
entries["goo_jar_stair@space"] =
	{ assetId = 122250827035156, meshId = "rbxassetid://122859187330117", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@space"] =
	{ assetId = 124809692882219, meshId = "rbxassetid://76947715559709", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@space"] =
	{ assetId = 107072326071653, meshId = "rbxassetid://104958033528368", size = { 60.374, 16.05, 58.379 } }
entries["goo_jar_trim_1_top@space"] =
	{ assetId = 121790985107522, meshId = "rbxassetid://126708599763625", size = { 60.374, 22.688, 58.379 } }
entries["goo_jar_trim_2_mid@space"] =
	{ assetId = 139645343343936, meshId = "rbxassetid://91395103324675", size = { 53.143, 16.05, 50.988 } }
entries["goo_jar_trim_2_top@space"] =
	{ assetId = 132770873915212, meshId = "rbxassetid://115873094833067", size = { 53.143, 20.047, 50.988 } }
entries["goo_jar_trim_3_mid@space"] =
	{ assetId = 125281028265174, meshId = "rbxassetid://82380460244255", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@space"] =
	{ assetId = 89390564721287, meshId = "rbxassetid://78624485691633", size = { 47.366, 20.212, 45.444 } }
entries["goo_jar_trim_4_top@space"] =
	{ assetId = 111431645600871, meshId = "rbxassetid://127426595042140", size = { 41.135, 18.788, 40.825 } }
entries["goo_lock_button@space"] =
	{ assetId = 93359199153259, meshId = "rbxassetid://94078373296906", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@winter"] =
	{ assetId = 74094188426777, meshId = "rbxassetid://79632623851937", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@winter"] =
	{ assetId = 116395976685400, meshId = "rbxassetid://83300176689330", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@winter"] =
	{ assetId = 135562251808227, meshId = "rbxassetid://74136350557181", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@winter"] =
	{ assetId = 125506386985020, meshId = "rbxassetid://103741145849340", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@winter"] =
	{ assetId = 124194408952360, meshId = "rbxassetid://74171421383042", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@winter"] =
	{ assetId = 93854426484899, meshId = "rbxassetid://135245995469744", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@winter"] =
	{ assetId = 86895083529501, meshId = "rbxassetid://90327729021722", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@winter"] =
	{ assetId = 128948294612556, meshId = "rbxassetid://131000054196089", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@winter"] =
	{ assetId = 93637875571697, meshId = "rbxassetid://72079229536747", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@winter"] =
	{ assetId = 134052171807095, meshId = "rbxassetid://80313502143930", size = { 2.19, 2.179, 2.12 } }
entries["goo_jar_mascot@winter"] =
	{ assetId = 93139794904628, meshId = "rbxassetid://94328015081946", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@winter"] =
	{ assetId = 119385962053752, meshId = "rbxassetid://123446446653553", size = { 68.353, 8.869, 60.556 } }
entries["goo_jar_stair@winter"] =
	{ assetId = 91941251661873, meshId = "rbxassetid://121176769072659", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@winter"] =
	{ assetId = 87437290550291, meshId = "rbxassetid://140522041008591", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@winter"] =
	{ assetId = 103567521531028, meshId = "rbxassetid://138599445569630", size = { 60.321, 16.05, 58.251 } }
entries["goo_jar_trim_1_top@winter"] =
	{ assetId = 124459426978816, meshId = "rbxassetid://81187444249730", size = { 60.321, 22.688, 58.292 } }
entries["goo_jar_trim_2_mid@winter"] =
	{ assetId = 105757773741548, meshId = "rbxassetid://111317036105790", size = { 53.091, 16.05, 50.909 } }
entries["goo_jar_trim_2_top@winter"] =
	{ assetId = 81263273660427, meshId = "rbxassetid://117017304496862", size = { 53.091, 20.047, 50.905 } }
entries["goo_jar_trim_3_mid@winter"] =
	{ assetId = 118454146919383, meshId = "rbxassetid://98640530868832", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@winter"] =
	{ assetId = 106311753032908, meshId = "rbxassetid://127675406147184", size = { 47.314, 20.212, 45.364 } }
entries["goo_jar_trim_4_top@winter"] =
	{ assetId = 132927014483751, meshId = "rbxassetid://110140845047664", size = { 41.082, 18.788, 40.746 } }
entries["goo_lock_button@winter"] =
	{ assetId = 91052891039602, meshId = "rbxassetid://109987625824792", size = { 5, 3.966, 5 } }
entries["goo_cork_stand@haunted"] =
	{ assetId = 73581621531164, meshId = "rbxassetid://114301522796374", size = { 7.8, 2.45, 7.8 } }
entries["goo_drop_tube_goo_2@haunted"] =
	{ assetId = 70483075865209, meshId = "rbxassetid://88108208327810", size = { 8.657, 21.794, 13.688 } }
entries["goo_drop_tube_goo_3@haunted"] =
	{ assetId = 91769791049640, meshId = "rbxassetid://126053389882877", size = { 9.683, 37.692, 16.489 } }
entries["goo_drop_tube_goo_4@haunted"] =
	{ assetId = 133902367351223, meshId = "rbxassetid://79083300906433", size = { 10.638, 53.692, 18.838 } }
entries["goo_jar_deck_2@haunted"] =
	{ assetId = 103400149661321, meshId = "rbxassetid://125117090292076", size = { 53.2, 1.839, 53.2 } }
entries["goo_jar_deck_3@haunted"] =
	{ assetId = 84561175945846, meshId = "rbxassetid://73318624993190", size = { 47.2, 1.839, 47.2 } }
entries["goo_jar_deck_4@haunted"] =
	{ assetId = 74807397984555, meshId = "rbxassetid://110742228977325", size = { 42.2, 1.78, 42.2 } }
entries["goo_jar_door@haunted"] =
	{ assetId = 94105731118446, meshId = "rbxassetid://132866177493662", size = { 14.521, 13.06, 3.419 } }
entries["goo_jar_foot@haunted"] =
	{ assetId = 97412286454327, meshId = "rbxassetid://114326594035198", size = { 80.1, 2.076, 80.1 } }
entries["goo_jar_hat@haunted"] =
	{ assetId = 131308399887923, meshId = "rbxassetid://123612131708093", size = { 3.836, 1.287, 0.376 } }
entries["goo_jar_mascot@haunted"] =
	{ assetId = 110894296288981, meshId = "rbxassetid://95525000271641", size = { 2.2, 1.567, 2.138 } }
entries["goo_jar_props@haunted"] =
	{ assetId = 111991897731148, meshId = "rbxassetid://80175267874643", size = { 69.198, 4.475, 60.131 } }
entries["goo_jar_stair@haunted"] =
	{ assetId = 113169763082851, meshId = "rbxassetid://138931537571453", size = { 10.99, 17.026, 10.99 } }
entries["goo_jar_stopper@haunted"] =
	{ assetId = 115792268446459, meshId = "rbxassetid://81649865609987", size = { 9.889, 9.66, 1.508 } }
entries["goo_jar_trim_1_mid@haunted"] =
	{ assetId = 84656043187868, meshId = "rbxassetid://119908185769596", size = { 60.321, 16.05, 58.307 } }
entries["goo_jar_trim_1_top@haunted"] =
	{ assetId = 125906125322164, meshId = "rbxassetid://96210792256978", size = { 60.321, 22.688, 58.307 } }
entries["goo_jar_trim_2_mid@haunted"] =
	{ assetId = 76212716095903, meshId = "rbxassetid://117791511742492", size = { 53.091, 16.05, 50.916 } }
entries["goo_jar_trim_2_top@haunted"] =
	{ assetId = 126971550307034, meshId = "rbxassetid://105550570547530", size = { 53.091, 20.047, 50.916 } }
entries["goo_jar_trim_3_mid@haunted"] =
	{ assetId = 129936832901616, meshId = "rbxassetid://109979005006990", size = { 47.643, 16.05, 45.978 } }
entries["goo_jar_trim_3_top@haunted"] =
	{ assetId = 76106514065572, meshId = "rbxassetid://125916269775312", size = { 47.314, 20.212, 45.373 } }
entries["goo_jar_trim_4_top@haunted"] =
	{ assetId = 110737774795080, meshId = "rbxassetid://88818169036953", size = { 41.082, 18.788, 40.753 } }
entries["goo_lock_button@haunted"] =
	{ assetId = 83453529502308, meshId = "rbxassetid://120162979510517", size = { 5, 3.966, 5 } }
-- END goo jar tower themes
-- BEGIN base shape meshes (generated by shared/modeling-kit/tools/base_mesh_assets.py from uploaded.json): the
-- other bases' pieces and their skins' themed ones, "<piece>@<skin>" (CONTRACT.md §44). Not map slots, so not in
-- NAMES: BaseShapes builds their slots at runtime and server/MeshSwap fills them.
entries["carousel_deck"] =
	{ assetId = 108044231206026, meshId = "rbxassetid://123497626047731", size = { 58, 0.73, 58 } }
entries["carousel_glass"] =
	{ assetId = 95330065122374, meshId = "rbxassetid://88859532616689", size = { 57.3, 10, 57.3 } }
entries["carousel_glass_1"] =
	{ assetId = 99092832547235, meshId = "rbxassetid://82819509789039", size = { 57.286, 10, 57.016 } }
entries["carousel_gold"] =
	{ assetId = 95784365660268, meshId = "rbxassetid://91271283130037", size = { 62.352, 16, 62.32 } }
entries["carousel_gold_1"] =
	{ assetId = 71678098004157, meshId = "rbxassetid://114550126157334", size = { 62.352, 16, 62.32 } }
entries["carousel_horses"] =
	{ assetId = 119857602331655, meshId = "rbxassetid://80803419103834", size = { 64.139, 12.12, 62.179 } }
entries["carousel_ramp"] =
	{ assetId = 81983541361304, meshId = "rbxassetid://103204225235532", size = { 15.939, 16.8, 15.964 } }
entries["carousel_roof_cream_1"] =
	{ assetId = 80168339049963, meshId = "rbxassetid://127055199021025", size = { 64, 20.459, 64 } }
entries["carousel_roof_cream_2"] =
	{ assetId = 80573001217581, meshId = "rbxassetid://101153202558885", size = { 70.02, 51.8, 64 } }
entries["carousel_roof_cream_3"] =
	{ assetId = 140513737077419, meshId = "rbxassetid://107585371090977", size = { 70.046, 67.8, 64 } }
entries["carousel_roof_cream_4"] =
	{ assetId = 76591379648526, meshId = "rbxassetid://129467635545747", size = { 70.047, 83.8, 64 } }
entries["carousel_roof_gold"] =
	{ assetId = 131230762766121, meshId = "rbxassetid://133130989027175", size = { 64.862, 26.35, 64.827 } }
entries["carousel_roof_stripe_1"] =
	{ assetId = 94570604333965, meshId = "rbxassetid://80696471710988", size = { 64, 20.459, 64 } }
entries["carousel_roof_stripe_2"] =
	{ assetId = 129735305518237, meshId = "rbxassetid://138664000141403", size = { 69.99, 51.294, 64 } }
entries["carousel_roof_stripe_3"] =
	{ assetId = 113349130287634, meshId = "rbxassetid://107554733898258", size = { 69.996, 67.22, 64 } }
entries["carousel_roof_stripe_4"] =
	{ assetId = 80511027065526, meshId = "rbxassetid://132612452525374", size = { 70.025, 83.22, 64 } }
entries["carousel_room"] =
	{ assetId = 119288798238300, meshId = "rbxassetid://80075685186088", size = { 63.466, 15.4, 63.466 } }
entries["carousel_room_1"] =
	{ assetId = 95329178604298, meshId = "rbxassetid://77609826993273", size = { 63.466, 15.8, 63.466 } }
entries["carousel_stripes"] =
	{ assetId = 92445932037291, meshId = "rbxassetid://110653917458781", size = { 63.466, 2.975, 63.466 } }
entries["factory_belt"] =
	{ assetId = 100773088768796, meshId = "rbxassetid://91785805232339", size = { 37.331, 1.6, 3 } }
entries["factory_chute_2"] =
	{ assetId = 103717292738699, meshId = "rbxassetid://90946783736230", size = { 5.843, 24.6, 7.25 } }
entries["factory_chute_3"] =
	{ assetId = 80603584252359, meshId = "rbxassetid://85888311352309", size = { 5.843, 40.6, 7.25 } }
entries["factory_chute_4"] =
	{ assetId = 76981547155138, meshId = "rbxassetid://120060042792689", size = { 5.843, 56.6, 7.25 } }
entries["factory_core"] =
	{ assetId = 70883604061302, meshId = "rbxassetid://97369194674125", size = { 23.65, 16, 10.25 } }
entries["factory_core_cap"] =
	{ assetId = 140175238353116, meshId = "rbxassetid://112400148842257", size = { 23, 0.6, 9.3 } }
entries["factory_door_frame"] =
	{ assetId = 88646514543064, meshId = "rbxassetid://79083745088339", size = { 13.327, 14.6, 3.2 } }
entries["factory_dress@candy"] =
	{ assetId = 93951856303094, meshId = "rbxassetid://135626665933919", size = { 53.961, 16.787, 51.914 } }
entries["factory_dress@crystal"] =
	{ assetId = 138331433547097, meshId = "rbxassetid://112531772599353", size = { 53.961, 16.787, 51.914 } }
entries["factory_dress@garden"] =
	{ assetId = 100246169983770, meshId = "rbxassetid://131522071442155", size = { 53.961, 16.787, 51.914 } }
entries["factory_dress@mushroom"] =
	{ assetId = 126019050793421, meshId = "rbxassetid://132523398222556", size = { 53.961, 16.787, 51.914 } }
entries["factory_dress@starlight"] =
	{ assetId = 78905332508003, meshId = "rbxassetid://79858307176815", size = { 53.961, 16.787, 51.914 } }
entries["factory_floor_1"] =
	{ assetId = 126997434272892, meshId = "rbxassetid://101243832383480", size = { 46, 0.34, 46 } }
entries["factory_foot"] =
	{ assetId = 82138658447446, meshId = "rbxassetid://85301963600878", size = { 80, 19.941, 80 } }
entries["factory_foot@candy"] =
	{ assetId = 113391621856877, meshId = "rbxassetid://72962005034377", size = { 80, 19.941, 80 } }
entries["factory_foot@crystal"] =
	{ assetId = 84593877467040, meshId = "rbxassetid://98825439721168", size = { 80, 19.941, 80 } }
entries["factory_foot@garden"] =
	{ assetId = 139800318731332, meshId = "rbxassetid://129361781724846", size = { 80, 19.941, 80 } }
entries["factory_foot@mushroom"] =
	{ assetId = 94173446592849, meshId = "rbxassetid://104503316582591", size = { 80, 19.941, 80 } }
entries["factory_foot@starlight"] =
	{ assetId = 124157471991794, meshId = "rbxassetid://116091214379279", size = { 80, 19.941, 80 } }
entries["factory_hatch"] =
	{ assetId = 91447747825601, meshId = "rbxassetid://104341037665525", size = { 1.4, 7.55, 4.6 } }
entries["factory_parapet"] =
	{ assetId = 76518829771611, meshId = "rbxassetid://119550353720958", size = { 49, 2.2, 49 } }
entries["factory_pipes"] =
	{ assetId = 137013276497816, meshId = "rbxassetid://130868215472235", size = { 27.16, 16, 1.7 } }
entries["factory_pipes_1"] =
	{ assetId = 79875058404914, meshId = "rbxassetid://105625497971677", size = { 27.433, 16, 2.6 } }
entries["factory_roof"] =
	{ assetId = 119605346107994, meshId = "rbxassetid://111473610822329", size = { 46.4, 5.536, 46.4 } }
entries["factory_roof_kit"] =
	{ assetId = 75330902155265, meshId = "rbxassetid://75443235074124", size = { 46.758, 22.287, 42.271 } }
entries["factory_roof_kit@candy"] =
	{ assetId = 71845756398078, meshId = "rbxassetid://92756587984279", size = { 46.758, 22.287, 42.271 } }
entries["factory_roof_kit@crystal"] =
	{ assetId = 93967679108151, meshId = "rbxassetid://88547176281311", size = { 46.758, 22.287, 42.271 } }
entries["factory_roof_kit@garden"] =
	{ assetId = 118643875551160, meshId = "rbxassetid://98690765257902", size = { 46.758, 22.287, 42.271 } }
entries["factory_roof_kit@mushroom"] =
	{ assetId = 89034609975496, meshId = "rbxassetid://74988601931995", size = { 46.758, 22.287, 42.271 } }
entries["factory_roof_kit@starlight"] =
	{ assetId = 91521931104374, meshId = "rbxassetid://121025247408078", size = { 46.758, 22.287, 42.271 } }
entries["factory_shutter"] =
	{ assetId = 80100065449366, meshId = "rbxassetid://124961879321214", size = { 9.9, 0.86, 0.7 } }
entries["factory_shutter_shut"] =
	{ assetId = 122966859018755, meshId = "rbxassetid://130006635148507", size = { 9.9, 10.943, 0.7 } }
entries["factory_sign"] =
	{ assetId = 74902095108006, meshId = "rbxassetid://135713486274830", size = { 19.8, 4.7, 2.625 } }
entries["factory_silo"] =
	{ assetId = 126218051767919, meshId = "rbxassetid://123772859407252", size = { 7.989, 22, 8 } }
entries["factory_slab"] =
	{ assetId = 110209612622988, meshId = "rbxassetid://119949954414453", size = { 46, 0.655, 47.8 } }
entries["factory_stair"] =
	{ assetId = 95260270970124, meshId = "rbxassetid://138228412530345", size = { 23.162, 17.003, 9.3 } }
entries["factory_storey"] =
	{ assetId = 84718934758513, meshId = "rbxassetid://110630432738194", size = { 49.2, 16, 49.2 } }
entries["factory_storey_1"] =
	{ assetId = 95566648647121, meshId = "rbxassetid://101749787817763", size = { 49.2, 16, 49.2 } }
entries["factory_trim"] =
	{ assetId = 105772582314807, meshId = "rbxassetid://123555542981124", size = { 49.6, 14.7, 49.6 } }
entries["factory_trim_1"] =
	{ assetId = 93418768478515, meshId = "rbxassetid://95294578024345", size = { 49.6, 14.7, 49.6 } }
entries["factory_windows"] =
	{ assetId = 92517434783794, meshId = "rbxassetid://100512097912453", size = { 47.3, 11, 47.3 } }
entries["factory_windows_1"] =
	{ assetId = 118178946943878, meshId = "rbxassetid://112110740248772", size = { 47.3, 11, 47.3 } }
entries["lighthouse_beam"] =
	{ assetId = 117389742829815, meshId = "rbxassetid://131301547979171", size = { 31.235, 6.848, 46.901 } }
entries["lighthouse_cap"] =
	{ assetId = 130259495935403, meshId = "rbxassetid://103455139676222", size = { 23, 10.2, 23 } }
entries["lighthouse_deck_2"] =
	{ assetId = 116519460217676, meshId = "rbxassetid://125608508928281", size = { 56.1, 0.72, 56.1 } }
entries["lighthouse_deck_3"] =
	{ assetId = 125523205607490, meshId = "rbxassetid://99016238205126", size = { 53.1, 0.72, 53.1 } }
entries["lighthouse_deck_4"] =
	{ assetId = 122677705898513, meshId = "rbxassetid://82400547210087", size = { 50.1, 0.72, 50.1 } }
entries["lighthouse_drop_2"] =
	{ assetId = 131167581377767, meshId = "rbxassetid://85615741994413", size = { 6.367, 37.829, 16.262 } }
entries["lighthouse_drop_3"] =
	{ assetId = 119065975163120, meshId = "rbxassetid://79662869894530", size = { 5.027, 53.829, 16.278 } }
entries["lighthouse_drop_4"] =
	{ assetId = 109580350547373, meshId = "rbxassetid://134335261254440", size = { 5.68, 69.829, 16.285 } }
entries["lighthouse_gallery_1"] =
	{ assetId = 75877974096928, meshId = "rbxassetid://123652861732964", size = { 64.6, 6.35, 64.6 } }
entries["lighthouse_gallery_2"] =
	{ assetId = 89651848815111, meshId = "rbxassetid://83527183894360", size = { 61.6, 6.35, 61.6 } }
entries["lighthouse_gallery_3"] =
	{ assetId = 103968244397512, meshId = "rbxassetid://91623283306117", size = { 58.6, 6.35, 58.6 } }
entries["lighthouse_gallery_4"] =
	{ assetId = 95839153728375, meshId = "rbxassetid://138710311336988", size = { 55.6, 6.35, 55.6 } }
entries["lighthouse_glass_1"] =
	{ assetId = 100754808640650, meshId = "rbxassetid://114631074754123", size = { 57.286, 10.4, 57.016 } }
entries["lighthouse_glass_2"] =
	{ assetId = 86268137416212, meshId = "rbxassetid://89163134524882", size = { 54.3, 10.4, 54.3 } }
entries["lighthouse_glass_3"] =
	{ assetId = 97921933306505, meshId = "rbxassetid://80528087963728", size = { 51.3, 10.4, 51.3 } }
entries["lighthouse_glass_4"] =
	{ assetId = 118331530881903, meshId = "rbxassetid://76950773123355", size = { 48.3, 10.4, 48.3 } }
entries["lighthouse_lantern"] =
	{ assetId = 127801253138189, meshId = "rbxassetid://124130168000333", size = { 20.6, 9, 20.6 } }
entries["lighthouse_lantern_glass"] =
	{ assetId = 107965049410572, meshId = "rbxassetid://118853725510801", size = { 19.4, 6.3, 19.4 } }
entries["lighthouse_ramp"] =
	{ assetId = 99363115827538, meshId = "rbxassetid://126801061954104", size = { 15.999, 17.316, 15.727 } }
entries["lighthouse_rocks"] =
	{ assetId = 109329746083315, meshId = "rbxassetid://111049221141892", size = { 69.805, 4.214, 60.537 } }
entries["lighthouse_room_1"] =
	{ assetId = 97321490017703, meshId = "rbxassetid://85254582686352", size = { 58.786, 16, 58.509 } }
entries["lighthouse_room_2"] =
	{ assetId = 116070197294453, meshId = "rbxassetid://90571376122421", size = { 56.15, 16, 55.8 } }
entries["lighthouse_room_3"] =
	{ assetId = 96989272057294, meshId = "rbxassetid://121238730338179", size = { 53.15, 16, 52.8 } }
entries["lighthouse_room_4"] =
	{ assetId = 133424477008520, meshId = "rbxassetid://92533368487741", size = { 50.15, 16, 49.8 } }
entries["pagoda_cap_1_mid"] =
	{ assetId = 90148981916597, meshId = "rbxassetid://124092573387050", size = { 67, 5.354, 67 } }
entries["pagoda_cap_2_mid"] =
	{ assetId = 130176297050193, meshId = "rbxassetid://112069718277334", size = { 63, 5.359, 63 } }
entries["pagoda_cap_3_mid"] =
	{ assetId = 135502975947433, meshId = "rbxassetid://128581980104993", size = { 59, 5.359, 59 } }
entries["pagoda_cap_extra@candy"] =
	{ assetId = 106122845480811, meshId = "rbxassetid://114549613308395", size = { 64.661, 5.022, 63.676 } }
entries["pagoda_cap_extra@crystal"] =
	{ assetId = 112073711250132, meshId = "rbxassetid://76924652072540", size = { 64.661, 5.022, 63.676 } }
entries["pagoda_deck_2"] =
	{ assetId = 75065303944391, meshId = "rbxassetid://94931328386032", size = { 51.936, 0.65, 60 } }
entries["pagoda_deck_3"] =
	{ assetId = 74275262332877, meshId = "rbxassetid://110627085471106", size = { 47.921, 0.65, 58 } }
entries["pagoda_deck_4"] =
	{ assetId = 128559212436259, meshId = "rbxassetid://116458545105400", size = { 44.927, 0.65, 56.5 } }
entries["pagoda_dome"] = { assetId = 96514762576279, meshId = "rbxassetid://74375089778855", size = { 56, 13.55, 56 } }
entries["pagoda_dome_extra@candy"] =
	{ assetId = 73223874881398, meshId = "rbxassetid://134778956414385", size = { 52.406, 15.764, 52.51 } }
entries["pagoda_dome_extra@crystal"] =
	{ assetId = 79381406343104, meshId = "rbxassetid://108930669077544", size = { 52.406, 15.764, 52.51 } }
entries["pagoda_dome_spots"] =
	{ assetId = 85599561426007, meshId = "rbxassetid://122080826895197", size = { 55.104, 10.247, 55.119 } }
entries["pagoda_dome_spots@starlight"] =
	{ assetId = 81407370258060, meshId = "rbxassetid://118355105964202", size = { 55.104, 10.247, 55.119 } }
entries["pagoda_door_ring"] =
	{ assetId = 82855469548385, meshId = "rbxassetid://120580840342460", size = { 10.574, 11.685, 1.75 } }
entries["pagoda_foot_decor"] =
	{ assetId = 131431557755874, meshId = "rbxassetid://81801440786467", size = { 67.992, 4.841, 61.734 } }
entries["pagoda_foot_decor@candy"] =
	{ assetId = 117175946997069, meshId = "rbxassetid://120726478725509", size = { 67.992, 4.841, 61.734 } }
entries["pagoda_foot_decor@garden"] =
	{ assetId = 131596215167227, meshId = "rbxassetid://103316546776161", size = { 67.992, 4.841, 61.734 } }
entries["pagoda_foot_decor@mushroom"] =
	{ assetId = 76520474026279, meshId = "rbxassetid://96285729187812", size = { 67.992, 4.841, 61.734 } }
entries["pagoda_glass_1"] =
	{ assetId = 113809637257300, meshId = "rbxassetid://135293666163464", size = { 57.391, 8.6, 55.731 } }
entries["pagoda_glass_2"] =
	{ assetId = 139249922338428, meshId = "rbxassetid://95622805247523", size = { 52.388, 8.6, 50.788 } }
entries["pagoda_glass_3"] =
	{ assetId = 70492474595014, meshId = "rbxassetid://82083683806278", size = { 48.335, 8.6, 46.754 } }
entries["pagoda_glass_4"] =
	{ assetId = 122701413035312, meshId = "rbxassetid://105713796918183", size = { 45.338, 8.6, 43.861 } }
entries["pagoda_lamps"] =
	{ assetId = 130143762129897, meshId = "rbxassetid://102397767710976", size = { 6.283, 4.65, 5.9 } }
entries["pagoda_ramp"] =
	{ assetId = 126279512461305, meshId = "rbxassetid://100898647038470", size = { 15.939, 16.8, 15.697 } }
entries["pagoda_rim_extra@crystal"] =
	{ assetId = 112207482932872, meshId = "rbxassetid://123996857422761", size = { 64.356, 7.634, 63.294 } }
entries["pagoda_rim_extra@garden"] =
	{ assetId = 106408835425793, meshId = "rbxassetid://98811141616074", size = { 64.356, 7.634, 63.294 } }
entries["pagoda_rim_extra@mushroom"] =
	{ assetId = 118800140472797, meshId = "rbxassetid://89063606641604", size = { 64.356, 7.634, 63.294 } }
entries["pagoda_rim_extra@starlight"] =
	{ assetId = 115773610944899, meshId = "rbxassetid://91229799271505", size = { 64.356, 7.634, 63.294 } }
entries["pagoda_room_1"] =
	{ assetId = 87127519906460, meshId = "rbxassetid://122367356951883", size = { 58.991, 11.6, 57.285 } }
entries["pagoda_room_2"] =
	{ assetId = 74045087365557, meshId = "rbxassetid://128415717787430", size = { 54.408, 11.6, 52.338 } }
entries["pagoda_room_3"] =
	{ assetId = 88180810662379, meshId = "rbxassetid://76408220224411", size = { 50.418, 11.6, 48.299 } }
entries["pagoda_room_4"] =
	{ assetId = 133173844437587, meshId = "rbxassetid://100830450946866", size = { 47.447, 11.6, 45.406 } }
entries["pagoda_spots_mid"] =
	{ assetId = 136364760292103, meshId = "rbxassetid://125180031516674", size = { 58.925, 3.528, 60.119 } }
entries["pagoda_spots_mid@starlight"] =
	{ assetId = 94387196753433, meshId = "rbxassetid://74069222469689", size = { 58.925, 3.528, 60.119 } }
entries["pagoda_turret_cap"] =
	{ assetId = 107128114751964, meshId = "rbxassetid://121894473059537", size = { 18.4, 5.6, 18.4 } }
entries["pagoda_turret_mid"] =
	{ assetId = 135136188678352, meshId = "rbxassetid://115611381223656", size = { 18.8, 16.6, 18.8 } }
entries["pagoda_turret_top"] =
	{ assetId = 119399600127457, meshId = "rbxassetid://82664207844321", size = { 18.8, 27.2, 18.8 } }
entries["pagoda_vine_2"] =
	{ assetId = 140532652408205, meshId = "rbxassetid://72886498167688", size = { 24.004, 25.3, 32.129 } }
entries["pagoda_vine_3"] =
	{ assetId = 87863760361775, meshId = "rbxassetid://124742112527538", size = { 23.018, 40.678, 32.51 } }
entries["pagoda_vine_4"] =
	{ assetId = 97773448919319, meshId = "rbxassetid://118477830509433", size = { 21.981, 56, 32.797 } }
entries["pagoda_vine_glass_2"] =
	{ assetId = 89245828768651, meshId = "rbxassetid://112145908112745", size = { 17.024, 21.404, 28.347 } }
entries["pagoda_vine_glass_3"] =
	{ assetId = 79388803484608, meshId = "rbxassetid://72091308746733", size = { 15.626, 37.178, 28.801 } }
entries["pagoda_vine_glass_4"] =
	{ assetId = 112973821986352, meshId = "rbxassetid://131587695683133", size = { 14.963, 52.903, 29.161 } }
entries["rocket_boosters"] =
	{ assetId = 140052313154780, meshId = "rbxassetid://119866929059730", size = { 52.518, 14, 52.518 } }
entries["rocket_chute_2"] =
	{ assetId = 107171137880163, meshId = "rbxassetid://84232228215289", size = { 6.62, 23.156, 15.814 } }
entries["rocket_chute_3"] =
	{ assetId = 106433108661661, meshId = "rbxassetid://76651140132195", size = { 7.803, 39.136, 15.805 } }
entries["rocket_chute_4"] =
	{ assetId = 111114034888563, meshId = "rbxassetid://116099100380508", size = { 8.818, 55.146, 15.798 } }
entries["rocket_cockpit"] =
	{ assetId = 97242862099852, meshId = "rbxassetid://100485831138766", size = { 12.56, 7.6, 12.56 } }
entries["rocket_deck_2"] =
	{ assetId = 88522622392082, meshId = "rbxassetid://77176281034260", size = { 57.9, 16.6, 57.9 } }
entries["rocket_deck_3"] =
	{ assetId = 137717878173861, meshId = "rbxassetid://107006604734237", size = { 55.9, 16.6, 55.9 } }
entries["rocket_deck_4"] =
	{ assetId = 85591154704584, meshId = "rbxassetid://78001197654951", size = { 53.9, 16.6, 53.9 } }
entries["rocket_fins"] =
	{ assetId = 98008661450920, meshId = "rbxassetid://97449823691716", size = { 52.118, 25.5, 52.118 } }
entries["rocket_glass_1"] =
	{ assetId = 108050008782811, meshId = "rbxassetid://89107941907995", size = { 57.399, 9.6, 57.116 } }
entries["rocket_glass_2"] =
	{ assetId = 75659419965061, meshId = "rbxassetid://97534541336542", size = { 55.4, 9.6, 55.4 } }
entries["rocket_glass_3"] =
	{ assetId = 99522033898134, meshId = "rbxassetid://86649082453082", size = { 53.4, 9.6, 53.4 } }
entries["rocket_glass_4"] =
	{ assetId = 114333324177330, meshId = "rbxassetid://74043990154074", size = { 51.4, 9.6, 51.4 } }
entries["rocket_hull_1"] =
	{ assetId = 109172908502862, meshId = "rbxassetid://74314279160024", size = { 58.6, 16.4, 58.6 } }
entries["rocket_hull_2"] =
	{ assetId = 93702690207370, meshId = "rbxassetid://116950161205421", size = { 57.5, 16, 56.6 } }
entries["rocket_hull_3"] =
	{ assetId = 109498222238080, meshId = "rbxassetid://91142793539532", size = { 55.5, 16, 54.6 } }
entries["rocket_hull_4"] =
	{ assetId = 76436827629241, meshId = "rbxassetid://131859442863227", size = { 53.5, 16, 52.6 } }
entries["rocket_nose"] =
	{ assetId = 101870638284184, meshId = "rbxassetid://113060810279371", size = { 53.5, 43.4, 53.5 } }
entries["rocket_nose_trim"] =
	{ assetId = 96961830571291, meshId = "rbxassetid://111652453588588", size = { 45.74, 32.6, 45.74 } }
entries["rocket_post"] =
	{ assetId = 96370701560482, meshId = "rbxassetid://127632246821404", size = { 3.022, 16, 3.1 } }
entries["rocket_ramp"] =
	{ assetId = 136622445416088, meshId = "rbxassetid://109820891355436", size = { 16, 16.8, 15.727 } }
entries["rocket_ring_1"] =
	{ assetId = 71492379043643, meshId = "rbxassetid://98163829295210", size = { 59.5, 1.8, 59.5 } }
entries["rocket_ring_2"] =
	{ assetId = 95813332195686, meshId = "rbxassetid://114628044631476", size = { 57.5, 1.8, 57.5 } }
entries["rocket_ring_3"] =
	{ assetId = 111088281493979, meshId = "rbxassetid://87528485908567", size = { 55.5, 1.8, 55.5 } }
entries["rocket_ring_4"] =
	{ assetId = 125559197598612, meshId = "rbxassetid://107143459899473", size = { 53.5, 1.8, 53.5 } }
entries["snowglobe_chute_2"] =
	{ assetId = 103169910522225, meshId = "rbxassetid://139131495701520", size = { 11.305, 24.661, 17.021 } }
entries["snowglobe_chute_3"] =
	{ assetId = 76600070761616, meshId = "rbxassetid://95988354544383", size = { 7.782, 40.661, 17.021 } }
entries["snowglobe_chute_4"] =
	{ assetId = 102552294721456, meshId = "rbxassetid://88981690903118", size = { 10.787, 56.661, 17.021 } }
entries["snowglobe_chute_glass_2"] =
	{ assetId = 82813427015911, meshId = "rbxassetid://139472446475619", size = { 10.741, 20.307, 14.261 } }
entries["snowglobe_chute_glass_3"] =
	{ assetId = 133058916128097, meshId = "rbxassetid://107420425273005", size = { 7.445, 35.887, 14.684 } }
entries["snowglobe_chute_glass_4"] =
	{ assetId = 123149781132007, meshId = "rbxassetid://117920060239713", size = { 10.224, 51.629, 14.844 } }
entries["snowglobe_core"] =
	{ assetId = 88132690391383, meshId = "rbxassetid://97477944607889", size = { 16.045, 32.8, 16.049 } }
entries["snowglobe_crown"] =
	{ assetId = 104775270820948, meshId = "rbxassetid://123732450521576", size = { 14.3, 1.15, 14.3 } }
entries["snowglobe_deck"] =
	{ assetId = 136375782117252, meshId = "rbxassetid://132496059005379", size = { 58, 0.65, 58 } }
entries["snowglobe_decor"] =
	{ assetId = 70881649384939, meshId = "rbxassetid://94626085782456", size = { 58.126, 7.723, 46.293 } }
entries["snowglobe_dome_l"] =
	{ assetId = 113073524700407, meshId = "rbxassetid://117537619820035", size = { 59, 16, 59 } }
entries["snowglobe_dome_s"] =
	{ assetId = 132067858495742, meshId = "rbxassetid://116739034360965", size = { 53.22, 16, 53.22 } }
entries["snowglobe_glass_1"] =
	{ assetId = 87050844925487, meshId = "rbxassetid://121562090672681", size = { 57.54, 8.8, 57.28 } }
entries["snowglobe_glass_2"] =
	{ assetId = 99193842531790, meshId = "rbxassetid://119592250376268", size = { 58.854, 15.8, 58.854 } }
entries["snowglobe_glass_2t"] =
	{ assetId = 110047121198990, meshId = "rbxassetid://98578493642165", size = { 55.237, 15.2, 55.237 } }
entries["snowglobe_glass_3"] =
	{ assetId = 93392240542498, meshId = "rbxassetid://70930142318527", size = { 59.6, 15.6, 59.6 } }
entries["snowglobe_glass_4"] =
	{ assetId = 126064017463215, meshId = "rbxassetid://82885177487810", size = { 58.891, 15.6, 58.891 } }
entries["snowglobe_ped"] =
	{ assetId = 91127555129505, meshId = "rbxassetid://96302002950509", size = { 62.7, 16.3, 62.7 } }
entries["snowglobe_ped_gold"] =
	{ assetId = 101508199635085, meshId = "rbxassetid://112243204913059", size = { 63.172, 13.796, 63.144 } }
entries["snowglobe_pine"] =
	{ assetId = 73379709884413, meshId = "rbxassetid://86994482926982", size = { 34.071, 8.834, 4.655 } }
entries["snowglobe_post"] =
	{ assetId = 106589669619348, meshId = "rbxassetid://77166177216023", size = { 3.6, 16, 3.6 } }
entries["snowglobe_snow_2"] =
	{ assetId = 81094349713519, meshId = "rbxassetid://122344244443331", size = { 52.676, 14.312, 52.557 } }
entries["snowglobe_snow_3"] =
	{ assetId = 119157771534544, meshId = "rbxassetid://126949729236833", size = { 59.797, 13.04, 59.797 } }
entries["snowglobe_snow_4"] =
	{ assetId = 107338760166636, meshId = "rbxassetid://102749601053561", size = { 59.909, 14.494, 59.909 } }
entries["treehouse_canopy"] =
	{ assetId = 73632814361498, meshId = "rbxassetid://87303263734430", size = { 72.897, 23.764, 72.535 } }
entries["treehouse_deck_2"] =
	{ assetId = 122876544631635, meshId = "rbxassetid://94826074595749", size = { 57.6, 1.114, 57.6 } }
entries["treehouse_deck_3"] =
	{ assetId = 136582324113725, meshId = "rbxassetid://70865421707032", size = { 60.6, 1.114, 60.6 } }
entries["treehouse_deck_4"] =
	{ assetId = 105796152450169, meshId = "rbxassetid://87854457007909", size = { 62.6, 1.114, 62.6 } }
entries["treehouse_exit_pool"] =
	{ assetId = 129674300521979, meshId = "rbxassetid://122423153766969", size = { 7.8, 1.35, 7.8 } }
entries["treehouse_glass_1"] =
	{ assetId = 86042361574138, meshId = "rbxassetid://127487496918066", size = { 56.389, 10, 56.111 } }
entries["treehouse_glass_2"] =
	{ assetId = 108431907538088, meshId = "rbxassetid://115984949760766", size = { 56.4, 10, 56.4 } }
entries["treehouse_glass_3"] =
	{ assetId = 134097483818751, meshId = "rbxassetid://75540980548891", size = { 59.4, 10, 59.4 } }
entries["treehouse_glass_4"] =
	{ assetId = 74556092746458, meshId = "rbxassetid://130032199208903", size = { 61.4, 10, 61.4 } }
entries["treehouse_leaves_3"] =
	{ assetId = 125688699912454, meshId = "rbxassetid://122458740158063", size = { 63.538, 5.847, 70.471 } }
entries["treehouse_leaves_4"] =
	{ assetId = 138143949961855, meshId = "rbxassetid://123893943039948", size = { 66.333, 5.821, 72.087 } }
entries["treehouse_nest"] =
	{ assetId = 103916980404783, meshId = "rbxassetid://72445398959142", size = { 13.658, 2.634, 14.231 } }
entries["treehouse_post"] =
	{ assetId = 102515653437276, meshId = "rbxassetid://134032847756229", size = { 3.3, 16, 3.3 } }
entries["treehouse_ramp"] =
	{ assetId = 76092674935654, meshId = "rbxassetid://84194452088857", size = { 16.275, 16.821, 15.95 } }
entries["treehouse_rim_3"] =
	{ assetId = 117086823074765, meshId = "rbxassetid://103156818261872", size = { 61.1, 2.4, 61.1 } }
entries["treehouse_rim_4"] =
	{ assetId = 137810440027400, meshId = "rbxassetid://95136905910779", size = { 63.1, 2.4, 63.1 } }
entries["treehouse_room_1"] =
	{ assetId = 115411124068456, meshId = "rbxassetid://120943140392375", size = { 65.27, 16.142, 64.555 } }
entries["treehouse_room_2"] =
	{ assetId = 100579432789480, meshId = "rbxassetid://104238366255350", size = { 58.525, 15.4, 57.736 } }
entries["treehouse_room_3"] =
	{ assetId = 99868965563965, meshId = "rbxassetid://113663402166472", size = { 61.3, 13, 60.3 } }
entries["treehouse_room_4"] =
	{ assetId = 91349285982261, meshId = "rbxassetid://70509961694891", size = { 63.3, 13, 62.3 } }
entries["treehouse_slide_2"] =
	{ assetId = 89636812251293, meshId = "rbxassetid://129356299262094", size = { 6.714, 22.07, 15.287 } }
entries["treehouse_slide_3"] =
	{ assetId = 105940439657624, meshId = "rbxassetid://132430905764751", size = { 8.774, 38.075, 15.412 } }
entries["treehouse_slide_4"] =
	{ assetId = 84252555115751, meshId = "rbxassetid://124995312208499", size = { 8.372, 54.068, 15.394 } }
entries["treehouse_struts_3"] =
	{ assetId = 131105914810344, meshId = "rbxassetid://100094783216424", size = { 58.641, 2.021, 58.641 } }
entries["treehouse_struts_4"] =
	{ assetId = 74696050785664, meshId = "rbxassetid://70368866950103", size = { 60.75, 1.836, 60.75 } }
-- END base shape meshes
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
entries["slime_gummy"] = { assetId = 109275905134159, size = { 3.008, 2.95, 3.042 }, offset = { 0, 1.475, -0.017 } }
entries["slime_mochi"] = { assetId = 88468109163483, size = { 3.339, 2.159, 3.125 }, offset = { -0, 1.079, -0.014 } }
entries["slime_bubbles"] = { assetId = 136117360920606, size = { 3.299, 3.86, 3.47 }, offset = { -0.1, 1.93, -0.185 } }
entries["slime_pebble"] =
	{ assetId = 124134851993528, size = { 3.219, 2.823, 3.223 }, offset = { 0.032, 1.412, -0.003 } }
entries["slime_sprout"] = { assetId = 95596092652471, size = { 2.783, 4.029, 3.001 }, offset = { 0, 2.014, -0.036 } }
entries["slime_cheddar"] =
	{ assetId = 104100743814476, size = { 2.907, 2.549, 2.914 }, offset = { 0.005, 1.275, -0.009 } }
entries["slime_bumble"] = { assetId = 140176590528302, size = { 3.141, 3.9, 4.147 }, offset = { 0, 1.95, 0.384 } }
entries["slime_mushie"] = { assetId = 117092813936490, size = { 4.16, 3.493, 4.16 }, offset = { 0, 1.747, -0 } }
entries["slime_prickles"] =
	{ assetId = 128744905531044, size = { 4.864, 3.799, 3.05 }, offset = { -0.004, 1.899, 0.032 } }
entries["slime_froggo"] = { assetId = 71274428079528, size = { 3.698, 2.684, 3.113 }, offset = { 0, 1.311, -0.046 } }
entries["slime_flan"] = { assetId = 89380442384228, size = { 3.156, 3.97, 3.142 }, offset = { 0.004, 1.985, 0.009 } }
entries["slime_chomp"] = { assetId = 95926102417193, size = { 4.568, 3.62, 4.121 }, offset = { 0, 1.81, 0.368 } }
entries["slime_whiskers"] =
	{ assetId = 133896172858214, size = { 4.198, 3.003, 3.307 }, offset = { -0.347, 1.501, -0.024 } }
entries["slime_lop"] = { assetId = 107798862734190, size = { 3.541, 3.616, 3.447 }, offset = { 0.001, 1.808, 0.203 } }
entries["slime_moo"] = { assetId = 120951185287411, size = { 3.935, 2.915, 3.653 }, offset = { 0, 1.457, -0.105 } }
entries["slime_pengoo"] = { assetId = 96963913146270, size = { 4.596, 3.9, 3.2 }, offset = { 0, 1.947, -0.156 } }
entries["slime_blaze"] = { assetId = 136135987150514, size = { 3.36, 4.938, 3.159 }, offset = { -0.01, 2.469, -0.023 } }
entries["slime_frostbite"] =
	{ assetId = 137039779756480, size = { 3.165, 3.904, 3.207 }, offset = { 0, 1.952, -0.021 } }
entries["slime_zap"] = { assetId = 80334558020467, size = { 4.078, 3.688, 3.418 }, offset = { 0, 1.844, -0.003 } }
entries["slime_imp"] = { assetId = 84166464527451, size = { 4.596, 3.491, 3.884 }, offset = { 0, 1.746, 0.443 } }
entries["slime_octo"] = { assetId = 121886155113536, size = { 5.058, 3.495, 4.192 }, offset = { 0, 1.673, -0.141 } }
entries["slime_drako"] = { assetId = 85981669582151, size = { 4.194, 3.272, 4 }, offset = { 0, 1.636, 0.323 } }
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
	{ assetId = 73912580635466, size = { 4.872, 4.374, 3.447 }, offset = { 0.039, 2.114, 0.089 } }
entries["slime_sir_goo"] =
	{ assetId = 86600172378002, size = { 4.595, 4.834, 3.745 }, offset = { 0.165, 2.417, -0.077 } }
entries["slime_phoenix"] =
	{ assetId = 112027311988161, size = { 6.524, 4.458, 5.718 }, offset = { -0.096, 2.229, 0.842 } }
entries["slime_sunny"] =
	{ assetId = 76150467529446, size = { 5.386, 4.365, 3.049 }, offset = { -0.114, 1.829, -0.035 } }
entries["slime_elder_oak"] =
	{ assetId = 116150728691082, size = { 5.105, 5.144, 4.5 }, offset = { 0.003, 2.502, 0.074 } }
entries["slime_gaia"] = { assetId = 83101861537427, size = { 4.999, 4.34, 4.201 }, offset = { 0.049, 2.17, -0.108 } }
entries["slime_captain_goo"] =
	{ assetId = 85380821433285, size = { 3.535, 4.68, 3.486 }, offset = { -0.042, 2.34, -0.234 } }
entries["slime_yeti"] = { assetId = 87284738623950, size = { 4.645, 3.526, 4.118 }, offset = { -0.053, 1.763, 0.168 } }
entries["slime_abyss"] = { assetId = 70673494347652, size = { 5.346, 4.135, 4.888 }, offset = { 0, 2.067, 0.044 } }
entries["slime_lunara"] = { assetId = 90322048434782, size = { 4.903, 4.264, 4.244 }, offset = { -0.202, 1.835, -0 } }
entries["slime_solaris"] = { assetId = 137966278045601, size = { 5.78, 4.881, 3.219 }, offset = { 0, 2.141, -0.024 } }
entries["slime_nebulon"] =
	{ assetId = 137952210983806, size = { 5.053, 4.384, 5.215 }, offset = { 0.034, 2.192, 0.82 } }
entries["slime_aurora"] = { assetId = 81245681557355, size = { 4.638, 5.097, 3.874 }, offset = { -0.015, 2.548, -0 } }
entries["slime_goo_oracle"] = { assetId = 83004446733675, size = { 4.565, 4.65, 4.565 }, offset = { 0, 2.325, -0 } }
entries["slime_kirin"] = { assetId = 80680478341458, size = { 5.053, 4.182, 4.226 }, offset = { 0.107, 2.091, 0.297 } }
entries["slime_jackpot"] =
	{ assetId = 107540085780098, size = { 4.955, 4.626, 3.798 }, offset = { -0.023, 2.137, 0.186 } }
entries["slime_star_emperor"] =
	{ assetId = 110613916638021, size = { 4.902, 4.453, 4.495 }, offset = { -0.206, 2.157, 0.698 } }
entries["slime_goo_god"] =
	{ assetId = 130069852439424, size = { 7.565, 6.557, 4.401 }, offset = { -0.12, 3.278, 0.209 } }
entries["slime_boo"] = { assetId = 96310373601330, size = { 4.198, 3.849, 2.926 }, offset = { 0.015, 1.846, -0.002 } }

entries["slime_soda"] = { assetId = 95888248190580, size = { 3.602, 4.483, 3.1 }, offset = { -0.08, 2.242, -0.023 } }
entries["slime_rocky_road"] =
	{ assetId = 74244309584071, size = { 3.137, 3.518, 3.138 }, offset = { 0.009, 1.759, 0.004 } }
entries["slime_bloom"] = { assetId = 99167270842330, size = { 4.607, 3.658, 4.751 }, offset = { 0, 1.829, -0.092 } }
entries["slime_honey_toad"] = { assetId = 76639819710103, size = { 3.698, 2.903, 3.181 }, offset = { 0, 1.42, -0.012 } }
entries["slime_truffle"] =
	{ assetId = 107050144207287, size = { 3.813, 5.14, 3.734 }, offset = { -0.004, 2.57, 0.033 } }
entries["slime_sushi"] = { assetId = 79864638354637, size = { 3.734, 3.746, 3.529 }, offset = { -0.201, 1.873, 0.314 } }
entries["slime_snow_bunny"] = { assetId = 122177895345867, size = { 3.482, 4.842, 3.482 }, offset = { 0, 2.376, -0 } }
entries["slime_moo_shroom"] =
	{ assetId = 110396997416743, size = { 3.993, 3.467, 3.882 }, offset = { 0, 1.734, -0.021 } }
entries["slime_catfish"] = { assetId = 76770603623417, size = { 4.699, 3.573, 4.43 }, offset = { 0, 1.764, 0.481 } }
entries["slime_steam"] = { assetId = 107367947074628, size = { 4.794, 4.72, 3.335 }, offset = { 0, 2.36, 0.005 } }
entries["slime_kraken"] =
	{ assetId = 70503828098080, size = { 5.49, 4.449, 4.185 }, offset = { -0.025, 2.215, -0.041 } }
entries["slime_thunderbee"] =
	{ assetId = 131233135861150, size = { 4.66, 4.321, 4.21 }, offset = { -0.03, 2.16, 0.376 } }
entries["slime_cyber_ninja"] =
	{ assetId = 116106560463464, size = { 3.697, 3.63, 4.006 }, offset = { -0.04, 1.815, 0.441 } }
entries["slime_dragon_king"] =
	{ assetId = 88961374433419, size = { 5.566, 4.129, 4.424 }, offset = { 0, 2.065, 0.301 } }
entries["slime_nightwing"] =
	{ assetId = 112164365401063, size = { 6.262, 4.163, 3.802 }, offset = { 0.036, 2.081, 0.378 } }
entries["slime_goozilla"] = { assetId = 95597031533993, size = { 3.204, 3.927, 5.049 }, offset = { 0, 1.907, 0.617 } }
entries["slime_queen_jelly"] =
	{ assetId = 108716301261458, size = { 4.401, 4.653, 4.403 }, offset = { -0.032, 2.337, 0.024 } }
entries["slime_klawdius"] =
	{ assetId = 110829970779610, size = { 6.072, 5.292, 5.219 }, offset = { 0.445, 2.641, 1.039 } }
entries["slime_pumpking"] = { assetId = 95135050927158, size = { 3.54, 4.066, 3.575 }, offset = { 0, 2.033, -0.018 } }
entries["slime_mecha_goo"] = { assetId = 78640546070601, size = { 4.48, 3.5, 3.568 }, offset = { 0, 1.75, 0.097 } }
entries["slime_goomancer"] =
	{ assetId = 118089713951424, size = { 4.683, 6.309, 3.725 }, offset = { 0.447, 3.042, -0.075 } }
entries["slime_glitch"] =
	{ assetId = 112653965607800, size = { 5.349, 4.23, 3.126 }, offset = { -0.037, 2.115, -0.013 } }
entries["slime_doodle"] = { assetId = 74559390612314, size = { 4.192, 4.199, 3.276 }, offset = { 0, 2.025, -0.041 } }
entries["slime_origami"] = { assetId = 102661066928788, size = { 6.542, 4.521, 4.442 }, offset = { 0, 2.261, 0.608 } }
entries["slime_disco"] = { assetId = 89692353422465, size = { 5.368, 3.97, 3.525 }, offset = { -0.095, 1.985, -0.073 } }
entries["slime_isle"] = { assetId = 106246529336627, size = { 4.667, 5.736, 3.95 }, offset = { 0.055, 2.818, 0.298 } }
entries["slime_chrono"] = { assetId = 80629324297687, size = { 4.982, 4.791, 3.6 }, offset = { 0.013, 2.355, -0 } }
entries["slime_kitsune"] = { assetId = 129157153377304, size = { 7.571, 5.424, 3.518 }, offset = { -0, 2.712, 0.212 } }

-- BEGIN slime mutation kits (generated by shared/modeling-kit/tools/slime_mutation_assets.py from uploaded.json):
-- species kit -> its recoloured copies (Config.SHINES `kit`), uploaded as slime_<id>_<kit>.
local MUTATION_KITS: { [string]: { [string]: number } } = {
	slime_abyss = { gold = 130752526095676, diamond = 99595211141238, rainbow = 84124421629684 },
	slime_amethyst = { gold = 84278709906678, diamond = 71186579061119, rainbow = 88261177876998 },
	slime_aurora = { gold = 136519138661384, diamond = 120837621508915, rainbow = 105724255427244 },
	slime_blaze = { gold = 135038290808769, diamond = 109212172370883, rainbow = 106910337305634 },
	slime_bloom = { gold = 116052315338572, diamond = 94969873856756, rainbow = 86871539117607 },
	slime_boo = { gold = 70928934024964, diamond = 74825642288313, rainbow = 78370871236505 },
	slime_bubbles = { gold = 134295301398243, diamond = 107800924435158, rainbow = 111547889653021 },
	slime_bumble = { gold = 130545766782378, diamond = 134704133573966, rainbow = 90655781731415 },
	slime_captain_goo = { gold = 110300070027142, diamond = 89174340318594, rainbow = 99403054079535 },
	slime_catfish = { gold = 110748658492337, diamond = 105732280863227, rainbow = 108774914053403 },
	slime_cheddar = { gold = 138566619155001, diamond = 87996814270519, rainbow = 139727493879660 },
	slime_chomp = { gold = 123023351381862, diamond = 131866935889265, rainbow = 84590715086785 },
	slime_chrono = { gold = 97302754826453, diamond = 115292627583485, rainbow = 115270812735238 },
	slime_cosmo = { gold = 139693366547896, diamond = 75883720225623, rainbow = 104390417850984 },
	slime_cyber_ninja = { gold = 72579230608567, diamond = 85975313964751, rainbow = 116737312278055 },
	slime_disco = { gold = 116158235024765, diamond = 125295447538335, rainbow = 139153045518875 },
	slime_doodle = { gold = 111875125532423, diamond = 98956841690152, rainbow = 105573554498703 },
	slime_dragon_king = { gold = 80982030895976, diamond = 122686640672138, rainbow = 92949441871895 },
	slime_drako = { gold = 87255040439464, diamond = 98657003399391, rainbow = 135779176995405 },
	slime_eclipse = { gold = 79223700740135, diamond = 83068176697500, rainbow = 81243830287985 },
	slime_elder_oak = { gold = 72146799571397, diamond = 125005442001464, rainbow = 119198346119864 },
	slime_flan = { gold = 124122755224247, diamond = 86457904290316, rainbow = 99936302566424 },
	slime_froggo = { gold = 70932644534767, diamond = 101277614931111, rainbow = 97125953467580 },
	slime_frostbite = { gold = 112805318563194, diamond = 81270950060940, rainbow = 104032973539899 },
	slime_gaia = { gold = 123413957193829, diamond = 128011632034134, rainbow = 133842599983926 },
	slime_glitch = { gold = 129092413867689, diamond = 133446861665042, rainbow = 100054785253321 },
	slime_goo_god = { gold = 125869469106381, diamond = 86591318283644, rainbow = 99762031897441 },
	slime_goo_oracle = { gold = 124089853469317, diamond = 92345138680903, rainbow = 79989390452200 },
	slime_goomancer = { gold = 110095077103476, diamond = 124977267958924, rainbow = 126436943881919 },
	slime_goozilla = { gold = 79516927192628, diamond = 114401767762372, rainbow = 78414750715171 },
	slime_gummy = { gold = 109796297282310, diamond = 80126405368205, rainbow = 134648467278318 },
	slime_honey_toad = { gold = 72220949388576, diamond = 105593769874077, rainbow = 101709493345318 },
	slime_imp = { gold = 78216038798684, diamond = 118679779091877, rainbow = 73151335820569 },
	slime_isle = { gold = 131547866360085, diamond = 100669194703638, rainbow = 73093119071591 },
	slime_jackpot = { gold = 77840749435074, diamond = 100402188007670, rainbow = 122771893003189 },
	slime_king = { gold = 114158119095548, diamond = 78158177464186, rainbow = 131294972470544 },
	slime_kirin = { gold = 115498826558859, diamond = 97180865512161, rainbow = 84344753067070 },
	slime_kitsune = { gold = 111290254648607, diamond = 80407267293559, rainbow = 73772203119608 },
	slime_klawdius = { gold = 77330949205161, diamond = 70910540393816, rainbow = 89635269272285 },
	slime_kraken = { gold = 137466094323805, diamond = 102702723671558, rainbow = 74868165919916 },
	slime_lop = { gold = 92838711523309, diamond = 95360695872204, rainbow = 86599388226799 },
	slime_lunara = { gold = 106145059844956, diamond = 104510678821137, rainbow = 112817087580720 },
	slime_mecha_goo = { gold = 70479561675819, diamond = 136100240993127, rainbow = 86760621458396 },
	slime_midas = { gold = 82938555333582, diamond = 77918161552560, rainbow = 73267095716663 },
	slime_mochi = { gold = 103950149714490, diamond = 126212381520921, rainbow = 112619750529512 },
	slime_moo = { gold = 111475551674608, diamond = 80955397447064, rainbow = 130037060968913 },
	slime_moo_shroom = { gold = 110604795743667, diamond = 109975354720528, rainbow = 91987228201821 },
	slime_mushie = { gold = 94121714043651, diamond = 78451069460247, rainbow = 103870709434167 },
	slime_nebulon = { gold = 82907829736337, diamond = 132322877771659, rainbow = 110333504714442 },
	slime_nightwing = { gold = 100905451630474, diamond = 78841507939956, rainbow = 118158765641959 },
	slime_ninja = { gold = 130152648545485, diamond = 91527103514069, rainbow = 89669721722951 },
	slime_octo = { gold = 101404496627623, diamond = 119760291801208, rainbow = 122258521375801 },
	slime_origami = { gold = 121097522814869, diamond = 78882100726781, rainbow = 115923078581027 },
	slime_pebble = { gold = 135719996117803, diamond = 133077544710485, rainbow = 95036057210554 },
	slime_pengoo = { gold = 119638384600766, diamond = 95300454822873, rainbow = 128665336308987 },
	slime_phoenix = { gold = 89759461851516, diamond = 70991918474258, rainbow = 101203148428790 },
	slime_prickles = { gold = 73737617655316, diamond = 94746814323559, rainbow = 70467383459434 },
	slime_prism = { gold = 117781783166257, diamond = 106448708996923, rainbow = 79061622219053 },
	slime_pumpking = { gold = 108602521849603, diamond = 77865267342356, rainbow = 113445129231871 },
	slime_queen_jelly = { gold = 84360364505000, diamond = 132493787075448, rainbow = 89139991540834 },
	slime_robo = { gold = 79566222101865, diamond = 121930628967243, rainbow = 92208512757139 },
	slime_rocky_road = { gold = 89551875816971, diamond = 134759994144094, rainbow = 137226209680315 },
	slime_seraph = { gold = 89443376091520, diamond = 71629619284640, rainbow = 130726140871904 },
	slime_sir_goo = { gold = 136826046378735, diamond = 93496332418178, rainbow = 89186048311564 },
	slime_snow_bunny = { gold = 93951227268562, diamond = 118409542751151, rainbow = 94795012155603 },
	slime_soda = { gold = 107638507514907, diamond = 71537072111787, rainbow = 80745466870079 },
	slime_solaris = { gold = 137113796395576, diamond = 132075351659821, rainbow = 93783438093091 },
	slime_sprout = { gold = 84024136104950, diamond = 107136418493294, rainbow = 106211813164404 },
	slime_star_emperor = { gold = 92928146665766, diamond = 79195901213468, rainbow = 73528075971250 },
	slime_steam = { gold = 121648537435306, diamond = 118488993793004, rainbow = 80313774343563 },
	slime_sunny = { gold = 134557058862014, diamond = 83372667654524, rainbow = 136693776536142 },
	slime_sushi = { gold = 87971682363772, diamond = 115448894969726, rainbow = 75980041401133 },
	slime_thunderbee = { gold = 114764714341420, diamond = 75218905376148, rainbow = 130338595991284 },
	slime_truffle = { gold = 126094096167605, diamond = 86004917454697, rainbow = 80321373555079 },
	slime_whiskers = { gold = 106588493426473, diamond = 105563612078180, rainbow = 99609813211597 },
	slime_yeti = { gold = 93721856953515, diamond = 109025950288420, rainbow = 96807338556020 },
	slime_zap = { gold = 130446278002495, diamond = 128300838743825, rainbow = 81665944059253 },
}
-- END slime mutation kits

-- A recoloured copy is the species mesh with other vertex colours: it wears the species' size and offset.
for kit, copies in MUTATION_KITS do
	local base = entries[kit]
	if base then
		for suffix, assetId in copies do
			entries[`{kit}_{suffix}`] = { assetId = assetId, size = base.size, offset = base.offset }
		end
	end
end

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
	-- the Item / Upgrade Shop stands (CONTRACT.md §27.2): a solid counter, not a box to stand inside
	ranch_item_shop = "Hull",
	ranch_upgrade_cabinet = "Hull",
	-- the slime stands on every pad (WorldLayout padNode): a round cork stand players bump into and stand on
	goo_cork_stand = "Hull",

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
	-- boxy ranch props (Box, or Default where a box would leave invisible space)
	ranch_crate = "Box", -- 3x3x3 cube
	ranch_crate_goo = "Box", -- 3x3x3 cube
	ranch_feed_trough = "Box", -- 6x2.3x2.5 low box, nobody walks inside
	ranch_hay_bale = "Box", -- 4x2.6x2.6 bale
	ranch_bench = "Default", -- 6x4x2.4 bench with a back: Default follows seat and back (a Box stands players on air 2.4 over the seat)
	ranch_compost_bin = "Default", -- 5.5x4.8x5.3 slatted bin: Default follows the slats (a Box stands players up to 4 studs on air)
	ranch_flower_planter = "Box", -- 5.2x3.2x2 planter box
	ranch_goo_sign = "Default", -- 8.8x8.2x3.7 signboard on two posts: Default follows board and posts (a Box stops walkers 2 studs short)
	ranch_hitching_post = "Default", -- 7.3x4.8x3.2 rail between posts: Default follows rail and posts (a Box stands players on air over the gap)
	ranch_mailbox = "Box", -- 1.4x5.4x2.7 box on a post
	ranch_picnic_table = "Box", -- 8.1x3.4x6 table with benches
	ranch_tool_rack = "Box", -- 7.7x8x3 rack of tools, a flat wall
	ranch_wagon = "Default", -- 9.9x3x5.8 cart, flat bed to stand on: Default follows bed and wheels (a Box stops walkers 1.5 studs out)
	ranch_water_trough = "Box", -- 9.7x3.6x3.2 low box
	-- blobby and roofed ranch props: Hull (Default where a hull would leave invisible space)
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
	ranch_slime_coop = "Default", -- 7.4x7.7x7.8 gabled coop: Default follows the walls (a Hull stops walkers 1.5 studs short)
	ranch_water_pump = "Hull", -- 3.8x4.4x4.9 pump
	ranch_weathervane = "Hull", -- 5x8.6x3.4 vane on a pole
	ranch_well = "Box", -- 6.9x7.7x5.5 stone well with a roof: nobody falls into or walks under it; the box is the ring + roof footprint (v196: Hull let pushes slide round)
	ranch_wheelbarrow = "Hull", -- 6.6x3.5x3.8 wheelbarrow
	ranch_windmill = "Default", -- 8.4x17.4x9.7 tower with sails: Default keeps tower and sails apart (a Hull wraps the sails and stands players 16 studs up on air)
	-- the sand yard's dressing (YardProps) reuses border meshes; the same meshes also stand behind the border wall, where
	-- nobody reaches them, so they are solid there too. Yard trees collide through trunk posts (WorldLayout), not a mesh.
	ranch_border_rock_boulder = "Hull", -- 11.8x6.7x7.6 boulder: solid, players climb over it
	ranch_border_rock_cluster = "Hull", -- 14.2x4.8x9.2 low cluster of rocks
	ranch_border_rock_slab = "Hull", -- 13.8x3.2x6.6 flat rock slab
	ranch_border_fence_straight = "Box", -- a straight fence panel, a flat wall
	ranch_border_hedge_long = "Box", -- a long hedge, a flat wall
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

-- The recoloured copy of species kit `kit` for a Config.SHINES row's `kit` suffix ("slime_mochi" + "gold" ->
-- "slime_mochi_gold"), or nil when that copy isn't uploaded (the slime keeps its species kit).
function MeshAssets.mutationKit(kit: string?, suffix: string?): string?
	if kit == nil or suffix == nil then
		return nil
	end
	local name = `{kit}_{suffix}`
	local e = entries[name]
	return if e and e.assetId then name else nil
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
