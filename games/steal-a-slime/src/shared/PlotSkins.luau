--!strict
--[[
	PlotSkins

	Plot skins: goo jar tower themes unlocked by collecting slimes (Config.PLOT_SKINS, FEATURES.PlotSkins,
	CONTRACT.md §15). A skin's slimes are a whole family (every SlimeRoster spawn species of it) or its own species
	list; it unlocks once the owner has found (SlimeDex, data.found) `threshold` (75 %) of them, rounded up. A skin
	with no slimes (classic) is always unlocked. The equipped skin is data.plotSkin; `equip` refuses anything that
	is not unlocked, `current` never returns a skin the player has not earned.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local FountainTiers = if script then require(script.Parent.FountainTiers) else require("./FountainTiers")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")

type Data = PlayerData.Data

export type View = {
	id: string,
	name: string,
	setName: string?, -- the group the slimes come from: the family's name, or the skin's own; nil for classic
	tier: number?, -- always nil: skins are no longer tied to a rarity tier
	owned: number, -- the skin's slimes found
	total: number, -- the skin's slimes
	needed: number, -- slimes that unlock the skin
	fraction: number, -- owned / total, 0..1
	unlocked: boolean,
	equipped: boolean,
}

local PlotSkins = {}

PlotSkins.DEFAULT = Config.PLOT_SKIN_DEFAULT

-- Each skin's species ids, in roster order (a family) or Config order (a list), built once.
local SLIMES: { [string]: { string } } = {}
for _, skin in Config.PLOT_SKINS do
	local out: { string } = if skin.species then table.clone(skin.species) else {}
	if skin.family and not skin.species then
		for _, entry in SlimeRoster.ROSTER do
			if entry.kind == "spawn" and entry.family == skin.family then
				table.insert(out, entry.id)
			end
		end
	end
	SLIMES[skin.id] = table.freeze(out)
end

-- The species ids that count toward `skin` (frozen). Empty = none: always unlocked.
function PlotSkins.slimes(skin: Config.PlotSkin): { string }
	return SLIMES[skin.id] or {}
end

function PlotSkins.get(id: any): Config.PlotSkin?
	if type(id) ~= "string" then
		return nil
	end
	for _, skin in Config.PLOT_SKINS do
		if skin.id == id then
			return skin
		end
	end
	return nil
end

-- The skin's slimes the player has found.
function PlotSkins.owned(data: Data, skin: Config.PlotSkin): number
	local count = 0
	for _, id in PlotSkins.slimes(skin) do
		if data.found[id] then
			count += 1
		end
	end
	return count
end

function PlotSkins.needed(skin: Config.PlotSkin): number
	return math.ceil(#PlotSkins.slimes(skin) * (skin.threshold or 1) - 1e-9)
end

function PlotSkins.unlocked(data: Data, skin: Config.PlotSkin): boolean
	return PlotSkins.owned(data, skin) >= PlotSkins.needed(skin)
end

-- The skin to show: the equipped one if it still exists and is unlocked, else classic.
function PlotSkins.current(data: Data): string
	local skin = PlotSkins.get(data.plotSkin)
	if skin and PlotSkins.unlocked(data, skin) then
		return skin.id
	end
	return PlotSkins.DEFAULT
end

function PlotSkins.equip(data: Data, id: any): (boolean, string?)
	local skin = PlotSkins.get(id)
	if not skin then
		return false, "unknown plot skin"
	end
	if not PlotSkins.unlocked(data, skin) then
		return false, "plot skin is locked"
	end
	data.plotSkin = skin.id
	return true, nil
end

-- The name of the group a skin's slimes come from (the family's, or the skin's own for a list).
local function groupName(skin: Config.PlotSkin): string?
	if skin.family then
		for _, family in FountainTiers.FAMILIES do
			if family.id == skin.family then
				return family.name
			end
		end
	end
	return if skin.species then skin.name else nil
end

-- State.plotSkins: classic first, then Config order.
function PlotSkins.view(data: Data): { View }
	local equipped = PlotSkins.current(data)
	local out: { View } = {}
	for _, skin in Config.PLOT_SKINS do
		local total = #PlotSkins.slimes(skin)
		local owned = PlotSkins.owned(data, skin)
		table.insert(out, {
			id = skin.id,
			name = skin.name,
			setName = groupName(skin),
			tier = nil,
			owned = owned,
			total = total,
			needed = PlotSkins.needed(skin),
			fraction = if total > 0 then owned / total else 1,
			unlocked = PlotSkins.unlocked(data, skin),
			equipped = skin.id == equipped,
		})
	end
	return out
end

return table.freeze(PlotSkins)
