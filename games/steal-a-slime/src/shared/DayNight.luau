--!strict
--[[
	DayNight (FEATURES.DayNight)

	Lighting.ClockTime from seconds since server start: one full day every
	DAY_LENGTH seconds, daytime (06:30 -> 17:30) for DAY_FRACTION of it and a
	quicker night (17:30 -> 06:30) for the rest. Starts at 06:30. Pure.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local DayNight = {}

DayNight.SUNRISE = 6.5
DayNight.SUNSET = 17.5

function DayNight.clockTime(elapsed: number): number
	local phase = (math.max(elapsed, 0) % Config.DAY_LENGTH) / Config.DAY_LENGTH
	local dayHours = DayNight.SUNSET - DayNight.SUNRISE
	if phase < Config.DAY_FRACTION then
		return DayNight.SUNRISE + dayHours * phase / Config.DAY_FRACTION
	end
	local night = (phase - Config.DAY_FRACTION) / (1 - Config.DAY_FRACTION)
	return (DayNight.SUNSET + (24 - dayHours) * night) % 24
end

-- The dawn / dusk phase `elapsed` seconds into the cycle: 0 = first day, 1 = first
-- night, 2 = second day ... Also returns the seconds left in that phase.
function DayNight.phase(elapsed: number): (number, number)
	local e = math.max(elapsed, 0)
	local cycle = math.floor(e / Config.DAY_LENGTH)
	local into = e - cycle * Config.DAY_LENGTH
	local dayLen = Config.DAY_LENGTH * Config.DAY_FRACTION
	if into < dayLen then
		return cycle * 2, dayLen - into
	end
	return cycle * 2 + 1, Config.DAY_LENGTH - into
end

return table.freeze(DayNight)
