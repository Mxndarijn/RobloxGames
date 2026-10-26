--!strict
--[[
	ThemeMeshes

	Which kit mesh a plot's slot shows under the owner's plot skin (CONTRACT.md §15). A themed mesh is the same piece
	in the skin's colours, named "<mesh>@<skin>" and built to the classic piece's box, so it drops into the classic
	slot. Companions are a theme's extra meshes that ride on one piece (the props on the foot, the hat on the mascot):
	`companion` gives the box they take, from the boxes in Visuals.JarMeshes (each round the piece's build anchor).
	server/MeshSwap uses both. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Box = { size: { number }, centre: { number } }

local ThemeMeshes = {}

-- piece mesh -> the companion mesh a theme may add on it ("<companion>@<skin>")
ThemeMeshes.COMPANIONS = table.freeze({
	goo_jar_foot = "goo_jar_props",
	goo_jar_mascot = "goo_jar_hat",
} :: { [string]: string })

local function themed(skin: any): string?
	if type(skin) == "string" and skin ~= Config.PLOT_SKIN_DEFAULT then
		return skin
	end
	return nil
end

-- The mesh a slot for `mesh` shows under `skin`: "<mesh>@<skin>" when `has` says that mesh exists, else `mesh`.
function ThemeMeshes.look(mesh: string, skin: any, has: (string) -> boolean): string
	local id = themed(skin)
	local name = if id then `{mesh}@{id}` else nil
	return if name and has(name) then name else mesh
end

-- The companion mesh `skin` adds on a `mesh` slot, or nil (no companion for that piece, classic, or not built).
function ThemeMeshes.companion(mesh: string, skin: any, has: (string) -> boolean): string?
	local id = themed(skin)
	local base = ThemeMeshes.COMPANIONS[mesh]
	local name = if id and base then `{base}@{id}` else nil
	return if name and has(name) then name else nil
end

-- Where a companion stands on its piece's slot: the slot holds the piece's box scaled by `scale`; the result is the
-- companion's size and its centre's offset in the slot's own axes. Jar slots turn half round from the build axes
-- (WorldLayout jarLook adds 180 degrees), so x and z flip.
function ThemeMeshes.place(piece: Box, companion: Box, scale: number): ({ number }, { number })
	local size = { companion.size[1] * scale, companion.size[2] * scale, companion.size[3] * scale }
	local offset = {
		-(companion.centre[1] - piece.centre[1]) * scale,
		(companion.centre[2] - piece.centre[2]) * scale,
		-(companion.centre[3] - piece.centre[3]) * scale,
	}
	return size, offset
end

return table.freeze(ThemeMeshes)
