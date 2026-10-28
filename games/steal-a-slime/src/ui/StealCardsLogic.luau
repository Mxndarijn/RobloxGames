--!strict
--[[
	StealCardsLogic: which cards show in the top banner stack (contract/notice-cards.md). Pure
	(tests/ui/StealCards.spec).

	* "stealing": one card per player carrying one of my slimes away right now (SlimeView.stolenBy).
	* "stolen": a slime that was being carried and is now gone from my plot was stolen; that card shows for
	  STOLEN_SECONDS. (A slime that escapes comes back with stolenBy cleared, so it is never gone.)
	* "bonked" / "home" / "locked": State.notices (shared/NoticeCards), each shown once for its seconds.

	At most MAX_CARDS cards show (live thieves first, then the newest); the rest are counted for a "+N more" chip.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local NoticeCards = if Shared then require(Shared.NoticeCards) else require("../shared/NoticeCards")

local StealCardsLogic = {}

StealCardsLogic.STOLEN_SECONDS = 4
StealCardsLogic.MAX_CARDS = 2

export type Kind = "stealing" | "stolen" | "bonked" | "home" | "locked"

export type Card = {
	kind: Kind,
	thief: number?, -- UserId: "stealing" / "stolen"
	name: string?, -- "home": who had the slime
	startedAt: number?, -- timed cards: when it happened
	endsAt: number?, -- timed cards: when it goes
	opensAt: number?, -- "locked": when that base opens
}

export type Memory = {
	carried: { [string]: number }, -- slime id -> thief UserId, from the last State
	timed: { Card }, -- "stolen" and notice cards, oldest first
	seen: { [string]: boolean }, -- notices already turned into a card (id .. at)
}

type SlimeLike = { slime: { id: string }, stolenBy: number? }
type StateLike = { slimes: { SlimeLike }, notices: { NoticeCards.Notice }? }

local NOTICE_KIND: { [string]: Kind } = { Bonked = "bonked", SlimeHome = "home", BaseLocked = "locked" }

function StealCardsLogic.new(): Memory
	return { carried = {}, timed = {}, seen = {} }
end

-- The next memory after a State arrives at `now`.
function StealCardsLogic.observe(memory: Memory, state: StateLike, now: number): Memory
	local present: { [string]: boolean } = {}
	local carried: { [string]: number } = {}
	for _, view in state.slimes do
		present[view.slime.id] = true
		if view.stolenBy ~= nil then
			carried[view.slime.id] = view.stolenBy
		end
	end
	local timed: { Card } = {}
	for _, card in memory.timed do
		if (card.endsAt :: number) > now then
			table.insert(timed, card)
		end
	end
	local gone: { Card } = {}
	for id, thief in memory.carried do
		if not present[id] then
			table.insert(
				gone,
				{ kind = "stolen", thief = thief, startedAt = now, endsAt = now + StealCardsLogic.STOLEN_SECONDS }
			)
		end
	end
	table.sort(gone, function(a, b)
		return (a.thief :: number) < (b.thief :: number)
	end)
	for _, card in gone do
		table.insert(timed, card)
	end
	local seen = memory.seen
	for _, notice in state.notices or {} do
		local key = `{notice.id}@{notice.at}`
		local kind = NOTICE_KIND[notice.id]
		if kind and not seen[key] then
			seen[key] = true
			local endsAt = notice.at + NoticeCards.seconds(notice.id)
			if endsAt > now then
				table.insert(timed, {
					kind = kind,
					name = notice.name,
					opensAt = notice.opensAt,
					startedAt = notice.at,
					endsAt = endsAt,
				})
			end
		end
	end
	return { carried = carried, timed = timed, seen = seen }
end

-- The cards to show at `now` (stealing first, then the newest timed cards) and how many more are hidden.
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
	for i = #memory.timed, 1, -1 do
		local card = memory.timed[i]
		if (card.endsAt :: number) > now then
			table.insert(all, card)
		end
	end
	local shown: { Card } = {}
	for i = 1, math.min(#all, StealCardsLogic.MAX_CARDS) do
		shown[i] = all[i]
	end
	return shown, #all - #shown
end

-- The card's title. `name` is the thief's display name (rich-text safe) for "stealing" / "stolen" / "home".
function StealCardsLogic.title(card: Card, name: string): string
	if card.kind == "stealing" then
		return `{name} is stealing your slime!`
	elseif card.kind == "stolen" then
		return `{name} has stolen one of your slimes`
	elseif card.kind == "bonked" then
		return "You got bonked!"
	elseif card.kind == "home" then
		return "Your slime is back home"
	end
	return "This base is locked"
end

-- The small line under the title at `now`, nil for none.
function StealCardsLogic.subtitle(card: Card, name: string, now: number): string?
	if card.kind == "stealing" then
		return "Chase them and hit them with your bat"
	elseif card.kind == "stolen" then
		return "Lock your base to keep the rest safe"
	elseif card.kind == "bonked" then
		return "The slime bounced home"
	elseif card.kind == "home" then
		return `It escaped from {name}`
	end
	if card.opensAt == nil then
		return nil
	end
	local left = math.max(math.ceil(card.opensAt - now), 0)
	return string.format("Opens in %d:%02d", left // 60, left % 60)
end

-- The "+N more" chip text, nil when nothing is hidden.
function StealCardsLogic.moreText(hidden: number): string?
	if hidden <= 0 then
		return nil
	end
	return `+{hidden} more`
end

return StealCardsLogic
