--!strict
--[[
	NoticeCards (contract/notice-cards.md): the short moments a player sees as a card in the top banner stack.
	Pure (tests/NoticeCards.spec.luau).

	* Bonked: you were bonked while carrying a stolen slime; it bounced home.
	* SlimeHome: a slime someone was stealing from you went back home (`name` = who had it).
	* BaseLocked: you walked into a locked base (`opensAt` = when its lock ends).

	The server keeps each player's recent notices (World.notice) and sends the live ones in State.notices;
	the client shows each one once, for SECONDS[id] from `at`.
]]

local NoticeCards = {}

export type Id = "Bonked" | "SlimeHome" | "BaseLocked"

export type Notice = {
	id: Id,
	at: number, -- server time it happened
	name: string?, -- SlimeHome: the thief's display name
	opensAt: number?, -- BaseLocked: when that base's lock ends
}

NoticeCards.SECONDS = table.freeze({
	Bonked = 3,
	SlimeHome = 3,
	BaseLocked = 4,
} :: { [Id]: number })

NoticeCards.CAP = 4 -- notices kept per player; older ones drop off

function NoticeCards.seconds(id: Id): number
	return NoticeCards.SECONDS[id] or 3
end

function NoticeCards.isLive(notice: Notice, now: number): boolean
	return notice.at + NoticeCards.seconds(notice.id) > now
end

-- Adds `notice` to `list` (mutates), dropping notices that are over or past CAP.
function NoticeCards.add(list: { Notice }, notice: Notice, now: number)
	for i = #list, 1, -1 do
		if not NoticeCards.isLive(list[i], now) then
			table.remove(list, i)
		end
	end
	table.insert(list, notice)
	while #list > NoticeCards.CAP do
		table.remove(list, 1)
	end
end

-- The notices still showing at `now`, as fresh tables (State.notices).
function NoticeCards.live(list: { Notice }?, now: number): { Notice }
	local out: { Notice } = {}
	for _, notice in list or {} do
		if NoticeCards.isLive(notice, now) then
			table.insert(out, table.clone(notice))
		end
	end
	return out
end

return NoticeCards
