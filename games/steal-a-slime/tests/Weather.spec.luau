--!strict
local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local Rng = require("../src/shared/Rng")
local TestRunner = require("./TestRunner")
local Weather = require("../src/shared/Weather")
local WeatherLook = require("../src/visuals/shared/WeatherLook")
local WeatherService = require("../src/server/WeatherService")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- A stand-in for workspace: attributes plus a change signal.
local function fakeHolder()
	local attrs: { [string]: any } = {}
	local fns: { [string]: { () -> () } } = {}
	local holder = {}
	function holder:SetAttribute(name: string, value: any)
		attrs[name] = value
		for _, fn in fns[name] or {} do
			fn()
		end
	end
	function holder:GetAttribute(name: string)
		return attrs[name]
	end
	function holder:GetAttributeChangedSignal(name: string)
		return {
			Connect = function(_self: any, fn: () -> ())
				fns[name] = fns[name] or {}
				table.insert(fns[name], fn)
				return {
					Disconnect = function()
						table.remove(fns[name], table.find(fns[name], fn))
					end,
				}
			end,
		}
	end
	return holder
end

local function sequence(values: { number }): () -> number
	local i = 0
	return function()
		i += 1
		return values[(i - 1) % #values + 1]
	end
end

describe("Weather cycle", function()
	it("starts Clear and holds until WEATHER_FIRST_AT", function()
		local state = WeatherService.new(100)
		expect(state.id).toBe("Clear")
		expect(WeatherService.step(state, 100 + Config.WEATHER_FIRST_AT - 1, sequence({ 0.5 }))).toBe(false)
		expect(state.id).toBe("Clear")
	end)
	it("changes at the deadline, never repeats, and lasts within the configured range", function()
		local state = WeatherService.new(0)
		local t = Config.WEATHER_FIRST_AT
		local seen: { [string]: boolean } = {}
		local rng = Rng.new(7)
		local function roll()
			return rng:float()
		end
		for _ = 1, 60 do
			local before = state.id
			expect(WeatherService.step(state, t, roll)).toBe(true)
			expect(state.id == before).toBe(false)
			seen[state.id] = true
			local d = Config.WEATHER[state.id]
			local length = state.changeAt - t
			expect(length >= d.minSeconds and length <= d.maxSeconds).toBe(true)
			t = state.changeAt
		end
		for _, id in { "Clear", "Rain", "Snow", "Starfall" } do
			expect(seen[id]).toBe(true)
		end
	end)
	it("pick covers every other id across rolls and clamps out-of-range rolls", function()
		expect(Weather.pick("Rain", 0)).toBe("Clear")
		expect(Weather.pick("Rain", 5)).toBe("Starfall")
		expect(Weather.pick(nil, -1)).toBe("Clear")
	end)
	it("durations come from Config.WEATHER", function()
		expect(Weather.duration("Rain", 0)).toBe(Config.WEATHER.Rain.minSeconds)
		expect(Weather.duration("Rain", 1)).toBe(Config.WEATHER.Rain.maxSeconds)
	end)
end)

describe("Weather replication", function()
	it("publish writes the workspace attribute; attach mirrors it and fires Changed once per change", function()
		Weather.reset()
		local holder = fakeHolder()
		local log: { string } = {}
		Weather.attach(holder)
		Weather.Changed:Connect(function(new, old)
			table.insert(log, `{old}>{new}`)
		end)
		local state = WeatherService.new(0)
		state.id = "Snow"
		WeatherService.publish(state, holder)
		expect(holder:GetAttribute(Constants.WEATHER_ATTRIBUTE)).toBe("Snow")
		expect(Weather.getCurrent()).toBe("Snow")
		WeatherService.publish(state, holder) -- same id: no second event
		holder:SetAttribute(Constants.WEATHER_ATTRIBUTE, "Rain")
		holder:SetAttribute(Constants.WEATHER_ATTRIBUTE, "garbage") -- unknown ids read as Clear
		expect(log).toEqual({ "Clear>Snow", "Snow>Rain", "Rain>Clear" })
		Weather.reset()
	end)
	it("a late-joining client reads the value already set", function()
		Weather.reset()
		local holder = fakeHolder()
		holder:SetAttribute(Constants.WEATHER_ATTRIBUTE, "Starfall")
		Weather.attach(holder)
		expect(Weather.getCurrent()).toBe("Starfall")
		Weather.reset()
	end)
end)

describe("Weather visual quality", function()
	it("rates scale with the graphics level and touch", function()
		local low, high = Weather.qualityScale(1, false), Weather.qualityScale(10, false)
		expect(low < high).toBe(true)
		expect(high).toBe(1)
		expect(low >= 0.2).toBe(true)
		expect(Weather.qualityScale(10, true) < high).toBe(true)
		expect(Weather.qualityScale(0, false)).toBe(0.5)
		local rain = WeatherLook.EMITTERS.Drops
		expect(Weather.emitterRate(rain.rate, rain.lifetime, low) < Weather.emitterRate(rain.rate, rain.lifetime, 0.7)).toBe(
			true
		)
	end)
	it("every emitter stays under its share of the hard particle cap at any quality", function()
		local total = 0
		for _, look in WeatherLook.LOOKS do
			local alive = 0
			for _, name in look.emitters do
				local spec = WeatherLook.EMITTERS[name]
				expect(spec ~= nil).toBe(true)
				for _, scale in { 0.2, 0.6, 1, 50 } do
					local rate = Weather.emitterRate(spec.rate, spec.lifetime, scale, spec.share)
					expect(rate * spec.lifetime <= Config.WEATHER_PARTICLE_CAP * spec.share + 1e-6).toBe(true)
				end
				alive += Weather.emitterRate(spec.rate, spec.lifetime, 50, spec.share) * spec.lifetime
			end
			expect(alive <= Config.WEATHER_PARTICLE_CAP + 1e-6).toBe(true)
			total += 1
		end
		expect(total).toBe(4)
	end)
	it("every weather id has a look", function()
		for _, id in Config.WEATHER_ORDER do
			expect(WeatherLook.LOOKS[id] ~= nil).toBe(true)
		end
	end)
end)

describe("Weather flag", function()
	it("is on", function()
		expect(Config.FEATURES.Weather).toBe(true)
	end)
	it("flag off draws nothing for any server id, unless a debug preview is set", function()
		for _, id in Config.WEATHER_ORDER do
			expect(Weather.visualId(false, id, nil)).toBe("Clear")
		end
		expect(Weather.visualId(false, "Rain", "Snow")).toBe("Snow")
		expect(Weather.visualId(false, "Rain", "nonsense")).toBe("Clear")
	end)
	it("flag on follows the server id, and a debug id wins", function()
		expect(Weather.visualId(true, "Rain", nil)).toBe("Rain")
		expect(Weather.visualId(true, "Rain", "Starfall")).toBe("Starfall")
		expect(Weather.visualId(true, "bogus", nil)).toBe("Clear")
	end)
end)

describe("Weather hook for #8", function()
	it(
		"exposes getCurrent, Changed and Config.WEATHER[id] with a mutation and chanceBonus on every weather but Clear",
		function()
			expect(type(Weather.getCurrent)).toBe("function")
			expect(type(Weather.Changed.Connect)).toBe("function")
			for _, id in Config.WEATHER_ORDER do
				local data = Weather.data(id)
				expect(data.chanceBonus >= 0).toBe(true)
				expect((data.mutation == nil) == (data.chanceBonus == 0)).toBe(true)
			end
		end
	)
end)
