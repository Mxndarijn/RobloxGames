--!strict
--[[
	ExclusiveRotation (pure, contract/exclusive-shop.md §6)

	The weekly featured Exclusive seats: `featured(week)` picks Config.EXCLUSIVE_SHOP.featuredCount distinct
	Exclusive seats from Config.PET_SEATS with a small seeded shuffle, so every server (and the client, for the
	carousel riders) gets the same four for the same UTC week. `week(now)` is the week index of a unix time.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local ExclusiveRotation = {}

local WEEK_SECONDS = 7 * 24 * 3600

local exclusives: { string } = {}
for _, seat in Config.PET_SEATS do
	if seat.unlock.kind == "exclusive" then
		table.insert(exclusives, seat.id)
	end
end
ExclusiveRotation.SEATS = table.freeze(exclusives)

function ExclusiveRotation.week(now: number): number
	return math.floor(now / WEEK_SECONDS)
end

-- Deterministic for a week index; never repeats a seat within one week.
function ExclusiveRotation.featured(week: number): { string }
	local pool = table.clone(exclusives)
	local state = (math.floor(week) * 2654435761 + 97) % 4294967296
	local function nextInt(n: number): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state % n + 1
	end
	for i = #pool, 2, -1 do
		local j = nextInt(i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(Config.EXCLUSIVE_SHOP.featuredCount, #pool) do
		out[i] = pool[i]
	end
	return out
end

return ExclusiveRotation
