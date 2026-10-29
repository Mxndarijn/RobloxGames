--!strict
--[[
	PlotSkinsView

	The Plot skins menu's content (Panels/Skins), pure (tests/ui/PlotSkins.spec). State.plotSkins
	(contract/plot-skins.md) becomes one row per skin (name, a bar and the count toward unlocking it, or its
	state) and, for the selected skin, a pane listing the slimes that unlock it, each found or not (State.dex
	cards), and what its button does: Equip, Equipped, or how many slimes are still needed.
	The server decides unlocks; this module only formats them.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")
local SlimeDex = if script then require(script.Parent.SlimeDex) else require("./SlimeDex")

local PlotSkinsView = {}

export type State = "equipped" | "unlocked" | "locked"

export type Row = {
	key: string, -- "skin:<id>"
	id: string,
	title: string,
	state: State,
	count: string, -- "3/4" toward unlocking ("" once unlocked)
	fraction: number, -- 0..1 toward unlocking (1 once unlocked)
	color: { number }, -- the skin's colour (icon backdrop)
	exclusive: boolean, -- sold in the Exclusive shop and not owned: no bar, "Only in the Exclusive shop."
}

export type SkinSlime = {
	species: string,
	title: string,
	found: boolean,
	tag: string, -- "Found", "Merge" or the set to catch it in
	tier: number,
	speciesColor: { number },
}

export type Detail = {
	id: string,
	title: string,
	state: State,
	line: string, -- "Find 4 of these 5 slimes" / "Every player has this skin"
	count: string?, -- "3/4"
	fraction: number,
	slimes: { SkinSlime },
	action: string, -- "Equip" / "Equipped" / "Need 1 more slime"
}

PlotSkinsView.EQUIPPED = "Equipped"
PlotSkinsView.EQUIP = "Equip"
PlotSkinsView.FOUND = "Found"
PlotSkinsView.MERGE = "Merge"
PlotSkinsView.EMPTY = "Plot skins are not on this server."
PlotSkinsView.EXCLUSIVE_LINE = "Only in the Exclusive shop."
PlotSkinsView.EXCLUSIVE_ACTION = "Exclusive shop"

local DEFAULT_COLOR = { 110, 226, 170 }

local function num(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

local function stateOf(skin: any): State
	return if skin.equipped == true then "equipped" elseif skin.unlocked == true then "unlocked" else "locked"
end

-- One row per State.plotSkins entry (classic first, as the server sends them). Empty without the field.
function PlotSkinsView.rows(plotSkins: any, config: any): { Row }
	local out: { Row } = {}
	if type(plotSkins) ~= "table" then
		return out
	end
	local colors: { [string]: { number } } = {}
	for _, def in config.PLOT_SKINS or {} do
		colors[def.id] = def.color
	end
	for _, skin in plotSkins :: { any } do
		if type(skin) == "table" and type(skin.id) == "string" then
			local state = stateOf(skin)
			local owned, needed = num(skin.owned), num(skin.needed)
			local exclusive = skin.exclusive == true and state == "locked"
			table.insert(out, {
				key = `skin:{skin.id}`,
				id = skin.id,
				title = Format.sentenceCase(if type(skin.name) == "string" then skin.name else skin.id),
				state = state,
				count = if state == "locked" and not exclusive then `{math.min(owned, needed)}/{needed}` else "",
				fraction = if state ~= "locked" then 1 elseif needed > 0 then math.clamp(owned / needed, 0, 1) else 0,
				color = colors[skin.id] or DEFAULT_COLOR,
				exclusive = exclusive,
			})
		end
	end
	return out
end

-- The pane for skin `id`: its slimes (`slimesOf`: PlotSkins.slimes for that skin) with their Dex cards.
function PlotSkinsView.detail(
	plotSkins: any,
	id: string,
	cards: { SlimeDex.Card },
	slimesOf: (id: string) -> { string }
): Detail?
	if type(plotSkins) ~= "table" then
		return nil
	end
	local skin: any = nil
	for _, s in plotSkins :: { any } do
		if type(s) == "table" and s.id == id then
			skin = s
		end
	end
	if skin == nil then
		return nil
	end
	local byId: { [string]: SlimeDex.Card } = {}
	for _, card in cards do
		byId[card.key] = card
	end
	local slimes: { SkinSlime } = {}
	for _, species in slimesOf(id) do
		local card = byId[species]
		if card then
			table.insert(slimes, {
				species = species,
				title = card.title,
				found = card.found,
				tag = if card.found
					then PlotSkinsView.FOUND
					elseif card.kind == "hybrid" then PlotSkinsView.MERGE
					else card.set or SlimeDex.UNKNOWN,
				tier = card.tier,
				speciesColor = card.speciesColor,
			})
		end
	end
	local state = stateOf(skin)
	local owned, needed, total = num(skin.owned), num(skin.needed), num(skin.total)
	local left = math.max(needed - owned, 0)
	if skin.exclusive == true then
		return {
			id = id,
			title = Format.sentenceCase(if type(skin.name) == "string" then skin.name else id),
			state = state,
			line = PlotSkinsView.EXCLUSIVE_LINE,
			count = nil,
			fraction = if state == "locked" then 0 else 1,
			slimes = {},
			action = if state == "equipped"
				then PlotSkinsView.EQUIPPED
				elseif state == "unlocked" then PlotSkinsView.EQUIP
				else PlotSkinsView.EXCLUSIVE_ACTION,
		}
	end
	return {
		id = id,
		title = Format.sentenceCase(if type(skin.name) == "string" then skin.name else id),
		state = state,
		line = if total > 0 then `Find {needed} of these {total} slimes` else "Every player has this skin",
		count = if total > 0 then `{math.min(owned, needed)}/{needed}` else nil,
		fraction = if needed > 0 then math.clamp(owned / needed, 0, 1) else 1,
		slimes = slimes,
		action = if state == "equipped"
			then PlotSkinsView.EQUIPPED
			elseif state == "unlocked" then PlotSkinsView.EQUIP
			else `Need {left} more slime{if left == 1 then "" else "s"}`,
	}
end

-- The skin to show first: the equipped one, else the first.
function PlotSkinsView.firstSelected(rows: { Row }): string?
	for _, row in rows do
		if row.state == "equipped" then
			return row.id
		end
	end
	return if rows[1] then rows[1].id else nil
end

-- "1/6 unlocked"
function PlotSkinsView.summary(rows: { Row }): string
	local n = 0
	for _, row in rows do
		if row.state ~= "locked" then
			n += 1
		end
	end
	return `{n}/{#rows} unlocked`
end

return table.freeze(PlotSkinsView)
