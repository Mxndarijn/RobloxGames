--!strict
local Config = require("../src/shared/Config")
local FeatureOverride = require("../src/shared/FeatureOverride")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local base = { FountainTiers = false, Audio = false, Weather = false, Parade = true }
local function attrs(t: { [string]: any }): (string) -> any
	return function(name: string)
		return t[name]
	end
end

describe("FeatureOverride", function()
	it("is ignored outside Studio, even with every attribute set", function()
		local all: { [string]: any } = {}
		for _, name in FeatureOverride.FLAGS do
			all[FeatureOverride.PREFIX .. name] = true
		end
		local view = FeatureOverride.wrap(base, false, attrs(all))
		expect(view == base).toBe(true)
		expect(view.FountainTiers).toBe(false)
		expect(view.Audio).toBe(false)
	end)

	it("turns a listed flag on in Studio when its attribute is true", function()
		local view = FeatureOverride.wrap(base, true, attrs({ PcwFlag_FountainTiers = true }))
		expect(view.FountainTiers).toBe(true)
		expect(view.Audio).toBe(false)
		expect(view.Parade).toBe(true)
	end)

	it("never overrides flags outside the list, never turns one off, ignores non-boolean values", function()
		local view = FeatureOverride.wrap(
			base,
			true,
			attrs({ PcwFlag_Weather = true, PcwFlag_Parade = false, PcwFlag_Audio = "yes" })
		)
		expect(view.Weather).toBe(false)
		expect(view.Parade).toBe(true)
		expect(view.Audio).toBe(false)
	end)

	it("is read-only and follows later attribute changes", function()
		local live: { [string]: any } = {}
		local view = FeatureOverride.wrap(base, true, attrs(live))
		expect(view.Audio).toBe(false)
		live.PcwFlag_Audio = true
		expect(view.Audio).toBe(true)
		live.PcwFlag_Audio = nil
		expect(view.Audio).toBe(false)
		expect(pcall(function()
			(view :: any).Audio = true
		end)).toBe(false)
	end)

	it("leaves the shipped defaults unchanged under Lune (install is a no-op)", function()
		-- Every built feature ships on (2026-10-18); the override list stays so the pc-watcher shots that
		-- set PcwFlag_<name> keep working (a no-op for the flags that ship on). ServerProfiler is a dev tool.
		-- BaseShapes ships off until the new bases have their meshes (CONTRACT.md §43).
		local SHIPS_OFF = { ServerProfiler = true, BaseShapes = true }
		for _, name in FeatureOverride.FLAGS do
			expect((Config.FEATURES :: any)[name]).toBe(SHIPS_OFF[name] ~= true)
		end
		expect(table.isfrozen(Config.FEATURES)).toBe(true)
		expect(FeatureOverride.install(base) == base).toBe(true)
	end)

	it("lists only real, default-off Config.FEATURES flags", function()
		for _, name in FeatureOverride.FLAGS do
			expect(type((Config.FEATURES :: any)[name])).toBe("boolean")
		end
	end)
end)
