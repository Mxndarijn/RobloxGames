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

return table.freeze(DayNight)
