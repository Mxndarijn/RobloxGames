--!strict
--[[
	Suspicion (pure)

	Points per player that drain over time. `add` returns the level the points reached:

	* "ok": below `pauseAt`.
	* "pause": at or over `pauseAt`; the game pauses whatever the player was abusing for `pauseSeconds`.
	* "kick": at or over `kickAt`.

	The game decides what each kind of offence is worth and what a level does. No Roblox APIs.
]]

export type Level = "ok" | "pause" | "kick"

export type Options = {
	drainPerSecond: number,
	pauseAt: number,
	pauseSeconds: number,
	kickAt: number,
}

export type State = {
	options: Options,
	points: number,
	at: number, -- last time points were drained
	pausedUntil: number,
}

local Suspicion = {}

Suspicion.DEFAULTS = table.freeze({
	drainPerSecond = 1 / 60,
	pauseAt = 3,
	pauseSeconds = 60,
	kickAt = 8,
} :: Options)

function Suspicion.new(now: number, overrides: { [string]: number }?): State
	local options = table.clone(Suspicion.DEFAULTS) :: any
	for key, value in overrides or {} do
		if options[key] == nil or type(value) ~= "number" or value ~= value then
			error(`Suspicion.new: bad option {tostring(key)}`, 2)
		end
		options[key] = value
	end
	return { options = table.freeze(options) :: Options, points = 0, at = now, pausedUntil = -math.huge }
end

-- Points left at `now` after draining (also moves the drain clock).
function Suspicion.points(state: State, now: number): number
	local gone = math.max(0, now - state.at) * state.options.drainPerSecond
	state.points = math.max(0, state.points - gone)
	state.at = math.max(state.at, now)
	return state.points
end

function Suspicion.add(state: State, points: number, now: number): Level
	local total = Suspicion.points(state, now) + math.max(0, points)
	state.points = total
	local o = state.options
	if total >= o.kickAt then
		return "kick"
	end
	if total >= o.pauseAt then
		state.pausedUntil = now + o.pauseSeconds
		return "pause"
	end
	return "ok"
end

function Suspicion.paused(state: State, now: number): boolean
	return now < state.pausedUntil
end

return table.freeze(Suspicion)
