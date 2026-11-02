--!strict
--[[
	Daily

	Pure helpers for the daily reward part of the welcome card (Panels/Welcome, WelcomeBack.view). Reads
	`State.daily` (CONTRACT §5.1); no Roblox APIs, so it runs under Lune (tests/ui/Daily.spec.luau). The
	server decides everything: the card only shows `daily.amount` and calls `Request("Daily")`.
]]

export type DailyLike = { available: boolean, streak: number, amount: number, day: number? }
export type Cell = { day: number, state: "claimed" | "today" | "upcoming" }

local Daily = {}

-- The streak day (1..cap) the pending claim pays, or the day the last claim paid (`daily.day`). Falls back to the
-- stored streak (+1 when a claim is available) when State has no day.
function Daily.dayOf(daily: DailyLike, cap: number): number
	local day = if type(daily.day) == "number"
		then daily.day
		else (if daily.available then daily.streak + 1 else daily.streak)
	return math.clamp(day, 1, math.max(cap, 1))
end

-- One cell per streak day for the track. `today` is the day being claimed (or the last claimed day when nothing
-- is available).
function Daily.track(today: number, cap: number, available: boolean): { Cell }
	local cells: { Cell } = {}
	for day = 1, cap do
		local state: "claimed" | "today" | "upcoming" = "upcoming"
		if day < today or (day == today and not available) then
			state = "claimed"
		elseif day == today then
			state = "today"
		end
		table.insert(cells, { day = day, state = state })
	end
	return cells
end

-- Cash a given streak day pays (mirrors Progression.dailyAmount: base * day * multiplier, floored).
function Daily.reward(day: number, base: number, multiplier: number): number
	return math.floor(base * day * multiplier)
end

-- A tile's label: "Day N" for today and the last day, the bare number otherwise, empty once claimed (the tile's
-- check shows there instead).
function Daily.dayLabel(day: number, state: string, cap: number): string
	if state == "claimed" then
		return ""
	end
	return if state == "today" or day == cap then `Day {day}` else tostring(day)
end

-- Auto-open once per availability edge: the first State with a claim ready, or when one becomes ready while
-- playing. Not again after the player closes it.
function Daily.shouldAutoOpen(wasAvailable: boolean?, available: boolean): boolean
	return available and wasAvailable ~= true
end

return table.freeze(Daily)
