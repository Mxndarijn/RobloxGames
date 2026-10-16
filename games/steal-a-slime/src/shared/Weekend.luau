--!strict
--[[
	Weekend (pure, Config.WEEKEND, competitor-gaps #17)

	The x2 Weekend: every cash income is multiplied while the UTC clock is in the window
	(Config.WEEKEND.weekdays, Sat 00:00 - Sun 23:59 by default) or on one of the extra
	`overrideDates`. `now` is unix seconds and always passed in (os.time() on the server),
	so tests inject their own clock. Nothing is saved. No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Cfg = typeof(Config.WEEKEND)
export type View = { active: boolean, multiplier: number, endsAt: number? }

local Weekend = {}

local DAY = 86400

-- 1970-01-01 was a Thursday (4); 0 = Sunday.
local function weekday(day: number): number
	return (day + 4) % 7
end

local function dayActive(day: number, cfg: Cfg): boolean
	if table.find(cfg.weekdays, weekday(day)) then
		return true
	end
	local dates = cfg.overrideDates
	return #dates > 0 and table.find(dates, os.date("!%Y-%m-%d", day * DAY)) ~= nil
end

-- `cfg` defaults to Config.WEEKEND (tests pass their own).
function Weekend.active(now: number, cfg: Cfg?): boolean
	local c = cfg or Config.WEEKEND
	return c.enabled and c.multiplier > 1 and dayActive(math.floor(now / DAY), c)
end

-- Income multiplier at `now` (1 = none).
function Weekend.multiplier(now: number, cfg: Cfg?): number
	return if Weekend.active(now, cfg) then (cfg or Config.WEEKEND).multiplier else 1
end

-- First second after the active run that contains `now`; nil when not active.
function Weekend.endsAt(now: number, cfg: Cfg?): number?
	local c = cfg or Config.WEEKEND
	if not Weekend.active(now, c) then
		return nil
	end
	local day = math.floor(now / DAY)
	for _ = 1, 400 do -- a bounded walk: a config with every day active still ends
		if not dayActive(day, c) then
			break
		end
		day += 1
	end
	return day * DAY
end

function Weekend.view(now: number, cfg: Cfg?): View
	return {
		active = Weekend.active(now, cfg),
		multiplier = Weekend.multiplier(now, cfg),
		endsAt = Weekend.endsAt(now, cfg),
	}
end

return table.freeze(Weekend)
