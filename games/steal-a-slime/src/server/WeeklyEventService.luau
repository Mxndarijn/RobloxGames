--!strict
--[[
	WeeklyEventService (server, FEATURES.WeeklyEvents, CONTRACT.md §17)

	Replicates the weekly schedule through the workspace attribute Constants.WEEKLY_EVENT_ATTRIBUTE
	(WeeklyEvents.encode) so the client / events board can read the current and next event. The effects
	themselves are applied at drop time (Spawner.spawnOne); nothing here changes gameplay. `publish` only
	writes when the value changed. `start` sleeps until the next boundary (at most SYNC_SECONDS).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local WeeklyEvents = if Shared then require(Shared.WeeklyEvents) else require("../shared/WeeklyEvents")

local WeeklyEventService = {}

-- Writes the attribute for unix time `now`. Returns true when it changed. Feature off: clears it.
function WeeklyEventService.publish(holder: any, now: number): boolean
	local value: string? = if WeeklyEvents.enabled() then WeeklyEvents.encode(now) else nil
	if holder:GetAttribute(Constants.WEEKLY_EVENT_ATTRIBUTE) == value then
		return false
	end
	holder:SetAttribute(Constants.WEEKLY_EVENT_ATTRIBUTE, value)
	return true
end

-- Seconds until `publish` has anything new to say after `now`.
function WeeklyEventService.waitSeconds(now: number): number
	local soonest = WeeklyEvents.next(now).startsAt
	for _, event in WeeklyEvents.current(now) do
		soonest = math.min(soonest, event.endsAt)
	end
	return math.clamp(soonest - now, 1, Config.WEEKLY.SYNC_SECONDS)
end

-- Server entry. `unixNow` is os.time.
function WeeklyEventService.start(holder: any, unixNow: () -> number)
	WeeklyEventService.publish(holder, unixNow())
	if not WeeklyEvents.enabled() then
		return
	end
	task.spawn(function()
		while true do
			task.wait(WeeklyEventService.waitSeconds(unixNow()))
			WeeklyEventService.publish(holder, unixNow())
		end
	end)
end

return WeeklyEventService
