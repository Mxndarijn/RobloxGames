--!strict
--[[
	SlimeDex

	The SlimeDex panel's content (Panels/Dex), pure (tests/ui/SlimeDex.spec). State.dex (CONTRACT.md §36.4)
	becomes one card per species, grouped by rarity under a header line, the event Secrets last as a bonus
	section. A card is found (full colour mesh, name) or a silhouette (its name, the hint, and for
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
	title: string, -- the species name ("???" only if State left it out)
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
	detail: string?, -- header: "3/6 found"
	cards: { Card }?, -- cards line, left to right
}

export type Grid = { columns: number, cardW: number, cardH: number, gap: number }

-- Species name and colour for ingredient slots and previews (Panels/Dex builds it from SlimeRoster / SlimeLooks).
export type Lookup = (id: string) -> (string?, { number }?)

local Format = if script then require(script.Parent.Format) else require("./Format")

local SlimeDex = {}

SlimeDex.SILHOUETTE = table.freeze({ 24, 26, 36 })
SlimeDex.UNKNOWN = "???"
SlimeDex.BONUS_TIER = 0 -- section key of the event Secrets

SlimeDex.BADGES = table.freeze({ hybrid = "Merge-only", boss = "Boss", event = "Event" })

-- Card grid (design px): cards at least CARD_MIN_W wide, at most MAX_COLUMNS per line.
SlimeDex.CARD = table.freeze({
	minW = 150,
	h = 172,
	gap = 8,
	maxColumns = 6,
	preview = 80, -- square mesh preview at the top
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
			{ key = `header:{tier}`, kind = "header", tier = tier, title = title, detail = `{found}/{#list} found` }
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
	count: string, -- "Species 12/50"
	secrets: string?, -- "Secrets 1/7" (nil without event Secrets)
}

function SlimeDex.summary(dex: any): Summary
	local d = if type(dex) == "table" then dex else {}
	local function n(v: any): number
		return if type(v) == "number" then v else 0
	end
	local found, total = n(d.found), n(d.total)
	local fraction = if total > 0 then math.clamp(found / total, 0, 1) else 0
	return {
		percent = `{math.floor(fraction * 100)}%`,
		fraction = fraction,
		count = `Species {found}/{total}`,
		secrets = if n(d.bonusTotal) > 0 then `Secrets {n(d.bonusFound)}/{n(d.bonusTotal)}` else nil,
	}
end

-- Panel header above the list (Panels/Dex, design px): the big percent on the left and the count chips beside
-- it, wrapping onto more rows on a narrow body. Compact (short bodies): a smaller percent and one chip row.
SlimeDex.HEADER = table.freeze({
	percent = 60, -- big percent block height
	chip = 26,
	chipGap = 6,
	gap = 8, -- header to list
})
-- Advance width (em) of the percent's characters in Theme.Font (FredokaOne), from Studio TextService at 26 and
-- 56 px, rounded up so small sizes still fit.
local PERCENT_EM = table.freeze({ ["1"] = 0.35, ["%"] = 0.73 })
local DIGIT_EM = 0.53

-- Width (px) of percent text like "42%" at `size`, so the chips can start right after it.
function SlimeDex.percentWidth(text: string, size: number): number
	local em = 0
	for i = 1, #text do
		em += PERCENT_EM[string.sub(text, i, i)] or DIGIT_EM
	end
	return math.ceil(em * size)
end

-- The list keeps at least one rarity header and part of a card visible + scroll padding.
SlimeDex.MIN_LIST = 72 + 12

export type Header = { compact: boolean, height: number, listTop: number }

-- What fits above the list in a `bodyH` tall panel body with the chips on `chipRows` rows (a boolean means
-- one row / two rows): the full header, else the compact one (one chip row) once the list would drop under
-- MIN_LIST (short landscape phones). The list height is never negative.
function SlimeDex.header(bodyH: number, chipRows: (number | boolean)?): Header
	local h = SlimeDex.HEADER
	local rows = if type(chipRows) == "number" then math.max(1, chipRows) elseif chipRows == true then 2 else 1
	local full = math.max(h.percent, rows * h.chip + (rows - 1) * h.chipGap)
	if bodyH - (full + h.gap) >= SlimeDex.MIN_LIST then
		return { compact = false, height = full, listTop = full + h.gap }
	end
	return { compact = true, height = h.chip, listTop = h.chip + h.gap }
end

export type ChipSpot = { x: number, y: number, visible: boolean }

-- Places chips `widths` (design px) left to right from `x0` in a `width` wide header, wrapping to a new row
-- when one does not fit; past `maxRows` rows a chip is hidden. Returns the spots and the rows used.
function SlimeDex.chipRows(widths: { number }, x0: number, width: number, maxRows: number): ({ ChipSpot }, number)
	local h = SlimeDex.HEADER
	local spots: { ChipSpot } = {}
	local x, row = x0, 1
	for i, w in widths do
		if x > x0 and x + w > width then
			x, row = x0, row + 1
		end
		spots[i] = { x = x, y = (row - 1) * (h.chip + h.chipGap), visible = row <= maxRows }
		x += w + h.chipGap
	end
	return spots, math.min(row, maxRows)
end

export type RewardTick = { count: number, at: number, claimed: boolean, isNext: boolean }
export type RewardCard = {
	title: string, -- "Next reward at 8 species"
	reward: string?, -- "+$5K and +2% income"
	fraction: number, -- species found over the last species milestone
	ticks: { RewardTick }, -- every species milestone, `at` placed to scale (0..1)
}

local function pct(fraction: number): string
	return `{math.floor(fraction * 100 + 0.5)}%`
end

-- The SlimeDex reward card from State.dexRewards and State.dex.found: the next unclaimed species milestone
-- and one bar from 0 to the last one with every milestone marked. nil on a server without species milestones.
function SlimeDex.rewardCard(state: any): RewardCard?
	local rewards = if type(state) == "table" then state.dexRewards else nil
	if type(rewards) ~= "table" then
		return nil
	end
	local function n(v: any): number
		return if type(v) == "number" and v == v then v else 0
	end
	local found = if type(state.dex) == "table" then n(state.dex.found) else 0
	local species: { any } = {}
	local nextSpecies = nil
	local last = 0
	for _, r in rewards do
		if type(r) == "table" then
			table.insert(species, r)
			last = math.max(last, n(r.count))
			if r.claimed ~= true and nextSpecies == nil then
				nextSpecies = r
			end
		end
	end
	if #species == 0 or last <= 0 then
		return nil
	end
	local ticks: { RewardTick } = {}
	for _, r in species do
		table.insert(ticks, {
			count = n(r.count),
			at = math.clamp(n(r.count) / last, 0, 1),
			claimed = r.claimed == true,
			isNext = r == nextSpecies,
		})
	end
	return {
		title = if nextSpecies
			then `Next reward at {n(nextSpecies.count)} species`
			else "Every species reward collected",
		reward = if nextSpecies
			then `+{Format.formatCash(n(nextSpecies.reward))} and +{pct(n(nextSpecies.bonus))} income`
			else nil,
		fraction = if nextSpecies then math.clamp(found / last, 0, 1) else 1,
		ticks = ticks,
	}
end

-- Plot skin cards (FEATURES.PlotSkins, CONTRACT.md §15) shown above the species: one per State.plotSkins entry,
-- locked / unlocked with the progress on the skin's slimes. Empty without the field.
export type SkinRow = {
	key: string,
	tier: number,
	locked: boolean,
	title: string, -- the skin's name
	detail: string, -- the slimes' group, or for a locked skin what unlocks it
	found: string?, -- a locked skin's count toward it ("3/5 found")
	fraction: number, -- set progress (1 once unlocked)
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
		floors[def.id] = def.color or (if def.floor then def.floor.color else { 214, 176, 124 }) -- else ranch_plaza
	end
	for _, skin in plotSkins :: { any } do
		if type(skin) == "table" and type(skin.id) == "string" then
			local unlocked, equipped = skin.unlocked == true, skin.equipped == true
			local owned = if type(skin.owned) == "number" then skin.owned else 0
			local needed = if type(skin.needed) == "number" then skin.needed else 0
			local detail = if unlocked
				then (if skin.setName then `{skin.setName} set` else "Default look")
				else `Find {needed} {if skin.setName then `{skin.setName} ` else ""}species`
			table.insert(out, {
				key = `skin:{skin.id}`,
				tier = skin.tier or 0,
				locked = not unlocked,
				title = Format.sentenceCase(if type(skin.name) == "string" then skin.name else skin.id),
				detail = detail,
				found = if unlocked then nil else `{math.min(owned, needed)}/{needed} found`,
				fraction = if unlocked then 1 elseif needed > 0 then math.clamp(owned / needed, 0, 1) else 0,
				color = floors[skin.id] or SlimeDex.SILHOUETTE,
				skin = { id = skin.id, unlocked = unlocked, equipped = equipped },
			})
		end
	end
	return out
end

return table.freeze(SlimeDex)
