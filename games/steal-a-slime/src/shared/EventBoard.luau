--!strict
--[[
	EventBoard (pure)
	The cards of the Upcoming Events wall at the fountain (server/EventBoardView draws them): the boss, Slime Rain,
	the guaranteed Legendary and Mythic drops, and a running admin or weekly event (the weather is not on it). Each
	card has an icon key, an accent colour, a title, a detail line and a "m:ss" countdown. Running events come first,
	then the rest soonest first; a card with nothing to say is left out.
]]

export type Input = {
	bossHere: string?, -- name of the boss on the plaza now (nil = none)
	bossAt: number?, -- server time of the next boss arrival
	rainEndsAt: number?, -- Slime Rain running until this time
	rainAt: number?, -- next Slime Rain start (when none runs)
	legendaryIn: number?, -- seconds until the guaranteed Legendary (Spawner.guaranteeIn)
	mythicIn: number?, -- seconds until the guaranteed Mythic
	event: string?, -- a running admin or weekly event's label
	eventEndsAt: number?,
}

export type Row = {
	id: string, -- "boss" | "rain" | "legendary" | "mythic" | "event"
	icon: string, -- EventBoard.ICONS key (the view maps it to an image or a glyph)
	accent: { number }, -- RGB
	title: string,
	detail: string,
	time: string, -- the countdown, "NOW" or "2:05 left"
	live: boolean, -- running now
	inSeconds: number, -- seconds until it starts (0 while live); the sort key
}

local EventBoard = {}

EventBoard.TITLE = "Upcoming Events"
EventBoard.MAX_ROWS = 6

-- Accent colours per card.
EventBoard.ACCENTS = table.freeze({
	boss = table.freeze({ 255, 84, 84 }),
	rain = table.freeze({ 70, 170, 255 }),
	legendary = table.freeze({ 255, 196, 40 }),
	mythic = table.freeze({ 236, 90, 255 }),
	event = table.freeze({ 60, 220, 120 }),
})

-- Order among cards that start at the same moment.
local RANK = table.freeze({ boss = 1, event = 2, rain = 3, mythic = 4, legendary = 5 })

-- "m:ss" for `seconds` (rounded up, never negative).
function EventBoard.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function card(
	id: string,
	accent: { number },
	title: string,
	detail: string,
	time: string,
	live: boolean,
	inSeconds: number
): Row
	return {
		id = id,
		icon = id,
		accent = accent,
		title = title,
		detail = detail,
		time = time,
		live = live,
		inSeconds = if live then 0 else math.max(0, inSeconds),
	}
end

-- The cards, running ones first, then soonest first; at most MAX_ROWS.
function EventBoard.rows(input: Input, now: number): { Row }
	local A = EventBoard.ACCENTS
	local rows: { Row } = {}
	if input.bossHere then
		table.insert(rows, card("boss", A.boss, "Boss Fight", `{input.bossHere} is here!`, "NOW", true, 0))
	elseif input.bossAt then
		local left = input.bossAt - now
		table.insert(rows, card("boss", A.boss, "Boss", "arrives at the fountain", EventBoard.clock(left), false, left))
	end
	if input.rainEndsAt then
		local left = EventBoard.clock(input.rainEndsAt - now)
		table.insert(rows, card("rain", A.rain, "Slime Rain", "rarer slimes fall now!", `{left} left`, true, 0))
	elseif input.rainAt then
		local left = input.rainAt - now
		table.insert(
			rows,
			card("rain", A.rain, "Slime Rain", "slimes pour from the sky", EventBoard.clock(left), false, left)
		)
	end
	if input.legendaryIn then
		table.insert(
			rows,
			card(
				"legendary",
				A.legendary,
				"Legendary",
				"guaranteed from the fountain",
				EventBoard.clock(input.legendaryIn),
				false,
				input.legendaryIn
			)
		)
	end
	if input.mythicIn then
		table.insert(
			rows,
			card(
				"mythic",
				A.mythic,
				"Mythic",
				"guaranteed from the fountain",
				EventBoard.clock(input.mythicIn),
				false,
				input.mythicIn
			)
		)
	end
	if input.event then
		local left = if input.eventEndsAt then `{EventBoard.clock(input.eventEndsAt - now)} left` else "NOW"
		table.insert(rows, card("event", A.event, input.event, "event running", left, true, 0))
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		if a.live ~= b.live then
			return a.live
		end
		if a.inSeconds ~= b.inSeconds then
			return a.inSeconds < b.inSeconds
		end
		return RANK[a.id] < RANK[b.id]
	end)
	while #rows > EventBoard.MAX_ROWS do
		table.remove(rows)
	end
	return rows
end

-- The cards as plain text, one "Title: detail (time)" line each (logs and tests).
function EventBoard.text(rows: { Row }): string
	local lines = {}
	for _, row in rows do
		local time = if row.time ~= "" then ` ({row.time})` else ""
		table.insert(lines, `{row.title}: {row.detail}{time}`)
	end
	return table.concat(lines, "\n")
end

-- A key that changes only when the cards or their order change (the view rebuilds then, else only retexts).
function EventBoard.layoutKey(rows: { Row }): string
	local ids = {}
	for _, row in rows do
		table.insert(ids, `{row.icon}{if row.live then "!" else ""}`)
	end
	return table.concat(ids, ",")
end

return table.freeze(EventBoard)
