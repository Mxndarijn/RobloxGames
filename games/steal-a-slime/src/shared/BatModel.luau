--!strict
--[[
	BatModel (the ONE place to hook up the Bat's look)

	The Bat's look is wired HERE: MESH_ID comes from MeshAssets "ranch_bat", ICON_ID is ItemIcons Pvp_Bat. A new mesh /
	icon is a one-line change of those two.
	If MESH_ID is nil or the mesh fails to load the Bat is a plain single-Part placeholder (a wood-coloured block, no collision);
	server/BatTool builds the handle with AssetService:CreateMeshPartAsync(MESH_ID) when MESH_ID is set and falls back
	to the placeholder if that fails. SIZE is the handle's size in studs (the mesh is fitted to it); GRIP is the
	Tool.Grip offset (position studs, rotation degrees) so the model sits right in the hand: tune it with the mesh.
	ICON_ID is the Roblox image asset for the Tool's backpack slot (Tool.TextureId); nil = the tool shows its name.
]]

local MeshAssets = if script then require(script.Parent.MeshAssets) else require("./MeshAssets")

local BatModel = {}

local entry = MeshAssets.get("ranch_bat") -- Archer's kit mesh (#307): 606 tris, pommel at the bottom, long axis Y, no collision
BatModel.MESH_ID = if entry then entry.meshId else nil :: string? -- nil = the placeholder block below
BatModel.ICON_ID = "rbxassetid://107609481658581" :: string? -- ItemIcons Pvp_Bat (a spec keeps it equal to ItemIcons.IMAGES.Pvp_Bat)
BatModel.SIZE = if entry and entry.size then entry.size else { 1.351, 5.09, 1.351 } -- studs, the mesh's native size
BatModel.GRIP = { pos = { 0, -1.345, 0 }, rotDeg = { 0, 0, 0 } } -- the red wrap centre, 1.2 above the pommel
BatModel.COLOR = { 0.72, 0.5, 0.28 } -- placeholder wood colour (RGB 0..1)
BatModel.SWING_SOUND = "rbxassetid://12222216" -- whoosh on every swing (classic library sword slash)

return BatModel
