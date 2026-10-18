--!strict
--[[
	PlotSkins

	Plot skins unlocked by SlimeDex sets (Config.PLOT_SKINS, FEATURES.PlotSkins,
	CONTRACT.md §15, §36.3). A skin's set is one rarity tier of the SlimeDex; it
	unlocks once the owner has found `threshold` (75 %) of that tier's species
	entries (SpeciesDex.tierSize). The equipped skin is data.plotSkin; `equip` refuses anything that is
	not unlocked, `current` never returns a skin the player has not earned.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local SpeciesDex = if script then require(script.Parent.SpeciesDex) else require("./SpeciesDex")

type Data = PlayerData.Data

export type View = {
	id: string,
	name: string,
	setName: string?, -- rarity name of the Dex set, nil for classic
	tier: number?,
	owned: number, -- species of the set found
	total: number, -- species in the set (PlotSkins.setSize)
	needed: number, -- species that unlock the skin
	fraction: number, -- owned / total, 0..1
	unlocked: boolean,
	equipped: boolean,
}

local PlotSkins = {}

PlotSkins.DEFAULT = Config.PLOT_SKIN_DEFAULT

-- Species entries in one tier of the SlimeDex.
function PlotSkins.setSize(tier: number): number
	return SpeciesDex.tierSize(tier)
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

-- Found species of one tier.
function PlotSkins.owned(data: Data, tier: number): number
	return SpeciesDex.tierCount(data, tier)
end

function PlotSkins.needed(skin: Config.PlotSkin): number
	return math.ceil(PlotSkins.setSize(skin.set or 0) * (skin.threshold or 1) - 1e-9)
end

function PlotSkins.unlocked(data: Data, skin: Config.PlotSkin): boolean
	if skin.set == nil then
		return true
	end
	return PlotSkins.owned(data, skin.set) >= PlotSkins.needed(skin)
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

-- State.plotSkins: classic first, then Config order.
function PlotSkins.view(data: Data): { View }
	local equipped = PlotSkins.current(data)
	local out: { View } = {}
	for _, skin in Config.PLOT_SKINS do
		local total = if skin.set then PlotSkins.setSize(skin.set) else 0
		local owned = if skin.set then math.min(PlotSkins.owned(data, skin.set), total) else total
		local rarity = if skin.set then Config.RARITIES[skin.set] else nil
		table.insert(out, {
			id = skin.id,
			name = skin.name,
			setName = if rarity then rarity.name else nil,
			tier = skin.set,
			owned = owned,
			total = total,
			needed = if skin.set then PlotSkins.needed(skin) else 0,
			fraction = if total > 0 then owned / total else 1,
			unlocked = PlotSkins.unlocked(data, skin),
			equipped = skin.id == equipped,
		})
	end
	return out
end

return table.freeze(PlotSkins)
