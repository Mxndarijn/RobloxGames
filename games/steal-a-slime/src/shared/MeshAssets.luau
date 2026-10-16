--!strict
--[[
	MeshAssets (owner: Phoenix)

	Slime Ranch kit meshes (shared/modeling-kit/out/*.fbx), keyed by kit name.
	WorldLayout tags placeholder Parts with the attribute MeshAsset = <name>;
	server/MeshSwap replaces their look with AssetService:CreateMeshPartAsync
	(scripts can't set MeshId on an existing MeshPart). A name whose meshId is
	still nil keeps its primitive placeholder, so the map plays without uploads.

	Filled from shared/modeling-kit/uploaded.json (Open Cloud Model uploads).
	size = the mesh's native size (studs); MeshSwap fits the MeshPart to the
	placeholder box either way.
]]

export type Entry = { assetId: number?, meshId: string?, size: { number }? }

local NAMES = {
	"slime_fountain",
	"phoenix_fence_segment",
	"phoenix_corner_post",
	"phoenix_gate",
	"phoenix_pad_crate",
	"phoenix_pad_hay",
	"phoenix_pad_goo",
	"phoenix_pad_stool",
	"phoenix_top_earners_board",
	"ranch_plaza_signpost",
	"ranch_shop_stand",
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
	"phoenix_pad_barrel_top",
	"phoenix_pad_flower_bed",
	"phoenix_pad_mushroom",
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
	"slime_fountain_emerge",
}

local entries: { [string]: Entry } = {}
-- Size is the polished FBX bbox (goo polish, ~43.316 tall). The asset id is
-- still the previous upload: Open Cloud was not available to re-upload
-- out/slime_fountain.fbx. The WorldLayout slot uses this same box.
entries["slime_fountain"] =
	{ assetId = 137335028699292, meshId = "rbxassetid://109732747899788", size = { 54.45, 43.316, 63.851 } }
entries["phoenix_fence_segment"] =
	{ assetId = 92327721520041, meshId = "rbxassetid://127187149466504", size = { 11, 9.02, 1.8 } }
entries["phoenix_corner_post"] =
	{ assetId = 122993526477202, meshId = "rbxassetid://119122479393270", size = { 2.8, 9.689, 2.8 } }
entries["phoenix_gate"] =
	{ assetId = 92840827180297, meshId = "rbxassetid://95862556594894", size = { 20.2, 13.4, 2.6 } }
entries["phoenix_pad_crate"] =
	{ assetId = 122007188029546, meshId = "rbxassetid://78946442257134", size = { 7.8, 2.61, 7.8 } }
entries["phoenix_pad_hay"] =
	{ assetId = 140052030266744, meshId = "rbxassetid://113376925245833", size = { 7.957, 2.052, 7.715 } }
entries["phoenix_pad_goo"] =
	{ assetId = 108913920722728, meshId = "rbxassetid://85372957549244", size = { 7.834, 2.09, 7.861 } }
entries["phoenix_pad_stool"] =
	{ assetId = 75412207782571, meshId = "rbxassetid://91205766247208", size = { 7.019, 3.344, 7.2 } }
entries["phoenix_top_earners_board"] =
	{ assetId = 126155085567089, meshId = "rbxassetid://98390738410954", size = { 21.103, 19.934, 4.097 } }
entries["ranch_plaza_signpost"] =
	{ assetId = 131934867179344, meshId = "rbxassetid://73448923703025", size = { 12.648, 14.515, 7.55 } }
entries["ranch_shop_stand"] =
	{ assetId = 102942641234419, meshId = "rbxassetid://93701432819080", size = { 12.01, 14.15, 7.454 } }
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
-- 2026-10-16 upload (landing ring, goo drain, ranch/pad props).
entries["phoenix_pad_barrel_top"] =
	{ assetId = 82809982076949, meshId = "rbxassetid://83664398449787", size = { 7.6, 2.4, 7.084 } }
entries["phoenix_pad_flower_bed"] =
	{ assetId = 77026508844150, meshId = "rbxassetid://118881206271839", size = { 7.788, 2.4, 7.788 } }
entries["phoenix_pad_mushroom"] =
	{ assetId = 111001907276189, meshId = "rbxassetid://116498512852323", size = { 7.8, 3, 7.682 } }
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
	{ assetId = 126479458852729, meshId = "rbxassetid://105175088358977", size = { 13.145, 3.145, 10.27 } }
entries["ranch_lantern_post"] =
	{ assetId = 124004679363569, meshId = "rbxassetid://99456773451008", size = { 3.65, 9.3, 1.6 } }
entries["ranch_log_pile"] =
	{ assetId = 112182235851209, meshId = "rbxassetid://107529832767130", size = { 10.935, 4.011, 6.812 } }
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
entries["slime_fountain_emerge"] =
	{ assetId = 100517882708695, meshId = "rbxassetid://74501501975558", size = { 19.436, 12.798, 11.353 } }

local MeshAssets = {}
MeshAssets.NAMES = table.freeze(NAMES)
MeshAssets.entries = entries

function MeshAssets.get(name: string): Entry?
	return entries[name]
end

-- The rbxassetid string for `name`, or nil while it isn't uploaded.
function MeshAssets.meshId(name: string): string?
	local e = entries[name]
	return e and e.meshId
end

return MeshAssets
