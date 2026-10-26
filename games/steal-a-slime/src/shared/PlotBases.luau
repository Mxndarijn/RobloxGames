--!strict
--[[
	PlotBases

	Plot bases: the building a plot stands in (Config.PLOT_BASES, FEATURES.BaseShapes, CONTRACT.md §43), chosen
	apart from the plot skin (the colours, PlotSkins). The goo jar tower is everyone's; the other bases unlock at a
	rebirth count (`rebirths`). The equipped base is data.plotBase; `equip` refuses a locked base and `current` never
	returns one, so a base saved before its rebirths shows the jar until the player gets there.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Data = PlayerData.Data

export type View = {
	id: string,
	name: string,
	rebirths: number, -- rebirths that unlock it (0 = everyone)
	unlocked: boolean,
	equipped: boolean,
}

local PlotBases = {}

PlotBases.DEFAULT = Config.PLOT_BASE_DEFAULT

function PlotBases.get(id: any): Config.PlotBase?
	if type(id) ~= "string" then
		return nil
	end
	for _, base in Config.PLOT_BASES do
		if base.id == id then
			return base
		end
	end
	return nil
end

function PlotBases.unlocked(data: Data, base: Config.PlotBase): boolean
	return (data.rebirths or 0) >= (base.rebirths or 0)
end

-- The base to build: the equipped one if it still exists and is unlocked, else the jar.
function PlotBases.current(data: Data): string
	local base = PlotBases.get(data.plotBase)
	if base and PlotBases.unlocked(data, base) then
		return base.id
	end
	return PlotBases.DEFAULT
end

function PlotBases.equip(data: Data, id: any): (boolean, string?)
	local base = PlotBases.get(id)
	if not base then
		return false, "unknown plot base"
	end
	if not PlotBases.unlocked(data, base) then
		return false, "plot base is locked"
	end
	data.plotBase = base.id
	return true, nil
end

-- State.plotBases: the jar first, then Config order.
function PlotBases.view(data: Data): { View }
	local equipped = PlotBases.current(data)
	local out: { View } = {}
	for _, base in Config.PLOT_BASES do
		table.insert(out, {
			id = base.id,
			name = base.name,
			rebirths = base.rebirths or 0,
			unlocked = PlotBases.unlocked(data, base),
			equipped = base.id == equipped,
		})
	end
	return out
end

-- A saved plotBase: a known id is kept (locked or not: current() decides what shows), anything else -> the jar.
function PlotBases.clean(raw: any): string
	return if PlotBases.get(raw) then raw else PlotBases.DEFAULT
end

return table.freeze(PlotBases)
