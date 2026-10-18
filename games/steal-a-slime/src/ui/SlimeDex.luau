--!strict
--[[
	SlimeDex

	The SlimeDex panel's content (Panels/Dex), pure (tests/ui/SlimeDex.spec). State.dex (CONTRACT.md §36.4)
	becomes one card per species, grouped by rarity under a header line, the event Secrets last as a bonus
	section. A card is found (full colour mesh, name) or a silhouette ("???", the hint, and for
	hybrids three ingredient slots that fill in as the player finds each ingredient). The server decides what is
	revealed; this module only formats it. `lines` packs the cards into grid lines for a list width
	(`grid`: as many columns as fit, one on a narrow phone), so the panel stacks lines like any scroll list.
]]

export type Slot = { species: string?, label: string, color: { number } }

export type Card = {
	key: string, -- species id
	kind: string, -- "spawn" | "hybrid" | "boss" | "event"
	tier: number,
	found: boolean,
	title: string, -- name, or "???"
	hint: string?,
	badge: string?, -- "Merge-only" | "Boss" | "Event"
	slots: { Slot }?, -- hybrids: the three ingredients
	color: { number }, -- rarity frame colour
	speciesColor: { number }, -- the species' own colour (preview fallback)
}

export type Line = {
	key: string,
	kind: string, -- "header" | "cards"
	tier: number,
	title: string?, -- header
	detail: string?, -- header: "3 / 6"
	cards: { Card }?, -- cards line, left to right
}

export type Grid = { columns: number, cardW: number, cardH: number, gap: number }

-- Species name and colour for ingredient slots and previews (Panels/Dex builds it from SlimeRoster / SlimeLooks).
export type Lookup = (id: string) -> (string?, { number }?)

local SlimeDex = {}

SlimeDex.SILHOUETTE = table.freeze({ 24, 26, 36 })
SlimeDex.UNKNOWN = "???"
SlimeDex.BONUS_TIER = 0 -- section key of the event Secrets

SlimeDex.BADGES = table.freeze({ hybrid = "Merge-only", boss = "Boss", event = "Event" })

-- Card grid (design px): cards at least CARD_MIN_W wide, at most MAX_COLUMNS per line.
SlimeDex.CARD = table.freeze({
	minW = 150,
	h = 188,
	gap = 8,
	maxColumns = 6,
	preview = 76, -- square mesh preview at the top
	header = 26, -- rarity header line
})

local function str(value: any): string?
	return if type(value) == "string" and value ~= "" then value else nil
end

-- One card per State.dex entry, in State order. Junk entries are skipped.
function SlimeDex.cards(dex: any, config: any, lookup: Lookup?): { Card }
	local out: { Card } = {}
	local entries = if type(dex) == "table" and type(dex.entries) == "table" then dex.entries else {}
	for _, e in entries :: { any } do
		local id = if type(e) == "table" then str(e.id) else nil
		local tier = if type(e) == "table" then tonumber(e.tier) else nil
		local rarity = if tier then config.RARITIES[tier] else nil
		if id and tier and rarity then
			local kind = str(e.kind) or "spawn"
			local found = e.found == true
			local ownColor: { number }? = nil
			if lookup then
				local _, color = lookup(id)
				ownColor = color
			end
			local slots: { Slot }? = nil
			if kind == "hybrid" and type(e.ingredients) == "table" then
				local list: { Slot } = {}
				for i = 1, 3 do
					local species = str(e.ingredients[i])
					local name, color = nil, nil
					if species and lookup then
						name, color = lookup(species)
					end
					list[i] = {
						species = species,
						label = if species then name or species else "?",
						color = if species then color or rarity.color else SlimeDex.SILHOUETTE,
					}
				end
				slots = list
			end
			table.insert(out, {
				key = id,
				kind = kind,
				tier = tier,
				found = found,
				title = str(e.name) or SlimeDex.UNKNOWN,
				hint = str(e.hint),
				badge = (SlimeDex.BADGES :: any)[kind],
				slots = slots,
				color = rarity.color,
				speciesColor = ownColor or rarity.color,
			})
		end
	end
	return out
end

-- Columns, card width and height for a list `width` design px wide.
function SlimeDex.grid(width: number): Grid
	local c = SlimeDex.CARD
	local columns = math.clamp(math.floor((width + c.gap) / (c.minW + c.gap)), 1, c.maxColumns)
	local cardW = math.max(1, math.floor((width - c.gap * (columns - 1)) / columns))
	return { columns = columns, cardW = cardW, cardH = c.h, gap = c.gap }
end

-- Header + card lines: one rarity at a time (found count over the rarity's cards), the bonus section
-- (event Secrets) last. `columns` cards per line.
function SlimeDex.lines(cards: { Card }, columns: number, config: any): { Line }
	local byTier: { [number]: { Card } } = {}
	local bonus: { Card } = {}
	for _, card in cards do
		if card.kind == "event" then
			table.insert(bonus, card)
		else
			byTier[card.tier] = byTier[card.tier] or {}
			table.insert(byTier[card.tier], card)
		end
	end
	local out: { Line } = {}
	local function section(tier: number, title: string, list: { Card })
		local found = 0
		for _, card in list do
			if card.found then
				found += 1
			end
		end
		table.insert(
			out,
			{ key = `header:{tier}`, kind = "header", tier = tier, title = title, detail = `{found} / {#list}` }
		)
		for start = 1, #list, columns do
			table.insert(out, {
				key = `cards:{tier}:{(start - 1) // columns + 1}`,
				kind = "cards",
				tier = tier,
				cards = table.move(list, start, math.min(start + columns - 1, #list), 1, {}),
			})
		end
	end
	for tier, rarity in config.RARITIES do
		local list = byTier[tier]
		if list and #list > 0 then
			section(tier, rarity.name, list)
		end
	end
	if #bonus > 0 then
		section(SlimeDex.BONUS_TIER, "Bonus: Event Secrets", bonus)
	end
	return out
end

-- A display genome for a card (Genome.Slime shape, for Visuals.ModelFactory.build): the species on a size-1
-- body in its colour. The panel paints it flat black for an unfound card.
function SlimeDex.genome(card: Card): { [string]: any }
	return {
		id = `Dex_{card.key}`,
		name = "",
		tier = card.tier,
		species = card.key,
		color = { card.speciesColor[1], card.speciesColor[2], card.speciesColor[3] },
		size = 1,
		pattern = "Plain",
		eyes = "Round",
		mouth = "Smile",
	}
end

export type Summary = {
	percent: string,
	fraction: number,
	count: string, -- "Species 12 / 50"
	secrets: string, -- "Secrets 1 / 7", empty without event Secrets
}

function SlimeDex.summary(dex: any): Summary
	local d = if type(dex) == "table" then dex else {}
	local function n(v: any): number
		return if type(v) == "number" then v else 0
	end
	local found, total = n(d.found), n(d.total)
	local fraction = if total > 0 then math.clamp(found / total, 0, 1) else 0
	local secrets = if n(d.bonusTotal) > 0 then `Secrets {n(d.bonusFound)} / {n(d.bonusTotal)}` else ""
	return {
		percent = `{math.floor(fraction * 100)}%`,
		fraction = fraction,
		count = `Species {found} / {total}`,
		secrets = secrets,
	}
end

-- Panel header above the list (Panels/Dex, design px): percent + count + secrets (40), the bar (to 64),
-- then the rewards line (36) when there is one.
SlimeDex.HEADER = table.freeze({ count = 40, bar = 64, rewards = 36, gap = 4 })
-- The list keeps at least one rarity header and part of a card visible + scroll padding.
SlimeDex.MIN_LIST = 72 + 12

export type Header = { bar: boolean, rewards: boolean, rewardsY: number, listTop: number }

-- What fits above the list in a `bodyH` tall panel body: the rewards line goes first, then the bar, until the
-- list is MIN_LIST tall (short landscape phones). The list height is never negative.
function SlimeDex.header(bodyH: number, hasRewards: boolean): Header
	local h = SlimeDex.HEADER
	local options = {
		{ bar = true, rewards = hasRewards },
		{ bar = true, rewards = false },
		{ bar = false, rewards = false },
	}
	local out: Header
	for _, o in options do
		local top = if o.bar then h.bar else h.count
		out = {
			bar = o.bar,
			rewards = o.rewards,
			rewardsY = top,
			listTop = top + h.gap + (if o.rewards then h.rewards else 0),
		}
		if bodyH - out.listTop >= SlimeDex.MIN_LIST then
			break
		end
	end
	return out
end

-- Plot skin cards (FEATURES.PlotSkins, CONTRACT.md §15) shown above the species: one per State.plotSkins entry,
-- locked / unlocked with the SlimeDex set progress. Empty without the field.
export type SkinRow = {
	key: string,
	tier: number,
	locked: boolean,
	title: string,
	detail: string,
	color: { number },
	skin: { id: string, unlocked: boolean, equipped: boolean },
}

function SlimeDex.skinRows(plotSkins: any, config: any): { SkinRow }
	local out: { SkinRow } = {}
	if type(plotSkins) ~= "table" then
		return out
	end
	local floors: { [string]: { number } } = {}
	for _, def in config.PLOT_SKINS or {} do
		floors[def.id] = if def.floor then def.floor.color else { 214, 176, 124 } -- classic: ranch_plaza
	end
	for _, skin in plotSkins :: { any } do
		if type(skin) == "table" and type(skin.id) == "string" then
			local set = if skin.setName then `{skin.setName} set` else "Default look"
			local unlocked, equipped = skin.unlocked == true, skin.equipped == true
			local detail = if equipped
				then `Equipped · {set}`
				elseif unlocked then `Unlocked · {set}`
				else `{set}: {skin.owned}/{skin.needed} species to unlock`
			table.insert(out, {
				key = `skin:{skin.id}`,
				tier = skin.tier or 0,
				locked = not unlocked,
				title = `Plot skin · {skin.name}`,
				detail = detail,
				color = floors[skin.id] or SlimeDex.SILHOUETTE,
				skin = { id = skin.id, unlocked = unlocked, equipped = equipped },
			})
		end
	end
	return out
end

return table.freeze(SlimeDex)
