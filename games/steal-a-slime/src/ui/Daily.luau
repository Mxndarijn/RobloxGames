--!strict
--[[
	Daily

	Pure helpers for the daily reward popup (Panels/DailyPopup). Reads
	`State.daily` (CONTRACT §5.1); no Roblox APIs, so it runs under Lune
	(tests/ui/Daily.spec.luau). The server decides everything: the popup only
	shows `daily.amount` and calls `Request("Daily")`.

	CONTRACT gap (UI-CONTRACT-GAPS.md): `State.daily.streak` is the streak
	of the *last* claim, and a missed day resets it, so the client can't tell
	which day today's claim counts as. `dayOf` derives it from `amount`
	(= DAILY_BASE × day × rebirthMultiplier, Progression.dailyAmount); a
	`daily.day` field would remove the guess.
]]

export type DailyLike = { available: boolean, streak: number, amount: number }
export type Cell = { day: number, state: "claimed" | "today" | "upcoming" }

local Daily = {}

-- The streak day (1..cap) that `daily.amount` pays. Falls back to the stored
-- streak (+1 when a claim is available) if the amount can't be decoded.
function Daily.dayOf(daily: DailyLike, base: number, multiplier: number, cap: number): number
	local fallback = if daily.available then daily.streak + 1 else daily.streak
	local day = fallback
	if base > 0 and multiplier > 0 and type(daily.amount) == "number" and daily.amount > 0 then
		day = math.floor(daily.amount / (base * multiplier) + 0.5)
	end
	return math.clamp(day, 1, math.max(cap, 1))
end

-- One cell per streak day for the popup's track. `today` is the day being
-- claimed (or the last claimed day when nothing is available).
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

-- Auto-open once per availability edge: the first State with a claim ready,
-- or when one becomes ready while playing. Not again after the player closes it.
function Daily.shouldAutoOpen(wasAvailable: boolean?, available: boolean): boolean
	return available and wasAvailable ~= true
end

return table.freeze(Daily)
