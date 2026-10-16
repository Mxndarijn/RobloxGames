--!strict
--[[
	WeatherService (FEATURES.Weather)

	Cycles Clear -> Rain / Snow / Starfall on a timer and replicates the id through the workspace
	attribute Constants.WEATHER_ATTRIBUTE. Nothing runs per frame: start() sleeps until the next
	change (task.wait) and clients do all the drawing. The state is plain data so tests can step it.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local Weather = if Shared then require(Shared.Weather) else require("../shared/Weather")

local WeatherService = {}

export type State = { id: string, changeAt: number }

-- Starts Clear; the first change comes WEATHER_FIRST_AT seconds after `t0`.
function WeatherService.new(t0: number): State
	return { id = Weather.CLEAR, changeAt = t0 + Config.WEATHER_FIRST_AT }
end

-- Advances to time `t`. Returns true if the id changed. `roll` returns [0, 1).
function WeatherService.step(state: State, t: number, roll: () -> number): boolean
	if t < state.changeAt then
		return false
	end
	state.id = Weather.pick(state.id, roll())
	state.changeAt = t + Weather.duration(state.id, roll())
	return true
end

-- Writes the replicated attributes and updates the shared Weather module (server-side readers).
-- `serverNow` is workspace:GetServerTimeNow(); on a change it stamps WEATHER_STARTED_ATTRIBUTE (and
-- SNOW_ENDED_ATTRIBUTE when Snow stops, cleared when it starts) BEFORE the id, so a client that sees the new
-- id always sees matching times. Clients use them to place a late join inside the settle / melt.
function WeatherService.publish(state: State, holder: any, serverNow: number?)
	if serverNow and holder:GetAttribute(Constants.WEATHER_ATTRIBUTE) ~= state.id then
		local previous = holder:GetAttribute(Constants.WEATHER_ATTRIBUTE)
		holder:SetAttribute(Constants.WEATHER_STARTED_ATTRIBUTE, serverNow)
		if state.id == "Snow" then
			holder:SetAttribute(Constants.SNOW_ENDED_ATTRIBUTE, nil)
		elseif previous == "Snow" then
			holder:SetAttribute(Constants.SNOW_ENDED_ATTRIBUTE, serverNow)
		end
	end
	holder:SetAttribute(Constants.WEATHER_ATTRIBUTE, state.id)
	Weather.set(state.id)
end

-- Server entry (`now` must be server time, workspace:GetServerTimeNow): publishes Clear, then sleeps from change to change. Returns the state.
function WeatherService.start(holder: any, now: () -> number): State
	local state = WeatherService.new(now())
	WeatherService.publish(state, holder, now())
	task.spawn(function()
		while true do
			task.wait(math.max(state.changeAt - now(), 1))
			if WeatherService.step(state, now(), math.random) then
				WeatherService.publish(state, holder, now())
			end
		end
	end)
	return state
end

return WeatherService
