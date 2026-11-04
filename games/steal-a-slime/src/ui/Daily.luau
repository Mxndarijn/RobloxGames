--!strict
--[[
	Daily

	Pure helpers for the daily streak part of the welcome card (Panels/Welcome, WelcomeBack.view). Reads
	`State.daily` (contract/daily-streak.md); no Roblox APIs, so it runs under Lune (tests/ui/Daily.spec.luau). The
	server decides everything: the card shows `daily.track` / `daily.reward` and calls `Request("Daily")`.
]]

export type Reward = {
	day: number,
	kind: string,
	label: string,
	short: string,
	icon: string,
	amount: number?,
	skin: boolean,
}
export type DailyLike = { available: boolean, streak: number, day: number, track: { Reward }? }
export type Cell = { day: number, state: "claimed" | "today" | "upcoming", reward: Reward }

local Daily = {}

Daily.TRACK = 7 -- tiles in the track (the server sends this many days)

-- One cell per day in `daily.track`. A day before `daily.day` is claimed; `daily.day` itself is today while a claim
-- is ready, else it was claimed today too.
function Daily.track(daily: DailyLike): { Cell }
	local cells: { Cell } = {}
	local available = daily.available == true
	for _, reward in (if type(daily.track) == "table" then daily.track else {}) :: { Reward } do
		local state: "claimed" | "today" | "upcoming" = "upcoming"
		if reward.day < daily.day or (reward.day == daily.day and not available) then
			state = "claimed"
		elseif reward.day == daily.day then
			state = "today"
		end
		table.insert(cells, { day = reward.day, state = state, reward = reward })
	end
	return cells
end

-- A tile's label: "Day N" for today and skin days, the bare number otherwise, empty once claimed (the tile's check
-- shows there instead).
function Daily.dayLabel(cell: Cell): string
	if cell.state == "claimed" then
		return ""
	end
	return if cell.state == "today" or cell.reward.skin then `Day {cell.day}` else tostring(cell.day)
end

-- Auto-open once per availability edge: the first State with a claim ready, or when one becomes ready while
-- playing. Not again after the player closes it.
function Daily.shouldAutoOpen(wasAvailable: boolean?, available: boolean): boolean
	return available and wasAvailable ~= true
end

return table.freeze(Daily)
