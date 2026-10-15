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
}

local entries: { [string]: Entry } = {}
entries["slime_fountain"] = { assetId = 137335028699292, meshId = "rbxassetid://109732747899788", size = { 54.45, 43.3, 63.851 } }
entries["phoenix_fence_segment"] = { assetId = 92327721520041, meshId = "rbxassetid://127187149466504", size = { 11, 9.02, 1.8 } }
entries["phoenix_corner_post"] = { assetId = 122993526477202, meshId = "rbxassetid://119122479393270", size = { 2.8, 9.689, 2.8 } }
entries["phoenix_gate"] = { assetId = 92840827180297, meshId = "rbxassetid://95862556594894", size = { 20.2, 13.4, 2.6 } }
entries["phoenix_pad_crate"] = { assetId = 122007188029546, meshId = "rbxassetid://78946442257134", size = { 7.8, 2.61, 7.8 } }
entries["phoenix_pad_hay"] = { assetId = 140052030266744, meshId = "rbxassetid://113376925245833", size = { 7.957, 2.052, 7.715 } }
entries["phoenix_pad_goo"] = { assetId = 108913920722728, meshId = "rbxassetid://85372957549244", size = { 7.834, 2.09, 7.861 } }
entries["phoenix_pad_stool"] = { assetId = 75412207782571, meshId = "rbxassetid://91205766247208", size = { 7.019, 3.344, 7.2 } }
entries["phoenix_top_earners_board"] = { assetId = 126155085567089, meshId = "rbxassetid://98390738410954", size = { 21.103, 19.934, 4.097 } }
entries["ranch_plaza_signpost"] = { assetId = 131934867179344, meshId = "rbxassetid://73448923703025", size = { 12.648, 14.515, 7.55 } }
entries["ranch_shop_stand"] = { assetId = 102942641234419, meshId = "rbxassetid://93701432819080", size = { 12.01, 14.15, 7.454 } }
entries["phoenix_plaza_podium_1"] = { assetId = 77650457545661, meshId = "rbxassetid://94983834296700", size = { 8.923, 7.192, 8.58 } }
entries["phoenix_plaza_podium_2"] = { assetId = 97620670705737, meshId = "rbxassetid://105418025189003", size = { 8.281, 5.198, 7.991 } }
entries["phoenix_plaza_podium_3"] = { assetId = 131978647736381, meshId = "rbxassetid://83534651387040", size = { 7.907, 4.093, 7.586 } }
entries["ranch_crate"] = { assetId = 113390790867779, meshId = "rbxassetid://120918291298344", size = { 3, 3, 3 } }
entries["ranch_crate_goo"] = { assetId = 127060204046625, meshId = "rbxassetid://72755843253725", size = { 3, 3, 3 } }
entries["ranch_feed_trough"] = { assetId = 122284008329780, meshId = "rbxassetid://118620263144053", size = { 5.95, 2.32, 2.509 } }
entries["ranch_hay_bale"] = { assetId = 108180914521962, meshId = "rbxassetid://83011141223539", size = { 4, 2.617, 2.56 } }
entries["ranch_shed"] = { assetId = 84203174193070, meshId = "rbxassetid://78762155869477", size = { 10.55, 9.33, 8.55 } }

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
