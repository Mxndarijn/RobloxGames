--!strict
--[[
	SlimeDex

	The SlimeDex panel's content (Panels/Dex), pure (tests/ui/SlimeDex.spec). State.dex (contract/species-dex.md
	§36.4) becomes one card per species, split over four tabs by kind: Fountain (spawn), Merges (hybrid), Bosses
	and Secrets (event). The species tabs are a card grid grouped by rarity (`lines`) beside a side pane for the
	selected card (`detail`). The Merges tab is one recipe row per hybrid (`recipes`): three ingredient slots
	marked "In base", "Found" or unknown, the result, and whether it is made, ready or how many slimes are missing.
	The server decides what is revealed; this module only formats it.
]]

export type Slot = {
	species: string?, -- nil while the ingredient is not found
	label: string, -- its name, or "???"
	set: string?, -- the set its species belongs to ("Meadow", "Garden", ...)
	color: { number },
}

export type Card = {
	key: string, -- species id
	kind: string, -- "spawn" | "hybrid" | "boss" | "event"
	tier: number,
	found: boolean,
	title: string, -- the species name ("???" only if State left it out)
	hint: string?,
	slots: { Slot }?, -- hybrids: the three ingredients
	set: string?, -- spawn species: its set
	color: { number }, -- rarity colour
	speciesColor: { number }, -- the species' own colour (preview fallback)
}

export type Line = {
	key: string,
	kind: string, -- "header" | "cards"
	tier: number,
	title: string?, -- header
	detail: string?, -- header: "3/6"
	cards: { Card }?, -- cards line, left to right
}

export type Grid = { columns: number, cardW: number, cardH: number, gap: number }

-- Species name, colour and set for ingredient slots, previews and the side pane (Panels/Dex builds it from
-- SlimeRoster, SlimeLooks and SpeciesDex.setName).
export type Lookup = (id: string) -> (string?, { number }?, string?)

local Format = if script then require(script.Parent.Format) else require("./Format")
local Layout = if script then require(script.Parent.Layout) else require("./Layout")

local SlimeDex = {}

SlimeDex.SILHOUETTE = table.freeze({ 24, 26, 36 })
SlimeDex.UNKNOWN = "???"
SlimeDex.BONUS_TIER = 0 -- section key of the event Secrets

-- The tabs, left to right: the State.dex entry kind each one shows.
export type TabDef = { key: string, label: string }
SlimeDex.TABS = table.freeze({
	table.freeze({ key = "spawn", label = "Fountain" }),
	table.freeze({ key = "hybrid", label = "Merges" }),
	table.freeze({ key = "boss", label = "Bosses" }),
	table.freeze({ key = "event", label = "Secrets" }),
} :: { TabDef })
SlimeDex.MERGES = "hybrid"

-- Card grid (design px): cards at least minW wide, at most maxColumns per line.
SlimeDex.CARD = table.freeze({
	minW = 92,
	h = 112,
	gap = 8,
	maxColumns = 5,
	preview = 64, -- square mesh preview at the top
	header = 24, -- rarity header line
})

-- The panel body's blocks above the tab content (design px): the tabs, then the reward line when the server
-- has species milestones.
SlimeDex.BODY = table.freeze({
	tabH = Layout.MIN_TOUCH_DESIGN,
	gap = 8,
	rewardH = 42,
})

-- Where the tab content starts in the body.
function SlimeDex.contentTop(hasReward: boolean): number
	local b = SlimeDex.BODY
	return b.tabH + b.gap + (if hasReward then b.rewardH + b.gap else 0)
end

-- The content keeps at least one rarity heading and one line of cards on every screen.
SlimeDex.MIN_CONTENT = SlimeDex.CARD.header + SlimeDex.CARD.h

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
			local ownColor: { number }?, ownSet: string? = nil, nil
			if lookup then
				local _, color, set = lookup(id)
				ownColor, ownSet = color, set
			end
			local slots: { Slot }? = nil
			if kind == "hybrid" and type(e.ingredients) == "table" then
				local sets = if type(e.ingredientSets) == "table" then e.ingredientSets else {}
				local list: { Slot } = {}
				for i = 1, 3 do
					local species = str(e.ingredients[i])
					local name, color = nil, nil
					if species and lookup then
						name, color = lookup(species)
					end
					list[i] = {
						species = species,
						label = if species then name or species else SlimeDex.UNKNOWN,
						set = str(sets[i]),
						color = if species then color or rarity.color else SlimeDex.SILHOUETTE,
					}
				end
				slots = list
			end
			table.insert(out, {
				key = id,
				kind = kind,
				tier = tier,
				found = e.found == true,
				title = str(e.name) or SlimeDex.UNKNOWN,
				hint = str(e.hint),
				slots = slots,
				set = if kind == "spawn" then ownSet else nil,
				color = rarity.color,
				speciesColor = ownColor or rarity.color,
			})
		end
	end
	return out
end

export type Tab = { key: string, label: string, found: number, total: number, count: string }

-- The tabs that have cards, in TABS order, with their found counts ("3/15").
function SlimeDex.tabs(cards: { Card }): { Tab }
	local found: { [string]: number } = {}
	local total: { [string]: number } = {}
	for _, card in cards do
		total[card.kind] = (total[card.kind] or 0) + 1
		if card.found then
			found[card.kind] = (found[card.kind] or 0) + 1
		end
	end
	local out: { Tab } = {}
	for _, def in SlimeDex.TABS do
		local n = total[def.key] or 0
		if n > 0 then
			local f = found[def.key] or 0
			table.insert(out, { key = def.key, label = def.label, found = f, total = n, count = `{f}/{n}` })
		end
	end
	return out
end

-- The cards of one tab, State order.
function SlimeDex.ofKind(cards: { Card }, kind: string): { Card }
	local out: { Card } = {}
	for _, card in cards do
		if card.kind == kind then
			table.insert(out, card)
		end
	end
	return out
end

-- Columns, card width and height for a grid `width` design px wide.
function SlimeDex.grid(width: number): Grid
	local c = SlimeDex.CARD
	local columns = math.clamp(math.floor((width + c.gap) / (c.minW + c.gap)), 1, c.maxColumns)
	local cardW = math.max(1, math.floor((width - c.gap * (columns - 1)) / columns))
	return { columns = columns, cardW = cardW, cardH = c.h, gap = c.gap }
end

-- Header + card lines for one tab's cards: one rarity at a time (found count over the rarity's cards); event
-- Secrets are one section. `columns` cards per line.
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
			{ key = `header:{tier}`, kind = "header", tier = tier, title = title, detail = `{found}/{#list}` }
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
		section(SlimeDex.BONUS_TIER, "Event Secrets", bonus)
	end
	return out
end

-- How many slimes of each species the player has in their base now (State.slimes; one being stolen does not
-- count).
function SlimeDex.inBase(slimes: any): { [string]: number }
	local out: { [string]: number } = {}
	if type(slimes) ~= "table" then
		return out
	end
	for _, view in slimes do
		local slime = if type(view) == "table" then view.slime else nil
		if type(slime) == "table" and view.stolenBy == nil and type(slime.species) == "string" then
			out[slime.species] = (out[slime.species] or 0) + 1
		end
	end
	return out
end

-- The side pane for a selected card.
export type UsedIn = { key: string, title: string }
export type Detail = {
	key: string,
	title: string,
	found: boolean,
	rarity: string,
	rarityColor: { number },
	how: string, -- how to get it
	set: string?, -- "Garden set" (spawn species)
	have: string, -- "2 in your base" / "None in your base"
	usedIn: { UsedIn }, -- merges that take it (only known once it is found)
}

SlimeDex.HOW = table.freeze({
	spawn = "Catch it at the fountain",
	hybrid = "Merge it in the Merge vat",
	boss = "Defeat the boss event",
	event = "An event Secret",
})

function SlimeDex.detail(card: Card, cards: { Card }, inBase: { [string]: number }, config: any): Detail
	local rarity = config.RARITIES[card.tier]
	local usedIn: { UsedIn } = {}
	for _, other in cards do
		for _, slot in other.slots or {} do
			if slot.species == card.key then
				table.insert(usedIn, { key = other.key, title = other.title })
				break
			end
		end
	end
	local n = inBase[card.key] or 0
	return {
		key = card.key,
		title = card.title,
		found = card.found,
		rarity = if rarity then rarity.name else "",
		rarityColor = card.color,
		how = if card.kind == "spawn" or card.kind == "hybrid"
			then (SlimeDex.HOW :: any)[card.kind]
			else card.hint or (SlimeDex.HOW :: any)[card.kind] or "",
		set = if card.set then `{card.set} set` else nil,
		have = if n > 0 then `{n} in your base` else "None in your base",
		usedIn = usedIn,
	}
end

-- Merge recipe rows (the Merges tab).
export type RecipeSlot = {
	species: string?,
	label: string,
	state: "base" | "found" | "unknown",
	tag: string, -- "In base" / "Found" / the set of an unknown one
	color: { number },
}
export type Recipe = {
	key: string, -- "recipe:<hybrid id>"
	result: Card,
	slots: { RecipeSlot },
	status: "made" | "ready" | "need",
	statusText: string, -- "Made" / "Ready to merge" / "Need 2 more"
	missing: number, -- slots not in base
}

SlimeDex.SLOT_TAGS = table.freeze({ base = "In base", found = "Found" })

-- One row per hybrid card with a recipe: ready ones first, then the fewest missing, made ones last (State order
-- within each). `only` keeps the recipes that take that species.
function SlimeDex.recipes(cards: { Card }, inBase: { [string]: number }, only: string?): { Recipe }
	local out: { Recipe } = {}
	local order: { [string]: number } = {}
	for _, card in cards do
		local cardSlots = card.slots
		if card.kind == "hybrid" and cardSlots then
			local wanted = only == nil
			local used: { [string]: number } = {}
			local slots: { RecipeSlot } = {}
			local missing = 0
			for i, slot in cardSlots do
				local species = slot.species
				local state: "base" | "found" | "unknown" = "unknown"
				if species then
					wanted = wanted or species == only
					if (inBase[species] or 0) > (used[species] or 0) then
						used[species] = (used[species] or 0) + 1
						state = "base"
					else
						state = "found"
					end
				end
				if state ~= "base" then
					missing += 1
				end
				slots[i] = {
					species = species,
					label = slot.label,
					state = state,
					tag = if state == "unknown"
						then slot.set or SlimeDex.UNKNOWN
						else (SlimeDex.SLOT_TAGS :: any)[state],
					color = slot.color,
				}
			end
			if wanted then
				local status: "made" | "ready" | "need" = if card.found
					then "made"
					elseif missing == 0 then "ready"
					else "need"
				table.insert(out, {
					key = `recipe:{card.key}`,
					result = card,
					slots = slots,
					status = status,
					statusText = if status == "made"
						then "Made"
						elseif status == "ready" then "Ready to merge"
						else `Need {missing} more`,
					missing = missing,
				})
				order[card.key] = #out
			end
		end
	end
	local rank = { ready = 0, need = 1, made = 2 }
	table.sort(out, function(a, b)
		if a.status ~= b.status then
			return rank[a.status] < rank[b.status]
		end
		if a.status == "need" and a.missing ~= b.missing then
			return a.missing < b.missing
		end
		return order[a.result.key] < order[b.result.key]
	end)
	return out
end

-- A display genome for a card (Genome.Slime shape, for Visuals.ModelFactory.build): the species on a size-1
-- body in its colour. The panel paints it flat black for an unfound card.
function SlimeDex.genome(card: { key: string, tier: number, speciesColor: { number } }): { [string]: any }
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
	percent: string, -- "28%"
	fraction: number,
	count: string, -- "14/53 found"
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
		count = `{found}/{total} found`,
	}
end

export type RewardLine = {
	text: string, -- "Next reward at 16: +$19K and +2% income"
	count: string?, -- "14/16"
	fraction: number, -- species found toward the next milestone (1 once every reward is collected)
}

local function pct(fraction: number): string
	return `{math.floor(fraction * 100 + 0.5)}%`
end

-- The SlimeDex reward line from State.dexRewards and State.dex.found: the next unclaimed species milestone, what
-- it pays and the progress toward it. nil on a server without species milestones.
function SlimeDex.rewardLine(state: any): RewardLine?
	local rewards = if type(state) == "table" then state.dexRewards else nil
	if type(rewards) ~= "table" then
		return nil
	end
	local function n(v: any): number
		return if type(v) == "number" and v == v then v else 0
	end
	local found = if type(state.dex) == "table" then n(state.dex.found) else 0
	local any = false
	for _, r in rewards do
		if type(r) == "table" then
			any = true
			if r.claimed ~= true and n(r.count) > 0 then
				local count = n(r.count)
				return {
					text = `Next reward at {count}: +{Format.formatCash(n(r.reward))} and +{pct(n(r.bonus))} income`,
					count = `{math.min(found, count)}/{count}`,
					fraction = math.clamp(found / count, 0, 1),
				}
			end
		end
	end
	if not any then
		return nil
	end
	return { text = "Every species reward collected", count = nil, fraction = 1 }
end

return table.freeze(SlimeDex)
