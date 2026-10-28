--!strict
--[[
	StealCardsLogic: which steal cards the owner sees in the top banner stack. Pure (tests/ui/StealCards.spec).

	* "stealing": one card per player carrying one of my slimes away right now (SlimeView.stolenBy).
	* "stolen": a slime that was being carried and is now gone from my plot was stolen; that card shows for
	  STOLEN_SECONDS. (A slime that escapes comes back with stolenBy cleared, so it is never gone.)

	At most MAX_CARDS cards show; the rest are counted for a "+N more" chip.
]]

local StealCardsLogic = {}

StealCardsLogic.STOLEN_SECONDS = 4
StealCardsLogic.MAX_CARDS = 2

export type Card = {
	kind: "stealing" | "stolen",
	thief: number, -- UserId
	startedAt: number?, -- "stolen" only: when the slime was taken
}

export type Memory = {
	carried: { [string]: number }, -- slime id -> thief UserId, from the last State
	stolen: { Card }, -- recent "stolen" cards, oldest first
}

type SlimeLike = { slime: { id: string }, stolenBy: number? }

function StealCardsLogic.new(): Memory
	return { carried = {}, stolen = {} }
end

-- The next memory after a State with these slimes arrives at `now`.
function StealCardsLogic.observe(memory: Memory, slimes: { SlimeLike }, now: number): Memory
	local present: { [string]: boolean } = {}
	local carried: { [string]: number } = {}
	for _, view in slimes do
		present[view.slime.id] = true
		if view.stolenBy ~= nil then
			carried[view.slime.id] = view.stolenBy
		end
	end
	local stolen: { Card } = {}
	for _, card in memory.stolen do
		if (card.startedAt :: number) + StealCardsLogic.STOLEN_SECONDS > now then
			table.insert(stolen, card)
		end
	end
	local gone: { Card } = {}
	for id, thief in memory.carried do
		if not present[id] then
			table.insert(gone, { kind = "stolen", thief = thief, startedAt = now })
		end
	end
	table.sort(gone, function(a, b)
		return a.thief < b.thief
	end)
	for _, card in gone do
		table.insert(stolen, card)
	end
	return { carried = carried, stolen = stolen }
end

-- The cards to show at `now` (stealing first, then the newest steals) and how many more are hidden.
function StealCardsLogic.cards(memory: Memory, now: number): ({ Card }, number)
	local all: { Card } = {}
	local seen: { [number]: boolean } = {}
	local thieves: { number } = {}
	for _, thief in memory.carried do
		if not seen[thief] then
			seen[thief] = true
			table.insert(thieves, thief)
		end
	end
	table.sort(thieves)
	for _, thief in thieves do
		table.insert(all, { kind = "stealing", thief = thief })
	end
	for i = #memory.stolen, 1, -1 do
		local card = memory.stolen[i]
		if (card.startedAt :: number) + StealCardsLogic.STOLEN_SECONDS > now then
			table.insert(all, card)
		end
	end
	local shown: { Card } = {}
	for i = 1, math.min(#all, StealCardsLogic.MAX_CARDS) do
		shown[i] = all[i]
	end
	return shown, #all - #shown
end

-- The card's title (`name` is the thief's display name).
function StealCardsLogic.title(card: Card, name: string): string
	if card.kind == "stealing" then
		return `{name} is stealing your slime!`
	end
	return `{name} has stolen one of your slimes`
end

-- The small line under the title, nil for none.
function StealCardsLogic.subtitle(card: Card): string?
	if card.kind == "stealing" then
		return "Chase them and hit them with your bat"
	end
	return "Lock your base to keep the rest safe"
end

-- The "+N more" chip text, nil when nothing is hidden.
function StealCardsLogic.moreText(hidden: number): string?
	if hidden <= 0 then
		return nil
	end
	return `+{hidden} more`
end

return StealCardsLogic
