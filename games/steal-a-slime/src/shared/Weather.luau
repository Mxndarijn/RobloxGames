--!strict
--[[
	Weather (FEATURES.Weather, WEATHER.md)

	Shared, mostly pure. The server's WeatherService writes the workspace attribute
	Constants.WEATHER_ATTRIBUTE; both sides call Weather.attach(workspace) to mirror it.

	  Weather.getCurrent(): string        current weather id ("Clear" until attached / unknown value)
	  Weather.Changed:Connect(fn(new, old))  fires when the id changes
	  Weather.data(id)                    Config.WEATHER[id] (the hook table for #8)
	  Weather.pick(previous, roll)        next id by weight, never the same twice in a row
	  Weather.duration(id, roll)          seconds the id lasts
	  Weather.qualityScale(level, touch)  0.2..1 emitter-rate factor from the graphics level
	  Weather.emitterRate(base, lifetime, scale, share)  rate under the particle cap
	  Weather.visualId(enabled, current, debug)  what the client should draw
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Constants = if script then require(script.Parent.Constants) else require("./Constants")

local Weather = {}

export type Id = string
type Listener = (new: Id, old: Id) -> ()

Weather.CLEAR = "Clear"
Weather.ORDER = Config.WEATHER_ORDER

local current: Id = Weather.CLEAR
local listeners: { Listener } = {}
local connection: { Disconnect: (any) -> () }? = nil

local function known(id: any): boolean
	return type(id) == "string" and Config.WEATHER[id] ~= nil
end

Weather.Changed = {
	Connect = function(_self: any, fn: Listener)
		table.insert(listeners, fn)
		return {
			Disconnect = function()
				local i = table.find(listeners, fn)
				if i then
					table.remove(listeners, i)
				end
			end,
		}
	end,
}

function Weather.getCurrent(): Id
	return current
end

function Weather.data(id: Id)
	return Config.WEATHER[id]
end

-- Sets the id (unknown ids become "Clear") and fires Changed once if it differs.
function Weather.set(id: any)
	local new: Id = if known(id) then id else Weather.CLEAR
	if new == current then
		return
	end
	local old = current
	current = new
	for _, fn in table.clone(listeners) do
		local ok, err = pcall(fn :: any, new, old)
		if not ok then
			warn(`[Weather] Changed listener failed: {err}`)
		end
	end
end

-- Mirrors a holder's attribute (workspace) into Weather. Idempotent: re-attaching replaces the old link.
function Weather.attach(holder: any)
	if connection then
		connection:Disconnect()
	end
	connection = holder:GetAttributeChangedSignal(Constants.WEATHER_ATTRIBUTE):Connect(function()
		Weather.set(holder:GetAttribute(Constants.WEATHER_ATTRIBUTE))
	end)
	Weather.set(holder:GetAttribute(Constants.WEATHER_ATTRIBUTE))
end

-- Test helper: back to a fresh Clear state with no listeners.
function Weather.reset()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	table.clear(listeners)
	current = Weather.CLEAR
end

-- Weighted pick from Config.WEATHER_ORDER, excluding `previous` so the weather always changes. roll in [0, 1).
function Weather.pick(previous: Id?, roll: number): Id
	local total = 0
	for _, id in Config.WEATHER_ORDER do
		if id ~= previous then
			total += Config.WEATHER[id].weight
		end
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	local last = Weather.CLEAR
	for _, id in Config.WEATHER_ORDER do
		if id ~= previous then
			last = id
			target -= Config.WEATHER[id].weight
			if target < 0 then
				return id
			end
		end
	end
	return last
end

function Weather.duration(id: Id, roll: number): number
	local d = Config.WEATHER[id] or Config.WEATHER.Clear
	return d.minSeconds + (d.maxSeconds - d.minSeconds) * math.clamp(roll, 0, 1)
end

-- Graphics level (1..10; 0 = automatic) to a 0.2..1 factor. Touch devices get 60% of it.
function Weather.qualityScale(level: number, touch: boolean?): number
	local l = if level <= 0 then 5 else math.clamp(level, 1, 10)
	local scale = math.clamp(l / 10, 0.2, 1)
	if touch then
		scale *= 0.6
	end
	return scale
end

-- Emitter Rate for a base rate: scaled by quality, then limited so rate * lifetime (particles alive)
-- stays under this emitter's `share` (0..1) of Config.WEATHER_PARTICLE_CAP.
function Weather.emitterRate(base: number, lifetime: number, scale: number, share: number?): number
	local cap = Config.WEATHER_PARTICLE_CAP * (share or 1)
	return math.max(0, math.min(base * scale, cap / math.max(lifetime, 0.1)))
end

-- What the client draws: nothing unless FEATURES.Weather is on; a known debug id (pc-watcher) wins over the server's.
-- With the flag off a debug id still previews, so shots can be reviewed before the flag is flipped.
function Weather.visualId(enabled: boolean, serverId: Id, debug: any): Id
	if known(debug) then
		return debug
	end
	if not enabled then
		return Weather.CLEAR
	end
	return if known(serverId) then serverId else Weather.CLEAR
end

return Weather
