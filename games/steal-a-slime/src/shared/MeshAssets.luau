--!strict
--[[
	MeshAssets (owner: Phoenix)

	Slime Ranch kit meshes (shared/modeling-kit/out/*.fbx), keyed by kit name.
	WorldLayout tags placeholder Parts with the attribute MeshAsset = <name>;
	server/MeshSwap replaces their look with AssetService:CreateMeshPartAsync
	(scripts can't set MeshId on an existing MeshPart). A name whose meshId is
	still nil keeps its primitive placeholder, so the map plays without uploads.

	Fill meshId / assetId from shared/modeling-kit/uploaded.json once the kit
	upload lands ("rbxassetid://<id>"). size = the mesh's native size (studs)
	if known; MeshSwap fits the MeshPart to the placeholder box either way.
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
for _, name in NAMES do
	entries[name] = {} -- TODO(upload): ids from shared/modeling-kit/uploaded.json
end

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
